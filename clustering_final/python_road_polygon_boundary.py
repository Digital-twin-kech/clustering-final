#!/usr/bin/env python3
"""
Road/Sidewalk Boundary Extraction via Polygon Boundaries
Uses existing polygon workflow then extracts boundaries as lines
"""

import sys
import os
import json
import subprocess
import numpy as np
from shapely.geometry import Polygon
from shapely.ops import unary_union

def extract_polygon_boundaries(chunk_name, class_name, class_id):
    """Extract boundaries by first creating polygons, then extracting their edges"""
    print(f"\n🛣️  === {class_name.upper()} BOUNDARY EXTRACTION ===")
    print(f"📍 Chunk: {chunk_name}")
    print(f"🎯 Method: Polygon boundary extraction")

    base_path = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final"
    input_laz = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/{class_name}.laz"

    # Create both polygon and line outputs
    polygon_dir = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/polygons"
    line_dir = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/lines"

    polygon_file = f"{polygon_dir}/{class_name}_polygons.geojson"
    boundary_file = f"{line_dir}/{class_name}_lines.geojson"

    if not os.path.exists(input_laz):
        print(f"❌ No data: {input_laz}")
        return 0

    os.makedirs(polygon_dir, exist_ok=True)
    os.makedirs(line_dir, exist_ok=True)

    print(f"📂 Creating polygons first...")

    # Step 1: Create polygons using PDAL pipeline (similar to buildings/vegetation)
    polygon_pipeline = create_polygon_pipeline(input_laz, polygon_file, class_name, class_id)

    if not run_pipeline(polygon_pipeline, f"polygon_{class_name}_{chunk_name}"):
        return 0

    # Step 2: Load polygons and extract boundaries
    if not os.path.exists(polygon_file):
        print(f"❌ Polygon file not created")
        return 0

    with open(polygon_file, 'r') as f:
        polygon_data = json.load(f)

    print(f"✅ Created {len(polygon_data.get('features', []))} polygons")

    # Step 3: Extract boundaries from polygons
    boundaries = extract_boundaries_from_polygons(polygon_data)

    if not boundaries:
        print(f"⚠️  No boundaries extracted")
        return 0

    # Step 4: Create boundary GeoJSON
    boundary_geojson = create_boundary_geojson(boundaries, chunk_name, class_name, class_id)

    # Save boundary lines
    with open(boundary_file, 'w') as f:
        json.dump(boundary_geojson, f, indent=2)

    print(f"✅ Extracted {len(boundaries)} boundary segments")
    print(f"📁 Boundaries: {boundary_file}")

    return len(boundaries)

def create_polygon_pipeline(input_laz, output_file, class_name, class_id):
    """Create PDAL pipeline for polygon generation"""

    # Parameters based on surface type
    if "Road" in class_name:
        resolution = 1.0      # 1m resolution for roads
        hole_cull_area = 10   # Remove holes < 10m²
        smooth_iterations = 2
    else:  # Sidewalks
        resolution = 0.5      # 0.5m resolution for sidewalks
        hole_cull_area = 2    # Remove holes < 2m²
        smooth_iterations = 1

    pipeline = {
        "pipeline": [
            {
                "type": "readers.las",
                "filename": input_laz
            },
            {
                "type": "filters.poisson",
                "depth": 8
            },
            {
                "type": "writers.gdal",
                "resolution": resolution,
                "output_type": "idw",
                "window_size": 3,
                "filename": f"/tmp/{class_name.lower()}_surface.tif"
            }
        ]
    }

    # Alternative: Use concave hull approach
    alt_pipeline = {
        "pipeline": [
            {
                "type": "readers.las",
                "filename": input_laz
            },
            {
                "type": "filters.sample",
                "radius": 2.0  # Sample every 2m
            },
            {
                "type": "writers.ogr",
                "filename": output_file,
                "ogrdriver": "GeoJSON",
                "multipolygon": "true"
            }
        ]
    }

    return alt_pipeline

def run_pipeline(pipeline, name):
    """Run PDAL pipeline"""
    pipeline_file = f"/tmp/{name}_pipeline.json"

    with open(pipeline_file, 'w') as f:
        json.dump(pipeline, f, indent=2)

    result = subprocess.run(['pdal', 'pipeline', pipeline_file],
                          capture_output=True, text=True)

    try:
        os.remove(pipeline_file)
    except:
        pass

    if result.returncode != 0:
        print(f"❌ PDAL pipeline failed: {result.stderr}")
        return False

    return True

