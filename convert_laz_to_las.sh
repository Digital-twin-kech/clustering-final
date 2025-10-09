#!/bin/bash

# Convert all LAZ files to LAS files in-place (same directory)
# Usage: ./convert_laz_to_las.sh DIRECTORY_PATH

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "ERROR: Usage: $0 DIRECTORY_PATH" >&2
    echo "  DIRECTORY_PATH: Root directory to search for LAZ files" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $0 out/job-20250911110357                    # Convert all LAZ in job" >&2
    echo "  $0 out/job-20250911110357/chunks            # Convert only chunks" >&2
    echo "  $0 out/job-20250911110357/chunks/part_1_filtred_by_classes  # Convert one folder" >&2
    exit 1
fi

TARGET_DIR="$1"

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "ERROR: Directory not found: $TARGET_DIR" >&2
    exit 1
fi

echo "INFO: Converting LAZ files to LAS in directory: $TARGET_DIR"
echo "========================================="

# Find all LAZ files
LAZ_FILES=()
while IFS= read -r -d '' file; do
    LAZ_FILES+=("$file")
done < <(find "$TARGET_DIR" -name "*.laz" -print0 2>/dev/null)

if [[ ${#LAZ_FILES[@]} -eq 0 ]]; then
    echo "INFO: No LAZ files found in $TARGET_DIR" >&2
    exit 0
fi

echo "INFO: Found ${#LAZ_FILES[@]} LAZ files to convert"

CONVERTED_COUNT=0
FAILED_COUNT=0
TOTAL_POINTS=0

# Process each LAZ file
for LAZ_FILE in "${LAZ_FILES[@]}"; do
    # Generate LAS filename (same directory, same name, .las extension)
    LAS_FILE="${LAZ_FILE%.laz}.las"
    
    # Get relative path for cleaner output
    RELATIVE_LAZ=${LAZ_FILE#$TARGET_DIR/}
    RELATIVE_LAS=${LAS_FILE#$TARGET_DIR/}
    
    echo "INFO: Converting $RELATIVE_LAZ"
    
    # Check if LAS file already exists
    if [[ -f "$LAS_FILE" ]]; then
        echo "  ⚠ $RELATIVE_LAS already exists - skipping"
        continue
    fi
    
    # Convert using pdal translate
    if pdal translate "$LAZ_FILE" "$LAS_FILE" >/dev/null 2>&1; then
        # Get point count for verification
        POINT_COUNT=$(pdal info "$LAS_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
        
        # Get file sizes for comparison
        LAZ_SIZE=$(stat -c%s "$LAZ_FILE" 2>/dev/null || echo "0")
        LAS_SIZE=$(stat -c%s "$LAS_FILE" 2>/dev/null || echo "0")
        
        # Convert bytes to human readable
        LAZ_SIZE_HR=$(numfmt --to=iec "$LAZ_SIZE" 2>/dev/null || echo "${LAZ_SIZE}B")
        LAS_SIZE_HR=$(numfmt --to=iec "$LAS_SIZE" 2>/dev/null || echo "${LAS_SIZE}B")
        
        printf "  ✓ %s → %s (%s points, %s → %s)\n" \
               "$(basename "$LAZ_FILE")" \
               "$(basename "$LAS_FILE")" \
               "$POINT_COUNT" \
               "$LAZ_SIZE_HR" \
               "$LAS_SIZE_HR"
        
        CONVERTED_COUNT=$((CONVERTED_COUNT + 1))
        TOTAL_POINTS=$((TOTAL_POINTS + POINT_COUNT))
        
    else
        echo "  ✗ Failed to convert $RELATIVE_LAZ"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

echo ""
echo "========================================="
echo "CONVERSION COMPLETE"
echo "========================================="
echo "Files processed: ${#LAZ_FILES[@]}"
echo "Successfully converted: $CONVERTED_COUNT"
echo "Failed conversions: $FAILED_COUNT"
echo "Total points converted: $(printf "%'d" $TOTAL_POINTS)"

if [[ $CONVERTED_COUNT -gt 0 ]]; then
    echo ""
    echo "Directory structure after conversion:"
    
    # Show directory structure with both LAZ and LAS files
    find "$TARGET_DIR" -type d -name "*filtred_by_classes" | sort | head -3 | while read -r dir; do
        dir_name=$(basename "$dir")
        echo "$dir_name/"
        
        # Show LAZ files
        find "$dir" -name "*.laz" | sort | head -5 | while read -r file; do
            filename=$(basename "$file")
            printf "├── %-30s (compressed)\n" "$filename"
        done
        
        # Show LAS files  
        find "$dir" -name "*.las" | sort | head -5 | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            printf "├── %-30s (%8s points, uncompressed)\n" "$filename" "$point_count"
        done
        
        echo ""
    done
    
    echo "Usage:"
    echo "  - LAZ files: Compressed, smaller file size"
    echo "  - LAS files: Uncompressed, faster to load in viewers"
    echo ""
    echo "Visualization software:"
    echo "  - CloudCompare: Open LAS files for 3D viewing"
    echo "  - QGIS: Load LAS files as point cloud layers"
    echo "  - MeshLab: Import LAS for mesh processing"
    echo "  - PDAL view: pdal view filename.las"
fi

echo "========================================="