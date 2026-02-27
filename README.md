# OSM z14 Tile -> City Assignment

Offline batch pipeline that imports OSM country data, builds z=14 Web Mercator tiles, and assigns exactly one city/place label per tile.

Code in this repo is mostly vibe-coded. The goal has been for me to get familiar with working with OSM data. 

## Published Docs

- [Docs hub](data/index.html)
- [Area analysis summary](AREA_ANALYSIS.md)
- [Finland tiles](data/finland_tiles_dissolved.html)
- [France tiles](data/france_tiles_dissolved.html)
- [Hungary tiles](data/hungary_tiles_dissolved.html)
- [Helsinki / Espoo / Vantaa tiles](data/helsinki_espoo_vantaa_tiles.html)

## Stack

- PostgreSQL 16 + PostGIS
- osm2pgsql
- `shp2pgsql` + `unzip` for landmask imports
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
- `make all` runs: setup, download, db-init, import, landmask import, SQL build, validation.
- The default landmask provider is the OSM-derived `osmdata` land polygons dataset.
- Natural Earth `ne_10m_land` remains available as a fallback via `LANDMASK_PROVIDER=natural-earth`.
- The landmask import skips work if the pinned source/version is already loaded.

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

`demo.tiles_z14` now also stores coastal classification metadata:
- `is_boundary_tile`: whether the tile touches the country polygon boundary
- `country_overlap_ratio`: `area(tile ∩ country) / area(tile)` in EPSG:3857
- `land_sample_count`: number of tile sample points that fall on land polygons
- `land_sample_ratio`: `land_sample_count / 5.0`
- `tile_class`: one of `interior_land`, `land_dominant`, `coastal_mixed`, `water_dominant`

`tile_class` is driven by 5-point sampling against a staged global landmask. `country_overlap_ratio` is kept as a secondary diagnostic field.

## Assignment order (deterministic)

1. Place inside tile: lowest `place_rank`, highest `population`, lowest `osm_id`
2. Nearest to tile centroid within radius: lowest `place_rank`, shortest distance, highest `population`, lowest `osm_id`
3. Safety fallback: nearest globally with same ordering (guarantees one row per tile)

## Useful targets

- `make db-init`
- `make landmask-download`
- `make landmask-download-osmdata`
- `make landmask-download-natural-earth`
- `make landmask-import`
- `make landmask-import-osmdata`
- `make landmask-import-natural-earth`
- `make import`
- `make sql-all`
- `make build-country-landmask`
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
- `tile_scope`: `all_tiles` or `non_water_tiles` (`interior_land`, `land_dominant`, `coastal_mixed`)
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
- `tile_scope`: `all_tiles` or `non_water_tiles`
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

By default, per-tile rendering colors tiles by `tile_class`. Use `--color-by uniform` to restore a single fill color.

For a much smaller classified output, dissolve tiles into one geometry per `tile_class`:

```bash
uv run python scripts/plot_country_tiles.py --country-name "Suomi / Finland" --mode dissolved-by-class --output data/finland_tiles_classified_dissolved.html
```
