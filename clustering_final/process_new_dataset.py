#!/usr/bin/env python3
"""
Process New Dataset (chunk_3) - Masts, Trees, Buildings, OtherVegetation, Wires
Adapted from the existing clustering pipeline for new dataset structure
"""

import os
import sys
import json
import subprocess
import numpy as np
from sklearn.cluster import DBSCAN
from pathlib import Path

def log_info(msg):
    print(f"[INFO] {msg}")

def log_success(msg):
    print(f"[SUCCESS] {msg}")

def log_error(msg):
    print(f"[ERROR] {msg}")

def process_masts_new_dataset(input_laz, output_dir):
    """Process masts from new dataset using lightweight clustering"""

    log_info(f"🔍 Processing masts: {input_laz}")

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Extract points using PDAL
    temp_file = "/tmp/masts_new_dataset.txt"

    pipeline = {
        "pipeline": [
            {
                "type": "readers.las",
                "filename": input_laz
            },
            {
                "type": "writers.text",
                "filename": temp_file,
                "format": "csv",
                "order": "X,Y,Z",
                "keep_unspecified": "false",
                "write_header": "false"
            }
        ]
    }

    # Write pipeline to temp file
    pipeline_file = "/tmp/masts_pipeline.json"
    with open(pipeline_file, 'w') as f:
        json.dump(pipeline, f)

    # Execute PDAL pipeline
    log_info("Extracting points with PDAL...")
    result = subprocess.run(['pdal', 'pipeline', pipeline_file],
                          capture_output=True, text=True)

    if result.returncode != 0:
        log_error(f"PDAL failed: {result.stderr}")
        return None

    # Load points
    try:
        points = np.loadtxt(temp_file, delimiter=',')
        log_info(f"Loaded {len(points):,} points")
    except Exception as e:
        log_error(f"Failed to load points: {e}")
        return None

    if len(points) < 50:
        log_error("Too few points for clustering")
        return None

    # 2D clustering (project to XY plane)
    xy_points = points[:, :2]  # X, Y coordinates only

    log_info("Performing DBSCAN clustering...")
    clustering = DBSCAN(eps=1.5, min_samples=30).fit(xy_points)
    labels = clustering.labels_

    # Count clusters
    unique_labels = set(labels)
    n_clusters = len(unique_labels) - (1 if -1 in unique_labels else 0)

    log_info(f"Found {n_clusters} mast clusters")

    if n_clusters == 0:
        log_error("No clusters found")
        return None

    # Create centroids
    centroids = []
    cluster_id = 1

    for label in unique_labels:
        if label == -1:  # Noise
            continue

        cluster_mask = (labels == label)
        cluster_points = points[cluster_mask]

        if len(cluster_points) < 30:  # Skip small clusters
            continue

        # Calculate centroid
        centroid = np.mean(cluster_points, axis=0)
        height_range = np.max(cluster_points[:, 2]) - np.min(cluster_points[:, 2])

        centroid_data = {
            "id": cluster_id,
            "centroid_x": float(centroid[0]),
            "centroid_y": float(centroid[1]),
            "centroid_z": float(centroid[2]),
            "point_count": len(cluster_points),
            "height_m": float(height_range),
            "class": "12_Masts",
            "class_id": 12,
            "chunk": "chunk_6",  # New dataset chunk
            "source": "new_dataset_chunk_3"
        }

        centroids.append(centroid_data)
        cluster_id += 1

    # Create JSON output
    output_data = {
        "class": "12_Masts",
        "class_id": 12,
        "chunk": "chunk_6",
        "total_points": len(points),
        "instances_found": len(centroids),
        "clustering_method": "2D_DBSCAN",
        "source_file": input_laz,
        "instances": centroids
    }

    # Save centroids
    output_file = os.path.join(output_dir, "12_Masts_centroids.json")
    with open(output_file, 'w') as f:
        json.dump(output_data, f, indent=2)

    log_success(f"Mast centroids saved: {output_file}")

    # Cleanup
    try:
        os.remove(temp_file)
        os.remove(pipeline_file)
    except:
        pass

    return len(centroids)

