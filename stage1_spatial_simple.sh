#!/bin/bash

# Stage 1 Spatial Simple: Reliable spatial chunking using translate
# Uses PDAL translate with bounds parameter for spatial cropping
# Usage: ./stage1_spatial_simple.sh

set -euo pipefail

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out_spatial"

echo "=== STAGE 1 SPATIAL SIMPLE: RELIABLE SPATIAL CHUNKING ==="
echo "Input file: cloud_point_part_1.laz"
echo "Method: PDAL translate with bounds cropping"
echo ""

# Setup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"

# Get dataset bounds
echo "Getting dataset bounds..."
BOUNDS_DATA=$(pdal info "$INPUT_FILE" --summary)
MIN_X=$(echo "$BOUNDS_DATA" | python3 -c "import json, sys; data = json.load(sys.stdin); print(data['summary']['bounds']['minx'])")
MIN_Y=$(echo "$BOUNDS_DATA" | python3 -c "import json, sys; data = json.load(sys.stdin); print(data['summary']['bounds']['miny'])")
MAX_X=$(echo "$BOUNDS_DATA" | python3 -c "import json, sys; data = json.load(sys.stdin); print(data['summary']['bounds']['maxx'])")
MAX_Y=$(echo "$BOUNDS_DATA" | python3 -c "import json, sys; data = json.load(sys.stdin); print(data['summary']['bounds']['maxy'])")

echo "Dataset bounds:"
echo "  X: $MIN_X to $MAX_X"
echo "  Y: $MIN_Y to $MAX_Y"

# Calculate dimensions
X_RANGE=$(echo "$MAX_X - $MIN_X" | bc -l)
Y_RANGE=$(echo "$MAX_Y - $MIN_Y" | bc -l)

echo "  Area: ${X_RANGE}m x ${Y_RANGE}m"
echo ""

# Create 5 chunks along the longer dimension
if (( $(echo "$Y_RANGE > $X_RANGE" | bc -l) )); then
    echo "Splitting along Y-axis (north-south route)"
    GRID_X=1
    GRID_Y=5
else
    echo "Splitting along X-axis (east-west route)"
    GRID_X=5
    GRID_Y=1
fi

CELL_WIDTH=$(echo "$X_RANGE / $GRID_X" | bc -l)
CELL_HEIGHT=$(echo "$Y_RANGE / $GRID_Y" | bc -l)

echo "Grid: ${GRID_X}x${GRID_Y} chunks"
echo "Cell size: ${CELL_WIDTH}m x ${CELL_HEIGHT}m"
echo ""

echo "Creating spatial chunks..."

chunk_count=0
successful_chunks=0

for ((x=0; x<GRID_X; x++)); do
    for ((y=0; y<GRID_Y; y++)); do
        ((chunk_count++))

        # Calculate cell bounds
        CELL_MIN_X=$(echo "$MIN_X + $x * $CELL_WIDTH" | bc -l)
        CELL_MAX_X=$(echo "$MIN_X + ($x + 1) * $CELL_WIDTH" | bc -l)
        CELL_MIN_Y=$(echo "$MIN_Y + $y * $CELL_HEIGHT" | bc -l)
        CELL_MAX_Y=$(echo "$MIN_Y + ($y + 1) * $CELL_HEIGHT" | bc -l)

        CHUNK_NAME="spatial_segment_${chunk_count}"
        OUTPUT_CHUNK="$OUTPUT_DIR/chunks/${CHUNK_NAME}.laz"

        echo "[$chunk_count/5] Creating: $CHUNK_NAME"
        echo "  Bounds: X(${CELL_MIN_X}, ${CELL_MAX_X}) Y(${CELL_MIN_Y}, ${CELL_MAX_Y})"

        # Use pdal translate with bounds - simpler approach
        BOUNDS_STR="([$CELL_MIN_X,$CELL_MAX_X],[$CELL_MIN_Y,$CELL_MAX_Y])"

        # Try the translate command
        if pdal translate "$INPUT_FILE" "$OUTPUT_CHUNK" \
           --writers.las.compression=true \
           --json='[{"type":"readers.las","filename":"'$INPUT_FILE'"},{"type":"filters.crop","bounds":"'$BOUNDS_STR'"},{"type":"writers.las","filename":"'$OUTPUT_CHUNK'","compression":"laszip"}]' 2>/dev/null; then

            if [[ -f "$OUTPUT_CHUNK" ]]; then
                CHUNK_SIZE=$(stat -c%s "$OUTPUT_CHUNK")

                if [[ $CHUNK_SIZE -gt 1000 ]]; then
                    CHUNK_SIZE_MB=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')
                    echo "  ✓ Success: $CHUNK_SIZE_MB"
                    ((successful_chunks++))
                else
                    echo "  ⚠ Empty area (no points)"
                    rm -f "$OUTPUT_CHUNK"
                fi
            else
                echo "  ✗ Failed: No output file"
            fi
        else
            echo "  ✗ Failed: PDAL error"
            echo "    Trying fallback method..."

            # Fallback: Use pipeline file approach
            PIPELINE_FILE="/tmp/crop_${chunk_count}.json"
            cat > "$PIPELINE_FILE" << EOF
