#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-osm_demo}"
DB_HOST="${DB_HOST:-}"
DB_PORT="${DB_PORT:-5433}"
DB_USER="${DB_USER:-${USER:-postgres}}"
LANDMASK_ARCHIVE_PATH="${LANDMASK_ARCHIVE_PATH:-data/landmask/osmdata/land-polygons-split-3857.zip}"
LANDMASK_EXTRACT_DIR="${LANDMASK_EXTRACT_DIR:-data/landmask/extracted}"
LANDMASK_SHP_PATH="${LANDMASK_SHP_PATH:-}"
LANDMASK_SOURCE_NAME="${LANDMASK_SOURCE_NAME:-osmdata_land_polygons}"
LANDMASK_VERSION="${LANDMASK_VERSION:-}"
LANDMASK_SOURCE_SRID="${LANDMASK_SOURCE_SRID:-3857}"
LANDMASK_TARGET_SRID="${LANDMASK_TARGET_SRID:-3857}"
LANDMASK_FORCE_IMPORT="${LANDMASK_FORCE_IMPORT:-0}"

PSQL_ARGS=(
  -U "$DB_USER"
  -p "$DB_PORT"
  -d "$DB_NAME"
  -v ON_ERROR_STOP=1
)

if [[ -n "${DB_HOST// }" ]]; then
  PSQL_ARGS+=(-h "$DB_HOST")
fi

if [[ ! -f "$LANDMASK_ARCHIVE_PATH" ]]; then
  echo "Missing landmask archive: $LANDMASK_ARCHIVE_PATH" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "unzip is required for landmask import" >&2
  exit 1
fi

if ! command -v shp2pgsql >/dev/null 2>&1; then
  echo "shp2pgsql is required for landmask import" >&2
  exit 1
fi

mkdir -p "$LANDMASK_EXTRACT_DIR"
unzip -o "$LANDMASK_ARCHIVE_PATH" -d "$LANDMASK_EXTRACT_DIR" >/dev/null

if [[ -z "$LANDMASK_VERSION" ]]; then
  LANDMASK_VERSION="$(basename "$LANDMASK_ARCHIVE_PATH" .zip)"
fi

if [[ -z "$LANDMASK_SHP_PATH" ]]; then
  LANDMASK_SHP_PATH="$(find "$LANDMASK_EXTRACT_DIR" -type f -name '*.shp' | sort | head -n 1)"
fi

if [[ -z "$LANDMASK_SHP_PATH" || ! -f "$LANDMASK_SHP_PATH" ]]; then
  echo "Missing extracted shapefile: $LANDMASK_SHP_PATH" >&2
  exit 1
fi

existing_count="$(
  psql "${PSQL_ARGS[@]}" -tA -c \
    "SELECT COUNT(*) FROM demo.global_land_polygons WHERE source_name = '$LANDMASK_SOURCE_NAME' AND COALESCE(source_version, '') = '$LANDMASK_VERSION';"
)"

if [[ "$LANDMASK_FORCE_IMPORT" != "1" && "$existing_count" != "0" ]]; then
  echo "Landmask ${LANDMASK_SOURCE_NAME}/${LANDMASK_VERSION} already loaded; skipping import"
  exit 0
fi

psql "${PSQL_ARGS[@]}" -c "DROP TABLE IF EXISTS demo.stg_landmask_import;" >/dev/null

if [[ "$LANDMASK_SOURCE_SRID" == "$LANDMASK_TARGET_SRID" ]]; then
  SHP2PGSQL_SRID_ARGS=(-s "$LANDMASK_TARGET_SRID")
else
  SHP2PGSQL_SRID_ARGS=(-s "${LANDMASK_SOURCE_SRID}:${LANDMASK_TARGET_SRID}")
fi

shp2pgsql -c -I "${SHP2PGSQL_SRID_ARGS[@]}" "$LANDMASK_SHP_PATH" demo.stg_landmask_import | psql "${PSQL_ARGS[@]}" >/dev/null

psql "${PSQL_ARGS[@]}" <<SQL
DELETE FROM demo.global_land_polygons
WHERE source_name = '${LANDMASK_SOURCE_NAME}'
  AND COALESCE(source_version, '') = '${LANDMASK_VERSION}';

INSERT INTO demo.global_land_polygons (source_name, source_version, geom)
SELECT
    '${LANDMASK_SOURCE_NAME}',
    '${LANDMASK_VERSION}',
    ST_Multi(geom)::geometry(MultiPolygon, 3857)
FROM demo.stg_landmask_import;

DROP TABLE IF EXISTS demo.stg_landmask_import;

ANALYZE demo.global_land_polygons;
SQL

echo "Imported landmask ${LANDMASK_SOURCE_NAME}/${LANDMASK_VERSION} into demo.global_land_polygons"
