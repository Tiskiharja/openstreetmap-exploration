# Area Analysis (z14 Tiles)

Generated on: 2026-02-27

## Latest Results

### Projected clipped area (`demo.country_tile_area_summary`)

Includes one row per country and `tile_scope`:
- `all_tiles`
- `non_water_tiles` = `interior_land`, `land_dominant`, `coastal_mixed`

| Country | Scope | Tile count | Clipped area (km², projected) |
|---|---|---:|---:|
| Finland | `all_tiles` | 348,733 | 2,072,027.515 |
| Finland | `non_water_tiles` | 312,931 | 1,862,072.212 |
| France | `all_tiles` | 216,340 | 1,283,381.547 |
| France | `non_water_tiles` | 193,913 | 1,154,230.904 |
| Hungary | `all_tiles` | 34,349 | 201,175.473 |
| Hungary | `non_water_tiles` | 34,349 | 201,175.473 |

### Geodesic clipped area (`demo.country_tile_area_summary_geodesic`)

Includes one row per country and `tile_scope`:
- `all_tiles`
- `non_water_tiles` = `interior_land`, `land_dominant`, `coastal_mixed`

| Country | Scope | Tile count | Clipped area (km², geodesic) |
|---|---|---:|---:|
| Finland | `all_tiles` | 348,733 | 391,101.129 |
| Finland | `non_water_tiles` | 312,931 | 344,356.151 |
| France | `all_tiles` | 216,340 | 602,776.262 |
| France | `non_water_tiles` | 193,913 | 543,079.552 |
| Hungary | `all_tiles` | 34,349 | 93,012.615 |
| Hungary | `non_water_tiles` | 34,349 | 93,012.615 |

## How to Run

```bash
make area-summary
make area-summary-geodesic
```
