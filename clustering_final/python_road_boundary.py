#!/usr/bin/env python3
"""
Road and Sidewalk Boundary Extraction
Extracts precise edge boundaries from surface point clouds
"""

import sys
import os
import json
import subprocess
import numpy as np
from scipy.spatial import ConvexHull, cKDTree
from sklearn.cluster import DBSCAN
from shapely.geometry import Polygon, LineString
from shapely.ops import unary_union
import alphashape

def extract_surface_boundaries(chunk_name, class_name, class_id):
    """Extract precise boundaries from road/sidewalk surface points"""
    print(f"\n🛣️  === {class_name.upper()} BOUNDARY EXTRACTION ===")
    print(f"📍 Chunk: {chunk_name}")
    print(f"🎯 Method: Surface boundary detection")

    base_path = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final"
    input_laz = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/{class_name}.laz"
    output_dir = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/lines"
    output_file = f"{output_dir}/{class_name}_lines.geojson"

    if not os.path.exists(input_laz):
        print(f"❌ No data: {input_laz}")
        return 0

    os.makedirs(output_dir, exist_ok=True)

    # Load points with sampling for performance
    print(f"📂 Loading surface points...")
    temp_file = f"/tmp/{class_name.lower()}_{chunk_name}_boundary.txt"

    # Use denser sampling for boundary detection (every 1m)
    pipeline = {
        "pipeline": [
            {"type": "readers.las", "filename": input_laz},
            {"type": "filters.sample", "radius": 1.0},  # Sample every 1m for accuracy
            {"type": "writers.text", "format": "csv", "order": "X,Y,Z",
             "keep_unspecified": "false", "filename": temp_file}
        ]
    }

    pipeline_file = f"/tmp/boundary_pipeline_{class_name}_{chunk_name}.json"
    with open(pipeline_file, 'w') as f:
        json.dump(pipeline, f)

    result = subprocess.run(['pdal', 'pipeline', pipeline_file],
                          capture_output=True, text=True)

    if result.returncode != 0:
        print(f"❌ PDAL failed: {result.stderr}")
        return 0

    try:
        points = np.loadtxt(temp_file, delimiter=',', skiprows=1)
        print(f"✅ Loaded {len(points):,} surface points")
    except:
        print(f"❌ Failed to load points")
        return 0

    if len(points) < 100:
        print(f"⚠️  Too few points for boundary extraction")
        return 0

    # Extract boundaries using surface clustering + alpha shapes
    boundaries = extract_alpha_shape_boundaries(points, class_name)

    if not boundaries:
        print(f"⚠️  No boundaries extracted")
        return 0

    # Create GeoJSON
    geojson_data = create_boundary_geojson(boundaries, chunk_name, class_name, class_id)

    # Save
    with open(output_file, 'w') as f:
        json.dump(geojson_data, f, indent=2)

    print(f"✅ Extracted {len(boundaries)} boundary segments")
    print(f"📁 Saved to: {output_file}")

    # Cleanup
    try:
        os.remove(temp_file)
        os.remove(pipeline_file)
    except:
        pass

    return len(boundaries)

