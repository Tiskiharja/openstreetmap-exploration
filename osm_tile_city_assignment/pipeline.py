from __future__ import annotations

import os
import subprocess
import sys
from dataclasses import dataclass

SQL_STAGES = {
    "extensions": "sql/00_extensions.sql",
    "persistent-schema": "sql/05_persistent_tables.sql",
    "build-country": "sql/10_country_boundary.sql",
    "build-country-landmask": "sql/25_country_landmask.sql",
    "build-places": "sql/20_place_points.sql",
    "build-tiles": "sql/30_tiles_z14.sql",
    "assign": "sql/40_tile_city_assignment.sql",
    "validate": "sql/50_validation.sql",
    "area-summary": "sql/60_country_tile_area_summary.sql",
    "area-summary-geodesic": "sql/61_country_tile_area_summary_geodesic.sql",
}

RUN_ALL_ORDER = [
    "extensions",
    "persistent-schema",
    "build-country",
    "build-country-landmask",
    "build-places",
    "build-tiles",
    "assign",
    "area-summary",
]


@dataclass(frozen=True)
class Config:
    db_name: str = os.getenv("DB_NAME", "osm_demo")
    db_host: str = os.getenv("DB_HOST", "")
    db_port: str = os.getenv("DB_PORT", "5433")
    db_user: str = os.getenv("DB_USER", os.getenv("USER", "postgres"))
    country_name: str = os.getenv("COUNTRY_NAME", "Finland")
    country_slug: str = os.getenv("COUNTRY_SLUG", "finland")
    fallback_radius_m: str = os.getenv("FALLBACK_RADIUS_M", "7000")
    landmask_bbox_buffer_m: str = os.getenv("LANDMASK_BBOX_BUFFER_M", "10000")
    landmask_source_name: str = os.getenv("LANDMASK_SOURCE_NAME", "osmdata_land_polygons")
    landmask_version: str = os.getenv("LANDMASK_VERSION", "land-polygons-split-3857")


def run_sql(stage: str, cfg: Config) -> None:
    sql_file = SQL_STAGES[stage]
    cmd = [
        "psql",
        "-U",
        cfg.db_user,
        "-p",
        cfg.db_port,
        "-d",
        cfg.db_name,
        "-v",
        "ON_ERROR_STOP=1",
        "-v",
        f"country_name={cfg.country_name}",
        "-v",
        f"country_slug={cfg.country_slug}",
        "-v",
        f"fallback_radius_m={cfg.fallback_radius_m}",
        "-v",
        f"landmask_bbox_buffer_m={cfg.landmask_bbox_buffer_m}",
        "-v",
        f"landmask_source_name={cfg.landmask_source_name}",
        "-v",
        f"landmask_version={cfg.landmask_version}",
        "-f",
        sql_file,
    ]
    if cfg.db_host.strip():
        cmd[1:1] = ["-h", cfg.db_host]
    print(f"\n==> Running stage: {stage} ({sql_file})")
    subprocess.run(cmd, check=True)


def usage() -> int:
    print(
        "Usage:\n"
        "  uv run osm-tile-pipeline run-all\n"
        "  uv run osm-tile-pipeline run <stage>\n"
        "  uv run osm-tile-pipeline validate\n"
        "  uv run osm-tile-pipeline area-summary\n"
        "  uv run osm-tile-pipeline area-summary-geodesic\n"
        f"Stages: {', '.join(k for k in SQL_STAGES if k != 'validate')}"
    )
    return 2


def main() -> None:
    cfg = Config()
    args = sys.argv[1:]
    if not args:
        raise SystemExit(usage())

    command = args[0]
    if command == "run-all":
        for stage in RUN_ALL_ORDER:
            run_sql(stage, cfg)
        return

    if command == "run":
        if len(args) != 2:
            raise SystemExit(usage())
        stage = args[1]
        if stage not in SQL_STAGES or stage == "validate":
            raise SystemExit(usage())
        run_sql(stage, cfg)
        return

    if command == "validate":
        run_sql("validate", cfg)
        return

    if command == "area-summary":
        run_sql("area-summary", cfg)
        return

    if command == "area-summary-geodesic":
        run_sql("area-summary-geodesic", cfg)
        return

    raise SystemExit(usage())


if __name__ == "__main__":
    main()
