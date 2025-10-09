#!/bin/bash

# Debug Stage 2 - Simple version to identify the issue
set -euxo pipefail  # Show all commands and exit on any error

JOB_DIR="$1"

echo "=== DEBUG STAGE 2 ==="
echo "Job directory: $JOB_DIR"

# Test chunk file detection
echo "Looking for chunk files in: $JOB_DIR/chunks/"
chunk_files=("$JOB_DIR/chunks"/*.laz)
echo "Found ${#chunk_files[@]} files"

for chunk_file in "${chunk_files[@]}"; do
    if [[ -f "$chunk_file" ]]; then
        chunk_name=$(basename "$chunk_file" .laz)
        echo "Processing: $chunk_name"

        # Test PDAL stats command
        echo "Running pdal info --stats on $chunk_file"
        pdal info "$chunk_file" --stats > "/tmp/debug_${chunk_name}_stats.json"
        echo "Stats saved to /tmp/debug_${chunk_name}_stats.json"

        # Test Python parsing
        echo "Testing Python parsing..."
        python3 -c "
import json
with open('/tmp/debug_${chunk_name}_stats.json', 'r') as f:
    data = json.load(f)
print('Stats file loaded successfully')

for stat in data.get('stats', {}).get('statistic', []):
    if stat.get('name') == 'Classification':
        min_class = int(stat.get('minimum', 0))
        max_class = int(stat.get('maximum', 0))
        print(f'Classification range: {min_class} to {max_class}')
        classes = list(range(min_class, max_class + 1))
        print(f'Classes: {classes}')
        break
else:
    print('No Classification dimension found')
"

        echo "Chunk $chunk_name processed successfully"
        echo "---"
        break  # Only test first chunk for debugging
    fi
done

echo "Debug complete"