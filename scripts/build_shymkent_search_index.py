#!/usr/bin/env python3
"""Build a compact offline Shymkent address and POI index from OSM GeoJSONSeq."""

from __future__ import annotations

import argparse
import gzip
import json
import math
from pathlib import Path
from typing import Any, Iterator

# Keep in sync with the Shymkent map/routing coverage used by BAKE Navigator.
WEST, SOUTH, EAST, NORTH = 69.35, 42.12, 69.90, 42.53

NAME_KEYS = (
    "name",
    "name:ru",
    "name:kk",
    "name:en",
    "official_name",
    "short_name",
    "alt_name",
    "brand",
    "operator",
)
ADDRESS_KEYS = (
    "addr:street",
    "addr:place",
    "addr:housenumber",
    "addr:suburb",
    "addr:district",
    "addr:city",
)


def coordinate_pairs(value: Any) -> Iterator[tuple[float, float]]:
    """Yield (lon, lat) pairs from any GeoJSON geometry coordinate nesting."""
    if (
        isinstance(value, (list, tuple))
        and len(value) >= 2
        and isinstance(value[0], (int, float))
        and isinstance(value[1], (int, float))
    ):
        yield float(value[0]), float(value[1])
        return
    if isinstance(value, (list, tuple)):
        for child in value:
            yield from coordinate_pairs(child)


def feature_point(feature: dict[str, Any]) -> tuple[float, float] | None:
    geometry = feature.get("geometry") or {}
    coordinates = geometry.get("coordinates")
    if geometry.get("type") == "Point":
        pairs = list(coordinate_pairs(coordinates))
        if not pairs:
            return None
        return pairs[0]
    pairs = list(coordinate_pairs(coordinates))
    if not pairs:
        return None
    # For a building polygon or a named road, the average of its vertices is
    # a stable searchable point and avoids adding a geometry dependency.
    lon = sum(point[0] for point in pairs) / len(pairs)
    lat = sum(point[1] for point in pairs) / len(pairs)
    return lon, lat


def values_for(properties: dict[str, Any], keys: tuple[str, ...]) -> list[str]:
    values: list[str] = []
    for key in keys:
        raw = properties.get(key)
        if raw is None:
            continue
        for value in str(raw).split(";"):
            value = value.strip()
            if value and value not in values:
                values.append(value)
    return values


def make_record(feature: dict[str, Any]) -> dict[str, Any] | None:
    properties = feature.get("properties") or {}
    if not isinstance(properties, dict):
        return None

    names = values_for(properties, NAME_KEYS)
    street = str(
        properties.get("addr:street")
        or properties.get("addr:place")
        or ""
    ).strip()
    house = str(properties.get("addr:housenumber") or "").strip()
    place = str(properties.get("addr:place") or "").strip()
    if not names and not house:
        return None

    point = feature_point(feature)
    if point is None:
        return None
    lon, lat = point
    if not (WEST <= lon <= EAST and SOUTH <= lat <= NORTH):
        return None
    if not (math.isfinite(lat) and math.isfinite(lon)):
        return None

    primary_name = names[0] if names else ""
    if house and street:
        label = f"{street}, {house}"
        if primary_name and primary_name != street:
            label = f"{primary_name}, {street}, {house}"
    elif primary_name:
        label = primary_name
        if street and street != primary_name:
            label += f", {street}"
        if house:
            label += f", {house}"
    else:
        label = f"{place or street or 'Дом'}, {house}".strip(", ")

    if house:
        kind = "address"
    elif properties.get("highway"):
        kind = "street"
    elif any(
        key in properties
        for key in ("amenity", "shop", "tourism", "leisure", "office", "healthcare")
    ):
        kind = "poi"
    else:
        kind = "place"

    aliases = list(names)
    for key in ADDRESS_KEYS:
        raw = properties.get(key)
        if raw is not None:
            aliases.extend(
                part.strip() for part in str(raw).split(";") if part.strip()
            )
    aliases = list(dict.fromkeys(aliases))
    search_text = " ".join([label, *aliases])

    return {
        "label": label,
        "name": primary_name,
        "street": street,
        "house": house,
        "kind": kind,
        "lat": round(lat, 7),
        "lon": round(lon, 7),
        "search": search_text,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    if not args.input.is_file() or args.input.stat().st_size == 0:
        raise SystemExit(f"Missing or empty OSM GeoJSONSeq: {args.input}")

    records: list[dict[str, Any]] = []
    seen: set[tuple[str, str, str, int, int]] = set()
    with args.input.open("r", encoding="utf-8") as source:
        for line_number, line in enumerate(source, start=1):
            line = line.strip().lstrip("\x1e").strip()
            if not line:
                continue
            try:
                feature = json.loads(line)
            except json.JSONDecodeError as error:
                raise SystemExit(
                    f"Invalid GeoJSONSeq at line {line_number}: {error}"
                ) from error
            if not isinstance(feature, dict):
                continue
            record = make_record(feature)
            if record is None:
                continue
            key = (
                record["label"].casefold(),
                record["street"].casefold(),
                record["house"].casefold(),
                round(record["lat"] * 100000),
                round(record["lon"] * 100000),
            )
            if key in seen:
                continue
            seen.add(key)
            records.append(record)

    if not records:
        raise SystemExit(
            "The Shymkent OSM extract contains no named places or address records; "
            "refusing to package an empty offline search index."
        )

    records.sort(key=lambda item: (item["kind"], item["label"].casefold()))
    payload = json.dumps(
        {"version": 1, "source": "OpenStreetMap", "items": records},
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as target:
        with gzip.GzipFile(fileobj=target, mode="wb", mtime=0, compresslevel=9) as zipped:
            zipped.write(payload)

    print(
        f"Built offline Shymkent search index: {len(records)} records, "
        f"{args.output.stat().st_size} compressed bytes"
    )


if __name__ == "__main__":
    main()