def process_trees_new_dataset(input_laz, output_dir):
    """Process trees from new dataset"""

    log_info(f"🌳 Processing trees: {input_laz}")

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Extract points using PDAL
    temp_file = "/tmp/trees_new_dataset.txt"

    pipeline = {
        "pipeline": [
            {
                "type": "readers.las",
                "filename": input_laz
            },
            {
                "type": "writers.text",
                "filename": temp_file,
                "format": "csv",
                "order": "X,Y,Z",
                "keep_unspecified": "false",
                "write_header": "false"
            }
        ]
    }

    pipeline_file = "/tmp/trees_pipeline.json"
    with open(pipeline_file, 'w') as f:
        json.dump(pipeline, f)

    result = subprocess.run(['pdal', 'pipeline', pipeline_file],
                          capture_output=True, text=True)

    if result.returncode != 0:
        log_error(f"PDAL failed: {result.stderr}")
        return None

    try:
        points = np.loadtxt(temp_file, delimiter=',')
        log_info(f"Loaded {len(points):,} points")
    except Exception as e:
        log_error(f"Failed to load points: {e}")
        return None

    if len(points) < 50:
        log_error("Too few points for clustering")
        return None

    # 2D clustering for trees
    xy_points = points[:, :2]

    log_info("Performing DBSCAN clustering...")
    clustering = DBSCAN(eps=2.5, min_samples=20).fit(xy_points)
    labels = clustering.labels_

    unique_labels = set(labels)
    n_clusters = len(unique_labels) - (1 if -1 in unique_labels else 0)

    log_info(f"Found {n_clusters} tree clusters")

    if n_clusters == 0:
        return None

    # Create centroids
    centroids = []
    cluster_id = 1

    for label in unique_labels:
        if label == -1:
            continue

        cluster_mask = (labels == label)
        cluster_points = points[cluster_mask]

        if len(cluster_points) < 20:
            continue

        centroid = np.mean(cluster_points, axis=0)
        height_range = np.max(cluster_points[:, 2]) - np.min(cluster_points[:, 2])

        centroid_data = {
            "id": cluster_id,
            "centroid_x": float(centroid[0]),
            "centroid_y": float(centroid[1]),
            "centroid_z": float(centroid[2]),
            "point_count": len(cluster_points),
            "height_m": float(height_range),
            "class": "7_Trees",
            "class_id": 7,
            "chunk": "chunk_6",
            "source": "new_dataset_chunk_3"
        }

        centroids.append(centroid_data)
        cluster_id += 1

    output_data = {
        "class": "7_Trees",
        "class_id": 7,
        "chunk": "chunk_6",
        "total_points": len(points),
        "instances_found": len(centroids),
        "clustering_method": "2D_DBSCAN",
        "source_file": input_laz,
        "instances": centroids
    }

    output_file = os.path.join(output_dir, "7_Trees_centroids.json")
    with open(output_file, 'w') as f:
        json.dump(output_data, f, indent=2)

    log_success(f"Tree centroids saved: {output_file}")

    # Cleanup
    try:
        os.remove(temp_file)
        os.remove(pipeline_file)
    except:
        pass

    return len(centroids)

