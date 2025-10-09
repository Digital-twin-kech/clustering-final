#!/bin/bash

# Stage 3: Cluster classes within each chunk separately (memory-efficient)
# Usage: ./stage3_per_chunk.sh JOB_ROOT ALGO [PARAM1] [PARAM2]

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

# Set default parameters
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

echo "INFO: Starting per-chunk clustering with $ALGO algorithm"

# Find all chunk directories with classes
CHUNK_DIRS=()
while IFS= read -r -d '' dir; do
    if [[ -d "$dir/classes" ]]; then
        CHUNK_DIRS+=("$dir")
    fi
done < <(find "$JOB_ROOT/chunks" -maxdepth 1 -type d -print0 2>/dev/null)

if [[ ${#CHUNK_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: No chunk directories with classes found" >&2
    echo "       Run stage2_per_chunk.sh first" >&2
    exit 1
fi

echo "INFO: Found ${#CHUNK_DIRS[@]} chunk(s) with classes to cluster"

TOTAL_CLUSTERS=0
PROCESSED_CLASSES=0
PROCESSED_CHUNKS=0

# Process each chunk separately
for CHUNK_DIR in "${CHUNK_DIRS[@]}"; do
    CHUNK_NAME=$(basename "$CHUNK_DIR")
    CLASSES_DIR="$CHUNK_DIR/classes"
    
    echo ""
    echo "================================================="
    echo "Processing chunk: $CHUNK_NAME"
    echo "================================================="
    
    # Find class directories in this chunk
    CLASS_DIRS=()
    while IFS= read -r -d '' dir; do
        if [[ -f "$dir/class.laz" ]]; then
            CLASS_DIRS+=("$dir")
        fi
    done < <(find "$CLASSES_DIR" -maxdepth 1 -type d -name "*-*" -print0 2>/dev/null)
    
    if [[ ${#CLASS_DIRS[@]} -eq 0 ]]; then
        echo "INFO: No classes found in chunk $CHUNK_NAME"
        continue
    fi
    
    echo "INFO: Found ${#CLASS_DIRS[@]} class(es) in chunk $CHUNK_NAME"
    
    CHUNK_CLUSTERS=0
    CHUNK_PROCESSED=0
    
    # Process each class in this chunk
    for CLASS_DIR in "${CLASS_DIRS[@]}"; do
        CLASS_NAME=$(basename "$CLASS_DIR")
        CLASS_FILE="$CLASS_DIR/class.laz"
        
        echo "INFO: Clustering $CLASS_NAME in chunk $CHUNK_NAME..."
        
        # Get point count
        POINT_COUNT=$(pdal info "$CLASS_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
        
        if [[ $POINT_COUNT -lt ${MIN_POINTS:-10} ]]; then
            echo "  Skipping $CLASS_NAME - insufficient points ($POINT_COUNT < ${MIN_POINTS:-10})"
            continue
        fi
        
        echo "  Processing $POINT_COUNT points..."
        
        # Create instances directory
        INSTANCES_DIR="$CLASS_DIR/instances"
        mkdir -p "$INSTANCES_DIR"
        
        # Create clustering pipeline
        PIPELINE_FILE="$CLASS_DIR/cluster_pipeline.json"
        
        if [[ "$ALGO" == "euclidean" ]]; then
            cat > "$PIPELINE_FILE" << EOF
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
            cat > "$PIPELINE_FILE" << EOF
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
        
        # Execute clustering
        METADATA_FILE="$CLASS_DIR/instance_metrics.json"
        
        if timeout 300 pdal pipeline "$PIPELINE_FILE" --metadata "$METADATA_FILE" >/dev/null 2>&1; then
            
            # Count clusters
            if [[ "$ALGO" == "dbscan" ]]; then
                CLUSTER_COUNT=$(find "$INSTANCES_DIR" -name "cluster_*.laz" ! -name "cluster_0.laz" 2>/dev/null | wc -l)
            else
                CLUSTER_COUNT=$(find "$INSTANCES_DIR" -name "cluster_*.laz" 2>/dev/null | wc -l)
            fi
            
            if [[ $CLUSTER_COUNT -gt 0 ]]; then
                echo "  ✓ Generated $CLUSTER_COUNT cluster(s)"
                
                # Create summary
                python3 << EOF
import json
import os
import glob

class_name = "$CLASS_NAME"
chunk_name = "$CHUNK_NAME"
instances_dir = "$INSTANCES_DIR"
algo = "$ALGO"
point_count = $POINT_COUNT
cluster_count = $CLUSTER_COUNT

cluster_files = sorted(glob.glob(os.path.join(instances_dir, "cluster_*.laz")))

summary = {
    'chunk_name': chunk_name,
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
EOF
                
                CHUNK_CLUSTERS=$((CHUNK_CLUSTERS + CLUSTER_COUNT))
                CHUNK_PROCESSED=$((CHUNK_PROCESSED + 1))
                
            else
                echo "  ✗ No clusters generated"
                rm -rf "$INSTANCES_DIR"
            fi
        else
            echo "  ✗ Clustering failed or timed out"
            rm -rf "$INSTANCES_DIR"
        fi
        
        # Clean up pipeline
        rm -f "$PIPELINE_FILE"
    done
    
    echo "INFO: Chunk $CHUNK_NAME completed: $CHUNK_PROCESSED classes processed, $CHUNK_CLUSTERS total clusters"
    
    if [[ $CHUNK_PROCESSED -gt 0 ]]; then
        PROCESSED_CHUNKS=$((PROCESSED_CHUNKS + 1))
        PROCESSED_CLASSES=$((PROCESSED_CLASSES + CHUNK_PROCESSED))
        TOTAL_CLUSTERS=$((TOTAL_CLUSTERS + CHUNK_CLUSTERS))
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

# Add stage 3 info
stage3_info = {
    'timestamp': '$(date -Iseconds)',
    'approach': 'per_chunk',
    'algorithm': '$ALGO',
    'parameters': {},
    'processed_chunks': $PROCESSED_CHUNKS,
    'processed_classes': $PROCESSED_CLASSES,
    'total_clusters': $TOTAL_CLUSTERS,
    'chunk_results': []
}

if '$ALGO' == 'euclidean':
    stage3_info['parameters'] = {'tolerance': $TOLERANCE, 'min_points': $MIN_POINTS}
else:
    stage3_info['parameters'] = {'eps': ${EPS:-0}, 'min_points': $MIN_POINTS}

# Find all chunk results
chunk_dirs = glob.glob(os.path.join('$JOB_ROOT', 'chunks', '*'))
for chunk_dir in sorted(chunk_dirs):
    if os.path.isdir(chunk_dir):
        classes_dir = os.path.join(chunk_dir, 'classes')
        if os.path.exists(classes_dir):
            chunk_name = os.path.basename(chunk_dir)
            
            chunk_result = {
                'chunk_name': chunk_name,
                'chunk_dir': chunk_dir,
                'classes_dir': classes_dir,
                'class_results': []
            }
            
            class_dirs = glob.glob(os.path.join(classes_dir, '*-*'))
            for class_dir in sorted(class_dirs):
                if os.path.isdir(class_dir):
                    instances_dir = os.path.join(class_dir, 'instances')
                    if os.path.exists(instances_dir):
                        cluster_files = glob.glob(os.path.join(instances_dir, 'cluster_*.laz'))
                        if cluster_files:
                            chunk_result['class_results'].append({
                                'class_name': os.path.basename(class_dir),
                                'class_dir': class_dir,
                                'instances_dir': instances_dir,
                                'cluster_count': len(cluster_files),
                                'cluster_files': sorted(cluster_files)
                            })
            
            if chunk_result['class_results']:
                stage3_info['chunk_results'].append(chunk_result)

manifest['stage3'] = stage3_info

# Write updated manifest
with open('$MANIFEST', 'w') as f:
    json.dump(manifest, f, indent=2)
EOF

echo ""
echo "========================================="
echo "PER-CHUNK CLUSTERING COMPLETE"
echo "========================================="
echo "Algorithm used: $ALGO"
if [[ "$ALGO" == "euclidean" ]]; then
    echo "Parameters: tolerance=$TOLERANCE, min_points=$MIN_POINTS"
else
    echo "Parameters: eps=$EPS, min_points=$MIN_POINTS"
fi
echo "Chunks processed: $PROCESSED_CHUNKS"
echo "Classes processed: $PROCESSED_CLASSES"
echo "Total clusters generated: $TOTAL_CLUSTERS"
echo ""
echo "Results:"
if [[ $TOTAL_CLUSTERS -gt 0 ]]; then
    find "$JOB_ROOT/chunks" -name "cluster_summary.json" | sort | while read -r summary_file; do
        python3 << PYEOF
import json
with open('$summary_file', 'r') as f:
    data = json.load(f)
chunk_name = data['chunk_name']
class_name = data['class_name']
input_points = data['input_points']
cluster_count = data['total_clusters']
print(f"  {chunk_name}/{class_name:20} {input_points:>8} points → {cluster_count:>3} clusters")
PYEOF
    done
else
    echo "  No clusters were generated"
fi
echo ""
echo "Manifest updated: $MANIFEST"
echo "========================================="
