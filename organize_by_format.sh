#!/bin/bash

# Organize LAZ and LAS files into separate folder structures
# Usage: ./organize_by_format.sh JOB_ROOT

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

echo "INFO: Organizing files by format in: $JOB_ROOT"
echo "========================================="

# Create organized directory structure
LAZ_DIR="$JOB_ROOT/compressed_laz"
LAS_DIR="$JOB_ROOT/visualization_las"

mkdir -p "$LAZ_DIR"
mkdir -p "$LAS_DIR"

echo "INFO: Creating organized structure:"
echo "  LAZ files (compressed): $LAZ_DIR"
echo "  LAS files (visualization): $LAS_DIR"

LAZ_MOVED=0
LAS_MOVED=0

# Find all filtered class directories
CLASS_DIRS=()
while IFS= read -r -d '' dir; do
    if [[ $(basename "$dir") == *"_filtred_by_classes" ]]; then
        CLASS_DIRS+=("$dir")
    fi
done < <(find "$CHUNKS_DIR" -type d -print0 2>/dev/null)

if [[ ${#CLASS_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: No filtered class directories found" >&2
    exit 1
fi

echo "INFO: Found ${#CLASS_DIRS[@]} chunk directories to organize"

# Process each chunk directory
for CLASS_DIR in "${CLASS_DIRS[@]}"; do
    # Extract chunk name (e.g., part_1_filtred_by_classes -> part_1)
    DIR_NAME=$(basename "$CLASS_DIR")
    CHUNK_NAME=${DIR_NAME%_filtred_by_classes}
    
    echo ""
    echo "Processing: $CHUNK_NAME"
    
    # Create corresponding directories in organized structure
    LAZ_CHUNK_DIR="$LAZ_DIR/$CHUNK_NAME"
    LAS_CHUNK_DIR="$LAS_DIR/$CHUNK_NAME"
    
    mkdir -p "$LAZ_CHUNK_DIR"
    mkdir -p "$LAS_CHUNK_DIR"
    
    # Move LAZ files
    LAZ_FILES=($(find "$CLASS_DIR" -name "*.laz" 2>/dev/null || true))
    if [[ ${#LAZ_FILES[@]} -gt 0 ]]; then
        echo "  Moving ${#LAZ_FILES[@]} LAZ files to: compressed_laz/$CHUNK_NAME/"
        for laz_file in "${LAZ_FILES[@]}"; do
            filename=$(basename "$laz_file")
            cp "$laz_file" "$LAZ_CHUNK_DIR/"
            echo "    ✓ $filename"
            LAZ_MOVED=$((LAZ_MOVED + 1))
        done
    else
        echo "  No LAZ files found in $DIR_NAME"
    fi
    
    # Move LAS files  
    LAS_FILES=($(find "$CLASS_DIR" -name "*.las" 2>/dev/null || true))
    if [[ ${#LAS_FILES[@]} -gt 0 ]]; then
        echo "  Moving ${#LAS_FILES[@]} LAS files to: visualization_las/$CHUNK_NAME/"
        for las_file in "${LAS_FILES[@]}"; do
            filename=$(basename "$las_file")
            cp "$las_file" "$LAS_CHUNK_DIR/"
            echo "    ✓ $filename"
            LAS_MOVED=$((LAS_MOVED + 1))
        done
    else
        echo "  No LAS files found in $DIR_NAME"
    fi
done

echo ""
echo "========================================="
echo "ORGANIZATION COMPLETE"
echo "========================================="
echo "LAZ files moved: $LAZ_MOVED"
echo "LAS files moved: $LAS_MOVED"

# Show the organized structure
echo ""
echo "New organized structure:"
echo ""
echo "📁 compressed_laz/ (for storage & processing)"
if [[ -d "$LAZ_DIR" ]]; then
    find "$LAZ_DIR" -type d | sort | while read -r dir; do
        if [[ "$dir" != "$LAZ_DIR" ]]; then
            rel_dir=${dir#$LAZ_DIR/}
            echo "├── $rel_dir/"
            find "$dir" -name "*.laz" | head -3 | while read -r file; do
                filename=$(basename "$file")
                point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                printf "│   ├── %-30s %8s points\n" "$filename" "$point_count"
            done
            more_files=$(find "$dir" -name "*.laz" | wc -l)
            if [[ $more_files -gt 3 ]]; then
                echo "│   └── ... ($(($more_files - 3)) more files)"
            fi
        fi
    done
fi

echo ""
echo "📁 visualization_las/ (for viewing & analysis)"
if [[ -d "$LAS_DIR" ]]; then
    find "$LAS_DIR" -type d | sort | while read -r dir; do
        if [[ "$dir" != "$LAS_DIR" ]]; then
            rel_dir=${dir#$LAS_DIR/}
            echo "├── $rel_dir/"
            find "$dir" -name "*.las" | head -3 | while read -r file; do
                filename=$(basename "$file")
                point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                printf "│   ├── %-30s %8s points\n" "$filename" "$point_count"
            done
            more_files=$(find "$dir" -name "*.las" | wc -l)
            if [[ $more_files -gt 3 ]]; then
                echo "│   └── ... ($(($more_files - 3)) more files)"
            fi
        fi
    done
fi

# Create index files for easy access
LAZ_INDEX="$LAZ_DIR/index.txt"
LAS_INDEX="$LAS_DIR/index.txt"

echo ""
echo "Creating index files..."

# LAZ index
cat > "$LAZ_INDEX" << EOF
Compressed LAZ Files Index
Generated: $(date)
========================================

Directory Structure:
EOF

find "$LAZ_DIR" -name "*.laz" | sort | while read -r file; do
    rel_path=${file#$LAZ_DIR/}
    point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
    printf "%-50s %10s points\n" "$rel_path" "$point_count" >> "$LAZ_INDEX"
done

# LAS index
cat > "$LAS_INDEX" << EOF
Visualization LAS Files Index  
Generated: $(date)
========================================

Directory Structure:
EOF

find "$LAS_DIR" -name "*.las" | sort | while read -r file; do
    rel_path=${file#$LAS_DIR/}
    point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
    printf "%-50s %10s points\n" "$rel_path" "$point_count" >> "$LAS_INDEX"
done

echo "✓ Created: $LAZ_INDEX"
echo "✓ Created: $LAS_INDEX"

echo ""
echo "Usage:"
echo "  📁 Use compressed_laz/ for:"
echo "     - Long-term storage (smaller files)"
echo "     - Further processing with PDAL"
echo "     - Backup and archiving"
echo ""
echo "  📁 Use visualization_las/ for:"
echo "     - Loading in CloudCompare, QGIS, etc."
echo "     - Quick visualization (faster loading)"
echo "     - Analysis and measurement tools"
echo ""
echo "========================================="