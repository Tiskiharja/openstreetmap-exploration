SHELL := /bin/zsh

DB_NAME ?= osm_demo
DB_HOST ?= 
DB_PORT ?= 5433
DB_USER ?= $(shell whoami)
COUNTRY_NAME ?= Finland
COUNTRY_SLUG ?= finland
PBF_URL ?= https://download.geofabrik.de/europe/$(COUNTRY_SLUG)-latest.osm.pbf
PBF_PATH ?= data/$(COUNTRY_SLUG)-latest.osm.pbf
FALLBACK_RADIUS_M ?= 7000
LANDMASK_PROVIDER ?= osmdata
LANDMASK_DIR ?= data/landmask/$(LANDMASK_PROVIDER)
LANDMASK_EXTRACT_DIR ?= $(LANDMASK_DIR)/extracted
LANDMASK_SHP_PATH ?=
LANDMASK_BBOX_BUFFER_M ?= 10000
LANDMASK_FORCE_IMPORT ?= 0
LANDMASK_TARGET_SRID ?= 3857

ifeq ($(LANDMASK_PROVIDER),osmdata)
LANDMASK_URL ?= https://osmdata.openstreetmap.de/download/land-polygons-split-3857.zip
LANDMASK_ARCHIVE_BASENAME ?= land-polygons-split-3857.zip
LANDMASK_SOURCE_NAME ?= osmdata_land_polygons
LANDMASK_VERSION ?= land-polygons-split-3857
LANDMASK_SOURCE_SRID ?= 3857
else ifeq ($(LANDMASK_PROVIDER),natural-earth)
LANDMASK_URL ?= https://naciscdn.org/naturalearth/10m/physical/ne_10m_land.zip
LANDMASK_ARCHIVE_BASENAME ?= ne_10m_land.zip
LANDMASK_SOURCE_NAME ?= natural_earth_land
LANDMASK_VERSION ?= ne_10m_land
LANDMASK_SOURCE_SRID ?= 4326
else
$(error Unsupported LANDMASK_PROVIDER '$(LANDMASK_PROVIDER)'; use osmdata or natural-earth)
endif

LANDMASK_ARCHIVE_PATH ?= $(LANDMASK_DIR)/$(LANDMASK_ARCHIVE_BASENAME)

PSQL_ARGS = -U $(DB_USER) -p $(DB_PORT) -d $(DB_NAME)
OSM2PGSQL_ARGS = \
	  --database $(DB_NAME) \
	  --port $(DB_PORT) # \
	  # --username $(DB_USER)

ifneq ($(strip $(DB_HOST)),)
PSQL_ARGS += -h $(DB_HOST)
OSM2PGSQL_ARGS += --host $(DB_HOST)
endif

PSQL = psql $(PSQL_ARGS)
PIPELINE_ENV = \
	DB_NAME="$(DB_NAME)" \
	DB_HOST="$(DB_HOST)" \
	DB_PORT="$(DB_PORT)" \
	DB_USER="$(DB_USER)" \
	COUNTRY_NAME="$(COUNTRY_NAME)" \
	COUNTRY_SLUG="$(COUNTRY_SLUG)" \
	FALLBACK_RADIUS_M="$(FALLBACK_RADIUS_M)" \
	LANDMASK_BBOX_BUFFER_M="$(LANDMASK_BBOX_BUFFER_M)" \
	LANDMASK_SOURCE_NAME="$(LANDMASK_SOURCE_NAME)" \
	LANDMASK_VERSION="$(LANDMASK_VERSION)"

.PHONY: help setup data-dir landmask-dir download landmask-download landmask-download-osmdata landmask-download-natural-earth db-init import landmask-import landmask-import-osmdata landmask-import-natural-earth sql-all build-country build-country-landmask build-places build-tiles assign area-summary area-summary-geodesic validate all france

