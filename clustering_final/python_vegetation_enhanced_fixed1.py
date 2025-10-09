#!/usr/bin/env python3
"""
FIXED Enhanced Vegetation Polygon Extraction
- Relaxed clustering parameters to catch more vegetation areas
- Better overlap detection
- Sophisticated noise filtering
- Detailed progress tracking
"""

import sys
import os
import json
import subprocess
import numpy as np
import math
import time
from scipy.spatial import ConvexHull, cKDTree
from sklearn.cluster import DBSCAN

def extract_vegetation_polygons_enhanced(chunk_path):
    """
    Enhanced vegetation extraction with sophisticated filtering and progress tracking

    Args:
        chunk_path: Path to chunk directory (e.g., /path/to/chunk_1 or /path/to/chunk_1/compressed/filtred_by_classes)
    """

    start_time = time.time()

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

    print(f"\n{'='*70}")
    print(f"🌿 SOPHISTICATED VEGETATION EXTRACTION - FIXED VERSION")
    print(f"{'='*70}")
    print(f"📍 Chunk: {chunk_name}")
    print(f"📂 Base path: {classes_base}")
    print(f"🎯 Strategy: Capture ALL vegetation with intelligent noise filtering")
    print(f"{'='*70}\n")

    # Paths
    vegetation_laz = f"{classes_base}/8_OtherVegetation/8_OtherVegetation.laz"
    output_dir = f"{classes_base}/8_OtherVegetation/polygons"
    output_file = f"{output_dir}/8_OtherVegetation_polygons.geojson"

    # Check if vegetation data exists
    if not os.path.exists(vegetation_laz):
        print(f"❌ No vegetation data found: {vegetation_laz}")
        return 0

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Load vegetation points using PDAL pipeline
    print(f"[1/6] 📂 Loading vegetation point data...")
    try:
        # Create temporary text file for points
        temp_points_file = f"/tmp/vegetation_points_{chunk_name}.txt"

        # PDAL pipeline to extract points as text
        pipeline = {
            "pipeline": [
                {
                    "type": "readers.las",
                    "filename": vegetation_laz
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
        temp_pipeline_file = f"/tmp/vegetation_pipeline_{chunk_name}.json"
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

            # Clean up temporary files
            os.remove(temp_points_file)
            os.remove(temp_pipeline_file)

        points_3d = np.array(points_3d)

        if len(points_3d) == 0:
            print(f"❌ No vegetation points found")
            return 0

        print(f"      ✅ Loaded {len(points_3d):,} total points")

        # Step 1: Voxel grid filtering (reasonable size)
        print(f"\n[2/6] 🔄 Voxel downsampling (0.4m grid)...")
        voxel_size = 0.4  # Balanced voxel size for vegetation
        voxel_indices = np.floor(points_3d / voxel_size).astype(int)
        unique_voxels, unique_indices = np.unique(voxel_indices, axis=0, return_index=True)
        voxel_filtered = points_3d[unique_indices]
        print(f"      ✅ {len(voxel_filtered):,} points after voxel filtering ({100*len(voxel_filtered)/len(points_3d):.1f}% kept)")

        # Step 2: Height-based filtering
        print(f"\n[3/6] 🔄 Ground removal (height-based)...")
        z_values = voxel_filtered[:, 2]
        height_threshold = np.percentile(z_values, 15)  # Keep upper 85% of points
        height_mask = z_values > height_threshold
        height_filtered = voxel_filtered[height_mask]
        print(f"      ✅ {len(height_filtered):,} points after ground removal (threshold: {height_threshold:.1f}m)")

        # Step 3: Statistical outlier removal (less aggressive)
        print(f"\n[4/6] 🔄 Outlier removal (statistical)...")
        points_2d = height_filtered[:, :2]

        if len(points_2d) < 20:
            print(f"❌ Too few points after filtering: {len(points_2d)}")
            return 0

        tree = cKDTree(points_2d)
        k_neighbors = min(12, len(points_2d) - 1)
        distances, _ = tree.query(points_2d, k=k_neighbors+1)

        mean_distances = distances[:, 1:].mean(axis=1)
        mean_dist = np.mean(mean_distances)
        std_dist = np.std(mean_distances)

        # FIXED: Less aggressive outlier threshold (2.5 instead of 1.8)
        outlier_threshold = mean_dist + 2.5 * std_dist
        inlier_mask = mean_distances < outlier_threshold
        clean_points_2d = points_2d[inlier_mask]

        print(f"      ✅ {len(clean_points_2d):,} points after outlier removal ({100*len(clean_points_2d)/len(points_2d):.1f}% kept)")
        print(f"      📊 Mean neighbor distance: {mean_dist:.2f}m, Threshold: {outlier_threshold:.2f}m")

        # Step 4: DBSCAN clustering with RELAXED parameters
        print(f"\n[5/6] 🔄 Vegetation area clustering (DBSCAN)...")
        print(f"      ⚙️  Parameters:")

        # FIXED: More permissive clustering
        eps = 5.0  # FIXED: 5.0 instead of 4.0 (larger radius)
        min_samples = 50  # FIXED: 50 instead of 80 (lower minimum)

        print(f"          • eps (search radius): {eps}m")
        print(f"          • min_samples: {min_samples}")

        clustering = DBSCAN(eps=eps, min_samples=min_samples, n_jobs=-1)
        labels = clustering.fit_predict(clean_points_2d)

        unique_labels = [l for l in set(labels) if l != -1]
        n_clusters = len(unique_labels)
        n_noise = list(labels).count(-1)

        print(f"      ✅ Found {n_clusters} vegetation clusters")
        print(f"      📊 Noise points: {n_noise:,} ({100*n_noise/len(labels):.1f}%)")

        if n_clusters == 0:
            print(f"❌ No vegetation clusters found")
            return 0

        # Step 5: Extract vegetation polygons with sophisticated filtering
        print(f"\n[6/6] 🌿 Vegetation polygon extraction...")
        print(f"      ⚙️  Quality filters:")
        print(f"          • Size range: 8-3000 m²")
        print(f"          • Aspect ratio: < 20:1")
        print(f"          • Overlap distance: > 5m")
        print(f"          • Minimum points: 40")
        print()

        vegetation_areas = []
        vegetation_polygons = []  # To check for overlaps
        rejected_stats = {
            'too_small': 0,
            'too_large': 0,
            'too_few_points': 0,
            'aspect_ratio': 0,
            'overlap': 0,
            'invalid_polygon': 0
        }

        for i, cluster_id in enumerate(sorted(unique_labels)):
            cluster_mask = labels == cluster_id
            cluster_points = clean_points_2d[cluster_mask]

            print(f"  🔍 Candidate {i+1}/{n_clusters}: {len(cluster_points):,} points...", end=' ')

            # Filter 1: Minimum point count (noise rejection)
            if len(cluster_points) < 40:  # FIXED: Lowered from implied higher threshold
                print(f"❌ Too few points")
                rejected_stats['too_few_points'] += 1
                continue

            # Create polygon
            polygon_coords = create_vegetation_polygon(cluster_points)

            if polygon_coords is None:
                print(f"❌ Invalid polygon")
                rejected_stats['invalid_polygon'] += 1
                continue

            # Calculate metrics
            area_m2 = calculate_polygon_area(polygon_coords)
            perimeter_m = calculate_polygon_perimeter(polygon_coords)
            aspect_ratio = calculate_aspect_ratio(polygon_coords)

            # Filter 2: Size filtering (FIXED: wider range)
            if area_m2 < 8:  # FIXED: 8 instead of 10
                print(f"❌ Too small ({area_m2:.1f} m²)")
                rejected_stats['too_small'] += 1
                continue

            if area_m2 > 3000:  # FIXED: 3000 instead of 2000
                print(f"❌ Too large ({area_m2:.1f} m²)")
                rejected_stats['too_large'] += 1
                continue

            # Filter 3: Aspect ratio (FIXED: 20:1 instead of 15:1)
            if aspect_ratio > 20:
                print(f"❌ Aspect ratio too high ({aspect_ratio:.1f}:1)")
                rejected_stats['aspect_ratio'] += 1
                continue

            # Filter 4: Overlap check (FIXED: better distance-based check)
            if has_overlap_with_existing(polygon_coords, vegetation_polygons, min_distance=5.0):
                print(f"❌ Overlaps with existing")
                rejected_stats['overlap'] += 1
                continue

            # Calculate compactness
            compactness = calculate_compactness(area_m2, perimeter_m)

            # Keep coordinates in UTM format
            utm_coords = []
            for x, y in polygon_coords:
                utm_coords.append([x, y])

            # Close the polygon if not already closed
            if utm_coords[0] != utm_coords[-1]:
                utm_coords.append(utm_coords[0])

            # Create vegetation feature
            vegetation_area = {
                "type": "Feature",
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [utm_coords]
                },
                "properties": {
                    "polygon_id": len(vegetation_areas) + 1,
                    "class": "8_OtherVegetation",
                    "chunk": chunk_name,
                    "area_m2": round(area_m2, 2),
                    "perimeter_m": round(perimeter_m, 2),
                    "point_count": len(cluster_points),
                    "aspect_ratio": round(aspect_ratio, 2),
                    "compactness": round(compactness, 3),
                    "extraction_method": "python_vegetation_enhanced_fixed1"
                }
            }

            vegetation_areas.append(vegetation_area)
            vegetation_polygons.append(polygon_coords)

            print(f"✅ Vegetation #{len(vegetation_areas)}: {area_m2:.1f}m², {len(cluster_points)} pts, {aspect_ratio:.1f}:1, compact={compactness:.2f}")

        elapsed_time = time.time() - start_time

        print(f"\n{'='*70}")
        print(f"📊 EXTRACTION SUMMARY")
        print(f"{'='*70}")
        print(f"✅ Vegetation areas extracted: {len(vegetation_areas)}")
        print(f"❌ Rejected clusters: {sum(rejected_stats.values())}")
        print(f"   • Too few points: {rejected_stats['too_few_points']}")
        print(f"   • Too small (<8 m²): {rejected_stats['too_small']}")
        print(f"   • Too large (>3000 m²): {rejected_stats['too_large']}")
        print(f"   • Aspect ratio (>20:1): {rejected_stats['aspect_ratio']}")
        print(f"   • Overlap (<5m): {rejected_stats['overlap']}")
        print(f"   • Invalid polygon: {rejected_stats['invalid_polygon']}")

        if len(vegetation_areas) == 0:
            print(f"\n❌ No valid vegetation areas after filtering")
            print(f"⏱️  Processing time: {elapsed_time:.1f}s")
            return 0

        # Calculate statistics
        total_area = sum(area["properties"]["area_m2"] for area in vegetation_areas)
        avg_area = total_area / len(vegetation_areas)
        areas = [v["properties"]["area_m2"] for v in vegetation_areas]
        min_area = min(areas)
        max_area = max(areas)

        print(f"\n📈 Vegetation Statistics:")
        print(f"   • Total area: {total_area:.1f} m²")
        print(f"   • Average area: {avg_area:.1f} m²")
        print(f"   • Size range: {min_area:.1f} - {max_area:.1f} m²")

        # Create GeoJSON output
        geojson_data = {
            "type": "FeatureCollection",
            "features": vegetation_areas,
            "properties": {
                "class": "8_OtherVegetation",
                "chunk": chunk_name,
                "extraction_method": "python_vegetation_enhanced_fixed1",
                "processing_time_seconds": round(elapsed_time, 1),
                "parameters": {
                    "voxel_size_m": 0.4,
                    "dbscan_eps_m": eps,
                    "dbscan_min_samples": min_samples,
                    "size_range_m2": [8, 3000],
                    "max_aspect_ratio": 20,
                    "min_overlap_distance_m": 5,
                    "outlier_threshold_factor": 2.5
                },
                "results": {
                    "input_points": len(points_3d),
                    "voxel_filtered_points": len(voxel_filtered),
                    "clean_points": len(clean_points_2d),
                    "clusters_found": n_clusters,
                    "vegetation_areas": len(vegetation_areas),
                    "total_area_m2": round(total_area, 2),
                    "avg_area_m2": round(avg_area, 2)
                }
            }
        }

        # Save GeoJSON file
        with open(output_file, 'w') as f:
            json.dump(geojson_data, f, indent=2)

        print(f"\n✅ SUCCESS!")
        print(f"📁 Output: {output_file}")
        print(f"⏱️  Processing time: {elapsed_time:.1f}s")
        print(f"{'='*70}\n")

        return len(vegetation_areas)

    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return 0

def calculate_compactness(area, perimeter):
    """
    Calculate compactness ratio (how circular the shape is)
    Compactness = 4π * Area / Perimeter²
    Perfect circle = 1.0, irregular shapes < 0.5
    """
    try:
        if perimeter > 0:
            return (4 * math.pi * area) / (perimeter ** 2)
        return 0
    except:
        return 0

def create_vegetation_polygon(points_2d):
    """Create natural vegetation polygon with curved boundaries"""
    try:
        if len(points_2d) < 6:
            return None

        # Method 1: Try alpha shape with relaxed alpha for natural boundaries
        try:
            hull = create_vegetation_concave_hull(points_2d, alpha=5.0)  # FIXED: 5.0 instead of 4.0
            if hull is not None and len(hull) >= 6:
                # Relaxed simplification for natural boundaries
                simplified = simplify_vegetation_polygon(hull, tolerance=0.7)  # FIXED: 0.7 instead of 0.5
                if simplified is not None and len(simplified) >= 6:
                    return simplified
        except:
            pass

        # Method 2: Fallback to convex hull
        try:
            hull = ConvexHull(points_2d)
            hull_points = points_2d[hull.vertices]

            hull_coords = hull_points.tolist()
            if len(hull_coords) > 0 and hull_coords[0] != hull_coords[-1]:
                hull_coords.append(hull_coords[0])

            return hull_coords

        except:
            pass

        # Method 3: Final fallback to axis-aligned bounding box
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

def create_vegetation_concave_hull(points, alpha=5.0):
    """Create concave hull optimized for vegetation boundaries"""
    try:
        if len(points) < 6:
            return None

        # Build k-d tree for efficient neighbor finding
        tree = cKDTree(points)

        # Find boundary points with relaxed alpha for natural vegetation boundaries
        boundary_points = []

        for i, point in enumerate(points):
            neighbors = tree.query_ball_point(point, alpha)

            # FIXED: Relaxed boundary detection (10 instead of 8)
            if len(neighbors) <= 10:
                boundary_points.append(point)

        if len(boundary_points) < 6:
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

def simplify_vegetation_polygon(coords, tolerance=0.7):
    """Simplify vegetation polygon with relaxed tolerance for natural boundaries"""
    try:
        if len(coords) < 6:
            return coords

        # Douglas-Peucker with looser tolerance for vegetation
        def dp_simplify(points, epsilon):
            if len(points) <= 3:
                return points

            max_dist = 0
            index = 0

            for i in range(1, len(points) - 1):
                dist = point_to_line_distance(points[i], points[0], points[-1])
                if dist > max_dist:
                    max_dist = dist
                    index = i

            if max_dist > epsilon:
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

        num = abs((y2-y1)*x0 - (x2-x1)*y0 + x2*y1 - y2*x1)
        den = math.sqrt((y2-y1)**2 + (x2-x1)**2)

        if den == 0:
            return math.sqrt((x0-x1)**2 + (y0-y1)**2)

        return num / den

    except:
        return 0

def calculate_polygon_area(coords):
    """Calculate polygon area using shoelace formula"""
    try:
        if len(coords) < 4:
            return 0

        x = [point[0] for point in coords[:-1]]
        y = [point[1] for point in coords[:-1]]

        return 0.5 * abs(sum(x[i]*y[i+1] - x[i+1]*y[i] for i in range(-1, len(x)-1)))

    except:
        return 0

def calculate_polygon_perimeter(coords):
    """Calculate polygon perimeter"""
    try:
        if len(coords) < 3:
            return 0

        perimeter = 0
        for i in range(len(coords) - 1):
            x1, y1 = coords[i]
            x2, y2 = coords[i + 1]
            perimeter += math.sqrt((x2 - x1)**2 + (y2 - y1)**2)

        return perimeter

    except:
        return 0

def calculate_aspect_ratio(coords):
    """Calculate aspect ratio of polygon bounding box"""
    try:
        if len(coords) < 3:
            return 1.0

        xs = [point[0] for point in coords]
        ys = [point[1] for point in coords]

        width = max(xs) - min(xs)
        height = max(ys) - min(ys)

        if height == 0:
            return float('inf')

        return max(width, height) / min(width, height)

    except:
        return 1.0

def has_overlap_with_existing(new_polygon, existing_polygons, min_distance=5.0):
    """
    Check if new polygon overlaps significantly with existing ones
    FIXED: Using 5m minimum distance and center-based check instead of bounding box
    """
    try:
        for existing in existing_polygons:
            # Calculate centers
            new_xs = [p[0] for p in new_polygon]
            new_ys = [p[1] for p in new_polygon]
            exist_xs = [p[0] for p in existing]
            exist_ys = [p[1] for p in existing]

            new_center_x = sum(new_xs) / len(new_xs)
            new_center_y = sum(new_ys) / len(new_ys)
            exist_center_x = sum(exist_xs) / len(exist_xs)
            exist_center_y = sum(exist_ys) / len(exist_ys)

            # Calculate center distance
            distance = math.sqrt((new_center_x - exist_center_x)**2 +
                               (new_center_y - exist_center_y)**2)

            # FIXED: 5m minimum distance instead of bounding box overlap
            if distance < min_distance:
                return True

        return False

    except:
        return False

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 python_vegetation_enhanced_fixed1.py <chunk_path>")
        print("Examples:")
        print("  python3 python_vegetation_enhanced_fixed1.py /path/to/chunk_1")
        print("  python3 python_vegetation_enhanced_fixed1.py /path/to/chunk_1/compressed/filtred_by_classes")
        sys.exit(1)

    chunk_path = sys.argv[1]

    # Validate path exists
    if not os.path.exists(chunk_path):
        print(f"❌ Path not found: {chunk_path}")
        sys.exit(1)

    result = extract_vegetation_polygons_enhanced(chunk_path)

    if result > 0:
        print(f"🎉 Success! Extracted {result} vegetation areas")
    else:
        print(f"❌ Failed to extract vegetation areas")
        sys.exit(1)
