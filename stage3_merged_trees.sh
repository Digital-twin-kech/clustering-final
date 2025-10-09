#!/bin/bash

# Stage 3: Fixed clustering with merged Trees and TreeTrunks
# Usage: ./stage3_merged_trees.sh JOB_ROOT [ALGO]

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

# Classes to MERGE before clustering
MERGE_TREES="7_Trees 40_TreeTrunks"

# Define class-specific clustering parameters (only for classes we want to cluster)
declare -A CLASS_TOLERANCE=(
    [16_Mobile4w]=0.4    [17_Stationary4w]=0.4    [15_2Wheel]=0.3
    [7_Trees_Combined]=1.2    [8_OtherVegetation]=1.2    
    [9_TrafficLights]=0.3    [10_TrafficSigns]=0.3    [12_Masts]=0.5       
    [11_Wires]=0.5       [13_Pedestrians]=0.5     [5_TrafficIslands]=1.5
)

declare -A CLASS_MIN_POINTS=(
    [16_Mobile4w]=50     [17_Stationary4w]=50     [15_2Wheel]=20
    [7_Trees_Combined]=150    [8_OtherVegetation]=60    
    [9_TrafficLights]=20     [10_TrafficSigns]=20     [12_Masts]=30        
    [11_Wires]=30        [13_Pedestrians]=30      [5_TrafficIslands]=100
)

CHUNKS_DIR="$JOB_ROOT/chunks"

if [[ ! -d "$CHUNKS_DIR" ]]; then
    echo "ERROR: Chunks directory not found: $CHUNKS_DIR" >&2
    exit 1
fi

echo "INFO: Tree-merging clustering with class combinations"
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

# Function to merge tree classes
merge_tree_classes() {
    local FILTERED_DIR="$1"
    local MERGED_FILE="$2"
    
    local TREE_FILES=()
    for tree_class in $MERGE_TREES; do
        if [[ -f "$FILTERED_DIR/${tree_class}.laz" ]]; then
            TREE_FILES+=("$FILTERED_DIR/${tree_class}.laz")
        fi
    done
    
    if [[ ${#TREE_FILES[@]} -eq 0 ]]; then
        return 1
    fi
    
    # Create merge pipeline
    local MERGE_PIPELINE="/tmp/merge_trees_$(basename "$(dirname "$MERGED_FILE")").json"
    
    # Build pipeline JSON with multiple inputs
    cat > "$MERGE_PIPELINE" << 'EOF'
{
  "pipeline": [
EOF
    
    # Add each tree file as input
    for i in "${!TREE_FILES[@]}"; do
        echo "    {" >> "$MERGE_PIPELINE"
        echo "      \"type\": \"readers.las\"," >> "$MERGE_PIPELINE"
        echo "      \"filename\": \"${TREE_FILES[$i]}\"" >> "$MERGE_PIPELINE"
        if [[ $i -lt $((${#TREE_FILES[@]} - 1)) ]]; then
            echo "    }," >> "$MERGE_PIPELINE"
        else
            echo "    }," >> "$MERGE_PIPELINE"
        fi
    done
    
    # Add merge and output
    cat >> "$MERGE_PIPELINE" << EOF
    {
      "type": "filters.merge"
    },
    {
      "type": "writers.las",
      "filename": "$MERGED_FILE",
      "compression": true,
      "forward": "all"
    }
  ]
}
EOF
    
    # Execute merge
    if pdal pipeline "$MERGE_PIPELINE" >/dev/null 2>&1; then
        local merged_points=$(pdal info "$MERGED_FILE" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
        echo "      ✅ Merged tree classes: $merged_points points"
        rm -f "$MERGE_PIPELINE"
        return 0
    else
        echo "      ✗ Failed to merge tree classes"
        rm -f "$MERGE_PIPELINE"
        return 1
    fi
}

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
    
    # Step 1: Handle tree merging first
    MERGED_TREES_FILE="$FILTERED_DIR/7_Trees_Combined.laz"
    echo ""
    echo "  🌳 Merging tree classes (Trees + TreeTrunks)..."
    
    if merge_tree_classes "$FILTERED_DIR" "$MERGED_TREES_FILE"; then
        # Add merged file to processing list
        CLASS_FILES+=("$MERGED_TREES_FILE")
        echo "      ✓ Created merged tree file: 7_Trees_Combined.laz"
    else
        echo "      ⚠ No tree classes to merge"
    fi
    
    # Step 2: Process each class file (including merged trees)
    for CLASS_FILE in "${CLASS_FILES[@]}"; do
        CLASS_FILENAME=$(basename "$CLASS_FILE" .laz)
        CLASS_DIR="$FILTERED_DIR/$CLASS_FILENAME"
        
        # Check if this class should be skipped
        if [[ " $SKIP_CLASSES " == *" $CLASS_FILENAME "* ]]; then
            echo "  ⏭️  Skipping $CLASS_FILENAME (large surface class)"
            continue
        fi
        
        # Skip individual tree classes if we have the merged version
        if [[ "$CLASS_FILENAME" == "7_Trees" || "$CLASS_FILENAME" == "40_TreeTrunks" ]] && [[ -f "$MERGED_TREES_FILE" ]]; then
            echo "  🔗 Skipping $CLASS_FILENAME (merged into 7_Trees_Combined)"
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
        
        # Clean up existing clustering results for this class
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
        
        # Step 3: Create clustered file with ClusterID
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
            
            # Step 4: Get cluster statistics
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
                VALID_MIN=0
            else
                VALID_MIN=1
            fi
            
            if [[ $MAX_CLUSTER_ID -ge $VALID_MIN ]]; then
                echo "        INFO: Found clusters from $MIN_CLUSTER_ID to $MAX_CLUSTER_ID"
                
                CLASS_INSTANCES=0
                # Step 5: Extract each cluster
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
  "is_merged_class": $(if [[ "$CLASS_FILENAME" == "7_Trees_Combined" ]]; then echo "true"; else echo "false"; fi),
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
echo "TREE-MERGED CLUSTERING COMPLETE"
echo "========================================="
echo "Algorithm: $ALGO"
echo "Classes processed: $TOTAL_CLASSES_PROCESSED"
echo "Total instances created: $TOTAL_INSTANCES_CREATED"
echo ""
echo "🌳 Tree Merging: 7_Trees + 40_TreeTrunks → 7_Trees_Combined"
echo "🎯 Instance Naming: ClassName_001.laz, ClassName_002.laz, etc."
echo "⏭️  Skipped Classes: $SKIP_CLASSES"
echo "📊 Clustered Object Types: Vehicles, Combined-Trees, Infrastructure, People"
echo "========================================"