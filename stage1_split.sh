#!/bin/bash

# Stage 1: Split input LAS/LAZ files by point count (~10M points per chunk)
# Usage: ./stage1_split.sh JOB_ROOT INPUT_FILES...

set -euo pipefail

# Check arguments
if [[ $# -lt 2 ]]; then
    echo "ERROR: Usage: $0 JOB_ROOT INPUT_FILES..." >&2
    echo "  JOB_ROOT: Output directory base" >&2
    echo "  INPUT_FILES: One or more LAS/LAZ files to process" >&2
    exit 1
fi

JOB_ROOT="$1"
shift
INPUT_FILES=("$@")

# Validate PDAL is available
if ! command -v pdal >/dev/null 2>&1; then
    echo "ERROR: pdal command not found. Please install PDAL >= 2.6" >&2
    exit 1
fi

# Check PDAL version (basic check)
PDAL_VERSION=$(pdal --version 2>/dev/null | head -n1 || echo "unknown")
echo "INFO: Using PDAL: $PDAL_VERSION"

# Create job root directory
mkdir -p "$JOB_ROOT"

# Initialize manifest
MANIFEST="$JOB_ROOT/manifest.json"
echo '{"stage1": {"input_files": [], "chunks": {}, "timestamp": "'$(date -Iseconds)'"}}' > "$MANIFEST"

# Template path
TEMPLATE_DIR="$(dirname "$0")/templates"
SPLIT_TEMPLATE="$TEMPLATE_DIR/split_by_points.json"

if [[ ! -f "$SPLIT_TEMPLATE" ]]; then
    echo "ERROR: Template not found: $SPLIT_TEMPLATE" >&2
    exit 1
fi

echo "INFO: Starting Stage 1 - Splitting files by point count"
echo "INFO: Target chunk size: ~10M points per file"

# Process each input file
for INPUT_FILE in "${INPUT_FILES[@]}"; do
    echo "INFO: Processing: $INPUT_FILE"
    
    # Validate input file exists
    if [[ ! -f "$INPUT_FILE" ]]; then
        echo "ERROR: Input file not found: $INPUT_FILE" >&2
        exit 1
    fi
    
    # Get absolute path
    INPUT_FILE=$(realpath "$INPUT_FILE")
    
    # Extract basename without extension
    BASENAME=$(basename "$INPUT_FILE" .laz)
    BASENAME=$(basename "$BASENAME" .las)
    
    # Create chunk directory
    CHUNK_DIR="$JOB_ROOT/chunks/$BASENAME"
    mkdir -p "$CHUNK_DIR"
    
    echo "INFO: Chunks will be written to: $CHUNK_DIR"
    
    # Create working pipeline by substituting template
    WORKING_PIPELINE="$CHUNK_DIR/split_pipeline.json"
    sed -e "s|INFILE|$INPUT_FILE|g" \
        -e "s|OUTDIR|$CHUNK_DIR|g" \
        "$SPLIT_TEMPLATE" > "$WORKING_PIPELINE"
    
    # Validate pipeline
    echo "INFO: Validating pipeline..."
    if ! pdal pipeline --validate "$WORKING_PIPELINE" >/dev/null 2>&1; then
        echo "ERROR: Pipeline validation failed for: $WORKING_PIPELINE" >&2
        exit 1
    fi
    
    # Execute pipeline
    echo "INFO: Executing split pipeline..."
    METADATA_FILE="$CHUNK_DIR/split_metadata.json"
    
    if ! pdal pipeline "$WORKING_PIPELINE" --metadata "$METADATA_FILE"; then
        echo "ERROR: Pipeline execution failed for: $INPUT_FILE" >&2
        exit 1
    fi
    
    # Count generated chunks
    CHUNK_COUNT=$(find "$CHUNK_DIR" -name "part_*.laz" | wc -l)
    echo "INFO: Generated $CHUNK_COUNT chunk(s) for: $BASENAME"
    
    # Update manifest with results
    python3 << EOF
import json

# Read current manifest
with open('$MANIFEST', 'r') as f:
    manifest = json.load(f)

# Add this file's info
manifest['stage1']['input_files'].append({
    'path': '$INPUT_FILE',
    'basename': '$BASENAME'
})

manifest['stage1']['chunks']['$BASENAME'] = {
    'chunk_dir': '$CHUNK_DIR',
    'chunk_count': $CHUNK_COUNT,
    'metadata_file': '$METADATA_FILE'
}

# Write updated manifest
with open('$MANIFEST', 'w') as f:
    json.dump(manifest, f, indent=2)
EOF

    # Clean up working pipeline
    rm -f "$WORKING_PIPELINE"
    
    echo "INFO: Completed processing: $BASENAME"
done

# Final summary
TOTAL_CHUNKS=$(find "$JOB_ROOT/chunks" -name "part_*.laz" 2>/dev/null | wc -l)
echo ""
echo "SUCCESS: Stage 1 completed"
echo "INFO: Total input files: ${#INPUT_FILES[@]}"
echo "INFO: Total chunks generated: $TOTAL_CHUNKS"
echo "INFO: Results stored in: $JOB_ROOT"
echo "INFO: Manifest: $MANIFEST"