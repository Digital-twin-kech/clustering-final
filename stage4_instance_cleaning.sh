#!/bin/bash

# Stage 4: Instance Cleaning and Merging Pipeline
# Purpose: Clean and merge instances to improve quality while preserving important data
# Output: clustering/out/cleaned_data/chunks/part_X_chunk/X_className

set -euo pipefail

# Configuration
BASE_DIR="/home/prodair/Desktop/MORIUS5090/clustering"
INPUT_DIR="$BASE_DIR/out/job-20250911110357"
METADATA_DIR="$BASE_DIR/out/dashboard_metadata"
OUTPUT_DIR="$BASE_DIR/out/cleaned_data"
TEMP_DIR="$BASE_DIR/temp/stage4_cleaning"

# Class-specific quality rules
declare -A MIN_POINTS=(
    ["12_Masts"]=100
    ["15_2Wheel"]=80
    ["16_4Wheel"]=200
    ["17_Truck"]=300
    ["18_Bus"]=400
    ["19_Pedestrian"]=50
    ["20_Person"]=50
    ["21_Cyclist"]=60
    ["7_Trees_Combined"]=150
    ["29_Traffic_Signs"]=40
    ["30_Traffic_Lights"]=60
    ["31_Lamp_Posts"]=80
    ["32_Utility_Poles"]=100
)

declare -A MIN_HEIGHT=(
    ["12_Masts"]=2.0
    ["15_2Wheel"]=0.8
    ["16_4Wheel"]=0.8
    ["17_Truck"]=1.5
    ["18_Bus"]=2.0
    ["19_Pedestrian"]=1.2
    ["20_Person"]=1.2
    ["21_Cyclist"]=1.0
    ["7_Trees_Combined"]=2.0
    ["29_Traffic_Signs"]=1.0
    ["30_Traffic_Lights"]=2.5
    ["31_Lamp_Posts"]=3.0
    ["32_Utility_Poles"]=4.0
)

declare -A MERGE_DISTANCE=(
    ["12_Masts"]=2.5
    ["15_2Wheel"]=1.5
    ["16_4Wheel"]=3.5
    ["17_Truck"]=4.0
    ["18_Bus"]=5.0
    ["19_Pedestrian"]=0.8
    ["20_Person"]=0.8
    ["21_Cyclist"]=1.2
    ["7_Trees_Combined"]=3.0
    ["29_Traffic_Signs"]=1.5
    ["30_Traffic_Lights"]=2.0
    ["31_Lamp_Posts"]=2.0
    ["32_Utility_Poles"]=3.0
)

