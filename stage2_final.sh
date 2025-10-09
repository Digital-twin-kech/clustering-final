#!/bin/bash

# Stage 2: Auto-discover classes and physically separate each class into its own LAZ
# Usage: ./stage2_final.sh JOB_ROOT

set -euo pipefail

# Check arguments
if [[ $# -ne 1 ]]; then
    echo "ERROR: Usage: $0 JOB_ROOT" >&2
    echo "  JOB_ROOT: Job directory from stage 1" >&2
    exit 1
fi

JOB_ROOT="$1"
MANIFEST="$JOB_ROOT/manifest.json"

# Validate job root and manifest
if [[ ! -d "$JOB_ROOT" ]]; then
    echo "ERROR: Job root directory not found: $JOB_ROOT" >&2
    exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: Manifest not found: $MANIFEST" >&2
    echo "       Run stage 1 first" >&2
    exit 1
fi

# Validate PDAL is available
if ! command -v pdal >/dev/null 2>&1; then
    echo "ERROR: pdal command not found. Please install PDAL >= 2.6" >&2
    exit 1
fi

echo "INFO: Starting Stage 2 - Class discovery and separation"

# Create classes directory
CLASSES_DIR="$JOB_ROOT/classes"
mkdir -p "$CLASSES_DIR"

# Build list of all chunk files
echo "INFO: Building chunk file list..."
CHUNK_FILES=()
while IFS= read -r -d '' file; do
    CHUNK_FILES+=("$file")
done < <(find "$JOB_ROOT/chunks" -name "part_*.laz" -print0 2>/dev/null)

if [[ ${#CHUNK_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No chunk files found in $JOB_ROOT/chunks" >&2
    echo "       Run stage 1 first" >&2
    exit 1
fi

echo "INFO: Found ${#CHUNK_FILES[@]} chunk files"

# Use a simple approach - try common classification codes
echo "INFO: Testing common classification codes..."
CLASSIFICATION_CODES="1 2 3 4 5 6 7 8 9 10 11 12 13 15 16 17 18 40"

echo "INFO: Will attempt to extract these classification codes: $CLASSIFICATION_CODES"

# Common class name mappings (ASPRS standard)
declare -A CLASS_NAMES=(
    [0]="Never_Classified"
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
    [14]="Wire_Conductor"
    [15]="Transmission_Tower"
    [16]="Wire_Structure_Connector"
    [17]="Bridge_Deck"
    [18]="High_Noise"
    [40]="Class_40"
)

# Extract each class into separate files
echo "INFO: Extracting classes into separate files..."

EXTRACTED_CLASSES=0
TOTAL_POINTS=0

for CLASS_CODE in $CLASSIFICATION_CODES; do
    CLASS_NAME="${CLASS_NAMES[$CLASS_CODE]:-Class_$CLASS_CODE}"
    CLASS_DIR_NAME=$(printf "%02d-%s" "$CLASS_CODE" "$CLASS_NAME")
    CLASS_DIR="$CLASSES_DIR/$CLASS_DIR_NAME"
    
    echo "INFO: Testing class $CLASS_CODE ($CLASS_NAME)..."
    
    # Create class directory
    mkdir -p "$CLASS_DIR"
    
    # Create extraction pipeline using filters.range
    PIPELINE_FILE="$CLASS_DIR/extract_pipeline.json"
    
    # Create pipeline JSON directly
    echo "{" > "$PIPELINE_FILE"
    echo '  "pipeline": [' >> "$PIPELINE_FILE"
    
    # Add all chunk files as readers
    for i in "${!CHUNK_FILES[@]}"; do
        if [[ $i -gt 0 ]]; then
            echo '    },' >> "$PIPELINE_FILE"
        fi
        echo '    {' >> "$PIPELINE_FILE"
        echo '      "type": "readers.las",' >> "$PIPELINE_FILE"
        echo "      \"filename\": \"${CHUNK_FILES[$i]}\"" >> "$PIPELINE_FILE"
    done
    echo '    },' >> "$PIPELINE_FILE"
    
    # Add class filter using filters.range
    echo '    {' >> "$PIPELINE_FILE"
    echo '      "type": "filters.range",' >> "$PIPELINE_FILE"
    echo "      \"limits\": \"Classification[$CLASS_CODE:$CLASS_CODE]\"" >> "$PIPELINE_FILE"
    echo '    },' >> "$PIPELINE_FILE"
    
    # Add stats filter
    echo '    {' >> "$PIPELINE_FILE"
    echo '      "type": "filters.stats",' >> "$PIPELINE_FILE"
    echo '      "dimensions": "X,Y,Z,Intensity,Classification",' >> "$PIPELINE_FILE"
    echo '      "enumerate": "Classification"' >> "$PIPELINE_FILE"
    echo '    },' >> "$PIPELINE_FILE"
    
    # Add info filter
    echo '    {' >> "$PIPELINE_FILE"
    echo '      "type": "filters.info"' >> "$PIPELINE_FILE"
    echo '    },' >> "$PIPELINE_FILE"
    
    # Add writer
    echo '    {' >> "$PIPELINE_FILE"
    echo '      "type": "writers.las",' >> "$PIPELINE_FILE"
    echo "      \"filename\": \"$CLASS_DIR/class.laz\"," >> "$PIPELINE_FILE"
    echo '      "compression": true,' >> "$PIPELINE_FILE"
    echo '      "forward": "all"' >> "$PIPELINE_FILE"
    echo '    }' >> "$PIPELINE_FILE"
    
    # Close pipeline JSON
    echo '  ]' >> "$PIPELINE_FILE"
    echo '}' >> "$PIPELINE_FILE"
    
    # Validate pipeline
    if ! pdal pipeline --validate "$PIPELINE_FILE" >/dev/null 2>&1; then
        echo "WARNING: Pipeline validation failed for class $CLASS_CODE, skipping"
        rm -rf "$CLASS_DIR"
        continue
    fi
    
    # Execute pipeline with timeout
    METADATA_FILE="$CLASS_DIR/metrics.json"
    echo "INFO: Running extraction for class $CLASS_CODE..."
    
    if timeout 60 pdal pipeline "$PIPELINE_FILE" --metadata "$METADATA_FILE" >/dev/null 2>&1; then
        # Check if any points were actually written
        if [[ -f "$CLASS_DIR/class.laz" ]]; then
            POINT_COUNT=$(pdal info "$CLASS_DIR/class.laz" --summary 2>/dev/null | grep -o '"count": [0-9]*' | head -1 | grep -o '[0-9]*' || echo "0")
            if [[ $POINT_COUNT -gt 0 ]]; then
                echo "INFO: ✓ Extracted class $CLASS_CODE: $POINT_COUNT points"
                EXTRACTED_CLASSES=$((EXTRACTED_CLASSES + 1))
                TOTAL_POINTS=$((TOTAL_POINTS + POINT_COUNT))
            else
                echo "INFO: ✗ Class $CLASS_CODE has no points"
                rm -rf "$CLASS_DIR"
            fi
        else
            echo "INFO: ✗ Class $CLASS_CODE produced no output file"
            rm -rf "$CLASS_DIR"
        fi
    else
        echo "WARNING: ✗ Pipeline execution failed/timed out for class $CLASS_CODE"
        rm -rf "$CLASS_DIR"
    fi
    
    # Clean up working pipeline
    rm -f "$PIPELINE_FILE"
done

# Update manifest
cat > /tmp/update_manifest.py << 'EOF'
import json
import os
import glob
import sys

manifest_file = sys.argv[1]
classes_dir = sys.argv[2]

# Read current manifest
with open(manifest_file, 'r') as f:
    manifest = json.load(f)

# Add stage 2 info
manifest['stage2'] = {
    'timestamp': sys.argv[3],
    'classes_dir': classes_dir,
    'extracted_classes': []
}

# Find all extracted class directories
class_dirs = glob.glob(os.path.join(classes_dir, '*-*'))
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
with open(manifest_file, 'w') as f:
    json.dump(manifest, f, indent=2)
EOF

python3 /tmp/update_manifest.py "$MANIFEST" "$CLASSES_DIR" "$(date -Iseconds)"
rm -f /tmp/update_manifest.py

echo ""
echo "SUCCESS: Stage 2 completed"
echo "INFO: Classes extracted: $EXTRACTED_CLASSES"
echo "INFO: Total points extracted: $TOTAL_POINTS"
echo "INFO: Class files stored in: $CLASSES_DIR"
echo "INFO: Manifest updated: $MANIFEST"

# List extracted classes
if [[ $EXTRACTED_CLASSES -gt 0 ]]; then
    echo ""
    echo "Extracted class files:"
    find "$CLASSES_DIR" -name "class.laz" | sort | while read -r file; do
        count=$(pdal info "$file" --summary 2>/dev/null | grep -o '"count": [0-9]*' | head -1 | grep -o '[0-9]*' || echo "0")
        echo "  $(basename $(dirname "$file")): $count points"
    done
else
    echo ""
    echo "WARNING: No classes were successfully extracted"
    echo "This may indicate:"
    echo "- The data has different classification codes than expected"
    echo "- The classification dimension is not present"
    echo "- All points are unclassified (class 0)"
fi