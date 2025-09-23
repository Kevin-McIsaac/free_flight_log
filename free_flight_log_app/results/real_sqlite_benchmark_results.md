# Real SQLite Airspace Indexing Benchmark Results

Generated: 2025-09-23T11:06:59.627240
Database: **Real SQLite with FFI** (actual database operations)
Schema: Production AirspaceDiskCache schema

## 🎯 Executive Summary

**Best Overall Performance**: Strategy A: Spatial Index Only (20.9ms average)

## 📈 Performance Summary

| Strategy | Perth (ms) | Continental AU (ms) | France (ms) | Overall Avg (ms) |
|----------|------------|---------------------|-------------|------------------|
| **A: Spatial Index Only** | 0.6 | 44.0 | 18.0 | 20.9 |
| **B: Spatial + Separate Indexes** | 8.2 | 44.2 | 24.6 | 25.7 |
| **C: Single Covering Index** | 1.2 | 48.6 | 17.4 | 22.4 |

## 🔍 Real EXPLAIN QUERY PLAN Analysis

These are **actual SQLite query execution plans**, not simulations:

### Strategy A: Spatial Index Only

**Query Execution Plan:**
```
SEARCH airspace_geometries USING INDEX idx_geometry_spatial (bounds_west<?)
USE TEMP B-TREE FOR ORDER BY
```

### Strategy B: Spatial + Separate Indexes

**Query Execution Plan:**
```
SCAN airspace_geometries USING INDEX idx_geometry_lower_altitude
```

### Strategy C: Single Covering Index

**Query Execution Plan:**
```
SEARCH airspace_geometries USING INDEX idx_geometry_covering (bounds_west<?)
USE TEMP B-TREE FOR ORDER BY
```

## 📊 Detailed Performance Analysis

### Perth (Perth metropolitan area (small))

**Strategy A: Spatial Index Only**:
- Average: 0.60ms
- Range: 0-3ms
- Std Dev: 1.20ms
- Results: 1 airspaces

**Strategy B: Spatial + Separate Indexes**:
- Average: 8.20ms
- Range: 5-13ms
- Std Dev: 2.79ms
- Results: 1 airspaces

**Strategy C: Single Covering Index**:
- Average: 1.20ms
- Range: 0-3ms
- Std Dev: 1.17ms
- Results: 1 airspaces

### Continental Australia (Australian mainland (large))

**Strategy A: Spatial Index Only**:
- Average: 44.00ms
- Range: 37-48ms
- Std Dev: 3.85ms
- Results: 5927 airspaces

**Strategy B: Spatial + Separate Indexes**:
- Average: 44.20ms
- Range: 34-59ms
- Std Dev: 9.11ms
- Results: 5927 airspaces

**Strategy C: Single Covering Index**:
- Average: 48.60ms
- Range: 45-51ms
- Std Dev: 2.06ms
- Results: 5927 airspaces

### France (Metropolitan France (medium))

**Strategy A: Spatial Index Only**:
- Average: 18.00ms
- Range: 11-24ms
- Std Dev: 5.40ms
- Results: 1643 airspaces

**Strategy B: Spatial + Separate Indexes**:
- Average: 24.60ms
- Range: 14-36ms
- Std Dev: 9.24ms
- Results: 1643 airspaces

**Strategy C: Single Covering Index**:
- Average: 17.40ms
- Range: 9-43ms
- Std Dev: 12.91ms
- Results: 1643 airspaces

## 🚀 Production Implementation

Based on real SQLite performance measurements:

```sql
-- Replace current index in AirspaceDiskCache._onCreate()
-- FROM:
CREATE INDEX idx_geometry_spatial ON airspace_geometries(
  bounds_west, bounds_east, bounds_south, bounds_north
);

-- TO:
CREATE INDEX idx_geometry_covering ON airspace_geometries(
  bounds_west, bounds_east, bounds_south, bounds_north,
  type_code, icao_class, lower_altitude_ft
);
```

### Expected Performance Impact

- **Small regions (Perth)**: -100% faster
- **Medium regions (France)**: 3% faster
- **Large regions (Continental AU)**: -10% faster

**Overall**: -7% performance improvement