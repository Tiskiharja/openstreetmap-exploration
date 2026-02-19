# OSM z14 Tile -> City Assignment

Offline batch pipeline that imports OSM country data, builds z=14 Web Mercator tiles, and assigns exactly one city/place label per tile.

## Stack

- PostgreSQL 17 + PostGIS
- osm2pgsql
- uv
- curl

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

Install required tools (Homebrew):

```bash
brew install libpq osm2pgsql postgis postgresql@17
```

Start PostgreSQL 17 (example on port 5433):

```bash
/opt/homebrew/opt/postgresql@17/bin/pg_ctl -D /opt/homebrew/var/postgresql@17 -l /tmp/postgresql17.log -o "-p 5433" start
createdb -p 5433 -U postgres osm_demo
```

Configuration:
- Use environment variables (`DB_NAME`, `DB_HOST`, `DB_PORT`, `DB_USER`) for local settings.
- `.env.example` is safe to commit; keep real credentials in a local `.env` (ignored by git).
- Unix socket auth is the default: leave `DB_HOST` empty (`DB_HOST=`).

## Run

Use PATH so `psql`/`osm2pgsql` resolve:

```bash
PATH="/opt/homebrew/opt/postgresql@17/bin:/opt/homebrew/opt/libpq/bin:/opt/homebrew/bin:$PATH" make all
```

Notes:
- `make download` is idempotent and reuses `$(PBF_PATH)` if it already exists.
- `make all` runs: setup, download, db-init, import, SQL build, validation.

## Run For France

One-command shortcut:

```bash
PATH="/opt/homebrew/opt/postgresql@17/bin:/opt/homebrew/opt/libpq/bin:/opt/homebrew/bin:$PATH" make france
```

Equivalent explicit command:

```bash
PATH="/opt/homebrew/opt/postgresql@17/bin:/opt/homebrew/opt/libpq/bin:/opt/homebrew/bin:$PATH" \
  make all COUNTRY_NAME=France COUNTRY_SLUG=france
```

This uses:
- `PBF_URL=https://download.geofabrik.de/europe/france-latest.osm.pbf`
- `PBF_PATH=data/france-latest.osm.pbf`

## Key tables

- `demo.country_boundary`
- `demo.place_points`
- `demo.tiles_z14`
- `demo.tile_city_z14`

## Assignment order (deterministic)

1. Place inside tile: lowest `place_rank`, highest `population`, lowest `osm_id`
2. Nearest to tile centroid within radius: lowest `place_rank`, shortest distance, highest `population`, lowest `osm_id`
3. Safety fallback: nearest globally with same ordering (guarantees one row per tile)

## Useful targets

- `make db-init`
- `make import`
- `make sql-all`
- `make validate`
- `uv run osm-tile-pipeline run build-tiles`

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
