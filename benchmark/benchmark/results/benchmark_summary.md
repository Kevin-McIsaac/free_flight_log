# Airspace Indexing Benchmark Results

Generated: 2025-09-23T10:42:45.850306

## Overview

- **Total Tests**: 45
- **Strategies**: 3
- **Regions**: 3
- **Runs per Test**: 5

## Performance Summary

| Strategy | Perth (ms) | Continental AU (ms) | France (ms) | Overall Avg (ms) |
|----------|------------|---------------------|-------------|------------------|
| A: Spatial Index Only | 14.6 | 226.8 | 227.2 | 156.2 |
| B: Spatial + Separate Indexes | 12.8 | 130.2 | 149.6 | 97.5 |
| C: Single Covering Index | 17.2 | 95.0 | 98.8 | 70.3 |

## Detailed Analysis

### Perth

Area: 0.24 square degrees

**Strategy A: Spatial Index Only**: 14.60ms average (12-18ms range, σ=2.42)
**Strategy B: Spatial + Separate Indexes**: 12.80ms average (12-15ms range, σ=1.17)
**Strategy C: Single Covering Index**: 17.20ms average (15-19ms range, σ=1.47)

### Continental Australia

Area: 1159.95 square degrees

**Strategy A: Spatial Index Only**: 226.80ms average (188-249ms range, σ=20.92)
**Strategy B: Spatial + Separate Indexes**: 130.20ms average (115-153ms range, σ=12.58)
**Strategy C: Single Covering Index**: 95.00ms average (83-113ms range, σ=10.97)

### France

Area: 145.04 square degrees

**Strategy A: Spatial Index Only**: 227.20ms average (190-264ms range, σ=23.59)
**Strategy B: Spatial + Separate Indexes**: 149.60ms average (124-166ms range, σ=14.60)
**Strategy C: Single Covering Index**: 98.80ms average (89-106ms range, σ=6.55)

## Recommendations

- **Perth**: Best performance with Strategy B: Spatial + Separate Indexes (12.8ms average)
- **Continental Australia**: Best performance with Strategy C: Single Covering Index (95.0ms average)
- **France**: Best performance with Strategy C: Single Covering Index (98.8ms average)

## SQL Index Strategies

### Strategy A: Spatial Index Only
```sql
CREATE INDEX idx_geometry_spatial ON airspace_geometries(
  bounds_west, bounds_east, bounds_south, bounds_north
);
```

### Strategy B: Spatial + Separate Indexes
```sql
CREATE INDEX idx_geometry_spatial ON airspace_geometries(
  bounds_west, bounds_east, bounds_south, bounds_north
);
CREATE INDEX idx_geometry_type_code ON airspace_geometries(type_code);
CREATE INDEX idx_geometry_icao_class ON airspace_geometries(icao_class);
CREATE INDEX idx_geometry_lower_altitude ON airspace_geometries(lower_altitude_ft);
```

### Strategy C: Single Covering Index
```sql
CREATE INDEX idx_geometry_covering ON airspace_geometries(
  bounds_west, bounds_east, bounds_south, bounds_north,
  type_code, icao_class, lower_altitude_ft
);
```