[
    {
        "type": "readers.las",
        "filename": "$INPUT_FILE"
    },
    {
        "type": "filters.crop",
        "bounds": "$BOUNDS_STR"
    },
    {
        "type": "writers.las",
        "filename": "$OUTPUT_CHUNK",
        "compression": "laszip"
    }
]
EOF

            if pdal pipeline "$PIPELINE_FILE" 2>/dev/null; then
                if [[ -f "$OUTPUT_CHUNK" ]]; then
                    CHUNK_SIZE=$(stat -c%s "$OUTPUT_CHUNK")
                    if [[ $CHUNK_SIZE -gt 1000 ]]; then
                        CHUNK_SIZE_MB=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')
                        echo "    ✓ Fallback success: $CHUNK_SIZE_MB"
                        ((successful_chunks++))
                    else
                        echo "    ⚠ Fallback: Empty area"
                        rm -f "$OUTPUT_CHUNK"
                    fi
                else
                    echo "    ✗ Fallback failed"
                fi
            else
                echo "    ✗ Fallback failed"
            fi

            rm -f "$PIPELINE_FILE"
        fi

        echo ""
    done
done

# Results
echo "=== SPATIAL CHUNKING RESULTS ==="
echo "Attempted chunks: $chunk_count"
echo "Successful chunks: $successful_chunks"
echo ""

if [[ $successful_chunks -gt 0 ]]; then
    echo "Created spatial chunks:"
    total_points=0

    for chunk_file in "$OUTPUT_DIR/chunks"/*.laz; do
        if [[ -f "$chunk_file" ]]; then
            chunk_name=$(basename "$chunk_file" .laz)
            chunk_size=$(ls -lh "$chunk_file" | awk '{print $5}')

            # Get point count
            point_count=$(pdal info "$chunk_file" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print('unknown')
" || echo "unknown")

            if [[ "$point_count" != "unknown" ]]; then
                total_points=$((total_points + point_count))
            fi

            echo "  $chunk_name: $chunk_size ($point_count points)"
        fi
    done

    echo ""
    echo "Total points in spatial chunks: $total_points"
    echo "Original dataset: 50,000,000 points"

    if [[ $total_points -gt 0 ]]; then
        coverage=$(echo "scale=1; $total_points * 100 / 50000000" | bc -l)
        echo "Coverage: ${coverage}%"
    fi

    # Create metadata
    cat > "$OUTPUT_DIR/job_metadata.json" << EOF
{
  "job_info": {
    "created_at": "$(date -Iseconds)",
    "input_file": "$INPUT_FILE",
    "stage_completed": "stage1_spatial_chunking"
  },
  "input_data": {
    "total_points": 50000000,
    "file_size": "319M",
    "source": "berkane mobile mapping"
  },
  "spatial_chunking": {
    "method": "bounds_based_cropping",
    "bounds": {
      "min_x": $MIN_X,
      "min_y": $MIN_Y,
      "max_x": $MAX_X,
      "max_y": $MAX_Y
    },
    "grid": {
      "grid_x": $GRID_X,
      "grid_y": $GRID_Y,
      "cell_width": $CELL_WIDTH,
      "cell_height": $CELL_HEIGHT
    },
    "results": {
      "successful_chunks": $successful_chunks,
      "total_points_captured": $total_points
    }
  }
}
EOF

    echo ""
    echo "✅ SUCCESS! Created $successful_chunks spatially coherent chunks"
    echo "📁 Output: $OUTPUT_DIR/chunks/"
    echo "📄 Metadata: $OUTPUT_DIR/job_metadata.json"
    echo ""
    echo "🔄 NEXT: Run Stage 2"
    echo "   ./clustering_production/scripts/stage2_extract_classes.sh $OUTPUT_DIR"

else
    echo "❌ No spatial chunks created"
    echo "The dataset may be too concentrated or there may be PDAL issues"
    echo ""
    echo "🔄 FALLBACK: Use sequential chunking"
    echo "   ./stage1_simple.sh"
fi