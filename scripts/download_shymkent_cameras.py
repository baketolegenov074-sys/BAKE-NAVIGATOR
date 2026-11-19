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
    """Try several public Overpass instances with retries for transient 5xx/429 errors."""
    errors = []
    for endpoint in OVERPASS_URLS:
        for attempt in range(3):
            try:
                response = session.post(
                    endpoint,
                    data={"data": query},
                    timeout=240,
                )
                if response.status_code in (429, 500, 502, 503, 504):
                    raise requests.HTTPError(
                        f"{response.status_code} from {endpoint}",
                        response=response,
                    )
                response.raise_for_status()
                return response.json()
            except (requests.RequestException, ValueError) as exc:
                errors.append(f"{endpoint} (попытка {attempt + 1}/3): {exc}")
                if attempt < 2:
                    time.sleep(2 ** (attempt + 1))
    details = "\\n".join(errors)
    raise RuntimeError(
        "Все серверы Overpass временно недоступны или вернули ошибку. "
        "Данные не сохранены. Подробности:\\n" + details
    )

