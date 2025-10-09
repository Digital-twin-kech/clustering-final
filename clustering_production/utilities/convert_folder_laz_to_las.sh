#!/bin/bash

# LAZ to LAS Folder Converter (Production Ready)
# Purpose: Convert ALL LAZ files in a folder to LAS format in output_las subfolder
# Usage: ./convert_folder_laz_to_las.sh <folder_path>

set -euo pipefail

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <folder_path>"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/chunks"
    echo "  $0 ../out_clean/chunks"
    echo "  $0 ."
    echo ""
    echo "This utility converts ALL .laz files to .las format"
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

echo "=== LAZ TO LAS FOLDER CONVERTER ==="
echo "Input folder: $INPUT_FOLDER"
echo "Output folder: $OUTPUT_FOLDER"
echo ""

# Create output directory
mkdir -p "$OUTPUT_FOLDER"

# Find LAZ files
echo "Scanning for LAZ files..."
cd "$INPUT_FOLDER"

LAZ_COUNT=0
declare -a LAZ_FILES

for file in *.laz; do
    if [[ -f "$file" && "$file" != *"/output_las/"* ]]; then
        LAZ_FILES[LAZ_COUNT]="$file"
        ((LAZ_COUNT++))
    fi
done

if [[ $LAZ_COUNT -eq 0 ]]; then
    echo "No LAZ files found in $INPUT_FOLDER"
    exit 1
fi

echo "Found $LAZ_COUNT LAZ files to convert:"
for ((i=0; i<LAZ_COUNT; i++)); do
    echo "  $((i+1)). ${LAZ_FILES[i]}"
done

echo ""
echo "Starting conversion of ALL $LAZ_COUNT files..."
echo ""

# Initialize counters
converted_count=0
failed_count=0
total_input_size=0
total_output_size=0

# Process each file
for ((i=0; i<LAZ_COUNT; i++)); do
    laz_file="${LAZ_FILES[i]}"
    filename=$(basename "$laz_file" .laz)
    las_file="$OUTPUT_FOLDER/${filename}.las"

    echo "[$((i+1))/$LAZ_COUNT] Converting: $laz_file"

    # Get input file size
    if [[ -f "$laz_file" ]]; then
        input_size=$(stat -c%s "$laz_file" 2>/dev/null || echo "0")
        input_size_mb=$(echo "scale=1; $input_size/1048576" | bc -l)
        total_input_size=$((total_input_size + input_size))

        echo "  Input: ${input_size_mb}MB"

        # Convert using PDAL
        start_time=$(date +%s)

        if timeout 300 pdal translate "$laz_file" "$las_file" --writers.las.compression=false 2>/dev/null; then
            end_time=$(date +%s)
            duration=$((end_time - start_time))

            # Get output file size
            if [[ -f "$las_file" ]]; then
                output_size=$(stat -c%s "$las_file" 2>/dev/null || echo "0")
                output_size_mb=$(echo "scale=1; $output_size/1048576" | bc -l)
                total_output_size=$((total_output_size + output_size))

                echo "  ✓ Success: ${output_size_mb}MB in ${duration}s"
                ((converted_count++))
            else
                echo "  ✗ Failed: Output file not created"
                ((failed_count++))
            fi
        else
            echo "  ✗ Failed: PDAL conversion error or timeout"
            ((failed_count++))
        fi
    else
        echo "  ✗ Failed: Input file not found"
        ((failed_count++))
    fi

    echo ""
done

# Calculate statistics
total_input_mb=$(echo "scale=1; $total_input_size/1048576" | bc -l)
total_output_mb=$(echo "scale=1; $total_output_size/1048576" | bc -l)

if [[ "$total_input_size" -gt 0 ]]; then
    expansion_ratio=$(echo "scale=1; $total_output_size*100/$total_input_size" | bc -l)
else
    expansion_ratio="N/A"
fi

success_rate=$(echo "scale=1; $converted_count*100/$LAZ_COUNT" | bc -l 2>/dev/null || echo "0")

# Final summary
echo "=== CONVERSION COMPLETE ==="
echo ""
echo "📊 RESULTS:"
echo "  LAZ files found:    $LAZ_COUNT"
echo "  Successfully converted: $converted_count"
echo "  Failed conversions: $failed_count"
echo "  Success rate:      ${success_rate}%"
echo ""
echo "💾 SIZE COMPARISON:"
echo "  Total input (LAZ): ${total_input_mb}MB"
echo "  Total output (LAS): ${total_output_mb}MB"
echo "  Size expansion:    ${expansion_ratio}%"
echo ""

# List all converted files
if [[ $converted_count -gt 0 ]]; then
    echo "📁 CONVERTED FILES:"
    find "$OUTPUT_FOLDER" -name "*.las" -type f | sort | while read las_file; do
        filename=$(basename "$las_file")
        file_size=$(ls -lh "$las_file" | awk '{print $5}')
        echo "  $filename ($file_size)"
    done
    echo ""
fi

# Generate report
cat > "$OUTPUT_FOLDER/conversion_report.json" << EOF
{
  "conversion_summary": {
    "input_folder": "$INPUT_FOLDER",
    "output_folder": "$OUTPUT_FOLDER",
    "laz_files_found": $LAZ_COUNT,
    "files_converted": $converted_count,
    "files_failed": $failed_count,
    "success_rate_percent": $success_rate
  },
  "size_analysis": {
    "total_input_mb": $total_input_mb,
    "total_output_mb": $total_output_mb,
    "expansion_ratio_percent": "$expansion_ratio"
  },
  "processing_metadata": {
    "generated_at": "$(date -Iseconds)",
    "generator": "convert_folder_laz_to_las.sh",
    "conversion_tool": "PDAL translate"
  }
}
EOF

echo "📄 Report saved: $OUTPUT_FOLDER/conversion_report.json"

if [[ $converted_count -eq $LAZ_COUNT ]]; then
    echo ""
    echo "🎉 SUCCESS: All $LAZ_COUNT LAZ files converted to LAS!"
elif [[ $converted_count -gt 0 ]]; then
    echo ""
    echo "⚠️  Partial success: $converted_count/$LAZ_COUNT files converted"
else
    echo ""
    echo "❌ No files were converted successfully"
fi

echo ""
echo "Output location: $OUTPUT_FOLDER"