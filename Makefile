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

.PHONY: help setup data-dir download db-init import sql-all build-country build-places build-tiles assign area-summary area-summary-geodesic validate all france

help:
	@echo "Targets:"
	@echo "  setup        - Sync uv environment"
	@echo "  download     - Download country PBF"
	@echo "  db-init      - Enable required extensions"
	@echo "  import       - Import PBF via osm2pgsql (classic schema)"
	@echo "  sql-all      - Run all SQL stages"
	@echo "  area-summary - Build country tile area summary view"
	@echo "  area-summary-geodesic - Build country tile area summary geodesic view (slower)"
	@echo "  validate     - Run validation queries"
	@echo "  all          - setup + download + db-init + import + sql-all + validate"

data-dir:
	mkdir -p data

setup:
	uv sync

download: data-dir
	@if [ -s "$(PBF_PATH)" ]; then \
		echo "Using existing $(PBF_PATH)"; \
	else \
		curl -L "$(PBF_URL)" -o "$(PBF_PATH)"; \
	fi

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

sql-all:
	uv run osm-tile-pipeline run-all

build-country:
	uv run osm-tile-pipeline run build-country

build-places:
	uv run osm-tile-pipeline run build-places

build-tiles:
	uv run osm-tile-pipeline run build-tiles

assign:
	uv run osm-tile-pipeline run assign

area-summary:
	uv run osm-tile-pipeline area-summary

area-summary-geodesic:
	uv run osm-tile-pipeline area-summary-geodesic

validate:
	uv run osm-tile-pipeline validate

all: setup download db-init import sql-all validate

france:
	$(MAKE) all COUNTRY_NAME=France COUNTRY_SLUG=france
