#!/bin/bash

METADATA_DIR="/home/prodair/Desktop/MORIUS5090/clustering/out/dashboard_metadata"

# Test metadata extraction
test_instance="/home/prodair/Desktop/MORIUS5090/clustering/out/job-20250911110357/chunks/part_5_chunk/compressed/filtred_by_classes/12_Masts/instances/12_Masts_013.laz"
chunk_name="part_5_chunk"
class_name="12_Masts"

# Get instance name without extension
instance_name=$(basename "$test_instance" .laz)
echo "Instance name: $instance_name"

# Construct metadata file path
metadata_file="$METADATA_DIR/chunks/$chunk_name/filtred_by_classes/$class_name/${chunk_name}_compressed_filtred_by_classes_${class_name}_instances_${instance_name}_metadata.json"
echo "Metadata file: $metadata_file"

# Check if file exists
if [[ -f "$metadata_file" ]]; then
    echo "File exists!"

    # Extract key metrics using Python
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

    echo "Point count: $point_count"
    echo "Height: $height"
    echo "Centroid: $centroid_x, $centroid_y, $centroid_z"
else
    echo "File does NOT exist!"
fi