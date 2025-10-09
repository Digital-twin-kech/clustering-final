#!/bin/bash

# Populate the chunk class directories with mobile mapping classes
# Usage: ./populate_chunk_classes.sh JOB_ROOT

set -euo pipefail

JOB_ROOT="$1"

echo "INFO: Populating chunk class directories with mobile mapping classes"

# Mobile mapping classification codes from classes.json  
declare -A CLASS_NAMES=(
    [1]="Other"
    [2]="Roads"
    [3]="Sidewalks" 
    [4]="OtherGround"
    [5]="TrafficIslands"
    [6]="Buildings"
    [7]="Trees"
    [8]="OtherVegetation"
    [9]="TrafficLights"
    [10]="TrafficSigns"
    [11]="Wires"
    [12]="Masts"
    [13]="Pedestrians"
    [15]="2Wheel"
    [16]="Mobile4w"
    [17]="Stationary4w" 
    [18]="Noise"
    [40]="TreeTrunks"
)

CLASSIFICATION_CODES="1 2 3 4 5 6 7 8 9 10 11 12 13 15 16 17 18 40"

# Find chunk files
CHUNKS_DIR="$JOB_ROOT/chunks"
CHUNK_FILES=($(find "$CHUNKS_DIR" -name "part_*.laz" | sort))

if [[ ${#CHUNK_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No chunk files found" >&2
    exit 1
fi

echo "INFO: Found ${#CHUNK_FILES[@]} chunks to process"

TOTAL_EXTRACTED=0

# Process each chunk
for CHUNK_FILE in "${CHUNK_FILES[@]}"; do
    CHUNK_NAME=$(basename "$CHUNK_FILE" .laz)
    CLASS_DIR="$CHUNKS_DIR/${CHUNK_NAME}_filtred_by_classes"
    
    echo ""
    echo "================================================="
    echo "Processing: $CHUNK_NAME"
    echo "Input: $CHUNK_FILE" 
    echo "Output: $CLASS_DIR"
    echo "================================================="
    
    # Get chunk info
    CHUNK_POINTS=$(pdal info "$CHUNK_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
    echo "INFO: Chunk contains $CHUNK_POINTS points"
    
    CHUNK_EXTRACTED=0
    
    # Extract each class
    for CLASS_CODE in $CLASSIFICATION_CODES; do
        CLASS_NAME="${CLASS_NAMES[$CLASS_CODE]}"
        OUTPUT_FILE="$CLASS_DIR/${CLASS_CODE}_${CLASS_NAME}.laz"
        
        echo "INFO: Extracting class $CLASS_CODE ($CLASS_NAME)..."
        
        # Create extraction pipeline
        PIPELINE_FILE="/tmp/extract_${CHUNK_NAME}_${CLASS_CODE}.json"
        cat > "$PIPELINE_FILE" << EOF
{
  "pipeline": [
    {
      "type": "readers.las",
      "filename": "$CHUNK_FILE"
    },
    {
      "type": "filters.range", 
      "limits": "Classification[$CLASS_CODE:$CLASS_CODE]"
    },
    {
      "type": "writers.las",
      "filename": "$OUTPUT_FILE",
      "compression": true,
      "forward": "all"
    }
  ]
}
EOF
        
        # Execute extraction
        if timeout 60 pdal pipeline "$PIPELINE_FILE" >/dev/null 2>&1; then
            if [[ -f "$OUTPUT_FILE" ]]; then
                POINT_COUNT=$(pdal info "$OUTPUT_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                
                if [[ $POINT_COUNT -gt 0 ]]; then
                    printf "  ✓ %s: %8s points\n" "$CLASS_NAME" "$POINT_COUNT"
                    CHUNK_EXTRACTED=$((CHUNK_EXTRACTED + 1))
                    TOTAL_EXTRACTED=$((TOTAL_EXTRACTED + 1))
                else
                    echo "  ✗ $CLASS_NAME: no points"
                    rm -f "$OUTPUT_FILE"
                fi
            else
                echo "  ✗ $CLASS_NAME: no output file"
            fi
        else
            echo "  ✗ $CLASS_NAME: extraction failed"
        fi
        
        # Clean up
        rm -f "$PIPELINE_FILE"
    done
    
    echo "INFO: $CHUNK_NAME: extracted $CHUNK_EXTRACTED classes"
done

echo ""
echo "========================================="
echo "EXTRACTION COMPLETE"
echo "========================================="
echo "Total class files created: $TOTAL_EXTRACTED"
echo ""
echo "Directory structure:"
find "$CHUNKS_DIR" -name "*_filtred_by_classes" | sort | while read -r dir; do
    chunk_name=$(basename "$dir")
    echo "$chunk_name/"
    find "$dir" -name "*.laz" | sort | while read -r file; do
        filename=$(basename "$file")
        point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
        printf "├── %-30s %8s points\n" "$filename" "$point_count"
    done
    echo ""
done

echo "Ready for clustering!"
echo "Next: Create clustering script for mobile mapping data"
echo "========================================="