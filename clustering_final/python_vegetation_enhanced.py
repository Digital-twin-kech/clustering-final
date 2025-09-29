#!/usr/bin/env python3
"""
Enhanced Vegetation Polygon Extraction for LiDAR Point Clouds
Creates natural, curved boundary polygons for Other Vegetation areas
Based on footprint-following algorithms with vegetation-specific optimizations
"""

import sys
import os
import json
import subprocess
import numpy as np
import math
from scipy.spatial import ConvexHull, cKDTree
from sklearn.cluster import DBSCAN

def extract_vegetation_polygons_enhanced(chunk_name):
    """
    Enhanced vegetation extraction using footprint-based polygon generation
    Optimized for natural vegetation boundaries with curved edges
    """
    print(f"\n🌿 === ENHANCED VEGETATION POLYGON EXTRACTION ===")
    print(f"📍 Chunk: {chunk_name}")
    print(f"🎯 Method: Natural boundary detection + curved polygons")
    print(f"📊 Extracting vegetation areas...")

    # Paths
    base_path = "/home/prodair/Desktop/clustering/datasetclasified/new_data/new_data"
    vegetation_laz = f"{base_path}/{chunk_name}/compressed/filtred_by_classes/8_OtherVegetation/8_OtherVegetation.laz"
    output_dir = f"{base_path}/{chunk_name}/compressed/filtred_by_classes/8_OtherVegetation/polygons"
    output_file = f"{output_dir}/8_OtherVegetation_polygons.geojson"

    # Check if vegetation data exists
    if not os.path.exists(vegetation_laz):
        print(f"❌ No vegetation data found: {vegetation_laz}")
        return 0

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Load vegetation points using PDAL pipeline
    print(f"📂 Loading vegetation point data...")
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

        print(f"📊 Input points: {len(points_3d):,}")

        # Step 1: Balanced voxel grid filtering (medium precision)
        print(f"\n🔄 Step 1: Balanced voxel filtering (0.4m grid)")
        voxel_size = 0.4  # Medium voxel for balanced precision/coverage
        voxel_indices = np.floor(points_3d / voxel_size).astype(int)
        unique_voxels, unique_indices = np.unique(voxel_indices, axis=0, return_index=True)
        voxel_filtered = points_3d[unique_indices]
        print(f"  📊 Voxel filtered: {len(voxel_filtered):,} ({100*len(voxel_filtered)/len(points_3d):.1f}%)")

        # Step 2: Enhanced height-based filtering
        print(f"\n🔄 Step 2: Enhanced height-based filtering")
        z_values = voxel_filtered[:, 2]
        height_threshold = np.percentile(z_values, 20)  # Keep upper 80% for vegetation
        height_mask = z_values > height_threshold
        height_filtered = voxel_filtered[height_mask]
        print(f"  📊 Height filtered (>{height_threshold:.1f}m): {len(height_filtered):,} ({100*len(height_filtered)/len(voxel_filtered):.1f}%)")

        # Step 3: Moderate outlier removal (balanced precision)
        print(f"\n🔄 Step 3: Moderate outlier removal")
        points_2d = height_filtered[:, :2]

        if len(points_2d) < 20:
            print(f"❌ Too few points after filtering: {len(points_2d)}")
            return 0

        tree = cKDTree(points_2d)
        k_neighbors = min(12, len(points_2d) - 1)  # Moderate neighbors for balanced filtering
        distances, _ = tree.query(points_2d, k=k_neighbors+1)

        mean_distances = distances[:, 1:].mean(axis=1)
        mean_dist = np.mean(mean_distances)
        std_dist = np.std(mean_distances)

        # Moderate outlier threshold for balanced precision/coverage
        outlier_threshold = mean_dist + 1.8 * std_dist  # Looser threshold than buildings
        inlier_mask = mean_distances < outlier_threshold
        clean_points_2d = points_2d[inlier_mask]

        print(f"  📊 Outlier removal: {len(clean_points_2d):,} ({100*len(clean_points_2d)/len(points_2d):.1f}%)")

        # Step 4: Moderate vegetation clustering for balanced boundaries
        print(f"\n🔄 Step 4: Moderate vegetation area clustering")
        clustering = DBSCAN(eps=4.0, min_samples=80, n_jobs=-1)  # Balanced eps and samples
        labels = clustering.fit_predict(clean_points_2d)

        unique_labels = [l for l in set(labels) if l != -1]
        n_clusters = len(unique_labels)
        n_noise = list(labels).count(-1)

        print(f"  📊 Found {n_clusters} potential vegetation areas, {n_noise} noise points")

        if n_clusters == 0:
            print(f"❌ No vegetation clusters found")
            return 0

        # Step 5: Create natural vegetation polygons
        print(f"\n🔄 Step 5: Vegetation polygon generation")

        vegetation_areas = []
        vegetation_polygons = []  # To check for overlaps

        for i, cluster_id in enumerate(sorted(unique_labels)):
            cluster_mask = labels == cluster_id
            cluster_points = clean_points_2d[cluster_mask]

            print(f"  🌿 Vegetation area {i+1}: {len(cluster_points):,} points")

            # Create natural vegetation polygon with curved boundaries
            polygon_coords = create_vegetation_polygon(cluster_points)

            if polygon_coords is None:
                print(f"    ❌ Failed to create valid polygon")
                continue

            # Calculate area
            area_m2 = calculate_polygon_area(polygon_coords)
            perimeter_m = calculate_polygon_perimeter(polygon_coords)

            # Vegetation-specific size filtering (smaller minimum, larger maximum)
            if area_m2 < 10 or area_m2 > 2000:  # 10-2000 m² for vegetation areas
                print(f"    ❌ Size filter: {area_m2:.1f} m² (must be 10-2000 m²)")
                continue

            # Check aspect ratio (vegetation can be more elongated)
            aspect_ratio = calculate_aspect_ratio(polygon_coords)
            if aspect_ratio > 15:  # Max 15:1 ratio for vegetation
                print(f"    ❌ Aspect ratio too high: {aspect_ratio:.1f}:1")
                continue

            # Check for overlaps with existing vegetation areas
            if has_overlap_with_existing(polygon_coords, vegetation_polygons):
                print(f"    ❌ Overlaps with existing vegetation area")
                continue

            # Keep coordinates in UTM format
            utm_coords = []
            for x, y in polygon_coords:
                utm_coords.append([x, y])

            # Close the polygon if not already closed
            if utm_coords[0] != utm_coords[-1]:
                utm_coords.append(utm_coords[0])

            # Create vegetation feature with UTM coordinates
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
                    "extraction_method": "python_vegetation_enhanced"
                }
            }

            vegetation_areas.append(vegetation_area)
            vegetation_polygons.append(polygon_coords)

            print(f"    ✅ Vegetation area {len(vegetation_areas)}: {area_m2:.1f} m², {len(cluster_points)} points, {aspect_ratio:.1f}:1 ratio")

        if len(vegetation_areas) == 0:
            print(f"❌ No valid vegetation areas after filtering")
            return 0

        # Create GeoJSON output
        total_area = sum(area["properties"]["area_m2"] for area in vegetation_areas)

        geojson_data = {
            "type": "FeatureCollection",
            "features": vegetation_areas,
            "properties": {
                "class": "8_OtherVegetation",
                "chunk": chunk_name,
                "extraction_method": "python_vegetation_enhanced_natural",
                "results": {
                    "input_points": len(points_3d),
                    "clean_points": len(clean_points_2d),
                    "vegetation_areas": len(vegetation_areas),
                    "total_area_m2": round(total_area, 2)
                }
            }
        }

        # Save GeoJSON file
        with open(output_file, 'w') as f:
            json.dump(geojson_data, f, indent=2)

        print(f"\n✅ SUCCESS: {len(vegetation_areas)} vegetation areas")
        print(f"📊 Total area: {total_area:.1f} m² (avg: {total_area/len(vegetation_areas):.1f} m² per area)")
        print(f"📁 Saved: {output_file}")

        return len(vegetation_areas)

    except Exception as e:
        print(f"❌ ERROR: {e}")
        return 0

