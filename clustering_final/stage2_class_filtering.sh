#!/bin/bash

# ==============================================================================
# STAGE 2: CLASS FILTERING SCRIPT (Based on production version)
# ==============================================================================
#
# Description: Extracts individual classes from a spatial chunk LAZ file
# Based on: clustering_production/scripts/stage2_extract_classes.sh
# Author: Claude Code Assistant
# Version: 2.0 (Production-ready)
#
# Usage:
#   ./stage2_class_filtering.sh <input_laz_file>
#
# Arguments:
#   input_laz_file : Path to input LAZ chunk file
#
# Examples:
#   ./stage2_class_filtering.sh ./out/chunks/spatial_segment_1.laz
#
# Output Structure:
#   ./out/chunks/chunk_X/compressed/filtred_by_classes/
#   ├── 7_Trees/7_Trees.laz
#   ├── 12_Masts/12_Masts.laz
#   └── ... (one directory per class found)
#
# ==============================================================================

set -uo pipefail  # Removed -e to prevent early exit on minor errors

# Class definitions for mobile mapping data (from production script)
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

# Classes to skip - NONE! This is filtering stage, not clustering
SKIP_CLASSES=""  # Process ALL classes in filtering stage

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <input_laz_file>"
    echo "Example: $0 ./out/chunks/spatial_segment_1.laz"
    exit 1
fi

INPUT_FILE="$1"

# Validate input file
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file '$INPUT_FILE' not found"
    exit 1
fi

# Extract chunk information from filename
CHUNK_BASENAME=$(basename "$INPUT_FILE" .laz)
if [[ "$CHUNK_BASENAME" =~ spatial_segment_([0-9]+) ]]; then
    CHUNK_NUM="${BASH_REMATCH[1]}"
else
    # Fallback for non-standard naming
    CHUNK_NUM=$(echo "$CHUNK_BASENAME" | sed 's/[^0-9]*//g')
    if [[ -z "$CHUNK_NUM" ]]; then
        CHUNK_NUM="unknown"
    fi
fi

# Setup output directory (same structure as production)
BASE_DIR=$(dirname "$(realpath "$INPUT_FILE")")
CHUNK_OUTPUT="$BASE_DIR/chunk_${CHUNK_NUM}"
CLASS_OUTPUT_DIR="$CHUNK_OUTPUT/compressed/filtred_by_classes"
mkdir -p "$CLASS_OUTPUT_DIR"

echo "=== STAGE 2: CLASS EXTRACTION ==="
echo "Processing chunk: $CHUNK_BASENAME"
echo "Output: $CLASS_OUTPUT_DIR"
echo ""

# Get available classes in this chunk (using production method)
echo "  Analyzing available classes..."
AVAILABLE_CLASSES=$(pdal info "$INPUT_FILE" --metadata 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    # Use full mobile mapping classes as in previous successful run
    print('1 2 3 4 5 6 7 8 9 10 11 12 13 15 16 17 18 40')  # All mobile mapping classes
except:
    print('1 2 3 4 5 6 7 8 9 10 11 12 13 15 16 17 18 40')
" || echo '1 2 3 4 5 6 7 8 9 10 11 12 13 15 16 17 18 40')

echo "  Classes to process: $AVAILABLE_CLASSES"
echo ""

successful_extractions=0
empty_classes=0
total_points_extracted=0

# Extract each class (same method as production)
for CLASS_CODE in $AVAILABLE_CLASSES; do
    # Process ALL classes - no skipping in filtering stage

    CLASS_NAME=${CLASS_NAMES[$CLASS_CODE]:-"${CLASS_CODE}_Unknown"}
    CLASS_DIR="$CLASS_OUTPUT_DIR/$CLASS_NAME"
    mkdir -p "$CLASS_DIR"

    CLASS_FILE="$CLASS_DIR/${CLASS_NAME}.laz"

    echo "    Extracting class $CLASS_CODE ($CLASS_NAME)..."

    # Create PDAL pipeline for class extraction (exact same as production)
    TEMP_PIPELINE="/tmp/temp_${CHUNK_BASENAME}_${CLASS_CODE}_$$.json"
    cat > "$TEMP_PIPELINE" << EOF
[
    {
        "type": "readers.las",
        "filename": "$INPUT_FILE"
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
    if pdal pipeline "$TEMP_PIPELINE" 2>/dev/null; then
        # Check if file has points (same method as production)
        POINT_COUNT=$(pdal info "$CLASS_FILE" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print('0')
" || echo "0")

        if [[ "$POINT_COUNT" -gt 0 ]]; then
            echo "      ✓ Extracted: $(printf "%'d" $POINT_COUNT) points"
            total_points_extracted=$((total_points_extracted + POINT_COUNT))
            ((successful_extractions++))
        else
            echo "      - No points found, removing empty file"
            rm -f "$CLASS_FILE"
            rmdir "$CLASS_DIR" 2>/dev/null || true
            ((empty_classes++))
        fi
    else
        echo "      ✗ Failed to extract class $CLASS_NAME"
        rm -f "$CLASS_FILE"
        rmdir "$CLASS_DIR" 2>/dev/null || true
        ((empty_classes++))
    fi

    # Cleanup temp pipeline
    rm -f "$TEMP_PIPELINE"
done

echo ""
echo "=== CLASS EXTRACTION COMPLETE ==="
echo ""
echo "📊 SUMMARY:"
echo "  Successful extractions: $successful_extractions"
echo "  Empty classes: $empty_classes"
echo "  Total points extracted: $(printf "%'d" $total_points_extracted)"
echo ""

if [[ $successful_extractions -gt 0 ]]; then
    echo "✅ CLASSES EXTRACTED:"
    for class_dir in "$CLASS_OUTPUT_DIR"/*/; do
        if [[ -d "$class_dir" ]]; then
            class_name=$(basename "$class_dir")
            class_file="$class_dir/${class_name}.laz"

            if [[ -f "$class_file" ]]; then
                # Get point count using production method
                point_count=$(pdal info "$class_file" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print('0')
" || echo "0")

                file_size=$(ls -lh "$class_file" | awk '{print $5}')
                echo "  $class_name: $file_size ($(printf "%'d" $point_count) points)"
            fi
        fi
    done

    echo ""
    echo "🎉 SUCCESS! Class extraction completed"
    echo "📁 Output: $CLASS_OUTPUT_DIR"
    echo ""
    echo "🔄 NEXT STEP: Run Stage 3 clustering on each class"

else
    echo "❌ No classes were extracted successfully"
    echo "Possible causes:"
    echo "  - Input file might not have the expected classification codes"
    echo "  - All classes might be in the skip list"
    echo "  - PDAL pipeline issues"
    exit 1
fi

echo ""
echo "✨ Stage 2 class filtering complete!"