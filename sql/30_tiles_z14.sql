\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION demo.lon_to_tile_x(lon double precision, z int)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT FLOOR((lon + 180.0) / 360.0 * (2 ^ z))::int;
$$;

CREATE OR REPLACE FUNCTION demo.lat_to_tile_y(lat double precision, z int)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT FLOOR(
        (
            1.0 - LN(TAN(RADIANS(lat)) + (1.0 / COS(RADIANS(lat)))) / PI()
        ) / 2.0 * (2 ^ z)
    )::int;
$$;

DO $$
BEGIN
    IF to_regclass('demo.stg_country_landmask') IS NULL THEN
        RAISE EXCEPTION
            'demo.stg_country_landmask is missing; run build-country-landmask before build-tiles';
    END IF;
END $$;

DROP TABLE IF EXISTS demo.stg_tiles_z14;

CREATE TABLE demo.stg_tiles_z14 AS
WITH thresholds AS (
    SELECT 5::int AS total_sample_points
), country AS (
    SELECT
        geom,
        ST_Boundary(geom) AS boundary_geom
    FROM demo.stg_country_boundary
), bbox AS (
    SELECT ST_Transform(ST_Envelope(geom), 4326) AS geom
    FROM demo.stg_country_boundary
), raw_ranges AS (
    SELECT
        demo.lon_to_tile_x(ST_XMin(geom), 14) AS x_a,
        demo.lon_to_tile_x(ST_XMax(geom), 14) AS x_b,
        demo.lat_to_tile_y(ST_YMin(geom), 14) AS y_a,
        demo.lat_to_tile_y(ST_YMax(geom), 14) AS y_b
    FROM bbox
), ranges AS (
    SELECT
        GREATEST(0, LEAST(16383, LEAST(x_a, x_b))) AS x_min,
        GREATEST(0, LEAST(16383, GREATEST(x_a, x_b))) AS x_max,
        GREATEST(0, LEAST(16383, LEAST(y_a, y_b))) AS y_min,
        GREATEST(0, LEAST(16383, GREATEST(y_a, y_b))) AS y_max
    FROM raw_ranges
), candidates AS (
    SELECT
        14::int AS z,
        x::int AS x,
        y::int AS y,
        ST_TileEnvelope(14, x, y)::geometry(Polygon, 3857) AS geom
    FROM ranges r
    CROSS JOIN LATERAL generate_series(r.x_min, r.x_max) AS x
    CROSS JOIN LATERAL generate_series(r.y_min, r.y_max) AS y
), selected_tiles AS (
    SELECT
        c.z,
        c.x,
        c.y,
        c.geom,
        ST_Centroid(c.geom)::geometry(Point, 3857) AS centroid,
        ST_Intersects(c.geom, country.boundary_geom) AS is_boundary_tile
    FROM candidates c
    CROSS JOIN country
    WHERE ST_Intersects(c.geom, country.geom)
), overlap_tiles AS (
    SELECT
        t.z,
        t.x,
        t.y,
        t.geom,
        t.centroid,
        t.is_boundary_tile,
        CASE
            WHEN t.is_boundary_tile THEN ST_Area(ST_Intersection(t.geom, country.geom)) / ST_Area(t.geom)
            ELSE 1.0::double precision
        END AS country_overlap_ratio
    FROM selected_tiles t
    CROSS JOIN country
), sample_points AS (
    SELECT
        t.z,
        t.x,
        t.y,
        sample_points.sample_id,
        sample_points.sample_point
    FROM selected_tiles t
    CROSS JOIN LATERAL (
        SELECT
            ST_XMin(t.geom) AS min_x,
            ST_XMax(t.geom) AS max_x,
            ST_YMin(t.geom) AS min_y,
            ST_YMax(t.geom) AS max_y
    ) bounds
    CROSS JOIN LATERAL (
        VALUES
            (
                1,
                ST_SetSRID(
                    ST_MakePoint((bounds.min_x + bounds.max_x) / 2.0, (bounds.min_y + bounds.max_y) / 2.0),
                    3857
                )
            ),
            (
                2,
                ST_SetSRID(
                    ST_MakePoint(
                        bounds.min_x + ((bounds.max_x - bounds.min_x) * 0.2),
                        bounds.min_y + ((bounds.max_y - bounds.min_y) * 0.2)
                    ),
                    3857
                )
            ),
            (
                3,
                ST_SetSRID(
                    ST_MakePoint(
                        bounds.max_x - ((bounds.max_x - bounds.min_x) * 0.2),
                        bounds.min_y + ((bounds.max_y - bounds.min_y) * 0.2)
                    ),
                    3857
                )
            ),
            (
                4,
                ST_SetSRID(
                    ST_MakePoint(
                        bounds.min_x + ((bounds.max_x - bounds.min_x) * 0.2),
                        bounds.max_y - ((bounds.max_y - bounds.min_y) * 0.2)
                    ),
                    3857
                )
            ),
            (
                5,
                ST_SetSRID(
                    ST_MakePoint(
                        bounds.max_x - ((bounds.max_x - bounds.min_x) * 0.2),
                        bounds.max_y - ((bounds.max_y - bounds.min_y) * 0.2)
                    ),
                    3857
                )
            )
    ) AS sample_points(sample_id, sample_point)
), land_sample_hits AS (
    SELECT DISTINCT
        sp.z,
        sp.x,
        sp.y,
        sp.sample_id
    FROM sample_points sp
    JOIN demo.stg_country_landmask lm
      ON lm.geom && sp.sample_point
     AND ST_Intersects(sp.sample_point, lm.geom)
), land_samples AS (
    SELECT
        lsh.z,
        lsh.x,
        lsh.y,
        COUNT(*)::smallint AS land_sample_count
    FROM land_sample_hits lsh
    GROUP BY lsh.z, lsh.x, lsh.y
)
SELECT
    t.z,
    t.x,
    t.y,
    t.geom,
    t.centroid,
    t.is_boundary_tile,
    t.country_overlap_ratio,
    COALESCE(ls.land_sample_count, 0::smallint) AS land_sample_count,
    COALESCE(ls.land_sample_count, 0)::double precision / thresholds.total_sample_points AS land_sample_ratio,
    CASE
        WHEN COALESCE(ls.land_sample_count, 0) = thresholds.total_sample_points THEN 'interior_land'
        WHEN COALESCE(ls.land_sample_count, 0) >= 3 THEN 'land_dominant'
        WHEN COALESCE(ls.land_sample_count, 0) >= 1 THEN 'coastal_mixed'
        ELSE 'water_dominant'
    END AS tile_class
