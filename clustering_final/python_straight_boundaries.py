#!/usr/bin/env python3
"""
Straight Boundary Lines for Roads and Sidewalks
Creates clean, straight boundary lines instead of zigzag curves
"""

import sys
import os
import json
import subprocess
import numpy as np
from sklearn.cluster import DBSCAN
from sklearn.linear_model import LinearRegression
from sklearn.decomposition import PCA

def create_straight_boundaries(chunk_name, class_name, class_id):
    """Create clean straight boundary lines for road/sidewalk surfaces"""
    print(f"\n🛣️  === {class_name.upper()} STRAIGHT BOUNDARIES ===")
    print(f"📍 Chunk: {chunk_name}")
    print(f"🎯 Method: Clean straight line boundaries")

    base_path = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final"
    input_laz = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/{class_name}.laz"
    output_dir = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/lines"
    output_file = f"{output_dir}/{class_name}_lines.geojson"

    if not os.path.exists(input_laz):
        print(f"❌ No data: {input_laz}")
        return 0

    os.makedirs(output_dir, exist_ok=True)

    # Load and sample points
    print(f"📂 Loading surface points...")
    temp_file = f"/tmp/{class_name.lower()}_{chunk_name}_straight.txt"

    pipeline = {
        "pipeline": [
            {"type": "readers.las", "filename": input_laz},
            {"type": "filters.sample", "radius": 3.0},  # Sample every 3m for clean lines
            {"type": "writers.text", "format": "csv", "order": "X,Y,Z",
             "keep_unspecified": "false", "filename": temp_file}
        ]
    }

    pipeline_file = f"/tmp/straight_pipeline_{class_name}_{chunk_name}.json"
    with open(pipeline_file, 'w') as f:
        json.dump(pipeline, f)

    result = subprocess.run(['pdal', 'pipeline', pipeline_file],
                          capture_output=True, text=True)

    if result.returncode != 0:
        print(f"❌ PDAL failed: {result.stderr}")
        return 0

    try:
        points = np.loadtxt(temp_file, delimiter=',', skiprows=1)
        print(f"✅ Loaded {len(points):,} points")
    except:
        print(f"❌ Failed to load points")
        return 0

    if len(points) < 50:
        print(f"⚠️  Too few points")
        return 0

    # Create straight boundary lines
    boundaries = create_clean_straight_lines(points, class_name)

    if not boundaries:
        print(f"⚠️  No boundaries created")
        return 0

    # Create GeoJSON
    geojson_data = {
        "type": "FeatureCollection",
        "properties": {
            "class": class_name,
            "class_id": class_id,
            "chunk": chunk_name,
            "extraction_method": "straight_boundary_lines",
            "total_lines": len(boundaries)
        },
        "features": boundaries
    }

    with open(output_file, 'w') as f:
        json.dump(geojson_data, f, indent=2)

    print(f"✅ Created {len(boundaries)} straight boundary lines")

    # Cleanup
    try:
        os.remove(temp_file)
        os.remove(pipeline_file)
    except:
        pass

    return len(boundaries)

def create_clean_straight_lines(points, class_name):
    """Create clean straight boundary lines from point clusters"""
    print(f"🔍 Creating straight boundary lines...")

    xy_points = points[:, :2]

    # Clustering parameters
    if "Road" in class_name:
        eps = 15.0        # Larger clusters for roads
        min_samples = 30
    else:  # Sidewalks
        eps = 12.0        # Increased for sidewalk detection
        min_samples = 15  # Reduced minimum points for sidewalks

    # Cluster points into road/sidewalk segments
    clustering = DBSCAN(eps=eps, min_samples=min_samples).fit(xy_points)
    labels = clustering.labels_
    n_clusters = len(set(labels)) - (1 if -1 in labels else 0)

    print(f"   Found {n_clusters} surface segments")

    boundaries = []

    for cluster_id in range(n_clusters):
        cluster_points = xy_points[labels == cluster_id]

        if len(cluster_points) < 20:
            continue

        # Find the main direction using PCA
        pca = PCA(n_components=2)
        pca.fit(cluster_points)
        main_direction = pca.components_[0]  # First principal component

        # Find the extent along main direction
        centroid = np.mean(cluster_points, axis=0)

        # Project all points onto the main direction
        centered_points = cluster_points - centroid
        projections = np.dot(centered_points, main_direction)

        # Get the extent (min and max projections)
        min_proj = np.min(projections)
        max_proj = np.max(projections)

        # Create straight line endpoints
        start_point = centroid + min_proj * main_direction
        end_point = centroid + max_proj * main_direction

        # Calculate length
        length = np.linalg.norm(end_point - start_point)

        # Only keep reasonable length lines
        min_length = 20.0 if "Road" in class_name else 10.0  # Minimum length threshold

        if length >= min_length:
            # Create straight line feature
            feature = {
                "type": "Feature",
                "geometry": {
                    "type": "LineString",
                    "coordinates": [
                        [float(start_point[0]), float(start_point[1])],
                        [float(end_point[0]), float(end_point[1])]
                    ]
                },
                "properties": {
                    "line_id": len(boundaries) + 1,
                    "length_m": round(length, 2),
                    "surface_points": len(cluster_points),
                    "boundary_type": "straight_boundary",
                    "class": class_name,
                    "class_id": 2 if "Road" in class_name else 3,
                    "chunk": "chunk_1"  # Will be updated by caller
                }
            }
            boundaries.append(feature)

    print(f"   Created {len(boundaries)} straight boundary lines")
    return boundaries

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 python_straight_boundaries.py <chunk_name>")
        sys.exit(1)

    chunk_name = sys.argv[1]

    print("="*70)
    print("STRAIGHT BOUNDARY LINE EXTRACTION")
    print("="*70)
    print(f"Target chunk: {chunk_name}")
    print("Method: Clean straight boundary lines (no zigzag)")
    print()

    total_lines = 0

    # Create straight boundaries for roads
    roads = create_straight_boundaries(chunk_name, "2_Roads", 2)
    total_lines += roads

    # Create straight boundaries for sidewalks
    sidewalks = create_straight_boundaries(chunk_name, "3_Sidewalks", 3)
    total_lines += sidewalks

    print()
    print("="*70)
    print("STRAIGHT BOUNDARY SUMMARY")
    print("="*70)
    print(f"Road boundaries: {roads}")
    print(f"Sidewalk boundaries: {sidewalks}")
    print(f"Total straight lines: {total_lines}")

    if total_lines > 0:
        print(f"✅ Clean straight boundaries created!")
        print(f"🛣️  No more zigzag lines!")
    else:
        print(f"⚠️  No boundaries created")

if __name__ == "__main__":
    main()