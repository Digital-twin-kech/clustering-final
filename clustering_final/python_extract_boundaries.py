#!/usr/bin/env python3
"""
Extract Boundaries from Surface Polygons
Converts polygon edges to precise boundary lines
"""

import sys
import os
import json
import subprocess
import numpy as np

def extract_boundaries_from_existing_polygons(chunk_name, class_name, class_id):
    """Extract boundaries from existing polygon files"""
    print(f"\n📐 === {class_name.upper()} BOUNDARY EXTRACTION ===")
    print(f"📍 Chunk: {chunk_name}")
    print(f"🎯 Method: Extract from existing polygons")

    base_path = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final"

    # Check for existing polygons first
    polygon_file = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/polygons/{class_name}_polygons.geojson"

    # Output boundary lines
    line_dir = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/lines"
    boundary_file = f"{line_dir}/{class_name}_lines.geojson"

    os.makedirs(line_dir, exist_ok=True)

    # If polygons exist, extract boundaries from them
    if os.path.exists(polygon_file):
        print(f"✅ Found existing polygons: {polygon_file}")
        return extract_from_polygon_file(polygon_file, boundary_file, chunk_name, class_name, class_id)

    # If no polygons, create them first using PDAL
    print(f"📂 Creating polygons first...")

    input_laz = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/{class_name}.laz"

    if not os.path.exists(input_laz):
        print(f"❌ No data: {input_laz}")
        return 0

    # Create polygons using simple PDAL approach
    polygon_dir = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/polygons"
    os.makedirs(polygon_dir, exist_ok=True)

    if create_polygons_with_pdal(input_laz, polygon_file, class_name):
        return extract_from_polygon_file(polygon_file, boundary_file, chunk_name, class_name, class_id)

    return 0

def create_polygons_with_pdal(input_laz, output_file, class_name):
    """Create polygons using PDAL boundary filter"""
    print(f"   Running PDAL polygon creation...")

    # Parameters for different surface types
    if "Road" in class_name:
        edge_length = 5.0    # Larger edge length for roads
        hole_cull = 25.0     # Remove small holes
    else:  # Sidewalks
        edge_length = 2.0    # Smaller edge length for sidewalks
        hole_cull = 4.0      # Keep smaller features

    pipeline = {
        "pipeline": [
            {
                "type": "readers.las",
                "filename": input_laz
            },
            {
                "type": "filters.sample",
                "radius": 1.5  # Sample every 1.5m for performance
            },
            {
                "type": "filters.boundary",
                "edge_length": edge_length,
                "hole_cull_area": hole_cull
            },
            {
                "type": "writers.ogr",
                "filename": output_file,
                "ogrdriver": "GeoJSON"
            }
        ]
    }

    pipeline_file = f"/tmp/polygon_creation_{class_name}.json"

    with open(pipeline_file, 'w') as f:
        json.dump(pipeline, f, indent=2)

    result = subprocess.run(['pdal', 'pipeline', pipeline_file],
                          capture_output=True, text=True)

    try:
        os.remove(pipeline_file)
    except:
        pass

    if result.returncode != 0:
        print(f"   ❌ PDAL polygon creation failed: {result.stderr}")
        return False

    if os.path.exists(output_file):
        print(f"   ✅ Polygons created successfully")
        return True

    return False

