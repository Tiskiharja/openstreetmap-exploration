#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from dataclasses import dataclass

import folium
import psycopg


CITY_COLORS = {
    "Helsinki": "#e41a1c",
    "Espoo": "#1f78b4",
    "Vantaa": "#33a02c",
}
TARGET_CITIES = tuple(CITY_COLORS.keys())


@dataclass(frozen=True)
class DbConfig:
    db_name: str = os.getenv("DB_NAME", "osm_demo")
    db_host: str = os.getenv("DB_HOST", "")
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


def fetch_features(conn: psycopg.Connection) -> list[dict]:
    sql = """
        WITH target_cities AS (
            SELECT * FROM (VALUES ('Helsinki'), ('Espoo'), ('Vantaa')) AS t(city_name)
        ),
        matched_boundaries AS (
            SELECT
                tc.city_name,
                p.way::geometry(MultiPolygon, 3857) AS geom,
                ROW_NUMBER() OVER (
                    PARTITION BY tc.city_name
                    ORDER BY ST_Area(p.way::geometry) DESC
                ) AS rn
            FROM public.planet_osm_polygon p
            JOIN target_cities tc
              ON (
                  p.name = tc.city_name
                  OR p.tags->'name:fi' = tc.city_name
                  OR p.tags->'name:sv' = tc.city_name
                  OR p.tags->'name:en' = tc.city_name
              )
            WHERE p.boundary = 'administrative'
              AND p.admin_level IN ('7', '8')
        ),
        city_boundaries AS (
            SELECT city_name, geom
            FROM matched_boundaries
            WHERE rn = 1
        )
        SELECT
            t.z,
            t.x,
            t.y,
            b.city_name,
            ST_AsGeoJSON(ST_Transform(t.geom, 4326)) AS geom_geojson
        FROM demo.tiles_z14 t
        JOIN city_boundaries b
          ON ST_Covers(b.geom, t.centroid)
        ORDER BY b.city_name, t.x, t.y
    """
    with conn.cursor() as cur:
        cur.execute(sql)
        rows = cur.fetchall()

    features: list[dict] = []
    for z, x, y, city, geom_geojson in rows:
        features.append(
            {
                "type": "Feature",
                "properties": {
                    "z": z,
                    "x": x,
                    "y": y,
                    "city": city,
                    "color": CITY_COLORS[city],
                },
                "geometry": json.loads(geom_geojson),
            }
        )
    return features


def fetch_loaded_country_name(conn: psycopg.Connection) -> str | None:
    sql = "SELECT name FROM demo.country_boundary LIMIT 1"
    with conn.cursor() as cur:
        cur.execute(sql)
        row = cur.fetchone()
    return row[0] if row and row[0] else None


def build_map(features: list[dict], bounds: tuple[float, float, float, float] | None) -> folium.Map:
    if bounds is not None:
        min_lon, min_lat, max_lon, max_lat = bounds
        center = [(min_lat + max_lat) / 2.0, (min_lon + max_lon) / 2.0]
    else:
        center = [60.22, 24.9]

    m = folium.Map(location=center, zoom_start=10, tiles="CartoDB positron")
    geojson = {"type": "FeatureCollection", "features": features}

    layer = folium.GeoJson(
        data=geojson,
        style_function=lambda feature: {
            "fillColor": feature["properties"]["color"],
            "color": "#111111",
            "fill": True,
            "weight": 0.35,
            "opacity": 0.9,
            "fillOpacity": 0.4,
        },
        tooltip=folium.GeoJsonTooltip(fields=["city", "z", "x", "y"], aliases=["City", "Z", "X", "Y"]),
        name="City tiles",
    )
    layer.add_to(m)
    folium.LayerControl(collapsed=False).add_to(m)

    if bounds is not None:
        min_lon, min_lat, max_lon, max_lat = bounds
        m.fit_bounds([[min_lat, min_lon], [max_lat, max_lon]])

    return m


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render z14 tiles for Helsinki, Espoo and Vantaa with city colors."
    )
    parser.add_argument(
        "--output",
        default="data/helsinki_espoo_vantaa_tiles.html",
        help="Output HTML map path (default: data/helsinki_espoo_vantaa_tiles.html)",
    )
    parser.add_argument(
        "--dsn",
        default=None,
        help="Optional full PostgreSQL DSN. If omitted, DB_* environment variables are used.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    cfg = DbConfig()

    if args.dsn:
        conn_ctx = psycopg.connect(args.dsn)
    else:
        conn_ctx = psycopg.connect(**cfg.connect_kwargs)

    with conn_ctx as conn:
        features = fetch_features(conn)
        if not features:
            country_name = fetch_loaded_country_name(conn)
            country_suffix = f" Loaded country_boundary is '{country_name}'." if country_name else ""
            raise RuntimeError(
                f"No municipality tiles found for {', '.join(TARGET_CITIES)}.{country_suffix}"
                " Make sure Finland data is imported before running this script."
            )
        bounds = compute_bounds(features)

    m = build_map(features, bounds)
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    m.save(args.output)
    print(f"Wrote {len(features)} tiles to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
