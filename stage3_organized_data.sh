#!/bin/bash

# Stage 3: Cluster organized data structure into instances 
# Works with: part_X_chunk/compressed/filtred_by_classes/N_ClassName.laz
# Creates: N_ClassName/main_cluster/ and N_ClassName/instances/
# Usage: ./stage3_organized_data.sh JOB_ROOT [ALGO] [PARAM1] [PARAM2]

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "ERROR: Usage: $0 JOB_ROOT [ALGO] [PARAM1] [PARAM2]" >&2
    echo "  JOB_ROOT: Job directory containing organized chunks" >&2
    echo "  ALGO: euclidean or dbscan (default: euclidean)" >&2
    echo "  PARAM1: tolerance/eps (default: 1.0)" >&2
    echo "  PARAM2: min_points (default: 300 for euclidean, 10 for dbscan)" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $0 /path/to/job" >&2
    echo "  $0 /path/to/job euclidean 1.5 500" >&2
    echo "  $0 /path/to/job dbscan 1.0 10" >&2
    exit 1
fi

JOB_ROOT="$1"
ALGO="${2:-euclidean}"
PARAM1="${3:-1.0}"
PARAM2="${4:-}"

# Set algorithm-specific defaults
if [[ "$ALGO" == "euclidean" ]]; then
    TOLERANCE="$PARAM1"
    MIN_POINTS="${PARAM2:-300}"
    echo "INFO: Using Euclidean clustering with tolerance=$TOLERANCE, min_points=$MIN_POINTS"
elif [[ "$ALGO" == "dbscan" ]]; then
    EPS="$PARAM1" 
    MIN_POINTS="${PARAM2:-10}"
    echo "INFO: Using DBSCAN clustering with eps=$EPS, min_points=$MIN_POINTS"
else
    echo "ERROR: Algorithm must be 'euclidean' or 'dbscan', got: $ALGO" >&2
    exit 1
fi

CHUNKS_DIR="$JOB_ROOT/chunks"

if [[ ! -d "$CHUNKS_DIR" ]]; then
    echo "ERROR: Chunks directory not found: $CHUNKS_DIR" >&2
    exit 1
fi

echo "INFO: Starting Stage 3 clustering on organized data structure"
echo "========================================="

# Find all chunk directories
CHUNK_DIRS=($(find "$CHUNKS_DIR" -name "*_chunk" -type d | sort))

