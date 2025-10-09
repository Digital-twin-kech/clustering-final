#!/bin/bash

# Stage 1 Spatial: Split LAZ into Spatially Coherent Chunks
# Uses geographic bounds to create spatially connected chunks
# Usage: ./stage1_spatial.sh

set -euo pipefail

# Configuration
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out_spatial"

echo "=== STAGE 1 SPATIAL: SPATIAL CHUNK SPLITTING ==="
echo "Input file: cloud_point_part_1.laz"
echo "Method: Geographic grid-based chunking"
echo ""

# Setup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"

echo "Step 1: Analyzing spatial bounds..."

# Get spatial bounds using PDAL info
echo "Getting spatial extent of dataset..."
BOUNDS_INFO=$(pdal info "$INPUT_FILE" --boundary 2>/dev/null || pdal info "$INPUT_FILE" --metadata 2>/dev/null)

# Extract bounds - try multiple methods
echo "Extracting coordinate bounds..."

# Method 1: Try to get bounds directly
BOUNDS_JSON=$(pdal info "$INPUT_FILE" --metadata 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    # Look for bounds in metadata
    if 'metadata' in data and 'readers.las' in data['metadata']:
        metadata = data['metadata']['readers.las']
        if 'minx' in metadata:
            print(f'{metadata[\"minx\"]},{metadata[\"miny\"]},{metadata[\"maxx\"]},{metadata[\"maxy\"]}')
        else:
            print('BOUNDS_NOT_FOUND')
    else:
        print('BOUNDS_NOT_FOUND')
except:
    print('BOUNDS_NOT_FOUND')
" || echo "BOUNDS_NOT_FOUND")

if [[ "$BOUNDS_JSON" == "BOUNDS_NOT_FOUND" ]]; then
    echo "Cannot extract bounds from metadata. Using sampling method..."

    # Method 2: Sample points to estimate bounds
    TEMP_SAMPLE="$OUTPUT_DIR/sample_points.las"

    # Take a sample of points to get bounds
    pdal translate "$INPUT_FILE" "$TEMP_SAMPLE" --filters.sample.radius=100 --writers.las.compression=false 2>/dev/null

    # Get bounds from sample
    BOUNDS_JSON=$(pdal info "$TEMP_SAMPLE" --metadata 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if 'metadata' in data and 'readers.las' in data['metadata']:
        metadata = data['metadata']['readers.las']
        if 'minx' in metadata:
            print(f'{metadata[\"minx\"]},{metadata[\"miny\"]},{metadata[\"maxx\"]},{metadata[\"maxy\"]}')
        else:
            print('BOUNDS_NOT_FOUND')
    else:
        print('BOUNDS_NOT_FOUND')
except:
    print('BOUNDS_NOT_FOUND')
" || echo "BOUNDS_NOT_FOUND")

    rm -f "$TEMP_SAMPLE"
fi

if [[ "$BOUNDS_JSON" == "BOUNDS_NOT_FOUND" ]]; then
    echo "Error: Could not determine spatial bounds of the dataset"
    echo "Falling back to sequential chunking..."

    # Fallback to original method
    exec /home/prodair/Desktop/MORIUS5090/clustering/stage1_simple.sh
    exit $?
fi

# Parse bounds
IFS=',' read -r MIN_X MIN_Y MAX_X MAX_Y <<< "$BOUNDS_JSON"

echo "Spatial Bounds:"
echo "  X: $MIN_X to $MAX_X"
echo "  Y: $MIN_Y to $MAX_Y"

# Calculate grid dimensions
X_RANGE=$(echo "$MAX_X - $MIN_X" | bc -l)
Y_RANGE=$(echo "$MAX_Y - $MIN_Y" | bc -l)

echo "  X Range: ${X_RANGE}m"
echo "  Y Range: ${Y_RANGE}m"
echo ""

# Calculate optimal grid for ~5 chunks
# Try to create roughly square chunks
TOTAL_AREA=$(echo "$X_RANGE * $Y_RANGE" | bc -l)
CHUNK_AREA=$(echo "$TOTAL_AREA / 5" | bc -l)
CHUNK_SIZE=$(echo "sqrt($CHUNK_AREA)" | bc -l)

# Calculate grid dimensions
GRID_X=$(echo "($X_RANGE + $CHUNK_SIZE - 1) / $CHUNK_SIZE" | bc -l | cut -d. -f1)
GRID_Y=$(echo "($Y_RANGE + $CHUNK_SIZE - 1) / $CHUNK_SIZE" | bc -l | cut -d. -f1)

# Ensure we have at least 1 grid cell in each dimension
GRID_X=$([[ $GRID_X -lt 1 ]] && echo 1 || echo $GRID_X)
GRID_Y=$([[ $GRID_Y -lt 1 ]] && echo 1 || echo $GRID_Y)

echo "Grid Configuration:"
echo "  Grid cells: ${GRID_X}x${GRID_Y} = $((GRID_X * GRID_Y)) chunks"
echo "  Chunk size: ~${CHUNK_SIZE}m x ${CHUNK_SIZE}m"
echo ""

# Calculate cell dimensions
CELL_WIDTH=$(echo "$X_RANGE / $GRID_X" | bc -l)
CELL_HEIGHT=$(echo "$Y_RANGE / $GRID_Y" | bc -l)

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
        echo "  Bounds: (${CELL_MIN_X}, ${CELL_MIN_Y}) to (${CELL_MAX_X}, ${CELL_MAX_Y})"

        # Create PDAL pipeline for spatial cropping
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
                # Check if chunk has points
                CHUNK_SIZE_MB=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')
                POINT_COUNT=$(pdal info "$OUTPUT_CHUNK" --summary 2>/dev/null | grep -i "count:" | head -1 | sed 's/.*count:\s*//' | sed 's/,//g' || echo "0")

                if [[ "$POINT_COUNT" -gt 0 ]]; then
                    echo "  ✓ Success: $POINT_COUNT points ($CHUNK_SIZE_MB)"
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
      "max_y": $MAX_Y
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
echo "SUCCESS! Spatial chunking completed"
echo "Job metadata: $OUTPUT_DIR/job_metadata.json"
echo ""
echo "NEXT STEPS:"
echo "1. Verify spatial chunks: ls -la $OUTPUT_DIR/chunks/"
echo "2. Run Stage 2: ./clustering_production/scripts/stage2_extract_classes.sh $OUTPUT_DIR"