#!/bin/bash

# Stage 3: Cluster each class file using Euclidean or DBSCAN algorithms
# Usage: ./stage3_fixed.sh JOB_ROOT ALGO [PARAM1] [PARAM2]

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
SKIPPED_CLASSES=0

for CLASS_DIR in "${CLASS_DIRS[@]}"; do
    CLASS_NAME=$(basename "$CLASS_DIR")
    CLASS_FILE="$CLASS_DIR/class.laz"
    
    echo "INFO: Processing class: $CLASS_NAME"
    
    # Check if class file has sufficient points using proper method
    POINT_COUNT=$(pdal info "$CLASS_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
    
    if [[ $POINT_COUNT -lt ${MIN_POINTS:-10} ]]; then
        echo "INFO: Skipping $CLASS_NAME - insufficient points ($POINT_COUNT < ${MIN_POINTS:-10})"
        SKIPPED_CLASSES=$((SKIPPED_CLASSES + 1))
        continue
    fi
    
    echo "INFO: Clustering $POINT_COUNT points in class: $CLASS_NAME"
    
    # Create instances directory
    INSTANCES_DIR="$CLASS_DIR/instances"
    mkdir -p "$INSTANCES_DIR"
    
    # Create clustering pipeline directly (avoid template substitution issues)
    WORKING_PIPELINE="$CLASS_DIR/cluster_pipeline.json"
    
    if [[ "$ALGO" == "euclidean" ]]; then
        cat > "$WORKING_PIPELINE" << EOF
{
  "pipeline": [
    {
      "type": "readers.las",
      "filename": "$CLASS_FILE"
    },
    {
      "type": "filters.cluster",
      "tolerance": $TOLERANCE,
      "min_points": $MIN_POINTS,
      "is3d": true
    },
    {
      "type": "filters.groupby",
      "dimension": "ClusterID"
    },
    {
      "type": "filters.stats",
      "dimensions": "X,Y,Z,Intensity,ClusterID"
    },
    {
      "type": "filters.info"
    },
    {
      "type": "writers.las",
      "filename": "$INSTANCES_DIR/cluster_#.laz",
      "compression": true,
      "forward": "all"
    }
  ]
}
EOF
    else # dbscan
        cat > "$WORKING_PIPELINE" << EOF
{
  "pipeline": [
    {
      "type": "readers.las",
      "filename": "$CLASS_FILE"
    },
    {
      "type": "filters.dbscan",
      "eps": $EPS,
      "min_points": $MIN_POINTS
    },
    {
      "type": "filters.groupby",
      "dimension": "ClusterID"
    },
    {
      "type": "filters.stats",
      "dimensions": "X,Y,Z,Intensity,ClusterID"
    },
    {
      "type": "filters.info"
    },
    {
      "type": "writers.las",
      "filename": "$INSTANCES_DIR/cluster_#.laz",
      "compression": true,
      "forward": "all"
    }
  ]
}
EOF
    fi
    
    # Validate pipeline
    echo "INFO: Validating clustering pipeline for $CLASS_NAME..."
    if ! pdal pipeline --validate "$WORKING_PIPELINE" >/dev/null 2>&1; then
        echo "ERROR: Pipeline validation failed for: $CLASS_NAME" >&2
        rm -f "$WORKING_PIPELINE"
        continue
    fi
    
    # Execute clustering pipeline with timeout
    echo "INFO: Executing clustering pipeline for $CLASS_NAME (this may take a while)..."
    METADATA_FILE="$CLASS_DIR/instance_metrics.json"
    
    if timeout 1200 pdal pipeline "$WORKING_PIPELINE" --metadata "$METADATA_FILE" >/dev/null 2>&1; then
        
        # Count generated clusters
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
        
        echo "SUCCESS: ✓ Generated $CLUSTER_COUNT cluster(s) for class: $CLASS_NAME"
        
        # Create cluster summary
        python3 << EOF
import json
import os
import glob

class_name = "$CLASS_NAME"
instances_dir = "$INSTANCES_DIR"
algo = "$ALGO"
point_count = $POINT_COUNT
cluster_count = $CLUSTER_COUNT

# Get list of cluster files
cluster_files = sorted(glob.glob(os.path.join(instances_dir, "cluster_*.laz")))

summary = {
    'class_name': class_name,
    'algorithm': algo,
    'input_points': point_count,
    'total_clusters': cluster_count,
    'cluster_files': cluster_files,
    'parameters': {}
}

if algo == 'euclidean':
    summary['parameters'] = {'tolerance': $TOLERANCE, 'min_points': $MIN_POINTS}
else:
    summary['parameters'] = {'eps': ${EPS:-0}, 'min_points': $MIN_POINTS}

summary_file = os.path.join(instances_dir, 'cluster_summary.json')
with open(summary_file, 'w') as f:
    json.dump(summary, f, indent=2)

print(f"INFO: Cluster summary written to: {summary_file}")
EOF
        
        TOTAL_CLUSTERS=$((TOTAL_CLUSTERS + CLUSTER_COUNT))
        PROCESSED_CLASSES=$((PROCESSED_CLASSES + 1))
        
    else
        echo "ERROR: Clustering pipeline failed or timed out for: $CLASS_NAME" >&2
    fi
    
    # Clean up working pipeline
    rm -f "$WORKING_PIPELINE"
    
    echo "INFO: Completed processing for class: $CLASS_NAME"
    echo ""
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
stage3_info = {
    'timestamp': '$(date -Iseconds)',
    'algorithm': '$ALGO',
    'parameters': {},
    'processed_classes': $PROCESSED_CLASSES,
    'skipped_classes': $SKIPPED_CLASSES,
    'total_clusters': $TOTAL_CLUSTERS,
    'class_results': []
}

if '$ALGO' == 'euclidean':
    stage3_info['parameters'] = {'tolerance': $TOLERANCE, 'min_points': $MIN_POINTS}
else:
    stage3_info['parameters'] = {'eps': $EPS, 'min_points': $MIN_POINTS}

# Find all class directories with instances
for class_dir in sorted(glob.glob(os.path.join('$CLASSES_DIR', '*-*'))):
    if os.path.isdir(class_dir):
        instances_dir = os.path.join(class_dir, 'instances')
        if os.path.exists(instances_dir):
            cluster_files = glob.glob(os.path.join(instances_dir, 'cluster_*.laz'))
            if cluster_files:
                stage3_info['class_results'].append({
                    'class_dir': class_dir,
                    'class_name': os.path.basename(class_dir),
                    'instances_dir': instances_dir,
                    'cluster_count': len(cluster_files),
                    'cluster_files': sorted(cluster_files),
                    'summary_file': os.path.join(instances_dir, 'cluster_summary.json'),
                    'metrics_file': os.path.join(class_dir, 'instance_metrics.json')
                })

manifest['stage3'] = stage3_info

# Write updated manifest
with open('$MANIFEST', 'w') as f:
    json.dump(manifest, f, indent=2)
EOF

echo "========================================="
echo "STAGE 3 CLUSTERING COMPLETE"
echo "========================================="
echo "Algorithm used: $ALGO"
if [[ "$ALGO" == "euclidean" ]]; then
    echo "Parameters: tolerance=$TOLERANCE, min_points=$MIN_POINTS"
else
    echo "Parameters: eps=$EPS, min_points=$MIN_POINTS"
fi
echo "Classes processed: $PROCESSED_CLASSES"
echo "Classes skipped: $SKIPPED_CLASSES"
echo "Total clusters generated: $TOTAL_CLUSTERS"
echo ""

# Show results per class
if [[ $PROCESSED_CLASSES -gt 0 ]]; then
    echo "Clustering results by class:"
    find "$CLASSES_DIR" -name "cluster_summary.json" | sort | while read -r summary_file; do
        python3 << EOF
import json
with open('$summary_file', 'r') as f:
    data = json.load(f)
class_name = data['class_name']
input_points = data['input_points']
cluster_count = data['total_clusters']
print(f"  {class_name:30} {input_points:>10} points → {cluster_count:>6} clusters")
EOF
    done
    
    echo ""
    echo "Instance files stored in: */instances/"
    echo "Total cluster files: $(find "$CLASSES_DIR" -name "cluster_*.laz" | wc -l)"
else
    echo "No classes were processed!"
fi

echo "Manifest updated: $MANIFEST"
echo "========================================="