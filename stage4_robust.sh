#!/bin/bash

# Stage 4 Robust: Instance Cleaning Pipeline - Full Dataset Processing
set -euo pipefail

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_DIR="$BASE_DIR/out/job-20250911110357"
METADATA_DIR="$BASE_DIR/out/dashboard_metadata"
OUTPUT_DIR="$BASE_DIR/out/cleaned_data"
TEMP_DIR="$BASE_DIR/temp/stage4_robust"

# Setup
rm -rf "$OUTPUT_DIR"/* "$TEMP_DIR"/*
mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

# Create comprehensive Python processing script
cat > "$TEMP_DIR/process_all_instances.py" << 'EOF'
#!/usr/bin/env python3
import json
import os
import sys
import shutil
from pathlib import Path

def process_class_instances(input_dir, metadata_dir, output_dir, chunk_name, class_name, min_points, min_height):
    instances_dir = os.path.join(input_dir, 'chunks', chunk_name, 'compressed', 'filtred_by_classes', class_name, 'instances')

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
        metadata_file = os.path.join(
            metadata_dir, 'chunks', chunk_name, 'filtred_by_classes', class_name,
            f'{chunk_name}_compressed_filtred_by_classes_{class_name}_instances_{instance_name}_metadata.json'
        )

        if not os.path.exists(metadata_file):
            continue

        try:
            with open(metadata_file, 'r') as f:
                data = json.load(f)

            point_count = data['geometry']['stats']['point_count']
            height = data['geometry']['bbox']['dimensions']['height']

            if point_count >= min_points and height >= min_height:
                quality_instances.append(laz_file)

        except Exception as e:
            print(f"Error processing {metadata_file}: {e}")
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
            "processing_timestamp": "2025-09-17T16:50:00Z"
        }

        with open(os.path.join(output_class_dir, 'cleaning_summary.json'), 'w') as f:
            json.dump(summary, f, indent=2)

        print(f"  -> {len(quality_instances)}/{total_instances} quality instances, {copied_count} copied")
        return total_instances, len(quality_instances), copied_count

    return total_instances, 0, 0

if __name__ == "__main__":
    input_dir = sys.argv[1]
    metadata_dir = sys.argv[2]
    output_dir = sys.argv[3]

    # Class definitions
    classes = {
        "12_Masts": {"min_points": 100, "min_height": 2.0},
        "15_2Wheel": {"min_points": 80, "min_height": 0.8},
        "7_Trees_Combined": {"min_points": 150, "min_height": 2.0}
    }

    total_original = 0
    total_quality = 0
    total_copied = 0

    # Process all chunks
    chunks_dir = os.path.join(input_dir, 'chunks')
    if os.path.exists(chunks_dir):
        for chunk_name in os.listdir(chunks_dir):
            chunk_path = os.path.join(chunks_dir, chunk_name)
            if os.path.isdir(chunk_path):
                print(f"\nProcessing chunk: {chunk_name}")

                for class_name, params in classes.items():
                    orig, qual, copied = process_class_instances(
                        input_dir, metadata_dir, output_dir,
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
            "quality_improvement": f"{total_quality/total_original*100:.1f}%" if total_original > 0 else "0%",
            "classes_processed": list(classes.keys())
        },
        "processing_metadata": {
            "generated_at": "2025-09-17T16:50:00Z",
            "generator": "stage4_robust.py",
            "input_directory": input_dir,
            "output_directory": output_dir
        }
    }

    with open(os.path.join(output_dir, 'cleaning_report.json'), 'w') as f:
        json.dump(report, f, indent=2)

    print(f"\n=== FINAL RESULTS ===")
    print(f"Original instances: {total_original}")
    print(f"Quality instances: {total_quality}")
    print(f"Copied instances: {total_copied}")
    if total_original > 0:
        print(f"Quality improvement: {total_quality/total_original*100:.1f}%")
EOF

chmod +x "$TEMP_DIR/process_all_instances.py"

log "Starting Stage 4 Robust: Full Dataset Processing"
log "Processing all classes across all chunks..."

# Run the comprehensive Python script
"$TEMP_DIR/process_all_instances.py" "$INPUT_DIR" "$METADATA_DIR" "$OUTPUT_DIR"

# Show final directory structure
log "Cleaning completed! Final structure:"
find "$OUTPUT_DIR" -name "*.laz" | head -20
echo "..."
log "Total instances cleaned: $(find "$OUTPUT_DIR" -name "*.laz" | wc -l)"

log "Stage 4 robust processing completed successfully!"