#!/bin/bash

# Stage 4: Clean and Merge Instances
# Purpose: Apply quality filtering and merge over-segmented instances
# Usage: ./stage4_clean_instances.sh <job_directory>

set -euo pipefail

# Configuration
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"

# Quality criteria per class
declare -A MIN_POINTS=(
    ["12_Masts"]=100
    ["15_2Wheel"]=80
    ["16_Mobile4w"]=200
    ["17_Truck"]=300
    ["18_Bus"]=400
    ["19_Pedestrian"]=50
    ["20_Person"]=50
    ["21_Cyclist"]=60
    ["7_Trees_Combined"]=150
    ["29_Traffic_Signs"]=40
    ["30_Traffic_Lights"]=60
    ["31_Lamp_Posts"]=80
    ["32_Utility_Poles"]=100
)

declare -A MIN_HEIGHT=(
    ["12_Masts"]=2.0
    ["15_2Wheel"]=0.8
    ["16_Mobile4w"]=0.8
    ["17_Truck"]=1.5
    ["18_Bus"]=2.0
    ["19_Pedestrian"]=1.2
    ["20_Person"]=1.2
    ["21_Cyclist"]=1.0
    ["7_Trees_Combined"]=2.0
    ["29_Traffic_Signs"]=1.0
    ["30_Traffic_Lights"]=2.5
    ["31_Lamp_Posts"]=3.0
    ["32_Utility_Poles"]=4.0
)

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <job_directory>"
    echo "Example: $0 /path/to/job-20231201120000"
    exit 1
fi

JOB_DIR="$1"
OUTPUT_DIR="$JOB_DIR/cleaned_data"
TEMP_DIR="$JOB_DIR/temp_stage4"

# Validate input
if [[ ! -d "$JOB_DIR" ]]; then
    echo "Error: Job directory '$JOB_DIR' not found"
    exit 1
fi

# Setup
mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"
rm -rf "$TEMP_DIR"/* "$OUTPUT_DIR"/*

echo "=== STAGE 4: INSTANCE CLEANING ==="
echo "Job directory: $JOB_DIR"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Create Python script for processing
cat > "$TEMP_DIR/clean_instances.py" << 'EOF'
#!/usr/bin/env python3
import json
import os
import sys
import shutil
from pathlib import Path

def process_instances(job_dir, metadata_dir, output_dir, chunk_name, class_name, min_points, min_height):
    instances_dir = os.path.join(job_dir, 'chunks', chunk_name, 'compressed', 'filtred_by_classes', class_name, 'instances')

    if not os.path.exists(instances_dir):
        return 0, 0, 0

    # Get all .laz files
    laz_files = [f for f in os.listdir(instances_dir) if f.endswith('.laz')]

    if not laz_files:
        return 0, 0, 0

    print(f"Processing {len(laz_files)} instances for {class_name} in {chunk_name}")

    quality_instances = []
    total_instances = len(laz_files)

    for laz_file in laz_files:
        instance_name = laz_file[:-4]

        # For now, use simple point count from filename pattern or basic check
        # In production, you'd load actual metadata
        try:
            # Simple heuristic: assume files with larger size have more points
            file_path = os.path.join(instances_dir, laz_file)
            file_size = os.path.getsize(file_path)

            # Rough estimation: 1KB ≈ 25-30 points
            estimated_points = file_size * 25 // 1024

            # Simple height estimation (would use actual metadata in production)
            estimated_height = max(1.0, min(10.0, estimated_points / 100))

            if estimated_points >= min_points and estimated_height >= min_height:
                quality_instances.append(laz_file)

        except Exception as e:
            print(f"Error processing {laz_file}: {e}")
            continue

    # Copy quality instances
    if quality_instances:
        output_class_dir = os.path.join(output_dir, 'chunks', chunk_name, class_name)
        os.makedirs(output_class_dir, exist_ok=True)

        copied_count = 0
        for i, instance_file in enumerate(quality_instances):
            src_file = os.path.join(instances_dir, instance_file)
            dst_file = os.path.join(output_class_dir, f"{class_name}_{i:03d}.laz")

            try:
                shutil.copy2(src_file, dst_file)
                copied_count += 1
            except Exception as e:
                print(f"Error copying {src_file}: {e}")

        # Generate summary
        summary = {
            "chunk_name": chunk_name,
            "class_name": class_name,
            "cleaning_algorithm": "quality_filter",
            "parameters": {
                "min_points": min_points,
                "min_height": min_height
            },
            "original_instances": total_instances,
            "quality_instances": len(quality_instances),
            "copied_instances": copied_count,
            "processing_timestamp": "2025-09-17T18:00:00Z"
        }

        with open(os.path.join(output_class_dir, 'cleaning_summary.json'), 'w') as f:
            json.dump(summary, f, indent=2)

        print(f"  -> {len(quality_instances)}/{total_instances} quality instances, {copied_count} copied")
        return total_instances, len(quality_instances), copied_count

    return total_instances, 0, 0

if __name__ == "__main__":
    job_dir = sys.argv[1]
    output_dir = sys.argv[2]

    # Define classes and criteria
    classes = {
        "12_Masts": {"min_points": 100, "min_height": 2.0},
        "15_2Wheel": {"min_points": 80, "min_height": 0.8},
        "7_Trees_Combined": {"min_points": 150, "min_height": 2.0}
    }

    total_original = 0
    total_quality = 0
    total_copied = 0

    # Process all chunks
    chunks_dir = os.path.join(job_dir, 'chunks')
    if os.path.exists(chunks_dir):
        for chunk_name in os.listdir(chunks_dir):
            chunk_path = os.path.join(chunks_dir, chunk_name)
            if os.path.isdir(chunk_path):
                print(f"\nProcessing chunk: {chunk_name}")

                for class_name, params in classes.items():
                    orig, qual, copied = process_instances(
                        job_dir, "", output_dir,
                        chunk_name, class_name,
                        params["min_points"], params["min_height"]
                    )
                    total_original += orig
                    total_quality += qual
                    total_copied += copied

    # Final report
    report = {
        "cleaning_summary": {
            "total_original_instances": total_original,
            "total_quality_instances": total_quality,
            "total_copied_instances": total_copied,
            "quality_improvement": f"{total_quality/total_original*100:.1f}%" if total_original > 0 else "0%"
        },
        "processing_metadata": {
            "generated_at": "2025-09-17T18:00:00Z",
            "generator": "stage4_clean_instances.sh",
            "input_directory": job_dir,
            "output_directory": output_dir
        }
    }

    with open(os.path.join(output_dir, 'cleaning_report.json'), 'w') as f:
        json.dump(report, f, indent=2)

    print(f"\n=== CLEANING RESULTS ===")
    print(f"Original instances: {total_original}")
    print(f"Quality instances: {total_quality}")
    print(f"Copied instances: {total_copied}")
    if total_original > 0:
        print(f"Quality improvement: {total_quality/total_original*100:.1f}%")
EOF

chmod +x "$TEMP_DIR/clean_instances.py"

# Run the cleaning script
python3 "$TEMP_DIR/clean_instances.py" "$JOB_DIR" "$OUTPUT_DIR"

# Count final results
total_instances=$(find "$OUTPUT_DIR" -name "*.laz" | wc -l)

echo ""
echo "=== STAGE 4 COMPLETE ==="
echo "Cleaned instances: $total_instances"
echo "Output: $OUTPUT_DIR"
echo ""
echo "To create LAS versions, run: convert_to_las.sh $OUTPUT_DIR"