# Logging
LOG_FILE="$BASE_DIR/logs/stage4_cleaning_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# Initialize directories
setup_directories() {
    log "Setting up directories..."
    mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"
    rm -rf "$TEMP_DIR"/*
}

# Extract metadata from instance file
extract_instance_metadata() {
    local instance_file="$1"
    local chunk_name="$2"
    local class_name="$3"

    # Get instance name without extension
    local instance_name=$(basename "$instance_file" .laz)

    # Construct metadata file path using the dashboard_metadata naming convention
    local metadata_file="$METADATA_DIR/chunks/$chunk_name/filtred_by_classes/$class_name/${chunk_name}_compressed_filtred_by_classes_${class_name}_instances_${instance_name}_metadata.json"

    if [[ ! -f "$metadata_file" ]]; then
        error "Metadata file not found: $metadata_file"
        return 1
    fi

    # Extract key metrics using Python since jq is not available
    local point_count=$(python3 -c "
import json, sys
try:
    with open('$metadata_file', 'r') as f:
        data = json.load(f)
    print(data['geometry']['stats']['point_count'])
except:
    print('0')
" 2>/dev/null || echo "0")

    local height=$(python3 -c "
import json, sys
try:
    with open('$metadata_file', 'r') as f:
        data = json.load(f)
    print(data['geometry']['bbox']['dimensions']['height'])
except:
    print('0')
" 2>/dev/null || echo "0")

    local centroid_x=$(python3 -c "
import json, sys
try:
    with open('$metadata_file', 'r') as f:
        data = json.load(f)
    print(data['geometry']['centroid']['x'])
except:
    print('0')
" 2>/dev/null || echo "0")

    local centroid_y=$(python3 -c "
import json, sys
try:
    with open('$metadata_file', 'r') as f:
        data = json.load(f)
    print(data['geometry']['centroid']['y'])
except:
    print('0')
" 2>/dev/null || echo "0")

    local centroid_z=$(python3 -c "
import json, sys
try:
    with open('$metadata_file', 'r') as f:
        data = json.load(f)
    print(data['geometry']['centroid']['z'])
except:
    print('0')
" 2>/dev/null || echo "0")

    echo "$point_count,$height,$centroid_x,$centroid_y,$centroid_z"
}

# Calculate 3D distance between centroids
calculate_distance() {
    local x1=$1 y1=$2 z1=$3
    local x2=$4 y2=$5 z2=$6

    echo "scale=6; sqrt(($x1-$x2)*($x1-$x2) + ($y1-$y2)*($y1-$y2) + ($z1-$z2)*($z1-$z2))" | bc -l
}

# Check if instance meets quality criteria
is_quality_instance() {
    local class_name="$1"
    local point_count="$2"
    local height="$3"

    local min_points=${MIN_POINTS[$class_name]:-50}
    local min_height=${MIN_HEIGHT[$class_name]:-0.5}

    if (( $(echo "$point_count >= $min_points" | bc -l) )) && \
       (( $(echo "$height >= $min_height" | bc -l) )); then
        return 0
    else
        return 1
    fi
}

# Process class instances
process_class_instances() {
    local chunk_dir="$1"
    local class_name="$2"
    local instances_dir="$chunk_dir/compressed/filtred_by_classes/$class_name/instances"
    local chunk_name=$(basename "$chunk_dir")

    if [[ ! -d "$instances_dir" ]]; then
        log "No instances directory for $class_name in $chunk_name"
        return 0
    fi

    log "Processing class $class_name in $chunk_name..."

    # Create temporary analysis file
    local analysis_file="$TEMP_DIR/${chunk_name}_${class_name}_analysis.csv"
    echo "instance_file,point_count,height,centroid_x,centroid_y,centroid_z,quality" > "$analysis_file"

    # Analyze all instances
    local total_instances=0
    local quality_instances=0

    for instance_file in "$instances_dir"/*.laz; do
        [[ -f "$instance_file" ]] || continue

        local metadata=$(extract_instance_metadata "$instance_file" "$chunk_name" "$class_name")
        if [[ -z "$metadata" ]]; then
            continue
        fi

        IFS=',' read -r point_count height centroid_x centroid_y centroid_z <<< "$metadata"

        local is_quality="false"
        if is_quality_instance "$class_name" "$point_count" "$height"; then
            is_quality="true"
            ((quality_instances++))
        fi

        echo "$(basename "$instance_file"),$metadata,$is_quality" >> "$analysis_file"
        ((total_instances++))
    done

    if (( total_instances == 0 )); then
        log "No instances found for $class_name"
        return 0
    fi

    log "$class_name: $quality_instances/$total_instances quality instances ($(echo "scale=1; $quality_instances*100/$total_instances" | bc -l)%)"

    # Find merge candidates
    find_and_merge_instances "$chunk_dir" "$class_name" "$analysis_file"
}

# Find instances that should be merged
find_and_merge_instances() {
    local chunk_dir="$1"
    local class_name="$2"
    local analysis_file="$3"
    local instances_dir="$chunk_dir/compressed/filtred_by_classes/$class_name/instances"

    local merge_distance=${MERGE_DISTANCE[$class_name]:-2.0}
    local chunk_name=$(basename "$chunk_dir")
    local merge_pairs_file="$TEMP_DIR/${chunk_name}_${class_name}_merge_pairs.txt"

    log "Finding merge candidates for $class_name (distance <= ${merge_distance}m)..."

    # Find all merge pairs
    > "$merge_pairs_file"
    local merge_count=0

    while IFS=',' read -r instance1 point_count1 height1 x1 y1 z1 quality1; do
        [[ "$instance1" != "instance_file" ]] || continue
        [[ "$quality1" == "false" ]] || continue  # Only merge low quality instances

        while IFS=',' read -r instance2 point_count2 height2 x2 y2 z2 quality2; do
            [[ "$instance2" != "instance_file" ]] || continue
            [[ "$instance1" != "$instance2" ]] || continue

            local distance=$(calculate_distance "$x1" "$y1" "$z1" "$x2" "$y2" "$z2")

            if (( $(echo "$distance <= $merge_distance" | bc -l) )); then
                # Check if pair already exists (avoid duplicates)
                local pair_exists=$(grep -c "$instance2,$instance1" "$merge_pairs_file" 2>/dev/null || echo "0")
                if (( pair_exists == 0 )); then
                    echo "$instance1,$instance2,$distance" >> "$merge_pairs_file"
                    ((merge_count++))
                fi
            fi
        done < "$analysis_file"
    done < "$analysis_file"

    log "Found $merge_count merge pairs for $class_name"

    if (( merge_count > 0 )); then
        execute_merges "$chunk_dir" "$class_name" "$merge_pairs_file"
    fi

    # Copy quality instances to output
    copy_quality_instances "$chunk_dir" "$class_name" "$analysis_file"
}

# Execute instance merges using PDAL
execute_merges() {
    local chunk_dir="$1"
    local class_name="$2"
    local merge_pairs_file="$3"
    local instances_dir="$chunk_dir/compressed/filtred_by_classes/$class_name/instances"

    local merged_count=0
    local merged_instances=()

    while IFS=',' read -r instance1 instance2 distance; do
        # Skip if either instance was already merged
        local skip=false
        for merged in "${merged_instances[@]}"; do
            if [[ "$instance1" == "$merged" ]] || [[ "$instance2" == "$merged" ]]; then
                skip=true
                break
            fi
        done
        [[ "$skip" == "false" ]] || continue

        log "Merging $instance1 + $instance2 (distance: ${distance}m)"

        # Create merge pipeline
        local chunk_name=$(basename "$chunk_dir")
        local merge_pipeline="$TEMP_DIR/merge_${chunk_name}_${class_name}_${merged_count}.json"
        local merged_instance="$TEMP_DIR/merged_${chunk_name}_${class_name}_$(printf '%03d' $merged_count).laz"

        cat > "$merge_pipeline" << EOF
[
    {
        "type": "readers.las",
        "filename": "$instances_dir/$instance1"
    },
    {
        "type": "readers.las",
        "filename": "$instances_dir/$instance2"
    },
    {
        "type": "filters.merge"
    },
    {
        "type": "filters.assign",
        "assignment": "ClusterID[$merged_count] = $merged_count"
    },
    {
        "type": "writers.las",
        "filename": "$merged_instance",
        "extra_dims": "ClusterID=uint32",
        "compression": "laszip"
    }
]
EOF

        if pdal pipeline "$merge_pipeline" 2>/dev/null; then
            merged_instances+=("$instance1" "$instance2")
            ((merged_count++))
            log "Successfully merged $instance1 + $instance2"
        else
            error "Failed to merge $instance1 + $instance2"
        fi

    done < "$merge_pairs_file"

    log "Completed $merged_count merges for $class_name"
}

# Copy quality instances to output directory
copy_quality_instances() {
    local chunk_dir="$1"
    local class_name="$2"
    local analysis_file="$3"
    local instances_dir="$chunk_dir/compressed/filtred_by_classes/$class_name/instances"

    local chunk_name=$(basename "$chunk_dir")
    local output_class_dir="$OUTPUT_DIR/chunks/$chunk_name/$class_name"
    mkdir -p "$output_class_dir"

    local copied_count=0
    local new_instance_id=0

    # Copy quality instances
    while IFS=',' read -r instance_file point_count height x y z quality; do
        [[ "$instance_file" != "instance_file" ]] || continue
        [[ "$quality" == "true" ]] || continue

        local new_name="${class_name}_$(printf '%03d' $new_instance_id).laz"
        cp "$instances_dir/$instance_file" "$output_class_dir/$new_name"
        ((copied_count++))
        ((new_instance_id++))

    done < "$analysis_file"

    # Copy merged instances
    local chunk_name=$(basename "$chunk_dir")
    for merged_file in "$TEMP_DIR"/merged_${chunk_name}_${class_name}_*.laz; do
        [[ -f "$merged_file" ]] || continue

        local new_name="${class_name}_$(printf '%03d' $new_instance_id).laz"
        cp "$merged_file" "$output_class_dir/$new_name"
        ((copied_count++))
        ((new_instance_id++))
    done

    log "$class_name: Copied $copied_count cleaned instances to output"

    # Generate cleaning summary
    generate_class_summary "$chunk_name" "$class_name" "$output_class_dir" "$copied_count"
}

# Generate cleaning summary for class
generate_class_summary() {
    local chunk_name="$1"
    local class_name="$2"
    local output_dir="$3"
    local final_count="$4"

    local summary_file="$output_dir/cleaning_summary.json"

    cat > "$summary_file" << EOF
{
  "chunk_name": "$chunk_name",
  "class_name": "$class_name",
  "cleaning_algorithm": "quality_filter_and_merge",
  "parameters": {
    "min_points": ${MIN_POINTS[$class_name]:-50},
    "min_height": ${MIN_HEIGHT[$class_name]:-0.5},
    "merge_distance": ${MERGE_DISTANCE[$class_name]:-2.0}
  },
  "final_instances": $final_count,
  "processing_timestamp": "$(date -Iseconds)"
}
EOF
}

# Generate overall cleaning report
generate_cleaning_report() {
    log "Generating overall cleaning report..."

    local report_file="$OUTPUT_DIR/cleaning_report.json"
    local total_instances=0
    local total_classes=0

    # Count cleaned instances
    for chunk_dir in "$OUTPUT_DIR"/chunks/*/; do
        [[ -d "$chunk_dir" ]] || continue

        for class_dir in "$chunk_dir"/*/; do
            [[ -d "$class_dir" ]] || continue

            local class_instances=$(find "$class_dir" -name "*.laz" | wc -l)
            ((total_instances += class_instances))
            ((total_classes++))
        done
    done

    cat > "$report_file" << EOF
{
  "cleaning_summary": {
    "total_cleaned_instances": $total_instances,
    "total_classes_processed": $total_classes,
    "output_structure": "clustering/out/cleaned_data/chunks/part_X_chunk/X_className/",
    "quality_improvement": "Filtered noise instances and merged over-segmented pairs"
  },
  "processing_metadata": {
    "generated_at": "$(date -Iseconds)",
    "generator": "stage4_instance_cleaning.sh",
    "input_directory": "$INPUT_DIR",
    "output_directory": "$OUTPUT_DIR"
  }
}
EOF

    log "Cleaning complete: $total_instances instances across $total_classes class directories"
    log "Cleaning report: $report_file"
}

# Main execution
main() {
    log "Starting Stage 4: Instance Cleaning and Merging"
    log "Input: $INPUT_DIR"
    log "Output: $OUTPUT_DIR"

    setup_directories

    # Process all chunks
    for chunk_dir in "$INPUT_DIR"/chunks/*/; do
        [[ -d "$chunk_dir" ]] || continue

        local chunk_name=$(basename "$chunk_dir")
        log "Processing $chunk_name..."

        # Process all classes in chunk
        for class_dir in "$chunk_dir"/compressed/filtred_by_classes/*/; do
            [[ -d "$class_dir" ]] || continue

            local class_name=$(basename "$class_dir")

            # Skip excluded classes
            case "$class_name" in
                "2_Ground"|"3_Low_Vegetation"|"4_Medium_Vegetation"|"5_High_Vegetation"|"6_Buildings"|"9_Water"|"13_Bridges"|"64_Wire_Guard"|"65_Wire_Conductor")
                    log "Skipping excluded class: $class_name"
                    continue
                    ;;
            esac

            # Only process classes with defined rules
            if [[ -n "${MIN_POINTS[$class_name]:-}" ]]; then
                process_class_instances "$chunk_dir" "$class_name"
            else
                log "Skipping $class_name (no cleaning rules defined)"
            fi
        done
    done

    generate_cleaning_report

    log "Stage 4 instance cleaning completed successfully"
}

# Execute main function
main "$@"