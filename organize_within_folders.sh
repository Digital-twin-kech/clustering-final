#!/bin/bash

# Organize LAZ and LAS files within each filtered class directory
# Creates 'compressed' and 'not_compressed' subfolders in each part_X_filtred_by_classes directory
# Usage: ./organize_within_folders.sh JOB_ROOT

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "ERROR: Usage: $0 JOB_ROOT" >&2
    echo "  JOB_ROOT: Job directory containing chunks" >&2
    exit 1
fi

JOB_ROOT="$1"
CHUNKS_DIR="$JOB_ROOT/chunks"

if [[ ! -d "$CHUNKS_DIR" ]]; then
    echo "ERROR: Chunks directory not found: $CHUNKS_DIR" >&2
    exit 1
fi

echo "INFO: Organizing files within each filtered class directory"
echo "========================================="

# Find all filtered class directories
CLASS_DIRS=()
while IFS= read -r -d '' dir; do
    if [[ $(basename "$dir") == *"_filtred_by_classes" ]]; then
        CLASS_DIRS+=("$dir")
    fi
done < <(find "$CHUNKS_DIR" -type d -print0 2>/dev/null)

if [[ ${#CLASS_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: No filtered class directories found" >&2
    echo "       Expected directories like: part_1_filtred_by_classes, part_2_filtred_by_classes, etc." >&2
    exit 1
fi

echo "INFO: Found ${#CLASS_DIRS[@]} filtered class directories to organize"

TOTAL_LAZ_MOVED=0
TOTAL_LAS_MOVED=0

# Process each filtered class directory
for CLASS_DIR in "${CLASS_DIRS[@]}"; do
    DIR_NAME=$(basename "$CLASS_DIR")
    
    echo ""
    echo "Processing: $DIR_NAME"
    echo "  Directory: $CLASS_DIR"
    
    # Create subfolders within this directory
    COMPRESSED_DIR="$CLASS_DIR/compressed"
    NOT_COMPRESSED_DIR="$CLASS_DIR/not_compressed"
    
    mkdir -p "$COMPRESSED_DIR"
    mkdir -p "$NOT_COMPRESSED_DIR"
    
    # Find LAZ files in the root of this directory (not in subfolders)
    LAZ_FILES=($(find "$CLASS_DIR" -maxdepth 1 -name "*.laz" 2>/dev/null || true))
    LAS_FILES=($(find "$CLASS_DIR" -maxdepth 1 -name "*.las" 2>/dev/null || true))
    
    # Move LAZ files to compressed subfolder
    if [[ ${#LAZ_FILES[@]} -gt 0 ]]; then
        echo "  Moving ${#LAZ_FILES[@]} LAZ files to compressed/"
        for laz_file in "${LAZ_FILES[@]}"; do
            filename=$(basename "$laz_file")
            mv "$laz_file" "$COMPRESSED_DIR/"
            echo "    ✓ $filename → compressed/"
            TOTAL_LAZ_MOVED=$((TOTAL_LAZ_MOVED + 1))
        done
    else
        echo "  No LAZ files found in root of $DIR_NAME"
    fi
    
    # Move LAS files to not_compressed subfolder
    if [[ ${#LAS_FILES[@]} -gt 0 ]]; then
        echo "  Moving ${#LAS_FILES[@]} LAS files to not_compressed/"
        for las_file in "${LAS_FILES[@]}"; do
            filename=$(basename "$las_file")
            mv "$las_file" "$NOT_COMPRESSED_DIR/"
            echo "    ✓ $filename → not_compressed/"
            TOTAL_LAS_MOVED=$((TOTAL_LAS_MOVED + 1))
        done
    else
        echo "  No LAS files found in root of $DIR_NAME"
    fi
    
    # Show the structure created
    if [[ ${#LAZ_FILES[@]} -gt 0 ]] || [[ ${#LAS_FILES[@]} -gt 0 ]]; then
        echo "  ✓ Created structure:"
        echo "    $DIR_NAME/"
        echo "    ├── compressed/     (${#LAZ_FILES[@]} LAZ files)"
        echo "    └── not_compressed/ (${#LAS_FILES[@]} LAS files)"
    fi
done

echo ""
echo "========================================="
echo "ORGANIZATION COMPLETE"
echo "========================================="
echo "Total LAZ files moved: $TOTAL_LAZ_MOVED"
echo "Total LAS files moved: $TOTAL_LAS_MOVED"

# Show the final directory structure
echo ""
echo "📁 Final Directory Structure:"
find "$CHUNKS_DIR" -name "*_filtred_by_classes" | sort | while read -r class_dir; do
    dir_name=$(basename "$class_dir")
    echo ""
    echo "$dir_name/"
    
    # Show compressed folder
    compressed_dir="$class_dir/compressed"
    if [[ -d "$compressed_dir" ]]; then
        laz_count=$(find "$compressed_dir" -name "*.laz" 2>/dev/null | wc -l)
        echo "├── compressed/ ($laz_count LAZ files)"
        
        # Show first few files as examples
        find "$compressed_dir" -name "*.laz" | head -3 | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            printf "│   ├── %-25s %8s points\n" "$filename" "$point_count"
        done
        
        if [[ $laz_count -gt 3 ]]; then
            echo "│   └── ... ($(($laz_count - 3)) more files)"
        fi
    fi
    
    # Show not_compressed folder
    not_compressed_dir="$class_dir/not_compressed"
    if [[ -d "$not_compressed_dir" ]]; then
        las_count=$(find "$not_compressed_dir" -name "*.las" 2>/dev/null | wc -l)
        echo "└── not_compressed/ ($las_count LAS files)"
        
        # Show first few files as examples
        find "$not_compressed_dir" -name "*.las" | head -3 | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            printf "    ├── %-25s %8s points\n" "$filename" "$point_count"
        done
        
        if [[ $las_count -gt 3 ]]; then
            echo "    └── ... ($(($las_count - 3)) more files)"
        fi
    fi
done

# Create index files in each directory
echo ""
echo "Creating index files..."
find "$CHUNKS_DIR" -name "*_filtred_by_classes" | while read -r class_dir; do
    dir_name=$(basename "$class_dir")
    
    # Create index for compressed files
    compressed_dir="$class_dir/compressed"
    if [[ -d "$compressed_dir" ]]; then
        index_file="$compressed_dir/index.txt"
        cat > "$index_file" << EOF
Compressed LAZ Files - $dir_name
Generated: $(date)
========================================

EOF
        find "$compressed_dir" -name "*.laz" | sort | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            printf "%-30s %10s points\n" "$filename" "$point_count" >> "$index_file"
        done
        echo "✓ Created: $dir_name/compressed/index.txt"
    fi
    
    # Create index for not_compressed files
    not_compressed_dir="$class_dir/not_compressed"
    if [[ -d "$not_compressed_dir" ]]; then
        index_file="$not_compressed_dir/index.txt"
        cat > "$index_file" << EOF
Uncompressed LAS Files - $dir_name  
Generated: $(date)
========================================

EOF
        find "$not_compressed_dir" -name "*.las" | sort | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}.get('num_points', 0))" 2>/dev/null || echo "0")
            printf "%-30s %10s points\n" "$filename" "$point_count" >> "$index_file"
        done
        echo "✓ Created: $dir_name/not_compressed/index.txt"
    fi
done

echo ""
echo "🎯 Usage:"
echo "  📁 /compressed/     → LAZ files for storage and processing"
echo "  📁 /not_compressed/ → LAS files for CloudCompare, QGIS, etc."
echo ""
echo "========================================="