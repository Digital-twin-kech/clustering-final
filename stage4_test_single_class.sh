#!/bin/bash

# Test Stage 4 on single class - 12_Masts in part_5_chunk
set -euo pipefail

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_DIR="$BASE_DIR/out/job-20250911110357"
METADATA_DIR="$BASE_DIR/out/dashboard_metadata"
OUTPUT_DIR="$BASE_DIR/out/test_cleaned_data"
TEMP_DIR="$BASE_DIR/temp/stage4_test"

# Setup
mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"
rm -rf "$TEMP_DIR"/* "$OUTPUT_DIR"/*

echo "Testing Stage 4 on 12_Masts in part_5_chunk..."

# Test parameters
chunk_dir="$INPUT_DIR/chunks/part_5_chunk"
class_name="12_Masts"
instances_dir="$chunk_dir/compressed/filtred_by_classes/$class_name/instances"
chunk_name="part_5_chunk"

# Analysis file
analysis_file="$TEMP_DIR/${chunk_name}_${class_name}_analysis.csv"
echo "instance_file,point_count,height,centroid_x,centroid_y,centroid_z,quality" > "$analysis_file"

# Analyze instances
total_instances=0
quality_instances=0

for instance_file in "$instances_dir"/*.laz; do
    [[ -f "$instance_file" ]] || continue

    # Get metadata
    instance_name=$(basename "$instance_file" .laz)
    metadata_file="$METADATA_DIR/chunks/$chunk_name/filtred_by_classes/$class_name/${chunk_name}_compressed_filtred_by_classes_${class_name}_instances_${instance_name}_metadata.json"

    if [[ ! -f "$metadata_file" ]]; then
        echo "ERROR: Metadata file not found: $metadata_file"
        continue
    fi

    # Extract metrics
    point_count=$(python3 -c "
import json
with open('$metadata_file', 'r') as f:
    data = json.load(f)
print(data['geometry']['stats']['point_count'])
" 2>/dev/null || echo "0")

    height=$(python3 -c "
import json
with open('$metadata_file', 'r') as f:
    data = json.load(f)
print(data['geometry']['bbox']['dimensions']['height'])
" 2>/dev/null || echo "0")

    centroid_x=$(python3 -c "
import json
with open('$metadata_file', 'r') as f:
    data = json.load(f)
print(data['geometry']['centroid']['x'])
" 2>/dev/null || echo "0")

    centroid_y=$(python3 -c "
import json
with open('$metadata_file', 'r') as f:
    data = json.load(f)
print(data['geometry']['centroid']['y'])
" 2>/dev/null || echo "0")

    centroid_z=$(python3 -c "
import json
with open('$metadata_file', 'r') as f:
    data = json.load(f)
print(data['geometry']['centroid']['z'])
" 2>/dev/null || echo "0")

    # Quality check (12_Masts: min 100 points, min 2.0m height)
    is_quality="false"
    if (( $(echo "$point_count >= 100" | bc -l) )) && (( $(echo "$height >= 2.0" | bc -l) )); then
        is_quality="true"
        ((quality_instances++))
    fi

    echo "$(basename "$instance_file"),$point_count,$height,$centroid_x,$centroid_y,$centroid_z,$is_quality" >> "$analysis_file"
    ((total_instances++))
done

echo "$class_name: $quality_instances/$total_instances quality instances ($(echo "scale=1; $quality_instances*100/$total_instances" | bc -l)%)"

# Show analysis results
echo ""
echo "Analysis results:"
cat "$analysis_file"

echo ""
echo "Test completed successfully!"