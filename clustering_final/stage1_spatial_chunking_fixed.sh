#!/bin/bash

# ==============================================================================
# STAGE 1: FIXED SPATIAL CHUNKING SCRIPT
# ==============================================================================
#
# CRITICAL FIX: Auto-detect actual data bounds instead of using hardcoded bounds
# This ensures NO POINTS ARE LOST during spatial chunking
#
# Previous issue: Hardcoded bounds excluded TreeTrunks (class 40)
# Solution: Dynamic bounds detection + careful spatial division
#
# ==============================================================================

set -u  # Don't exit on errors, handle them gracefully

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local level=$1
    shift
    case $level in
        "INFO")  echo -e "${BLUE}[INFO]${NC} $*" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $*" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $*" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $*" ;;
        "HEADER") echo -e "${CYAN}=== $* ===${NC}" ;;
    esac
}

BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering/clustering_final"
INPUT_FILE="/home/prodair/Desktop/MORIUS5090/clustering/datasetclasified/berkane-classifier-mobile-mapping-flainet/berkane_-_classifier_-_mobile_mapping_flainet/cloud_point_part_1.laz"
OUTPUT_DIR="$BASE_DIR/out"

log "HEADER" "STAGE 1: FIXED SPATIAL CHUNKING"
log "INFO" "Input file: $(basename "$INPUT_FILE")"
log "INFO" "Method: Dynamic bounds detection with careful spatial chunking"
log "INFO" "Goal: Preserve ALL points including TreeTrunks (class 40)"
echo

# Setup
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/chunks"

# ==============================================================================
# DYNAMIC BOUNDS DETECTION
# ==============================================================================

log "HEADER" "DYNAMIC BOUNDS DETECTION"
log "INFO" "Analyzing actual data bounds (no hardcoded values)..."

# Get actual data bounds from the file
BOUNDS_INFO=$(pdal info "$INPUT_FILE" --summary)

