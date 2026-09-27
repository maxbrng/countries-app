#!/usr/bin/env python3
"""Build the bundled countries.geojson from a Natural Earth Admin 0 shapefile.

Source
------
Natural Earth 1:10m Cultural Vectors, Admin 0 - Countries, version 5.1.1:

    https://www.naturalearthdata.com/downloads/10m-cultural-vectors/10m-admin-0-countries/

Natural Earth is public domain: "No permission is needed to use Natural Earth.
Crediting the authors is unnecessary." The app credits it anyway, in Settings.

Why this script exists
----------------------
The raw 10m data is 548,471 vertices and about 25 MB as GeoJSON, which is far more
than a phone screen can show and far more than the app should parse at launch. The
shipped file is therefore simplified here, at build time, so the app never pays for
it. Simplification runs in the same normalized Web Mercator space the renderer draws
in, so the tolerance means what it says: a tolerance of 3e-5 moves no point further
than 3e-5 of the world's width, which stays under one device pixel up to about 13x
zoom.

Only the properties the app actually reads are kept. The raw data carries 169 columns
per feature, around 925 KB of payload for a handful of values.

Usage
-----
    python3 Tools/build_countries_geojson.py <path to ne_10m_admin_0_countries.shp>

Writes Countries/Countries/Resources/Assets/countries.geojson.
"""

import json
import math
import os
import struct
import sys

# Simplification tolerance, in normalized world units (0...1 across the whole map).
# 6e-5 is about 2.4 km on the ground at the equator, and stays under one device pixel
# up to roughly 6x zoom.
#
# This is the one knob worth turning. 3e-5 gives 217,546 vertices and a 4.78 MiB file,
# 1.9e-5 gives 276,000 and 5.98 MiB. The value below was chosen so the shipped file
# stays *smaller* than the 1:50m file it replaces while carrying 1.45 times its detail:
# every vertex is drawn on every frame, and a detail step that costs frame rate is not
# worth having.
TOLERANCE = 6.0e-5

# Coordinate precision in the written file. Six decimal places is about 11 cm, four
# orders of magnitude finer than the simplification, and it cuts the file roughly in
# half against full double precision.
COORDINATE_PRECISION = 6

# Properties copied into the output. The first four are what the loader resolves
# countries by; the rest are carried for label placement.
KEPT_PROPERTIES = [
    "iso_a2", "iso_a3", "admin", "name",
    "name_de", "abbrev", "labelrank", "label_x", "label_y", "min_label", "max_label",
    "continent",
]

# Numeric properties, parsed out of the shapefile's text columns.
NUMERIC_PROPERTIES = {"labelrank", "label_x", "label_y", "min_label", "max_label"}

# Web Mercator is undefined at the poles and is cut off at this latitude, the same
# value the renderer's projection uses.
MAX_MERCATOR_LATITUDE = 85.05112878

# Shapefile shape type for a polygon record.
SHAPE_TYPE_POLYGON = 5

# A ring needs at least three distinct corners plus the repeated closing point.
MINIMUM_RING_POINTS = 4

OUTPUT_PATH = os.path.join("Countries", "Countries", "Resources", "Assets", "countries.geojson")


def read_shapefile_polygons(path):
    """Yields one list of rings per record, in file order.

    Only polygon records are understood; anything else yields an empty list, which
    keeps the record aligned with its attribute row.
    """
    data = open(path, "rb").read()
    offset = 100  # File header.
    records = []

    while offset < len(data):
        _, content_length = struct.unpack(">ii", data[offset:offset + 8])
        offset += 8
        end = offset + content_length * 2
        shape_type, = struct.unpack("<i", data[offset:offset + 4])
        rings = []

        if shape_type == SHAPE_TYPE_POLYGON:
            cursor = offset + 4 + 32  # Shape type plus the bounding box.
            part_count, point_count = struct.unpack("<ii", data[cursor:cursor + 8])
            cursor += 8
            parts = struct.unpack("<%di" % part_count, data[cursor:cursor + 4 * part_count])
            cursor += 4 * part_count
            flat = struct.unpack("<%dd" % (2 * point_count), data[cursor:cursor + 16 * point_count])
            points = [(flat[2 * i], flat[2 * i + 1]) for i in range(point_count)]

            for index, start in enumerate(parts):
                stop = parts[index + 1] if index + 1 < part_count else point_count
                rings.append(points[start:stop])

        records.append(rings)
        offset = end

    return records


def read_dbf(path):
    """Reads the attribute table as a list of lowercase-keyed dicts."""
    data = open(path, "rb").read()
    record_count, header_length, record_length = struct.unpack("<IHH", data[4:12])

    fields = []
    cursor = 32
    while data[cursor] != 0x0D:
        name = data[cursor:cursor + 11].split(b"\x00")[0].decode("latin-1").lower()
        fields.append((name, data[cursor + 16]))
        cursor += 32

    rows = []
    for index in range(record_count):
        raw = data[header_length + index * record_length:header_length + (index + 1) * record_length]
        cursor = 1  # Deletion flag.
        row = {}
        for name, length in fields:
            # This table pads with NUL bytes, not with spaces, so plain strip() is not enough.
            value = raw[cursor:cursor + length].decode("utf-8", "replace")
            row[name] = value.replace("\x00", "").strip()
            cursor += length
        rows.append(row)

    return rows


