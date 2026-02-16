\set ON_ERROR_STOP on

DROP TABLE IF EXISTS demo.place_points;

CREATE TABLE demo.place_points AS
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
JOIN demo.country_boundary c
  ON ST_DWithin(p.way, c.geom, :'fallback_radius_m'::double precision)
WHERE p.name IS NOT NULL
  AND p.place IN ('city', 'town', 'village', 'suburb', 'neighbourhood');

ALTER TABLE demo.place_points
    ALTER COLUMN geom SET NOT NULL,
    ALTER COLUMN place_rank SET NOT NULL;

CREATE INDEX place_points_geom_gix ON demo.place_points USING GIST (geom);
CREATE INDEX place_points_rank_idx ON demo.place_points (place_rank);
CREATE INDEX place_points_rank_pop_osm_idx ON demo.place_points (place_rank, population DESC NULLS LAST, osm_id);
