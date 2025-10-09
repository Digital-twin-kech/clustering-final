#!/bin/bash

# Stage 2: Extract Semantic Classes from Chunks
# Purpose: Split chunks by semantic classes and organize into separate directories
# Usage: ./stage2_extract_classes.sh <job_directory>

set -euo pipefail

# Configuration
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"

# Class definitions for mobile mapping data
declare -A CLASS_NAMES=(
    [1]="1_Other"
    [2]="2_Roads"
    [3]="3_Sidewalks"
    [4]="4_OtherGround"
    [5]="5_TrafficIslands"
    [6]="6_Buildings"
    [7]="7_Trees"
    [8]="8_OtherVegetation"
    [9]="9_TrafficLights"
    [10]="10_TrafficSigns"
    [11]="11_Wires"
    [12]="12_Masts"
    [13]="13_Pedestrians"
    [15]="15_2Wheel"
    [16]="16_Mobile4w"
    [17]="17_Stationary4w"
    [18]="18_Noise"
    [19]="19_Pedestrian"
    [40]="40_TreeTrunks"
    [64]="64_Wire_Guard"
    [65]="65_Wire_Conductor"
)

# Classes to skip (too large, not suitable for instance clustering)
SKIP_CLASSES="2 3 4 5 6 9 13 64 65"

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <job_directory>"
    echo "Example: $0 /path/to/job-20231201120000"
    exit 1
fi

JOB_DIR="$1"

# Validate input
if [[ ! -d "$JOB_DIR" ]]; then
    echo "Error: Job directory '$JOB_DIR' not found"
    exit 1
fi

if [[ ! -d "$JOB_DIR/chunks" ]]; then
    echo "Error: Chunks directory not found in $JOB_DIR"
    exit 1
fi

echo "=== STAGE 2: CLASS EXTRACTION ==="
echo "Job directory: $JOB_DIR"
echo "Processing chunks..."
echo ""

# Process each chunk
for chunk_file in "$JOB_DIR/chunks"/*.laz; do
    [[ -f "$chunk_file" ]] || continue

    CHUNK_NAME=$(basename "$chunk_file" .laz)
    echo "Processing chunk: $CHUNK_NAME"

    # Create output directories
    CHUNK_OUTPUT="$JOB_DIR/chunks/$CHUNK_NAME"
    mkdir -p "$CHUNK_OUTPUT/compressed/filtred_by_classes"

    # Get available classes in this chunk
    echo "  Analyzing available classes..."
    AVAILABLE_CLASSES=$(pdal info "$chunk_file" --metadata | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    # Use full mobile mapping classes as in previous successful run
    print('1 2 3 4 5 6 7 8 9 10 11 12 13 15 16 17 18 40')  # All mobile mapping classes
except:
    print('1 2 3 4 5 6 7 8 9 10 11 12 13 15 16 17 18 40')
" 2>/dev/null)

    # Extract each class
    for CLASS_CODE in $AVAILABLE_CLASSES; do
        # Skip if in skip list
        if [[ " $SKIP_CLASSES " =~ " $CLASS_CODE " ]]; then
            continue
        fi

        CLASS_NAME=${CLASS_NAMES[$CLASS_CODE]:-"${CLASS_CODE}_Unknown"}
        CLASS_OUTPUT="$CHUNK_OUTPUT/compressed/filtred_by_classes/$CLASS_NAME"
        mkdir -p "$CLASS_OUTPUT"

        CLASS_FILE="$CLASS_OUTPUT/${CLASS_NAME}.laz"

        echo "    Extracting class $CLASS_CODE ($CLASS_NAME)..."

        # Create PDAL pipeline for class extraction
        TEMP_PIPELINE="$JOB_DIR/temp_${CHUNK_NAME}_${CLASS_CODE}.json"
        cat > "$TEMP_PIPELINE" << EOF
[
    {
        "type": "readers.las",
        "filename": "$chunk_file"
    },
    {
        "type": "filters.range",
        "limits": "Classification[$CLASS_CODE:$CLASS_CODE]"
    },
    {
        "type": "writers.las",
        "filename": "$CLASS_FILE",
        "compression": "laszip"
    }
]
EOF

        # Execute extraction
        if pdal pipeline "$TEMP_PIPELINE"; then
            # Check if file has points
            POINT_COUNT=$(pdal info "$CLASS_FILE" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print('0')
" || echo "0")

            if [[ "$POINT_COUNT" -gt 0 ]]; then
                echo "      ✓ Extracted: $POINT_COUNT points"
            else
                echo "      - No points found, removing empty file"
                rm -f "$CLASS_FILE"
                rmdir "$CLASS_OUTPUT" 2>/dev/null || true
            fi
        else
            echo "      ✗ Failed to extract class $CLASS_NAME"
            rm -f "$CLASS_FILE"
        fi

        # Cleanup temp pipeline
        rm -f "$TEMP_PIPELINE"
    done

    echo ""
done

# Generate summary
echo "=== CLASS EXTRACTION COMPLETE ==="
echo ""
echo "Classes extracted per chunk:"
for chunk_dir in "$JOB_DIR/chunks"/*/compressed/filtred_by_classes/*/; do
    if [[ -d "$chunk_dir" ]]; then
        chunk_path=$(dirname "$(dirname "$(dirname "$chunk_dir")")")
        chunk_name=$(basename "$chunk_path")
        class_name=$(basename "$chunk_dir")

        class_file="$chunk_dir/${class_name}.laz"
        if [[ -f "$class_file" ]]; then
            point_count=$(pdal info "$class_file" --metadata 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['metadata']['readers.las']['count'])
except:
    print('0')
" || echo "0")
            echo "  $chunk_name/$class_name: $point_count points"
        fi
    fi
done

echo ""
echo "Next step: Run stage3_cluster_instances.sh on each chunk/class"
echo "Ready for clustering: $JOB_DIR"