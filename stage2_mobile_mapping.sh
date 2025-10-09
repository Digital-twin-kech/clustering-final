#!/bin/bash

# Stage 2: Extract mobile mapping classes from each chunk separately
# Usage: ./stage2_mobile_mapping.sh JOB_ROOT

set -euo pipefail

JOB_ROOT="$1"
MANIFEST="$JOB_ROOT/manifest.json"

echo "INFO: Starting mobile mapping per-chunk class extraction"

# Build list of all chunk files (from your original chunking)
CHUNK_FILES=()
while IFS= read -r -d '' file; do
    CHUNK_FILES+=("$file")
done < <(find "$JOB_ROOT/chunks" -name "part_*.laz" -print0 2>/dev/null)

if [[ ${#CHUNK_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No chunk files found in $JOB_ROOT/chunks" >&2
    exit 1
fi

echo "INFO: Found ${#CHUNK_FILES[@]} chunk files to process"

# Mobile mapping classification codes from your classes.json
declare -A CLASS_NAMES=(
    [1]="Other"
    [2]="Roads" 
    [3]="Sidewalks"
    [4]="OtherGround"
    [5]="TrafficIslands"
    [6]="Buildings"
    [7]="Trees"
    [8]="OtherVegetation"
    [9]="TrafficLights"
    [10]="TrafficSigns"
    [11]="Wires"
    [12]="Masts"
    [13]="Pedestrians"
    [15]="2Wheel"
    [16]="Mobile4w"
    [17]="Stationary4w"
    [18]="Noise"
    [40]="TreeTrunks"
)

CLASSIFICATION_CODES="1 2 3 4 5 6 7 8 9 10 11 12 13 15 16 17 18 40"
echo "INFO: Will extract mobile mapping classes: $CLASSIFICATION_CODES"

TOTAL_EXTRACTED_FILES=0
TOTAL_POINTS=0

# Process each chunk file separately
for CHUNK_FILE in "${CHUNK_FILES[@]}"; do
    CHUNK_NAME=$(basename "$CHUNK_FILE" .laz)
    CHUNK_DIR=$(dirname "$CHUNK_FILE")
    
    echo ""
    echo "================================================="
    echo "Processing chunk: $CHUNK_NAME"
    echo "File: $CHUNK_FILE"
    echo "================================================="
    
    # Create chunk classes directory
    CHUNK_CLASSES_DIR="$CHUNK_DIR/classes"
    mkdir -p "$CHUNK_CLASSES_DIR"
    
    # Get point count for this chunk
    CHUNK_POINTS=$(pdal info "$CHUNK_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
    echo "INFO: Chunk $CHUNK_NAME contains $CHUNK_POINTS total points"
    
    CHUNK_EXTRACTED=0
    
    # Extract each class from this chunk
    for CLASS_CODE in $CLASSIFICATION_CODES; do
        CLASS_NAME="${CLASS_NAMES[$CLASS_CODE]}"
        CLASS_DIR_NAME=$(printf "%02d-%s" "$CLASS_CODE" "$CLASS_NAME")
        CLASS_DIR="$CHUNK_CLASSES_DIR/$CLASS_DIR_NAME"
        
        echo "INFO: Extracting class $CLASS_CODE ($CLASS_NAME) from $CHUNK_NAME..."
        
        # Create class directory
        mkdir -p "$CLASS_DIR"
        
        # Create extraction pipeline
        PIPELINE_FILE="$CLASS_DIR/extract_pipeline.json"
        
        cat > "$PIPELINE_FILE" << EOF
{
  "pipeline": [
    {
      "type": "readers.las",
      "filename": "$CHUNK_FILE"
    },
    {
      "type": "filters.range",
      "limits": "Classification[$CLASS_CODE:$CLASS_CODE]"
    },
    {
      "type": "filters.stats",
      "dimensions": "X,Y,Z,Intensity,Classification",
      "enumerate": "Classification"
    },
    {
      "type": "filters.info"
    },
    {
      "type": "writers.las",
      "filename": "$CLASS_DIR/class.laz",
      "compression": true,
      "forward": "all"
    }
  ]
}
EOF
        
        # Execute extraction
        METADATA_FILE="$CLASS_DIR/metrics.json"
        
        if timeout 60 pdal pipeline "$PIPELINE_FILE" --metadata "$METADATA_FILE" >/dev/null 2>&1; then
            
            # Check if any points were extracted
            if [[ -f "$CLASS_DIR/class.laz" ]]; then
                POINT_COUNT=$(pdal info "$CLASS_DIR/class.laz" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                
                if [[ $POINT_COUNT -gt 0 ]]; then
                    printf "  ✓ Class %2d %-20s %8s points\n" "$CLASS_CODE" "($CLASS_NAME):" "$POINT_COUNT"
                    CHUNK_EXTRACTED=$((CHUNK_EXTRACTED + 1))
                    TOTAL_EXTRACTED_FILES=$((TOTAL_EXTRACTED_FILES + 1))
                    TOTAL_POINTS=$((TOTAL_POINTS + POINT_COUNT))
                else
                    echo "  ✗ Class $CLASS_CODE ($CLASS_NAME): no points"
                    rm -rf "$CLASS_DIR"
                fi
            else
                echo "  ✗ Class $CLASS_CODE ($CLASS_NAME): no output file"
                rm -rf "$CLASS_DIR"
            fi
        else
            echo "  ✗ Class $CLASS_CODE ($CLASS_NAME): extraction failed"
            rm -rf "$CLASS_DIR"
        fi
        
        # Clean up pipeline
        rm -f "$PIPELINE_FILE"
    done
    
    echo "INFO: Chunk $CHUNK_NAME: extracted $CHUNK_EXTRACTED classes"
    
    # Clean up empty classes directory if no classes were extracted
    if [[ $CHUNK_EXTRACTED -eq 0 ]]; then
        rm -rf "$CHUNK_CLASSES_DIR"
    fi
done

echo ""
echo "========================================="
echo "MOBILE MAPPING CLASS EXTRACTION COMPLETE"
echo "========================================="
echo "Total class files extracted: $TOTAL_EXTRACTED_FILES"
echo "Total points extracted: $TOTAL_POINTS"
echo ""

# Show detailed breakdown
echo "Directory structure created:"
for CHUNK_FILE in "${CHUNK_FILES[@]}"; do
    CHUNK_NAME=$(basename "$CHUNK_FILE" .laz)
    CHUNK_DIR=$(dirname "$CHUNK_FILE")
    CHUNK_CLASSES_DIR="$CHUNK_DIR/classes"
    
    if [[ -d "$CHUNK_CLASSES_DIR" ]]; then
        echo "$CHUNK_CLASSES_DIR/"
        find "$CHUNK_CLASSES_DIR" -name "class.laz" | sort | while read -r class_file; do
            class_dir=$(dirname "$class_file")
            class_name=$(basename "$class_dir")
            point_count=$(pdal info "$class_file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            printf "├── %-30s %8s points\n" "$class_name/class.laz" "$point_count"
        done
        echo ""
    fi
done

# Update manifest
python3 << EOF
import json
import os
import glob

# Read current manifest
with open('$MANIFEST', 'r') as f:
    manifest = json.load(f)

# Add stage 2 info
manifest['stage2'] = {
    'timestamp': '$(date -Iseconds)',
    'approach': 'per_chunk_mobile_mapping',
    'total_class_files': $TOTAL_EXTRACTED_FILES,
    'total_points': $TOTAL_POINTS,
    'chunk_classes': []
}

# Find all chunk class directories
chunk_dirs = glob.glob(os.path.join('$JOB_ROOT', 'chunks', '*'))
for chunk_dir in sorted(chunk_dirs):
    if os.path.isdir(chunk_dir):
        classes_dir = os.path.join(chunk_dir, 'classes')
        if os.path.exists(classes_dir):
            chunk_name = os.path.basename(chunk_dir)
            class_dirs = glob.glob(os.path.join(classes_dir, '*-*'))
            
            chunk_info = {
                'chunk_name': chunk_name,
                'chunk_dir': chunk_dir,
                'classes_dir': classes_dir,
                'extracted_classes': []
            }
            
            for class_dir in sorted(class_dirs):
                if os.path.isdir(class_dir):
                    class_file = os.path.join(class_dir, 'class.laz')
                    if os.path.exists(class_file):
                        chunk_info['extracted_classes'].append({
                            'class_name': os.path.basename(class_dir),
                            'class_dir': class_dir,
                            'class_file': class_file,
                            'metrics_file': os.path.join(class_dir, 'metrics.json')
                        })
            
            if chunk_info['extracted_classes']:
                manifest['stage2']['chunk_classes'].append(chunk_info)

# Write updated manifest
with open('$MANIFEST', 'w') as f:
    json.dump(manifest, f, indent=2)
EOF

echo "Ready for mobile mapping clustering!"
echo "Next: ./stage3_mobile_mapping.sh $JOB_ROOT euclidean 1.0 100"
echo "========================================="