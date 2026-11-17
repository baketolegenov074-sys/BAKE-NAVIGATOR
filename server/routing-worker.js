/**
 * BAKE Navigator routing proxy for Cloudflare Workers.
 *
 * Required Worker secrets:
 *   HEIGIT_API_KEY       HeiGIT/OpenRouteService API key (never put in the APK)
 *   BAKE_ROUTING_TOKEN   Temporary app-to-proxy bearer token
 *
 * POST /route
 *   { "coordinates": [[lon, lat], [lon, lat], ...] }
 *
 * The response is normalized to the OSRM-like shape currently consumed by
 * lib/main.dart. The Flutter client will be switched to this endpoint in a
 * separate, reviewed step.
 *
 * Before public launch, replace the shared app token with per-user auth
 * (for example Firebase ID-token verification) and configure edge rate limits.
 */

const ORS_URL =
  "https://api.heigit.org/openrouteservice/v2/directions/driving-car/geojson";

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "POST, OPTIONS",
      "access-control-allow-headers": "authorization, content-type",
    },
  });
}

function normalizeFeature(feature) {
  const coordinates = feature?.geometry?.coordinates;
  const properties = feature?.properties ?? {};
  if (!Array.isArray(coordinates) || coordinates.length < 2) return null;

  const segments = Array.isArray(properties.segments) ? properties.segments : [];
  let firstStep = true;
  const legs = segments.map((segment) => {
    const steps = Array.isArray(segment.steps) ? segment.steps : [];
    return {
      steps: steps.map((step) => {
        const wayPoints = Array.isArray(step.way_points) ? step.way_points : [];
        const pointIndex = Math.max(
          0,
          Math.min(coordinates.length - 1, Number(wayPoints[0] ?? 0)),
        );
        const location = coordinates[pointIndex];
        const instruction = String(step.instruction ?? "").toLowerCase();
        let modifier = "straight";

        if (/налево|left/.test(instruction)) modifier = "left";
        else if (/направо|right/.test(instruction)) modifier = "right";
        else if (/разворот|развернит|u.?turn/.test(instruction)) modifier = "uturn";
        else if (/кругов|roundabout|rotary/.test(instruction)) modifier = "right";

        let type = "continue";
        if (firstStep) {
          type = "depart";
          firstStep = false;
        }

        return {
          distance: Number(step.distance ?? 0),
          name: String(step.name ?? ""),
          maneuver: {
            location,
            type,
            modifier,
          },
        };
      }),
    };
  });

  const allSteps = legs.flatMap((leg) => leg.steps);
  if (allSteps.length > 0) {
    allSteps[allSteps.length - 1].maneuver.type = "arrive";
  }

  return {
    distance: Number(properties.summary?.distance ?? 0),
    duration: Number(properties.summary?.duration ?? 0),
    geometry: { type: "LineString", coordinates },
    legs,
  };
}

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "access-control-allow-origin": "*",
          "access-control-allow-methods": "POST, OPTIONS",
          "access-control-allow-headers": "authorization, content-type",
          "access-control-max-age": "86400",
        },
      });
    }

    const url = new URL(request.url);
    if (url.pathname !== "/route" || request.method !== "POST") {
      return json({ error: "Not found" }, 404);
    }

    if (!env.HEIGIT_API_KEY || !env.BAKE_ROUTING_TOKEN) {
      return json({ error: "Routing service is not configured" }, 503);
    }

    const auth = request.headers.get("authorization") ?? "";
    if (auth !== `Bearer ${env.BAKE_ROUTING_TOKEN}`) {
      return json({ error: "Unauthorized" }, 401);
    }

    const declaredLength = Number(request.headers.get("content-length") ?? 0);
    if (declaredLength > 12_000) {
      return json({ error: "Request is too large" }, 413);
    }

    let input;
    try {
      input = await request.json();
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    const coordinates = input?.coordinates;
    if (
      !Array.isArray(coordinates) ||
      coordinates.length < 2 ||
      coordinates.length > 7 ||
      !coordinates.every(
        (point) =>
          Array.isArray(point) &&
          point.length === 2 &&
          Number.isFinite(point[0]) &&
          Number.isFinite(point[1]) &&
          point[0] >= -180 &&
          point[0] <= 180 &&
          point[1] >= -90 &&
          point[1] <= 90,
      )
    ) {
      return json({ error: "Coordinates must contain 2 to 7 valid [longitude, latitude] points" }, 400);
    }

    try {
      const upstream = await fetch(ORS_URL, {
        method: "POST",
        headers: {
          authorization: env.HEIGIT_API_KEY,
          "content-type": "application/json",
          accept: "application/geo+json",
        },
        body: JSON.stringify({
          coordinates,
          instructions: true,
          language: "ru",
          geometry: true,
        }),
      });

      const payload = await upstream.json().catch(() => ({}));
      if (!upstream.ok) {
        return json(
          {
            error: "HeiGIT routing request failed",
            upstreamStatus: upstream.status,
            details: payload?.error?.message ?? payload?.error ?? payload?.message ?? null,
          },
          upstream.status === 429 ? 429 : 502,
        );
      }

      const features = Array.isArray(payload.features) ? payload.features : [];
      const routes = features.map(normalizeFeature).filter(Boolean);
      if (routes.length === 0) {
        return json({ code: "NoRoute", routes: [] }, 200);
      }

      return json({ code: "Ok", routes, provider: "HeiGIT OpenRouteService" });
    } catch {
      return json({ error: "Routing provider is temporarily unavailable" }, 502);
    }
  },
};
