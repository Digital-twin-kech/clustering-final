#!/bin/bash

# Stage 4 Optimized: Instance Cleaning and Merging Pipeline
# Faster version with optimized Python processing

set -euo pipefail

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_DIR="$BASE_DIR/out/job-20250911110357"
METADATA_DIR="$BASE_DIR/out/dashboard_metadata"
OUTPUT_DIR="$BASE_DIR/out/cleaned_data"
TEMP_DIR="$BASE_DIR/temp/stage4_optimized"

# Setup directories
mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"
rm -rf "$TEMP_DIR"/* "$OUTPUT_DIR"/*

# Class-specific quality rules
declare -A MIN_POINTS=(
    ["12_Masts"]=100
    ["15_2Wheel"]=80
    ["7_Trees_Combined"]=150
)

declare -A MIN_HEIGHT=(
    ["12_Masts"]=2.0
    ["15_2Wheel"]=0.8
    ["7_Trees_Combined"]=2.0
)

declare -A MERGE_DISTANCE=(
    ["12_Masts"]=2.5
    ["15_2Wheel"]=1.5
    ["7_Trees_Combined"]=3.0
)

# Create Python script for batch metadata processing
cat > "$TEMP_DIR/extract_metadata.py" << 'EOF'
#!/usr/bin/env python3
import json
import sys
import os

def process_instances(instances_dir, metadata_dir, chunk_name, class_name):
    results = []

    # Get all .laz files in instances directory
    if not os.path.exists(instances_dir):
        return results

    laz_files = [f for f in os.listdir(instances_dir) if f.endswith('.laz')]

    for laz_file in laz_files:
        instance_name = laz_file[:-4]  # Remove .laz extension

        # Construct metadata file path
        metadata_file = os.path.join(
            metadata_dir,
            'chunks',
            chunk_name,
            'filtred_by_classes',
            class_name,
            f"{chunk_name}_compressed_filtred_by_classes_{class_name}_instances_{instance_name}_metadata.json"
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

            results.append(f"{laz_file},{point_count},{height},{centroid_x},{centroid_y},{centroid_z}")

        except Exception as e:
            print(f"Error processing {metadata_file}: {e}", file=sys.stderr)
            continue

    return results

if __name__ == "__main__":
    if len(sys.argv) != 5:
        print("Usage: extract_metadata.py instances_dir metadata_dir chunk_name class_name", file=sys.stderr)
        sys.exit(1)

    instances_dir, metadata_dir, chunk_name, class_name = sys.argv[1:5]
    results = process_instances(instances_dir, metadata_dir, chunk_name, class_name)

    for result in results:
        print(result)
EOF

chmod +x "$TEMP_DIR/extract_metadata.py"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Process class instances
process_class() {
    local chunk_dir="$1"
    local class_name="$2"
    local chunk_name=$(basename "$chunk_dir")
    local instances_dir="$chunk_dir/compressed/filtred_by_classes/$class_name/instances"

    if [[ ! -d "$instances_dir" ]]; then
        log "No instances directory for $class_name in $chunk_name"
        return 0
    fi

    log "Processing class $class_name in $chunk_name..."

    # Create analysis file with header
    local analysis_file="$TEMP_DIR/${chunk_name}_${class_name}_analysis.csv"
    echo "instance_file,point_count,height,centroid_x,centroid_y,centroid_z,quality" > "$analysis_file"

    # Use optimized Python script to extract all metadata at once
    "$TEMP_DIR/extract_metadata.py" "$instances_dir" "$METADATA_DIR" "$chunk_name" "$class_name" > "$TEMP_DIR/${chunk_name}_${class_name}_raw.csv" 2>/dev/null

    if [[ ! -s "$TEMP_DIR/${chunk_name}_${class_name}_raw.csv" ]]; then
        log "No valid instances found for $class_name in $chunk_name"
        return 0
    fi

    # Process each instance for quality assessment
    local total_instances=0
    local quality_instances=0
    local min_points=${MIN_POINTS[$class_name]:-50}
    local min_height=${MIN_HEIGHT[$class_name]:-0.5}

    while IFS=',' read -r instance_file point_count height centroid_x centroid_y centroid_z; do
        [[ -n "$instance_file" ]] || continue

        # Quality check
        local is_quality="false"
        if (( $(echo "$point_count >= $min_points" | bc -l) )) && \
           (( $(echo "$height >= $min_height" | bc -l) )); then
            is_quality="true"
            ((quality_instances++))
        fi

        echo "$instance_file,$point_count,$height,$centroid_x,$centroid_y,$centroid_z,$is_quality" >> "$analysis_file"
        ((total_instances++))

    done < "$TEMP_DIR/${chunk_name}_${class_name}_raw.csv"

    if (( total_instances > 0 )); then
        local quality_pct=$(echo "scale=1; $quality_instances*100/$total_instances" | bc -l)
        log "$class_name: $quality_instances/$total_instances quality instances ($quality_pct%)"

        # Copy quality instances to output
        copy_quality_instances "$chunk_dir" "$class_name" "$analysis_file"
    fi
}

# Copy quality instances to output
copy_quality_instances() {
    local chunk_dir="$1"
    local class_name="$2"
    local analysis_file="$3"
    local instances_dir="$chunk_dir/compressed/filtred_by_classes/$class_name/instances"

    local chunk_name=$(basename "$chunk_dir")
    local output_class_dir="$OUTPUT_DIR/chunks/$chunk_name/$class_name"
    mkdir -p "$output_class_dir"

    local copied_count=0
    local new_instance_id=0

    # Copy quality instances
    while IFS=',' read -r instance_file point_count height x y z quality; do
        [[ "$instance_file" != "instance_file" ]] || continue
        [[ "$quality" == "true" ]] || continue

        local new_name="${class_name}_$(printf '%03d' $new_instance_id).laz"
        if cp "$instances_dir/$instance_file" "$output_class_dir/$new_name" 2>/dev/null; then
            ((copied_count++))
            ((new_instance_id++))
        fi
    done < "$analysis_file"

    log "$class_name: Copied $copied_count quality instances to output"

    # Generate summary
    cat > "$output_class_dir/cleaning_summary.json" << EOF
{
  "chunk_name": "$chunk_name",
  "class_name": "$class_name",
  "cleaning_algorithm": "quality_filter",
  "parameters": {
    "min_points": ${MIN_POINTS[$class_name]:-50},
    "min_height": ${MIN_HEIGHT[$class_name]:-0.5}
  },
  "final_instances": $copied_count,
  "processing_timestamp": "$(date -Iseconds)"
}
EOF
}

# Main processing
log "Starting Stage 4 Optimized: Instance Cleaning"
log "Input: $INPUT_DIR"
log "Output: $OUTPUT_DIR"

total_cleaned_instances=0
total_classes_processed=0

# Process all chunks
for chunk_dir in "$INPUT_DIR"/chunks/*/; do
    [[ -d "$chunk_dir" ]] || continue

    chunk_name=$(basename "$chunk_dir")
    log "Processing $chunk_name..."

    # Process only defined classes
    for class_name in "${!MIN_POINTS[@]}"; do
        if [[ -d "$chunk_dir/compressed/filtred_by_classes/$class_name" ]]; then
            process_class "$chunk_dir" "$class_name"
            ((total_classes_processed++))
        fi
    done
