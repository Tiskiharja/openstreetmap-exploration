\set ON_ERROR_STOP on

SELECT id, name
FROM demo.countries
WHERE slug = :'country_slug'
LIMIT 1
\gset

\echo '=== Tile vs assignment count ==='
SELECT
    t.tile_count,
    a.assignment_count,
    (t.tile_count = a.assignment_count) AS counts_match
FROM
    (SELECT COUNT(*) AS tile_count FROM demo.tiles_z14 WHERE country_id = :id) t,
    (SELECT COUNT(*) AS assignment_count FROM demo.tile_city_z14 WHERE country_id = :id) a;

\echo '=== Assignment method distribution ==='
SELECT assignment_method, COUNT(*) AS cnt
FROM demo.tile_city_z14
WHERE country_id = :id
GROUP BY assignment_method
ORDER BY cnt DESC;

\echo '=== Largest fallback distances (top 20) ==='
SELECT
    tc.z,
    tc.x,
    tc.y,
    tc.city_name,
    tc.place_type,
    ROUND(tc.distance_m)::bigint AS distance_m,
    ST_AsText(ST_Transform(t.centroid, 4326)) AS tile_centroid_wgs84
FROM demo.tile_city_z14 tc
JOIN demo.tiles_z14 t
  ON t.country_id = tc.country_id
 AND t.z = tc.z
 AND t.x = tc.x
 AND t.y = tc.y
WHERE tc.country_id = :id
ORDER BY tc.distance_m DESC
LIMIT 20;

\echo '=== Border tile spot-check sample (20 rows) ==='
SELECT
    t.z,
    t.x,
    t.y,
    tc.city_name,
    tc.place_type,
    ROUND(tc.distance_m)::bigint AS distance_m,
    tc.assignment_method
FROM demo.tiles_z14 t
JOIN demo.tile_city_z14 tc
  ON tc.country_id = t.country_id
 AND tc.z = t.z
 AND tc.x = t.x
 AND tc.y = t.y
JOIN demo.countries cb
  ON cb.id = t.country_id
WHERE t.country_id = :id
  AND ST_DWithin(t.geom, cb.geom, 50)
ORDER BY t.x, t.y
LIMIT 20;
