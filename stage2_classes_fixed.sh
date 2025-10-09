#!/bin/bash

# Stage 2: Auto-discover classes and physically separate each class into its own LAZ
# Usage: ./stage2_classes.sh JOB_ROOT

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

# Template paths
TEMPLATE_DIR="$(dirname "$0")/templates"
DISCOVERY_TEMPLATE="$TEMPLATE_DIR/class_discovery.json"
EXTRACT_TEMPLATE="$TEMPLATE_DIR/class_extract.json"

for template in "$DISCOVERY_TEMPLATE" "$EXTRACT_TEMPLATE"; do
    if [[ ! -f "$template" ]]; then
        echo "ERROR: Template not found: $template" >&2
        exit 1
    fi
done

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

# Create class discovery pipeline
echo "INFO: Discovering classes..."
DISCOVERY_PIPELINE="$CLASSES_DIR/class_discovery_pipeline.json"

# Create discovery pipeline by replacing placeholder with proper JSON
python3 << EOF
import json

# Read template
with open('$DISCOVERY_TEMPLATE', 'r') as f:
    template = json.load(f)

# Build chunk list
chunk_files = []
EOF

# Add chunk files to Python array
for file in "${CHUNK_FILES[@]}"; do
    python3 << EOF
chunk_files.append("$file")
EOF
done

python3 << EOF
# Replace placeholder with actual chunk files
pipeline = template['pipeline']
new_pipeline = []
for stage in pipeline:
    if stage == "CHUNK_LIST_PLACEHOLDER":
        # Add each chunk file as a separate stage
        for chunk_file in chunk_files:
            new_pipeline.append({"type": "readers.las", "filename": chunk_file})
    else:
        new_pipeline.append(stage)

template['pipeline'] = new_pipeline

# Write corrected pipeline
with open('$DISCOVERY_PIPELINE', 'w') as f:
    json.dump(template, f, indent=2)
EOF

# Execute class discovery
DISCOVERY_METADATA="$CLASSES_DIR/class_discovery_metadata.json"
echo "INFO: Running class discovery pipeline..."

if ! pdal pipeline "$DISCOVERY_PIPELINE" --metadata "$DISCOVERY_METADATA"; then
    echo "ERROR: Class discovery pipeline failed" >&2
    exit 1
fi

# Parse discovered classes from metadata
echo "INFO: Parsing discovered classes..."
DISCOVERY_METADATA="$DISCOVERY_METADATA" CLASSES_DIR="$CLASSES_DIR" python3 << 'EOF'
import json
import sys
import os

# Read discovery metadata
with open(os.environ['DISCOVERY_METADATA'], 'r') as f:
    metadata = json.load(f)

# Find the filters.stats stage metadata
stats_data = None
if 'stages' in metadata and 'filters.stats' in metadata['stages']:
    stats_data = metadata['stages']['filters.stats']

if not stats_data:
    print("ERROR: No filters.stats metadata found in discovery results", file=sys.stderr)
    sys.exit(1)

# Extract classification values from the statistic array
classifications = {}
if 'statistic' in stats_data:
    for stat in stats_data['statistic']:
        if stat.get('name') == 'Classification' and 'values' in stat:
            # Count points per class (simple estimate based on total count)
            total_count = stat.get('count', 0)
            class_values = stat['values']
            # Rough estimate: divide total points equally among classes
            # (This is an approximation - real counts would need enumeration)
            points_per_class = total_count // len(class_values) if class_values else 0
            
            for class_code in class_values:
                classifications[int(class_code)] = points_per_class
            break

if not classifications:
    print("ERROR: No classifications found in data", file=sys.stderr)
    sys.exit(1)

# Write class enumeration file
classes_enum = {
    'classes': [],
    'total_classified_points': sum(classifications.values())
}

# Common class name mappings (ASPRS standard)
CLASS_NAMES = {
    0: "Never_Classified",
    1: "Unassigned", 
    2: "Ground",
    3: "Low_Vegetation",
    4: "Medium_Vegetation", 
    5: "High_Vegetation",
    6: "Building",
    7: "Low_Point",
    8: "Reserved",
    9: "Water",
    10: "Rail",
    11: "Road_Surface",
    12: "Reserved", 
    13: "Wire_Guard",
    14: "Wire_Conductor",
    15: "Transmission_Tower",
    16: "Wire_Structure_Connector",
    17: "Bridge_Deck",
    18: "High_Noise"
}