if [[ ${#CHUNK_DIRS[@]} -eq 0 ]]; then
    echo "ERROR: No chunk directories found in $CHUNKS_DIR" >&2
    exit 1
fi

echo "INFO: Found ${#CHUNK_DIRS[@]} chunk directories to process"

TOTAL_CLASSES_PROCESSED=0
TOTAL_INSTANCES_CREATED=0
GLOBAL_INSTANCE_ID=1

# Process each chunk
for CHUNK_DIR in "${CHUNK_DIRS[@]}"; do
    CHUNK_NAME=$(basename "$CHUNK_DIR")
    FILTERED_DIR="$CHUNK_DIR/compressed/filtred_by_classes"
    
    echo ""
    echo "================================================="
    echo "Processing: $CHUNK_NAME"
    echo "Filtered classes: $FILTERED_DIR"
    echo "================================================="
    
    if [[ ! -d "$FILTERED_DIR" ]]; then
        echo "  ⚠ No filtered classes directory found"
        continue
    fi
    
    # Find all class LAZ files
    CLASS_FILES=($(find "$FILTERED_DIR" -name "*_*.laz" 2>/dev/null | sort))
    
    if [[ ${#CLASS_FILES[@]} -eq 0 ]]; then
        echo "  ⚠ No class files found"
        continue
    fi
    
    echo "  INFO: Found ${#CLASS_FILES[@]} class files"
    
    # Process each class file
    for CLASS_FILE in "${CLASS_FILES[@]}"; do
        CLASS_FILENAME=$(basename "$CLASS_FILE" .laz)
        CLASS_DIR="$FILTERED_DIR/$CLASS_FILENAME"
        
        echo ""
        echo "  Processing class: $CLASS_FILENAME"
        
        # Get point count
        POINT_COUNT=$(pdal info "$CLASS_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
        
        if [[ $POINT_COUNT -lt $MIN_POINTS ]]; then
            echo "    ⚠ Skipping - insufficient points ($POINT_COUNT < $MIN_POINTS)"
            continue
        fi
        
        echo "    INFO: Processing $POINT_COUNT points..."
        
        # Create class directory structure
        MAIN_CLUSTER_DIR="$CLASS_DIR/main_cluster"
        INSTANCES_DIR="$CLASS_DIR/instances"
        
        mkdir -p "$MAIN_CLUSTER_DIR"
        mkdir -p "$INSTANCES_DIR"
        
        # Copy original class file to main_cluster
        cp "$CLASS_FILE" "$MAIN_CLUSTER_DIR/"
        echo "      ✓ Copied to main_cluster/"
        
        # Create clustering pipeline
        PIPELINE_FILE="/tmp/cluster_${CHUNK_NAME}_${CLASS_FILENAME}.json"
        
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
      "type": "filters.stats",
      "dimensions": "X,Y,Z,Intensity,ClusterID",
      "enumerate": "ClusterID"
    },
    {
      "type": "filters.info"
    },
    {
      "type": "writers.las",
      "filename": "$INSTANCES_DIR/temp_cluster_#.laz",
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
      "type": "filters.stats",
      "dimensions": "X,Y,Z,Intensity,ClusterID",
      "enumerate": "ClusterID"
    },
    {
      "type": "filters.info"
    },
    {
      "type": "writers.las",
      "filename": "$INSTANCES_DIR/temp_cluster_#.laz",
      "compression": true,
      "forward": "all"
    }
  ]
}
EOF
        fi
        
        # Execute clustering
        METADATA_FILE="$CLASS_DIR/clustering_metadata.json"
        
        if timeout 300 pdal pipeline "$PIPELINE_FILE" --metadata "$METADATA_FILE" >/dev/null 2>&1; then
            
            # Count and rename clusters with unique IDs
            TEMP_CLUSTERS=($(find "$INSTANCES_DIR" -name "temp_cluster_*.laz" | sort -V))
            
            # For DBSCAN, exclude cluster 0 (noise)
            if [[ "$ALGO" == "dbscan" ]]; then
                TEMP_CLUSTERS=($(printf '%s\n' "${TEMP_CLUSTERS[@]}" | grep -v "temp_cluster_0.laz" || true))
            fi
            
            CLUSTER_COUNT=${#TEMP_CLUSTERS[@]}
            
            if [[ $CLUSTER_COUNT -gt 0 ]]; then
                echo "      INFO: Generated $CLUSTER_COUNT cluster(s)"
                
                CLASS_INSTANCES=0
                # Rename clusters with global unique IDs
                for temp_file in "${TEMP_CLUSTERS[@]}"; do
                    # Check if cluster has minimum points
                    cluster_points=$(pdal info "$temp_file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                    
                    if [[ $cluster_points -ge $MIN_POINTS ]]; then
                        # Generate unique instance ID
                        INSTANCE_ID=$(printf "instance_%06d" $GLOBAL_INSTANCE_ID)
                        NEW_FILE="$INSTANCES_DIR/${INSTANCE_ID}.laz"
                        
                        mv "$temp_file" "$NEW_FILE"
                        echo "        ✓ $INSTANCE_ID ($cluster_points points)"
                        
                        GLOBAL_INSTANCE_ID=$((GLOBAL_INSTANCE_ID + 1))
                        CLASS_INSTANCES=$((CLASS_INSTANCES + 1))
                    else
                        echo "        ✗ Removing small cluster ($cluster_points points)"
                        rm -f "$temp_file"
                    fi
                done
                
                # Clean up any remaining temp files
                rm -f "$INSTANCES_DIR"/temp_cluster_*.laz
                
                if [[ $CLASS_INSTANCES -gt 0 ]]; then
                    # Create class summary
                    cat > "$CLASS_DIR/clustering_summary.json" << EOF
{
  "chunk_name": "$CHUNK_NAME",
  "class_name": "$CLASS_FILENAME",
  "algorithm": "$ALGO",
  "parameters": {
$(if [[ "$ALGO" == "euclidean" ]]; then
    echo "    \"tolerance\": $TOLERANCE,"
    echo "    \"min_points\": $MIN_POINTS"
else
    echo "    \"eps\": $EPS,"
    echo "    \"min_points\": $MIN_POINTS"
fi)
  },
  "input_points": $POINT_COUNT,
  "instances_created": $CLASS_INSTANCES,
  "processing_timestamp": "$(date -Iseconds)"
}
EOF
                    
                    echo "      ✓ Created $CLASS_INSTANCES instances for $CLASS_FILENAME"
                    TOTAL_CLASSES_PROCESSED=$((TOTAL_CLASSES_PROCESSED + 1))
                    TOTAL_INSTANCES_CREATED=$((TOTAL_INSTANCES_CREATED + CLASS_INSTANCES))
                else
                    echo "      ✗ No valid instances created"
                    # Clean up empty directories
                    rm -rf "$INSTANCES_DIR"
                    if [[ -d "$MAIN_CLUSTER_DIR" ]] && [[ -z "$(ls -A "$MAIN_CLUSTER_DIR")" ]]; then
                        rm -rf "$MAIN_CLUSTER_DIR"
                    fi
                    if [[ -d "$CLASS_DIR" ]] && [[ -z "$(ls -A "$CLASS_DIR")" ]]; then
                        rm -rf "$CLASS_DIR"
                    fi
                fi
            else
                echo "      ✗ No clusters generated"
                # Clean up empty directories
                rm -rf "$INSTANCES_DIR" "$MAIN_CLUSTER_DIR" "$CLASS_DIR"
            fi
        else
            echo "      ✗ Clustering failed or timed out"
            # Clean up on failure
            rm -rf "$INSTANCES_DIR" "$MAIN_CLUSTER_DIR" "$CLASS_DIR"
        fi
        
        # Clean up pipeline file
        rm -f "$PIPELINE_FILE"
    done
done

echo ""
echo "========================================="
echo "CLUSTERING COMPLETE"
echo "========================================="
echo "Algorithm: $ALGO"
if [[ "$ALGO" == "euclidean" ]]; then
    echo "Parameters: tolerance=$TOLERANCE, min_points=$MIN_POINTS"
else
    echo "Parameters: eps=$EPS, min_points=$MIN_POINTS"
fi
echo "Classes processed: $TOTAL_CLASSES_PROCESSED"
echo "Total instances created: $TOTAL_INSTANCES_CREATED"
echo "Next available instance ID: $(printf "instance_%06d" $GLOBAL_INSTANCE_ID)"

# Show final structure examples
echo ""
echo "📁 Final Structure Examples:"
find "$CHUNKS_DIR" -name "*_chunk" -type d | head -2 | while read -r chunk_dir; do
    chunk_name=$(basename "$chunk_dir")
    echo ""
    echo "$chunk_name/"
    echo "└── compressed/"
    echo "    └── filtred_by_classes/"
    
    find "$chunk_dir/compressed/filtred_by_classes" -name "*_*" -type d 2>/dev/null | head -3 | while read -r class_dir; do
        class_name=$(basename "$class_dir")
        echo "        ├── $class_name/"
        
        if [[ -d "$class_dir/main_cluster" ]]; then
            main_count=$(find "$class_dir/main_cluster" -name "*.laz" | wc -l)
            echo "        │   ├── main_cluster/ ($main_count files)"
        fi
        
        if [[ -d "$class_dir/instances" ]]; then
            instance_count=$(find "$class_dir/instances" -name "instance_*.laz" | wc -l)
            echo "        │   └── instances/ ($instance_count instances)"
            
            find "$class_dir/instances" -name "instance_*.laz" | head -3 | while read -r instance; do
                instance_name=$(basename "$instance" .laz)
                instance_points=$(pdal info "$instance" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                echo "        │       ├── $instance_name ($instance_points points)"
            done
        fi
    done
done

echo ""
echo "🎯 Usage:"
echo "  📁 main_cluster/  → Original class data"
echo "  📁 instances/     → Individual clustered objects with unique IDs"
echo "========================================="