def extract_alpha_shape_boundaries(points, class_name):
    """Extract boundaries using alpha shapes for precise edge detection"""
    print(f"🔍 Extracting boundaries using alpha shape method...")

    xy_points = points[:, :2]  # Use only X,Y for surface boundary

    # Parameters based on surface type
    if "Road" in class_name:
        eps = 8.0          # Roads: larger connected components
        min_samples = 50   # More points needed
        alpha = 15.0       # Moderate alpha for road edges
    else:  # Sidewalks
        eps = 4.0          # Sidewalks: smaller components
        min_samples = 30   # Fewer points needed
        alpha = 8.0        # Smaller alpha for precise sidewalk edges

    # Step 1: Cluster surface points into connected components
    clustering = DBSCAN(eps=eps, min_samples=min_samples).fit(xy_points)
    labels = clustering.labels_
    n_clusters = len(set(labels)) - (1 if -1 in labels else 0)

    print(f"   Found {n_clusters} surface clusters")

    boundaries = []

    # Step 2: For each surface cluster, extract boundary
    for cluster_id in range(n_clusters):
        cluster_points = xy_points[labels == cluster_id]

        if len(cluster_points) < 20:
            continue

        try:
            # Create alpha shape to get precise boundary
            alpha_shape = alphashape.alphashape(cluster_points, alpha)

            # Extract boundary coordinates
            if hasattr(alpha_shape, 'exterior'):
                # Single polygon
                boundary_coords = list(alpha_shape.exterior.coords)
                if len(boundary_coords) >= 4:  # Valid polygon
                    boundaries.append({
                        'coordinates': [[float(x), float(y)] for x, y in boundary_coords],
                        'surface_points': len(cluster_points),
                        'boundary_type': 'closed_boundary'
                    })

            elif hasattr(alpha_shape, 'geoms'):
                # MultiPolygon - extract all boundaries
                for geom in alpha_shape.geoms:
                    if hasattr(geom, 'exterior'):
                        boundary_coords = list(geom.exterior.coords)
                        if len(boundary_coords) >= 4:
                            boundaries.append({
                                'coordinates': [[float(x), float(y)] for x, y in boundary_coords],
                                'surface_points': len(cluster_points),
                                'boundary_type': 'multi_boundary'
                            })

        except Exception as e:
            # Fallback to convex hull if alpha shape fails
            print(f"   Alpha shape failed for cluster {cluster_id}, using convex hull")
            try:
                hull = ConvexHull(cluster_points)
                hull_coords = cluster_points[hull.vertices]
                # Close the boundary
                hull_coords = np.vstack([hull_coords, hull_coords[0]])

                boundaries.append({
                    'coordinates': [[float(x), float(y)] for x, y in hull_coords],
                    'surface_points': len(cluster_points),
                    'boundary_type': 'convex_hull'
                })
            except:
                print(f"   Failed to extract boundary for cluster {cluster_id}")
                continue

    print(f"   Extracted {len(boundaries)} boundary segments")
    return boundaries

def create_boundary_geojson(boundaries, chunk_name, class_name, class_id):
    """Create GeoJSON with boundary line strings"""

    features = []
    total_length = 0

    for i, boundary in enumerate(boundaries):
        # Convert closed boundary to LineString
        coords = boundary['coordinates']

        # Calculate boundary length
        length = 0
        for j in range(1, len(coords)):
            p1 = np.array(coords[j-1])
            p2 = np.array(coords[j])
            length += np.linalg.norm(p2 - p1)

        total_length += length

        feature = {
            "type": "Feature",
            "geometry": {
                "type": "LineString",  # Use LineString for boundary visualization
                "coordinates": coords
            },
            "properties": {
                "boundary_id": i + 1,
                "length_m": round(length, 2),
                "surface_points": boundary['surface_points'],
                "boundary_type": boundary['boundary_type'],
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
            "extraction_method": "alpha_shape_boundary",
            "total_boundaries": len(boundaries),
            "total_boundary_length_m": round(total_length, 2)
        },
        "features": features
    }

    return geojson_data

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 python_road_boundary.py <chunk_name>")
        sys.exit(1)

    chunk_name = sys.argv[1]

    print("="*70)
    print("ROAD AND SIDEWALK BOUNDARY EXTRACTION")
    print("="*70)
    print(f"Target chunk: {chunk_name}")
    print("Method: Alpha shape boundary detection")
    print()

    # Process roads and sidewalks with proper boundary extraction
    total_boundaries = 0

    roads_extracted = extract_surface_boundaries(chunk_name, "2_Roads", 2)
    total_boundaries += roads_extracted

    sidewalks_extracted = extract_surface_boundaries(chunk_name, "3_Sidewalks", 3)
    total_boundaries += sidewalks_extracted

    print()
    print("="*70)
    print("BOUNDARY EXTRACTION SUMMARY")
    print("="*70)
    print(f"Road boundaries: {roads_extracted}")
    print(f"Sidewalk boundaries: {sidewalks_extracted}")
    print(f"Total boundaries: {total_boundaries}")

    if total_boundaries > 0:
        print(f"✅ Boundary extraction completed successfully!")
        print(f"🗺️  Boundaries represent precise surface edges")
    else:
        print(f"⚠️  No boundaries extracted")

if __name__ == "__main__":
    main()