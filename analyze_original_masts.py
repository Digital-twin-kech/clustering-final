#!/usr/bin/env python3

import json
import os
import math

def load_metadata(metadata_file):
    """Load metadata from JSON file"""
    try:
        with open(metadata_file, 'r') as f:
            return json.load(f)
    except:
        return None

def calculate_distance(coord1, coord2):
    """Calculate 3D distance between two points"""
    return math.sqrt(
        (coord1['x'] - coord2['x'])**2 +
        (coord1['y'] - coord2['y'])**2 +
        (coord1['z'] - coord2['z'])**2
    )

def analyze_original_masts():
    """Analyze original masts instances before cleaning"""

    base_dir = "/home/prodair/Desktop/MORIUS5090/clustering"
    original_data_dir = f"{base_dir}/out/job-20250911110357"
    metadata_dir = f"{base_dir}/out/dashboard_metadata"

    print("=== ORIGINAL MASTS ANALYSIS (Before Stage 4) ===")
    print("Finding over-segmented masts instances that need merging...\n")

    all_instances = []
    merge_candidates = []

    # Process each chunk
    chunks_dir = os.path.join(original_data_dir, 'chunks')
    for chunk_name in os.listdir(chunks_dir):
        chunk_path = os.path.join(chunks_dir, chunk_name)
        if not os.path.isdir(chunk_path):
            continue

        masts_instances_dir = os.path.join(chunk_path, 'compressed', 'filtred_by_classes', '12_Masts', 'instances')
        if not os.path.exists(masts_instances_dir):
            continue

        print(f"Chunk: {chunk_name}")
        chunk_instances = []

        # Get all masts instances
        for laz_file in os.listdir(masts_instances_dir):
            if not laz_file.endswith('.laz'):
                continue

            instance_name = laz_file[:-4]  # Remove .laz
            metadata_file = os.path.join(
                metadata_dir, 'chunks', chunk_name, 'filtred_by_classes', '12_Masts',
                f'{chunk_name}_compressed_filtred_by_classes_12_Masts_instances_{instance_name}_metadata.json'
            )

            metadata = load_metadata(metadata_file)
            if not metadata:
                continue

            instance_info = {
                'chunk': chunk_name,
                'name': instance_name,
                'file': laz_file,
                'point_count': metadata['geometry']['stats']['point_count'],
                'centroid': metadata['geometry']['centroid'],
                'height': metadata['geometry']['bbox']['dimensions']['height'],
                'bbox': metadata['geometry']['bbox']
            }

            chunk_instances.append(instance_info)
            all_instances.append(instance_info)

        print(f"  Found {len(chunk_instances)} masts instances")

        # Find merge candidates within chunk
        for i, inst1 in enumerate(chunk_instances):
            for j, inst2 in enumerate(chunk_instances):
                if i >= j:
                    continue

                distance = calculate_distance(inst1['centroid'], inst2['centroid'])

                # Merge criteria: close distance AND small instances
                if distance <= 2.5 and (inst1['point_count'] < 300 or inst2['point_count'] < 300):
                    merge_candidates.append({
                        'chunk': chunk_name,
                        'instance1': inst1,
                        'instance2': inst2,
                        'distance': distance,
                        'combined_points': inst1['point_count'] + inst2['point_count'],
                        'priority': 'HIGH' if min(inst1['point_count'], inst2['point_count']) < 150 else 'MEDIUM'
                    })

        print()

    # Analysis summary
    print("=== ANALYSIS RESULTS ===")
    print(f"Total masts instances across all chunks: {len(all_instances)}")
    print(f"Potential merge pairs found: {len(merge_candidates)}")

    if all_instances:
        point_counts = [inst['point_count'] for inst in all_instances]
        small_instances = [inst for inst in all_instances if inst['point_count'] < 200]
        tiny_instances = [inst for inst in all_instances if inst['point_count'] < 150]

        print(f"\nPoint count statistics:")
        print(f"  Instances with <200 points: {len(small_instances)} ({len(small_instances)/len(all_instances)*100:.1f}%)")
        print(f"  Instances with <150 points: {len(tiny_instances)} ({len(tiny_instances)/len(all_instances)*100:.1f}%)")
        print(f"  Average points: {sum(point_counts)/len(point_counts):.0f}")
        print(f"  Range: {min(point_counts)} - {max(point_counts)} points")

    # Show top merge candidates
    if merge_candidates:
        print(f"\n=== TOP MERGE CANDIDATES ===")
        # Sort by priority (HIGH first) and then by distance
        sorted_candidates = sorted(merge_candidates, key=lambda x: (x['priority'] == 'MEDIUM', x['distance']))

        print("High Priority Merges (very small instances):")
        high_priority = [mc for mc in sorted_candidates if mc['priority'] == 'HIGH']
        for mc in high_priority[:10]:
            print(f"  {mc['chunk']}: {mc['instance1']['name']} ({mc['instance1']['point_count']} pts) + {mc['instance2']['name']} ({mc['instance2']['point_count']} pts)")
            print(f"    Distance: {mc['distance']:.1f}m, Combined: {mc['combined_points']} points")

        print(f"\nMedium Priority Merges:")
        medium_priority = [mc for mc in sorted_candidates if mc['priority'] == 'MEDIUM']
        for mc in medium_priority[:5]:
            print(f"  {mc['chunk']}: {mc['instance1']['name']} ({mc['instance1']['point_count']} pts) + {mc['instance2']['name']} ({mc['instance2']['point_count']} pts)")
            print(f"    Distance: {mc['distance']:.1f}m, Combined: {mc['combined_points']} points")

    # Save results
    result = {
        'total_instances': len(all_instances),
        'merge_candidates': len(merge_candidates),
        'merge_pairs': merge_candidates,
        'instance_stats': {
            'small_instances': len(small_instances) if all_instances else 0,
            'tiny_instances': len(tiny_instances) if all_instances else 0,
            'average_points': sum(point_counts)/len(point_counts) if point_counts else 0
        }
    }

    output_file = f"{base_dir}/temp/original_masts_analysis.json"
    os.makedirs(f"{base_dir}/temp", exist_ok=True)
    with open(output_file, 'w') as f:
        json.dump(result, f, indent=2)

    print(f"\nAnalysis saved to: {output_file}")
    return result

if __name__ == "__main__":
    analyze_original_masts()