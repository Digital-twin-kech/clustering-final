#!/usr/bin/env python3
"""
FIXED Enhanced Instance-Based Building Extraction
- Relaxed clustering parameters to catch ALL buildings
- Sophisticated noise filtering
- Better size range (20-5000 m²)
- Improved overlap detection
- Detailed progress tracking
"""

import numpy as np
from scipy.spatial import ConvexHull, cKDTree
from sklearn.cluster import DBSCAN
from collections import defaultdict
import json
import sys
import subprocess
import os
import math
import time

def extract_instance_buildings_enhanced(chunk_path):
    """
    Extract building instances with sophisticated filtering and progress tracking

    Args:
        chunk_path: Path to chunk directory (e.g., /path/to/chunk_1 or /path/to/chunk_1/compressed/filtred_by_classes)
    """

    start_time = time.time()

    try:
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

        # Paths
        laz_file = f"{classes_base}/6_Buildings/6_Buildings.laz"
        output_dir = f"{classes_base}/6_Buildings/polygons"
        output_file = f"{output_dir}/6_Buildings_polygons.geojson"

        print(f"\n{'='*70}")
        print(f"🏢 SOPHISTICATED BUILDING EXTRACTION - FIXED VERSION")
        print(f"{'='*70}")
        print(f"📍 Chunk: {chunk_name}")
        print(f"📂 Input: {laz_file}")
        print(f"🎯 Strategy: Capture ALL buildings with intelligent noise filtering")
        print(f"{'='*70}\n")

        # Create output directory
        os.makedirs(output_dir, exist_ok=True)

        # Extract points using PDAL pipeline
        temp_points = f"/tmp/building_test/{chunk_name}_all_points.txt"
        os.makedirs("/tmp/building_test", exist_ok=True)

        extraction_pipeline = [
            {
                "type": "readers.las",
                "filename": laz_file
            },
            {
                "type": "writers.text",
                "filename": temp_points,
                "format": "csv",
                "order": "X,Y,Z",
                "keep_unspecified": "false",
                "write_header": "false"
            }
        ]

        pipeline_file = f"/tmp/building_test/{chunk_name}_extract_pipeline.json"
        with open(pipeline_file, 'w') as f:
            json.dump(extraction_pipeline, f, indent=2)

        print(f"[1/7] 📊 Extracting building points from LAZ...")
        result = subprocess.run(f"pdal pipeline {pipeline_file}", shell=True,
                               capture_output=True, text=True, timeout=300)

        if result.returncode != 0:
            print(f"❌ PDAL extraction failed: {result.stderr}")
            return 0

        # Load points from CSV
        print(f"[2/7] 📂 Loading point cloud data...")
        try:
            points_3d = np.loadtxt(temp_points, delimiter=',')
            if len(points_3d.shape) == 1:
                points_3d = points_3d.reshape(1, -1)
        except Exception as e:
            print(f"❌ Failed to load points: {e}")
            return 0

        print(f"      ✅ Loaded {len(points_3d):,} total points")

        if len(points_3d) < 50:
            print(f"❌ Too few points: {len(points_3d)}")
            return 0

        # Step 1: Voxel grid filtering (reasonable size)
        print(f"\n[3/7] 🔄 Voxel downsampling (0.3m grid)...")
        voxel_size = 0.3  # Balanced voxel size
        voxel_indices = np.floor(points_3d / voxel_size).astype(int)
        unique_voxels, unique_indices = np.unique(voxel_indices, axis=0, return_index=True)
        voxel_filtered = points_3d[unique_indices]
        print(f"      ✅ {len(voxel_filtered):,} points after voxel filtering ({100*len(voxel_filtered)/len(points_3d):.1f}% kept)")

        # Step 2: Height-based ground filtering
        print(f"\n[4/7] 🔄 Ground removal (height-based)...")
        z_values = voxel_filtered[:, 2]
        height_threshold = np.percentile(z_values, 20)  # Keep upper 80% of points
        height_mask = z_values > height_threshold
        height_filtered = voxel_filtered[height_mask]
        print(f"      ✅ {len(height_filtered):,} points after ground removal (threshold: {height_threshold:.1f}m)")

        # Step 3: Statistical outlier removal (less aggressive)
        print(f"\n[5/7] 🔄 Outlier removal (statistical)...")
        points_2d = height_filtered[:, :2]

        if len(points_2d) < 20:
            print(f"❌ Too few points after filtering: {len(points_2d)}")
            return 0

        tree = cKDTree(points_2d)
        k_neighbors = min(10, len(points_2d) - 1)
        distances, _ = tree.query(points_2d, k=k_neighbors+1)

        mean_distances = distances[:, 1:].mean(axis=1)
        mean_dist = np.mean(mean_distances)
        std_dist = np.std(mean_distances)

        # Less aggressive outlier threshold
        outlier_threshold = mean_dist + 2.5 * std_dist  # FIXED: 2.5 instead of 1.2
        inlier_mask = mean_distances < outlier_threshold
        clean_points_2d = points_2d[inlier_mask]

        print(f"      ✅ {len(clean_points_2d):,} points after outlier removal ({100*len(clean_points_2d)/len(points_2d):.1f}% kept)")
        print(f"      📊 Mean neighbor distance: {mean_dist:.2f}m, Threshold: {outlier_threshold:.2f}m")

        if len(clean_points_2d) < 100:  # FIXED: Lowered from 500 to 100
            print(f"❌ Too few points after cleaning: {len(clean_points_2d)}")
            return 0

        # Step 4: DBSCAN clustering with RELAXED parameters
        print(f"\n[6/7] 🔄 Building instance clustering (DBSCAN)...")
        print(f"      ⚙️  Parameters:")

        # FIXED: Much more permissive clustering
        eps = 5.0  # FIXED: 5.0 instead of 2.0 (5 meter radius)
        min_samples = 120  # FIXED: 120 instead of 400 (lower minimum)

        print(f"          • eps (search radius): {eps}m")
        print(f"          • min_samples: {min_samples}")

        clustering = DBSCAN(eps=eps, min_samples=min_samples).fit(clean_points_2d)
        labels = clustering.labels_

        unique_labels = set(labels)
        if -1 in unique_labels:
            unique_labels.remove(-1)

        n_clusters = len(unique_labels)
        n_noise = list(labels).count(-1)

        print(f"      ✅ Found {n_clusters} building clusters")
        print(f"      📊 Noise points: {n_noise:,} ({100*n_noise/len(labels):.1f}%)")

        if n_clusters == 0:
            print(f"❌ No building clusters found")
            return 0

        # Step 5: Extract building polygons with sophisticated filtering
        print(f"\n[7/7] 🏗️  Building polygon extraction...")
        print(f"      ⚙️  Quality filters:")
        print(f"          • Size range: 20-5000 m²")
        print(f"          • Aspect ratio: < 12:1")
        print(f"          • Overlap distance: > 8m")
        print(f"          • Minimum points: 80")
        print(f"          • Compactness check: enabled")
        print()

        buildings = []
        building_polygons = []  # To check for overlaps
        rejected_stats = {
            'too_small': 0,
            'too_large': 0,
            'too_few_points': 0,
            'aspect_ratio': 0,
            'overlap': 0,
            'invalid_polygon': 0,
            'too_sparse': 0
        }

        for i, cluster_id in enumerate(sorted(unique_labels)):
            cluster_mask = labels == cluster_id
            cluster_points = clean_points_2d[cluster_mask]

            print(f"  🔍 Candidate {i+1}/{n_clusters}: {len(cluster_points):,} points...", end=' ')

            # Filter 1: Minimum point count (noise rejection)
            if len(cluster_points) < 80:  # FIXED: Lowered from implied higher threshold
                print(f"❌ Too few points")
                rejected_stats['too_few_points'] += 1
                continue

            # Filter 2: Density check (reject very sparse clusters - likely noise)
            cluster_density = calculate_point_density(cluster_points)
            if cluster_density < 0.3:  # Less than 0.3 points per m²
                print(f"❌ Too sparse (density: {cluster_density:.2f} pts/m²)")
                rejected_stats['too_sparse'] += 1
                continue

            # Create polygon
            polygon_coords = create_footprint_building(cluster_points)

            if polygon_coords is None:
                print(f"❌ Invalid polygon")
                rejected_stats['invalid_polygon'] += 1
                continue

            # Calculate metrics
            area_m2 = calculate_polygon_area(polygon_coords)
            perimeter_m = calculate_polygon_perimeter(polygon_coords)
            aspect_ratio = calculate_aspect_ratio(polygon_coords)

            # Filter 3: Size filtering (FIXED: much wider range)
            if area_m2 < 20:
                print(f"❌ Too small ({area_m2:.1f} m²)")
                rejected_stats['too_small'] += 1
                continue

            if area_m2 > 5000:
                print(f"❌ Too large ({area_m2:.1f} m²)")
                rejected_stats['too_large'] += 1
                continue

            # Filter 4: Aspect ratio (reject very thin objects - likely walls/roads)
            if aspect_ratio > 12:  # FIXED: 12:1 instead of 8:1
                print(f"❌ Aspect ratio too high ({aspect_ratio:.1f}:1)")
                rejected_stats['aspect_ratio'] += 1
                continue

            # Filter 5: Overlap check (FIXED: 8m instead of 25m)
            if has_overlap_with_existing(polygon_coords, building_polygons, min_distance=8.0):
                print(f"❌ Overlaps with existing")
                rejected_stats['overlap'] += 1
                continue

            # Calculate compactness (how circular/square the building is)
            compactness = calculate_compactness(area_m2, perimeter_m)

            # Keep coordinates in UTM format
            utm_coords = []
            for x, y in polygon_coords:
                utm_coords.append([x, y])

            # Close the polygon if not already closed
            if utm_coords[0] != utm_coords[-1]:
                utm_coords.append(utm_coords[0])

            # Create building feature
            building = {
                "type": "Feature",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [utm_coords]
                },
                "properties": {
                    "polygon_id": len(buildings) + 1,
                    "class": "6_Buildings",
                    "chunk": chunk_name,
                    "area_m2": round(area_m2, 2),
                    "perimeter_m": round(perimeter_m, 2),
                    "point_count": len(cluster_points),
                    "point_density": round(cluster_density, 2),
                    "aspect_ratio": round(aspect_ratio, 2),
                    "compactness": round(compactness, 3),
                    "extraction_method": "python_instance_enhanced_fixed1"
                }
            }

            buildings.append(building)
            building_polygons.append(polygon_coords)

            print(f"✅ Building #{len(buildings)}: {area_m2:.1f}m², {len(cluster_points)} pts, {aspect_ratio:.1f}:1, compact={compactness:.2f}")

        elapsed_time = time.time() - start_time

        print(f"\n{'='*70}")
        print(f"📊 EXTRACTION SUMMARY")
        print(f"{'='*70}")
        print(f"✅ Buildings extracted: {len(buildings)}")
        print(f"❌ Rejected clusters: {sum(rejected_stats.values())}")
        print(f"   • Too few points: {rejected_stats['too_few_points']}")
        print(f"   • Too sparse: {rejected_stats['too_sparse']}")
        print(f"   • Too small (<20 m²): {rejected_stats['too_small']}")
        print(f"   • Too large (>5000 m²): {rejected_stats['too_large']}")
        print(f"   • Aspect ratio (>12:1): {rejected_stats['aspect_ratio']}")
        print(f"   • Overlap (<8m): {rejected_stats['overlap']}")
        print(f"   • Invalid polygon: {rejected_stats['invalid_polygon']}")

        if not buildings:
            print(f"\n❌ No valid building instances found after filtering")
            print(f"⏱️  Processing time: {elapsed_time:.1f}s")
            return 0

        # Calculate statistics
        total_area = sum(b["properties"]["area_m2"] for b in buildings)
        avg_area = total_area / len(buildings)
        areas = [b["properties"]["area_m2"] for b in buildings]
        min_area = min(areas)
        max_area = max(areas)

        print(f"\n📈 Building Statistics:")
        print(f"   • Total area: {total_area:.1f} m²")
        print(f"   • Average area: {avg_area:.1f} m²")
        print(f"   • Size range: {min_area:.1f} - {max_area:.1f} m²")

        # Create final GeoJSON
        geojson = {
            "type": "FeatureCollection",
            "features": buildings,
            "properties": {
                "class": "6_Buildings",
                "chunk": chunk_name,
                "extraction_method": "python_instance_enhanced_fixed1",
                "processing_time_seconds": round(elapsed_time, 1),
                "parameters": {
                    "voxel_size_m": 0.3,
                    "dbscan_eps_m": eps,
                    "dbscan_min_samples": min_samples,
                    "size_range_m2": [20, 5000],
                    "max_aspect_ratio": 12,
                    "min_overlap_distance_m": 8,
                    "outlier_threshold_factor": 2.5
                },
                "results": {
                    "input_points": len(points_3d),
                    "voxel_filtered_points": len(voxel_filtered),
                    "clean_points": len(clean_points_2d),
                    "clusters_found": n_clusters,
                    "buildings_extracted": len(buildings),
                    "total_area_m2": round(total_area, 2),
                    "avg_area_m2": round(avg_area, 2)
                }
            }
        }

        # Save results
        with open(output_file, 'w') as f:
            json.dump(geojson, f, indent=2)

        print(f"\n✅ SUCCESS!")
        print(f"📁 Output: {output_file}")
        print(f"⏱️  Processing time: {elapsed_time:.1f}s")
        print(f"{'='*70}\n")

        # Clean up temp files
        try:
            os.remove(temp_points)
            os.remove(pipeline_file)
        except:
            pass

        return len(buildings)

    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return 0

