#!/usr/bin/env python3

import json
import os
import sys
from pathlib import Path
import math

def load_instance_metadata(metadata_dir, chunk_name, class_name, instance_name):
    """Load metadata for a specific instance"""
    metadata_file = os.path.join(
        metadata_dir, 'chunks', chunk_name, 'filtred_by_classes', class_name,
        f'{chunk_name}_compressed_filtred_by_classes_{class_name}_instances_{instance_name}_metadata.json'
    )

    if not os.path.exists(metadata_file):
        return None

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

def analyze_masts_instances():
    """Analyze all masts instances for potential merging"""

    base_dir = "/home/prodair/Desktop/MORIUS5090/clustering"
    cleaned_data_dir = f"{base_dir}/out/cleaned_data"
    metadata_dir = f"{base_dir}/out/dashboard_metadata"

    print("=== MASTS INSTANCE ANALYSIS ===")
    print("Looking for over-segmented instances that should be merged...\n")

    all_instances = []
    merge_candidates = []

    # Collect all masts instances across chunks
    chunks_dir = os.path.join(cleaned_data_dir, 'chunks')
    for chunk_name in os.listdir(chunks_dir):
        chunk_path = os.path.join(chunks_dir, chunk_name)
        if not os.path.isdir(chunk_path):
            continue

        masts_dir = os.path.join(chunk_path, '12_Masts')
        if not os.path.exists(masts_dir):
            continue

        print(f"Chunk: {chunk_name}")
        chunk_instances = []

        # Get all masts instances in this chunk
        for las_file in os.listdir(masts_dir):
            if not las_file.endswith('.las'):
                continue

            instance_name = las_file[:-4]  # Remove .las extension

            # Load metadata
            metadata = load_instance_metadata(metadata_dir, chunk_name, '12_Masts', instance_name)
            if not metadata:
                print(f"  WARNING: No metadata for {instance_name}")
                continue

            instance_info = {
                'chunk': chunk_name,
                'name': instance_name,
                'file': las_file,
                'point_count': metadata['geometry']['stats']['point_count'],
                'centroid': metadata['geometry']['centroid'],
                'height': metadata['geometry']['bbox']['dimensions']['height'],
                'bbox': metadata['geometry']['bbox']
            }

            chunk_instances.append(instance_info)
            all_instances.append(instance_info)

            print(f"  {instance_name}: {instance_info['point_count']} points, {instance_info['height']:.1f}m height")

        # Find merge candidates within this chunk
        print(f"  Analyzing {len(chunk_instances)} instances for merge candidates...")

        for i, inst1 in enumerate(chunk_instances):
            for j, inst2 in enumerate(chunk_instances):
                if i >= j:  # Avoid duplicates and self-comparison
                    continue

                distance = calculate_distance(inst1['centroid'], inst2['centroid'])

                # Merge criteria: within 2.5m distance AND at least one has <200 points
                if distance <= 2.5 and (inst1['point_count'] < 200 or inst2['point_count'] < 200):
                    merge_candidates.append({
                        'chunk': chunk_name,
                        'instance1': inst1,
                        'instance2': inst2,
                        'distance': distance,
                        'combined_points': inst1['point_count'] + inst2['point_count'],
                        'priority': 'HIGH' if min(inst1['point_count'], inst2['point_count']) < 150 else 'MEDIUM'
                    })

                    print(f"    MERGE CANDIDATE: {inst1['name']} ({inst1['point_count']} pts) + {inst2['name']} ({inst2['point_count']} pts) = {distance:.1f}m apart")

        print()

    # Summary
    print("=== ANALYSIS SUMMARY ===")
    print(f"Total masts instances: {len(all_instances)}")
    print(f"Merge candidates found: {len(merge_candidates)}")
    print()

    # Show statistics
    point_counts = [inst['point_count'] for inst in all_instances]
    small_instances = [inst for inst in all_instances if inst['point_count'] < 200]
    tiny_instances = [inst for inst in all_instances if inst['point_count'] < 150]

    print("=== POINT COUNT STATISTICS ===")
    print(f"Instances with <200 points: {len(small_instances)} ({len(small_instances)/len(all_instances)*100:.1f}%)")
    print(f"Instances with <150 points: {len(tiny_instances)} ({len(tiny_instances)/len(all_instances)*100:.1f}%)")
    print(f"Average points per instance: {sum(point_counts)/len(point_counts):.0f}")
    print(f"Min points: {min(point_counts)}, Max points: {max(point_counts)}")
    print()

    # Prioritized merge candidates
    if merge_candidates:
        print("=== PRIORITIZED MERGE CANDIDATES ===")
        high_priority = [mc for mc in merge_candidates if mc['priority'] == 'HIGH']
        medium_priority = [mc for mc in merge_candidates if mc['priority'] == 'MEDIUM']

        print(f"HIGH Priority (very small instances): {len(high_priority)}")
        for mc in high_priority[:5]:  # Show top 5
            print(f"  {mc['instance1']['name']} ({mc['instance1']['point_count']} pts) + {mc['instance2']['name']} ({mc['instance2']['point_count']} pts) -> {mc['combined_points']} pts, {mc['distance']:.1f}m")

        print(f"\nMEDIUM Priority: {len(medium_priority)}")
        for mc in medium_priority[:3]:  # Show top 3
            print(f"  {mc['instance1']['name']} ({mc['instance1']['point_count']} pts) + {mc['instance2']['name']} ({mc['instance2']['point_count']} pts) -> {mc['combined_points']} pts, {mc['distance']:.1f}m")

    # Save analysis results
    analysis_result = {
        'analysis_summary': {
            'total_instances': len(all_instances),
            'merge_candidates': len(merge_candidates),
            'small_instances_under_200': len(small_instances),
            'tiny_instances_under_150': len(tiny_instances),
            'average_points': sum(point_counts)/len(point_counts),
            'min_points': min(point_counts),
            'max_points': max(point_counts)
        },
        'merge_candidates': merge_candidates,
        'all_instances': all_instances
    }

    output_file = f"{base_dir}/temp/masts_analysis.json"
    os.makedirs(f"{base_dir}/temp", exist_ok=True)
    with open(output_file, 'w') as f:
        json.dump(analysis_result, f, indent=2)

    print(f"\nAnalysis saved to: {output_file}")
    return analysis_result

if __name__ == "__main__":
    analyze_masts_instances()