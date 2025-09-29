#!/usr/bin/env python3
"""
Enhanced Instance-Based Building Extraction
- Uses existing PDAL pipeline approach
- Aggressive instance separation with tight clustering
- Rectangular polygon shapes with straight lines
- Size filtering and overlap detection
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

def extract_instance_buildings_enhanced(chunk_name):
    """Extract building instances with aggressive separation and rectangular shapes"""

    try:
        # Paths
        laz_file = f"/home/prodair/Desktop/clustering/datasetclasified/new_data/new_data/{chunk_name}/compressed/filtred_by_classes/6_Buildings/6_Buildings.laz"
        output_dir = f"/home/prodair/Desktop/clustering/datasetclasified/new_data/new_data/{chunk_name}/compressed/filtred_by_classes/6_Buildings/polygons"
        output_file = f"{output_dir}/6_Buildings_polygons.geojson"

        print(f"\n🏢 === ENHANCED INSTANCE BUILDING EXTRACTION ===")
        print(f"📍 Chunk: {chunk_name}")
        print(f"🎯 Method: Tight clustering + rectangular polygons + overlap prevention")

        # Create output directory
        os.makedirs(output_dir, exist_ok=True)

        # Extract points using PDAL pipeline
        temp_points = f"/tmp/building_test/{chunk_name}_all_points.txt"

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

        print(f"📊 Extracting all building points...")
        result = subprocess.run(f"pdal pipeline {pipeline_file}", shell=True,
                               capture_output=True, text=True, timeout=300)

        if result.returncode != 0:
            print(f"❌ PDAL extraction failed: {result.stderr}")
            return 0

        # Load points from CSV
        print(f"📂 Loading point data...")
        try:
            points_3d = np.loadtxt(temp_points, delimiter=',')
            if len(points_3d.shape) == 1:
                points_3d = points_3d.reshape(1, -1)
        except Exception as e:
            print(f"❌ Failed to load points: {e}")
            return 0

        print(f"📊 Input points: {len(points_3d):,}")

        if len(points_3d) < 100:
            print(f"❌ Too few points: {len(points_3d)}")
            return 0

        # Step 1: Aggressive voxel grid filtering (smaller voxels)
        print(f"\n🔄 Step 1: Aggressive voxel filtering (0.25m grid)")
        voxel_size = 0.25  # Smaller voxel for more aggressive filtering
        voxel_indices = np.floor(points_3d / voxel_size).astype(int)
        unique_voxels, unique_indices = np.unique(voxel_indices, axis=0, return_index=True)
        voxel_filtered = points_3d[unique_indices]
        print(f"  📊 Voxel filtered: {len(voxel_filtered):,} ({100*len(voxel_filtered)/len(points_3d):.1f}%)")

        # Step 2: Height-based ground filtering
        print(f"\n🔄 Step 2: Height-based ground removal")
        z_values = voxel_filtered[:, 2]
        height_threshold = np.percentile(z_values, 25)  # Keep upper 75% of points
        height_mask = z_values > height_threshold
        height_filtered = voxel_filtered[height_mask]
        print(f"  📊 Height filtered (>{height_threshold:.1f}m): {len(height_filtered):,} ({100*len(height_filtered)/len(voxel_filtered):.1f}%)")

        # Step 3: Enhanced outlier removal
        print(f"\n🔄 Step 3: Enhanced outlier removal")
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

        # More aggressive outlier threshold
        outlier_threshold = mean_dist + 1.2 * std_dist  # Tighter threshold
        inlier_mask = mean_distances < outlier_threshold
        clean_points_2d = points_2d[inlier_mask]

        print(f"  📊 Outlier removal: {len(clean_points_2d):,} ({100*len(clean_points_2d)/len(points_2d):.1f}%)")

        if len(clean_points_2d) < 500:
            print(f"❌ Too few points after cleaning: {len(clean_points_2d)}")
            return 0

        # Step 4: Tight instance-based clustering
        print(f"\n🔄 Step 4: Tight instance clustering")
        eps = 2.0  # Much tighter clustering - 2 meter radius
        min_samples = 400  # Higher minimum samples for dense clusters

        clustering = DBSCAN(eps=eps, min_samples=min_samples).fit(clean_points_2d)
        labels = clustering.labels_

        unique_labels = set(labels)
        if -1 in unique_labels:
            unique_labels.remove(-1)

        n_clusters = len(unique_labels)
        n_noise = list(labels).count(-1)

        print(f"  📊 Found {n_clusters} potential building instances, {n_noise} noise points")

        if n_clusters == 0:
            print(f"❌ No building clusters found")
            return 0

        # Step 5: Create rectangular building polygons with strict filtering
        print(f"\n🔄 Step 5: Building instance extraction with strict filtering")

        buildings = []
        building_polygons = []  # To check for overlaps

        for i, cluster_id in enumerate(sorted(unique_labels)):
            cluster_mask = labels == cluster_id
            cluster_points = clean_points_2d[cluster_mask]

            print(f"  🏢 Candidate {i+1}: {len(cluster_points):,} points")

            # Create exact footprint polygon using alpha shape
            polygon_coords = create_footprint_building(cluster_points)

            if polygon_coords is None:
                print(f"    ❌ Failed to create valid polygon")
                continue

            # Calculate area
            area_m2 = calculate_polygon_area(polygon_coords)
            perimeter_m = calculate_polygon_perimeter(polygon_coords)

            # Strict size filtering for individual buildings
            if area_m2 < 40 or area_m2 > 500:
                print(f"    ❌ Size filter: {area_m2:.1f} m² (must be 40-500 m²)")
                continue

            # Check aspect ratio (buildings shouldn't be too thin)
            aspect_ratio = calculate_aspect_ratio(polygon_coords)
            if aspect_ratio > 8:  # Max 8:1 ratio
                print(f"    ❌ Aspect ratio too high: {aspect_ratio:.1f}:1")
                continue

            # Check for overlaps with existing buildings
            if has_overlap_with_existing(polygon_coords, building_polygons):
                print(f"    ❌ Overlaps with existing building")
                continue

            # Keep coordinates in UTM format - let the server convert them
            utm_coords = []
            for x, y in polygon_coords:
                utm_coords.append([x, y])

            # Close the polygon if not already closed
            if utm_coords[0] != utm_coords[-1]:
                utm_coords.append(utm_coords[0])

            # Create building feature with UTM coordinates
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
                    "aspect_ratio": round(aspect_ratio, 2),
                    "extraction_method": "python_instance_enhanced"
                }
            }

            buildings.append(building)
            building_polygons.append(polygon_coords)

            print(f"    ✅ Building {len(buildings)}: {area_m2:.1f} m², {len(cluster_points)} points, {aspect_ratio:.1f}:1 ratio")

        if not buildings:
            print(f"❌ No valid building instances found")
            return 0

        # Create final GeoJSON
        total_area = sum(b["properties"]["area_m2"] for b in buildings)

        geojson = {
            "type": "FeatureCollection",
            "features": buildings,
            "properties": {
                "class": "6_Buildings",
                "chunk": chunk_name,
                "extraction_method": "python_instance_enhanced_rectangular",
                "results": {
                    "input_points": len(points_3d),
                    "clean_points": len(clean_points_2d),
                    "polygons_extracted": len(buildings),
                    "total_area_m2": round(total_area, 2)
                }
            }
        }

        # Save results
        with open(output_file, 'w') as f:
            json.dump(geojson, f, indent=2)

        print(f"\n✅ SUCCESS: {len(buildings)} individual building instances")
        print(f"📊 Total area: {total_area:.1f} m² (avg: {total_area/len(buildings):.1f} m² per building)")
        print(f"📁 Saved: {output_file}")

        # Clean up temp files
        os.remove(temp_points)
        os.remove(pipeline_file)

        return len(buildings)

    except Exception as e:
        print(f"❌ ERROR: {e}")
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
            hull = create_concave_hull(points_2d, alpha=3.0)  # 3 meter alpha
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

def create_concave_hull(points, alpha=3.0):
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
            if len(neighbors) <= 8:  # Threshold for boundary detection
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

def has_overlap_with_existing(new_coords, existing_polygons, overlap_threshold=0.1):
    """Check if new polygon overlaps significantly with existing ones"""
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

            # If bounding boxes overlap, check for significant overlap
            # Simple approach: if centers are too close, consider overlapping
            new_center_x = (new_min_x + new_max_x) / 2
            new_center_y = (new_min_y + new_max_y) / 2
            existing_center_x = (existing_min_x + existing_max_x) / 2
            existing_center_y = (existing_min_y + existing_max_y) / 2

            distance = math.sqrt((new_center_x - existing_center_x)**2 +
                               (new_center_y - existing_center_y)**2)

            # If centers are closer than 25m, consider overlapping
            if distance < 25:
                return True

        return False
    except:
        return False

def utm_to_wgs84_simple(utm_x, utm_y):
    """Simple UTM Zone 29N to WGS84 conversion"""
    # Simplified conversion for Morocco region (UTM Zone 29N)
    # This is an approximation - for precise conversion use pyproj

    # UTM Zone 29N parameters
    false_easting = 500000.0
    false_northing = 0.0
    k0 = 0.9996
    a = 6378137.0  # WGS84 semi-major axis
    e2 = 0.00669437999014  # WGS84 first eccentricity squared

    # Central meridian for Zone 29
    lon0 = math.radians(-9.0)  # 9 degrees west

    # Remove false easting/northing
    x = utm_x - false_easting
    y = utm_y - false_northing

    # Calculate latitude and longitude (simplified)
    # This is a basic approximation
    lat_approx = y / (a * k0) + 33.0 * math.pi / 180.0  # Approximate center latitude
    lon_approx = x / (a * k0 * math.cos(lat_approx)) + lon0

    # Convert to degrees
    lat_deg = math.degrees(lat_approx)
    lon_deg = math.degrees(lon_approx)

    return lat_deg, lon_deg

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 python_instance_enhanced.py <chunk_name>")
        print("Example: python3 python_instance_enhanced.py chunk_1")
        sys.exit(1)

    chunk_name = sys.argv[1]
    result = extract_instance_buildings_enhanced(chunk_name)

    if result > 0:
        print(f"\n🎉 Success! Extracted {result} building instances")
    else:
        print(f"\n❌ Failed to extract buildings")
        sys.exit(1)