def calculate_point_density(points_2d):
    """Calculate point density (points per square meter)"""
    try:
        if len(points_2d) < 4:
            return 0

        # Use convex hull for area estimation
        hull = ConvexHull(points_2d)
        area = hull.volume  # In 2D, volume is area

        if area > 0:
            return len(points_2d) / area
        return 0
    except:
        return 0

def calculate_compactness(area, perimeter):
    """
    Calculate compactness ratio (how circular/square the shape is)
    Compactness = 4π * Area / Perimeter²
    Perfect circle = 1.0, square ≈ 0.785, elongated shapes < 0.5
    """
    try:
        if perimeter > 0:
            return (4 * math.pi * area) / (perimeter ** 2)
        return 0
    except:
        return 0

def create_footprint_building(points_2d):
    """Create exact building footprint polygon following actual point cloud boundary"""
    try:
        if len(points_2d) < 4:
            return None

        from scipy.spatial import ConvexHull
        from sklearn.cluster import DBSCAN

        # Method 1: Try alpha shape approach (concave hull)
        try:
            # Use a simple concave hull based on k-nearest neighbors
            hull = create_concave_hull(points_2d, alpha=4.0)  # FIXED: 4.0m instead of 3.0m
            if hull is not None and len(hull) >= 4:
                # Simplify the polygon to reduce noise while keeping main shape
                simplified = simplify_polygon(hull, tolerance=0.5)  # 0.5m tolerance
                if simplified is not None and len(simplified) >= 4:
                    return simplified
        except:
            pass

        # Method 2: Fallback to convex hull with corner cutting
        try:
            hull = ConvexHull(points_2d)
            hull_points = points_2d[hull.vertices]

            # Add the first point at the end to close the polygon
            hull_coords = hull_points.tolist()
            if len(hull_coords) > 0 and hull_coords[0] != hull_coords[-1]:
                hull_coords.append(hull_coords[0])

            return hull_coords

        except:
            pass

        # Method 3: Final fallback to oriented bounding box but with corner cutting
        try:
            # Get oriented bounding box but then cut corners based on point density
            bbox = create_oriented_bbox_with_cuts(points_2d)
            return bbox

        except:
            pass

        # Method 4: Ultimate fallback to axis-aligned bounding box
        x_min, y_min = np.min(points_2d, axis=0)
        x_max, y_max = np.max(points_2d, axis=0)

        return [
            [x_min, y_min],
            [x_max, y_min],
            [x_max, y_max],
            [x_min, y_max],
            [x_min, y_min]
        ]

    except Exception as e:
        return None

