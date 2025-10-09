#!/usr/bin/env python3
"""
Enhanced Wire Line Extraction for LiDAR Point Clouds
Creates precise line segments for wire/cable infrastructure
Optimized for continuous linear structures with height variations
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
from sklearn.preprocessing import PolynomialFeatures

def extract_wire_lines_enhanced(chunk_path):
    """
    Enhanced wire extraction using line-based segmentation
    Optimized for continuous linear wire structures

    Args:
        chunk_path: Path to chunk directory (e.g., /path/to/chunk_1 or /path/to/chunk_1/compressed/filtred_by_classes)
    """
    # Normalize the path - detect if it's the chunk root or filtred_by_classes
    chunk_path = os.path.abspath(chunk_path)

    if chunk_path.endswith('/compressed/filtred_by_classes'):
        # Path is already pointing to filtred_by_classes
        classes_base = chunk_path
        chunk_name = os.path.basename(os.path.dirname(os.path.dirname(chunk_path)))
    elif os.path.exists(os.path.join(chunk_path, 'compressed/filtred_by_classes')):
        # Path is chunk root directory
        classes_base = os.path.join(chunk_path, 'compressed/filtred_by_classes')
        chunk_name = os.path.basename(chunk_path)
    else:
        print(f"❌ Invalid path structure. Expected chunk directory or filtred_by_classes directory")
        return 0

    print(f"\n⚡ === ENHANCED WIRE LINE EXTRACTION ===")
    print(f"📍 Chunk: {chunk_name}")
    print(f"📂 Base path: {classes_base}")
    print(f"🎯 Method: Line segmentation + height-aware clustering")
    print(f"📊 Extracting wire lines...")

    # Paths
    wire_laz = f"{classes_base}/11_Wires/11_Wires.laz"
    output_dir = f"{classes_base}/11_Wires/lines"
    output_file = f"{output_dir}/11_Wires_lines.geojson"

    # Check if wire data exists
    if not os.path.exists(wire_laz):
        print(f"❌ No wire data found: {wire_laz}")
        return 0

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Load wire points using PDAL pipeline
    print(f"📂 Loading wire point data...")
    try:
        # Create temporary text file for points
        temp_points_file = f"/tmp/wire_points_{chunk_name}.txt"

        # PDAL pipeline to extract points as text
        pipeline = {
            "pipeline": [
                {
                    "type": "readers.las",
                    "filename": wire_laz
                },
                {
                    "type": "writers.text",
                    "filename": temp_points_file,
                    "format": "csv",
                    "order": "X,Y,Z",
                    "write_header": False
                }
            ]
        }

        # Write pipeline to temporary file
        temp_pipeline_file = f"/tmp/wire_pipeline_{chunk_name}.json"
        with open(temp_pipeline_file, 'w') as f:
            json.dump(pipeline, f)

        # Execute PDAL pipeline
        cmd = ["pdal", "pipeline", temp_pipeline_file]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)

        # Read points from text file
        points_3d = []
        if os.path.exists(temp_points_file):
            with open(temp_points_file, 'r') as f:
                for line in f:
                    try:
                        parts = line.strip().split(',')
                        if len(parts) >= 3:
                            x, y, z = float(parts[0]), float(parts[1]), float(parts[2])
                            points_3d.append([x, y, z])
                    except (ValueError, IndexError):
                        continue

        # Cleanup temp files
        for temp_file in [temp_points_file, temp_pipeline_file]:
            if os.path.exists(temp_file):
                os.remove(temp_file)

    except subprocess.CalledProcessError as e:
        print(f"❌ PDAL pipeline failed: {e}")
        return 0
    except Exception as e:
        print(f"❌ Error processing wire data: {e}")
        return 0

    if not points_3d:
        print(f"❌ No valid wire points found")
        return 0

    points_3d = np.array(points_3d)

    if len(points_3d) == 0:
        print(f"❌ No wire points found")
        return 0

    print(f"📊 Input points: {len(points_3d):,}")

    # Step 1: Light voxel filtering (preserve wire continuity)
    print(f"\n🔄 Step 1: Light voxel filtering (0.2m grid)")
    voxel_size = 0.2  # Small voxel to preserve wire detail
    voxel_indices = np.floor(points_3d / voxel_size).astype(int)
    unique_voxels, unique_indices = np.unique(voxel_indices, axis=0, return_index=True)
    voxel_filtered = points_3d[unique_indices]
    print(f"  📊 Voxel filtered: {len(voxel_filtered):,} ({100*len(voxel_filtered)/len(points_3d):.1f}%)")

    # Step 2: Height-based filtering (remove ground clutter)
    print(f"\n🔄 Step 2: Height-based filtering for elevated wires")
    z_values = voxel_filtered[:, 2]
    height_threshold = np.percentile(z_values, 10)  # Keep upper 90% for elevated wires
    height_mask = z_values > height_threshold
    height_filtered = voxel_filtered[height_mask]
    print(f"  📊 Height filtered (>{height_threshold:.1f}m): {len(height_filtered):,} ({100*len(height_filtered)/len(voxel_filtered):.1f}%)")

    # Step 3: Conservative outlier removal (preserve wire endpoints)
    print(f"\n🔄 Step 3: Conservative outlier removal")
    points_2d = height_filtered[:, :2]

    if len(points_2d) < 10:
        print(f"❌ Too few points after filtering: {len(points_2d)}")
        return 0

    tree = cKDTree(points_2d)
    k_neighbors = min(8, len(points_2d) - 1)  # Conservative neighbor count
    distances, _ = tree.query(points_2d, k=k_neighbors+1)

    mean_distances = distances[:, 1:].mean(axis=1)
    mean_dist = np.mean(mean_distances)
    std_dist = np.std(mean_distances)

    # Conservative outlier threshold (preserve wire endpoints)
    outlier_threshold = mean_dist + 2.5 * std_dist  # Looser than buildings/vegetation
    inlier_mask = mean_distances < outlier_threshold
    clean_points_3d = height_filtered[inlier_mask]

    print(f"  📊 Outlier removal: {len(clean_points_3d):,} ({100*len(clean_points_3d)/len(height_filtered):.1f}%)")

    # Step 4: Wire line clustering (height-aware)
    print(f"\n🔄 Step 4: Height-aware wire line clustering")

    # Use 3D clustering for wires (height matters for wire sag)
    clustering = DBSCAN(eps=5.0, min_samples=30, n_jobs=-1)  # Looser for continuous lines
    labels = clustering.fit_predict(clean_points_3d)

    unique_labels = [l for l in set(labels) if l != -1]
    n_clusters = len(unique_labels)
    n_noise = list(labels).count(-1)

    print(f"  📊 Found {n_clusters} potential wire lines, {n_noise} noise points")

    if n_clusters == 0:
        print(f"❌ No wire clusters found")
        return 0

    # Step 5: Wire line generation
    print(f"\n🔄 Step 5: Wire line generation")

    wire_lines = []
    valid_lines = 0

    for i, label in enumerate(unique_labels):
        cluster_mask = labels == label
        cluster_points = clean_points_3d[cluster_mask]

        print(f"  ⚡ Wire line {i+1}: {len(cluster_points)} points")

        if len(cluster_points) < 20:  # Minimum points for a valid wire line
            print(f"    ❌ Too few points: {len(cluster_points)} (need ≥20)")
            continue

        # Calculate line metrics
        points_2d = cluster_points[:, :2]

        # Fit line to 2D points to get direction
        try:
            # Use PCA to find principal direction
            centered_points = points_2d - np.mean(points_2d, axis=0)
            cov_matrix = np.cov(centered_points.T)
            eigenvalues, eigenvectors = np.linalg.eigh(cov_matrix)
            principal_direction = eigenvectors[:, -1]  # Largest eigenvalue

            # Calculate line length (extent along principal direction)
            projections = np.dot(centered_points, principal_direction)
            line_length = np.max(projections) - np.min(projections)

            # Calculate line width (extent perpendicular to principal direction)
            perpendicular_direction = np.array([-principal_direction[1], principal_direction[0]])
            perp_projections = np.dot(centered_points, perpendicular_direction)
            line_width = np.max(perp_projections) - np.min(perp_projections)

            # Calculate aspect ratio (should be high for wires)
            aspect_ratio = line_length / max(line_width, 0.1)

        except Exception as e:
            print(f"    ❌ Line fitting failed: {e}")
            continue

        # Quality filters for wire lines
        if line_length < 5:  # Minimum wire length (relaxed)
            print(f"    ❌ Line too short: {line_length:.1f}m (need ≥5m)")
            continue

        if aspect_ratio < 3:  # Wires should be long and narrow (relaxed)
            print(f"    ❌ Not linear enough: {aspect_ratio:.1f}:1 (need ≥3:1)")
            continue

        # Create line geometry by ordering points along the principal direction
        projections_with_indices = [(np.dot(point - np.mean(points_2d, axis=0), principal_direction), idx)
                                   for idx, point in enumerate(points_2d)]
        projections_with_indices.sort()

        # Sample points along the line (reduce density for cleaner lines)
        n_sample_points = min(50, len(projections_with_indices))  # Max 50 points per line
        sample_indices = np.linspace(0, len(projections_with_indices)-1, n_sample_points, dtype=int)

        line_coordinates = []
        for sample_idx in sample_indices:
            _, original_idx = projections_with_indices[sample_idx]
            point = cluster_points[original_idx]
            line_coordinates.append([float(point[0]), float(point[1])])

        # Create GeoJSON LineString
        line_feature = {
            "type": "Feature",
            "geometry": {
                "type": "LineString",
                "coordinates": line_coordinates
            },
            "properties": {
                "line_id": valid_lines + 1,
                "class": "11_Wires",
                "chunk": chunk_name,
                "length_m": round(line_length, 2),
                "width_m": round(line_width, 2),
                "point_count": len(cluster_points),
                "aspect_ratio": round(aspect_ratio, 2),
                "min_height_m": round(float(np.min(cluster_points[:, 2])), 2),
                "max_height_m": round(float(np.max(cluster_points[:, 2])), 2),
                "avg_height_m": round(float(np.mean(cluster_points[:, 2])), 2),
                "extraction_method": "python_wire_enhanced"
            }
        }

        wire_lines.append(line_feature)
        valid_lines += 1

        print(f"    ✅ Wire line {valid_lines}: {line_length:.1f}m long, {aspect_ratio:.1f}:1 ratio")

    if valid_lines == 0:
        print(f"❌ No valid wire lines found")
        return 0

    # Calculate total metrics
    total_length = sum(line["properties"]["length_m"] for line in wire_lines)
    avg_length = total_length / valid_lines if valid_lines > 0 else 0

    # Create output GeoJSON
    output_geojson = {
        "type": "FeatureCollection",
        "features": wire_lines,
        "properties": {
            "class": "11_Wires",
            "chunk": chunk_name,
            "extraction_method": "python_wire_enhanced_lines",
            "results": {
                "input_points": int(len(points_3d)),
                "clean_points": int(len(clean_points_3d)),
                "wire_lines": valid_lines,
                "total_length_m": round(total_length, 2)
            }
        }
    }

    # Write output file
    with open(output_file, 'w') as f:
        json.dump(output_geojson, f, indent=2)

    print(f"✅ SUCCESS: {valid_lines} wire lines")
    print(f"📊 Total length: {total_length:.1f}m (avg: {avg_length:.1f}m per line)")
    print(f"📁 Saved: {output_file}")

    print(f"\n🎉 Success! Extracted {valid_lines} wire lines")
    return valid_lines

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 python_wire_enhanced.py <chunk_path>")
        print("Examples:")
        print("  python3 python_wire_enhanced.py /path/to/chunk_1")
        print("  python3 python_wire_enhanced.py /path/to/chunk_1/compressed/filtred_by_classes")
        sys.exit(1)

    chunk_path = sys.argv[1]

    # Validate path exists
    if not os.path.exists(chunk_path):
        print(f"❌ Path not found: {chunk_path}")
        sys.exit(1)

    try:
        result = extract_wire_lines_enhanced(chunk_path)
        sys.exit(0 if result > 0 else 1)
    except KeyboardInterrupt:
        print(f"\n❌ Wire extraction interrupted")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Wire extraction failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()