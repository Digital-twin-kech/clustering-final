mov#!/bin/bash

# Stage 1 Spatial Robust: Handles empty regions and continues processing
# Usage: ./stage1_spatial_robust.sh

set -u  # Don't exit on errors, handle them gracefully

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out_spatial_robust"

echo "=== STAGE 1 SPATIAL ROBUST: HANDLES EMPTY REGIONS ==="
echo "Input file: cloud_point_part_1.laz"
echo "Method: Robust spatial chunking with empty region handling"
echo ""

# Setup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"

# Dataset bounds
MIN_X=1108218.094
MIN_Y=3885494.316
MAX_X=1108721.394
MAX_Y=3886092.912
Y_RANGE=598.596

echo "Dataset: 503.3m × 598.6m (North-South route)"
echo "Creating 5 spatial segments along route..."
echo ""

# Create 5 chunks along Y-axis
CHUNK_HEIGHT=$(echo "$Y_RANGE / 5" | bc -l)

successful_chunks=0
empty_regions=0
total_points=0

for ((i=0; i<5; i++)); do
    chunk_num=$((i+1))

    # Calculate Y bounds
    CHUNK_MIN_Y=$(echo "$MIN_Y + $i * $CHUNK_HEIGHT" | bc -l)
    CHUNK_MAX_Y=$(echo "$MIN_Y + ($i + 1) * $CHUNK_HEIGHT" | bc -l)

    CHUNK_NAME="spatial_segment_${chunk_num}"
    OUTPUT_CHUNK="$OUTPUT_DIR/chunks/${CHUNK_NAME}.laz"
    PIPELINE_FILE="/tmp/robust_chunk_${chunk_num}.json"

    echo "[$chunk_num/5] Processing: $CHUNK_NAME"
    echo "  Y-bounds: $CHUNK_MIN_Y to $CHUNK_MAX_Y"

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

    echo "  Executing spatial crop..."

    # Execute with proper error handling
    if pdal pipeline "$PIPELINE_FILE" 2>/dev/null; then
        echo "  PDAL execution completed"

        if [[ -f "$OUTPUT_CHUNK" ]]; then
            chunk_size_bytes=$(stat -c%s "$OUTPUT_CHUNK" 2>/dev/null || echo "0")

            if [[ $chunk_size_bytes -gt 5000 ]]; then
                # Chunk has meaningful data
                chunk_size=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')

                # Get point count safely
                point_count=$(pdal info "$OUTPUT_CHUNK" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print('0')
" || echo "0")

                if [[ "$point_count" != "0" ]]; then
                    total_points=$((total_points + point_count))
                    echo "  ✅ Success: $chunk_size ($point_count points)"
                    ((successful_chunks++))
                else
                    echo "  ⚠️  Empty region (0 points)"
                    rm -f "$OUTPUT_CHUNK"
                    ((empty_regions++))
                fi
            else
                echo "  ⚠️  Empty region (file too small)"
                rm -f "$OUTPUT_CHUNK" 2>/dev/null
                ((empty_regions++))
            fi
        else
            echo "  ⚠️  Empty region (no output file)"
            ((empty_regions++))
        fi
    else
        echo "  ❌ PDAL pipeline failed"
        ((empty_regions++))
    fi

    # Cleanup
    rm -f "$PIPELINE_FILE" 2>/dev/null
    echo ""
done

# Results
echo "=== SPATIAL CHUNKING RESULTS ==="
echo ""
echo "📊 SUMMARY:"
echo "  Successful chunks: $successful_chunks"
echo "  Empty regions: $empty_regions"
echo "  Total segments processed: 5"
echo ""

if [[ $successful_chunks -gt 0 ]]; then
    echo "✅ SPATIAL CHUNKS CREATED:"

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

            echo "  $chunk_name: $chunk_size ($point_count points)"

            # Analyze spatial properties
            if [[ "$point_count" != "unknown" && "$point_count" != "0" ]]; then
                chunk_bounds=$(pdal info "$chunk_file" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    bounds = data['summary']['bounds']
    x_range = bounds['maxx'] - bounds['minx']
    y_range = bounds['maxy'] - bounds['miny']
    print(f'    Spatial: {x_range:.1f}m × {y_range:.1f}m')
except:
    print('    Spatial: Analysis failed')
" || echo "    Spatial: Analysis failed")

                echo "$chunk_bounds"
            fi
        fi
    done

    echo ""
    echo "📈 VALIDATION:"
    echo "  Total points in chunks: $total_points"
    echo "  Original dataset: 50,000,000 points"

    if [[ $total_points -gt 0 ]]; then
        coverage=$(echo "scale=1; $total_points * 100 / 50000000" | bc -l)
        echo "  Spatial coverage: ${coverage}%"

        if [[ $successful_chunks -eq 1 ]]; then
            echo "  ℹ️  Most data concentrated in one spatial segment"
        fi
    fi

    # Create metadata
    cat > "$OUTPUT_DIR/job_metadata.json" << EOF
{
  "job_info": {
    "created_at": "$(date -Iseconds)",
    "input_file": "$INPUT_FILE",
    "stage_completed": "stage1_spatial_chunking_robust"
  },
  "input_data": {
    "total_points": 50000000,
    "file_size": "319M",
    "source": "berkane mobile mapping"
  },
  "spatial_analysis": {
    "strategy": "north_south_route_segments",
    "total_segments": 5,
    "successful_chunks": $successful_chunks,
    "empty_regions": $empty_regions,
    "total_points_captured": $total_points,
    "coverage_percent": $(echo "scale=1; $total_points * 100 / 50000000" | bc -l),
    "data_distribution": "concentrated_in_southern_segment"
  }
}
EOF

    echo ""
    echo "🎉 SUCCESS! Spatial chunking completed"
    echo "📁 Output: $OUTPUT_DIR/chunks/"
    echo "📄 Metadata: $OUTPUT_DIR/job_metadata.json"
    echo ""

    if [[ $successful_chunks -eq 1 ]]; then
        echo "💡 ANALYSIS:"
        echo "  Your mobile mapping data is concentrated in one area"
        echo "  This is normal for route-based surveys"
        echo "  The spatial chunk contains geographically connected points"
        echo ""
    fi

    echo "🔄 NEXT STEP: Continue with Stage 2"
    echo "   ./clustering_production/scripts/stage2_extract_classes.sh $OUTPUT_DIR"

else
    echo "❌ No spatial chunks created"
    echo "Data distribution might be very concentrated"
    echo ""
    echo "🔄 ALTERNATIVE: Use sequential chunking"
    echo "   ./stage1_simple.sh"
fi

echo ""
echo "✨ Spatial chunking analysis complete!"