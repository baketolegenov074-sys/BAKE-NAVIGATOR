#!/usr/bin/env python3
"""Download mapped speed cameras and surveillance objects inside Shymkent.

Usage:
    python -m pip install requests
    python scripts/download_shymkent_cameras.py

The script never invents coordinates. For OSM ways/relations it stores the
Overpass bounding-box center and labels the object type; the app treats those
centers as approximate map markers, not voice-alert coordinates.
"""
import json
import sys
import time
from pathlib import Path

import requests

HEADERS = {
    "User-Agent": "BAKE-Navigator/1.0 (OpenStreetMap camera data import)"
}
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
OUTPUT = Path(__file__).resolve().parents[1] / "assets" / "data" / "shymkent_cameras.json"


def find_city_relation(session):
    response = session.get(
        NOMINATIM_URL,
        params={
            "q": "Shymkent, Kazakhstan",
            "format": "jsonv2",
            "limit": 20,
            "addressdetails": 1,
        },
        timeout=30,
    )
    response.raise_for_status()
    results = response.json()

    for item in results:
        if item.get("osm_type") == "relation":
            return int(item["osm_id"])

    raise RuntimeError(
        "Nominatim не вернул OSM relation для Шымкента. "
        "Не подставляю приблизительную границу; проверьте результат вручную."
    )


def download():
    with requests.Session() as session:
        session.headers.update(HEADERS)
        relation_id = find_city_relation(session)
        area_id = relation_id + 3_600_000_000

        query = f"""
        [out:json][timeout:180];
        area({area_id})->.city;
        (
          nwr["highway"="speed_camera"](area.city);
          nwr["man_made"="surveillance"](area.city);
        );
        out center tags;
        """

        response = session.post(
            OVERPASS_URL,
            data={"data": query},
            timeout=240,
        )
        response.raise_for_status()
        payload = response.json()

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

    result = {
        "city": "Shymkent",
        "country": "Kazakhstan",
        "source": "OpenStreetMap",
        "osm_relation_id": relation_id,
        "downloaded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "count": len(cameras),
        "cameras": cameras,
    }

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Сохранено объектов OSM: {len(cameras)}")
    print(f"Файл: {OUTPUT}")
    print("Проверьте записи: surveillance может быть обычным видеонаблюдением.")


if __name__ == "__main__":
    try:
        download()
    except requests.RequestException as exc:
        print(f"Ошибка сети/API: {exc}", file=sys.stderr)
        raise SystemExit(1)
    except (ValueError, RuntimeError) as exc:
        print(f"Ошибка данных: {exc}", file=sys.stderr)
        raise SystemExit(1)
