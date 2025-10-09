#!/bin/bash

# Stage 2: Extract classes from each chunk separately (memory-efficient approach)
# Usage: ./stage2_per_chunk.sh JOB_ROOT

set -euo pipefail

JOB_ROOT="$1"
MANIFEST="$JOB_ROOT/manifest.json"

echo "INFO: Starting per-chunk class extraction (memory-efficient approach)"

# Build list of all chunk files
CHUNK_FILES=()
while IFS= read -r -d '' file; do
    CHUNK_FILES+=("$file")
done < <(find "$JOB_ROOT/chunks" -name "part_*.laz" -print0 2>/dev/null)

if [[ ${#CHUNK_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No chunk files found in $JOB_ROOT/chunks" >&2
    exit 1
fi

echo "INFO: Found ${#CHUNK_FILES[@]} chunk files to process"

# Known classification codes from your data
CLASSIFICATION_CODES="1 2 3 4 5 6 7 8 9 10 11 12 13 15 16 17 18 40"

declare -A CLASS_NAMES=(
    [1]="Unassigned"
    [2]="Ground"
    [3]="Low_Vegetation"
    [4]="Medium_Vegetation"
    [5]="High_Vegetation"
    [6]="Building"
    [7]="Low_Point"
    [8]="Reserved"
    [9]="Water"
    [10]="Rail"
    [11]="Road_Surface"
    [12]="Reserved"
    [13]="Wire_Guard"
    [15]="Transmission_Tower"
    [16]="Wire_Structure_Connector"
    [17]="Bridge_Deck"
    [18]="High_Noise"
    [40]="Class_40"
)

echo "INFO: Will extract classes: $CLASSIFICATION_CODES"

TOTAL_EXTRACTED_FILES=0
TOTAL_POINTS=0

# Process each chunk file separately
for CHUNK_FILE in "${CHUNK_FILES[@]}"; do
    CHUNK_NAME=$(basename "$CHUNK_FILE" .laz)
    CHUNK_DIR=$(dirname "$CHUNK_FILE")
    CHUNK_BASE_DIR=$(basename "$CHUNK_DIR")
    
    echo ""
    echo "================================================="
    echo "Processing chunk: $CHUNK_BASE_DIR/$CHUNK_NAME"
    echo "================================================="
    
    # Create chunk classes directory
    CHUNK_CLASSES_DIR="$CHUNK_DIR/classes"
    mkdir -p "$CHUNK_CLASSES_DIR"
    
    # Get point count for this chunk
    CHUNK_POINTS=$(pdal info "$CHUNK_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
    echo "INFO: Chunk contains $CHUNK_POINTS total points"
    
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
        
        if timeout 120 pdal pipeline "$PIPELINE_FILE" --metadata "$METADATA_FILE" >/dev/null 2>&1; then
            
            # Check if any points were extracted
            if [[ -f "$CLASS_DIR/class.laz" ]]; then
                POINT_COUNT=$(pdal info "$CLASS_DIR/class.laz" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                
                if [[ $POINT_COUNT -gt 0 ]]; then
                    echo "  ✓ Class $CLASS_CODE: $POINT_COUNT points"
                    CHUNK_EXTRACTED=$((CHUNK_EXTRACTED + 1))
                    TOTAL_EXTRACTED_FILES=$((TOTAL_EXTRACTED_FILES + 1))
                    TOTAL_POINTS=$((TOTAL_POINTS + POINT_COUNT))
                else
                    echo "  ✗ Class $CLASS_CODE: no points"
                    rm -rf "$CLASS_DIR"
                fi
            else
                echo "  ✗ Class $CLASS_CODE: no output file"
                rm -rf "$CLASS_DIR"
            fi
        else
            echo "  ✗ Class $CLASS_CODE: extraction failed"
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
echo "PER-CHUNK CLASS EXTRACTION COMPLETE"
echo "========================================="
echo "Total class files extracted: $TOTAL_EXTRACTED_FILES"
echo "Total points extracted: $TOTAL_POINTS"

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
    'approach': 'per_chunk',
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

echo ""
echo "Directory structure:"
echo "chunks/"
echo "├── cloud_point_part_1/"
echo "│   ├── part_1.laz"
echo "│   ├── part_2.laz"
echo "│   └── classes/              ← Classes extracted from this chunk"
echo "│       ├── 02-Ground/"
echo "│       │   └── class.laz"
echo "│       ├── 06-Building/"
echo "│       │   └── class.laz"
echo "│       └── ..."
echo ""
echo "Ready for per-chunk clustering!"
echo "Next: ./stage3_per_chunk.sh $JOB_ROOT euclidean 1.0 300"
echo "========================================="