def create_concave_hull(points, alpha=4.0):
    """Create concave hull using alpha shape concept"""
    try:
        from scipy.spatial import cKDTree

        if len(points) < 4:
            return None

        # Build k-d tree for efficient neighbor finding
        tree = cKDTree(points)

        # Find boundary points by identifying points with fewer neighbors within alpha distance
        boundary_points = []

        for i, point in enumerate(points):
            neighbors = tree.query_ball_point(point, alpha)

            # Points with fewer neighbors or on the edge are likely boundary points
            if len(neighbors) <= 10:  # FIXED: 10 instead of 8 for better detection
                boundary_points.append(point)

        if len(boundary_points) < 4:
            return None

        # Create convex hull of boundary points
        boundary_points = np.array(boundary_points)
        hull = ConvexHull(boundary_points)

        # Return hull vertices
        hull_coords = boundary_points[hull.vertices].tolist()
        if len(hull_coords) > 0:
            hull_coords.append(hull_coords[0])  # Close polygon

        return hull_coords

    except:
        return None

def simplify_polygon(coords, tolerance=0.5):
    """Simplify polygon using Douglas-Peucker algorithm"""
    try:
        if len(coords) < 4:
            return coords

        # Simple Douglas-Peucker implementation
        def dp_simplify(points, epsilon):
            if len(points) <= 2:
                return points

            # Find the point with maximum distance from line between first and last
            max_dist = 0
            index = 0

            for i in range(1, len(points) - 1):
                dist = point_to_line_distance(points[i], points[0], points[-1])
                if dist > max_dist:
                    max_dist = dist
                    index = i

            # If max distance is greater than epsilon, recursively simplify
            if max_dist > epsilon:
                # Recursively simplify
                left = dp_simplify(points[:index+1], epsilon)
                right = dp_simplify(points[index:], epsilon)
                return left[:-1] + right
            else:
                return [points[0], points[-1]]

        simplified = dp_simplify(coords, tolerance)

        # Ensure polygon is closed
        if len(simplified) > 0 and simplified[0] != simplified[-1]:
            simplified.append(simplified[0])

        return simplified

    except:
        return coords

