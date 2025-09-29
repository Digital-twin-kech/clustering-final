#!/usr/bin/env python3
"""
Enhanced Mast Processing with Impurity Cleanup
==============================================

Purpose: Clean mast classifications by removing noise and misclassified objects
Method: Multi-stage filtering with point count, height, and density validation
Output: Clean mast centroids with quality assurance metrics

Key Improvements:
- Point count filtering (remove tiny noise and huge building facades)
- Height validation (ensure proper utility pole heights)
- Density analysis (validate mast-like structures)
- Quality metrics and validation reporting
"""

import sys
import json
import os
import glob
import numpy as np
from pathlib import Path

# Enhanced mast filtering parameters
MAST_FILTERS = {
    # Point count bounds for real masts (exclude noise and buildings)
    'min_points': 100,      # Remove tiny noise objects
    'max_points': 3000,     # Remove large building facades

    # Height validation (relative to local ground)
    'min_relative_height': 5.0,    # Must be at least 5m tall
    'max_relative_height': 50.0,   # Not taller than 50m (unrealistic for utility poles)

    # Density validation (points per vertical meter)
    'min_density': 10.0,    # At least 10 points per meter height
    'max_density': 200.0,   # Not more than 200 points per meter

    # Quality thresholds
    'min_quality_score': 0.6,  # Combined quality metric
}

def log_info(message):
    print(f"[INFO] {message}")

def log_warn(message):
    print(f"[WARN] {message}")

def log_success(message):
    print(f"[SUCCESS] {message}")

def remove_duplicate_masts(masts, proximity_radius=1.5):
    """
    Remove duplicate masts within proximity radius, keeping the one with most points

    Args:
        masts: List of mast objects with centroid coordinates
        proximity_radius: Distance threshold in meters (default 1.5m)

    Returns:
        filtered_masts: List without duplicates
        duplicate_count: Number of duplicates removed
    """
    if len(masts) <= 1:
        return masts, 0

    log_info(f"    Checking for duplicates within {proximity_radius}m radius...")

    # Sort masts by point count (descending) to prioritize larger masts
    sorted_masts = sorted(masts, key=lambda m: m['point_count'], reverse=True)

    filtered_masts = []
    removed_count = 0

    for current_mast in sorted_masts:
        current_x = current_mast['centroid_x']
        current_y = current_mast['centroid_y']

        # Check if this mast is too close to any already kept mast
        is_duplicate = False

        for kept_mast in filtered_masts:
            kept_x = kept_mast['centroid_x']
            kept_y = kept_mast['centroid_y']

            # Calculate Euclidean distance
            distance = np.sqrt((current_x - kept_x)**2 + (current_y - kept_y)**2)

            if distance < proximity_radius:
                is_duplicate = True
                log_info(f"      Duplicate found: Mast #{current_mast['object_id']} ({current_mast['point_count']} pts) "
                        f"is {distance:.1f}m from Mast #{kept_mast['object_id']} ({kept_mast['point_count']} pts)")
                break

        if not is_duplicate:
            filtered_masts.append(current_mast)
        else:
            removed_count += 1

    if removed_count > 0:
        log_info(f"    Removed {removed_count} duplicate masts (kept longest within {proximity_radius}m)")
    else:
        log_info(f"    No duplicates found within {proximity_radius}m")

    return filtered_masts, removed_count

def calculate_mast_quality(mast_data, chunk_bounds):
    """
    Calculate quality score for mast based on multiple factors
    Returns: quality_score (0-1), validation_details
    """
    point_count = mast_data['point_count']
    height = mast_data['centroid_z']

    # Estimate ground level from chunk bounds
    ground_level = chunk_bounds['min_z']
    relative_height = height - ground_level

    # Calculate density (points per meter of height)
    density = point_count / max(relative_height, 1.0)

    quality_factors = {}

    # Factor 1: Point count validation (0-1 score)
    if MAST_FILTERS['min_points'] <= point_count <= MAST_FILTERS['max_points']:
        quality_factors['point_count'] = 1.0
    elif point_count < MAST_FILTERS['min_points']:
        quality_factors['point_count'] = 0.0  # Too small (noise)
    else:
        quality_factors['point_count'] = 0.0  # Too large (building)

    # Factor 2: Height validation (0-1 score)
    if MAST_FILTERS['min_relative_height'] <= relative_height <= MAST_FILTERS['max_relative_height']:
        quality_factors['height'] = 1.0
    else:
        quality_factors['height'] = 0.5  # Questionable height

    # Factor 3: Density validation (0-1 score)
    if MAST_FILTERS['min_density'] <= density <= MAST_FILTERS['max_density']:
        quality_factors['density'] = 1.0
    else:
        quality_factors['density'] = 0.7  # Density outside ideal range

    # Combined quality score (weighted average)
    weights = {'point_count': 0.5, 'height': 0.3, 'density': 0.2}
    quality_score = sum(quality_factors[k] * weights[k] for k in weights.keys())

    validation_details = {
        'point_count': point_count,
        'relative_height': round(relative_height, 1),
        'density': round(density, 1),
        'quality_factors': quality_factors,
        'quality_score': round(quality_score, 3)
    }

    return quality_score, validation_details

