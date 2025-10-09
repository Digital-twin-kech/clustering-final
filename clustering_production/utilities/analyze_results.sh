#!/bin/bash

# Utility: Analyze Clustering Results
# Purpose: Generate comprehensive analysis and statistics of clustering results
# Usage: ./analyze_results.sh <job_directory>

set -euo pipefail

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <job_directory>"
    echo "Example: $0 /path/to/job-20231201120000"
    echo ""
    echo "This utility analyzes clustering results and generates statistics"
    exit 1
fi

JOB_DIR="$1"

# Validate input
if [[ ! -d "$JOB_DIR" ]]; then
    echo "Error: Job directory '$JOB_DIR' not found"
    exit 1
fi

OUTPUT_FILE="$JOB_DIR/clustering_analysis.json"

echo "=== CLUSTERING RESULTS ANALYSIS ==="
echo "Job directory: $JOB_DIR"
echo "Output file: $OUTPUT_FILE"
echo ""

# Initialize counters
total_chunks=0
total_classes=0
total_instances=0
classes_found=()

declare -A class_stats
declare -A chunk_stats

# Analyze chunks and classes
echo "Analyzing clustering results..."

for chunk_dir in "$JOB_DIR/chunks"/*/; do
    if [[ ! -d "$chunk_dir" ]]; then
        continue
    fi

    chunk_name=$(basename "$chunk_dir")
    ((total_chunks++))

    echo "  Chunk: $chunk_name"
    chunk_instances=0

    # Check for instances directory structure
    instances_base="$chunk_dir/compressed/filtred_by_classes"
    if [[ ! -d "$instances_base" ]]; then
        echo "    No filtred_by_classes directory"
        continue
    fi

    for class_dir in "$instances_base"/*/; do
        if [[ ! -d "$class_dir" ]]; then
            continue
        fi

        class_name=$(basename "$class_dir")

        # Count instances
        instances_dir="$class_dir/instances"
        class_instances=0

        if [[ -d "$instances_dir" ]]; then
            class_instances=$(find "$instances_dir" -name "*.laz" | wc -l)
        fi

        if [[ "$class_instances" -gt 0 ]]; then
            echo "    $class_name: $class_instances instances"

            # Update statistics
            if [[ ! " ${classes_found[@]} " =~ " ${class_name} " ]]; then
                classes_found+=("$class_name")
                ((total_classes++))
                class_stats["$class_name"]=0
            fi

            class_stats["$class_name"]=$((${class_stats["$class_name"]} + $class_instances))
            chunk_instances=$((chunk_instances + $class_instances))
            total_instances=$((total_instances + $class_instances))
        fi
    done

    chunk_stats["$chunk_name"]=$chunk_instances
    echo "    Total: $chunk_instances instances"
    echo ""
done

# Generate analysis results
echo "=== ANALYSIS SUMMARY ==="
echo "Total chunks processed: $total_chunks"
echo "Total classes found: $total_classes"
echo "Total instances created: $total_instances"
echo ""

echo "Instances per class:"
for class_name in "${classes_found[@]}"; do
    echo "  $class_name: ${class_stats[$class_name]} instances"
done

echo ""
echo "Instances per chunk:"
for chunk_name in "${!chunk_stats[@]}"; do
    echo "  $chunk_name: ${chunk_stats[$chunk_name]} instances"
done

# Create JSON report
cat > "$OUTPUT_FILE" << EOF
{
  "analysis_summary": {
    "total_chunks": $total_chunks,
    "total_classes": $total_classes,
    "total_instances": $total_instances,
    "classes_found": [$(printf '"%s",' "${classes_found[@]}" | sed 's/,$//')],
    "average_instances_per_chunk": $(echo "scale=1; $total_instances/$total_chunks" | bc -l 2>/dev/null || echo "0")
  },
  "class_statistics": {
EOF

# Add class stats to JSON
first_class=true
for class_name in "${classes_found[@]}"; do
    if [[ "$first_class" == true ]]; then
        first_class=false
    else
        echo "," >> "$OUTPUT_FILE"
    fi
    echo -n "    \"$class_name\": ${class_stats[$class_name]}" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" << EOF

  },
  "chunk_statistics": {
EOF

# Add chunk stats to JSON
first_chunk=true
for chunk_name in "${!chunk_stats[@]}"; do
    if [[ "$first_chunk" == true ]]; then
        first_chunk=false
    else
        echo "," >> "$OUTPUT_FILE"
    fi
    echo -n "    \"$chunk_name\": ${chunk_stats[$chunk_name]}" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" << EOF

  },
  "processing_metadata": {
    "generated_at": "$(date -Iseconds)",
    "generator": "analyze_results.sh",
    "job_directory": "$JOB_DIR"
  }
}
EOF

echo ""
echo "Analysis complete!"
echo "Results saved to: $OUTPUT_FILE"

# Check for cleaned data
if [[ -d "$JOB_DIR/cleaned_data" ]]; then
    echo ""
    echo "Cleaned data directory found - analyzing cleaned results..."

    cleaned_instances=$(find "$JOB_DIR/cleaned_data" -name "*.laz" | wc -l)
    echo "Cleaned instances: $cleaned_instances"

    if [[ "$total_instances" -gt 0 ]]; then
        quality_rate=$(echo "scale=1; $cleaned_instances*100/$total_instances" | bc -l)
        echo "Quality rate: $quality_rate%"
    fi
fi