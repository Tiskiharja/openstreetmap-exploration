#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass

import folium
import psycopg


@dataclass(frozen=True)
class DbConfig:
    db_name: str = os.getenv("DB_NAME", "osm_demo")
    db_host: str = os.getenv("DB_HOST", "localhost")
    db_port: int = int(os.getenv("DB_PORT", "5433"))
    db_user: str = os.getenv("DB_USER", os.getenv("USER", "postgres"))

    @property
    def connect_kwargs(self) -> dict[str, str | int]:
        kwargs: dict[str, str | int] = {
            "dbname": self.db_name,
            "user": self.db_user,
            "port": self.db_port,
        }
        if self.db_host.strip():
            kwargs["host"] = self.db_host
        return kwargs


def _iter_coords(geometry: dict):
    geom_type = geometry.get("type")
    coords = geometry.get("coordinates", [])
    if geom_type == "Polygon":
        for ring in coords:
            for lon, lat in ring:
                yield lon, lat
    elif geom_type == "MultiPolygon":
        for poly in coords:
            for ring in poly:
                for lon, lat in ring:
                    yield lon, lat


def compute_bounds(features: list[dict]) -> tuple[float, float, float, float] | None:
    if not features:
        return None
    min_lon = float("inf")
    min_lat = float("inf")
    max_lon = float("-inf")
    max_lat = float("-inf")
    for feature in features:
        for lon, lat in _iter_coords(feature["geometry"]):
            min_lon = min(min_lon, lon)
            min_lat = min(min_lat, lat)
            max_lon = max(max_lon, lon)
            max_lat = max(max_lat, lat)
    if min_lon == float("inf"):
        return None
    return min_lon, min_lat, max_lon, max_lat


def fetch_features(conn: psycopg.Connection, country_name: str) -> list[dict]:
    sql = """
        WITH target_country AS (
            SELECT geom
            FROM demo.country_boundary
            WHERE name ILIKE %(country_name)s
            LIMIT 1
        )
        SELECT
            t.z,
            t.x,
            t.y,
            tc.city_name,
            tc.place_type,
            tc.assignment_method,
            ST_AsGeoJSON(ST_Transform(t.geom, 4326)) AS geom_geojson
        FROM demo.tiles_z14 t
        JOIN demo.tile_city_z14 tc USING (z, x, y)
        JOIN target_country c
          ON ST_Covers(c.geom, t.centroid)
        ORDER BY t.x, t.y
    """
    with conn.cursor() as cur:
        cur.execute(sql, {"country_name": country_name})
        rows = cur.fetchall()

    features: list[dict] = []
    for z, x, y, city_name, place_type, assignment_method, geom_geojson in rows:
        features.append(
            {
                "type": "Feature",
                "properties": {
                    "z": z,
                    "x": x,
                    "y": y,
                    "city_name": city_name,
                    "place_type": place_type,
                    "assignment_method": assignment_method,
                },
                "geometry": json.loads(geom_geojson),
            }
        )
    return features


def build_map(
    features: list[dict],
    bounds: tuple[float, float, float, float] | None,
    fill_color: str,
    fill_opacity: float,
) -> folium.Map:
    if bounds is not None:
        min_lon, min_lat, max_lon, max_lat = bounds
        center = [(min_lat + max_lat) / 2.0, (min_lon + max_lon) / 2.0]
    else:
        center = [46.5, 2.2]

    m = folium.Map(location=center, zoom_start=6, tiles="CartoDB positron")
    geojson = {"type": "FeatureCollection", "features": features}

    layer = folium.GeoJson(
        data=geojson,
        style_function=lambda _: {
            "fillColor": fill_color,
            "color": "#111111",
            "fill": True,
            "weight": 0.15,
            "opacity": 0.7,
            "fillOpacity": fill_opacity,
        },
        tooltip=folium.GeoJsonTooltip(
            fields=["city_name", "place_type", "assignment_method", "z", "x", "y"],
            aliases=["Assigned city", "Place type", "Method", "Z", "X", "Y"],
        ),
        name="France tiles",
    )
    layer.add_to(m)
    folium.LayerControl(collapsed=False).add_to(m)

    if bounds is not None:
        min_lon, min_lat, max_lon, max_lat = bounds
        m.fit_bounds([[min_lat, min_lon], [max_lat, max_lon]])

    return m


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render all z14 tiles mapped to France into an interactive HTML map."
    )
    parser.add_argument(
        "--country-name",
        default="France",
        help="Country boundary name to match in demo.country_boundary (default: France).",
    )
    parser.add_argument(
        "--output",
        default="data/france_tiles.html",
        help="Output HTML map path (default: data/france_tiles.html).",
    )
    parser.add_argument(
        "--fill-color",
        default="#1f78b4",
        help="Tile fill color (default: #1f78b4).",
    )
    parser.add_argument(
        "--fill-opacity",
        type=float,
        default=0.45,
        help="Tile fill opacity in [0,1] (default: 0.45).",
    )
    parser.add_argument(
        "--dsn",
        default=None,
        help="Optional PostgreSQL DSN. If omitted, DB_* environment variables are used.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not (0.0 <= args.fill_opacity <= 1.0):
        raise ValueError("--fill-opacity must be between 0 and 1.")

    cfg = DbConfig()
    if args.dsn:
        conn_ctx = psycopg.connect(args.dsn)
    else:
        conn_ctx = psycopg.connect(**cfg.connect_kwargs)

    with conn_ctx as conn:
        features = fetch_features(conn, country_name=args.country_name)
        if not features:
            raise RuntimeError(
                f"No tiles found for country_name={args.country_name!r} in demo.country_boundary/demo.tiles_z14."
            )
        bounds = compute_bounds(features)

    m = build_map(
        features=features,
        bounds=bounds,
        fill_color=args.fill_color,
        fill_opacity=args.fill_opacity,
    )
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    m.save(args.output)
    print(f"Wrote {len(features)} tiles to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
