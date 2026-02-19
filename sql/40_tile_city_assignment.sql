\set ON_ERROR_STOP on

DROP TABLE IF EXISTS demo.stg_tile_city_z14;

CREATE TABLE demo.stg_tile_city_z14 (
    z int NOT NULL,
    x int NOT NULL,
    y int NOT NULL,
    city_osm_id bigint NOT NULL,
    city_name text NOT NULL,
    place_type text NOT NULL,
    distance_m double precision NOT NULL,
    assignment_method text NOT NULL,
    PRIMARY KEY (z, x, y)
);

WITH tier1_ranked AS (
    SELECT
        t.z,
        t.x,
        t.y,
        p.osm_id,
        p.name,
        p.place,
        ROW_NUMBER() OVER (
            PARTITION BY t.z, t.x, t.y
            ORDER BY p.place_rank ASC, p.population DESC NULLS LAST, p.osm_id ASC
        ) AS rn
    FROM demo.stg_tiles_z14 t
    JOIN demo.stg_place_points p
      ON ST_Contains(t.geom, p.geom)
), tier1 AS (
    SELECT
        z,
        x,
        y,
        osm_id,
        name,
        place,
        0.0::double precision AS distance_m,
        'inside_tile'::text AS assignment_method
    FROM tier1_ranked
    WHERE rn = 1
), unassigned AS (
    SELECT
        t.z,
        t.x,
        t.y,
        t.centroid
    FROM demo.stg_tiles_z14 t
    LEFT JOIN tier1 a
      ON t.z = a.z AND t.x = a.x AND t.y = a.y
    WHERE a.z IS NULL
), tier2_in_radius_ranked AS (
    SELECT
        u.z,
        u.x,
        u.y,
        p.osm_id,
        p.name,
        p.place,
        ST_Distance(u.centroid, p.geom) AS distance_m,
        ROW_NUMBER() OVER (
            PARTITION BY u.z, u.x, u.y
            ORDER BY p.place_rank ASC,
                     ST_Distance(u.centroid, p.geom) ASC,
                     p.population DESC NULLS LAST,
                     p.osm_id ASC
        ) AS rn
    FROM unassigned u
    JOIN demo.stg_place_points p
      ON ST_DWithin(u.centroid, p.geom, :'fallback_radius_m'::double precision)
), tier2_in_radius AS (
    SELECT
        z,
        x,
        y,
        osm_id,
        name,
        place,
        distance_m,
        'nearest'::text AS assignment_method
    FROM tier2_in_radius_ranked
    WHERE rn = 1
), still_unassigned AS (
    SELECT
        u.z,
        u.x,
        u.y,
        u.centroid
    FROM unassigned u
    LEFT JOIN tier2_in_radius r
      ON u.z = r.z AND u.x = r.x AND u.y = r.y
    WHERE r.z IS NULL
), tier2_unbounded AS (
    SELECT
        s.z,
        s.x,
        s.y,
        p.osm_id,
        p.name,
        p.place,
        p.distance_m,
        'nearest'::text AS assignment_method
    FROM still_unassigned s
    JOIN LATERAL (
        SELECT
            pp.osm_id,
            pp.name,
            pp.place,
            pp.place_rank,
            pp.population,
            ST_Distance(s.centroid, pp.geom) AS distance_m
        FROM demo.stg_place_points pp
        ORDER BY pp.place_rank ASC,
                 ST_Distance(s.centroid, pp.geom) ASC,
                 pp.population DESC NULLS LAST,
                 pp.osm_id ASC
        LIMIT 1
    ) p ON TRUE
), final_rows AS (
    SELECT z, x, y, osm_id, name, place, distance_m, assignment_method FROM tier1
    UNION ALL
    SELECT z, x, y, osm_id, name, place, distance_m, assignment_method FROM tier2_in_radius
    UNION ALL
    SELECT z, x, y, osm_id, name, place, distance_m, assignment_method FROM tier2_unbounded
)
INSERT INTO demo.stg_tile_city_z14 (
    z,
    x,
    y,
    city_osm_id,
    city_name,
    place_type,
    distance_m,
    assignment_method
)
SELECT
    z,
    x,
    y,
    osm_id,
    name,
    place,
    distance_m,
    assignment_method
FROM final_rows;

DO $$
BEGIN
    IF (SELECT COUNT(*) FROM demo.stg_tiles_z14) <> (SELECT COUNT(*) FROM demo.stg_tile_city_z14) THEN
        RAISE EXCEPTION 'Assignment row count does not match tile count';
    END IF;
END $$;

DELETE FROM demo.tile_city_z14 tc
USING demo.countries c
WHERE tc.country_id = c.id
  AND c.slug = :'country_slug';

INSERT INTO demo.tile_city_z14 (
    country_id,
    z,
    x,
    y,
    city_osm_id,
    city_name,
    place_type,
    distance_m,
    assignment_method
)
SELECT
    c.id AS country_id,
    s.z,
    s.x,
    s.y,
    s.city_osm_id,
    s.city_name,
    s.place_type,
    s.distance_m,
    s.assignment_method
FROM demo.stg_tile_city_z14 s
JOIN demo.countries c
  ON c.slug = :'country_slug';
