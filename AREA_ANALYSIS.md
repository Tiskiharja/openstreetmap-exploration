# Area Analysis (z14 Tiles)

Generated on: 2026-02-19

## Latest Results

### Projected clipped area (`demo.country_tile_area_summary`)

Includes one row per country and `tile_scope`:
- `all_tiles`
- `non_water_tiles`

| Country | Tile count | Clipped area (km², projected) |
|---|---:|---:|
| Finland | 348,733 | 2,072,027.515 |
| France | 216,340 | 1,283,381.547 |
| Hungary | 34,349 | 201,175.473 |

### Geodesic clipped area (`demo.country_tile_area_summary_geodesic`)

Includes one row per country and `tile_scope`:
- `all_tiles`
- `non_water_tiles`

| Country | Tile count | Clipped area (km², geodesic) |
|---|---:|---:|
| Finland | 348,733 | 391,101.129 |
| France | 216,340 | 602,776.262 |
| Hungary | 34,349 | 93,012.615 |

## How to Run

```bash
make area-summary
make area-summary-geodesic
```
