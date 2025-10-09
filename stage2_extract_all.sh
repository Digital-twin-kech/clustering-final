#!/bin/bash

# Stage 2: Extract ALL classes from the point cloud
# Usage: ./stage2_extract_all.sh JOB_ROOT

set -euo pipefail

JOB_ROOT="$1"
MANIFEST="$JOB_ROOT/manifest.json"
CLASSES_DIR="$JOB_ROOT/classes"

echo "INFO: Starting complete class extraction for all classes"

# Build list of all chunk files
CHUNK_FILES=()
while IFS= read -r -d '' file; do
    CHUNK_FILES+=("$file")
done < <(find "$JOB_ROOT/chunks" -name "part_*.laz" -print0 2>/dev/null)

echo "INFO: Found ${#CHUNK_FILES[@]} chunk files"

# Based on our earlier discovery, we know these classes exist: 1,2,3,4,5,6,7,8,9,10,11,12,13,15,16,17,18,40
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

echo "INFO: Extracting all classes: $CLASSIFICATION_CODES"

EXTRACTED_CLASSES=0
TOTAL_POINTS=0

for CLASS_CODE in $CLASSIFICATION_CODES; do
    CLASS_NAME="${CLASS_NAMES[$CLASS_CODE]}"
    CLASS_DIR_NAME=$(printf "%02d-%s" "$CLASS_CODE" "$CLASS_NAME")
    CLASS_DIR="$CLASSES_DIR/$CLASS_DIR_NAME"
    
    echo "INFO: Extracting class $CLASS_CODE ($CLASS_NAME)..."
    
    # Create class directory
    mkdir -p "$CLASS_DIR"
    
    # Create extraction pipeline
    PIPELINE_FILE="$CLASS_DIR/extract_pipeline.json"
    
    cat > "$PIPELINE_FILE" << EOF
{
  "pipeline": [
EOF

    # Add all chunk files as readers
    for i in "${!CHUNK_FILES[@]}"; do
        if [[ $i -gt 0 ]]; then
            echo "    }," >> "$PIPELINE_FILE"
        fi
        echo "    {" >> "$PIPELINE_FILE"
        echo "      \"type\": \"readers.las\"," >> "$PIPELINE_FILE"
        echo "      \"filename\": \"${CHUNK_FILES[$i]}\"" >> "$PIPELINE_FILE"
    done
    echo "    }," >> "$PIPELINE_FILE"
    
    cat >> "$PIPELINE_FILE" << EOF
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
    
    # Execute pipeline with longer timeout for larger classes
    METADATA_FILE="$CLASS_DIR/metrics.json"
    
    echo "INFO: Running extraction pipeline for class $CLASS_CODE (this may take a while)..."
    
    # Use longer timeout and run in background to show progress
    if timeout 300 pdal pipeline "$PIPELINE_FILE" --metadata "$METADATA_FILE" >/dev/null 2>&1; then
        
        # Check if file was created and get point count
        if [[ -f "$CLASS_DIR/class.laz" ]]; then
            # Get actual point count from the file
            POINT_COUNT=$(pdal info "$CLASS_DIR/class.laz" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            
            if [[ $POINT_COUNT -gt 0 ]]; then
                echo "SUCCESS: ✓ Class $CLASS_CODE ($CLASS_NAME): $POINT_COUNT points"
                EXTRACTED_CLASSES=$((EXTRACTED_CLASSES + 1))
                TOTAL_POINTS=$((TOTAL_POINTS + POINT_COUNT))
            else
                echo "INFO: ✗ Class $CLASS_CODE has no points, removing directory"
                rm -rf "$CLASS_DIR"
            fi
        else
            echo "WARNING: ✗ Class $CLASS_CODE: No output file created"
            rm -rf "$CLASS_DIR"
        fi
    else
        echo "ERROR: ✗ Class $CLASS_CODE: Pipeline failed or timed out"
        rm -rf "$CLASS_DIR"
    fi
    
    # Clean up pipeline file
    rm -f "$PIPELINE_FILE"
    
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
    'classes_dir': '$CLASSES_DIR',
    'extracted_classes': []
}

# Find all extracted class directories
class_dirs = glob.glob(os.path.join('$CLASSES_DIR', '*-*'))
for class_dir in sorted(class_dirs):
    if os.path.isdir(class_dir):
        class_file = os.path.join(class_dir, 'class.laz')
        if os.path.exists(class_file):
            manifest['stage2']['extracted_classes'].append({
                'dir': class_dir,
                'class_file': class_file,
                'metrics_file': os.path.join(class_dir, 'metrics.json')
            })

# Write updated manifest
with open('$MANIFEST', 'w') as f:
    json.dump(manifest, f, indent=2)
EOF

echo ""
echo "========================================="
echo "STAGE 2 EXTRACTION COMPLETE"
echo "========================================="
echo "Classes successfully extracted: $EXTRACTED_CLASSES"
echo "Total points extracted: $TOTAL_POINTS"
echo ""

# Show detailed results
if [[ $EXTRACTED_CLASSES -gt 0 ]]; then
    echo "Extracted classes with point counts:"
    find "$CLASSES_DIR" -name "class.laz" | sort | while read -r file; do
        count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
        class_name=$(basename $(dirname "$file"))
        printf "  %-30s %12s points\n" "$class_name" "$count"
    done
    
    echo ""
    echo "Ready for Stage 3 clustering!"
    echo "Run: ./stage3_cluster.sh $JOB_ROOT euclidean 1.0 300"
    echo "Or:  ./stage3_cluster.sh $JOB_ROOT dbscan 1.0 20"
else
    echo "WARNING: No classes were extracted!"
fi

echo "========================================="