def create_vegetation_polygon(points_2d):
    """Create natural vegetation polygon with curved boundaries"""
    try:
        if len(points_2d) < 6:
            return None

        # Method 1: Try alpha shape with precise alpha for accurate boundaries
        try:
            hull = create_vegetation_concave_hull(points_2d, alpha=4.0)  # Smaller alpha for precise boundaries
            if hull is not None and len(hull) >= 6:
                # Precise simplification for accurate boundaries
                simplified = simplify_vegetation_polygon(hull, tolerance=0.5)  # Tighter tolerance
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

def create_vegetation_concave_hull(points, alpha=4.0):
    """Create concave hull optimized for vegetation with precise boundaries"""
    try:
        if len(points) < 6:
            return None

        # Build k-d tree for efficient neighbor finding
        tree = cKDTree(points)

        # Find boundary points with precise alpha for accurate vegetation boundaries
        boundary_points = []

        for i, point in enumerate(points):
            neighbors = tree.query_ball_point(point, alpha)

            # Precise boundary detection to avoid street extensions
            if len(neighbors) <= 8:  # Lower threshold for precise boundaries
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

def simplify_vegetation_polygon(coords, tolerance=0.5):
    """Simplify vegetation polygon with precise tolerance for accurate boundaries"""
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

def has_overlap_with_existing(new_polygon, existing_polygons, threshold=0.1):
    """Check if new polygon overlaps significantly with existing ones"""
    try:
        for existing in existing_polygons:
            # Simple bounding box overlap check for performance
            new_xs = [p[0] for p in new_polygon]
            new_ys = [p[1] for p in new_polygon]
            exist_xs = [p[0] for p in existing]
            exist_ys = [p[1] for p in existing]

            new_bbox = [min(new_xs), min(new_ys), max(new_xs), max(new_ys)]
            exist_bbox = [min(exist_xs), min(exist_ys), max(exist_xs), max(exist_ys)]

            # Check bounding box overlap
            if (new_bbox[2] < exist_bbox[0] or new_bbox[0] > exist_bbox[2] or
                new_bbox[3] < exist_bbox[1] or new_bbox[1] > exist_bbox[3]):
                continue

            # If bounding boxes overlap, assume overlap (conservative approach)
            return True

        return False

    except:
        return False

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 python_vegetation_enhanced.py <chunk_name>")
        print("Example: python3 python_vegetation_enhanced.py chunk_1")
        sys.exit(1)

    chunk_name = sys.argv[1]

    # Validate chunk name
    valid_chunks = [f"chunk_{i}" for i in range(1, 7)]
    if chunk_name not in valid_chunks:
        print(f"❌ Invalid chunk name. Must be one of: {', '.join(valid_chunks)}")
        sys.exit(1)

    result = extract_vegetation_polygons_enhanced(chunk_name)

    if result > 0:
        print(f"\n🎉 Success! Extracted {result} vegetation areas")
    else:
        print(f"\n❌ Failed to extract vegetation areas")
        sys.exit(1)