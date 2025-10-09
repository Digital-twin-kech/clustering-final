#!/bin/bash

# Stage 4 Final: Instance Cleaning Pipeline
# Simplified and working version based on successful tests

set -euo pipefail

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_DIR="$BASE_DIR/out/job-20250911110357"
METADATA_DIR="$BASE_DIR/out/dashboard_metadata"
OUTPUT_DIR="$BASE_DIR/out/cleaned_data"
TEMP_DIR="$BASE_DIR/temp/stage4_final"

# Setup
mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"
rm -rf "$TEMP_DIR"/* "$OUTPUT_DIR"/*

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Class processing function
process_class() {
    local chunk_name="$1"
    local class_name="$2"
    local min_points="$3"
    local min_height="$4"

    local chunk_dir="$INPUT_DIR/chunks/$chunk_name"
    local instances_dir="$chunk_dir/compressed/filtred_by_classes/$class_name/instances"

    if [[ ! -d "$instances_dir" ]]; then
        return 0
    fi

    log "Processing $class_name in $chunk_name (min: $min_points points, ${min_height}m height)"

    # Create analysis file and process with Python
    local analysis_file="$TEMP_DIR/${chunk_name}_${class_name}_analysis.csv"
    echo "instance_file,point_count,height,centroid_x,centroid_y,centroid_z,quality" > "$analysis_file"

    # Use Python to process all instances at once
    python3 << EOF >> "$analysis_file"
import json
import os

instances_dir = "$instances_dir"
metadata_dir = "$METADATA_DIR"
chunk_name = "$chunk_name"
class_name = "$class_name"
min_points = $min_points
min_height = $min_height

if not os.path.exists(instances_dir):
    exit(0)

laz_files = [f for f in os.listdir(instances_dir) if f.endswith('.laz')]

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
        centroid_x = data['geometry']['centroid']['x']
        centroid_y = data['geometry']['centroid']['y']
        centroid_z = data['geometry']['centroid']['z']

        is_quality = 'true' if (point_count >= min_points and height >= min_height) else 'false'
        print(f'{laz_file},{point_count},{height},{centroid_x},{centroid_y},{centroid_z},{is_quality}')

    except Exception as e:
        continue
EOF

    # Count and copy quality instances
    local quality_count=$(grep ",true" "$analysis_file" | wc -l)
    local total_count=$(($(wc -l < "$analysis_file") - 1))

    if (( quality_count > 0 )); then
        local output_class_dir="$OUTPUT_DIR/chunks/$chunk_name/$class_name"
        mkdir -p "$output_class_dir"

        local copied=0
        local instance_id=0

        # Copy quality instances using a more reliable approach
        local quality_files="$TEMP_DIR/${chunk_name}_${class_name}_quality.txt"
        grep ",true" "$analysis_file" | cut -d',' -f1 > "$quality_files"

        while IFS= read -r instance_file; do
            [[ -n "$instance_file" ]] || continue
            local new_name="${class_name}_$(printf '%03d' $instance_id).laz"
            if cp "$instances_dir/$instance_file" "$output_class_dir/$new_name" 2>/dev/null; then
                ((copied++))
                ((instance_id++))
            fi
        done < "$quality_files"

        # Generate summary
        cat > "$output_class_dir/cleaning_summary.json" << JSON
{
  "chunk_name": "$chunk_name",
  "class_name": "$class_name",
  "cleaning_algorithm": "quality_filter",
  "parameters": {
    "min_points": $min_points,
    "min_height": $min_height
  },
  "original_instances": $total_count,
  "quality_instances": $quality_count,
  "copied_instances": $copied,
  "processing_timestamp": "$(date -Iseconds)"
}
JSON

        log "$class_name: Filtered $quality_count/$total_count quality instances, copied $copied ($(echo "scale=1; $quality_count*100/$total_count" | bc -l)%)"
    else
        log "$class_name: No quality instances found ($total_count total)"
    fi
}

# Main processing
log "Starting Stage 4 Final: Instance Cleaning"

# Define classes and their quality criteria
declare -A CLASSES=(
    ["12_Masts"]="100,2.0"
    ["15_2Wheel"]="80,0.8"
    ["7_Trees_Combined"]="150,2.0"
)

total_cleaned=0
total_processed=0

# Process each chunk
for chunk_dir in "$INPUT_DIR"/chunks/*/; do
    [[ -d "$chunk_dir" ]] || continue
    chunk_name=$(basename "$chunk_dir")
    log "Processing chunk: $chunk_name"

    # Process each defined class
    for class_name in "${!CLASSES[@]}"; do
        if [[ -d "$chunk_dir/compressed/filtred_by_classes/$class_name" ]]; then
            IFS=',' read -r min_points min_height <<< "${CLASSES[$class_name]}"
            process_class "$chunk_name" "$class_name" "$min_points" "$min_height"
            ((total_processed++))
        fi
    done
done

# Count final results
for chunk_dir in "$OUTPUT_DIR"/chunks/*/; do
    [[ -d "$chunk_dir" ]] || continue
    for class_dir in "$chunk_dir"/*/; do
        [[ -d "$class_dir" ]] || continue
        local class_instances=$(find "$class_dir" -name "*.laz" | wc -l)
        ((total_cleaned += class_instances))
    done
done

# Final report
cat > "$OUTPUT_DIR/cleaning_report.json" << EOF
{
  "cleaning_summary": {
    "total_cleaned_instances": $total_cleaned,
    "classes_processed": $total_processed,
    "output_structure": "clustering/out/cleaned_data/chunks/part_X_chunk/X_className/",
    "quality_criteria": {
      "12_Masts": ">=100 points, >=2.0m height",
      "15_2Wheel": ">=80 points, >=0.8m height",
      "7_Trees_Combined": ">=150 points, >=2.0m height"
    }
  },
  "processing_metadata": {
    "generated_at": "$(date -Iseconds)",
    "generator": "stage4_final.sh",
    "input_directory": "$INPUT_DIR",
    "output_directory": "$OUTPUT_DIR"
  }
}
EOF

log "Stage 4 cleaning completed successfully!"
log "Total cleaned instances: $total_cleaned"
log "Classes processed: $total_processed"
log "Report: $OUTPUT_DIR/cleaning_report.json"

# Show final statistics
echo ""
echo "=== CLEANING RESULTS ==="
for chunk_dir in "$OUTPUT_DIR"/chunks/*/; do
    [[ -d "$chunk_dir" ]] || continue
    chunk_name=$(basename "$chunk_dir")
    echo "Chunk: $chunk_name"
    for class_dir in "$chunk_dir"/*/; do
        [[ -d "$class_dir" ]] || continue
        class_name=$(basename "$class_dir")
        class_count=$(find "$class_dir" -name "*.laz" | wc -l)
        echo "  $class_name: $class_count instances"
    done
done