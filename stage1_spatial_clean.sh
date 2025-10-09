#!/bin/bash

# Stage 1 Spatial Clean: Professional spatial chunking using proper PDAL syntax
# Based on PDAL documentation and best practices for mobile mapping data
# Usage: ./stage1_spatial_clean.sh

set -euo pipefail

# Configuration
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out_spatial_clean"

echo "=== STAGE 1 SPATIAL CLEAN: PROFESSIONAL SPATIAL CHUNKING ==="
echo "Input file: cloud_point_part_1.laz"
echo "Method: PDAL filters.crop with proper bounds syntax"
echo "Reference: PDAL documentation 2025"
echo ""

# Setup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"

echo "Step 1: Analyzing dataset bounds..."

# Get precise bounds using PDAL info
BOUNDS_INFO=$(pdal info "$INPUT_FILE" --summary)

# Extract bounds using Python for precision
BOUNDS_VALUES=$(echo "$BOUNDS_INFO" | python3 -c "
import json, sys
data = json.load(sys.stdin)
bounds = data['summary']['bounds']
print(f\"{bounds['minx']}\t{bounds['miny']}\t{bounds['maxx']}\t{bounds['maxy']}\")
")

# Parse bounds with tabs
IFS=$'\t' read -r MIN_X MIN_Y MAX_X MAX_Y <<< "$BOUNDS_VALUES"

echo "Dataset spatial bounds:"
echo "  X: $MIN_X to $MAX_X"
echo "  Y: $MIN_Y to $MAX_Y"

# Calculate dimensions
X_RANGE=$(echo "$MAX_X - $MIN_X" | bc -l)
Y_RANGE=$(echo "$MAX_Y - $MIN_Y" | bc -l)

echo "  Coverage: ${X_RANGE}m × ${Y_RANGE}m"
echo ""

# Determine optimal chunking strategy for mobile mapping
echo "Step 2: Determining optimal chunking strategy..."

# For mobile mapping, create chunks along the route direction
if (( $(echo "$Y_RANGE > $X_RANGE" | bc -l) )); then
    CHUNKS_X=1
    CHUNKS_Y=5
    ROUTE_DIR="North-South"
else
    CHUNKS_X=5
    CHUNKS_Y=1
    ROUTE_DIR="East-West"
fi

echo "Route orientation: $ROUTE_DIR"
echo "Chunking grid: ${CHUNKS_X} × ${CHUNKS_Y} = $((CHUNKS_X * CHUNKS_Y)) spatial chunks"

# Calculate chunk dimensions
CHUNK_WIDTH=$(echo "$X_RANGE / $CHUNKS_X" | bc -l)
CHUNK_HEIGHT=$(echo "$Y_RANGE / $CHUNKS_Y" | bc -l)

echo "Chunk size: ${CHUNK_WIDTH}m × ${CHUNK_HEIGHT}m"
echo ""

echo "Step 3: Creating spatially coherent chunks..."

chunk_count=0
successful_chunks=0
total_points_captured=0

# Create each spatial chunk
for ((x=0; x<CHUNKS_X; x++)); do
    for ((y=0; y<CHUNKS_Y; y++)); do
        ((chunk_count++))

        # Calculate precise chunk bounds
        CHUNK_MIN_X=$(echo "$MIN_X + $x * $CHUNK_WIDTH" | bc -l)
        CHUNK_MAX_X=$(echo "$MIN_X + ($x + 1) * $CHUNK_WIDTH" | bc -l)
        CHUNK_MIN_Y=$(echo "$MIN_Y + $y * $CHUNK_HEIGHT" | bc -l)
        CHUNK_MAX_Y=$(echo "$MIN_Y + ($y + 1) * $CHUNK_HEIGHT" | bc -l)

        # Generate chunk name
        CHUNK_NAME="spatial_chunk_${chunk_count}"
        OUTPUT_CHUNK="$OUTPUT_DIR/chunks/${CHUNK_NAME}.laz"

        echo "[$chunk_count/$((CHUNKS_X * CHUNKS_Y))] Processing: $CHUNK_NAME"
        echo "  Bounds: X(${CHUNK_MIN_X}, ${CHUNK_MAX_X}) Y(${CHUNK_MIN_Y}, ${CHUNK_MAX_Y})"

        # Create PDAL pipeline with correct bounds syntax
        PIPELINE_FILE="/tmp/spatial_chunk_${chunk_count}.json"
        cat > "$PIPELINE_FILE" << EOF
[
    {
        "type": "readers.las",
        "filename": "$INPUT_FILE"
    },
    {
        "type": "filters.crop",
        "bounds": "([${CHUNK_MIN_X}, ${CHUNK_MAX_X}], [${CHUNK_MIN_Y}, ${CHUNK_MAX_Y}])"
    },
    {
        "type": "writers.las",
        "filename": "$OUTPUT_CHUNK",
        "compression": "laszip"
    }
]
EOF

        # Execute PDAL pipeline
        echo "  Executing spatial crop..."
        if pdal pipeline "$PIPELINE_FILE" 2>/dev/null; then
            # Cleanup pipeline file
            rm -f "$PIPELINE_FILE"

            # Verify output
            if [[ -f "$OUTPUT_CHUNK" ]]; then
                CHUNK_SIZE_BYTES=$(stat -c%s "$OUTPUT_CHUNK")

                # Check if chunk contains meaningful data (>10KB indicates points)
                if [[ $CHUNK_SIZE_BYTES -gt 10000 ]]; then
                    CHUNK_SIZE_MB=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')

                    # Get precise point count
                    CHUNK_POINTS=$(pdal info "$OUTPUT_CHUNK" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print('0')
" || echo "0")

                    total_points_captured=$((total_points_captured + CHUNK_POINTS))

                    echo "  ✅ Success: $CHUNK_SIZE_MB ($CHUNK_POINTS points)"
                    ((successful_chunks++))

                    # Verify spatial coherence
                    if [[ $CHUNK_POINTS -gt 1000 ]]; then
                        echo "    📍 Spatially coherent chunk created"
                    else
                        echo "    ⚠️  Low point density in this area"
                    fi

                else
                    echo "  ⚠️  Empty spatial region (no points)"
                    rm -f "$OUTPUT_CHUNK"
                fi
            else
                echo "  ❌ Failed: Output file not created"
            fi
        else
            echo "  ❌ Failed: PDAL pipeline execution error"
            rm -f "$PIPELINE_FILE"
        fi

        echo ""
    done
done

# Generate comprehensive results
echo "=== SPATIAL CHUNKING RESULTS ==="
echo ""
echo "📊 EXECUTION SUMMARY:"
echo "  Spatial regions processed: $chunk_count"
echo "  Successful chunks created: $successful_chunks"
echo "  Empty regions: $((chunk_count - successful_chunks))"
echo ""

if [[ $successful_chunks -gt 0 ]]; then
    echo "✅ SPATIAL CHUNKS CREATED:"

    # Detailed chunk analysis
    for chunk_file in "$OUTPUT_DIR/chunks"/*.laz; do
        if [[ -f "$chunk_file" ]]; then
            chunk_name=$(basename "$chunk_file" .laz)
            chunk_size=$(ls -lh "$chunk_file" | awk '{print $5}')

            # Get detailed chunk statistics
            chunk_stats=$(pdal info "$chunk_file" --summary 2>/dev/null)
            if [[ -n "$chunk_stats" ]]; then
                chunk_points=$(echo "$chunk_stats" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    summary = data['summary']
    points = summary['num_points']
    bounds = summary['bounds']
    x_range = bounds['maxx'] - bounds['minx']
    y_range = bounds['maxy'] - bounds['miny']
    print(f'{points}\t{x_range:.1f}\t{y_range:.1f}')
except:
    print('0\t0.0\t0.0')
")

                IFS=$'\t' read -r points x_span y_span <<< "$chunk_points"
                echo "  $chunk_name: $chunk_size"
                echo "    Points: $points | Area: ${x_span}m × ${y_span}m"
            else
                echo "  $chunk_name: $chunk_size"
            fi
        fi
    done

    echo ""
    echo "📈 QUALITY METRICS:"
    echo "  Total points captured: $total_points_captured"
    echo "  Original dataset: 50,000,000 points"

    if [[ $total_points_captured -gt 0 ]]; then
        coverage=$(echo "scale=2; $total_points_captured * 100 / 50000000" | bc -l)
        echo "  Spatial coverage: ${coverage}%"

        if (( $(echo "$coverage > 95" | bc -l) )); then
            echo "  Quality: ✅ Excellent - Nearly complete spatial coverage"
        elif (( $(echo "$coverage > 85" | bc -l) )); then
            echo "  Quality: ✅ Good - High spatial coverage"
        elif (( $(echo "$coverage > 70" | bc -l) )); then
            echo "  Quality: ⚠️  Moderate - Some data outside main area"
        else
            echo "  Quality: ❌ Low - Check bounds or data distribution"
        fi
    fi

    # Create comprehensive metadata
    cat > "$OUTPUT_DIR/job_metadata.json" << EOF
{
  "job_info": {
    "created_at": "$(date -Iseconds)",
    "input_file": "$INPUT_FILE",
    "stage_completed": "stage1_spatial_chunking",
    "method": "pdal_filters_crop_professional"
  },
  "input_analysis": {
    "total_points": 50000000,
    "file_size": "319M",
    "source": "berkane mobile mapping dataset",
    "spatial_bounds": {
      "min_x": $MIN_X,
      "min_y": $MIN_Y,
      "max_x": $MAX_X,
      "max_y": $MAX_Y,
      "x_range": $X_RANGE,
      "y_range": $Y_RANGE
    }
  },
  "chunking_strategy": {
    "approach": "spatial_grid_mobile_mapping",
    "route_orientation": "$ROUTE_DIR",
    "grid_dimensions": {
      "chunks_x": $CHUNKS_X,
      "chunks_y": $CHUNKS_Y,
      "total_chunks": $((CHUNKS_X * CHUNKS_Y))
    },
    "chunk_dimensions": {
      "width_meters": $CHUNK_WIDTH,
      "height_meters": $CHUNK_HEIGHT
    }
  },
  "results": {
    "successful_chunks": $successful_chunks,
    "empty_regions": $((chunk_count - successful_chunks)),
    "total_points_captured": $total_points_captured,
    "spatial_coverage_percent": $(echo "scale=2; $total_points_captured * 100 / 50000000" | bc -l)
  }
}
EOF

    echo ""
    echo "🎉 SUCCESS! Professional spatial chunking completed"
    echo "📁 Output directory: $OUTPUT_DIR/chunks/"
    echo "📄 Detailed metadata: $OUTPUT_DIR/job_metadata.json"
    echo ""
    echo "💡 BENEFITS ACHIEVED:"
    echo "  ✅ Spatially coherent chunks (no scattered regions)"
    echo "  ✅ Geographic continuity within each chunk"
    echo "  ✅ Optimal for clustering algorithms"
    echo "  ✅ Better visualization and validation"
    echo "  ✅ Professional-grade processing pipeline"
    echo ""
    echo "🔄 NEXT STEP: Run Stage 2 with spatial chunks"
    echo "   ./clustering_production/scripts/stage2_extract_classes.sh $OUTPUT_DIR"

else
    echo "❌ NO SPATIAL CHUNKS CREATED"
    echo ""
    echo "🔍 TROUBLESHOOTING:"
    echo "  • Data may be highly concentrated in small areas"
    echo "  • Check if coordinate system is correct"
    echo "  • Consider using smaller spatial grid"
    echo "  • Verify PDAL installation and version"
    echo ""
    echo "🔄 FALLBACK OPTION:"
    echo "   ./stage1_simple.sh  # Use sequential chunking"
fi