FROM overlap_tiles t
LEFT JOIN land_samples ls
  ON ls.z = t.z
 AND ls.x = t.x
 AND ls.y = t.y
CROSS JOIN thresholds;

ALTER TABLE demo.stg_tiles_z14
    ADD CONSTRAINT stg_tiles_z14_pk PRIMARY KEY (z, x, y);

CREATE INDEX stg_tiles_z14_geom_gix ON demo.stg_tiles_z14 USING GIST (geom);
CREATE INDEX stg_tiles_z14_centroid_gix ON demo.stg_tiles_z14 USING GIST (centroid);

DELETE FROM demo.tiles_z14 t
USING demo.countries c
WHERE t.country_id = c.id
  AND c.slug = :'country_slug';

INSERT INTO demo.tiles_z14 (
    country_id,
    z,
    x,
    y,
    geom,
    centroid,
    is_boundary_tile,
    country_overlap_ratio,
    land_sample_count,
    land_sample_ratio,
    tile_class
)
SELECT
    c.id AS country_id,
    t.z,
    t.x,
    t.y,
    t.geom,
    t.centroid,
    t.is_boundary_tile,
    t.country_overlap_ratio,
    t.land_sample_count,
    t.land_sample_ratio,
    t.tile_class
FROM demo.stg_tiles_z14 t
JOIN demo.countries c
  ON c.slug = :'country_slug';
