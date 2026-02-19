\set ON_ERROR_STOP on

DROP TABLE IF EXISTS demo.stg_place_points;

CREATE TABLE demo.stg_place_points AS
SELECT
    p.osm_id::bigint AS osm_id,
    p.name::text AS name,
    p.place::text AS place,
    CASE
        WHEN NULLIF(regexp_replace(COALESCE(p.tags->'population', ''), '[^0-9]', '', 'g'), '') IS NULL THEN NULL
        ELSE NULLIF(regexp_replace(COALESCE(p.tags->'population', ''), '[^0-9]', '', 'g'), '')::bigint
    END AS population,
    CASE p.place
        WHEN 'city' THEN 1
        WHEN 'town' THEN 2
        WHEN 'village' THEN 3
        WHEN 'suburb' THEN 4
        WHEN 'neighbourhood' THEN 5
        ELSE 99
    END::int AS place_rank,
    p.way::geometry(Point, 3857) AS geom
FROM planet_osm_point p
JOIN demo.stg_country_boundary c
  ON ST_DWithin(p.way, c.geom, :'fallback_radius_m'::double precision)
WHERE p.name IS NOT NULL
  AND p.place IN ('city', 'town', 'village', 'suburb', 'neighbourhood');

ALTER TABLE demo.stg_place_points
    ALTER COLUMN geom SET NOT NULL,
    ALTER COLUMN place_rank SET NOT NULL;

CREATE INDEX stg_place_points_geom_gix ON demo.stg_place_points USING GIST (geom);
CREATE INDEX stg_place_points_rank_idx ON demo.stg_place_points (place_rank);
CREATE INDEX stg_place_points_rank_pop_osm_idx ON demo.stg_place_points (place_rank, population DESC NULLS LAST, osm_id);

DELETE FROM demo.admin_boundaries ab
USING demo.countries c
WHERE ab.country_id = c.id
  AND c.slug = :'country_slug';

INSERT INTO demo.admin_boundaries (
    country_id,
    osm_id,
    name,
    name_fi,
    name_sv,
    name_en,
    admin_level,
    geom
)
WITH candidates AS (
    SELECT
        c.id AS country_id,
        p.osm_id::bigint AS osm_id,
        p.name::text AS name,
        (p.tags->'name:fi')::text AS name_fi,
        (p.tags->'name:sv')::text AS name_sv,
        (p.tags->'name:en')::text AS name_en,
        p.admin_level::text AS admin_level,
        ST_Multi(ST_CollectionExtract(ST_MakeValid(p.way), 3))::geometry(MultiPolygon, 3857) AS geom
    FROM planet_osm_polygon p
    JOIN demo.stg_country_boundary cb
      ON ST_Intersects(p.way, cb.geom)
    JOIN demo.countries c
      ON c.slug = :'country_slug'
    WHERE p.boundary = 'administrative'
      AND p.admin_level IN ('7', '8')
      AND (
          p.name IS NOT NULL
          OR p.tags ? 'name:fi'
          OR p.tags ? 'name:sv'
          OR p.tags ? 'name:en'
      )
), ranked AS (
    SELECT
        country_id,
        osm_id,
        name,
        name_fi,
        name_sv,
        name_en,
        admin_level,
        geom,
        ROW_NUMBER() OVER (
            PARTITION BY country_id, osm_id
            ORDER BY ST_Area(geom) DESC, osm_id ASC
        ) AS rn
    FROM candidates
    WHERE NOT ST_IsEmpty(geom)
)
SELECT
    country_id,
    osm_id,
    name,
    name_fi,
    name_sv,
    name_en,
    admin_level,
    geom
FROM ranked
WHERE rn = 1;
