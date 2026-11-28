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
    "loc_name",
    "old_name",
    "alt_name:ru",
    "alt_name:kk",
    "name:latin",
    "int_name",
    "official_name:ru",
    "official_name:kk",
    "brand:ru",
)
ADDRESS_KEYS = (
    "addr:street",
    "addr:place",
    "addr:housenumber",
    "addr:suburb",
    "addr:district",
    "addr:city",
    "addr:postcode",
    "addr:full",
    "ref",
)

CATEGORY_KEYS = (
    "amenity", "shop", "healthcare", "healthcare:speciality", "speciality",
    "tourism", "leisure", "office", "landuse", "building",
    "public_transport", "railway", "natural", "historic",
)

CATEGORY_LABELS = {
    "school": ["школа", "мектеп", "school"],
    "university": ["университет", "вуз"],
    "hospital": ["больница", "медицинский центр", "кардиология"],
    "clinic": ["клиника", "медицинский центр", "кардиология"],
    "doctors": ["врач", "поликлиника", "кардиология"],
    "marketplace": ["рынок", "базар"],
    "mall": ["торговый центр", "молл", "mall"],
    "department_store": ["универмаг", "торговый центр"],
    "supermarket": ["супермаркет", "магазин"],
    "park": ["парк"],
    "garden": ["сад", "парк"],
    "nature_reserve": ["заповедник", "парк"],
    "museum": ["музей"],
    "attraction": ["достопримечательность"],
    "bus_station": ["автовокзал", "автобусная станция"],
    "pharmacy": ["аптека"],
    "bank": ["банк"],
    "fuel": ["азс", "заправка"],
}


def category_terms(properties: dict[str, Any]) -> list[str]:
    terms: list[str] = []
    for key in CATEGORY_KEYS:
        raw = properties.get(key)
        if raw is None:
            continue
        value = str(raw).strip().lower()
        if not value:
            continue
        terms.append(value.replace("_", " "))
        terms.extend(CATEGORY_LABELS.get(value, []))
    speciality = str(
        properties.get("healthcare:speciality")
        or properties.get("speciality")
        or ""
    ).lower()
    if "cardio" in speciality or "кардио" in speciality:
        terms.extend(["кардиология", "кардиолог", "кардиологический центр"])
    return list(dict.fromkeys(term for term in terms if term))


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


def _valid_point(value: Any) -> tuple[float, float] | None:
    if not isinstance(value, (list, tuple)) or len(value) < 2:
        return None
    if not isinstance(value[0], (int, float)) or not isinstance(value[1], (int, float)):
        return None
    lon, lat = float(value[0]), float(value[1])
    if not (math.isfinite(lon) and math.isfinite(lat)):
        return None
    return lon, lat


def _line_midpoint(line: Any) -> tuple[float, float] | None:
    if not isinstance(line, (list, tuple)):
        return None
    points = [point for point in (_valid_point(value) for value in line) if point]
    if len(points) < 2:
        return points[0] if points else None
    mean_lat = sum(point[1] for point in points) / len(points)
    x_scale = max(0.01, math.cos(math.radians(mean_lat)))
    lengths = [
        math.hypot((b[0] - a[0]) * x_scale, b[1] - a[1])
        for a, b in zip(points, points[1:])
    ]
    total = sum(lengths)
    if total <= 1e-15:
        return points[0]
    target = total / 2
    travelled = 0.0
    for a, b, length in zip(points, points[1:], lengths):
        if travelled + length >= target and length > 0:
            fraction = (target - travelled) / length
            return (
                a[0] + (b[0] - a[0]) * fraction,
                a[1] + (b[1] - a[1]) * fraction,
            )
        travelled += length
    return points[-1]


def _polygon_centroid(polygon: Any) -> tuple[float, float, float] | None:
    if not isinstance(polygon, (list, tuple)) or not polygon:
        return None
    ring = polygon[0]  # outer ring; holes do not affect the representative point
    if not isinstance(ring, (list, tuple)):
        return None
    points = [point for point in (_valid_point(value) for value in ring) if point]
    if len(points) > 1 and points[0] == points[-1]:
        points.pop()
    if len(points) < 3:
        return None
    cross_sum = 0.0
    cx_sum = 0.0
    cy_sum = 0.0
    for a, b in zip(points, points[1:] + points[:1]):
        cross = a[0] * b[1] - b[0] * a[1]
        cross_sum += cross
        cx_sum += (a[0] + b[0]) * cross
        cy_sum += (a[1] + b[1]) * cross
    if abs(cross_sum) <= 1e-15:
        return None
    lon = cx_sum / (3.0 * cross_sum)
    lat = cy_sum / (3.0 * cross_sum)
    return lon, lat, abs(cross_sum) / 2.0


