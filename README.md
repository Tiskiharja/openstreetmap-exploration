# OSM z14 Tile -> City Assignment

Offline batch pipeline that imports OSM country data, builds z=14 Web Mercator tiles, and assigns exactly one city/place label per tile.

## Stack

- PostgreSQL 16 + PostGIS
- osm2pgsql
- uv
- curl

The pipeline is platform-agnostic and can run on macOS or Linux as long as these tools are installed and available on `PATH`.

## Defaults (from `Makefile`)

- `DB_NAME=osm_demo`
- `DB_HOST=` (empty = Unix socket mode)
- `DB_PORT=5433`
- `DB_USER=$(whoami)`
- `COUNTRY_NAME=Finland`
- `COUNTRY_SLUG=finland`
- `FALLBACK_RADIUS_M=7000`
- `PBF_PATH=data/finland-latest.osm.pbf`

## One-time setup

Install the required tools using your platform package manager, then start PostgreSQL and create the database:

```bash
createdb -p 5433 -U postgres osm_demo
```

Configuration:
- Use environment variables (`DB_NAME`, `DB_HOST`, `DB_PORT`, `DB_USER`) for local settings.
- `.env.example` is safe to commit; keep real credentials in a local `.env` (ignored by git).
- Unix socket auth is the default: leave `DB_HOST` empty (`DB_HOST=`).

## Run

Ensure `psql` and `osm2pgsql` are on `PATH`, then run:

```bash
make all
```

Notes:
- `make download` is idempotent and reuses `$(PBF_PATH)` if it already exists.
- `make all` runs: setup, download, db-init, import, SQL build, validation.

## Run For France

One-command shortcut:

```bash
make france
```

Equivalent explicit command:

```bash
make all COUNTRY_NAME=France COUNTRY_SLUG=france
```

This uses:
- `PBF_URL=https://download.geofabrik.de/europe/france-latest.osm.pbf`
- `PBF_PATH=data/france-latest.osm.pbf`

## Key tables

- `demo.countries` (persistent, one row per `COUNTRY_SLUG`)
- `demo.tiles_z14`
- `demo.tile_city_z14`
- `demo.stg_country_boundary` (temporary, overwritten per run)
- `demo.stg_place_points` (temporary, overwritten per run)
- `demo.stg_tiles_z14` (temporary, overwritten per run)
- `demo.stg_tile_city_z14` (temporary, overwritten per run)

## Assignment order (deterministic)

1. Place inside tile: lowest `place_rank`, highest `population`, lowest `osm_id`
2. Nearest to tile centroid within radius: lowest `place_rank`, shortest distance, highest `population`, lowest `osm_id`
3. Safety fallback: nearest globally with same ordering (guarantees one row per tile)

## Useful targets

- `make db-init`
- `make import`
- `make sql-all`
- `make area-summary`
- `make area-summary-geodesic`
- `make validate`
- `uv run osm-tile-pipeline run build-tiles`

## Country tile area summary

Build a per-country summary from `demo.tiles_z14`:

```bash
make area-summary
```

This creates materialized view `demo.country_tile_area_summary` with:
- `tile_edge_m`: z14 tile edge length in projected meters (Web Mercator world width / `2^14`)
- `tile_count`: number of tiles intersecting the country
- `area_m2_by_constant_tile_size_projected`: `tile_count * tile_edge_m^2` (rough projected estimate)
- `area_m2_from_full_tiles_projected`: sum of full tile areas in EPSG:3857
- `area_m2_from_clipped_tiles_projected`: sum of tile-country intersections in EPSG:3857 (best tile-based estimate in this report)

For geodesic area (slower), run:

```bash
make area-summary-geodesic
```

This creates materialized view `demo.country_tile_area_summary_geodesic` with:
- `area_m2_from_full_tiles_geodesic`: sum of full tile geodesic areas
- `area_m2_from_clipped_tiles_geodesic`: sum of tile-country intersections as geodesic area

## Visualize Helsinki/Espoo/Vantaa tiles

Create an interactive HTML map where each z14 tile is filled with an opaque color by assigned city:

```bash
uv run python scripts/plot_hki_espoo_vantaa_tiles.py --output data/helsinki_espoo_vantaa_tiles.html
```

This visualization uses municipality boundaries from `public.planet_osm_polygon` (`boundary=administrative`, `admin_level=8`) for Helsinki, Espoo and Vantaa, then colors tiles by centroid-in-boundary membership.

Color mapping:
- Helsinki: red
- Espoo: blue
- Vantaa: green

## Visualize country tiles

Render all z14 tiles inside a country boundary as a single colored layer:

```bash
uv run python scripts/plot_country_tiles.py --country-name "Suomi / Finland" --output data/finland_tiles.html
```