def process_class_generic(input_laz, class_name, class_id, output_dir, eps=2.0, min_samples=15):
    """Generic processing for buildings and other vegetation"""

    log_info(f"🏗️ Processing {class_name}: {input_laz}")

    os.makedirs(output_dir, exist_ok=True)

    temp_file = f"/tmp/{class_name.lower()}_new_dataset.txt"

    pipeline = {
        "pipeline": [
            {
                "type": "readers.las",
                "filename": input_laz
            },
            {
                "type": "writers.text",
                "filename": temp_file,
                "format": "csv",
                "order": "X,Y,Z",
                "keep_unspecified": "false",
                "write_header": "false"
            }
        ]
    }

    pipeline_file = f"/tmp/{class_name.lower()}_pipeline.json"
    with open(pipeline_file, 'w') as f:
        json.dump(pipeline, f)

    result = subprocess.run(['pdal', 'pipeline', pipeline_file],
                          capture_output=True, text=True)

    if result.returncode != 0:
        log_error(f"PDAL failed: {result.stderr}")
        return None

    try:
        points = np.loadtxt(temp_file, delimiter=',')
        log_info(f"Loaded {len(points):,} points")
    except Exception as e:
        log_error(f"Failed to load points: {e}")
        return None

    if len(points) < 50:
        log_error("Too few points for clustering")
        return None

    # 2D clustering
    xy_points = points[:, :2]

    log_info("Performing DBSCAN clustering...")
    clustering = DBSCAN(eps=eps, min_samples=min_samples).fit(xy_points)
    labels = clustering.labels_

    unique_labels = set(labels)
    n_clusters = len(unique_labels) - (1 if -1 in unique_labels else 0)

    log_info(f"Found {n_clusters} {class_name} clusters")

    if n_clusters == 0:
        return None

    # Create centroids
    centroids = []
    cluster_id = 1

    for label in unique_labels:
        if label == -1:
            continue

        cluster_mask = (labels == label)
        cluster_points = points[cluster_mask]

        if len(cluster_points) < min_samples:
            continue

        centroid = np.mean(cluster_points, axis=0)
        height_range = np.max(cluster_points[:, 2]) - np.min(cluster_points[:, 2])

        centroid_data = {
            "id": cluster_id,
            "centroid_x": float(centroid[0]),
            "centroid_y": float(centroid[1]),
            "centroid_z": float(centroid[2]),
            "point_count": len(cluster_points),
            "height_m": float(height_range),
            "class": class_name,
            "class_id": class_id,
            "chunk": "chunk_6",
            "source": "new_dataset_chunk_3"
        }

        centroids.append(centroid_data)
        cluster_id += 1

    output_data = {
        "class": class_name,
        "class_id": class_id,
        "chunk": "chunk_6",
        "total_points": len(points),
        "instances_found": len(centroids),
        "clustering_method": "2D_DBSCAN",
        "source_file": input_laz,
        "instances": centroids
    }

    output_file = os.path.join(output_dir, f"{class_name}_centroids.json")
    with open(output_file, 'w') as f:
        json.dump(output_data, f, indent=2)

    log_success(f"{class_name} centroids saved: {output_file}")

    # Cleanup
    try:
        os.remove(temp_file)
        os.remove(pipeline_file)
    except:
        pass

    return len(centroids)

def process_wires_new_dataset(input_laz, output_dir):
    """Process wires from new dataset - creates lines instead of centroids"""

    log_info(f"⚡ Processing wires: {input_laz}")

    lines_dir = os.path.join(output_dir, "lines")
    os.makedirs(lines_dir, exist_ok=True)

    temp_file = "/tmp/wires_new_dataset.txt"

    pipeline = {
        "pipeline": [
            {
                "type": "readers.las",
                "filename": input_laz
            },
            {
                "type": "writers.text",
                "filename": temp_file,
                "format": "csv",
                "order": "X,Y,Z",
                "keep_unspecified": "false",
                "write_header": "false"
            }
        ]
    }

    pipeline_file = "/tmp/wires_pipeline.json"
    with open(pipeline_file, 'w') as f:
        json.dump(pipeline, f)

    result = subprocess.run(['pdal', 'pipeline', pipeline_file],
                          capture_output=True, text=True)

    if result.returncode != 0:
        log_error(f"PDAL failed: {result.stderr}")
        return None

    try:
        points = np.loadtxt(temp_file, delimiter=',')
        log_info(f"Loaded {len(points):,} wire points")
    except Exception as e:
        log_error(f"Failed to load points: {e}")
        return None

    if len(points) < 10:
        log_error("Too few wire points")
        return None

    # Simple wire line clustering
    xy_points = points[:, :2]

    log_info("Clustering wire segments...")
    clustering = DBSCAN(eps=3.0, min_samples=5).fit(xy_points)
    labels = clustering.labels_

    unique_labels = set(labels)
    n_clusters = len(unique_labels) - (1 if -1 in unique_labels else 0)

    log_info(f"Found {n_clusters} wire segments")

    if n_clusters == 0:
        return None

    # Create wire lines
    features = []
    line_id = 1

    for label in unique_labels:
        if label == -1:
            continue

        cluster_mask = (labels == label)
        cluster_points = points[cluster_mask]

        if len(cluster_points) < 5:
            continue

        # Sort points along main direction for line creation
        cluster_2d = cluster_points[:, :2]
        centroid = np.mean(cluster_2d, axis=0)

        # Simple line from first to last point
        sorted_points = cluster_points[np.argsort(cluster_points[:, 0])]  # Sort by X

        start_point = sorted_points[0]
        end_point = sorted_points[-1]

        # Calculate length
        length = np.linalg.norm(end_point[:2] - start_point[:2])

        if length < 5.0:  # Skip short segments
            continue

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
                "line_id": line_id,
                "length_m": round(length, 2),
                "wire_points": len(cluster_points),
                "class": "11_Wires",
                "class_id": 11,
                "chunk": "chunk_6",
                "source": "new_dataset_chunk_3"
            }
        }

        features.append(feature)
        line_id += 1

    # Create GeoJSON
    geojson_data = {
        "type": "FeatureCollection",
        "properties": {
            "class": "11_Wires",
            "class_id": 11,
            "chunk": "chunk_6",
            "total_lines": len(features),
            "source": "new_dataset_chunk_3"
        },
        "features": features
    }

    output_file = os.path.join(lines_dir, "11_Wires_lines.geojson")
    with open(output_file, 'w') as f:
        json.dump(geojson_data, f, indent=2)

    log_success(f"Wire lines saved: {output_file}")

    # Cleanup
    try:
        os.remove(temp_file)
        os.remove(pipeline_file)
    except:
        pass

    return len(features)

