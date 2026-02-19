from __future__ import annotations

import os
import subprocess
import sys
from dataclasses import dataclass

SQL_STAGES = {
    "extensions": "sql/00_extensions.sql",
    "persistent-schema": "sql/05_persistent_tables.sql",
    "build-country": "sql/10_country_boundary.sql",
    "build-places": "sql/20_place_points.sql",
    "build-tiles": "sql/30_tiles_z14.sql",
    "assign": "sql/40_tile_city_assignment.sql",
    "validate": "sql/50_validation.sql",
}

RUN_ALL_ORDER = [
    "extensions",
    "persistent-schema",
    "build-country",
    "build-places",
    "build-tiles",
    "assign",
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

    raise SystemExit(usage())


if __name__ == "__main__":
    main()
