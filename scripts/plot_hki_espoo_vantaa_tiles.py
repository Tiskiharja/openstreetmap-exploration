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


@dataclass(frozen=True)
class DbConfig:
    db_name: str = os.getenv("DB_NAME", "osm_demo")
    db_host: str = os.getenv("DB_HOST", "localhost")
    db_port: int = int(os.getenv("DB_PORT", "5433"))
    db_user: str = os.getenv("DB_USER", "postgres")

    @property
    def dsn(self) -> str:
        return f"postgresql://{self.db_user}@{self.db_host}:{self.db_port}/{self.db_name}"


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
        WITH city_boundaries AS (
            SELECT
                name AS city_name,
                way::geometry(MultiPolygon, 3857) AS geom
            FROM public.planet_osm_polygon
            WHERE boundary = 'administrative'
              AND admin_level = '8'
              AND name IN ('Helsinki', 'Espoo', 'Vantaa')
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
    dsn = args.dsn or DbConfig().dsn

    with psycopg.connect(dsn) as conn:
        features = fetch_features(conn)
        if not features:
            raise RuntimeError(
                "No municipality tiles found for Helsinki/Espoo/Vantaa."
            )
        bounds = compute_bounds(features)

    m = build_map(features, bounds)
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    m.save(args.output)
    print(f"Wrote {len(features)} tiles to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
