# Berkan Dataset - Unified Server Data

## Overview
This directory contains the unified processed LiDAR data from the **data-last-berkan** dataset, organized for visualization server deployment.

## Dataset Information
- **Source**: `/home/prodair/Downloads/data-last-berkan/data-last-berkan`
- **Chunks Processed**: 9 chunks (chunk_9 through chunk_17)
- **Processing Date**: 2025-10-01
- **Coordinate System**: UTM Zone 29N (EPSG:32629)
- **Region**: Western Morocco

## Directory Structure

```
data_new_2/
├── centroids/              # Trees & Masts centroids (18 files)
│   ├── berkan_chunk_9_7_Trees_centroids.json
│   ├── berkan_chunk_9_12_Masts_centroids.json
│   └── ...
├── polygons/
│   ├── buildings/         # Building footprints (9 files)
│   │   ├── berkan_chunk_9_buildings_polygons.geojson
│   │   └── ...
│   └── vegetation/        # Vegetation areas (9 files)
│       ├── berkan_chunk_9_vegetation_polygons.geojson
│       └── ...
├── lines/
│   └── wires/            # Wire infrastructure (9 files)
│       ├── berkan_chunk_9_wires_lines.geojson
│       └── ...
└── manifest.json         # Dataset metadata
```

## File Naming Convention
- **Pattern**: `berkan_chunk_<N>_<class>_<type>.<ext>`
- **Examples**:
  - `berkan_chunk_9_7_Trees_centroids.json`
  - `berkan_chunk_10_buildings_polygons.geojson`
  - `berkan_chunk_11_wires_lines.geojson`

## Statistics

| Category | Count | Description |
|----------|-------|-------------|
| **Total Files** | 45 | All processed files |
| **Centroids** | 18 | Trees + Masts point features |
| **Polygons** | 18 | Buildings (9) + Vegetation (9) |
| **Lines** | 9 | Wire infrastructure |

### Chunks Summary

| Chunk | Trees | Masts | Buildings | Vegetation | Wires |
|-------|-------|-------|-----------|------------|-------|
| 9 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 10 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 11 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 12 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 13 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 14 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 15 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 16 | ✅ | ✅ | ✅ | ✅ | ✅ |
| 17 | ✅ | ✅ | ✅ | ✅ | ✅ |

## Processing Methods

### Trees & Masts (Centroids)
- **Method**: Lightweight 2D projection clustering
- **Algorithm**: DBSCAN with Z-axis elimination
- **Performance**: 15x faster than 3D clustering
- **Output**: JSON centroids with point counts

### Buildings (Polygons)
- **Method**: Enhanced footprint-based extraction
- **Algorithm**: Alpha shapes (concave hull) + Douglas-Peucker simplification
- **Features**: Natural boundaries, no road extensions
- **Output**: GeoJSON polygons with precise footprints

### Vegetation (Polygons)
- **Method**: Natural boundary detection
- **Algorithm**: Balanced filtering + concave hull
- **Features**: Curved boundaries following actual vegetation
- **Output**: GeoJSON polygons with natural shapes

### Wires (Lines)
- **Method**: Height-aware 3D line segmentation
- **Algorithm**: DBSCAN 3D + PCA-based line generation
- **Features**: Continuous lines following wire paths with natural sag
- **Output**: GeoJSON LineString geometries

## Data Quality
- ✅ Comprehensive coverage across all 9 chunks
- ✅ Strict quality filters applied
- ✅ No duplicates or overlapping instances
- ✅ Sub-meter coordinate precision (UTM)
- ✅ Validated geometries

## Coordinate System
- **Input**: UTM Zone 29N (EPSG:32629) in meters
- **Storage**: Preserved UTM coordinates in all files
- **Visualization**: Auto-converted to WGS84 (EPSG:4326) by server

## Usage

### For Visualization Server
The data is ready to be loaded by the visualization server. The server will:
1. Read all JSON/GeoJSON files from subdirectories
2. Convert UTM coordinates to WGS84 for web display
3. Apply class-specific styling and colors
4. Enable interactive map features

### File Format Examples

**Centroids (Trees/Masts)**:
```json
{
  "class": "7_Trees",
  "chunk": "chunk_9",
  "centroids": [
    {
      "object_id": 1,
      "centroid_x": 500123.456,
      "centroid_y": 3850234.789,
      "centroid_z": 195.5,
      "point_count": 847
    }
  ]
}
```

**Polygons (Buildings/Vegetation)**:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[x1,y1], [x2,y2], ...]]
      },
      "properties": {
        "polygon_id": 1,
        "area_m2": 154.3,
        "perimeter_m": 52.1
      }
    }
  ]
}
```

**Lines (Wires)**:
```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [[x1,y1], [x2,y2], ...]
      },
      "properties": {
        "line_id": 1,
        "length_m": 44.53,
        "aspect_ratio": 32.11
      }
    }
  ]
}
```

## Generation Script
Data was unified using: `unify_berkan_data.py`

## Next Steps
1. ✅ Data unified and organized
2. ⏭️ Load into visualization server
3. ⏭️ Validate in local visualization
4. ⏭️ Migrate to production PostGIS database
5. ⏭️ Update production visualization server

---
**Generated**: 2025-10-01  
**Dataset**: data-last-berkan  
**Method**: Revolutionary 2D Lightweight Clustering Pipeline
