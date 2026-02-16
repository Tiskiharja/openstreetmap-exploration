SHELL := /bin/zsh

DB_NAME ?= osm_demo
DB_HOST ?= localhost
DB_PORT ?= 5433
DB_USER ?= postgres
COUNTRY_NAME ?= Finland
PBF_URL ?= https://download.geofabrik.de/europe/finland-latest.osm.pbf
PBF_PATH ?= data/finland-latest.osm.pbf
FALLBACK_RADIUS_M ?= 7000

PSQL = psql "postgresql://$(DB_USER)@$(DB_HOST):$(DB_PORT)/$(DB_NAME)"

.PHONY: help setup data-dir download db-init import sql-all build-country build-places build-tiles assign validate all

help:
	@echo "Targets:"
	@echo "  setup        - Sync uv environment"
	@echo "  download     - Download country PBF"
	@echo "  db-init      - Enable required extensions"
	@echo "  import       - Import PBF via osm2pgsql (classic schema)"
	@echo "  sql-all      - Run all SQL stages"
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
	  --database $(DB_NAME) \
	  --host $(DB_HOST) \
	  --port $(DB_PORT) \
	  --username $(DB_USER) \
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

validate:
	uv run osm-tile-pipeline validate

all: setup download db-init import sql-all validate