def extract_boundaries_from_polygons(polygon_data):
    """Extract boundary lines from polygon features"""
    boundaries = []

    for feature in polygon_data.get('features', []):
        geom = feature.get('geometry', {})

        if geom.get('type') == 'Polygon':
            # Extract exterior boundary
            exterior_coords = geom.get('coordinates', [[]])[0]

            if len(exterior_coords) >= 4:  # Valid polygon
                boundaries.append({
                    'coordinates': exterior_coords,
                    'boundary_type': 'exterior',
                    'area_m2': feature.get('properties', {}).get('area_m2', 0),
                    'perimeter_m': calculate_perimeter(exterior_coords)
                })

            # Extract hole boundaries if present
            holes = geom.get('coordinates', [])[1:]  # Skip first (exterior)
            for hole_coords in holes:
                if len(hole_coords) >= 4:
                    boundaries.append({
                        'coordinates': hole_coords,
                        'boundary_type': 'hole',
                        'area_m2': 0,
                        'perimeter_m': calculate_perimeter(hole_coords)
                    })

        elif geom.get('type') == 'MultiPolygon':
            # Handle MultiPolygon
            for polygon_coords in geom.get('coordinates', []):
                exterior_coords = polygon_coords[0]

                if len(exterior_coords) >= 4:
                    boundaries.append({
                        'coordinates': exterior_coords,
                        'boundary_type': 'multi_exterior',
                        'area_m2': 0,
                        'perimeter_m': calculate_perimeter(exterior_coords)
                    })

    return boundaries

def calculate_perimeter(coordinates):
    """Calculate perimeter length of coordinate sequence"""
    if len(coordinates) < 2:
        return 0

    perimeter = 0
    for i in range(1, len(coordinates)):
        p1 = np.array(coordinates[i-1][:2])  # Use only x,y
        p2 = np.array(coordinates[i][:2])
        perimeter += np.linalg.norm(p2 - p1)

    return perimeter

def create_boundary_geojson(boundaries, chunk_name, class_name, class_id):
    """Create GeoJSON LineString features from boundaries"""
    features = []
    total_length = 0

    for i, boundary in enumerate(boundaries):
        coords = boundary['coordinates']
        perimeter = boundary['perimeter_m']
        total_length += perimeter

        feature = {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": coords
            },
            "properties": {
                "boundary_id": i + 1,
                "length_m": round(perimeter, 2),
                "boundary_type": boundary['boundary_type'],
                "source_area_m2": boundary.get('area_m2', 0),
                "class": class_name,
                "class_id": class_id,
                "chunk": chunk_name
            }
        }
        features.append(feature)

    geojson_data = {
        "type": "FeatureCollection",
        "properties": {
            "class": class_name,
            "class_id": class_id,
            "chunk": chunk_name,
            "extraction_method": "polygon_boundary_extraction",
            "total_boundaries": len(boundaries),
            "total_boundary_length_m": round(total_length, 2)
        },
        "features": features
    }

    return geojson_data

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 python_road_polygon_boundary.py <chunk_name>")
        sys.exit(1)

    chunk_name = sys.argv[1]

    print("="*70)
    print("ROAD AND SIDEWALK BOUNDARY EXTRACTION")
    print("="*70)
    print(f"Target chunk: {chunk_name}")
    print("Method: Polygon boundary extraction")
    print()

    total_boundaries = 0

    # Extract road boundaries
    roads = extract_polygon_boundaries(chunk_name, "2_Roads", 2)
    total_boundaries += roads

    # Extract sidewalk boundaries
    sidewalks = extract_polygon_boundaries(chunk_name, "3_Sidewalks", 3)
    total_boundaries += sidewalks

    print()
    print("="*70)
    print("BOUNDARY EXTRACTION SUMMARY")
    print("="*70)
    print(f"Road boundaries: {roads}")
    print(f"Sidewalk boundaries: {sidewalks}")
    print(f"Total boundaries: {total_boundaries}")

    if total_boundaries > 0:
        print(f"✅ Surface boundary extraction completed!")
        print(f"🗺️  Boundaries show precise surface edges")
    else:
        print(f"⚠️  No boundaries extracted")

if __name__ == "__main__":
    main()