def project(longitude, latitude):
    """Projects to normalized Web Mercator, matching FlatMapModels' projection."""
    latitude = min(max(latitude, -MAX_MERCATOR_LATITUDE), MAX_MERCATOR_LATITUDE)
    radians = math.radians(latitude)
    x = (longitude + 180.0) / 360.0
    y = (1.0 - math.log(math.tan(math.pi / 4 + radians / 2)) / math.pi) / 2.0
    return x, y


def simplified_indices(points, tolerance):
    """Ramer-Douglas-Peucker, returning the indices of the points that survive."""
    count = len(points)
    if count <= 3 or tolerance <= 0:
        return list(range(count))

    squared_tolerance = tolerance * tolerance
    keep = [False] * count
    keep[0] = keep[count - 1] = True
    stack = [(0, count - 1)]

    while stack:
        first, last = stack.pop()
        if last <= first + 1:
            continue

        first_x, first_y = points[first]
        last_x, last_y = points[last]
        span_x = last_x - first_x
        span_y = last_y - first_y
        span_squared = span_x * span_x + span_y * span_y

        worst = 0.0
        worst_index = first
        for index in range(first + 1, last):
            x, y = points[index]
            if span_squared > 0:
                cross = span_x * (first_y - y) - span_y * (first_x - x)
                distance = (cross * cross) / span_squared
            else:
                distance = (x - first_x) ** 2 + (y - first_y) ** 2
            if distance > worst:
                worst = distance
                worst_index = index

        if worst > squared_tolerance:
            keep[worst_index] = True
            stack.append((first, worst_index))
            stack.append((worst_index, last))

    return [index for index in range(count) if keep[index]]


def shoelace(ring):
    """Twice the signed area of a ring; negative means clockwise."""
    total = 0.0
    for index in range(len(ring) - 1):
        total += ring[index][0] * ring[index + 1][1] - ring[index + 1][0] * ring[index][1]
    return total


def alpha2(attributes):
    """The feature's ISO 3166-1 alpha-2 code, or None.

    Natural Earth parks disputed and de-facto cases in `iso_a2`: France and Norway
    carry "-99", Taiwan carries "CN-TW". The `_eh` column holds the plain code.
    """
    for key in ("iso_a2", "iso_a2_eh"):
        value = (attributes.get(key) or "").strip()
        if len(value) == 2 and value != "-99":
            return value
    return None


def simplify_feature(rings, tolerance):
    """Simplifies one record's rings and groups them into polygons with holes.

    - Returns: `(geometry, vertex_count)`, or `(None, 0)` if nothing survives.
    """
    polygons = []
    vertex_count = 0

    for ring in rings:
        closed = ring if ring[0] == ring[-1] else ring + [ring[0]]
        projected = [project(x, y) for x, y in closed]
        indices = simplified_indices(projected, tolerance)

        if len(indices) < MINIMUM_RING_POINTS:
            # The whole ring is smaller than the tolerance. Dropping it would delete the
            # country: Vatican City, Monaco and San Marino are each a single such ring.
            # They are kept unsimplified instead, which costs almost nothing precisely
            # because they are that small.
            if len(closed) < MINIMUM_RING_POINTS:
                continue
            indices = list(range(len(closed)))

        simplified = [[round(closed[i][0], COORDINATE_PRECISION),
                       round(closed[i][1], COORDINATE_PRECISION)] for i in indices]
        vertex_count += len(simplified)

        # In a shapefile an outer ring runs clockwise and its holes run the other way,
        # and a hole always follows the ring it belongs to.
        if shoelace(simplified) < 0 or not polygons:
            polygons.append([simplified])
        else:
            polygons[-1].append(simplified)

    if not polygons:
        return None, 0

    if len(polygons) == 1:
        return {"type": "Polygon", "coordinates": polygons[0]}, vertex_count

    return {"type": "MultiPolygon", "coordinates": polygons}, vertex_count


def properties_of(attributes, code):
    """The trimmed property bag written for one feature."""
    properties = {"iso_a2": code}

    for key in KEPT_PROPERTIES:
        if key == "iso_a2":
            continue
        value = attributes.get(key)
        if value in (None, "", "-99"):
            continue
        if key in NUMERIC_PROPERTIES:
            try:
                value = float(value)
            except ValueError:
                continue
        properties[key] = value

    return properties


def build(shapefile_path, tolerance=TOLERANCE):
    """Builds the feature collection. Returns `(collection, vertex_count)`."""
    base = os.path.splitext(shapefile_path)[0]
    records = read_shapefile_polygons(shapefile_path)
    rows = read_dbf(base + ".dbf")

    features = []
    vertex_total = 0

    for rings, attributes in zip(records, rows):
        if not rings:
            continue

        code = alpha2(attributes)
        if code is None:
            continue

        geometry, vertex_count = simplify_feature(rings, tolerance)
        if geometry is None:
            continue

        vertex_total += vertex_count
        features.append({
            "type": "Feature",
            "properties": properties_of(attributes, code),
            "geometry": geometry,
        })

    return {"type": "FeatureCollection", "features": features}, vertex_total


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1

    collection, vertex_total = build(sys.argv[1])

    with open(OUTPUT_PATH, "w") as handle:
        json.dump(collection, handle, separators=(",", ":"))

    size = os.path.getsize(OUTPUT_PATH)
    print("features: %d" % len(collection["features"]))
    print("vertices: %d" % vertex_total)
    print("written:  %s (%.2f MiB)" % (OUTPUT_PATH, size / 1048576))
    return 0


if __name__ == "__main__":
    sys.exit(main())
