\set ON_ERROR_STOP on

SELECT (
    COUNT(*) = 0
) AS missing_landmask_source
FROM demo.global_land_polygons
WHERE source_name = :'landmask_source_name'
  AND COALESCE(source_version, '') = COALESCE(NULLIF(:'landmask_version', ''), '')
\gset

\if :missing_landmask_source
\echo 'demo.global_land_polygons has no rows for the selected source/version; run make landmask-import before build-country-landmask'
\quit 1
\endif

DROP TABLE IF EXISTS demo.stg_country_landmask;

CREATE TABLE demo.stg_country_landmask AS
WITH country AS (
    SELECT
        ST_Expand(
            ST_Envelope(geom),
            (:'landmask_bbox_buffer_m')::double precision
        ) AS buffered_bbox
    FROM demo.stg_country_boundary
)
SELECT
    glp.id,
    glp.source_name,
    glp.source_version,
    glp.geom
FROM demo.global_land_polygons glp
CROSS JOIN country c
WHERE glp.source_name = :'landmask_source_name'
  AND COALESCE(glp.source_version, '') = COALESCE(NULLIF(:'landmask_version', ''), '')
  AND glp.geom && c.buffered_bbox;

CREATE INDEX stg_country_landmask_geom_gix
    ON demo.stg_country_landmask
    USING GIST (geom);

ANALYZE demo.stg_country_landmask;
