#!/usr/bin/env python3
"""Download OSM speed-camera and surveillance objects inside Shymkent.

Coordinates come only from OpenStreetMap. Ways/relations use Overpass' center
as an approximate marker; they must not be treated as exact camera positions.
"""
import json
import re
import sys
import time
from pathlib import Path

import requests

HEADERS = {"User-Agent": "BAKE-Navigator/1.1 (OpenStreetMap camera data import)"}
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
OVERPASS_URLS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "data" / "shymkent_cameras.json"


def overpass(session, query):
    """Try several public Overpass instances with retries for transient errors."""
    errors = []
    retryable_statuses = (429, 500, 502, 503, 504)

    for endpoint in OVERPASS_URLS:
        for attempt in range(3):
            try:
                response = session.post(
                    endpoint,
                    data={"data": query},
                    timeout=240,
                )
                if response.status_code in retryable_statuses:
                    raise requests.HTTPError(
                        f"{response.status_code} from {endpoint}",
                        response=response,
                    )
                response.raise_for_status()
                return response.json()
            except (requests.RequestException, ValueError) as exc:
                errors.append(
                    f"{endpoint} (попытка {attempt + 1}/3): {exc}"
                )
                if attempt < 2:
                    time.sleep(2 ** (attempt + 1))

    details = "\n".join(errors)
    raise RuntimeError(
        "Все серверы Overpass временно недоступны или вернули ошибку. "
        "Данные не сохранены. Подробности:\n" + details
    )


def find_city_area(session):
    """Resolve the mapped administrative boundary; never substitute a bbox."""
    response = session.get(
        NOMINATIM_URL,
        params={
            "q": "Shymkent, Kazakhstan",
            "format": "jsonv2",
            "limit": 50,
            "addressdetails": 1,
            "extratags": 1,
        },
        timeout=40,
    )
    response.raise_for_status()
    results = response.json()

    # Nominatim may expose the administrative boundary as either a relation
    # or a closed way. The old code incorrectly accepted relations only.
    candidates = []
    for item in results:
        osm_type = item.get("osm_type")
        display = str(item.get("display_name", "")).lower()
        name = str(item.get("name", "")).lower()
        if osm_type not in ("relation", "way"):
            continue
        if "shymkent" not in display and name not in ("шымкент", "shymkent"):
            continue
        extra = item.get("extratags") or {}
        if item.get("class") == "boundary" and (
            item.get("type") == "administrative"
            or extra.get("boundary") == "administrative"
        ):
            candidates.append(item)

    if candidates:
        candidates.sort(
            key=lambda item: (
                item.get("osm_type") != "relation",
                item.get("addresstype") not in ("city", "municipality"),
                int(item.get("place_rank", 100)),
            )
        )
        chosen = candidates[0]
        osm_type = chosen["osm_type"]
        osm_id = int(chosen["osm_id"])
        # Overpass area IDs: relation + 3.6bn, closed way + 2.4bn.
        area_id = osm_id + (3_600_000_000 if osm_type == "relation" else 2_400_000_000)
        return osm_type, osm_id, area_id

    # Nominatim's search ranking/tags can vary. Ask Overpass directly for the
    # exact named administrative boundary, preferring Kazakhstan's city level.
    for level_clause in ('["admin_level"="4"]', ""):
        query = f"""
        [out:json][timeout:60];
        relation["boundary"="administrative"]
          ["name"~"^(Shymkent|Шымкент)$",i]{level_clause};
        out tags;
        """
        data = overpass(session, query)
        relations = [
            item for item in data.get("elements", [])
            if item.get("type") == "relation"
            and (item.get("tags") or {}).get("boundary") == "administrative"
            and re.fullmatch(
                r"(Shymkent|Шымкент)",
                (item.get("tags") or {}).get("name", ""),
                flags=re.IGNORECASE,
            )
        ]
        if relations:
            # Prefer admin_level=4 (city of republican significance).
            relations.sort(
                key=lambda item: (item.get("tags", {}).get("admin_level") != "4", item["id"])
            )
            osm_id = int(relations[0]["id"])
            return "relation", osm_id, osm_id + 3_600_000_000

    raise RuntimeError(
        "Не удалось найти точную административную границу Шымкента в OSM "
        "(ни через Nominatim, ни через Overpass). Координаты и примерный "
        "прямоугольник не подставлялись."
    )


def download():
    with requests.Session() as session:
        session.headers.update(HEADERS)
        boundary_type, boundary_id, area_id = find_city_area(session)

        query = f"""
        [out:json][timeout:180];
        area({area_id})->.city;
        (
          nwr["highway"="speed_camera"](area.city);
          nwr["man_made"="surveillance"](area.city);
        );
        out center tags;
        """
        payload = overpass(session, query)

    cameras = []
    for element in payload.get("elements", []):
        if element.get("type") == "node":
            lat, lon = element.get("lat"), element.get("lon")
        else:
            center = element.get("center") or {}
            lat, lon = center.get("lat"), center.get("lon")
        if lat is None or lon is None:
            continue

        tags = element.get("tags") or {}
        cameras.append({
            "osm_id": element.get("id"),
            "osm_type": element.get("type"),
            "latitude": lat,
            "longitude": lon,
            "maxspeed": tags.get("maxspeed"),
            "direction": tags.get("direction"),
            "highway": tags.get("highway"),
            "man_made": tags.get("man_made"),
            "surveillance": tags.get("surveillance"),
            "surveillance_type": tags.get("surveillance:type"),
            "camera_type": tags.get("camera:type"),
            "name": tags.get("name"),
            "tags": tags,
        })

    if not cameras:
        raise RuntimeError(
            "Overpass нашёл границу Шымкента, но не нашёл объектов "
            "highway=speed_camera или man_made=surveillance. JSON не перезаписан."
        )

    result = {
        "city": "Shymkent",
        "country": "Kazakhstan",
        "source": "OpenStreetMap",
        "osm_boundary_type": boundary_type,
        "osm_boundary_id": boundary_id,
        "downloaded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "count": len(cameras),
        "speed_camera_count": sum(x.get("highway") == "speed_camera" for x in cameras),
        "surveillance_count": sum(x.get("man_made") == "surveillance" for x in cameras),
        "cameras": cameras,
    }
    if boundary_type == "relation":
        result["osm_relation_id"] = boundary_id

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Граница OSM: {boundary_type} {boundary_id}")
    print(f"Всего объектов OSM: {len(cameras)}")
    print(f"Скоростные камеры: {result['speed_camera_count']}")
    print(f"Объекты surveillance: {result['surveillance_count']}")
    print(f"Файл: {OUTPUT}")
    print("Важно: surveillance может быть обычным видеонаблюдением, не радаром.")


if __name__ == "__main__":
    try:
        download()
    except requests.RequestException as exc:
        print(f"Ошибка сети/API: {exc}", file=sys.stderr)
        raise SystemExit(1)
    except (ValueError, RuntimeError) as exc:
        print(f"Ошибка данных: {exc}", file=sys.stderr)
        raise SystemExit(1)