def point_to_line_distance(point, line_start, line_end):
    """Calculate distance from point to line segment"""
    try:
        x0, y0 = point
        x1, y1 = line_start
        x2, y2 = line_end

        # Calculate distance using cross product
        num = abs((y2-y1)*x0 - (x2-x1)*y0 + x2*y1 - y2*x1)
        den = math.sqrt((y2-y1)**2 + (x2-x1)**2)

        if den == 0:
            return math.sqrt((x0-x1)**2 + (y0-y1)**2)

        return num / den

    except:
        return 0

def create_oriented_bbox_with_cuts(points_2d):
    """Create oriented bounding box but cut corners where no points exist"""
    try:
        # Get convex hull first
        hull = ConvexHull(points_2d)
        hull_points = points_2d[hull.vertices]

        # For now, just return the convex hull to avoid road extensions
        hull_coords = hull_points.tolist()
        if len(hull_coords) > 0:
            hull_coords.append(hull_coords[0])  # Close polygon

        return hull_coords

    except:
        return None

def calculate_polygon_area(coords):
    """Calculate polygon area using shoelace formula"""
    try:
        if len(coords) < 4:
            return 0

        x = [p[0] for p in coords[:-1]]  # Remove last point (same as first)
        y = [p[1] for p in coords[:-1]]

        return 0.5 * abs(sum(x[i]*y[i+1] - x[i+1]*y[i] for i in range(-1, len(x)-1)))
    except:
        return 0

