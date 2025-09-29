#!/usr/bin/env python3
"""
Simple Road/Sidewalk Line Extraction - Memory Efficient
"""

import sys
import os
import json
import subprocess
import numpy as np
from sklearn.cluster import DBSCAN

def extract_simple_lines(chunk_name, class_name, class_id):
    """Simple line extraction with memory optimization"""
    print(f"\n🛣️  Extracting {class_name} lines (simple method)")

    base_path = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final"
    input_laz = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/{class_name}.laz"
    output_dir = f"{base_path}/outlast/chunks/{chunk_name}/compressed/filtred_by_classes/{class_name}/lines"
    output_file = f"{output_dir}/{class_name}_lines.geojson"

    if not os.path.exists(input_laz):
        print(f"❌ No data: {input_laz}")
        return 0

    os.makedirs(output_dir, exist_ok=True)

    # Use PDAL to sample points (every 10th point for performance)
    temp_file = f"/tmp/{class_name.lower()}_{chunk_name}_sample.txt"

    pipeline = {
        "pipeline": [
            {"type": "readers.las", "filename": input_laz},
            {"type": "filters.sample", "radius": 2.0},  # Sample every 2m
            {"type": "writers.text", "format": "csv", "order": "X,Y,Z",
             "keep_unspecified": "false", "filename": temp_file}
        ]
    }

    pipeline_file = f"/tmp/pipeline_{class_name}_{chunk_name}.json"
    with open(pipeline_file, 'w') as f:
        json.dump(pipeline, f)

    print(f"   Loading sampled points...")
    result = subprocess.run(['pdal', 'pipeline', pipeline_file],
                          capture_output=True, text=True)

    if result.returncode != 0:
        print(f"❌ PDAL failed: {result.stderr}")
        return 0

    # Load sampled points
    try:
        points = np.loadtxt(temp_file, delimiter=',', skiprows=1)
        print(f"   Loaded {len(points):,} sampled points")
    except:
        print(f"❌ Failed to load points")
        return 0

    if len(points) < 20:
        print(f"   Too few points for line extraction")
        return 0

    # Simple clustering
    eps = 10.0 if "Road" in class_name else 5.0  # Larger clusters for roads
    min_samples = 10

    clustering = DBSCAN(eps=eps, min_samples=min_samples).fit(points[:, :2])
    labels = clustering.labels_
    n_clusters = len(set(labels)) - (1 if -1 in labels else 0)

    print(f"   Found {n_clusters} clusters")

    # Create simple line segments
    lines = []
    for cluster_id in range(n_clusters):
        cluster_points = points[labels == cluster_id]
        if len(cluster_points) < 10:
            continue

        # Sort by X coordinate and create simple line
        sorted_points = cluster_points[np.argsort(cluster_points[:, 0])]

        # Simplify to 5-10 points per line
        n_points = min(10, max(5, len(sorted_points) // 10))
        indices = np.linspace(0, len(sorted_points)-1, n_points, dtype=int)
        line_points = sorted_points[indices]

        coordinates = [[float(p[0]), float(p[1])] for p in line_points]

        lines.append({
            "type": "Feature",
            "geometry": {"type": "LineString", "coordinates": coordinates},
            "properties": {
                "line_id": len(lines) + 1,
                "point_count": len(cluster_points),
                "class": class_name,
                "class_id": class_id,
                "chunk": chunk_name
            }
        })

    # Create GeoJSON
    geojson_data = {
        "type": "FeatureCollection",
        "properties": {
            "class": class_name,
            "class_id": class_id,
            "chunk": chunk_name,
            "total_lines": len(lines)
        },
        "features": lines
    }

    # Save
    with open(output_file, 'w') as f:
        json.dump(geojson_data, f, indent=2)

    print(f"✅ Saved {len(lines)} lines to: {output_file}")

    # Cleanup
    try:
        os.remove(temp_file)
        os.remove(pipeline_file)
    except:
        pass

    return len(lines)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 python_road_simple.py <chunk_name>")
        sys.exit(1)

    chunk_name = sys.argv[1]

    # Process roads and sidewalks
    roads = extract_simple_lines(chunk_name, "2_Roads", 2)
    sidewalks = extract_simple_lines(chunk_name, "3_Sidewalks", 3)

    print(f"\n✅ Total: {roads + sidewalks} lines extracted")