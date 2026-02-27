\set ON_ERROR_STOP on

DROP MATERIALIZED VIEW IF EXISTS demo.country_tile_area_summary;

CREATE MATERIALIZED VIEW demo.country_tile_area_summary AS
WITH scopes AS (
    SELECT 'all_tiles'::text AS tile_scope
    UNION ALL
    SELECT 'non_water_tiles'::text AS tile_scope
), constants AS (
    SELECT
        14::int AS z,
        40075016.68557849::double precision AS world_width_m,
        16384::double precision AS tiles_per_axis
), tile_dims AS (
    SELECT
        z,
        world_width_m / tiles_per_axis AS tile_edge_m
    FROM constants
), country_geom AS (
    SELECT
        id AS country_id,
        geom AS country_geom,
        ST_Boundary(geom) AS country_boundary
    FROM demo.countries
), tile_counts AS (
    SELECT
        c.id AS country_id,
        c.slug AS country_slug,
        c.name AS country_name,
        s.tile_scope,
        t.z,
        td.tile_edge_m,
        COUNT(*)::bigint AS tile_count
    FROM demo.countries c
    CROSS JOIN scopes s
    JOIN demo.tiles_z14 t
      ON t.country_id = c.id
     AND (
         s.tile_scope = 'all_tiles'
         OR t.tile_class <> 'water_dominant'
     )
    JOIN tile_dims td
      ON td.z = t.z
    GROUP BY
        c.id,
        c.slug,
        c.name,
        s.tile_scope,
        t.z,
        td.tile_edge_m
), border_tile_adjustments AS (
    SELECT
        cg.country_id,
        s.tile_scope,
        SUM(ST_Area(t.geom)) AS border_tiles_full_area_m2_projected,
        SUM(ST_Area(ST_Intersection(t.geom, cg.country_geom))) AS border_tiles_clipped_area_m2_projected
    FROM country_geom cg
    CROSS JOIN scopes s
    JOIN demo.tiles_z14 t
      ON t.country_id = cg.country_id
     AND (
         s.tile_scope = 'all_tiles'
         OR t.tile_class <> 'water_dominant'
     )
    WHERE ST_Intersects(t.geom, cg.country_boundary)
    GROUP BY cg.country_id, s.tile_scope
)
SELECT
    tc.country_id,
    tc.country_slug,
    tc.country_name,
    tc.tile_scope,
    tc.z,
    tc.tile_edge_m,
    (tc.tile_edge_m * tc.tile_edge_m) AS tile_area_m2_projected,
    tc.tile_count,
    (
        tc.tile_count::double precision
        * (tc.tile_edge_m * tc.tile_edge_m)
    ) AS area_m2_by_constant_tile_size_projected,
    (
        tc.tile_count::double precision
        * (tc.tile_edge_m * tc.tile_edge_m)
    ) AS area_m2_from_full_tiles_projected,
    (
        tc.tile_count::double precision
        * (tc.tile_edge_m * tc.tile_edge_m)
        - COALESCE(bta.border_tiles_full_area_m2_projected, 0.0)
        + COALESCE(bta.border_tiles_clipped_area_m2_projected, 0.0)
    ) AS area_m2_from_clipped_tiles_projected
FROM tile_counts tc
LEFT JOIN border_tile_adjustments bta
  ON bta.country_id = tc.country_id
 AND bta.tile_scope = tc.tile_scope;

CREATE UNIQUE INDEX country_tile_area_summary_country_id_scope_uidx
    ON demo.country_tile_area_summary (country_id, tile_scope);

CREATE INDEX country_tile_area_summary_country_slug_idx
    ON demo.country_tile_area_summary (country_slug, tile_scope);

\echo '=== Country tile area summary (km^2) ==='
SELECT
    country_slug,
    country_name,
    tile_scope,
    z,
    tile_edge_m,
    tile_count,
    ROUND((area_m2_by_constant_tile_size_projected / 1000000.0)::numeric, 3) AS area_km2_by_constant_tile_size_projected,
    ROUND((area_m2_from_full_tiles_projected / 1000000.0)::numeric, 3) AS area_km2_from_full_tiles_projected,
    ROUND((area_m2_from_clipped_tiles_projected / 1000000.0)::numeric, 3) AS area_km2_from_clipped_tiles_projected
FROM demo.country_tile_area_summary
ORDER BY country_slug, tile_scope;