def feature_point(feature: dict[str, Any]) -> tuple[float, float] | None:
    geometry = feature.get("geometry") or {}
    if not isinstance(geometry, dict):
        return None
    geometry_type = geometry.get("type")
    coordinates = geometry.get("coordinates")
    if geometry_type == "Point":
        return _valid_point(coordinates)
    if geometry_type == "LineString":
        return _line_midpoint(coordinates)
    if geometry_type == "MultiLineString":
        lines = coordinates if isinstance(coordinates, (list, tuple)) else []
        midpoint_candidates = [
            (_line_midpoint(line), line) for line in lines
        ]
        best: tuple[float, float] | None = None
        best_length = -1.0
        for midpoint, line in midpoint_candidates:
            if midpoint is None:
                continue
            points = [point for point in (_valid_point(value) for value in line) if point]
            mean_lat = sum(point[1] for point in points) / len(points)
            x_scale = max(0.01, math.cos(math.radians(mean_lat)))
            length = sum(
                math.hypot((b[0] - a[0]) * x_scale, b[1] - a[1])
                for a, b in zip(points, points[1:])
            )
            if length > best_length:
                best, best_length = midpoint, length
        return best
    if geometry_type == "Polygon":
        centroid = _polygon_centroid(coordinates)
        return (centroid[0], centroid[1]) if centroid else None
    if geometry_type == "MultiPolygon":
        polygons = coordinates if isinstance(coordinates, (list, tuple)) else []
        centroids = [
            centroid for centroid in (_polygon_centroid(polygon) for polygon in polygons)
            if centroid is not None
        ]
        if not centroids:
            return None
        largest = max(centroids, key=lambda item: item[2])
        return largest[0], largest[1]
    return None


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


def fold_search_text(value: str) -> str:
    """Mirror _foldOfflineAddressText in Dart; precompute once at build time."""
    text = value.lower().replace("ё", "е")
    for source, target in {
        "ә": "а", "ғ": "г", "қ": "к", "ң": "н",
        "ө": "о", "ұ": "у", "ү": "у", "һ": "х", "і": "и",
    }.items():
        text = text.replace(source, target)
    for source, target in {
        "shch": "щ", "zh": "ж", "ch": "ч", "sh": "ш",
        "kh": "х", "gh": "г", "ng": "н", "yo": "е",
        "yu": "ю", "ya": "я", "ts": "ц",
    }.items():
        text = text.replace(source, target)
    latin = {
        "a": "а", "b": "б", "c": "к", "d": "д", "e": "е",
        "f": "ф", "g": "г", "h": "х", "i": "и", "j": "ж",
        "k": "к", "l": "л", "m": "м", "n": "н", "o": "о",
        "p": "п", "q": "к", "r": "р", "s": "с", "t": "т",
        "u": "у", "v": "в", "w": "в", "x": "кс", "y": "ы",
        "z": "з",
    }
    text = "".join(latin.get(char, char) for char in text)
    text = text.replace("малл", "молл")
    import re
    text = re.sub(r"[^0-9а-я]+", " ", text)
    return re.sub(r"\\s+", " ", text).strip()


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
    district = str(
        properties.get("addr:suburb")
        or properties.get("addr:district")
        or ""
    ).strip()
    amenity = str(properties.get("amenity") or "").strip().lower()
    entrance = str(properties.get("entrance") or "").strip().lower()
    reference = str(properties.get("ref") or "").strip()
    categories = category_terms(properties)
    # Entrance nodes are useful only when their own address/name can identify
    # the building. This preserves the entrance coordinate instead of replacing
    # it with the building polygon centroid.
    is_addressed_entrance = bool(entrance and (house or street or district or names))
    if not names and not house and not categories and not is_addressed_entrance:
        return None
    # A house number without a street or district is not a usable address.
    # Excluding it prevents searches such as "5" from pointing to an
    # arbitrary building elsewhere in the city.
    if house and not street and not district:
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
    if not primary_name and amenity == "school" and reference:
        primary_name = f"Школа №{reference}"
    elif not primary_name and categories:
        primary_name = next(
            (term for term in categories if any("\u0400" <= char <= "\u04ff" for char in term)),
            categories[0],
        ).capitalize()

    if house and street:
        # An address must be displayed from its address tags, not a nearby
        # business brand/operator name attached to the same OSM feature.
        label = f"{street}, {house}"
    elif house and district:
        label = f"{district}, {house}"
    elif primary_name:
        label = primary_name
        if street and street != primary_name:
            label += f", {street}"
        if district and district not in label:
            label += f", {district}"
        if house:
            label += f", {house}"
    else:
        label = f"{place or street or district or 'Дом'}, {house}".strip(", ")

    if is_addressed_entrance:
        kind = "entrance"
        if not primary_name:
            primary_name = "Вход"
    elif house:
        kind = "address"
    elif properties.get("highway"):
        kind = "street"
    elif categories:
        kind = "poi"
    else:
        kind = "place"

    aliases = list(names)
    aliases.extend(categories)
    if is_addressed_entrance:
        aliases.extend(["вход", "подъезд", "entrance", "вход в здание"])
    if district:
        aliases.append(district)
    if amenity == "school":
        aliases.extend(["школа", "мектеп", "school"])
        if reference:
            aliases.extend([
                reference,
                f"школа {reference}",
                f"школа №{reference}",
                f"мектеп {reference}",
            ])
    for key in ADDRESS_KEYS:
        raw = properties.get(key)
        if raw is not None:
            aliases.extend(
                part.strip() for part in str(raw).split(";") if part.strip()
            )
    aliases = list(dict.fromkeys(aliases))
    search_text = " ".join([label, *aliases, *values_for(properties, CATEGORY_KEYS), reference])

    return {
        "label": label,
        "name": primary_name,
        "street": street,
        "house": house,
        "district": district,
        "kind": kind,
        "lat": round(lat, 7),
        "lon": round(lon, 7),
        "search": search_text,
        "search_folded": fold_search_text(search_text),
        "name_folded": fold_search_text(primary_name),
        "street_folded": fold_search_text(street),
        "house_folded": fold_search_text(house),
        "district_folded": fold_search_text(district),
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
