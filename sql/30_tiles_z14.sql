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

DROP TABLE IF EXISTS demo.stg_tiles_z14;

CREATE TABLE demo.stg_tiles_z14 AS
WITH bbox AS (
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
)
SELECT
    c.z,
    c.x,
    c.y,
    c.geom,
    ST_Centroid(c.geom)::geometry(Point, 3857) AS centroid
FROM candidates c
JOIN demo.stg_country_boundary cb
  ON ST_Intersects(c.geom, cb.geom);

ALTER TABLE demo.stg_tiles_z14
    ADD CONSTRAINT stg_tiles_z14_pk PRIMARY KEY (z, x, y);

CREATE INDEX stg_tiles_z14_geom_gix ON demo.stg_tiles_z14 USING GIST (geom);
CREATE INDEX stg_tiles_z14_centroid_gix ON demo.stg_tiles_z14 USING GIST (centroid);

DELETE FROM demo.tiles_z14 t
USING demo.countries c
WHERE t.country_id = c.id
  AND c.slug = :'country_slug';

INSERT INTO demo.tiles_z14 (country_id, z, x, y, geom, centroid)
SELECT
    c.id AS country_id,
    t.z,
    t.x,
    t.y,
    t.geom,
    t.centroid
FROM demo.stg_tiles_z14 t
JOIN demo.countries c
  ON c.slug = :'country_slug';
