#!/bin/bash

# Create LAS files from clustered instances for visualization
# Usage: ./create_visualization.sh JOB_ROOT

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "ERROR: Usage: $0 JOB_ROOT" >&2
    echo "  JOB_ROOT: Job directory with clustered instances" >&2
    exit 1
fi

JOB_ROOT="$1"

echo "INFO: Creating visualization files (LAZ to LAS conversion)"
echo "========================================="

# Create visualization directory
VIZ_DIR="$JOB_ROOT/visualization"
mkdir -p "$VIZ_DIR"

# Find all cluster files
CLUSTER_FILES=()
while IFS= read -r -d '' file; do
    CLUSTER_FILES+=("$file")
done < <(find "$JOB_ROOT/chunks" -name "cluster_*.laz" -print0 2>/dev/null)

if [[ ${#CLUSTER_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No cluster files found" >&2
    echo "       Run clustering first" >&2
    exit 1
fi

echo "INFO: Found ${#CLUSTER_FILES[@]} cluster files to convert"

CONVERTED_COUNT=0
TOTAL_POINTS=0

# Process each cluster file
for CLUSTER_FILE in "${CLUSTER_FILES[@]}"; do
    # Extract path components
    # e.g., chunks/cloud_point_part_1/classes/02-Ground/instances/cluster_1.laz
    RELATIVE_PATH=${CLUSTER_FILE#$JOB_ROOT/}
    
    # Create directory structure: chunk_name/class_name/
    IFS='/' read -ra PATH_PARTS <<< "$RELATIVE_PATH"
    CHUNK_NAME="${PATH_PARTS[1]}"          # cloud_point_part_1
    CLASS_NAME="${PATH_PARTS[3]}"          # 02-Ground
    CLUSTER_FILENAME="${PATH_PARTS[5]}"    # cluster_1.laz
    
    # Create output directory
    OUTPUT_DIR="$VIZ_DIR/$CHUNK_NAME/$CLASS_NAME"
    mkdir -p "$OUTPUT_DIR"
    
    # Convert LAZ to LAS
    CLUSTER_NAME=$(basename "$CLUSTER_FILENAME" .laz)
    OUTPUT_FILE="$OUTPUT_DIR/${CLUSTER_NAME}.las"
    
    echo "INFO: Converting $CHUNK_NAME/$CLASS_NAME/$CLUSTER_FILENAME"
    
    # Simple conversion using pdal translate
    if pdal translate "$CLUSTER_FILE" "$OUTPUT_FILE" >/dev/null 2>&1; then
        # Get point count for summary
        POINT_COUNT=$(pdal info "$OUTPUT_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
        
        echo "  ✓ Created: $OUTPUT_FILE ($POINT_COUNT points)"
        CONVERTED_COUNT=$((CONVERTED_COUNT + 1))
        TOTAL_POINTS=$((TOTAL_POINTS + POINT_COUNT))
    else
        echo "  ✗ Failed to convert: $CLUSTER_FILE"
    fi
done

# Create summary index
INDEX_FILE="$VIZ_DIR/index.txt"
echo "LiDAR Cluster Visualization Files" > "$INDEX_FILE"
echo "Generated on: $(date)" >> "$INDEX_FILE"
echo "=========================================" >> "$INDEX_FILE"
echo "" >> "$INDEX_FILE"

# Group by chunk and class
find "$VIZ_DIR" -name "*.las" | sort | while read -r las_file; do
    relative_path=${las_file#$VIZ_DIR/}
    point_count=$(pdal info "$las_file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
    printf "%-50s %10s points\n" "$relative_path" "$point_count" >> "$INDEX_FILE"
done

# Create a simple HTML index for easy browsing
HTML_INDEX="$VIZ_DIR/index.html"
cat > "$HTML_INDEX" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>LiDAR Cluster Visualization</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
        .chunk { background-color: #e6f3ff; font-weight: bold; }
        .class { background-color: #f0f8f0; }
    </style>
</head>
<body>
    <h1>LiDAR Cluster Visualization Files</h1>
    <p>Generated on: <code>$(date)</code></p>
    
    <h2>Summary</h2>
    <ul>
        <li>Total cluster files: <strong>$CONVERTED_COUNT</strong></li>
        <li>Total points: <strong>$TOTAL_POINTS</strong></li>
        <li>File format: LAS (uncompressed for visualization)</li>
    </ul>
    
    <h2>File Structure</h2>
    <table>
        <tr>
            <th>File Path</th>
            <th>Points</th>
            <th>Description</th>
        </tr>
EOF

# Add file entries to HTML
find "$VIZ_DIR" -name "*.las" | sort | while read -r las_file; do
    relative_path=${las_file#$VIZ_DIR/}
    point_count=$(pdal info "$las_file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
    
    # Extract components for description
    IFS='/' read -ra PATH_PARTS <<< "$relative_path"
    chunk_name="${PATH_PARTS[0]}"
    class_name="${PATH_PARTS[1]}"
    cluster_file="${PATH_PARTS[2]}"
    
    description=""
    case "$class_name" in
        *Ground*) description="Ground surface patch" ;;
        *Building*) description="Individual building structure" ;;
        *Vegetation*) description="Vegetation cluster (tree/bush)" ;;
        *Bridge*) description="Bridge segment" ;;
        *Wire*) description="Power line infrastructure" ;;
        *Rail*) description="Railway element" ;;
        *Road*) description="Road surface" ;;
        *Water*) description="Water feature" ;;
        *) description="Object instance" ;;
    esac
    
    cat >> "$HTML_INDEX" << EOF
        <tr>
            <td><code>$relative_path</code></td>
            <td>$point_count</td>
            <td>$description</td>
        </tr>
EOF
done

cat >> "$HTML_INDEX" << 'EOF'
    </table>
    
    <h2>Usage Instructions</h2>
    <p>These LAS files can be opened with LiDAR visualization software such as:</p>
    <ul>
        <li><strong>CloudCompare</strong> - Free, cross-platform</li>
        <li><strong>PDAL View</strong> - Command line viewer</li>
        <li><strong>LAStools</strong> - Commercial LiDAR toolkit</li>
        <li><strong>QGIS</strong> - With point cloud plugins</li>
        <li><strong>MeshLab</strong> - 3D mesh processing</li>
    </ul>
    
    <p>Each file represents a separate clustered object instance from the original point cloud.</p>
</body>
</html>
EOF

echo ""
echo "========================================="
echo "VISUALIZATION CREATION COMPLETE"
echo "========================================="
echo "Files converted: $CONVERTED_COUNT"
echo "Total points: $TOTAL_POINTS"
echo ""
echo "Visualization directory: $VIZ_DIR"
echo "File index: $INDEX_FILE"
echo "HTML index: $HTML_INDEX"
echo ""
echo "Directory structure:"
echo "$VIZ_DIR/"
echo "├── index.html                    # Web-based file browser"
echo "├── index.txt                     # Text file listing"
echo "└── chunk_name/"
echo "    └── class_name/"
echo "        ├── cluster_1.las         # Individual object instances"
echo "        ├── cluster_2.las"
echo "        └── ..."
echo ""
echo "Open the HTML index in a web browser to browse all files:"
echo "  firefox $HTML_INDEX"
echo "========================================="