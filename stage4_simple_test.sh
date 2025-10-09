#!/bin/bash

# Simple test of Stage 4 processing logic

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_DIR="$BASE_DIR/out/job-20250911110357"
METADATA_DIR="$BASE_DIR/out/dashboard_metadata"
OUTPUT_DIR="$BASE_DIR/out/test_cleaned_simple"
TEMP_DIR="$BASE_DIR/temp/stage4_simple"

mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"
rm -rf "$TEMP_DIR"/* "$OUTPUT_DIR"/*

# Test specific class
chunk_name="part_1_chunk"
class_name="12_Masts"
chunk_dir="$INPUT_DIR/chunks/$chunk_name"
instances_dir="$chunk_dir/compressed/filtred_by_classes/$class_name/instances"

echo "Testing: $class_name in $chunk_name"
echo "Instances dir: $instances_dir"
echo "Exists: $(ls -la "$instances_dir" | wc -l) items"

# Create analysis file
analysis_file="$TEMP_DIR/${chunk_name}_${class_name}_analysis.csv"
echo "instance_file,point_count,height,centroid_x,centroid_y,centroid_z,quality" > "$analysis_file"

# Use the working Python extraction
python3 -c "
import json
import sys
import os

instances_dir = '$instances_dir'
metadata_dir = '$METADATA_DIR'
chunk_name = '$chunk_name'
class_name = '$class_name'

if not os.path.exists(instances_dir):
    print('Instances directory does not exist')
    sys.exit(1)

laz_files = [f for f in os.listdir(instances_dir) if f.endswith('.laz')]
print(f'Found {len(laz_files)} .laz files')

for laz_file in laz_files[:5]:  # Test first 5 only
    instance_name = laz_file[:-4]
    metadata_file = os.path.join(
        metadata_dir,
        'chunks',
        chunk_name,
        'filtred_by_classes',
        class_name,
        f'{chunk_name}_compressed_filtred_by_classes_{class_name}_instances_{instance_name}_metadata.json'
    )

    if not os.path.exists(metadata_file):
        print(f'Metadata not found: {metadata_file}')
        continue

    try:
        with open(metadata_file, 'r') as f:
            data = json.load(f)

        point_count = data['geometry']['stats']['point_count']
        height = data['geometry']['bbox']['dimensions']['height']
        centroid_x = data['geometry']['centroid']['x']
        centroid_y = data['geometry']['centroid']['y']
        centroid_z = data['geometry']['centroid']['z']

        # Quality check: 12_Masts needs >= 100 points and >= 2.0m height
        is_quality = 'true' if (point_count >= 100 and height >= 2.0) else 'false'

        print(f'{laz_file},{point_count},{height},{centroid_x},{centroid_y},{centroid_z},{is_quality}')

    except Exception as e:
        print(f'Error processing {metadata_file}: {e}')
" >> "$analysis_file"

echo ""
echo "Analysis file content:"
cat "$analysis_file"

# Count quality instances
quality_count=$(grep ",true" "$analysis_file" | wc -l)
total_count=$(tail -n +2 "$analysis_file" | wc -l)

echo ""
echo "Results: $quality_count/$total_count quality instances"