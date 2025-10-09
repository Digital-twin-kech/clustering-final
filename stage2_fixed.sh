#!/bin/bash

# Stage 2 Fixed: Extract classes using chunk metadata with proper bash syntax
set -euo pipefail

JOB_DIR="$1"
echo "=== STAGE 2 FIXED: PERFECT CLASS FILTERING ==="
echo "Job directory: $JOB_DIR"
echo ""

# Class definitions
declare -A CLASS_NAMES=(
    [1]="1_Other" [2]="2_Roads" [3]="3_Sidewalks" [4]="4_OtherGround" [5]="5_TrafficIslands"
    [6]="6_Buildings" [7]="7_Trees" [8]="8_OtherVegetation" [9]="9_TrafficLights"
    [10]="10_TrafficSigns" [11]="11_Wires" [12]="12_Masts" [13]="13_Pedestrians"
    [15]="15_2Wheel" [16]="16_Mobile4w" [17]="17_Stationary4w" [18]="18_Noise" [40]="40_TreeTrunks"
)

SKIP_CLASSES="2 3 4 5 6"
mkdir -p "$JOB_DIR/chunks/metadata"

total_chunks=0
successful_extractions=0

# Process each chunk with fixed bash syntax
for chunk_file in "$JOB_DIR/chunks"/*.laz; do
    [[ -f "$chunk_file" ]] || continue

    ((total_chunks++))
    chunk_name=$(basename "$chunk_file" .laz)
    echo "[$total_chunks] Processing: $chunk_name"

    # Create directories
    chunk_output="$JOB_DIR/chunks/$chunk_name"
    mkdir -p "$chunk_output/compressed/filtred_by_classes"

    # Get stats and detect classes
    stats_file="$JOB_DIR/chunks/metadata/${chunk_name}_stats.json"
    pdal info "$chunk_file" --stats > "$stats_file"

    # Extract class range using Python
    class_range=$(python3 -c "
import json
with open('$stats_file', 'r') as f:
    data = json.load(f)
for stat in data.get('stats', {}).get('statistic', []):
    if stat.get('name') == 'Classification':
        min_class = int(stat.get('minimum', 0))
        max_class = int(stat.get('maximum', 0))
        classes = list(range(min_class, max_class + 1))
        print(' '.join(map(str, classes)))
        break
else:
    print('1 6 7 8 10 11 12 13 15 16 17 18')
")

    echo "  Classes detected: $class_range"

    # Extract each class
    for class_code in $class_range; do
        # Skip large classes
        if [[ " $SKIP_CLASSES " =~ " $class_code " ]]; then
            continue
        fi

        class_name=${CLASS_NAMES[$class_code]:-"${class_code}_Unknown"}
        class_output="$chunk_output/compressed/filtred_by_classes/$class_name"
        mkdir -p "$class_output"
        class_file="$class_output/${class_name}.laz"

        echo "    Extracting class $class_code ($class_name)..."

        # Create extraction pipeline
        pipeline_file="/tmp/extract_${chunk_name}_${class_code}.json"
        cat > "$pipeline_file" << EOF
[
    {"type": "readers.las", "filename": "$chunk_file"},
    {"type": "filters.range", "limits": "Classification[$class_code:$class_code]"},
    {"type": "writers.las", "filename": "$class_file", "compression": "laszip"}
]
EOF

        # Execute extraction
        if pdal pipeline "$pipeline_file" 2>/dev/null; then
            if [[ -f "$class_file" ]]; then
                file_size=$(stat -c%s "$class_file")
                if [[ $file_size -gt 1000 ]]; then
                    # Get point count
                    point_count=$(pdal info "$class_file" --summary | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['summary']['num_points'])
")
                    size_mb=$(ls -lh "$class_file" | awk '{print $5}')
                    echo "      ✅ Success: $size_mb ($point_count points)"
                    ((successful_extractions++))
                else
                    echo "      ⚠️ Empty class"
                    rm -f "$class_file"
                    rmdir "$class_output" 2>/dev/null || true
                fi
            fi
        else
            echo "      ❌ PDAL failed"
        fi
        rm -f "$pipeline_file"
    done
    echo ""
done

echo "=== RESULTS ==="
echo "Chunks processed: $total_chunks"
echo "Successful extractions: $successful_extractions"
echo ""

# List all extracted classes
echo "📁 EXTRACTED CLASSES:"
find "$JOB_DIR/chunks" -name "*.laz" -path "*/filtred_by_classes/*" | while read class_file; do
    if [[ -f "$class_file" ]]; then
        class_path=$(dirname "$class_file")
        class_name=$(basename "$class_path")
        chunk_name=$(basename "$(dirname "$(dirname "$(dirname "$class_path")")")")
        size=$(ls -lh "$class_file" | awk '{print $5}')
        points=$(pdal info "$class_file" --summary | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['summary']['num_points'])
" 2>/dev/null || echo "unknown")
        echo "  $chunk_name/$class_name: $size ($points points)"
    fi
done

echo ""
echo "✅ SUCCESS! All classes extracted from spatial chunks"
echo "🔄 NEXT: Run Stage 3 clustering"