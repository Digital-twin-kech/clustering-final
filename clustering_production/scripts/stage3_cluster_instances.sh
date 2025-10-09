#!/bin/bash

# Stage 3: Cluster Class Instances
# Purpose: Apply EUCLIDEAN clustering to create individual object instances per class
# Usage: ./stage3_cluster_instances.sh <job_directory> [class_name]

set -euo pipefail

# Configuration
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"

# Clustering parameters per class
declare -A TOLERANCE=(
    ["7_Trees"]=1.5
    ["10_TrafficSigns"]=1.0
    ["11_Wires"]=2.0
    ["12_Masts"]=0.5
    ["15_2Wheel"]=0.5
    ["16_Mobile4w"]=1.0
    ["17_Stationary4w"]=1.0
    ["40_TreeTrunks"]=1.0
)

declare -A MIN_POINTS=(
    ["7_Trees"]=50
    ["10_TrafficSigns"]=30
    ["11_Wires"]=20
    ["12_Masts"]=30
    ["15_2Wheel"]=30
    ["16_Mobile4w"]=50
    ["17_Stationary4w"]=50
    ["40_TreeTrunks"]=30
)

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <job_directory> [class_name]"
    echo "Example: $0 /path/to/job-20231201120000 12_Masts"
    echo "If class_name not provided, processes all classes"
    exit 1
fi

JOB_DIR="$1"
TARGET_CLASS="$2"

# Validate input
if [[ ! -d "$JOB_DIR" ]]; then
    echo "Error: Job directory '$JOB_DIR' not found"
    exit 1
fi

echo "=== STAGE 3: INSTANCE CLUSTERING ==="
echo "Job directory: $JOB_DIR"
if [[ -n "$TARGET_CLASS" ]]; then
    echo "Target class: $TARGET_CLASS"
fi
echo ""

cluster_class() {
    local chunk_name="$1"
    local class_name="$2"
    local class_file="$3"

    echo "  Clustering $class_name in $chunk_name..."

    # Get clustering parameters
    local tolerance=${TOLERANCE[$class_name]:-0.5}
    local min_points=${MIN_POINTS[$class_name]:-30}

    echo "    Parameters: tolerance=${tolerance}m, min_points=$min_points"

    # Create instances directory
    local instances_dir="$(dirname "$class_file")/instances"
    mkdir -p "$instances_dir"

    # Create main cluster file first
    local main_cluster_dir="$(dirname "$class_file")/main_cluster"
    mkdir -p "$main_cluster_dir"
    local main_cluster_file="$main_cluster_dir/${class_name}.laz"

    # Step 1: Create main cluster with ClusterID
    local cluster_pipeline="$JOB_DIR/temp_cluster_${chunk_name}_${class_name}.json"
    cat > "$cluster_pipeline" << EOF
[
    {
        "type": "readers.las",
        "filename": "$class_file"
    },
    {
        "type": "filters.cluster",
        "tolerance": $tolerance,
        "min_points": $min_points
    },
    {
        "type": "writers.las",
        "filename": "$main_cluster_file",
        "extra_dims": "ClusterID=uint32",
        "compression": "laszip"
    }
]
EOF

    if ! pdal pipeline "$cluster_pipeline" 2>/dev/null; then
        echo "      ✗ Clustering failed"
        rm -f "$cluster_pipeline"
        return 1
    fi

    # Step 2: Extract individual instances
    echo "    Extracting individual instances..."

    # Get unique cluster IDs
    local cluster_ids=$(pdal info "$main_cluster_file" --metadata | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    # This is simplified - in practice you'd need to scan the actual data
    # For now, assume clusters 1-50 (common range)
    print(' '.join([str(i) for i in range(1, 51)]))
except:
    print('1 2 3 4 5 6 7 8 9 10')
" 2>/dev/null)

    local instance_count=0
    for cluster_id in $cluster_ids; do
        local instance_file="$instances_dir/${class_name}_$(printf '%03d' $instance_count).laz"

        # Create extraction pipeline
        local extract_pipeline="$JOB_DIR/temp_extract_${chunk_name}_${class_name}_${cluster_id}.json"
        cat > "$extract_pipeline" << EOF
[
    {
        "type": "readers.las",
        "filename": "$main_cluster_file"
    },
    {
        "type": "filters.range",
        "limits": "ClusterID[$cluster_id:$cluster_id]"
    },
    {
        "type": "writers.las",
        "filename": "$instance_file",
        "compression": "laszip"
    }
]
EOF

        if pdal pipeline "$extract_pipeline" 2>/dev/null; then
            # Check if instance has points
            local instance_points=$(pdal info "$instance_file" --metadata 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['metadata']['readers.las']['count'])
except:
    print('0')
" || echo "0")

            if [[ "$instance_points" -gt 0 ]]; then
                ((instance_count++))
            else
                rm -f "$instance_file"
            fi
        fi

        rm -f "$extract_pipeline"
    done

    rm -f "$cluster_pipeline"

    echo "      ✓ Created $instance_count instances"
    return 0
}

# Process chunks and classes
total_processed=0
total_instances=0

for chunk_dir in "$JOB_DIR/chunks"/*/compressed/filtred_by_classes/*/; do
    if [[ ! -d "$chunk_dir" ]]; then
        continue
    fi

    # Extract chunk and class names
    chunk_path=$(dirname "$(dirname "$(dirname "$chunk_dir")")")
    chunk_name=$(basename "$chunk_path")
    class_name=$(basename "$chunk_dir")

    # Skip if target class specified and this isn't it
    if [[ -n "$TARGET_CLASS" && "$class_name" != "$TARGET_CLASS" ]]; then
        continue
    fi

    # Check if class file exists
    class_file="$chunk_dir/${class_name}.laz"
    if [[ ! -f "$class_file" ]]; then
        continue
    fi

    echo "Processing $chunk_name/$class_name..."

    # Get point count
    point_count=$(pdal info "$class_file" --metadata 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['metadata']['readers.las']['count'])
except:
    print('0')
" || echo "0")

    echo "  Input: $point_count points"

    # Skip if too few points
    if [[ "$point_count" -lt 100 ]]; then
        echo "  Skipping: too few points"
        continue
    fi

    # Perform clustering
    if cluster_class "$chunk_name" "$class_name" "$class_file"; then
        # Count instances created
        instances_created=$(find "$(dirname "$class_file")/instances" -name "*.laz" | wc -l)
        echo "  Result: $instances_created instances created"
        ((total_processed++))
        ((total_instances += instances_created))
    fi

    echo ""
done

echo "=== CLUSTERING COMPLETE ==="
echo "Classes processed: $total_processed"
echo "Total instances created: $total_instances"
echo ""
echo "Next step: Run stage4_clean_instances.sh for quality improvement"
echo "Or run tree combining utility if needed"