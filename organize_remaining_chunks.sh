#!/bin/bash

# Organize remaining chunks to match part_1_chunk and part_2_chunk structure
# Target structure:
#   part_X_chunk/
#   ├── compressed/
#   │   ├── filtred_by_classes/ (class LAZ files)
#   │   └── main_chunk/        (original part_X.laz)
#   └── not_compressed/
#       ├── filtred_by_classes/ (class LAS files)
#       └── main_chunk/        (original part_X.las)

set -euo pipefail

JOB_ROOT="/home/prodair/Desktop/MORIUS5090/clustering/out/job-20250911110357"
CHUNKS_DIR="$JOB_ROOT/chunks"

echo "INFO: Organizing remaining chunks to match part_1_chunk structure"
echo "========================================="

# Process chunks 3, 4, 5 (assuming 1 and 2 are already organized)
for PART_NUM in 3 4 5; do
    CHUNK_FILE="$CHUNKS_DIR/part_${PART_NUM}.laz"
    LAS_FILE="$CHUNKS_DIR/part_${PART_NUM}.las"
    CHUNK_DIR="$CHUNKS_DIR/part_${PART_NUM}_chunk"
    OLD_FILTERED_DIR="$CHUNKS_DIR/part_${PART_NUM}_filtred_by_classes"
    
    echo ""
    echo "================================================="
    echo "Processing: part_$PART_NUM"
    echo "================================================="
    
    # Create target structure
    COMPRESSED_MAIN="$CHUNK_DIR/compressed/main_chunk"
    COMPRESSED_CLASSES="$CHUNK_DIR/compressed/filtred_by_classes"
    NOT_COMPRESSED_MAIN="$CHUNK_DIR/not_compressed/main_chunk"
    NOT_COMPRESSED_CLASSES="$CHUNK_DIR/not_compressed/filtred_by_classes"
    
    mkdir -p "$COMPRESSED_MAIN"
    mkdir -p "$COMPRESSED_CLASSES"
    mkdir -p "$NOT_COMPRESSED_MAIN"
    mkdir -p "$NOT_COMPRESSED_CLASSES"
    
    # 1. Move original chunk files to main_chunk folders
    echo "INFO: Moving original chunk files"
    if [[ -f "$CHUNK_FILE" ]]; then
        mv "$CHUNK_FILE" "$COMPRESSED_MAIN/"
        echo "  ✓ part_${PART_NUM}.laz → compressed/main_chunk/"
    else
        echo "  ⚠ part_${PART_NUM}.laz not found"
    fi
    
    if [[ -f "$LAS_FILE" ]]; then
        mv "$LAS_FILE" "$NOT_COMPRESSED_MAIN/"
        echo "  ✓ part_${PART_NUM}.las → not_compressed/main_chunk/"
    else
        echo "  ⚠ part_${PART_NUM}.las not found"
    fi
    
    # 2. Move filtered class files from old directory structure
    if [[ -d "$OLD_FILTERED_DIR" ]]; then
        echo "INFO: Moving filtered class files from old structure"
        
        # Move compressed folder contents
        if [[ -d "$OLD_FILTERED_DIR/compressed" ]]; then
            COMPRESSED_FILES=($(find "$OLD_FILTERED_DIR/compressed" -name "*.laz" 2>/dev/null || true))
            if [[ ${#COMPRESSED_FILES[@]} -gt 0 ]]; then
                echo "  INFO: Moving ${#COMPRESSED_FILES[@]} LAZ class files"
                for laz_file in "${COMPRESSED_FILES[@]}"; do
                    filename=$(basename "$laz_file")
                    mv "$laz_file" "$COMPRESSED_CLASSES/"
                    echo "    ✓ $filename → compressed/filtred_by_classes/"
                done
            fi
            
            # Copy index file if it exists
            if [[ -f "$OLD_FILTERED_DIR/compressed/index.txt" ]]; then
                cp "$OLD_FILTERED_DIR/compressed/index.txt" "$COMPRESSED_CLASSES/"
                echo "    ✓ index.txt → compressed/filtred_by_classes/"
            fi
        fi
        
        # Move not_compressed folder contents
        if [[ -d "$OLD_FILTERED_DIR/not_compressed" ]]; then
            UNCOMPRESSED_FILES=($(find "$OLD_FILTERED_DIR/not_compressed" -name "*.las" 2>/dev/null || true))
            if [[ ${#UNCOMPRESSED_FILES[@]} -gt 0 ]]; then
                echo "  INFO: Moving ${#UNCOMPRESSED_FILES[@]} LAS class files"
                for las_file in "${UNCOMPRESSED_FILES[@]}"; do
                    filename=$(basename "$las_file")
                    mv "$las_file" "$NOT_COMPRESSED_CLASSES/"
                    echo "    ✓ $filename → not_compressed/filtred_by_classes/"
                done
            fi
            
            # Copy index file if it exists
            if [[ -f "$OLD_FILTERED_DIR/not_compressed/index.txt" ]]; then
                cp "$OLD_FILTERED_DIR/not_compressed/index.txt" "$NOT_COMPRESSED_CLASSES/"
                echo "    ✓ index.txt → not_compressed/filtred_by_classes/"
            fi
        fi
        
        # Remove old directory structure
        echo "  INFO: Removing old directory structure"
        rm -rf "$OLD_FILTERED_DIR"
        echo "    ✓ Removed $OLD_FILTERED_DIR"
        
    else
        echo "  ⚠ Old filtered directory not found: $OLD_FILTERED_DIR"
    fi
    
    # 3. Check if chunk directory already has a different structure and needs cleanup
    if [[ -d "$CHUNK_DIR" ]]; then
        # Check for any files directly in compressed/ or not_compressed/ (not in subfolders)
        DIRECT_COMPRESSED=($(find "$CHUNK_DIR/compressed" -maxdepth 1 -name "*.laz" 2>/dev/null || true))
        DIRECT_UNCOMPRESSED=($(find "$CHUNK_DIR/not_compressed" -maxdepth 1 -name "*.las" 2>/dev/null || true))
        
        if [[ ${#DIRECT_COMPRESSED[@]} -gt 0 ]]; then
            echo "  INFO: Moving ${#DIRECT_COMPRESSED[@]} LAZ files from compressed/ to proper subfolders"
            for laz_file in "${DIRECT_COMPRESSED[@]}"; do
                filename=$(basename "$laz_file")
                if [[ "$filename" == part_*.laz ]]; then
                    mv "$laz_file" "$COMPRESSED_MAIN/"
                    echo "    ✓ $filename → compressed/main_chunk/"
                else
                    mv "$laz_file" "$COMPRESSED_CLASSES/"
                    echo "    ✓ $filename → compressed/filtred_by_classes/"
                fi
            done
        fi
        
        if [[ ${#DIRECT_UNCOMPRESSED[@]} -gt 0 ]]; then
            echo "  INFO: Moving ${#DIRECT_UNCOMPRESSED[@]} LAS files from not_compressed/ to proper subfolders"
            for las_file in "${DIRECT_UNCOMPRESSED[@]}"; do
                filename=$(basename "$las_file")
                if [[ "$filename" == part_*.las ]]; then
                    mv "$las_file" "$NOT_COMPRESSED_MAIN/"
                    echo "    ✓ $filename → not_compressed/main_chunk/"
                else
                    mv "$las_file" "$NOT_COMPRESSED_CLASSES/"
                    echo "    ✓ $filename → not_compressed/filtred_by_classes/"
                fi
            done
        fi
    fi
    
    # 4. Show final structure
    echo "  📊 Final Structure for part_$PART_NUM:"
    main_laz_count=$(find "$COMPRESSED_MAIN" -name "*.laz" 2>/dev/null | wc -l)
    main_las_count=$(find "$NOT_COMPRESSED_MAIN" -name "*.las" 2>/dev/null | wc -l)
    class_laz_count=$(find "$COMPRESSED_CLASSES" -name "*.laz" 2>/dev/null | wc -l)
    class_las_count=$(find "$NOT_COMPRESSED_CLASSES" -name "*.las" 2>/dev/null | wc -l)
    
    echo "    ├── compressed/"
    echo "    │   ├── main_chunk/        ($main_laz_count LAZ files)"
    echo "    │   └── filtred_by_classes/ ($class_laz_count LAZ files)"
    echo "    └── not_compressed/"
    echo "        ├── main_chunk/        ($main_las_count LAS files)"
    echo "        └── filtred_by_classes/ ($class_las_count LAS files)"
done

echo ""
echo "========================================="
echo "ORGANIZATION COMPLETE"
echo "========================================="

# Show final directory structure
echo ""
echo "📁 Final Chunks Structure:"
for PART_NUM in 1 2 3 4 5; do
    CHUNK_DIR="$CHUNKS_DIR/part_${PART_NUM}_chunk"
    if [[ -d "$CHUNK_DIR" ]]; then
        echo ""
        echo "part_${PART_NUM}_chunk/"
        
        main_laz_count=$(find "$CHUNK_DIR/compressed/main_chunk" -name "*.laz" 2>/dev/null | wc -l)
        main_las_count=$(find "$CHUNK_DIR/not_compressed/main_chunk" -name "*.las" 2>/dev/null | wc -l)
        class_laz_count=$(find "$CHUNK_DIR/compressed/filtred_by_classes" -name "*.laz" 2>/dev/null | wc -l)
        class_las_count=$(find "$CHUNK_DIR/not_compressed/filtred_by_classes" -name "*.las" 2>/dev/null | wc -l)
        
        echo "├── compressed/"
        echo "│   ├── main_chunk/        ($main_laz_count original LAZ)"
        echo "│   └── filtred_by_classes/ ($class_laz_count class LAZ)"
        echo "└── not_compressed/"
        echo "    ├── main_chunk/        ($main_las_count original LAS)"
        echo "    └── filtred_by_classes/ ($class_las_count class LAS)"
    fi
done

echo ""
echo "🎯 Clean uniform structure achieved!"
echo "All chunks now follow the same organization pattern."
echo "========================================="