#!/bin/bash

# Organize chunks and filtered classes into unified compressed/not_compressed structure
# Creates: part_X_chunk/compressed/ and part_X_chunk/not_compressed/
# Each contains both the original chunk file and all filtered class files
# Usage: ./organize_chunks_and_classes.sh JOB_ROOT

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

echo "INFO: Creating separated chunk and class organization in: $CHUNKS_DIR"
echo "========================================="

# Find all chunk files and filtered class directories
CHUNK_FILES=($(find "$CHUNKS_DIR" -name "part_*.laz" 2>/dev/null | sort))
CLASS_DIRS=()
while IFS= read -r -d '' dir; do
    if [[ $(basename "$dir") == *"_filtred_by_classes" ]]; then
        CLASS_DIRS+=("$dir")
    fi
done < <(find "$CHUNKS_DIR" -type d -print0 2>/dev/null)

echo "INFO: Found ${#CHUNK_FILES[@]} chunk files and ${#CLASS_DIRS[@]} filtered class directories"

if [[ ${#CHUNK_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No chunk files found" >&2
    exit 1
fi

TOTAL_CHUNKS_PROCESSED=0
TOTAL_CHUNK_LAZ=0
TOTAL_CHUNK_LAS=0
TOTAL_CLASS_LAZ=0
TOTAL_CLASS_LAS=0

# Process each chunk
for CHUNK_FILE in "${CHUNK_FILES[@]}"; do
    CHUNK_NAME=$(basename "$CHUNK_FILE" .laz)
    CHUNK_DIR="$CHUNKS_DIR/${CHUNK_NAME}_chunk"
    FILTERED_DIR="$CHUNKS_DIR/${CHUNK_NAME}_filtred_by_classes"
    
    echo ""
    echo "================================================="
    echo "Processing: $CHUNK_NAME"
    echo "Original chunk: $CHUNK_FILE"
    echo "Filtered classes: $FILTERED_DIR"
    echo "Target structure: $CHUNK_DIR/"
    echo "================================================="
    
    # Create target directories with separation
    CHUNK_COMPRESSED_DIR="$CHUNK_DIR/compressed"
    CHUNK_NOT_COMPRESSED_DIR="$CHUNK_DIR/not_compressed"
    CLASS_COMPRESSED_DIR="$CHUNK_DIR/${CHUNK_NAME}_filtred_by_classes"
    
    mkdir -p "$CHUNK_COMPRESSED_DIR"
    mkdir -p "$CHUNK_NOT_COMPRESSED_DIR"
    mkdir -p "$CLASS_COMPRESSED_DIR"
    
    CURRENT_CHUNK_LAZ=0
    CURRENT_CHUNK_LAS=0
    CURRENT_CLASS_LAZ=0
    CURRENT_CLASS_LAS=0
    
    # 1. Handle original chunk file
    echo "  INFO: Processing original chunk file"
    if [[ -f "$CHUNK_FILE" ]]; then
        # Copy original LAZ chunk to compressed directory
        cp "$CHUNK_FILE" "$CHUNK_COMPRESSED_DIR/"
        echo "    ✓ Original chunk → compressed/$(basename "$CHUNK_FILE")"
        CURRENT_CHUNK_LAZ=$((CURRENT_CHUNK_LAZ + 1))
        
        # Convert original chunk to LAS for visualization
        CHUNK_LAS_FILE="$CHUNK_NOT_COMPRESSED_DIR/$(basename "$CHUNK_FILE" .laz).las"
        if pdal translate "$CHUNK_FILE" "$CHUNK_LAS_FILE" >/dev/null 2>&1; then
            echo "    ✓ $(basename "$CHUNK_FILE") → not_compressed/$(basename "$CHUNK_LAS_FILE")"
            CURRENT_CHUNK_LAS=$((CURRENT_CHUNK_LAS + 1))
        else
            echo "    ✗ Failed to convert chunk to LAS"
        fi
    fi
    
    # 2. Handle filtered class files separately
    if [[ -d "$FILTERED_DIR" ]]; then
        echo "  INFO: Processing filtered classes from $FILTERED_DIR"
        
        # Find all LAZ files in filtered classes directory
        FILTERED_LAZ_FILES=($(find "$FILTERED_DIR" -name "*.laz" 2>/dev/null || true))
        if [[ ${#FILTERED_LAZ_FILES[@]} -gt 0 ]]; then
            echo "    INFO: Moving ${#FILTERED_LAZ_FILES[@]} filtered LAZ files to ${CHUNK_NAME}_filtred_by_classes/"
            for laz_file in "${FILTERED_LAZ_FILES[@]}"; do
                filename=$(basename "$laz_file")
                cp "$laz_file" "$CLASS_COMPRESSED_DIR/"
                echo "      ✓ $filename → ${CHUNK_NAME}_filtred_by_classes/"
                CURRENT_CLASS_LAZ=$((CURRENT_CLASS_LAZ + 1))
            done
        fi
        
        # Find all LAS files in filtered classes directory  
        FILTERED_LAS_FILES=($(find "$FILTERED_DIR" -name "*.las" 2>/dev/null || true))
        if [[ ${#FILTERED_LAS_FILES[@]} -gt 0 ]]; then
            echo "    INFO: Moving ${#FILTERED_LAS_FILES[@]} filtered LAS files to ${CHUNK_NAME}_filtred_by_classes/"
            for las_file in "${FILTERED_LAS_FILES[@]}"; do
                filename=$(basename "$las_file")
                cp "$las_file" "$CLASS_COMPRESSED_DIR/"
                echo "      ✓ $filename → ${CHUNK_NAME}_filtred_by_classes/"
                CURRENT_CLASS_LAS=$((CURRENT_CLASS_LAS + 1))
            done
        fi
    else
        echo "  ⚠ No filtered classes directory found: $FILTERED_DIR"
    fi
    
    # Show summary for this chunk
    echo "  📊 Chunk Summary:"
    echo "    ├── compressed/                      ($CURRENT_CHUNK_LAZ original LAZ files)"
    echo "    ├── not_compressed/                  ($CURRENT_CHUNK_LAS original LAS files)"
    echo "    └── ${CHUNK_NAME}_filtred_by_classes/ ($CURRENT_CLASS_LAZ LAZ + $CURRENT_CLASS_LAS LAS class files)"
    
    TOTAL_CHUNKS_PROCESSED=$((TOTAL_CHUNKS_PROCESSED + 1))
    TOTAL_CHUNK_LAZ=$((TOTAL_CHUNK_LAZ + CURRENT_CHUNK_LAZ))
    TOTAL_CHUNK_LAS=$((TOTAL_CHUNK_LAS + CURRENT_CHUNK_LAS))
    TOTAL_CLASS_LAZ=$((TOTAL_CLASS_LAZ + CURRENT_CLASS_LAZ))
    TOTAL_CLASS_LAS=$((TOTAL_CLASS_LAS + CURRENT_CLASS_LAS))
done

echo ""
echo "========================================="
echo "SEPARATED ORGANIZATION COMPLETE"
echo "========================================="
echo "Chunks processed: $TOTAL_CHUNKS_PROCESSED"
echo "Original chunk LAZ files: $TOTAL_CHUNK_LAZ"
echo "Original chunk LAS files: $TOTAL_CHUNK_LAS"
echo "Filtered class LAZ files: $TOTAL_CLASS_LAZ"
echo "Filtered class LAS files: $TOTAL_CLASS_LAS"

# Show the final separated structure
echo ""
echo "📁 Separated Directory Structure:"
find "$CHUNKS_DIR" -name "*_chunk" -type d | sort | while read -r chunk_dir; do
    chunk_name=$(basename "$chunk_dir")
    echo ""
    echo "$chunk_name/"
    
    # Show compressed folder (original chunks only)
    compressed_dir="$chunk_dir/compressed"
    if [[ -d "$compressed_dir" ]]; then
        laz_count=$(find "$compressed_dir" -name "*.laz" 2>/dev/null | wc -l)
        echo "├── compressed/ ($laz_count original LAZ files)"
        
        find "$compressed_dir" -name "*.laz" | sort | head -2 | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            printf "│   ├── %-25s %8s points\\n" "$filename" "$point_count"
        done
    fi
    
    # Show not_compressed folder (original chunks only)
    not_compressed_dir="$chunk_dir/not_compressed"
    if [[ -d "$not_compressed_dir" ]]; then
        las_count=$(find "$not_compressed_dir" -name "*.las" 2>/dev/null | wc -l)
        echo "├── not_compressed/ ($las_count original LAS files)"
        
        find "$not_compressed_dir" -name "*.las" | sort | head -2 | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            printf "│   ├── %-25s %8s points\\n" "$filename" "$point_count"
        done
    fi
    
    # Show filtered classes folder
    base_name=${chunk_name%_chunk}
    class_dir="$chunk_dir/${base_name}_filtred_by_classes"
    if [[ -d "$class_dir" ]]; then
        laz_count=$(find "$class_dir" -name "*.laz" 2>/dev/null | wc -l)
        las_count=$(find "$class_dir" -name "*.las" 2>/dev/null | wc -l)
        echo "└── ${base_name}_filtred_by_classes/ ($laz_count LAZ + $las_count LAS class files)"
        
        find "$class_dir" -name "*.laz" -o -name "*.las" | sort | head -3 | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            printf "    ├── %-25s %8s points\\n" "$filename" "$point_count"
        done
        
        total_class_files=$((laz_count + las_count))
        if [[ $total_class_files -gt 3 ]]; then
            echo "    └── ... ($(($total_class_files - 3)) more class files)"
        fi
    fi
done

# Create index files for each chunk directory
echo ""
echo "Creating index files..."
find "$CHUNKS_DIR" -name "*_chunk" -type d | while read -r chunk_dir; do
    chunk_name=$(basename "$chunk_dir")
    
    # Create index for compressed files
    compressed_dir="$chunk_dir/compressed"
    if [[ -d "$compressed_dir" ]]; then
        index_file="$compressed_dir/index.txt"
        cat > "$index_file" << EOF
Compressed LAZ Files - $chunk_name
Generated: $(date)
========================================

EOF
        find "$compressed_dir" -name "*.laz" | sort | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            file_type="filtered class"
            if [[ "$filename" == part_*.laz ]]; then
                file_type="original chunk"
            fi
            printf "%-30s %10s points (%s)\\n" "$filename" "$point_count" "$file_type" >> "$index_file"
        done
        echo "✓ Created: $chunk_name/compressed/index.txt"
    fi
    
    # Create index for not_compressed files
    not_compressed_dir="$chunk_dir/not_compressed"
    if [[ -d "$not_compressed_dir" ]]; then
        index_file="$not_compressed_dir/index.txt"
        cat > "$index_file" << EOF
Uncompressed LAS Files - $chunk_name  
Generated: $(date)
========================================

EOF
        find "$not_compressed_dir" -name "*.las" | sort | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            file_type="filtered class"
            if [[ "$filename" == part_*.las ]]; then
                file_type="original chunk"
            fi
            printf "%-30s %10s points (%s)\\n" "$filename" "$point_count" "$file_type" >> "$index_file"
        done
        echo "✓ Created: $chunk_name/not_compressed/index.txt"
    fi
done

echo ""
echo "🎯 Separated Structure Usage:"
echo "  📁 /compressed/           → Original chunk LAZ files only"
echo "  📁 /not_compressed/       → Original chunk LAS files only"  
echo "  📁 /part_X_filtred_by_classes/ → All filtered class files (LAZ + LAS)"
echo ""
echo "Each chunk now contains:"
echo "  • Original chunk files separated by format (compressed vs not_compressed)"
echo "  • Filtered class files in their own dedicated folder"
echo "  • Clean separation between original chunks and extracted classes"
echo ""
echo "========================================="