done

# Count final results
for chunk_dir in "$OUTPUT_DIR"/chunks/*/; do
    [[ -d "$chunk_dir" ]] || continue
    for class_dir in "$chunk_dir"/*/; do
        [[ -d "$class_dir" ]] || continue
        class_instances=$(find "$class_dir" -name "*.laz" | wc -l)
        ((total_cleaned_instances += class_instances))
    done
done

# Generate final report
cat > "$OUTPUT_DIR/cleaning_report.json" << EOF
{
  "cleaning_summary": {
    "total_cleaned_instances": $total_cleaned_instances,
    "total_classes_processed": $total_classes_processed,
    "output_structure": "clustering/out/cleaned_data/chunks/part_X_chunk/X_className/",
    "quality_improvement": "Filtered noise instances based on point count and height thresholds"
  },
  "processing_metadata": {
    "generated_at": "$(date -Iseconds)",
    "generator": "stage4_optimized.sh",
    "input_directory": "$INPUT_DIR",
    "output_directory": "$OUTPUT_DIR"
  }
}
EOF

log "Stage 4 cleaning completed successfully!"
log "Cleaned instances: $total_cleaned_instances"
log "Classes processed: $total_classes_processed"
log "Cleaning report: $OUTPUT_DIR/cleaning_report.json"