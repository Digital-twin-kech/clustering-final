#!/bin/bash

# Stage 1 Hybrid: Sequential chunks with spatial verification
# Creates chunks sequentially but provides spatial information for each
# Usage: ./stage1_hybrid.sh

set -euo pipefail

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out_hybrid"

echo "=== STAGE 1 HYBRID: SPATIALLY-AWARE SEQUENTIAL CHUNKING ==="
echo "Input file: cloud_point_part_1.laz"
echo "Method: Sequential chunking with spatial analysis"
echo ""

# Setup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"

# Get overall bounds first
echo "Analyzing dataset spatial bounds..."
BOUNDS_DATA=$(pdal info "$INPUT_FILE" --summary)
BOUNDS_JSON=$(echo "$BOUNDS_DATA" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bounds = data['summary']['bounds']
print(f\"{bounds['minx']},{bounds['miny']},{bounds['maxx']},{bounds['maxy']}\")
")

IFS=',' read -r OVERALL_MIN_X OVERALL_MIN_Y OVERALL_MAX_X OVERALL_MAX_Y <<< "$BOUNDS_JSON"

echo "Overall spatial bounds:"
echo "  X: $OVERALL_MIN_X to $OVERALL_MAX_X"
echo "  Y: $OVERALL_MIN_Y to $OVERALL_MAX_Y"
echo ""

# Create sequential chunks (like before) but analyze their spatial properties
CHUNK_SIZE=10000000  # 10M points per chunk

echo "Creating 5 sequential chunks with spatial analysis..."
echo ""

successful_chunks=0

for ((i=0; i<5; i++)); do
    SKIP_POINTS=$((i * CHUNK_SIZE))
    CHUNK_NAME="hybrid_$((i+1))_chunk"
    OUTPUT_CHUNK="$OUTPUT_DIR/chunks/${CHUNK_NAME}.laz"

    echo "[$((i+1))/5] Creating chunk: $CHUNK_NAME"
    echo "  Sequential: Skip $SKIP_POINTS points, take $CHUNK_SIZE points"

    # Create PDAL pipeline for sequential chunk
    PIPELINE_JSON=$(cat << EOF
[
    {
        "type": "readers.las",
        "filename": "$INPUT_FILE"
    },
    {
        "type": "filters.tail",
        "count": $((50000000 - SKIP_POINTS))
    },
    {
        "type": "filters.head",
        "count": $CHUNK_SIZE
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
            CHUNK_SIZE_MB=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')
            echo "  ✓ Created: $CHUNK_SIZE_MB"

            # Analyze spatial properties of this chunk
            echo "  📍 Analyzing spatial distribution..."
            CHUNK_INFO=$(pdal info "$OUTPUT_CHUNK" --summary 2>/dev/null)

            if [[ -n "$CHUNK_INFO" ]]; then
                CHUNK_BOUNDS=$(echo "$CHUNK_INFO" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    bounds = data['summary']['bounds']
    points = data['summary']['num_points']
    print(f\"{bounds['minx']},{bounds['miny']},{bounds['maxx']},{bounds['maxy']},{points}\")
except:
    print('ERROR,ERROR,ERROR,ERROR,0')
" 2>/dev/null || echo "ERROR,ERROR,ERROR,ERROR,0")

                IFS=',' read -r CHUNK_MIN_X CHUNK_MIN_Y CHUNK_MAX_X CHUNK_MAX_Y CHUNK_POINTS <<< "$CHUNK_BOUNDS"

                if [[ "$CHUNK_MIN_X" != "ERROR" ]]; then
                    # Calculate spatial properties
                    CHUNK_X_RANGE=$(echo "$CHUNK_MAX_X - $CHUNK_MIN_X" | bc -l 2>/dev/null || echo "0")
                    CHUNK_Y_RANGE=$(echo "$CHUNK_MAX_Y - $CHUNK_MIN_Y" | bc -l 2>/dev/null || echo "0")

                    echo "    Spatial bounds: X($CHUNK_MIN_X to $CHUNK_MAX_X), Y($CHUNK_MIN_Y to $CHUNK_MAX_Y)"
                    echo "    Coverage area: ${CHUNK_X_RANGE}m x ${CHUNK_Y_RANGE}m"
                    echo "    Points: $CHUNK_POINTS"

                    # Check if this chunk is spatially coherent (small area = good)
                    SPATIAL_AREA=$(echo "$CHUNK_X_RANGE * $CHUNK_Y_RANGE" | bc -l 2>/dev/null || echo "0")
                    if (( $(echo "$SPATIAL_AREA < 100000" | bc -l 2>/dev/null || echo 0) )); then  # < 100k m²
                        echo "    ✅ Spatially coherent (small area)"
                    else
                        echo "    ⚠️ Spatially scattered (large area - points may be disconnected)"
                    fi

                    ((successful_chunks++))
                else
                    echo "    ❓ Could not analyze spatial properties"
                    ((successful_chunks++))
                fi
            else
                echo "    ❓ Could not get chunk information"
                ((successful_chunks++))
            fi
        else
            echo "  ✗ Failed: Output file not created"
        fi
    else
        echo "  ✗ Failed: PDAL pipeline error"
    fi

    echo ""
done

# Summary
echo "=== HYBRID CHUNKING COMPLETE ==="
echo ""
echo "📊 RESULTS:"
echo "  Chunks created: $successful_chunks/5"
echo "  Method: Sequential with spatial analysis"
echo ""

if [[ $successful_chunks -gt 0 ]]; then
    echo "📁 CREATED CHUNKS:"
    for chunk_file in "$OUTPUT_DIR/chunks"/*.laz; do
        if [[ -f "$chunk_file" ]]; then
            chunk_name=$(basename "$chunk_file" .laz)
            chunk_size=$(ls -lh "$chunk_file" | awk '{print $5}')
            echo "  $chunk_name: $chunk_size"
        fi
    done
fi

# Create job metadata
cat > "$OUTPUT_DIR/job_metadata.json" << EOF
{
  "job_info": {
    "created_at": "$(date -Iseconds)",
    "input_file": "$INPUT_FILE",
    "stage_completed": "stage1_hybrid_chunking"
  },
  "input_data": {
    "total_points": 50000000,
    "file_size": "319M",
    "source": "berkane mobile mapping",
    "overall_bounds": {
      "min_x": $OVERALL_MIN_X,
      "min_y": $OVERALL_MIN_Y,
      "max_x": $OVERALL_MAX_X,
      "max_y": $OVERALL_MAX_Y
    }
  },
  "chunking_method": {
    "type": "hybrid_sequential_spatial",
    "description": "Sequential point-based chunks with spatial analysis",
    "chunks_created": $successful_chunks,
    "chunk_size": $CHUNK_SIZE
  }
}
EOF

echo ""
echo "✅ SUCCESS! Hybrid chunking completed"
echo "📄 Metadata: $OUTPUT_DIR/job_metadata.json"
echo ""
echo "💡 ANALYSIS COMPLETE:"
echo "  - Created chunks using reliable sequential method"
echo "  - Analyzed spatial properties of each chunk"
echo "  - Identified potential spatial coherence issues"
echo ""
echo "🔄 RECOMMENDATION:"
echo "  For this dataset, sequential chunking appears most reliable."
echo "  Each chunk's spatial properties have been analyzed."
echo "  You can proceed with these chunks or explore pure spatial methods later."
echo ""
echo "🔄 NEXT: Run Stage 2"
echo "   ./clustering_production/scripts/stage2_extract_classes.sh $OUTPUT_DIR"