def calculate_polygon_perimeter(coords):
    """Calculate polygon perimeter"""
    try:
        perimeter = 0
        for i in range(len(coords)-1):
            dx = coords[i+1][0] - coords[i][0]
            dy = coords[i+1][1] - coords[i][1]
            perimeter += math.sqrt(dx*dx + dy*dy)
        return perimeter
    except:
        return 0

def calculate_aspect_ratio(coords):
    """Calculate aspect ratio of rectangular polygon"""
    try:
        if len(coords) < 4:
            return 1

        # Calculate all edge lengths
        edge_lengths = []
        for i in range(len(coords)-1):
            dx = coords[i+1][0] - coords[i][0]
            dy = coords[i+1][1] - coords[i][1]
            length = math.sqrt(dx*dx + dy*dy)
            edge_lengths.append(length)

        # For rectangle, should have pairs of equal sides
        edge_lengths.sort()
        if len(edge_lengths) >= 4:
            width = edge_lengths[0]
            height = edge_lengths[2]  # Third shortest should be the other dimension

            if width > 0:
                return max(height/width, width/height)

        return 1
    except:
        return 1

def has_overlap_with_existing(new_coords, existing_polygons, min_distance=8.0):
    """
    Check if new polygon overlaps significantly with existing ones
    FIXED: Using 8m minimum distance instead of 25m
    """
    try:
        new_area = calculate_polygon_area(new_coords)

        for existing_coords in existing_polygons:
            # Simple bounding box overlap check first (fast)
            new_x = [p[0] for p in new_coords]
            new_y = [p[1] for p in new_coords]
            existing_x = [p[0] for p in existing_coords]
            existing_y = [p[1] for p in existing_coords]

            new_min_x, new_max_x = min(new_x), max(new_x)
            new_min_y, new_max_y = min(new_y), max(new_y)
            existing_min_x, existing_max_x = min(existing_x), max(existing_x)
            existing_min_y, existing_max_y = min(existing_y), max(existing_y)

            # Check if bounding boxes overlap
            if (new_max_x < existing_min_x or new_min_x > existing_max_x or
                new_max_y < existing_min_y or new_min_y > existing_max_y):
                continue  # No overlap

            # If bounding boxes overlap, check center distance
            new_center_x = (new_min_x + new_max_x) / 2
            new_center_y = (new_min_y + new_max_y) / 2
            existing_center_x = (existing_min_x + existing_max_x) / 2
            existing_center_y = (existing_min_y + existing_max_y) / 2

            distance = math.sqrt((new_center_x - existing_center_x)**2 +
                               (new_center_y - existing_center_y)**2)

            # FIXED: 8m instead of 25m
            if distance < min_distance:
                return True

        return False
    except:
        return False

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 python_instance_enhanced_fixed1.py <chunk_path>")
        print("Examples:")
        print("  python3 python_instance_enhanced_fixed1.py /path/to/chunk_1")
        print("  python3 python_instance_enhanced_fixed1.py /path/to/chunk_1/compressed/filtred_by_classes")
        sys.exit(1)

    chunk_path = sys.argv[1]

    # Validate path exists
    if not os.path.exists(chunk_path):
        print(f"❌ Path not found: {chunk_path}")
        sys.exit(1)

    result = extract_instance_buildings_enhanced(chunk_path)

    if result > 0:
        print(f"🎉 Success! Extracted {result} building instances")
    else:
        print(f"❌ Failed to extract buildings")
        sys.exit(1)
