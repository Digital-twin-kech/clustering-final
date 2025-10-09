#!/bin/bash

# Simple LAZ to LAS Folder Converter
# Purpose: Convert ALL LAZ files in a folder to LAS format
# Usage: ./convert_folder_laz_to_las_simple.sh <folder_path>

set -euo pipefail

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <folder_path>"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/chunks"
    echo "  $0 ../out_clean/chunks"
    echo ""
    exit 1
fi

INPUT_FOLDER="$1"

# Validate input folder
if [[ ! -d "$INPUT_FOLDER" ]]; then
    echo "Error: Input folder '$INPUT_FOLDER' not found"
    exit 1
fi

# Convert to absolute path
INPUT_FOLDER=$(realpath "$INPUT_FOLDER")
OUTPUT_FOLDER="$INPUT_FOLDER/output_las"

echo "=== SIMPLE LAZ TO LAS CONVERTER ==="
echo "Input folder: $INPUT_FOLDER"
echo "Output folder: $OUTPUT_FOLDER"
echo ""

# Create output directory
mkdir -p "$OUTPUT_FOLDER"

# Find LAZ files
echo "Finding LAZ files..."
LAZ_FILES=($(find "$INPUT_FOLDER" -maxdepth 1 -name "*.laz" -type f | sort))
LAZ_COUNT=${#LAZ_FILES[@]}

if [[ $LAZ_COUNT -eq 0 ]]; then
    echo "No LAZ files found in $INPUT_FOLDER"
    exit 1
fi

echo "Found $LAZ_COUNT LAZ files:"
for ((i=0; i<LAZ_COUNT; i++)); do
    echo "  $((i+1)). $(basename "${LAZ_FILES[i]}")"
done
echo ""

# Initialize counters
converted_count=0
failed_count=0

# Convert each file
for ((i=0; i<LAZ_COUNT; i++)); do
    laz_file="${LAZ_FILES[i]}"
    filename=$(basename "$laz_file" .laz)
    las_file="$OUTPUT_FOLDER/${filename}.las"

    echo "[$((i+1))/$LAZ_COUNT] Converting: $(basename "$laz_file")"

    # Convert using PDAL
    if pdal translate "$laz_file" "$las_file" --writers.las.compression=false 2>/dev/null; then
        if [[ -f "$las_file" ]]; then
            file_size=$(ls -lh "$las_file" | awk '{print $5}')
            echo "  ✓ Success: $file_size"
            ((converted_count++))
        else
            echo "  ✗ Failed: Output file not created"
            ((failed_count++))
        fi
    else
        echo "  ✗ Failed: PDAL conversion error"
        ((failed_count++))
    fi
    echo ""
done

# Final summary
echo "=== CONVERSION COMPLETE ==="
echo "Files processed: $LAZ_COUNT"
echo "Successfully converted: $converted_count"
echo "Failed conversions: $failed_count"
echo ""

if [[ $converted_count -gt 0 ]]; then
    echo "Converted files in: $OUTPUT_FOLDER"
    ls -la "$OUTPUT_FOLDER"/*.las 2>/dev/null || echo "No LAS files found"
fi

if [[ $converted_count -eq $LAZ_COUNT ]]; then
    echo ""
    echo "🎉 SUCCESS: All $LAZ_COUNT LAZ files converted to LAS!"
else
    echo ""
    echo "⚠️  $converted_count/$LAZ_COUNT files converted successfully"
fi