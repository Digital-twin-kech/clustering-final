#!/bin/bash

# Stage 1: Split Large LAZ Files into Manageable Chunks
# Purpose: Split large LAZ files (up to 50M points) into chunks of ~10M points each
# Usage: ./stage1_split_chunks.sh <input_laz_file>

set -euo pipefail

# Configuration
DEFAULT_CHUNK_SIZE=10000000  # 10M points per chunk
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
OUTPUT_DIR="$BASE_DIR/out/job-$(date +%Y%m%d%H%M%S)"

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <input_laz_file> [chunk_size]"
    echo "Example: $0 /path/to/large_file.laz 8000000"
    exit 1
fi

INPUT_FILE="$1"
CHUNK_SIZE="${2:-$DEFAULT_CHUNK_SIZE}"

# Validate input
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file '$INPUT_FILE' not found"
    exit 1
fi

# Setup output directory
mkdir -p "$OUTPUT_DIR/chunks"
TEMP_DIR="$OUTPUT_DIR/temp"
mkdir -p "$TEMP_DIR"

echo "=== STAGE 1: CHUNK SPLITTING ==="
echo "Input file: $INPUT_FILE"
echo "Chunk size: $CHUNK_SIZE points"
echo "Output directory: $OUTPUT_DIR"
echo ""

# Get total point count
echo "Analyzing input file..."
TOTAL_POINTS=$(pdal info "$INPUT_FILE" --metadata | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['metadata']['readers.las']['count'])
")

echo "Total points in file: $TOTAL_POINTS"

# Calculate number of chunks needed
NUM_CHUNKS=$(echo "($TOTAL_POINTS + $CHUNK_SIZE - 1) / $CHUNK_SIZE" | bc)
echo "Will create $NUM_CHUNKS chunks"
echo ""

# Create chunks using PDAL
for ((i=0; i<NUM_CHUNKS; i++)); do
    SKIP_POINTS=$((i * CHUNK_SIZE))
    CHUNK_NAME="part_$((i+1))_chunk"
    OUTPUT_CHUNK="$OUTPUT_DIR/chunks/${CHUNK_NAME}.laz"

    echo "Creating chunk $((i+1))/$NUM_CHUNKS: $CHUNK_NAME"
    echo "  Skipping: $SKIP_POINTS points"
    echo "  Taking: $CHUNK_SIZE points"

    # Create PDAL pipeline for this chunk
    PIPELINE_FILE="$TEMP_DIR/chunk_${i}.json"
    cat > "$PIPELINE_FILE" << EOF
[
    {
        "type": "readers.las",
        "filename": "$INPUT_FILE"
    },
    {
        "type": "filters.tail",
        "count": $((TOTAL_POINTS - SKIP_POINTS))
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

    # Execute pipeline
    if pdal pipeline "$PIPELINE_FILE"; then
        # Verify chunk
        CHUNK_POINTS=$(pdal info "$OUTPUT_CHUNK" --metadata | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['metadata']['readers.las']['count'])
" 2>/dev/null || echo "0")

        echo "  ✓ Created: $CHUNK_POINTS points"
    else
        echo "  ✗ Failed to create chunk $CHUNK_NAME"
    fi

    echo ""
done

# Cleanup temp files
rm -rf "$TEMP_DIR"

# Generate summary
echo "=== CHUNK SPLITTING COMPLETE ==="
echo "Chunks created in: $OUTPUT_DIR/chunks/"
echo ""
echo "Chunk summary:"
for chunk_file in "$OUTPUT_DIR/chunks"/*.laz; do
    if [[ -f "$chunk_file" ]]; then
        chunk_name=$(basename "$chunk_file" .laz)
        chunk_points=$(pdal info "$chunk_file" --metadata | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['metadata']['readers.las']['count'])
except:
    print('0')
" 2>/dev/null)
        chunk_size=$(ls -lh "$chunk_file" | awk '{print $5}')
        echo "  $chunk_name: $chunk_points points ($chunk_size)"
    fi
done

echo ""
echo "Next step: Run stage2_extract_classes.sh on each chunk"
echo "Output directory: $OUTPUT_DIR"