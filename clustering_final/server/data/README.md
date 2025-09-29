# LiDAR Clustering Visualization Data

This folder contains organized LiDAR clustering data for visualization and server deployment.

## Directory Structure

```
data/
├── centroids/          # Point features (JSON)
│   └── {chunk}_{class}_centroids.json  # Masts and Trees centroids
├── polygons/           # Polygon features (GeoJSON)
│   ├── buildings/     # Building polygons
│   └── vegetation/    # Other vegetation polygons
├── lines/             # Line features (GeoJSON)
│   └── wires/        # Wire line data
├── metadata/          # Processing metadata
├── manifest.json      # Data inventory and statistics
└── README.md         # This file
```

## Data Formats

- **Centroids**: JSON format with UTM coordinates and metadata (Masts and Trees as point features)
- **Polygons**: GeoJSON format with polygon geometries (Buildings and Vegetation)
- **Lines**: GeoJSON format with LineString geometries (Wires)

## Coordinate System

All data uses **UTM Zone 29N (EPSG:29180)** coordinate system for the Morocco region.

## Usage

This organized data structure is designed for:
- Server deployment and visualization
- Database migration (PostGIS)
- API consumption
- Web map rendering

## File Naming Convention

Files follow the pattern: `{chunk}_{class}_{type}.{extension}`

Examples:
- `chunk_1_12_Masts_centroids_clean.json_centroids.json` (Mast centroids)
- `chunk_2_7_Trees_centroids.json_centroids.json` (Tree centroids)
- `chunk_3_buildings_polygons.geojson` (Building polygons)
- `chunk_4_vegetation_polygons.geojson` (Vegetation polygons)
- `chunk_5_wires_lines.geojson` (Wire lines)
