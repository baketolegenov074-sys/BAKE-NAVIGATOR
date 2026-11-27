#!/usr/bin/env python3
"""Resolve the OSM administrative polygon for Shymkent (city only)."""
# Boundary-only workflow trigger: keep this pipeline isolated from app builds.
import json
import urllib.parse
import urllib.request
from pathlib import Path

QUERY = urllib.parse.urlencode({
    "q": "Shymkent, Kazakhstan",
    "format": "jsonv2",
    "polygon_geojson": 1,
    "addressdetails": 1,
    "extratags": 1,
    "limit": 10,
})
URL = "https://nominatim.openstreetmap.org/search?" + QUERY
request = urllib.request.Request(
    URL,
    headers={"User-Agent": "BAKE-Navigator-offline-map/1.0 (OSM boundary extraction)"},
)
with urllib.request.urlopen(request, timeout=60) as response:
    results = json.load(response)

matches = []
for item in results:
    tags = item.get("extratags") or {}
    name = (item.get("name") or "").strip().casefold()
    if item.get("osm_type") != "relation":
        continue
    if tags.get("boundary") != "administrative":
        continue
    if tags.get("place") not in (None, "", "city"):
        continue
    if name not in {"shymkent", "шимкент"}:
        continue
    if not item.get("geojson"):
        continue
    south, north = float(item["boundingbox"][0]), float(item["boundingbox"][1])
    west, east = float(item["boundingbox"][2]), float(item["boundingbox"][3])
    # Reject the wider Turkestan Region or unrelated search results.
    if not (42.0 <= south <= 42.7 and 42.0 <= north <= 43.0
            and 69.0 <= west <= 69.8 and 69.4 <= east <= 70.2):
        continue
    matches.append(item)

if len(matches) != 1:
    summary = [
        {
            "osm_type": x.get("osm_type"),
            "osm_id": x.get("osm_id"),
            "name": x.get("name"),
            "admin_level": (x.get("extratags") or {}).get("admin_level"),
            "bbox": x.get("boundingbox"),
        }
        for x in results
    ]
    raise SystemExit(
        "Expected exactly one Shymkent city administrative relation; "
        f"found {len(matches)}. Nominatim results: {json.dumps(summary, ensure_ascii=False)}"
    )

city = matches[0]
feature = {
    "type": "Feature",
    "properties": {
        "name": "Shymkent",
        "osm_type": city["osm_type"],
        "osm_id": city["osm_id"],
        "admin_level": (city.get("extratags") or {}).get("admin_level", ""),
        "source": "© OpenStreetMap contributors",
    },
    "geometry": city["geojson"],
}
geometry_type = feature["geometry"].get("type")
if geometry_type not in {"Polygon", "MultiPolygon"}:
    raise SystemExit(f"Unexpected administrative geometry: {geometry_type}")

Path("shymkent-city-boundary.geojson").write_text(
    json.dumps({"type": "FeatureCollection", "features": [feature]}, ensure_ascii=False),
    encoding="utf-8",
)
print(
    "Resolved Shymkent city boundary: "
    f"OSM relation {city['osm_id']}, admin_level="
    f"{feature['properties']['admin_level'] or 'not supplied'}, "
    f"geometry={geometry_type}, bbox={city['boundingbox']}"
)
