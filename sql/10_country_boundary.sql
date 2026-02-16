\set ON_ERROR_STOP on

DROP TABLE IF EXISTS demo.country_boundary;

CREATE TABLE demo.country_boundary AS
WITH candidates AS (
    SELECT
        osm_id,
        COALESCE(name, tags->'name', tags->'name:en') AS name,
        ST_Multi(ST_CollectionExtract(ST_MakeValid(way), 3))::geometry(MultiPolygon, 3857) AS geom
    FROM planet_osm_polygon
    WHERE boundary = 'administrative'
      AND admin_level = '2'
      AND (
          COALESCE(name, '') ILIKE :'country_name'
          OR COALESCE(tags->'name', '') ILIKE :'country_name'
          OR COALESCE(tags->'name:en', '') ILIKE :'country_name'
      )
), ranked AS (
    SELECT
        osm_id,
        name,
        geom,
        ROW_NUMBER() OVER (ORDER BY ST_Area(geom) DESC, osm_id ASC) AS rn
    FROM candidates
)
SELECT
    osm_id,
    name,
    geom
FROM ranked
WHERE rn = 1;

ALTER TABLE demo.country_boundary
    ALTER COLUMN geom SET NOT NULL;

CREATE INDEX country_boundary_geom_gix ON demo.country_boundary USING GIST (geom);

DO $$
DECLARE
    boundary_count int;
BEGIN
    SELECT COUNT(*) INTO boundary_count FROM demo.country_boundary;
    IF boundary_count <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one country boundary match; found %', boundary_count;
    END IF;
END $$;
