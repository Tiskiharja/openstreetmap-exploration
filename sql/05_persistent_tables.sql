\set ON_ERROR_STOP on

DO $$
BEGIN
    IF to_regclass('demo.tile_city_z14') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'demo'
             AND table_name = 'tile_city_z14'
             AND column_name = 'country_id'
       ) THEN
        DROP TABLE demo.tile_city_z14;
    END IF;

    IF to_regclass('demo.tiles_z14') IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = 'demo'
             AND table_name = 'tiles_z14'
             AND column_name = 'country_id'
       ) THEN
        DROP TABLE demo.tiles_z14;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS demo.countries (
    id bigserial PRIMARY KEY,
    slug text NOT NULL UNIQUE,
    osm_id bigint,
    name text NOT NULL,
    geom geometry(MultiPolygon, 3857) NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS countries_geom_gix ON demo.countries USING GIST (geom);

CREATE TABLE IF NOT EXISTS demo.tiles_z14 (
    country_id bigint NOT NULL REFERENCES demo.countries(id) ON DELETE CASCADE,
    z int NOT NULL,
    x int NOT NULL,
    y int NOT NULL,
    geom geometry(Polygon, 3857) NOT NULL,
    centroid geometry(Point, 3857) NOT NULL,
    PRIMARY KEY (country_id, z, x, y)
);

CREATE INDEX IF NOT EXISTS tiles_z14_geom_gix ON demo.tiles_z14 USING GIST (geom);
CREATE INDEX IF NOT EXISTS tiles_z14_centroid_gix ON demo.tiles_z14 USING GIST (centroid);
CREATE INDEX IF NOT EXISTS tiles_z14_country_idx ON demo.tiles_z14 (country_id);

CREATE TABLE IF NOT EXISTS demo.tile_city_z14 (
    country_id bigint NOT NULL REFERENCES demo.countries(id) ON DELETE CASCADE,
    z int NOT NULL,
    x int NOT NULL,
    y int NOT NULL,
    city_osm_id bigint NOT NULL,
    city_name text NOT NULL,
    place_type text NOT NULL,
    distance_m double precision NOT NULL,
    assignment_method text NOT NULL,
    PRIMARY KEY (country_id, z, x, y),
    FOREIGN KEY (country_id, z, x, y)
        REFERENCES demo.tiles_z14 (country_id, z, x, y)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS tile_city_z14_country_idx ON demo.tile_city_z14 (country_id);

CREATE TABLE IF NOT EXISTS demo.admin_boundaries (
    country_id bigint NOT NULL REFERENCES demo.countries(id) ON DELETE CASCADE,
    osm_id bigint NOT NULL,
    name text,
    name_fi text,
    name_sv text,
    name_en text,
    admin_level text NOT NULL,
    geom geometry(MultiPolygon, 3857) NOT NULL,
    PRIMARY KEY (country_id, osm_id)
);

CREATE INDEX IF NOT EXISTS admin_boundaries_country_idx ON demo.admin_boundaries (country_id);
CREATE INDEX IF NOT EXISTS admin_boundaries_name_idx ON demo.admin_boundaries (name);
CREATE INDEX IF NOT EXISTS admin_boundaries_geom_gix ON demo.admin_boundaries USING GIST (geom);
