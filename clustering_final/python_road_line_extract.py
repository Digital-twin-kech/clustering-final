#!/usr/bin/env python3
"""
Road and Sidewalk Line Extraction for LiDAR Point Clouds
Creates line segments for road and sidewalk infrastructure
Optimized for continuous linear surface structures
"""

import sys
import os
import json
import subprocess
import numpy as np
import math
from scipy.spatial import cKDTree
from sklearn.cluster import DBSCAN
from sklearn.linear_model import RANSACRegressor

def extract_road_lines(chunk_name, class_name, class_id):
    """
    Extract line segments for road-like classes (roads, sidewalks)
    """
    print(f"\n🛣️  === {class_name.upper()} LINE EXTRACTION ===")
    print(f"📍 Chunk: {chunk_name}")
    print(f"🎯 Method: Surface-based line extraction")
    print(f"📊 Extracting {class_name.lower()} lines...")

    # Paths
    base_path = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final"
    input_laz = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/{class_name}.laz"
    output_dir = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/lines"
    output_file = f"{output_dir}/{class_name}_lines.geojson"

    # Check if data exists
    if not os.path.exists(input_laz):
        print(f"❌ No {class_name.lower()} data found: {input_laz}")
        return 0

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Load points using PDAL pipeline
    print(f"📂 Loading {class_name.lower()} point data...")
    try:
        # Create temporary text file for points
        temp_points_file = f"/tmp/{class_name.lower()}_points_{chunk_name}.txt"

        # PDAL pipeline to extract points as text
        pipeline = {
            "pipeline": [
                {
                    "type": "readers.las",
                    "filename": input_laz
                },
                {
                    "type": "writers.text",
                    "format": "csv",
                    "order": "X,Y,Z",
                    "keep_unspecified": "false",
                    "filename": temp_points_file
                }
            ]
        }

        # Write pipeline to temporary file
        pipeline_file = f"/tmp/{class_name.lower()}_pipeline_{chunk_name}.json"
        with open(pipeline_file, 'w') as f:
            json.dump(pipeline, f, indent=2)

        # Execute PDAL pipeline
        result = subprocess.run(['pdal', 'pipeline', pipeline_file],
                              capture_output=True, text=True)

        if result.returncode != 0:
            print(f"❌ PDAL pipeline failed: {result.stderr}")
            return 0

        # Load points from CSV
        points = np.loadtxt(temp_points_file, delimiter=',', skiprows=1)
        print(f"✅ Loaded {len(points):,} points")

        # Clean up temp files
        os.remove(temp_points_file)
        os.remove(pipeline_file)

    except Exception as e:
        print(f"❌ Failed to load point data: {e}")
        return 0

    # Extract line segments using spatial clustering and path following
    lines = extract_linear_paths(points, class_name)

    if not lines:
        print(f"⚠️  No lines extracted from {class_name.lower()}")
        return 0

    # Create GeoJSON output
    geojson_data = create_geojson(lines, chunk_name, class_name, class_id)

    # Save GeoJSON
    with open(output_file, 'w') as f:
        json.dump(geojson_data, f, indent=2)

    print(f"✅ Saved {len(lines)} {class_name.lower()} lines to: {output_file}")
    return len(lines)

def extract_linear_paths(points, class_name):
    """
    Extract linear paths from point cloud using clustering and path following
    Optimized for ground-level linear features like roads and sidewalks
    """
    print(f"🔍 Extracting linear paths from {class_name.lower()}...")

    if len(points) < 100:
        print(f"⚠️  Too few points ({len(points)}) for line extraction")
        return []

    # Parameters for road/sidewalk line extraction
    if "Road" in class_name:
        # Roads: wider, more continuous
        eps = 3.0          # 3m clustering radius
        min_samples = 50   # Minimum points per cluster
        line_simplify = 5.0  # Simplify lines to 5m segments
    else:  # Sidewalks
        # Sidewalks: narrower, potentially fragmented
        eps = 2.0          # 2m clustering radius
        min_samples = 30   # Minimum points per cluster
        line_simplify = 3.0  # Simplify lines to 3m segments

    # Step 1: Spatial clustering to identify connected components
    print(f"   Clustering with eps={eps}m, min_samples={min_samples}")

    # Use XY coordinates only for surface features
    xy_points = points[:, :2]
    clustering = DBSCAN(eps=eps, min_samples=min_samples).fit(xy_points)

    labels = clustering.labels_
    n_clusters = len(set(labels)) - (1 if -1 in labels else 0)
    n_noise = list(labels).count(-1)

    print(f"   Found {n_clusters} clusters, {n_noise} noise points")

    if n_clusters == 0:
        return []

    # Step 2: For each cluster, extract linear skeleton
    lines = []

    for cluster_id in range(n_clusters):
        cluster_mask = (labels == cluster_id)
        cluster_points = points[cluster_mask]

        if len(cluster_points) < min_samples:
            continue

        # Extract centerline from point cluster
        centerline = extract_centerline(cluster_points, line_simplify)

        if centerline and len(centerline) >= 2:
            lines.append({
                'coordinates': centerline,
                'point_count': len(cluster_points),
                'length_m': calculate_line_length(centerline)
            })

    print(f"   Extracted {len(lines)} line segments")
    return lines

