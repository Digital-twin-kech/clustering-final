#!/bin/bash

# Stage 2: Auto-discover classes and physically separate each class into its own LAZ
# Usage: ./stage2_simple.sh JOB_ROOT

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

# Get classification info using pdal info on first chunk
echo "INFO: Discovering classes using pdal info..."
FIRST_CHUNK="${CHUNK_FILES[0]}"

# Use pdal info to get classification values
CLASSES_INFO=$(pdal info "$FIRST_CHUNK" --stats --dimensions=Classification --enumerate=Classification 2>/dev/null || echo "")

if [[ -z "$CLASSES_INFO" ]]; then
    echo "ERROR: Could not get classification info from $FIRST_CHUNK" >&2
    exit 1
fi

# Parse classification codes from pdal info output
echo "INFO: Parsing classification codes..."
CLASSIFICATION_CODES=$(echo "$CLASSES_INFO" | python3 << 'EOF'
import json
import sys

try:
    data = json.load(sys.stdin)
    
    # Find classification statistics
    if 'stats' in data and 'statistic' in data['stats']:
        for stat in data['stats']['statistic']:
            if stat.get('name') == 'Classification':
                if 'values' in stat:
                    # Print each class code on a new line
                    for value in stat['values']:
                        print(int(value))
                elif 'enum' in stat:
                    # Alternative format
                    for key in stat['enum'].keys():
                        print(int(key))
                break
except:
    # Fallback: assume common classes
    print("1")
    print("2") 
    print("3")
    print("6")
EOF
)

if [[ -z "$CLASSIFICATION_CODES" ]]; then
    echo "WARNING: Could not parse classification codes, using common defaults"
    CLASSIFICATION_CODES="1
2
3
6"
fi

echo "INFO: Found classification codes:"
echo "$CLASSIFICATION_CODES"

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

while IFS= read -r CLASS_CODE; do
    if [[ -z "$CLASS_CODE" ]]; then
        continue
    fi
    
    CLASS_NAME="${CLASS_NAMES[$CLASS_CODE]:-Class_$CLASS_CODE}"
    CLASS_DIR_NAME=$(printf "%02d-%s" "$CLASS_CODE" "$CLASS_NAME")
    CLASS_DIR="$CLASSES_DIR/$CLASS_DIR_NAME"
    
    echo "INFO: Extracting class $CLASS_CODE ($CLASS_NAME)..."
    
    # Create class directory
    mkdir -p "$CLASS_DIR"
    
    # Create extraction pipeline directly
    PIPELINE_FILE="$CLASS_DIR/extract_pipeline.json"
    
    # Start pipeline JSON
    echo '{' > "$PIPELINE_FILE"
    echo '  "pipeline": [' >> "$PIPELINE_FILE"
    
    # Add all chunk files as readers
    for i in "${!CHUNK_FILES[@]}"; do
        if [[ $i -gt 0 ]]; then
            echo '    },' >> "$PIPELINE_FILE"
        fi
        echo "    {" >> "$PIPELINE_FILE"
        echo "      \"type\": \"readers.las\"," >> "$PIPELINE_FILE"
        echo "      \"filename\": \"${CHUNK_FILES[$i]}\"" >> "$PIPELINE_FILE"
    done
    echo '    },' >> "$PIPELINE_FILE"
    
    # Add class filter
    echo '    {' >> "$PIPELINE_FILE"
    echo '      "type": "filters.expression",' >> "$PIPELINE_FILE"
    echo "      \"expression\": \"Classification == $CLASS_CODE\"" >> "$PIPELINE_FILE"
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
        rm -f "$PIPELINE_FILE"
        continue
    fi
    
    # Execute pipeline
    METADATA_FILE="$CLASS_DIR/metrics.json"
    if pdal pipeline "$PIPELINE_FILE" --metadata "$METADATA_FILE" >/dev/null 2>&1; then
        echo "INFO: Successfully extracted class $CLASS_CODE to: $CLASS_DIR/class.laz"
        EXTRACTED_CLASSES=$((EXTRACTED_CLASSES + 1))
    else
        echo "WARNING: Pipeline execution failed for class $CLASS_CODE"
    fi
    
    # Clean up working pipeline
    rm -f "$PIPELINE_FILE"
    
done <<< "$CLASSIFICATION_CODES"

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
echo "SUCCESS: Stage 2 completed"
echo "INFO: Classes extracted: $EXTRACTED_CLASSES"
echo "INFO: Class files stored in: $CLASSES_DIR"
echo "INFO: Manifest updated: $MANIFEST"

# List extracted classes
if [[ $EXTRACTED_CLASSES -gt 0 ]]; then
    echo ""
    echo "Extracted class files:"
    find "$CLASSES_DIR" -name "class.laz" | sort
fi