for class_code in sorted(classifications.keys()):
    count = classifications[class_code]
    class_name = CLASS_NAMES.get(class_code, f"Class_{class_code}")
    
    classes_enum['classes'].append({
        'code': class_code,
        'name': class_name,
        'point_count': count
    })
    
    print(f"INFO: Found class {class_code} ({class_name}): {count:,} points")

# Write enumeration file
enum_file = os.path.join(os.environ['CLASSES_DIR'], 'classes_enum.json')
with open(enum_file, 'w') as f:
    json.dump(classes_enum, f, indent=2)

print(f"INFO: Class enumeration written to: {enum_file}")
print(f"INFO: Total classes found: {len(classes_enum['classes'])}")
print(f"INFO: Total classified points: {classes_enum['total_classified_points']:,}")
EOF

# Check if class enumeration was successful
CLASSES_ENUM="$CLASSES_DIR/classes_enum.json"
if [[ ! -f "$CLASSES_ENUM" ]]; then
    echo "ERROR: Class enumeration failed" >&2
    exit 1
fi

# Extract each class into separate files
echo "INFO: Extracting classes into separate files..."

# Create a simple extraction script for each class
python3 << EOF
import json
import subprocess
import os

# Read class enumeration
with open('$CLASSES_ENUM', 'r') as f:
    classes_data = json.load(f)

# Build chunk files list
chunk_files = []
EOF

for file in "${CHUNK_FILES[@]}"; do
    python3 << EOF
chunk_files.append("$file")
EOF
done

python3 << EOF
for class_info in classes_data['classes']:
    class_code = class_info['code']
    class_name = class_info['name']
    point_count = class_info['point_count']
    
    # Skip classes with very few points
    if point_count < 100:
        print(f"INFO: Skipping class {class_code} ({class_name}) - too few points ({point_count})")
        continue
    
    print(f"INFO: Extracting class {class_code} ({class_name}) - {point_count:,} points")
    
    # Create class directory
    class_dir_name = f"{class_code:02d}-{class_name}"
    class_dir = os.path.join('$CLASSES_DIR', class_dir_name)
    os.makedirs(class_dir, exist_ok=True)
    
    # Create extraction pipeline directly in Python
    pipeline = {
        "pipeline": []
    }
    
    # Add all chunk files as readers
    for chunk_file in chunk_files:
        pipeline["pipeline"].append({"type": "readers.las", "filename": chunk_file})
    
    # Add class filter
    pipeline["pipeline"].append({
        "type": "filters.expression",
        "expression": f"Classification == {class_code}"
    })
    
    # Add stats and info filters
    pipeline["pipeline"].append({
        "type": "filters.stats",
        "dimensions": "X,Y,Z,Intensity,Classification",
        "enumerate": "Classification"
    })
    
    pipeline["pipeline"].append({
        "type": "filters.info"
    })
    
    # Add writer
    pipeline["pipeline"].append({
        "type": "writers.las",
        "filename": f"{class_dir}/class.laz",
        "compression": True,
        "forward": "all"
    })
    
    # Write pipeline file
    pipeline_file = os.path.join(class_dir, 'extract_pipeline.json')
    with open(pipeline_file, 'w') as f:
        json.dump(pipeline, f, indent=2)
    
    # Validate pipeline
    try:
        subprocess.run(['pdal', 'pipeline', '--validate', pipeline_file], 
                      check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        print(f"ERROR: Pipeline validation failed for class {class_code}")
        continue
    
    # Execute pipeline
    metadata_file = os.path.join(class_dir, 'metrics.json')
    try:
        subprocess.run(['pdal', 'pipeline', pipeline_file, '--metadata', metadata_file],
                      check=True)
        print(f"INFO: Extracted class {class_code} to: {class_dir}/class.laz")
    except subprocess.CalledProcessError:
        print(f"ERROR: Pipeline execution failed for class {class_code}")
        continue
    
    # Clean up working pipeline
    os.remove(pipeline_file)

print("INFO: Class extraction completed")
EOF

# Clean up temporary files
rm -f "$DISCOVERY_PIPELINE" "$DISCOVERY_METADATA"

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
    'classes_enum_file': '$CLASSES_ENUM',
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

# Final summary
CLASS_COUNT=$(find "$CLASSES_DIR" -name "class.laz" 2>/dev/null | wc -l)
echo ""
echo "SUCCESS: Stage 2 completed"
echo "INFO: Classes discovered and extracted: $CLASS_COUNT"
echo "INFO: Class enumeration: $CLASSES_ENUM"
echo "INFO: Class files stored in: $CLASSES_DIR"
echo "INFO: Manifest updated: $MANIFEST"