def extract_from_polygon_file(polygon_file, boundary_file, chunk_name, class_name, class_id):
    """Extract boundary lines from polygon GeoJSON file"""

    try:
        with open(polygon_file, 'r') as f:
            polygon_data = json.load(f)
    except:
        print(f"❌ Failed to load polygon file")
        return 0

    features = polygon_data.get('features', [])
    print(f"   Processing {len(features)} polygon features...")

    if not features:
        print(f"   No polygon features found")
        return 0

    boundaries = []
    total_length = 0

    for i, feature in enumerate(features):
        geom = feature.get('geometry', {})

        if geom.get('type') == 'Polygon':
            # Extract exterior boundary (main edge)
            exterior_coords = geom.get('coordinates', [[]])[0]

            if len(exterior_coords) >= 4:
                length = calculate_line_length(exterior_coords)
                total_length += length

                # Create boundary line feature
                boundary_feature = {
                    "type": "Feature",
                    "geometry": {
                        "type": "LineString",
                        "coordinates": exterior_coords
                    },
                    "properties": {
                        "boundary_id": len(boundaries) + 1,
                        "length_m": round(length, 2),
                        "boundary_type": "exterior_edge",
                        "source_polygon_id": i + 1,
                        "class": class_name,
                        "class_id": class_id,
                        "chunk": chunk_name
                    }
                }
                boundaries.append(boundary_feature)

                # Also extract interior holes as separate boundaries
                holes = geom.get('coordinates', [])[1:]  # Skip exterior ring
                for j, hole_coords in enumerate(holes):
                    if len(hole_coords) >= 4:
                        hole_length = calculate_line_length(hole_coords)
                        total_length += hole_length

                        hole_feature = {
                            "type": "Feature",
                            "geometry": {
                                "type": "LineString",
                                "coordinates": hole_coords
                            },
                            "properties": {
                                "boundary_id": len(boundaries) + 1,
                                "length_m": round(hole_length, 2),
                                "boundary_type": "interior_hole",
                                "source_polygon_id": i + 1,
                                "hole_id": j + 1,
                                "class": class_name,
                                "class_id": class_id,
                                "chunk": chunk_name
                            }
                        }
                        boundaries.append(hole_feature)

        elif geom.get('type') == 'MultiPolygon':
            # Handle MultiPolygon features
            for poly_idx, polygon_coords in enumerate(geom.get('coordinates', [])):
                exterior_coords = polygon_coords[0]  # First ring is exterior

                if len(exterior_coords) >= 4:
                    length = calculate_line_length(exterior_coords)
                    total_length += length

                    boundary_feature = {
                        "type": "Feature",
                        "geometry": {
                            "type": "LineString",
                            "coordinates": exterior_coords
                        },
                        "properties": {
                            "boundary_id": len(boundaries) + 1,
                            "length_m": round(length, 2),
                            "boundary_type": "multi_exterior_edge",
                            "source_polygon_id": i + 1,
                            "multi_part_id": poly_idx + 1,
                            "class": class_name,
                            "class_id": class_id,
                            "chunk": chunk_name
                        }
                    }
                    boundaries.append(boundary_feature)

    # Create boundary GeoJSON
    boundary_geojson = {
        "type": "FeatureCollection",
        "properties": {
            "class": class_name,
            "class_id": class_id,
            "chunk": chunk_name,
            "extraction_method": "polygon_edge_extraction",
            "source_polygons": len(features),
            "total_boundaries": len(boundaries),
            "total_boundary_length_m": round(total_length, 2)
        },
        "features": boundaries
    }

    # Save boundary lines
    with open(boundary_file, 'w') as f:
        json.dump(boundary_geojson, f, indent=2)

    print(f"✅ Extracted {len(boundaries)} boundary segments")
    print(f"📊 Total boundary length: {total_length:.1f}m")
    print(f"📁 Saved to: {boundary_file}")

    return len(boundaries)

def calculate_line_length(coordinates):
    """Calculate total length of line in meters"""
    if len(coordinates) < 2:
        return 0.0

    total_length = 0.0
    for i in range(1, len(coordinates)):
        p1 = np.array(coordinates[i-1][:2])  # Use only x,y
        p2 = np.array(coordinates[i][:2])
        total_length += np.linalg.norm(p2 - p1)

    return total_length

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 python_extract_boundaries.py <chunk_name>")
        sys.exit(1)

    chunk_name = sys.argv[1]

    print("="*70)
    print("SURFACE BOUNDARY EXTRACTION FROM POLYGONS")
    print("="*70)
    print(f"Target chunk: {chunk_name}")
    print("Method: Extract precise boundaries from polygon edges")
    print()

    total_boundaries = 0

    # Extract road boundaries
    roads = extract_boundaries_from_existing_polygons(chunk_name, "2_Roads", 2)
    total_boundaries += roads

    # Extract sidewalk boundaries
    sidewalks = extract_boundaries_from_existing_polygons(chunk_name, "3_Sidewalks", 3)
    total_boundaries += sidewalks

    print()
    print("="*70)
    print("BOUNDARY EXTRACTION SUMMARY")
    print("="*70)
    print(f"Road boundaries: {roads}")
    print(f"Sidewalk boundaries: {sidewalks}")
    print(f"Total boundaries: {total_boundaries}")

    if total_boundaries > 0:
        print(f"✅ Precise boundary extraction completed!")
        print(f"🗺️  Boundaries show exact surface edges")
    else:
        print(f"⚠️  No boundaries extracted")

if __name__ == "__main__":
    main()