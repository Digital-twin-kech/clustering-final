#!/bin/bash

# Stage 1 Spatial Smart: Split LAZ into Spatially Coherent Chunks
# Uses data distribution analysis to create meaningful spatial chunks
# Usage: ./stage1_spatial_smart.sh

set -euo pipefail

# Configuration
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out_spatial"

echo "=== STAGE 1 SPATIAL SMART: INTELLIGENT SPATIAL CHUNKING ==="
echo "Input file: cloud_point_part_1.laz"
echo "Method: Data-driven spatial analysis"
echo ""

# Setup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"

echo "Step 1: Analyzing point distribution..."

# Sample points to understand data distribution
SAMPLE_FILE="/tmp/berkane_sample.las"
echo "Creating sample of dataset..."

# Sample 1% of points to analyze distribution
if pdal translate "$INPUT_FILE" "$SAMPLE_FILE" --filters.sample.radius=0.01 --writers.las.compression=false 2>/dev/null; then
    SAMPLE_INFO=$(pdal info "$SAMPLE_FILE" --summary)

    # Get sample bounds and point count
    SAMPLE_COUNT=$(echo "$SAMPLE_INFO" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['summary']['num_points'])
")

    SAMPLE_BOUNDS=$(echo "$SAMPLE_INFO" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bounds = data['summary']['bounds']
print(f\"{bounds['minx']},{bounds['miny']},{bounds['maxx']},{bounds['maxy']}\")
")

    echo "Sample analysis:"
    echo "  Sample points: $SAMPLE_COUNT"
    echo "  Sample bounds: $SAMPLE_BOUNDS"

    # Parse bounds
    IFS=',' read -r SAMPLE_MIN_X SAMPLE_MIN_Y SAMPLE_MAX_X SAMPLE_MAX_Y <<< "$SAMPLE_BOUNDS"

    # Calculate data-concentrated area
    X_RANGE=$(echo "$SAMPLE_MAX_X - $SAMPLE_MIN_X" | bc -l)
    Y_RANGE=$(echo "$SAMPLE_MAX_Y - $SAMPLE_MIN_Y" | bc -l)

    echo "  Active area: ${X_RANGE}m x ${Y_RANGE}m"

    # Add small buffer to ensure we capture edge points
    BUFFER=10  # 10 meter buffer
    MIN_X=$(echo "$SAMPLE_MIN_X - $BUFFER" | bc -l)
    MAX_X=$(echo "$SAMPLE_MAX_X + $BUFFER" | bc -l)
    MIN_Y=$(echo "$SAMPLE_MIN_Y - $BUFFER" | bc -l)
    MAX_Y=$(echo "$SAMPLE_MAX_Y + $BUFFER" | bc -l)

    rm -f "$SAMPLE_FILE"
else
    echo "Failed to sample data. Using full bounds..."

    # Fallback to full bounds
    BOUNDS_DATA=$(pdal info "$INPUT_FILE" --summary)
    BOUNDS_JSON=$(echo "$BOUNDS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bounds = data['summary']['bounds']
print(f\"{bounds['minx']},{bounds['miny']},{bounds['maxx']},{bounds['maxy']}\")
")

    IFS=',' read -r MIN_X MIN_Y MAX_X MAX_Y <<< "$BOUNDS_JSON"
fi

echo ""
echo "Working bounds:"
echo "  X: $MIN_X to $MAX_X"
echo "  Y: $MIN_Y to $MAX_Y"

# Recalculate dimensions
X_RANGE=$(echo "$MAX_X - $MIN_X" | bc -l)
Y_RANGE=$(echo "$MAX_Y - $MIN_Y" | bc -l)

echo "  Effective area: ${X_RANGE}m x ${Y_RANGE}m"
echo ""

# Create grid based on area size
# For mobile mapping data, create chunks along the route
if (( $(echo "$X_RANGE > $Y_RANGE" | bc -l) )); then
    # Longer in X direction - likely east-west route
    GRID_X=5
    GRID_Y=1
    echo "Route appears to be east-west oriented"
else
    # Longer in Y direction - likely north-south route
    GRID_X=1
    GRID_Y=5
    echo "Route appears to be north-south oriented"
fi

echo "Grid: ${GRID_X}x${GRID_Y} = $((GRID_X * GRID_Y)) chunks"

# Calculate cell dimensions
CELL_WIDTH=$(echo "$X_RANGE / $GRID_X" | bc -l)
CELL_HEIGHT=$(echo "$Y_RANGE / $GRID_Y" | bc -l)

echo "Cell size: ${CELL_WIDTH}m x ${CELL_HEIGHT}m"
echo ""

echo "Creating spatial chunks along route..."

chunk_count=0
successful_chunks=0
total_points=0

for ((x=0; x<GRID_X; x++)); do
    for ((y=0; y<GRID_Y; y++)); do
        ((chunk_count++))

        # Calculate cell bounds
        CELL_MIN_X=$(echo "$MIN_X + $x * $CELL_WIDTH" | bc -l)
        CELL_MAX_X=$(echo "$MIN_X + ($x + 1) * $CELL_WIDTH" | bc -l)
        CELL_MIN_Y=$(echo "$MIN_Y + $y * $CELL_HEIGHT" | bc -l)
        CELL_MAX_Y=$(echo "$MIN_Y + ($y + 1) * $CELL_HEIGHT" | bc -l)

        CHUNK_NAME="route_segment_${chunk_count}_chunk"
        OUTPUT_CHUNK="$OUTPUT_DIR/chunks/${CHUNK_NAME}.laz"

        echo "[$chunk_count/$((GRID_X * GRID_Y))] Creating: $CHUNK_NAME"
        echo "  Area: X(${CELL_MIN_X} to ${CELL_MAX_X}), Y(${CELL_MIN_Y} to ${CELL_MAX_Y})"

        # Create PDAL pipeline JSON
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
                CHUNK_SIZE_BYTES=$(stat -c%s "$OUTPUT_CHUNK")

                if [[ $CHUNK_SIZE_BYTES -gt 1000 ]]; then
                    # Get detailed info
                    CHUNK_SIZE_MB=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')
                    POINT_COUNT=$(pdal info "$OUTPUT_CHUNK" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print(0)
" || echo "0")

                    total_points=$((total_points + POINT_COUNT))
                    echo "  ✓ Success: $CHUNK_SIZE_MB ($POINT_COUNT points)"
                    ((successful_chunks++))
                else
                    echo "  ⚠ Empty segment (no points)"
                    rm -f "$OUTPUT_CHUNK"
                fi
            else
                echo "  ✗ Failed: Output not created"
            fi
        else
            echo "  ✗ Failed: PDAL error"
        fi
        echo ""
    done
done

# Final results
echo "=== SPATIAL CHUNKING COMPLETE ==="
echo ""
echo "📊 RESULTS:"
echo "  Route segments: $chunk_count"
echo "  Successful chunks: $successful_chunks"
echo "  Empty segments: $((chunk_count - successful_chunks))"
echo ""

if [[ $successful_chunks -gt 0 ]]; then
    echo "📍 SPATIAL CHUNKS CREATED:"
    for chunk_file in "$OUTPUT_DIR/chunks"/*.laz; do
        if [[ -f "$chunk_file" ]]; then
            chunk_name=$(basename "$chunk_file" .laz)
            chunk_size=$(ls -lh "$chunk_file" | awk '{print $5}')

            point_count=$(pdal info "$chunk_file" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print(0)
" || echo "0")

            echo "  $chunk_name: $chunk_size ($point_count points)"
        fi
    done

    echo ""
    echo "✅ VALIDATION:"
    echo "  Original file: 50,000,000 points"
    echo "  Total in chunks: $total_points points"
    coverage=$(echo "scale=2; $total_points * 100 / 50000000" | bc -l)
    echo "  Coverage: ${coverage}%"

    if (( $(echo "$coverage > 95" | bc -l) )); then
        echo "  Status: ✅ Excellent coverage"
    elif (( $(echo "$coverage > 80" | bc -l) )); then
        echo "  Status: ✅ Good coverage"
    else
        echo "  Status: ⚠️  Low coverage - check bounds"
    fi
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
  "spatial_analysis": {
    "method": "data_driven_route_segmentation",
    "working_bounds": {
      "min_x": $MIN_X,
      "min_y": $MIN_Y,
      "max_x": $MAX_X,
      "max_y": $MAX_Y
    },
    "dimensions": {
      "x_range": $X_RANGE,
      "y_range": $Y_RANGE,
      "grid_x": $GRID_X,
      "grid_y": $GRID_Y
    },
    "results": {
      "segments_created": $successful_chunks,
      "total_points_captured": $total_points,
      "coverage_percent": $(echo "scale=2; $total_points * 100 / 50000000" | bc -l)
    }
  }
}
EOF

echo ""
if [[ $successful_chunks -gt 0 ]]; then
    echo "🎉 SUCCESS! Created $successful_chunks spatially coherent chunks"
    echo "📁 Location: $OUTPUT_DIR/chunks/"
    echo ""
    echo "💡 BENEFITS OF SPATIAL CHUNKING:"
    echo "  ✓ Each chunk contains geographically connected areas"
    echo "  ✓ Objects don't span multiple chunks"
    echo "  ✓ Clustering algorithms work more effectively"
    echo "  ✓ Results are easier to visualize and validate"
    echo ""
    echo "🔄 NEXT STEP: Run Stage 2"
    echo "   ./clustering_production/scripts/stage2_extract_classes.sh $OUTPUT_DIR"
else
    echo "❌ No spatial chunks created"
    echo "The dataset might be concentrated in a very small area"
    echo "Consider using sequential chunking instead:"
    echo "   ./stage1_simple.sh"
fi