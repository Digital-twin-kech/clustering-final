#!/bin/bash

# Utility: Combine Trees and Tree Trunks
# Purpose: Merge 7_Trees and 40_TreeTrunks classes into 7_Trees_Combined
# Usage: ./combine_trees_trunks.sh <job_directory>
# Note: This is a utility script, NOT part of the main pipeline stages

set -euo pipefail

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <job_directory>"
    echo "Example: $0 /path/to/job-20231201120000"
    echo ""
    echo "This utility combines 7_Trees and 40_TreeTrunks classes into 7_Trees_Combined"
    echo "Run this BEFORE stage3 clustering if you want combined tree instances"
    exit 1
fi

JOB_DIR="$1"

# Validate input
if [[ ! -d "$JOB_DIR" ]]; then
    echo "Error: Job directory '$JOB_DIR' not found"
    exit 1
fi

echo "=== TREE COMBINING UTILITY ==="
echo "Job directory: $JOB_DIR"
echo "Combining 7_Trees + 40_TreeTrunks → 7_Trees_Combined"
echo ""

total_chunks_processed=0
total_merges_performed=0

# Process each chunk
for chunk_dir in "$JOB_DIR/chunks"/*/; do
    if [[ ! -d "$chunk_dir" ]]; then
        continue
    fi

    chunk_name=$(basename "$chunk_dir")
    echo "Processing chunk: $chunk_name"

    # Paths to tree classes
    trees_dir="$chunk_dir/compressed/filtred_by_classes/7_Trees"
    trunks_dir="$chunk_dir/compressed/filtred_by_classes/40_TreeTrunks"
    combined_dir="$chunk_dir/compressed/filtred_by_classes/7_Trees_Combined"

    trees_file="$trees_dir/7_Trees.laz"
    trunks_file="$trunks_dir/40_TreeTrunks.laz"
    combined_file="$combined_dir/7_Trees_Combined.laz"

    # Check if both tree classes exist
    trees_exists=false
    trunks_exists=false

    if [[ -f "$trees_file" ]]; then
        trees_points=$(pdal info "$trees_file" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print('0')
" || echo "0")
        if [[ "$trees_points" -gt 0 ]]; then
            trees_exists=true
            echo "  Found 7_Trees: $trees_points points"
        fi
    fi

    if [[ -f "$trunks_file" ]]; then
        trunks_points=$(pdal info "$trunks_file" --summary 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['summary']['num_points'])
except:
    print('0')
" || echo "0")
        if [[ "$trunks_points" -gt 0 ]]; then
            trunks_exists=true
            echo "  Found 40_TreeTrunks: $trunks_points points"
        fi
    fi

    # Perform merge if both exist
    if [[ "$trees_exists" == true && "$trunks_exists" == true ]]; then
        echo "  Merging trees and tree trunks..."

        # Create combined directory
        mkdir -p "$combined_dir"

        # Create merge pipeline
        merge_pipeline="$JOB_DIR/temp_merge_trees_${chunk_name}.json"
        cat > "$merge_pipeline" << EOF
[
    {
        "type": "readers.las",
        "filename": "$trees_file"
    },
    {
        "type": "readers.las",
        "filename": "$trunks_file"
    },
    {
        "type": "filters.merge"
    },
    {
        "type": "writers.las",
        "filename": "$combined_file",
        "compression": "laszip"
    }
]
EOF

        # Execute merge
        if pdal pipeline "$merge_pipeline" 2>/dev/null; then
            # Verify combined file
            combined_points=$(pdal info "$combined_file" --metadata 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data['metadata']['readers.las']['count'])
except:
    print('0')
" || echo "0")

            echo "  ✓ Combined: $combined_points points total"
            ((total_merges_performed++))

            # Optionally remove original tree class files to avoid duplication
            # Uncomment the next lines if you want to remove originals
            # rm -f "$trees_file"
            # rm -f "$trunks_file"
            # rmdir "$trees_dir" 2>/dev/null || true
            # rmdir "$trunks_dir" 2>/dev/null || true

        else
            echo "  ✗ Failed to merge trees"
        fi

        # Cleanup temp pipeline
        rm -f "$merge_pipeline"

    elif [[ "$trees_exists" == true ]]; then
        echo "  Only 7_Trees found, copying to combined..."
        mkdir -p "$combined_dir"
        cp "$trees_file" "$combined_file"
        ((total_merges_performed++))

    elif [[ "$trunks_exists" == true ]]; then
        echo "  Only 40_TreeTrunks found, copying to combined..."
        mkdir -p "$combined_dir"
        cp "$trunks_file" "$combined_file"
        ((total_merges_performed++))

    else
        echo "  No tree classes found in this chunk"
    fi

    ((total_chunks_processed++))
    echo ""
done

echo "=== TREE COMBINING COMPLETE ==="
echo "Chunks processed: $total_chunks_processed"
echo "Tree merges performed: $total_merges_performed"
echo ""
echo "Combined tree classes are now available as '7_Trees_Combined'"
echo "You can now run stage3 clustering on the combined tree class"