help:
	@echo "Targets:"
	@echo "  setup        - Sync uv environment"
	@echo "  download     - Download country PBF"
	@echo "  landmask-download - Download land polygons for LANDMASK_PROVIDER ($(LANDMASK_PROVIDER))"
	@echo "  landmask-download-osmdata - Download OSM-derived land polygons"
	@echo "  landmask-download-natural-earth - Download Natural Earth land polygons"
	@echo "  db-init      - Enable required extensions"
	@echo "  import       - Import PBF via osm2pgsql (classic schema)"
	@echo "  landmask-import - Load the selected landmask provider into PostGIS"
	@echo "  landmask-import-osmdata - Load OSM-derived land polygons into PostGIS"
	@echo "  landmask-import-natural-earth - Load Natural Earth land polygons into PostGIS"
	@echo "  sql-all      - Run all SQL stages"
	@echo "  area-summary - Build country tile area summary view"
	@echo "  area-summary-geodesic - Build country tile area summary geodesic view (slower)"
	@echo "  validate     - Run validation queries"
	@echo "  all          - setup + download + db-init + import + landmask-import + sql-all + validate"

data-dir:
	mkdir -p data

landmask-dir:
	mkdir -p $(LANDMASK_DIR)

setup:
	uv sync

download: data-dir
	@if [ -s "$(PBF_PATH)" ]; then \
		echo "Using existing $(PBF_PATH)"; \
	else \
		curl -L "$(PBF_URL)" -o "$(PBF_PATH)"; \
	fi

landmask-download: landmask-dir
	@if [ -s "$(LANDMASK_ARCHIVE_PATH)" ]; then \
		echo "Using existing $(LANDMASK_ARCHIVE_PATH)"; \
	else \
		curl -L "$(LANDMASK_URL)" -o "$(LANDMASK_ARCHIVE_PATH)"; \
	fi

landmask-download-osmdata:
	$(MAKE) landmask-download LANDMASK_PROVIDER=osmdata

landmask-download-natural-earth:
	$(MAKE) landmask-download LANDMASK_PROVIDER=natural-earth

db-init:
	$(PSQL) -f sql/00_extensions.sql

import:
	osm2pgsql \
	  $(OSM2PGSQL_ARGS) \
	  --create \
	  --slim \
	  --merc \
	  --hstore-all \
	  "$(PBF_PATH)"

landmask-import: landmask-download db-init
	$(PIPELINE_ENV) uv run osm-tile-pipeline run persistent-schema
	DB_NAME="$(DB_NAME)" \
	DB_HOST="$(DB_HOST)" \
	DB_PORT="$(DB_PORT)" \
	DB_USER="$(DB_USER)" \
	LANDMASK_ARCHIVE_PATH="$(LANDMASK_ARCHIVE_PATH)" \
	LANDMASK_EXTRACT_DIR="$(LANDMASK_EXTRACT_DIR)" \
	LANDMASK_SHP_PATH="$(LANDMASK_SHP_PATH)" \
	LANDMASK_SOURCE_NAME="$(LANDMASK_SOURCE_NAME)" \
	LANDMASK_VERSION="$(LANDMASK_VERSION)" \
	LANDMASK_SOURCE_SRID="$(LANDMASK_SOURCE_SRID)" \
	LANDMASK_TARGET_SRID="$(LANDMASK_TARGET_SRID)" \
	LANDMASK_FORCE_IMPORT="$(LANDMASK_FORCE_IMPORT)" \
	bash scripts/import_landmask.sh

landmask-import-osmdata:
	$(MAKE) landmask-import LANDMASK_PROVIDER=osmdata

landmask-import-natural-earth:
	$(MAKE) landmask-import LANDMASK_PROVIDER=natural-earth

sql-all:
	$(PIPELINE_ENV) uv run osm-tile-pipeline run-all

build-country:
	$(PIPELINE_ENV) uv run osm-tile-pipeline run build-country

build-country-landmask:
	$(PIPELINE_ENV) uv run osm-tile-pipeline run build-country-landmask

build-places:
	$(PIPELINE_ENV) uv run osm-tile-pipeline run build-places

build-tiles:
	$(PIPELINE_ENV) uv run osm-tile-pipeline run build-tiles

assign:
	$(PIPELINE_ENV) uv run osm-tile-pipeline run assign

area-summary:
	$(PIPELINE_ENV) uv run osm-tile-pipeline area-summary

area-summary-geodesic:
	$(PIPELINE_ENV) uv run osm-tile-pipeline area-summary-geodesic

validate:
	$(PIPELINE_ENV) uv run osm-tile-pipeline validate

all: setup download db-init import landmask-import sql-all validate

france:
	$(MAKE) all COUNTRY_NAME=France COUNTRY_SLUG=france
