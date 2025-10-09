#!/bin/bash

# Stage 1 Simple: Split Large LAZ Files into Manageable Chunks
# Simplified version that works reliably with your LAZ file
# Usage: ./stage1_simple.sh

set -euo pipefail

# Configuration
CHUNK_SIZE=10000000  # 10M points per chunk
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out_clean"

echo "=== STAGE 1: CHUNK SPLITTING ==="
echo "Input file: cloud_point_part_1.laz"
echo "Total points: 50,000,000"
echo "Target chunk size: $CHUNK_SIZE points"
echo "Expected chunks: 5"
echo ""

# Setup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"

# Create 5 chunks of 10M points each
for ((i=0; i<5; i++)); do
    SKIP_POINTS=$((i * CHUNK_SIZE))
    CHUNK_NAME="part_$((i+1))_chunk"
    OUTPUT_CHUNK="$OUTPUT_DIR/chunks/${CHUNK_NAME}.laz"

    echo "Creating chunk $((i+1))/5: $CHUNK_NAME"
    echo "  Skip: $SKIP_POINTS points, Take: $CHUNK_SIZE points"

    # Create PDAL pipeline JSON
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
    echo "$PIPELINE_JSON" | pdal pipeline --stdin

    if [[ -f "$OUTPUT_CHUNK" ]]; then
        CHUNK_SIZE_MB=$(ls -lh "$OUTPUT_CHUNK" | awk '{print $5}')
        echo "  ✓ Created: $CHUNK_SIZE_MB"
    else
        echo "  ✗ Failed to create chunk"
        exit 1
    fi

    echo ""
done

# Summary
echo "=== CHUNKING COMPLETE ==="
echo "Created 5 chunks in: $OUTPUT_DIR/chunks/"
echo ""

# List results
for chunk_file in "$OUTPUT_DIR/chunks"/*.laz; do
    chunk_name=$(basename "$chunk_file" .laz)
    chunk_size=$(ls -lh "$chunk_file" | awk '{print $5}')
    echo "  $chunk_name: $chunk_size"
done

# Create job metadata
cat > "$OUTPUT_DIR/job_metadata.json" << EOF
{
  "job_info": {
    "created_at": "$(date -Iseconds)",
    "input_file": "$INPUT_FILE",
    "stage_completed": "stage1_chunking"
  },
  "input_data": {
    "total_points": 50000000,
    "file_size": "319M",
    "source": "berkane mobile mapping"
  },
  "results": {
    "chunks_created": 5,
    "points_per_chunk": $CHUNK_SIZE
  }
}
EOF

echo ""
echo "✅ SUCCESS! Stage 1 completed"
echo "📁 Output: $OUTPUT_DIR/chunks/"
echo "📄 Metadata: $OUTPUT_DIR/job_metadata.json"
echo ""
echo "🔄 NEXT: Run Stage 2"
echo "   ./clustering_production/scripts/stage2_extract_classes.sh $OUTPUT_DIR"