#!/bin/bash

# Stage 1 Custom: Split Large LAZ Files into Manageable Chunks
# Custom version for berkane dataset with output to clustering/out_clean
# Usage: ./stage1_custom.sh

set -euo pipefail

# Configuration
DEFAULT_CHUNK_SIZE=10000000  # 10M points per chunk
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out_clean"

# Validate input
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file '$INPUT_FILE' not found"
    exit 1
fi

echo "=== STAGE 1 CUSTOM: CHUNK SPLITTING ==="
echo "Input file: $INPUT_FILE"
echo "Output directory: $OUTPUT_DIR"

# Get file size
FILE_SIZE=$(ls -lh "$INPUT_FILE" | awk '{print $5}')
echo "File size: $FILE_SIZE"

# Setup output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"
TEMP_DIR="$OUTPUT_DIR/temp"
mkdir -p "$TEMP_DIR"

echo ""
echo "Analyzing input file..."

# Get total point count
TOTAL_POINTS=$(pdal info "$INPUT_FILE" --metadata | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['metadata']['readers.las']['count'])
except Exception as e:
    print('Error reading point count:', e, file=sys.stderr)
    sys.exit(1)
")

echo "Total points in file: $TOTAL_POINTS"

# Calculate number of chunks needed
NUM_CHUNKS=$(echo "($TOTAL_POINTS + $DEFAULT_CHUNK_SIZE - 1) / $DEFAULT_CHUNK_SIZE" | bc)
echo "Will create $NUM_CHUNKS chunks of ~$DEFAULT_CHUNK_SIZE points each"
echo ""

# Create chunks using PDAL
for ((i=0; i<NUM_CHUNKS; i++)); do
    SKIP_POINTS=$((i * DEFAULT_CHUNK_SIZE))
    CHUNK_NAME="part_$((i+1))_chunk"
    OUTPUT_CHUNK="$OUTPUT_DIR/chunks/${CHUNK_NAME}.laz"

    echo "Creating chunk $((i+1))/$NUM_CHUNKS: $CHUNK_NAME"
    echo "  Skipping: $SKIP_POINTS points"
    echo "  Taking: $DEFAULT_CHUNK_SIZE points"

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
        "count": $DEFAULT_CHUNK_SIZE
    },
    {
        "type": "writers.las",
        "filename": "$OUTPUT_CHUNK",
        "compression": "laszip"
    }
]
EOF

    # Execute pipeline
    echo "  Executing PDAL pipeline..."
    if pdal pipeline "$PIPELINE_FILE"; then
        # Verify chunk
        CHUNK_POINTS=$(pdal info "$OUTPUT_CHUNK" --metadata | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['metadata']['readers.las']['count'])
except:
    print('0')
" 2>/dev/null || echo "0")

        CHUNK_SIZE=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')
        echo "  ✓ Created: $CHUNK_POINTS points ($CHUNK_SIZE)"
    else
        echo "  ✗ Failed to create chunk $CHUNK_NAME"
        exit 1
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
TOTAL_OUTPUT_POINTS=0

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
" 2>/dev/null || echo "0")
        chunk_size=$(ls -lh "$chunk_file" | awk '{print $5}')
        echo "  $chunk_name: $chunk_points points ($chunk_size)"
        TOTAL_OUTPUT_POINTS=$((TOTAL_OUTPUT_POINTS + chunk_points))
    fi
done

echo ""
echo "VERIFICATION:"
echo "  Input points:  $TOTAL_POINTS"
echo "  Output points: $TOTAL_OUTPUT_POINTS"
echo "  Point preservation: $(echo "scale=2; $TOTAL_OUTPUT_POINTS*100/$TOTAL_POINTS" | bc -l)%"

# Create job metadata
cat > "$OUTPUT_DIR/job_metadata.json" << EOF
{
  "job_info": {
    "created_at": "$(date -Iseconds)",
    "input_file": "$INPUT_FILE",
    "output_directory": "$OUTPUT_DIR",
    "stage_completed": "stage1_chunking"
  },
  "input_data": {
    "file_size": "$FILE_SIZE",
    "total_points": $TOTAL_POINTS,
    "source": "berkane mobile mapping dataset"
  },
  "chunking_results": {
    "chunks_created": $NUM_CHUNKS,
    "chunk_size_target": $DEFAULT_CHUNK_SIZE,
    "total_output_points": $TOTAL_OUTPUT_POINTS,
    "point_preservation_rate": "$(echo "scale=2; $TOTAL_OUTPUT_POINTS*100/$TOTAL_POINTS" | bc -l)%"
  }
}
EOF

echo ""
echo "SUCCESS! Stage 1 completed successfully"
echo "Job metadata saved: $OUTPUT_DIR/job_metadata.json"
echo ""
echo "NEXT STEPS:"
echo "1. Run Stage 2: ./clustering_production/scripts/stage2_extract_classes.sh $OUTPUT_DIR"
echo "2. Check results: ls -la $OUTPUT_DIR/chunks/"