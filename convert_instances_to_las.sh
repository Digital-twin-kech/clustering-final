#!/bin/bash

# Convert all LAZ instances to LAS files for visualization
# Creates instances_las folders alongside instances folders
# Usage: ./convert_instances_to_las.sh JOB_ROOT

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "ERROR: Usage: $0 JOB_ROOT" >&2
    echo "  JOB_ROOT: Job directory containing clustered chunks" >&2
    exit 1
fi

JOB_ROOT="$1"
CHUNKS_DIR="$JOB_ROOT/chunks"

if [[ ! -d "$CHUNKS_DIR" ]]; then
    echo "ERROR: Chunks directory not found: $CHUNKS_DIR" >&2
    exit 1
fi

echo "INFO: Converting all LAZ instances to LAS files"
echo "========================================="

# Find all chunk directories
CHUNK_DIRS=($(find "$CHUNKS_DIR" -name "*_chunk" -type d | sort))

if [[ ${#CHUNK_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: No chunk directories found in $CHUNKS_DIR" >&2
    exit 1
fi

echo "INFO: Found ${#CHUNK_DIRS[@]} chunk directories to process"

TOTAL_INSTANCES_CONVERTED=0
TOTAL_CLASSES_PROCESSED=0

# Process each chunk
for CHUNK_DIR in "${CHUNK_DIRS[@]}"; do
    CHUNK_NAME=$(basename "$CHUNK_DIR")
    FILTERED_DIR="$CHUNK_DIR/compressed/filtred_by_classes"
    
    echo ""
    echo "================================================="
    echo "Processing: $CHUNK_NAME"
    echo "================================================="
    
    if [[ ! -d "$FILTERED_DIR" ]]; then
        echo "  ⚠ No filtered classes directory found"
        continue
    fi
    
    # Find all instances directories
    INSTANCE_DIRS=($(find "$FILTERED_DIR" -name "instances" -type d | sort))
    
    if [[ ${#INSTANCE_DIRS[@]} -eq 0 ]]; then
        echo "  ⚠ No instance directories found"
        continue
    fi
    
    echo "  INFO: Found ${#INSTANCE_DIRS[@]} classes with instances"
    
    # Process each class with instances
    for INSTANCES_DIR in "${INSTANCE_DIRS[@]}"; do
        CLASS_DIR=$(dirname "$INSTANCES_DIR")
        CLASS_NAME=$(basename "$CLASS_DIR")
        
        echo ""
        echo "  Processing: $CLASS_NAME"
        
        # Create instances_las directory
        INSTANCES_LAS_DIR="$CLASS_DIR/instances_las"
        mkdir -p "$INSTANCES_LAS_DIR"
        
        # Find all LAZ instance files
        INSTANCE_FILES=($(find "$INSTANCES_DIR" -name "*.laz" 2>/dev/null | sort))
        
        if [[ ${#INSTANCE_FILES[@]} -eq 0 ]]; then
            echo "    ⚠ No LAZ instance files found"
            continue
        fi
        
        echo "    INFO: Converting ${#INSTANCE_FILES[@]} LAZ instances to LAS"
        
        CLASS_CONVERTED=0
        # Convert each LAZ instance to LAS
        for LAZ_FILE in "${INSTANCE_FILES[@]}"; do
            INSTANCE_NAME=$(basename "$LAZ_FILE" .laz)
            LAS_FILE="$INSTANCES_LAS_DIR/${INSTANCE_NAME}.las"
            
            # Skip if LAS file already exists and is newer
            if [[ -f "$LAS_FILE" ]] && [[ "$LAS_FILE" -nt "$LAZ_FILE" ]]; then
                echo "      ✓ $INSTANCE_NAME (already exists)"
                CLASS_CONVERTED=$((CLASS_CONVERTED + 1))
                continue
            fi
            
            # Convert LAZ to LAS
            if pdal translate "$LAZ_FILE" "$LAS_FILE" >/dev/null 2>&1; then
                # Get point count for verification
                POINT_COUNT=$(pdal info "$LAS_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                
                # Get file sizes
                LAZ_SIZE=$(stat -c%s "$LAZ_FILE" 2>/dev/null || echo "0")
                LAS_SIZE=$(stat -c%s "$LAS_FILE" 2>/dev/null || echo "0")
                
                # Convert to human readable
                LAZ_SIZE_HR=$(numfmt --to=iec "$LAZ_SIZE" 2>/dev/null || echo "${LAZ_SIZE}B")
                LAS_SIZE_HR=$(numfmt --to=iec "$LAS_SIZE" 2>/dev/null || echo "${LAS_SIZE}B")
                
                echo "      ✓ $INSTANCE_NAME ($POINT_COUNT pts, $LAZ_SIZE_HR → $LAS_SIZE_HR)"
                CLASS_CONVERTED=$((CLASS_CONVERTED + 1))
            else
                echo "      ✗ Failed to convert $INSTANCE_NAME"
            fi
        done
        
        if [[ $CLASS_CONVERTED -gt 0 ]]; then
            echo "    ✅ Converted $CLASS_CONVERTED instances for $CLASS_NAME"
            TOTAL_INSTANCES_CONVERTED=$((TOTAL_INSTANCES_CONVERTED + CLASS_CONVERTED))
            TOTAL_CLASSES_PROCESSED=$((TOTAL_CLASSES_PROCESSED + 1))
            
            # Create index file for this class
            INDEX_FILE="$INSTANCES_LAS_DIR/index.txt"
            cat > "$INDEX_FILE" << EOF
LAS Instance Files - $CLASS_NAME ($CHUNK_NAME)
Generated: $(date)
========================================

EOF
            find "$INSTANCES_LAS_DIR" -name "*.las" | sort | while read -r las_file; do
                filename=$(basename "$las_file")
                point_count=$(pdal info "$las_file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                file_size=$(stat -c%s "$las_file" 2>/dev/null | numfmt --to=iec 2>/dev/null || echo "0B")
                printf "%-30s %10s points %8s\\n" "$filename" "$point_count" "$file_size" >> "$INDEX_FILE"
            done
            echo "    📄 Created index: instances_las/index.txt"
        fi
    done
done

echo ""
echo "========================================="
echo "CONVERSION COMPLETE"
echo "========================================="
echo "Classes processed: $TOTAL_CLASSES_PROCESSED"
echo "Total instances converted: $TOTAL_INSTANCES_CONVERTED"

# Show final structure examples
echo ""
echo "📁 Final Structure Examples:"
find "$CHUNKS_DIR" -name "instances_las" -type d | head -3 | while read -r las_dir; do
    class_dir=$(dirname "$las_dir")
    chunk_dir=$(dirname "$(dirname "$(dirname "$class_dir")")")
    chunk_name=$(basename "$chunk_dir")
    class_name=$(basename "$class_dir")
    
    las_count=$(find "$las_dir" -name "*.las" | wc -l)
    
    echo ""
    echo "$chunk_name/$class_name/"
    echo "├── instances/         (LAZ compressed files)"
    echo "└── instances_las/     ($las_count LAS files for visualization)"
    
    # Show first few LAS files
    find "$las_dir" -name "*.las" | head -3 | while read -r las_file; do
        filename=$(basename "$las_file")
        point_count=$(pdal info "$las_file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
        printf "    ├── %-25s %8s points\\n" "$filename" "$point_count"
    done
done

echo ""
echo "🎯 Usage:"
echo "  📁 instances/     → LAZ files (compressed, for storage)"
echo "  📁 instances_las/ → LAS files (uncompressed, for CloudCompare/QGIS)"
echo ""
echo "💡 Load LAS files from instances_las/ folders in your visualization software!"
echo "========================================"