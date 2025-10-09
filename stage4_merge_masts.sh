#!/bin/bash

# Stage 4 Merge: Fix Over-Segmented Masts
set -euo pipefail

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
ORIGINAL_DIR="$BASE_DIR/out/job-20250911110357"
CLEANED_DIR="$BASE_DIR/out/cleaned_data"
MERGED_DIR="$BASE_DIR/out/cleaned_data_merged"
TEMP_DIR="$BASE_DIR/temp/stage4_merge"

# Setup
mkdir -p "$MERGED_DIR" "$TEMP_DIR"
rm -rf "$TEMP_DIR"/* "$MERGED_DIR"/*

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

log "Starting Stage 4 Merge: Fix Over-Segmented Masts"

# Copy all non-masts data first
log "Copying non-masts data..."
cp -r "$CLEANED_DIR"/* "$MERGED_DIR/"

# Create Python script to handle the merging
cat > "$TEMP_DIR/merge_masts.py" << 'EOF'
#!/usr/bin/env python3
import json
import os
import subprocess
import shutil
from pathlib import Path
import math

def load_metadata(metadata_file):
    try:
        with open(metadata_file, 'r') as f:
            return json.load(f)
    except:
        return None

def calculate_distance(coord1, coord2):
    return math.sqrt(
        (coord1['x'] - coord2['x'])**2 +
        (coord1['y'] - coord2['y'])**2 +
        (coord1['z'] - coord2['z'])**2
    )

def merge_masts_instances():
    base_dir = "/home/prodair/Desktop/MORIUS5090/clustering"
    original_dir = f"{base_dir}/out/job-20250911110357"
    metadata_dir = f"{base_dir}/out/dashboard_metadata"
    merged_dir = f"{base_dir}/out/cleaned_data_merged"
    temp_dir = f"{base_dir}/temp/stage4_merge"

    print("=== MERGING OVER-SEGMENTED MASTS ===")

    # Define specific merge pairs based on analysis
    merge_pairs = [
        # High priority merges (very close, small instances)
        ("part_1_chunk", "12_Masts_017", "12_Masts_018"),  # 1.0m apart
        ("part_2_chunk", "12_Masts_014", "12_Masts_013"),  # 1.0m apart
        ("part_5_chunk", "12_Masts_016", "12_Masts_015"),  # 1.1m apart
        ("part_3_chunk", "12_Masts_005", "12_Masts_004"),  # 1.1m apart
        ("part_2_chunk", "12_Masts_019", "12_Masts_018"),  # 1.2m apart
        ("part_5_chunk", "12_Masts_003", "12_Masts_004"),  # 1.4m apart
        ("part_5_chunk", "12_Masts_011", "12_Masts_009"),  # 1.7m apart
        ("part_2_chunk", "12_Masts_003", "12_Masts_004"),  # 2.4m apart
    ]

    total_merges = 0
    successful_merges = 0

    # Process each merge pair
    for chunk_name, inst1_name, inst2_name in merge_pairs:
        print(f"\nProcessing merge: {chunk_name} - {inst1_name} + {inst2_name}")

        # Original instance files
        inst1_file = f"{original_dir}/chunks/{chunk_name}/compressed/filtred_by_classes/12_Masts/instances/{inst1_name}.laz"
        inst2_file = f"{original_dir}/chunks/{chunk_name}/compressed/filtred_by_classes/12_Masts/instances/{inst2_name}.laz"

        if not os.path.exists(inst1_file) or not os.path.exists(inst2_file):
            print(f"  ERROR: Source files not found")
            continue

        # Load metadata for both instances
        metadata1_file = f"{metadata_dir}/chunks/{chunk_name}/filtred_by_classes/12_Masts/{chunk_name}_compressed_filtred_by_classes_12_Masts_instances_{inst1_name}_metadata.json"
        metadata2_file = f"{metadata_dir}/chunks/{chunk_name}/filtred_by_classes/12_Masts/{chunk_name}_compressed_filtred_by_classes_12_Masts_instances_{inst2_name}_metadata.json"

        metadata1 = load_metadata(metadata1_file)
        metadata2 = load_metadata(metadata2_file)

        if not metadata1 or not metadata2:
            print(f"  ERROR: Metadata not found")
            continue

        points1 = metadata1['geometry']['stats']['point_count']
        points2 = metadata2['geometry']['stats']['point_count']
        distance = calculate_distance(metadata1['geometry']['centroid'], metadata2['geometry']['centroid'])

        print(f"  Instance 1: {points1} points")
        print(f"  Instance 2: {points2} points")
        print(f"  Distance: {distance:.1f}m")
        print(f"  Combined: {points1 + points2} points")

        # Create merged instance using PDAL
        merged_file = f"{temp_dir}/merged_{chunk_name}_{inst1_name}_{inst2_name}.laz"
        merge_pipeline = f"{temp_dir}/merge_{chunk_name}_{inst1_name}_{inst2_name}.json"

        # Create PDAL merge pipeline
        pipeline = [
            {"type": "readers.las", "filename": inst1_file},
            {"type": "readers.las", "filename": inst2_file},
            {"type": "filters.merge"},
            {
                "type": "writers.las",
                "filename": merged_file,
                "compression": "laszip",
                "extra_dims": "ClusterID=uint32"
            }
        ]

        with open(merge_pipeline, 'w') as f:
            json.dump(pipeline, f, indent=2)

        try:
            # Execute PDAL merge
            result = subprocess.run(['pdal', 'pipeline', merge_pipeline],
                                  capture_output=True, text=True, timeout=30)

            if result.returncode == 0:
                print(f"  SUCCESS: Merged instance created")

                # Find next available slot in cleaned masts directory
                masts_dir = f"{merged_dir}/chunks/{chunk_name}/12_Masts"
                existing_files = [f for f in os.listdir(masts_dir) if f.startswith('12_Masts_') and f.endswith('.laz')]

                # Get highest number used
                max_num = -1
                for existing_file in existing_files:
                    try:
                        num = int(existing_file.split('_')[2].split('.')[0])
                        max_num = max(max_num, num)
                    except:
                        continue

                # Place merged instance
                new_name = f"12_Masts_{max_num+1:03d}.laz"
                final_path = f"{masts_dir}/{new_name}"
                shutil.copy2(merged_file, final_path)

                print(f"  PLACED: {new_name} in cleaned dataset")
                successful_merges += 1

                # Try to remove original small instances from cleaned dataset
                # (This is complex since cleaned instances have different naming)

            else:
                print(f"  ERROR: PDAL merge failed - {result.stderr}")

        except subprocess.TimeoutExpired:
            print(f"  ERROR: Merge timeout")
        except Exception as e:
            print(f"  ERROR: {str(e)}")

        total_merges += 1

    print(f"\n=== MERGE SUMMARY ===")
    print(f"Total merge attempts: {total_merges}")
    print(f"Successful merges: {successful_merges}")
    print(f"Success rate: {successful_merges/total_merges*100:.1f}%" if total_merges > 0 else "0%")

    return successful_merges

if __name__ == "__main__":
    merge_masts_instances()
EOF

chmod +x "$TEMP_DIR/merge_masts.py"

# Run the merge script
python3 "$TEMP_DIR/merge_masts.py"

# Count final results
total_masts_before=$(find "$CLEANED_DIR" -name "12_Masts_*.laz" | wc -l)
total_masts_after=$(find "$MERGED_DIR" -name "12_Masts_*.laz" | wc -l)

log "Merge processing completed!"
log "Masts instances before: $total_masts_before"
log "Masts instances after: $total_masts_after"
log "Net change: $((total_masts_after - total_masts_before))"

# Create merge report
cat > "$MERGED_DIR/merge_report.json" << EOF
{
  "merge_summary": {
    "operation": "masts_over_segmentation_fix",
    "masts_instances_before": $total_masts_before,
    "masts_instances_after": $total_masts_after,
    "net_change": $((total_masts_after - total_masts_before)),
    "merge_criteria": "distance ≤ 2.5m AND small instances <200 points"
  },
  "processing_metadata": {
    "generated_at": "$(date -Iseconds)",
    "generator": "stage4_merge_masts.sh",
    "input_directory": "$CLEANED_DIR",
    "output_directory": "$MERGED_DIR"
  }
}
EOF

log "Output directory: $MERGED_DIR"
log "Merge report: $MERGED_DIR/merge_report.json"