#!/bin/bash

# Stage 3: Cluster each class file using Euclidean or DBSCAN algorithms
# Usage: ./stage3_cluster.sh JOB_ROOT ALGO [PARAM1] [PARAM2]
#   ALGO: euclidean or dbscan
#   For euclidean: PARAM1=tolerance, PARAM2=min_points
#   For dbscan: PARAM1=eps, PARAM2=min_points

set -euo pipefail

# Check arguments
if [[ $# -lt 2 ]]; then
    echo "ERROR: Usage: $0 JOB_ROOT ALGO [PARAM1] [PARAM2]" >&2
    echo "  JOB_ROOT: Job directory from stages 1 & 2" >&2
    echo "  ALGO: euclidean or dbscan" >&2
    echo "  For euclidean: PARAM1=tolerance (e.g., 1.0), PARAM2=min_points (e.g., 300)" >&2
    echo "  For dbscan: PARAM1=eps (e.g., 1.0), PARAM2=min_points (e.g., 10)" >&2
    exit 1
fi

JOB_ROOT="$1"
ALGO="$2"
PARAM1="${3:-}"
PARAM2="${4:-}"

# Validate algorithm
if [[ "$ALGO" != "euclidean" && "$ALGO" != "dbscan" ]]; then
    echo "ERROR: Algorithm must be 'euclidean' or 'dbscan', got: $ALGO" >&2
    exit 1
fi

# Set default parameters if not provided
if [[ "$ALGO" == "euclidean" ]]; then
    TOLERANCE="${PARAM1:-1.0}"
    MIN_POINTS="${PARAM2:-300}"
    echo "INFO: Using Euclidean clustering with tolerance=$TOLERANCE, min_points=$MIN_POINTS"
elif [[ "$ALGO" == "dbscan" ]]; then
    EPS="${PARAM1:-1.0}"
    MIN_POINTS="${PARAM2:-10}"
    echo "INFO: Using DBSCAN clustering with eps=$EPS, min_points=$MIN_POINTS"
fi

MANIFEST="$JOB_ROOT/manifest.json"

# Validate job root and manifest
if [[ ! -d "$JOB_ROOT" ]]; then
    echo "ERROR: Job root directory not found: $JOB_ROOT" >&2
    exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: Manifest not found: $MANIFEST" >&2
    echo "       Run stages 1 and 2 first" >&2
    exit 1
fi

# Validate PDAL is available
if ! command -v pdal >/dev/null 2>&1; then
    echo "ERROR: pdal command not found. Please install PDAL >= 2.6" >&2
    exit 1
fi

# Template paths
TEMPLATE_DIR="$(dirname "$0")/templates"
CLUSTER_TEMPLATE="$TEMPLATE_DIR/cluster_${ALGO}.json"

if [[ ! -f "$CLUSTER_TEMPLATE" ]]; then
    echo "ERROR: Template not found: $CLUSTER_TEMPLATE" >&2
    exit 1
fi

echo "INFO: Starting Stage 3 - Clustering with $ALGO algorithm"

# Find all class directories
CLASSES_DIR="$JOB_ROOT/classes"
if [[ ! -d "$CLASSES_DIR" ]]; then
    echo "ERROR: Classes directory not found: $CLASSES_DIR" >&2
    echo "       Run stage 2 first" >&2
    exit 1
fi

# Get list of class directories with class.laz files
CLASS_DIRS=()
while IFS= read -r -d '' dir; do
    if [[ -f "$dir/class.laz" ]]; then
        CLASS_DIRS+=("$dir")
    fi
done < <(find "$CLASSES_DIR" -maxdepth 1 -type d -name "*-*" -print0 2>/dev/null)

if [[ ${#CLASS_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: No class directories with class.laz files found" >&2
    echo "       Run stage 2 first" >&2
    exit 1
fi

echo "INFO: Found ${#CLASS_DIRS[@]} class(es) to cluster"

# Process each class
TOTAL_CLUSTERS=0
PROCESSED_CLASSES=0

for CLASS_DIR in "${CLASS_DIRS[@]}"; do
    CLASS_NAME=$(basename "$CLASS_DIR")
    CLASS_FILE="$CLASS_DIR/class.laz"
    
    echo "INFO: Processing class: $CLASS_NAME"
    
    # Check if class file has sufficient points
    POINT_COUNT=$(pdal info "$CLASS_FILE" --summary 2>/dev/null | grep -o '"count": [0-9]*' | head -1 | grep -o '[0-9]*' || echo "0")
    
    if [[ $POINT_COUNT -lt ${MIN_POINTS:-10} ]]; then
        echo "INFO: Skipping $CLASS_NAME - insufficient points ($POINT_COUNT < ${MIN_POINTS:-10})"
        continue
    fi
    
    echo "INFO: Clustering $POINT_COUNT points in class: $CLASS_NAME"
    
    # Create instances directory
    INSTANCES_DIR="$CLASS_DIR/instances"
    mkdir -p "$INSTANCES_DIR"
    
    # Create working pipeline by substituting template
    WORKING_PIPELINE="$CLASS_DIR/cluster_pipeline.json"
    
    if [[ "$ALGO" == "euclidean" ]]; then
        sed -e "s|CLASS_DIR|$CLASS_DIR|g" \
            -e "s|\"TOL\"|$TOLERANCE|g" \
            -e "s|\"MINPTS\"|$MIN_POINTS|g" \
            "$CLUSTER_TEMPLATE" > "$WORKING_PIPELINE"
    else # dbscan
        sed -e "s|CLASS_DIR|$CLASS_DIR|g" \
            -e "s|\"EPS\"|$EPS|g" \
            -e "s|\"MINPTS\"|$MIN_POINTS|g" \
            "$CLUSTER_TEMPLATE" > "$WORKING_PIPELINE"
    fi
    
    # Validate pipeline
    echo "INFO: Validating clustering pipeline for $CLASS_NAME..."
    if ! pdal pipeline --validate "$WORKING_PIPELINE" >/dev/null 2>&1; then
        echo "ERROR: Pipeline validation failed for: $CLASS_NAME" >&2
        rm -f "$WORKING_PIPELINE"
        continue
    fi
    
    # Execute clustering pipeline
    echo "INFO: Executing clustering pipeline for $CLASS_NAME..."
    METADATA_FILE="$CLASS_DIR/instance_metrics.json"
    
    if ! pdal pipeline "$WORKING_PIPELINE" --metadata "$METADATA_FILE"; then
        echo "ERROR: Clustering pipeline failed for: $CLASS_NAME" >&2
        rm -f "$WORKING_PIPELINE"
        continue
    fi
    
    # Count generated clusters (excluding cluster 0 which is noise in DBSCAN)
    if [[ "$ALGO" == "dbscan" ]]; then
        # For DBSCAN, cluster 0 represents noise points
        CLUSTER_COUNT=$(find "$INSTANCES_DIR" -name "cluster_*.laz" ! -name "cluster_0.laz" 2>/dev/null | wc -l)
        NOISE_FILE="$INSTANCES_DIR/cluster_0.laz"
        if [[ -f "$NOISE_FILE" ]]; then
            echo "INFO: Found noise points file: cluster_0.laz"
        fi
    else
        # For Euclidean, all clusters are valid (ClusterID starts at 1)
        CLUSTER_COUNT=$(find "$INSTANCES_DIR" -name "cluster_*.laz" 2>/dev/null | wc -l)
    fi
    
    echo "INFO: Generated $CLUSTER_COUNT cluster(s) for class: $CLASS_NAME"
    
    # Extract cluster statistics from metadata
    python3 << EOF
import json
import os

metadata_file = '$METADATA_FILE'
instances_dir = '$INSTANCES_DIR'
class_name = '$CLASS_NAME'
algo = '$ALGO'

try:
    with open(metadata_file, 'r') as f:
        metadata = json.load(f)
    
    # Find stats from filters.stats stage
    stats_data = None
    for stage in metadata.get('stages', []):
        if stage.get('type') == 'filters.stats':
            stats_data = stage.get('metadata', {})
            break
    
    if stats_data and 'ClusterID' in stats_data:
        cluster_stats = {}
        cluster_enum = stats_data['ClusterID'].get('enum', {})
        
        # Get statistics for other dimensions
        x_stats = stats_data.get('X', {})
        y_stats = stats_data.get('Y', {})
        z_stats = stats_data.get('Z', {})
        
        # Calculate per-cluster statistics
        for cluster_id_str, count in cluster_enum.items():
            cluster_id = int(cluster_id_str)
            
            # Skip noise cluster for DBSCAN if desired in summary
            if algo == 'dbscan' and cluster_id == 0:
                continue
                
            cluster_stats[cluster_id] = {
                'cluster_id': cluster_id,
                'point_count': count,
                'is_noise': cluster_id == 0 if algo == 'dbscan' else False
            }
        
        # Write cluster summary
        summary = {
            'class_name': class_name,
            'algorithm': algo,
            'total_clusters': len([c for c in cluster_stats.keys() if not cluster_stats[c]['is_noise']]),
            'clusters': list(cluster_stats.values()),
            'parameters': {}
        }
        
        if algo == 'euclidean':
            summary['parameters'] = {'tolerance': $TOLERANCE, 'min_points': $MIN_POINTS}
        else:
            summary['parameters'] = {'eps': $EPS, 'min_points': $MIN_POINTS}
        
        summary_file = os.path.join(instances_dir, 'cluster_summary.json')
        with open(summary_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        print(f"INFO: Cluster summary written to: {summary_file}")
        
except Exception as e:
    print(f"WARNING: Could not extract cluster statistics: {e}")
EOF
    
    TOTAL_CLUSTERS=$((TOTAL_CLUSTERS + CLUSTER_COUNT))
    PROCESSED_CLASSES=$((PROCESSED_CLASSES + 1))
    
    # Clean up working pipeline
    rm -f "$WORKING_PIPELINE"
    
    echo "INFO: Completed clustering for class: $CLASS_NAME"
done

# Update manifest with stage 3 results
python3 << EOF
import json
import os
import glob

# Read current manifest
with open('$MANIFEST', 'r') as f:
    manifest = json.load(f)

# Add stage 3 info
manifest['stage3'] = {
    'timestamp': '$(date -Iseconds)',
    'algorithm': '$ALGO',
    'parameters': {},
    'processed_classes': $PROCESSED_CLASSES,
    'total_clusters': $TOTAL_CLUSTERS,
    'class_results': []
}

if '$ALGO' == 'euclidean':
    manifest['stage3']['parameters'] = {'tolerance': $TOLERANCE, 'min_points': $MIN_POINTS}
else:
    manifest['stage3']['parameters'] = {'eps': $EPS, 'min_points': $MIN_POINTS}

# Find all class directories with instances
for class_dir in sorted(glob.glob(os.path.join('$CLASSES_DIR', '*-*'))):
    if os.path.isdir(class_dir):
        instances_dir = os.path.join(class_dir, 'instances')
        if os.path.exists(instances_dir):
            cluster_files = glob.glob(os.path.join(instances_dir, 'cluster_*.laz'))
            if cluster_files:
                manifest['stage3']['class_results'].append({
                    'class_dir': class_dir,
                    'instances_dir': instances_dir,
                    'cluster_count': len(cluster_files),
                    'cluster_files': sorted(cluster_files),
                    'summary_file': os.path.join(instances_dir, 'cluster_summary.json'),
                    'metrics_file': os.path.join(class_dir, 'instance_metrics.json')
                })

# Write updated manifest
with open('$MANIFEST', 'w') as f:
    json.dump(manifest, f, indent=2)
EOF

echo ""
echo "SUCCESS: Stage 3 completed"
echo "INFO: Algorithm used: $ALGO"
if [[ "$ALGO" == "euclidean" ]]; then
    echo "INFO: Parameters: tolerance=$TOLERANCE, min_points=$MIN_POINTS"
else
    echo "INFO: Parameters: eps=$EPS, min_points=$MIN_POINTS"
fi
echo "INFO: Classes processed: $PROCESSED_CLASSES"
echo "INFO: Total clusters generated: $TOTAL_CLUSTERS"
echo "INFO: Instance files stored in: */instances/"
echo "INFO: Manifest updated: $MANIFEST"