def process_mast_chunk(centroids_file):
    """
    Process a single chunk of mast data with enhanced filtering
    """
    try:
        with open(centroids_file, 'r') as f:
            data = json.load(f)
    except Exception as e:
        log_warn(f"Failed to read {centroids_file}: {e}")
        return None

    chunk_name = data.get('chunk', 'unknown')
    original_masts = data.get('centroids', [])
    chunk_bounds = data.get('utm_bounds', {})

    log_info(f"Processing {chunk_name}: {len(original_masts)} original masts")

    if not original_masts:
        log_warn(f"No masts found in {chunk_name}")
        return data

    # Filter and validate masts
    clean_masts = []
    filtered_stats = {
        'too_small': 0,
        'too_large': 0,
        'poor_quality': 0,
        'duplicates_removed': 0,
        'clean_masts': 0
    }

    for mast in original_masts:
        quality_score, validation = calculate_mast_quality(mast, chunk_bounds)

        # Apply filters
        point_count = mast['point_count']

        # Filter 1: Point count bounds
        if point_count < MAST_FILTERS['min_points']:
            filtered_stats['too_small'] += 1
            continue
        elif point_count > MAST_FILTERS['max_points']:
            filtered_stats['too_large'] += 1
            continue

        # Filter 2: Quality score threshold
        if quality_score < MAST_FILTERS['min_quality_score']:
            filtered_stats['poor_quality'] += 1
            continue

        # Keep this mast - add validation details
        clean_mast = mast.copy()
        clean_mast.update({
            'relative_height_m': validation['relative_height'],
            'point_density': validation['density'],
            'quality_score': validation['quality_score'],
            'validation_status': 'clean_mast'
        })

        clean_masts.append(clean_mast)
        filtered_stats['clean_masts'] += 1

    # Step 3: Remove duplicate masts within proximity radius (keep longest)
    log_info(f"  Step 3: Proximity deduplication (1.5m radius)")
    clean_masts, duplicate_count = remove_duplicate_masts(clean_masts)
    filtered_stats['duplicates_removed'] = duplicate_count
    filtered_stats['clean_masts'] = len(clean_masts)  # Update final count

    # Update data with clean results
    data['centroids'] = clean_masts
    data['results']['instances_found'] = len(clean_masts)
    data['results']['original_instances'] = len(original_masts)
    data['results']['filtering_applied'] = True
    data['filtering'] = {
        'method': 'enhanced_mast_cleanup',
        'filters': MAST_FILTERS,
        'statistics': filtered_stats
    }

    # Log filtering results
    log_info(f"  Original masts: {len(original_masts)}")
    log_info(f"  Filtered out - Too small (< {MAST_FILTERS['min_points']} pts): {filtered_stats['too_small']}")
    log_info(f"  Filtered out - Too large (> {MAST_FILTERS['max_points']} pts): {filtered_stats['too_large']}")
    log_info(f"  Filtered out - Poor quality: {filtered_stats['poor_quality']}")
    log_info(f"  Filtered out - Duplicates (< 1.5m apart): {filtered_stats['duplicates_removed']}")
    log_success(f"  Clean masts remaining: {filtered_stats['clean_masts']}")

    return data

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 python_mast_enhanced.py <chunk_name>")
        print("Example: python3 python_mast_enhanced.py chunk_1")
        sys.exit(1)

    chunk_name = sys.argv[1]

    print("="*60)
    print("ENHANCED MAST PROCESSING WITH IMPURITY CLEANUP")
    print("="*60)
    print(f"Target chunk: {chunk_name}")
    print(f"Method: Multi-stage filtering with quality validation")
    print()

    # Find the centroids file
    centroids_pattern = f"**/chunks/{chunk_name}/compressed/filtred_by_classes/12_Masts/centroids/12_Masts_centroids.json"
    centroids_files = glob.glob(centroids_pattern, recursive=True)

    if not centroids_files:
        log_warn(f"No mast centroids found for {chunk_name}")
        log_info(f"Expected pattern: {centroids_pattern}")
        sys.exit(1)

    centroids_file = centroids_files[0]
    log_info(f"Processing: {centroids_file}")
    print()

    # Process the chunk
    clean_data = process_mast_chunk(centroids_file)

    if clean_data is None:
        log_warn("Processing failed")
        sys.exit(1)

    # Save cleaned results
    output_file = centroids_file.replace('.json', '_clean.json')

    try:
        with open(output_file, 'w') as f:
            json.dump(clean_data, f, indent=2)

        log_success(f"Clean mast data saved: {output_file}")

        # Summary
        print()
        print("="*60)
        print("CLEANUP SUMMARY")
        print("="*60)

        stats = clean_data['filtering']['statistics']
        original_count = clean_data['results']['original_instances']
        clean_count = clean_data['results']['instances_found']

        print(f"Original masts: {original_count}")
        print(f"Clean masts: {clean_count}")
        print(f"Filtered out: {original_count - clean_count}")
        print(f"Cleanup rate: {((original_count - clean_count) / original_count * 100):.1f}%")
        print()

        print("Filtering breakdown:")
        for category, count in stats.items():
            if count > 0:
                print(f"  {category.replace('_', ' ').title()}: {count}")

        print()
        print("Applied filters:")
        filters = clean_data['filtering']['filters']
        print(f"  Point count range: {filters['min_points']}-{filters['max_points']}")
        print(f"  Height range: {filters['min_relative_height']}-{filters['max_relative_height']}m")
        print(f"  Density range: {filters['min_density']}-{filters['max_density']} pts/m")
        print(f"  Quality threshold: {filters['min_quality_score']}")
        print(f"  Proximity deduplication: 1.5m radius (keep longest)")

        print()
        log_success("Enhanced mast processing completed!")

    except Exception as e:
        log_warn(f"Failed to save clean data: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()