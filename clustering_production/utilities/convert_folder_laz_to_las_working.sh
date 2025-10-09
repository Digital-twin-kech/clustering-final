#!/bin/bash

# Working LAZ to LAS Folder Converter
# Usage: ./convert_folder_laz_to_las_working.sh <folder_path>

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <folder_path>"
    exit 1
fi

INPUT_FOLDER=$(realpath "$1")
OUTPUT_FOLDER="$INPUT_FOLDER/output_las"

echo "=== LAZ TO LAS CONVERTER ==="
echo "Input: $INPUT_FOLDER"
echo "Output: $OUTPUT_FOLDER"
echo ""

mkdir -p "$OUTPUT_FOLDER"

# Process each LAZ file individually
cd "$INPUT_FOLDER"
converted=0
failed=0

for laz_file in *.laz; do
    if [[ -f "$laz_file" ]]; then
        echo "Converting: $laz_file"

        filename=$(basename "$laz_file" .laz)
        las_file="$OUTPUT_FOLDER/${filename}.las"

        if pdal translate "$laz_file" "$las_file" --writers.las.compression=false; then
            if [[ -f "$las_file" ]]; then
                size=$(ls -lh "$las_file" | awk '{print $5}')
                echo "  ✓ Created: $las_file ($size)"
                ((converted++))
            else
                echo "  ✗ Failed: Output not created"
                ((failed++))
            fi
        else
            echo "  ✗ Failed: PDAL error"
            ((failed++))
        fi
        echo ""
    fi
done

echo "=== RESULTS ==="
echo "Converted: $converted"
echo "Failed: $failed"

if [[ $converted -gt 0 ]]; then
    echo ""
    echo "Output files:"
    ls -la "$OUTPUT_FOLDER"/*.las 2>/dev/null || echo "No LAS files found"
fi