def extract_centerline(points, simplify_distance):
    """
    Extract centerline from a cluster of points representing a linear feature
    """
    if len(points) < 10:
        return None

    # Project points to 2D and find the principal axis
    xy_points = points[:, :2]

    # Find bounding box and principal direction
    centroid = np.mean(xy_points, axis=0)

    # Use PCA to find main direction
    centered_points = xy_points - centroid
    cov_matrix = np.cov(centered_points.T)
    eigenvalues, eigenvectors = np.linalg.eig(cov_matrix)

    # Main direction is the eigenvector with largest eigenvalue
    main_direction = eigenvectors[:, np.argmax(eigenvalues)]

    # Project points onto main axis
    projections = np.dot(centered_points, main_direction)

    # Sort points along main axis
    sort_indices = np.argsort(projections)
    sorted_points = points[sort_indices]

    # Simplify line by sampling every few points
    n_samples = max(2, len(sorted_points) // max(1, int(simplify_distance)))
    sample_indices = np.linspace(0, len(sorted_points)-1, n_samples, dtype=int)

    centerline_points = sorted_points[sample_indices]

    # Return as list of [x, y] coordinates (drop Z for lines)
    return [[float(pt[0]), float(pt[1])] for pt in centerline_points]

def calculate_line_length(coordinates):
    """Calculate total length of line in meters"""
    if len(coordinates) < 2:
        return 0.0

    total_length = 0.0
    for i in range(1, len(coordinates)):
        p1 = np.array(coordinates[i-1])
        p2 = np.array(coordinates[i])
        total_length += np.linalg.norm(p2 - p1)

    return total_length

def create_geojson(lines, chunk_name, class_name, class_id):
    """Create GeoJSON FeatureCollection from extracted lines"""

    features = []

    for i, line in enumerate(lines):
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": line['coordinates']
            },
            "properties": {
                "line_id": i + 1,
                "length_m": round(line['length_m'], 2),
                "point_count": line['point_count'],
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
            "extraction_method": "surface_line_extraction",
            "total_lines": len(lines),
            "total_length_m": round(sum(line['length_m'] for line in lines), 2)
        },
        "features": features
    }

    return geojson_data

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 python_road_line_extract.py <chunk_name>")
        print("Example: python3 python_road_line_extract.py chunk_1")
        sys.exit(1)

    chunk_name = sys.argv[1]

    print("="*60)
    print("ROAD AND SIDEWALK LINE EXTRACTION")
    print("="*60)
    print(f"Target chunk: {chunk_name}")
    print()

    # Process both roads and sidewalks
    total_lines = 0

    # Extract roads (class 2) - dark grey
    roads_extracted = extract_road_lines(chunk_name, "2_Roads", 2)
    total_lines += roads_extracted

    # Extract sidewalks (class 3) - light grey
    sidewalks_extracted = extract_road_lines(chunk_name, "3_Sidewalks", 3)
    total_lines += sidewalks_extracted

    print()
    print("="*60)
    print("EXTRACTION SUMMARY")
    print("="*60)
    print(f"Roads lines extracted: {roads_extracted}")
    print(f"Sidewalk lines extracted: {sidewalks_extracted}")
    print(f"Total lines: {total_lines}")

    if total_lines > 0:
        print(f"✅ Line extraction completed successfully!")
    else:
        print(f"⚠️  No lines extracted - check input data")

if __name__ == "__main__":
    main()