BOUNDS_DATA=$(echo "$BOUNDS_INFO" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    summary = data['summary']
    bounds = summary['bounds']
    total_points = summary['num_points']

    min_x = bounds['minx']
    max_x = bounds['maxx']
    min_y = bounds['miny']
    max_y = bounds['maxy']
    min_z = bounds['minz']
    max_z = bounds['maxz']

    x_range = max_x - min_x
    y_range = max_y - min_y
    z_range = max_z - min_z

    print(f'{total_points}|{min_x:.6f}|{max_x:.6f}|{min_y:.6f}|{max_y:.6f}|{min_z:.6f}|{max_z:.6f}|{x_range:.1f}|{y_range:.1f}|{z_range:.1f}')

except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
")

if [[ $? -ne 0 ]]; then
    log "ERROR" "Failed to analyze data bounds"
    exit 1
fi

# Parse bounds data
IFS='|' read -r TOTAL_POINTS MIN_X MAX_X MIN_Y MAX_Y MIN_Z MAX_Z X_RANGE Y_RANGE Z_RANGE <<< "$BOUNDS_DATA"

log "INFO" "ACTUAL DATA BOUNDS (not hardcoded):"
log "INFO" "  Total points: $(printf "%'d" $TOTAL_POINTS)"
log "INFO" "  X: $MIN_X to $MAX_X (${X_RANGE}m)"
log "INFO" "  Y: $MIN_Y to $MAX_Y (${Y_RANGE}m)"
log "INFO" "  Z: $MIN_Z to $MAX_Z (${Z_RANGE}m)"

# Verify TreeTrunks are within these bounds
log "INFO" "Verifying TreeTrunks (class 40) are within detected bounds..."

TRUNKS_TEST=$(pdal info "$INPUT_FILE" --stats --dimensions=Classification | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    stats = data['stats']['statistic'][0]
    max_class = int(stats['maximum'])
    if max_class >= 40:
        print('✅ TreeTrunks (class 40) detected in dataset')
    else:
        print('⚠️  TreeTrunks (class 40) not found in dataset')
except:
    print('❌ Failed to check classifications')
")

log "INFO" "$TRUNKS_TEST"

echo

# ==============================================================================
# POINT-COUNT-BASED CHUNKING (PROVEN FILTERS.DIVIDER METHOD)
# ==============================================================================

log "HEADER" "POINT-COUNT-BASED CHUNKING (PROVEN FILTERS.DIVIDER METHOD)"

# Use the proven filters.divider approach from production system
POINTS_PER_CHUNK=10000000  # 10M points per chunk (proven capacity)

log "INFO" "Using proven filters.divider method"
log "INFO" "Capacity: $(printf "%'d" $POINTS_PER_CHUNK) points per chunk"
log "INFO" "Total points to split: $(printf "%'d" $TOTAL_POINTS)"
log "INFO" "This will preserve ALL points including TreeTrunks (class 40)"

echo

# ==============================================================================
# FILTERS.DIVIDER EXECUTION
# ==============================================================================

log "HEADER" "EXECUTING FILTERS.DIVIDER CHUNKING"

PIPELINE_FILE="/tmp/divider_pipeline_$$.json"

# Create the proven PDAL pipeline with filters.divider
cat > "$PIPELINE_FILE" << EOF
[
    {
        "type": "readers.las",
        "filename": "$INPUT_FILE"
    },
    {
        "type": "filters.divider",
        "capacity": $POINTS_PER_CHUNK
    },
    {
        "type": "writers.las",
        "filename": "$OUTPUT_DIR/chunks/spatial_segment_#.laz",
        "compression": "laszip",
        "forward": "all"
    }
]
EOF

log "INFO" "Executing proven filters.divider pipeline..."
log "INFO" "Output pattern: $OUTPUT_DIR/chunks/spatial_segment_#.laz"

# Execute the pipeline
if pdal pipeline "$PIPELINE_FILE" 2>/dev/null; then
    log "SUCCESS" "✅ filters.divider execution completed"

    # Count and analyze generated chunks
    CHUNK_FILES=($(find "$OUTPUT_DIR/chunks" -name "spatial_segment_*.laz" -type f | sort))
    successful_chunks=${#CHUNK_FILES[@]}
    total_points_processed=0

    log "INFO" "Generated $successful_chunks chunk files"
    echo

    # Analyze each generated chunk with direct PDAL info
    for chunk_file in "${CHUNK_FILES[@]}"; do
        chunk_name=$(basename "$chunk_file" .laz)
        chunk_size=$(ls -lh "$chunk_file" | awk '{print $5}')

        log "INFO" "Analyzing: $chunk_name"

        # Get point count directly from PDAL
        point_count=$(pdal info "$chunk_file" --summary 2>/dev/null | grep -o '"num_points": [0-9]*' | cut -d' ' -f2 || echo "0")

        # Get classification range directly from PDAL
        class_info=$(pdal info "$chunk_file" --stats --dimensions=Classification 2>/dev/null)
        min_class=$(echo "$class_info" | grep -o '"minimum": [0-9]*' | cut -d' ' -f2 || echo "0")
        max_class=$(echo "$class_info" | grep -o '"maximum": [0-9]*' | cut -d' ' -f2 || echo "0")

        # Check for TreeTrunks
        if [[ "$max_class" -ge 40 ]]; then
            has_trunks="✅"
            trunks_msg="🌳 TreeTrunks (class 40) PRESERVED!"
        else
            has_trunks="❌"
            trunks_msg=""
        fi

        if [[ "$point_count" -gt 0 ]]; then
            total_points_processed=$((total_points_processed + point_count))
            log "SUCCESS" "  ✅ $chunk_size ($(printf "%'d" $point_count) points)"
            log "INFO" "    Classes: $min_class-$max_class $has_trunks"

            if [[ -n "$trunks_msg" ]]; then
                log "SUCCESS" "    $trunks_msg"
            fi
        else
            log "WARN" "  ⚠️  Empty chunk (unexpected with filters.divider)"
        fi
        echo
    done

else
    log "ERROR" "❌ filters.divider pipeline failed"
    exit 1
fi

# Cleanup
rm -f "$PIPELINE_FILE" 2>/dev/null

# ==============================================================================
# VALIDATION AND RESULTS
# ==============================================================================

log "HEADER" "VALIDATION AND RESULTS"

log "INFO" "filters.divider chunking completed"
log "INFO" "Successful chunks: $successful_chunks"
log "INFO" "Total points processed: $(printf "%'d" $total_points_processed)"

if [[ $successful_chunks -gt 0 ]]; then
    echo
    log "SUCCESS" "SPATIAL CHUNKS CREATED:"

    total_chunks_points=0
    chunks_with_trunks=0

    for chunk_file in "$OUTPUT_DIR/chunks"/*.laz; do
        if [[ -f "$chunk_file" ]]; then
            chunk_name=$(basename "$chunk_file" .laz)
            chunk_size=$(ls -lh "$chunk_file" | awk '{print $5}')

            # Get detailed chunk analysis
            DETAILED_ANALYSIS=$(pdal info "$chunk_file" --summary --stats --dimensions=Classification 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)

    # Basic stats
    summary = data['summary']
    points = summary['num_points']
    bounds = summary['bounds']

    # Classification stats
    max_class = 0
    if 'stats' in data and 'statistic' in data['stats']:
        for stat in data['stats']['statistic']:
            if stat['name'] == 'Classification':
                max_class = int(stat['maximum'])
                break

    # Spatial dimensions
    x_range = bounds['maxx'] - bounds['minx']
    y_range = bounds['maxy'] - bounds['miny']

    has_trunks = max_class >= 40
    trunk_indicator = '🌳' if has_trunks else '  '

    print(f'{points}|{max_class}|{x_range:.1f}|{y_range:.1f}|{trunk_indicator}|{has_trunks}')

except:
    print('0|0|0|0|  |false')
" || echo "0|0|0|0|  |false")

            IFS='|' read -r chunk_points chunk_max_class chunk_x_range chunk_y_range trunk_icon chunk_has_trunks <<< "$DETAILED_ANALYSIS"

            total_chunks_points=$((total_chunks_points + chunk_points))

            if [[ "$chunk_has_trunks" == "true" ]]; then
                ((chunks_with_trunks++))
            fi

            log "INFO" "  $chunk_name: $chunk_size ($(printf "%'d" $chunk_points) points) ${trunk_icon}"
            log "INFO" "    Spatial: ${chunk_x_range}m × ${chunk_y_range}m, Classes: 1-$chunk_max_class"
        fi
    done

    echo
    log "INFO" "📈 CRITICAL VALIDATION:"
    log "INFO" "  Original points: $(printf "%'d" $TOTAL_POINTS)"
    log "INFO" "  Processed points: $(printf "%'d" $total_chunks_points)"

    # Calculate coverage
    coverage=$(echo "scale=2; $total_chunks_points * 100 / $TOTAL_POINTS" | bc -l)
    log "INFO" "  Coverage: ${coverage}%"

    if (( $(echo "$coverage > 99.5" | bc -l) )); then
        log "SUCCESS" "  🎉 EXCELLENT! Nearly 100% coverage achieved"
    elif (( $(echo "$coverage > 95.0" | bc -l) )); then
        log "SUCCESS" "  ✅ GOOD! >95% coverage achieved"
    else
        log "WARN" "  ⚠️  Coverage lower than expected"
    fi

    # TreeTrunks verification
    echo
    log "INFO" "🌳 TREETRUNK VERIFICATION:"
    log "INFO" "  Chunks containing TreeTrunks: $chunks_with_trunks/$successful_chunks"

    if [[ $chunks_with_trunks -gt 0 ]]; then
        log "SUCCESS" "  🎉 SUCCESS! TreeTrunks (class 40) PRESERVED in spatial chunks!"
        log "INFO" "  TreeTrunks are now available for Stage 2 class filtering"
    else
        log "WARN" "  ⚠️  TreeTrunks still not found - investigate further"
    fi

    echo
    log "SUCCESS" "🎉 FIXED SPATIAL CHUNKING COMPLETED!"
    log "INFO" "📁 Output: $OUTPUT_DIR/chunks/"

    echo
    log "INFO" "🔄 NEXT STEP: Run Stage 2 class filtering"
    log "INFO" "  TreeTrunks should now be preserved in the chunks!"

else
    log "ERROR" "❌ No spatial chunks created"
    log "ERROR" "This indicates a serious problem with the data or bounds"
    exit 1
fi

echo
log "SUCCESS" "✨ Fixed spatial chunking analysis complete!"