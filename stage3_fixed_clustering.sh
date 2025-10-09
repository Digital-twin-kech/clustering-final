#!/bin/bash

# Stage 3: Fixed clustering with proper ClusterID handling  
# Usage: ./stage3_fixed_clustering.sh JOB_ROOT [ALGO]

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "ERROR: Usage: $0 JOB_ROOT [ALGO]" >&2
    echo "  JOB_ROOT: Job directory containing organized chunks" >&2
    echo "  ALGO: euclidean or dbscan (default: euclidean)" >&2
    exit 1
fi

JOB_ROOT="$1"
ALGO="${2:-euclidean}"

# Define classes to SKIP (large surfaces that don't need instance clustering)
SKIP_CLASSES="2_Roads 6_Buildings 18_Noise 4_OtherGround 1_Other 3_Sidewalks"

# Define class-specific clustering parameters (only for classes we want to cluster)
declare -A CLASS_TOLERANCE=(
    [16_Mobile4w]=0.4    [17_Stationary4w]=0.4    [15_2Wheel]=0.3
    [7_Trees]=1.0        [40_TreeTrunks]=0.8      [8_OtherVegetation]=1.2    
    [9_TrafficLights]=0.3    [10_TrafficSigns]=0.3    [12_Masts]=0.5       
    [11_Wires]=0.5       [13_Pedestrians]=0.5     [5_TrafficIslands]=1.5
)

declare -A CLASS_MIN_POINTS=(
    [16_Mobile4w]=50     [17_Stationary4w]=50     [15_2Wheel]=20
    [7_Trees]=100        [40_TreeTrunks]=80       [8_OtherVegetation]=60    
    [9_TrafficLights]=20     [10_TrafficSigns]=20     [12_Masts]=30        
    [11_Wires]=30        [13_Pedestrians]=30      [5_TrafficIslands]=100
)

CHUNKS_DIR="$JOB_ROOT/chunks"

if [[ ! -d "$CHUNKS_DIR" ]]; then
    echo "ERROR: Chunks directory not found: $CHUNKS_DIR" >&2
    exit 1
fi

echo "INFO: Fixed clustering with proper ClusterID handling"
echo "Algorithm: $ALGO"
echo ""
echo "INFO: Cleaning previous clustering results..."
find "$CHUNKS_DIR" -name "*_*" -type d -path "*/filtred_by_classes/*" -exec rm -rf {} \; 2>/dev/null || true
echo "✓ Previous clustering results cleaned"
echo "========================================="

# Find all chunk directories
CHUNK_DIRS=($(find "$CHUNKS_DIR" -name "*_chunk" -type d | sort))

echo "INFO: Found ${#CHUNK_DIRS[@]} chunk directories to process"

TOTAL_CLASSES_PROCESSED=0
TOTAL_INSTANCES_CREATED=0

