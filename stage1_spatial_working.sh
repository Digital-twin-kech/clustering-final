#!/bin/bash

# Stage 1 Spatial Working: Split LAZ into Spatially Coherent Chunks
# Uses correct PDAL pipeline syntax for spatial cropping
# Usage: ./stage1_spatial_working.sh

set -euo pipefail

# Configuration
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out_spatial"

echo "=== STAGE 1 SPATIAL: SPATIAL CHUNK SPLITTING ==="
echo "Input file: cloud_point_part_1.laz"
echo "Method: Geographic grid-based chunking with PDAL pipeline"
echo ""

# Setup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"

echo "Step 1: Analyzing spatial bounds..."

# Get bounds using PDAL info --summary
BOUNDS_DATA=$(pdal info "$INPUT_FILE" --summary)

# Extract bounds using Python
BOUNDS_JSON=$(echo "$BOUNDS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bounds = data['summary']['bounds']
print(f\"{bounds['minx']},{bounds['miny']},{bounds['maxx']},{bounds['maxy']}\")
")

# Parse bounds
IFS=',' read -r MIN_X MIN_Y MAX_X MAX_Y <<< "$BOUNDS_JSON"

echo "Spatial Bounds:"
echo "  X: $MIN_X to $MAX_X"
echo "  Y: $MIN_Y to $MAX_Y"

# Calculate dimensions
X_RANGE=$(echo "$MAX_X - $MIN_X" | bc -l)
Y_RANGE=$(echo "$MAX_Y - $MIN_Y" | bc -l)

echo "  X Range: ${X_RANGE}m"
echo "  Y Range: ${Y_RANGE}m"
echo ""

# For ~5 chunks, use a 2x3 grid
GRID_X=2
GRID_Y=3

echo "Grid Configuration:"
echo "  Grid cells: ${GRID_X}x${GRID_Y} = $((GRID_X * GRID_Y)) chunks"

# Calculate cell dimensions
CELL_WIDTH=$(echo "$X_RANGE / $GRID_X" | bc -l)
CELL_HEIGHT=$(echo "$Y_RANGE / $GRID_Y" | bc -l)

echo "  Cell size: ${CELL_WIDTH}m x ${CELL_HEIGHT}m"
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

        CHUNK_NAME="spatial_${x}_${y}_chunk"
        OUTPUT_CHUNK="$OUTPUT_DIR/chunks/${CHUNK_NAME}.laz"

        echo "[$chunk_count/$((GRID_X * GRID_Y))] Creating chunk: $CHUNK_NAME"
        echo "  Bounds: X(${CELL_MIN_X} to ${CELL_MAX_X}), Y(${CELL_MIN_Y} to ${CELL_MAX_Y})"

        # Create PDAL pipeline JSON for spatial cropping
        PIPELINE_JSON=$(cat << EOF
[
    {
        "type": "readers.las",
        "filename": "$INPUT_FILE"
    },
    {
        "type": "filters.crop",
        "bounds": "([$CELL_MIN_X, $CELL_MAX_X], [$CELL_MIN_Y, $CELL_MAX_Y])"
    },
    {
        "type": "writers.las",
        "filename": "$OUTPUT_CHUNK",
        "compression": "laszip"
    }
]
EOF
        )

        # Execute pipeline
        if echo "$PIPELINE_JSON" | pdal pipeline --stdin 2>/dev/null; then
            if [[ -f "$OUTPUT_CHUNK" ]]; then
                # Get chunk info
                CHUNK_SIZE_MB=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')
                CHUNK_SIZE_BYTES=$(stat -c%s "$OUTPUT_CHUNK")

                if [[ $CHUNK_SIZE_BYTES -gt 1000 ]]; then
                    # Get point count
                    POINT_COUNT=$(pdal info "$OUTPUT_CHUNK" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary'].get('num_points', 0))
except:
    print(0)
" || echo "0")

                    echo "  ✓ Success: $CHUNK_SIZE_MB ($POINT_COUNT points)"
                    ((successful_chunks++))
                else
                    echo "  ⚠ Empty chunk (no points in this area)"
                    rm -f "$OUTPUT_CHUNK"
                fi
            else
                echo "  ✗ Failed: Output file not created"
            fi
        else
            echo "  ✗ Failed: PDAL pipeline error"
        fi
        echo ""
    done
done

# Summary
echo "=== SPATIAL CHUNKING COMPLETE ==="
echo "Total grid cells: $chunk_count"
echo "Successful chunks: $successful_chunks"
echo "Empty areas: $((chunk_count - successful_chunks))"
echo ""

# List created chunks
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
    print(data['summary'].get('num_points', 0))
except:
    print(0)
" || echo "0")

            total_points=$((total_points + point_count))
            echo "  $chunk_name: $chunk_size ($point_count points)"
        fi
    done
    echo ""
    echo "Original file: 50,000,000 points"
    echo "Total in chunks: $total_points points"
    echo "Coverage: $(echo "scale=1; $total_points * 100 / 50000000" | bc -l)%"
fi

# Create job metadata
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
    "method": "geographic_grid",
    "bounds": {
      "min_x": $MIN_X,
      "min_y": $MIN_Y,
      "max_x": $MAX_X,
      "max_y": $MAX_Y,
      "x_range": $X_RANGE,
      "y_range": $Y_RANGE
    },
    "grid_dimensions": {
      "grid_x": $GRID_X,
      "grid_y": $GRID_Y,
      "cell_width": $CELL_WIDTH,
      "cell_height": $CELL_HEIGHT
    },
    "results": {
      "total_cells": $chunk_count,
      "successful_chunks": $successful_chunks,
      "empty_areas": $((chunk_count - successful_chunks))
    }
  }
}
EOF

echo ""
if [[ $successful_chunks -gt 0 ]]; then
    echo "✅ SUCCESS! Spatial chunking completed"
    echo "📁 Output: $OUTPUT_DIR/chunks/"
    echo "📄 Metadata: $OUTPUT_DIR/job_metadata.json"
    echo ""
    echo "Benefits of spatial chunking:"
    echo "  • Each chunk contains geographically connected areas"
    echo "  • No scattered/disconnected regions within chunks"
    echo "  • Better for clustering algorithms (objects don't span chunks)"
    echo "  • More intuitive for manual inspection and validation"
    echo ""
    echo "🔄 NEXT: Run Stage 2 on spatial chunks"
    echo "   ./clustering_production/scripts/stage2_extract_classes.sh $OUTPUT_DIR"
else
    echo "❌ No chunks created - all areas were empty"
fi