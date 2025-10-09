#!/bin/bash

# Stage 2 Spatial Fixed: Extract classes using actual classification values found in data
# Usage: ./stage2_spatial_fixed.sh <job_directory>

set -euo pipefail

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <job_directory>"
    echo "Example: $0 /path/to/out_spatial_robust"
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

echo "=== STAGE 2 SPATIAL: CLASS EXTRACTION (FIXED) ==="
echo "Job directory: $JOB_DIR"
echo "Using actual classification values found in dataset"
echo ""

# Actual class definitions found in the berkane dataset
declare -A CLASS_NAMES=(
    [3]="3_Low_Vegetation"
    [4]="4_Medium_Vegetation"
    [6]="6_Buildings"
    [17]="17_Stationary4w"
)

# Classes suitable for instance clustering
EXTRACT_CLASSES="3 4 6 17"

echo "Classes to extract: $EXTRACT_CLASSES"
echo ""

# Initialize counters
total_chunks=0
total_extractions=0
successful_extractions=0

# Process each spatial chunk
for chunk_file in "$JOB_DIR/chunks"/*.laz; do
    [[ -f "$chunk_file" ]] || continue

    ((total_chunks++))
    CHUNK_NAME=$(basename "$chunk_file" .laz)
    echo "[$total_chunks] Processing spatial chunk: $CHUNK_NAME"

    # Create output directories
    CHUNK_OUTPUT="$JOB_DIR/chunks/$CHUNK_NAME"
    mkdir -p "$CHUNK_OUTPUT/compressed/filtred_by_classes"

    # Extract each available class
    for CLASS_CODE in $EXTRACT_CLASSES; do
        ((total_extractions++))
        CLASS_NAME=${CLASS_NAMES[$CLASS_CODE]}
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
        if pdal pipeline "$TEMP_PIPELINE" 2>/dev/null; then
            # Check if file has points
            if [[ -f "$CLASS_FILE" ]]; then
                CHUNK_SIZE=$(stat -c%s "$CLASS_FILE" 2>/dev/null || echo "0")

                if [[ $CHUNK_SIZE -gt 1000 ]]; then
                    # Get point count
                    POINT_COUNT=$(pdal info "$CLASS_FILE" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print('0')
" || echo "0")

                    if [[ "$POINT_COUNT" -gt 0 ]]; then
                        FILE_SIZE=$(ls -lh "$CLASS_FILE" | awk '{print $5}')
                        echo "      ✅ Success: $FILE_SIZE ($POINT_COUNT points)"
                        ((successful_extractions++))
                    else
                        echo "      ⚠️  No points extracted"
                        rm -f "$CLASS_FILE"
                        rmdir "$CLASS_OUTPUT" 2>/dev/null || true
                    fi
                else
                    echo "      ⚠️  Empty class (file too small)"
                    rm -f "$CLASS_FILE"
                    rmdir "$CLASS_OUTPUT" 2>/dev/null || true
                fi
            else
                echo "      ❌ Output file not created"
            fi
        else
            echo "      ❌ PDAL pipeline failed"
            rm -f "$CLASS_FILE" 2>/dev/null
        fi

        # Cleanup temp pipeline
        rm -f "$TEMP_PIPELINE"
    done

    echo ""
done

# Generate comprehensive summary
echo "=== CLASS EXTRACTION RESULTS ==="
echo ""
echo "📊 PROCESSING SUMMARY:"
echo "  Spatial chunks processed: $total_chunks"
echo "  Class extractions attempted: $total_extractions"
echo "  Successful extractions: $successful_extractions"

if [[ $successful_extractions -gt 0 ]]; then
    success_rate=$(echo "scale=1; $successful_extractions * 100 / $total_extractions" | bc -l)
    echo "  Success rate: ${success_rate}%"
fi

echo ""

# Detail extracted classes per chunk
if [[ $successful_extractions -gt 0 ]]; then
    echo "📁 EXTRACTED CLASSES PER SPATIAL CHUNK:"

    for chunk_dir in "$JOB_DIR/chunks"/*/compressed/filtred_by_classes/; do
        if [[ -d "$chunk_dir" ]]; then
            chunk_name=$(basename "$(dirname "$(dirname "$(dirname "$chunk_dir")")")")
            echo "  $chunk_name:"

            for class_dir in "$chunk_dir"*/; do
                if [[ -d "$class_dir" ]]; then
                    class_name=$(basename "$class_dir")
                    class_file="$class_dir/${class_name}.laz"

                    if [[ -f "$class_file" ]]; then
                        file_size=$(ls -lh "$class_file" | awk '{print $5}')
                        point_count=$(pdal info "$class_file" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print('unknown')
" || echo "unknown")

                        echo "    └── $class_name: $file_size ($point_count points)"
                    fi
                fi
            done
        fi
    done

    echo ""
    echo "✅ SUCCESS! Class extraction completed with spatial chunks"
    echo "📁 Ready for Stage 3 clustering: $JOB_DIR"
    echo ""
    echo "🔄 NEXT STEP: Run Stage 3 clustering"
    echo "   ./clustering_production/scripts/stage3_cluster_instances.sh $JOB_DIR"

else
    echo "❌ No classes extracted successfully"
    echo ""
    echo "🔍 POSSIBLE ISSUES:"
    echo "  • Classification values might be different"
    echo "  • Data might not have the expected classes"
    echo "  • Check classification distribution in your dataset"
fi

# Cleanup any remaining temp files
rm -f "$JOB_DIR"/temp_*.json 2>/dev/null

echo ""
echo "Stage 2 complete - spatial chunks with extracted classes ready!"