# Process each chunk
for CHUNK_DIR in "${CHUNK_DIRS[@]}"; do
    CHUNK_NAME=$(basename "$CHUNK_DIR")
    FILTERED_DIR="$CHUNK_DIR/compressed/filtred_by_classes"
    
    echo ""
    echo "================================================="
    echo "Processing: $CHUNK_NAME"
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
        
        # Check if this class should be skipped
        if [[ " $SKIP_CLASSES " == *" $CLASS_FILENAME "* ]]; then
            echo "  ⏭️  Skipping $CLASS_FILENAME (large surface class)"
            continue
        fi
        
        # Get class-specific parameters
        TOLERANCE=${CLASS_TOLERANCE[$CLASS_FILENAME]:-1.0}
        MIN_POINTS=${CLASS_MIN_POINTS[$CLASS_FILENAME]:-100}
        
        echo ""
        echo "  Processing: $CLASS_FILENAME"
        echo "    Parameters: tolerance=${TOLERANCE}m, min_points=$MIN_POINTS"
        
        # Get point count
        POINT_COUNT=$(pdal info "$CLASS_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
        
        if [[ $POINT_COUNT -lt $MIN_POINTS ]]; then
            echo "      ⚠ Skipping - insufficient points ($POINT_COUNT < $MIN_POINTS)"
            continue
        fi
        
        echo "      INFO: Processing $POINT_COUNT points..."
        
        # Clean up existing clustering results
        if [[ -d "$CLASS_DIR" ]]; then
            rm -rf "$CLASS_DIR"
        fi
        
        # Create class directory structure
        MAIN_CLUSTER_DIR="$CLASS_DIR/main_cluster"
        INSTANCES_DIR="$CLASS_DIR/instances"
        TEMP_CLUSTERED_FILE="/tmp/clustered_${CHUNK_NAME}_${CLASS_FILENAME}.laz"
        
        mkdir -p "$MAIN_CLUSTER_DIR"
        mkdir -p "$INSTANCES_DIR"
        
        # Copy original class file to main_cluster
        cp "$CLASS_FILE" "$MAIN_CLUSTER_DIR/"
        
        # Step 1: Create clustered file with ClusterID
        CLUSTERING_PIPELINE="/tmp/cluster_${CHUNK_NAME}_${CLASS_FILENAME}.json"
        
        if [[ "$ALGO" == "euclidean" ]]; then
            cat > "$CLUSTERING_PIPELINE" << EOF
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
      "type": "writers.las",
      "filename": "$TEMP_CLUSTERED_FILE",
      "compression": true,
      "extra_dims": "ClusterID=uint32",
      "forward": "all"
    }
  ]
}
EOF
        else # dbscan
            cat > "$CLUSTERING_PIPELINE" << EOF
{
  "pipeline": [
    {
      "type": "readers.las",
      "filename": "$CLASS_FILE"
    },
    {
      "type": "filters.dbscan",
      "eps": $TOLERANCE,
      "min_points": $MIN_POINTS
    },
    {
      "type": "writers.las",
      "filename": "$TEMP_CLUSTERED_FILE",
      "compression": true,
      "extra_dims": "ClusterID=uint32",
      "forward": "all"
    }
  ]
}
EOF
        fi
        
        # Execute clustering
        if timeout 600 pdal pipeline "$CLUSTERING_PIPELINE" >/dev/null 2>&1; then
            
            # Step 2: Get cluster statistics
            CLUSTER_STATS=$(pdal info "$TEMP_CLUSTERED_FILE" --all 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
stats = data.get('stats', {}).get('statistic', [])
for stat in stats:
    if stat.get('name') == 'ClusterID':
        print(f\"{int(stat.get('minimum', 0))} {int(stat.get('maximum', 0))}\")
        break
" 2>/dev/null || echo "0 0")
            
            MIN_CLUSTER_ID=$(echo $CLUSTER_STATS | cut -d' ' -f1)
            MAX_CLUSTER_ID=$(echo $CLUSTER_STATS | cut -d' ' -f2)
            
            # Determine valid cluster range based on algorithm
            if [[ "$ALGO" == "dbscan" ]]; then
                # DBSCAN: valid clusters are >= 0, -1 is noise
                VALID_MIN=0
            else
                # Euclidean: valid clusters are >= 1, 0 is unclustered
                VALID_MIN=1
            fi
            
            if [[ $MAX_CLUSTER_ID -ge $VALID_MIN ]]; then
                echo "        INFO: Found clusters from $MIN_CLUSTER_ID to $MAX_CLUSTER_ID"
                
                CLASS_INSTANCES=0
                # Step 3: Extract each cluster
                for CLUSTER_ID in $(seq $VALID_MIN $MAX_CLUSTER_ID); do
                    INSTANCE_NAME="${CLASS_FILENAME}_$(printf "%03d" $((CLUSTER_ID - $VALID_MIN + 1)))"
                    INSTANCE_FILE="$INSTANCES_DIR/${INSTANCE_NAME}.laz"
                    
                    # Create extraction pipeline for this cluster
                    EXTRACT_PIPELINE="/tmp/extract_${CHUNK_NAME}_${CLASS_FILENAME}_${CLUSTER_ID}.json"
                    cat > "$EXTRACT_PIPELINE" << EOF
{
  "pipeline": [
    {
      "type": "readers.las",
      "filename": "$TEMP_CLUSTERED_FILE"
    },
    {
      "type": "filters.range",
      "limits": "ClusterID[$CLUSTER_ID:$CLUSTER_ID]"
    },
    {
      "type": "writers.las",
      "filename": "$INSTANCE_FILE",
      "compression": true,
      "extra_dims": "ClusterID=uint32",
      "forward": "all"
    }
  ]
}
EOF
                    
                    # Extract this cluster
                    if timeout 60 pdal pipeline "$EXTRACT_PIPELINE" >/dev/null 2>&1; then
                        if [[ -f "$INSTANCE_FILE" ]]; then
                            cluster_points=$(pdal info "$INSTANCE_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                            
                            if [[ $cluster_points -gt 0 ]]; then
                                echo "          ✓ $INSTANCE_NAME ($cluster_points points)"
                                CLASS_INSTANCES=$((CLASS_INSTANCES + 1))
                            else
                                rm -f "$INSTANCE_FILE"
                            fi
                        fi
                    fi
                    
                    rm -f "$EXTRACT_PIPELINE"
                done
                
                if [[ $CLASS_INSTANCES -gt 0 ]]; then
                    # Create class summary
                    cat > "$CLASS_DIR/clustering_summary.json" << EOF
{
  "chunk_name": "$CHUNK_NAME",
  "class_name": "$CLASS_FILENAME",
  "algorithm": "$ALGO",
  "parameters": {
    "tolerance": $TOLERANCE,
    "min_points": $MIN_POINTS
  },
  "input_points": $POINT_COUNT,
  "instances_created": $CLASS_INSTANCES,
  "cluster_range": "$MIN_CLUSTER_ID to $MAX_CLUSTER_ID",
  "processing_timestamp": "$(date -Iseconds)"
}
EOF
                    
                    echo "        ✅ Created $CLASS_INSTANCES instances for $CLASS_FILENAME"
                    TOTAL_CLASSES_PROCESSED=$((TOTAL_CLASSES_PROCESSED + 1))
                    TOTAL_INSTANCES_CREATED=$((TOTAL_INSTANCES_CREATED + CLASS_INSTANCES))
                else
                    echo "        ⚠ No valid instances created"
                    rm -rf "$CLASS_DIR"
                fi
            else
                echo "        ⚠ No valid clusters found"
                rm -rf "$CLASS_DIR"
            fi
        else
            echo "        ✗ Clustering failed or timed out"
            rm -rf "$CLASS_DIR"
        fi
        
        # Clean up temp files
        rm -f "$CLUSTERING_PIPELINE" "$TEMP_CLUSTERED_FILE"
    done
done

echo ""
echo "========================================="
echo "FIXED CLUSTERING COMPLETE"
echo "========================================="
echo "Algorithm: $ALGO"
echo "Classes processed: $TOTAL_CLASSES_PROCESSED"
echo "Total instances created: $TOTAL_INSTANCES_CREATED"
echo ""
echo "🎯 Instance Naming: ClassName_001.laz, ClassName_002.laz, etc."
echo "⏭️  Skipped Classes: $SKIP_CLASSES"
echo "📊 Clustered Object Types: Vehicles, Trees, Infrastructure, People"
echo "========================================"