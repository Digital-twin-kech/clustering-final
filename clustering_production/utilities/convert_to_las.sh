#!/bin/bash

# Utility: Convert LAZ to LAS
# Purpose: Convert all LAZ files in a directory to uncompressed LAS format
# Usage: ./convert_to_las.sh <input_directory>

set -euo pipefail

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <input_directory>"
    echo "Example: $0 /path/to/cleaned_data"
    echo ""
    echo "This utility converts all LAZ files to LAS format for easier visualization"
    exit 1
fi

INPUT_DIR="$1"
OUTPUT_DIR="${INPUT_DIR}_las"

# Validate input
if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Input directory '$INPUT_DIR' not found"
    exit 1
fi

# Setup output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "=== LAZ TO LAS CONVERSION ==="
echo "Input: $INPUT_DIR"
echo "Output: $OUTPUT_DIR"
echo ""

# Copy directory structure
echo "Copying directory structure..."
cp -r "$INPUT_DIR"/* "$OUTPUT_DIR/"

# Convert all LAZ files to LAS
converted_count=0
failed_count=0
total_laz_files=$(find "$OUTPUT_DIR" -name "*.laz" | wc -l)

echo "Found $total_laz_files LAZ files to convert"
echo ""

for laz_file in $(find "$OUTPUT_DIR" -name "*.laz"); do
    las_file="${laz_file%.laz}.las"

    echo "Converting: $(basename "$laz_file")"

    if pdal translate "$laz_file" "$las_file" --writers.las.compression=false 2>/dev/null; then
        rm "$laz_file"  # Remove original LAZ file
        ((converted_count++))

        # Show progress
        if (( converted_count % 20 == 0 )); then
            echo "  Progress: $converted_count/$total_laz_files converted..."
        fi
    else
        echo "  ERROR: Failed to convert $(basename "$laz_file")"
        ((failed_count++))
    fi
done

echo ""
echo "=== CONVERSION COMPLETE ==="
echo "Successfully converted: $converted_count"
echo "Failed conversions: $failed_count"
echo "Success rate: $(echo "scale=1; $converted_count*100/($converted_count+$failed_count)" | bc -l)%"
echo ""
echo "LAS files ready at: $OUTPUT_DIR"

# Generate conversion report
cat > "$OUTPUT_DIR/conversion_report.json" << EOF
{
  "conversion_summary": {
    "source_directory": "$INPUT_DIR",
    "target_directory": "$OUTPUT_DIR",
    "total_laz_files": $total_laz_files,
    "converted_files": $converted_count,
    "failed_conversions": $failed_count,
    "success_rate": "$(echo "scale=1; $converted_count*100/($converted_count+$failed_count)" | bc -l)%"
  },
  "processing_metadata": {
    "generated_at": "$(date -Iseconds)",
    "generator": "convert_to_las.sh",
    "conversion_tool": "PDAL translate"
  }
}
EOF

echo "Conversion report saved: $OUTPUT_DIR/conversion_report.json"