def main():
    """Process new dataset classes"""

    print("="*70)
    print("NEW DATASET PROCESSING - CHUNK_3")
    print("="*70)
    print("Classes: Masts, Trees, Buildings, OtherVegetation, Wires")
    print()

    # Base paths
    base_input = "/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/cloud-point-part-3-classifier-mobile-mapping-flainet/cloud_point_part_3_-_classifier_-_mobile_mapping_flainet/chunk_3/compressed/filtred_by_classes"
    base_output = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final/outlast_new/chunks/chunk_6/compressed/filtred_by_classes"

    total_processed = 0
    results = {}

    # Process each class
    classes_to_process = [
        ("12_Masts", 12, "masts", 1.5, 30),
        ("7_Trees", 7, "trees", 2.5, 20),
        ("6_Buildings", 6, "buildings", 5.0, 25),
        ("8_OtherVegetation", 8, "vegetation", 2.0, 15)
    ]

    for class_name, class_id, description, eps, min_samples in classes_to_process:
        input_laz = f"{base_input}/{class_name}/{class_name}.laz"

        if not os.path.exists(input_laz):
            log_error(f"Input file not found: {input_laz}")
            continue

        if class_name == "12_Masts":
            output_dir = f"{base_output}/{class_name}/centroids"
            count = process_masts_new_dataset(input_laz, output_dir)
        elif class_name == "7_Trees":
            output_dir = f"{base_output}/{class_name}/centroids"
            count = process_trees_new_dataset(input_laz, output_dir)
        else:
            output_dir = f"{base_output}/{class_name}/centroids"
            count = process_class_generic(input_laz, class_name, class_id, output_dir, eps, min_samples)

        if count:
            results[class_name] = count
            total_processed += count
            log_success(f"{description.capitalize()}: {count} instances")
        else:
            results[class_name] = 0
            log_error(f"Failed to process {description}")

        print()

    # Process wires separately (creates lines)
    wires_laz = f"{base_input}/11_Wires/11_Wires.laz"
    if os.path.exists(wires_laz):
        output_dir = f"{base_output}/11_Wires"
        wire_count = process_wires_new_dataset(wires_laz, output_dir)
        if wire_count:
            results["11_Wires"] = wire_count
            log_success(f"Wires: {wire_count} line segments")
        else:
            results["11_Wires"] = 0
            log_error("Failed to process wires")
    else:
        log_error(f"Wires file not found: {wires_laz}")
        results["11_Wires"] = 0

    # Summary
    print()
    print("="*70)
    print("PROCESSING SUMMARY")
    print("="*70)
    for class_name, count in results.items():
        print(f"{class_name}: {count} instances/lines")
    print(f"Total processed: {total_processed}")

    if total_processed > 0:
        log_success("New dataset processing completed!")
    else:
        log_error("No data was processed successfully")

if __name__ == "__main__":
    main()