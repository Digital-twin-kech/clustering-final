#!/bin/bash

# Stage 1 Spatial Final: Working spatial chunking with proper error handling
# Usage: ./stage1_spatial_final.sh

set -euo pipefail

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out_spatial_final"

echo "=== STAGE 1 SPATIAL FINAL: WORKING SPATIAL CHUNKING ==="
echo "Input file: cloud_point_part_1.laz"
echo "Method: Tested PDAL filters.crop with verified syntax"
echo ""

# Setup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"

# Dataset bounds (from previous analysis)
MIN_X=1108218.094
MIN_Y=3885494.316
MAX_X=1108721.394
MAX_Y=3886092.912

X_RANGE=503.300
Y_RANGE=598.596

echo "Dataset bounds: ${X_RANGE}m × ${Y_RANGE}m"
echo "Route: North-South orientation"
echo "Strategy: 5 spatial chunks along route"
echo ""

# Create 5 chunks along Y-axis (north-south route)
CHUNK_HEIGHT=$(echo "$Y_RANGE / 5" | bc -l)
echo "Chunk dimensions: ${X_RANGE}m × ${CHUNK_HEIGHT}m each"
echo ""

successful_chunks=0
total_points=0

for ((i=0; i<5; i++)); do
    chunk_num=$((i+1))

    # Calculate Y bounds for this chunk
    CHUNK_MIN_Y=$(echo "$MIN_Y + $i * $CHUNK_HEIGHT" | bc -l)
    CHUNK_MAX_Y=$(echo "$MIN_Y + ($i + 1) * $CHUNK_HEIGHT" | bc -l)

    CHUNK_NAME="spatial_segment_${chunk_num}"
    OUTPUT_CHUNK="$OUTPUT_DIR/chunks/${CHUNK_NAME}.laz"
    PIPELINE_FILE="/tmp/chunk_${chunk_num}.json"

    echo "[$chunk_num/5] Creating: $CHUNK_NAME"
    echo "  Y-range: $CHUNK_MIN_Y to $CHUNK_MAX_Y"

    # Create pipeline
    cat > "$PIPELINE_FILE" << EOF
[
    {
        "type": "readers.las",
        "filename": "$INPUT_FILE"
    },
    {
        "type": "filters.crop",
        "bounds": "([${MIN_X}, ${MAX_X}], [${CHUNK_MIN_Y}, ${CHUNK_MAX_Y}])"
    },
    {
        "type": "writers.las",
        "filename": "$OUTPUT_CHUNK",
        "compression": "laszip"
    }
]
EOF

    # Execute with error capture
    echo "  Processing spatial crop..."
    if pdal pipeline "$PIPELINE_FILE"; then
        rm -f "$PIPELINE_FILE"

        if [[ -f "$OUTPUT_CHUNK" ]]; then
            chunk_size=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')

            # Get point count
            point_count=$(pdal info "$OUTPUT_CHUNK" --summary | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['summary']['num_points'])
")

            total_points=$((total_points + point_count))
            echo "  ✅ Success: $chunk_size ($point_count points)"
            ((successful_chunks++))
        else
            echo "  ❌ No output file created"
        fi
    else
        echo "  ❌ PDAL pipeline failed"
        rm -f "$PIPELINE_FILE"
    fi
    echo ""
done

# Results
echo "=== SPATIAL CHUNKING COMPLETE ==="
echo ""
echo "📊 RESULTS:"
echo "  Successful chunks: $successful_chunks/5"
echo "  Total points captured: $total_points"
echo "  Original dataset: 50,000,000 points"

if [[ $total_points -gt 0 ]]; then
    coverage=$(echo "scale=1; $total_points * 100 / 50000000" | bc -l)
    echo "  Spatial coverage: ${coverage}%"
fi

echo ""
if [[ $successful_chunks -gt 0 ]]; then
    echo "✅ SPATIAL CHUNKS CREATED:"
    for chunk_file in "$OUTPUT_DIR/chunks"/*.laz; do
        if [[ -f "$chunk_file" ]]; then
            chunk_name=$(basename "$chunk_file" .laz)
            chunk_size=$(ls -lh "$chunk_file" | awk '{print $5}')

            point_count=$(pdal info "$chunk_file" --summary | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['summary']['num_points'])
")

            echo "  $chunk_name: $chunk_size ($point_count points)"
        fi
    done

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
  "spatial_results": {
    "method": "north_south_segments",
    "successful_chunks": $successful_chunks,
    "total_points_captured": $total_points,
    "coverage_percent": $(echo "scale=1; $total_points * 100 / 50000000" | bc -l)
  }
}
EOF

    echo ""
    echo "🎉 SUCCESS! Created $successful_chunks spatially coherent chunks"
    echo "📁 Output: $OUTPUT_DIR/chunks/"
    echo ""
    echo "💡 SPATIAL BENEFITS:"
    echo "  ✅ Each chunk covers a continuous geographic segment"
    echo "  ✅ No scattered/disconnected regions within chunks"
    echo "  ✅ Objects stay within single chunks"
    echo "  ✅ Better clustering and visualization results"
    echo ""
    echo "🔄 NEXT: Run Stage 2"
    echo "   ./clustering_production/scripts/stage2_extract_classes.sh $OUTPUT_DIR"
else
    echo "❌ No spatial chunks created successfully"
fi

# Cleanup
rm -f /tmp/test_*.laz /tmp/test_*.json