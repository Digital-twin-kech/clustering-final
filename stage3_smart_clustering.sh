#!/bin/bash

# Stage 3: Smart clustering with class-specific parameters for mobile mapping data
# Automatically adjusts clustering parameters based on object type
# Usage: ./stage3_smart_clustering.sh JOB_ROOT [ALGO]

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "ERROR: Usage: $0 JOB_ROOT [ALGO]" >&2
    echo "  JOB_ROOT: Job directory containing organized chunks" >&2
    echo "  ALGO: euclidean or dbscan (default: euclidean)" >&2
    echo "" >&2
    echo "Uses optimized parameters per class type:" >&2
    echo "  Vehicles (Mobile4w, Stationary4w): tolerance=0.4m, min_points=50" >&2
    echo "  Buildings: tolerance=2.0m, min_points=500" >&2
    echo "  Trees/TreeTrunks: tolerance=1.0m, min_points=100" >&2
    echo "  Small objects (Signs, Lights): tolerance=0.3m, min_points=20" >&2
    echo "  Infrastructure (Wires, Masts): tolerance=0.5m, min_points=30" >&2
    exit 1
fi

JOB_ROOT="$1"
ALGO="${2:-euclidean}"

# Define class-specific clustering parameters
declare -A CLASS_TOLERANCE=(
    # Vehicles - need tight clustering to separate individual cars
    [16_Mobile4w]=0.4
    [17_Stationary4w]=0.4
    [15_2Wheel]=0.3
    
    # Buildings - can be large, more permissive
    [6_Buildings]=2.0
    
    # Trees - medium tolerance 
    [7_Trees]=1.0
    [40_TreeTrunks]=0.8
    [8_OtherVegetation]=1.2
    
    # Small infrastructure objects
    [9_TrafficLights]=0.3
    [10_TrafficSigns]=0.3
    [12_Masts]=0.5
    [11_Wires]=0.5
    
    # People and movement
    [13_Pedestrians]=0.5
    
    # Ground surfaces - larger tolerance
    [2_Roads]=3.0
    [3_Sidewalks]=2.0
    [4_OtherGround]=2.5
    [5_TrafficIslands]=1.5
    
    # Other/Noise
    [1_Other]=1.0
    [18_Noise]=0.5
)

declare -A CLASS_MIN_POINTS=(
    # Vehicles
    [16_Mobile4w]=50
    [17_Stationary4w]=50  
    [15_2Wheel]=20
    
    # Buildings - need substantial point count
    [6_Buildings]=500
    
    # Trees
    [7_Trees]=100
    [40_TreeTrunks]=80
    [8_OtherVegetation]=60
    
    # Small objects
    [9_TrafficLights]=20
    [10_TrafficSigns]=20
    [12_Masts]=30
    [11_Wires]=30
    
    # People
    [13_Pedestrians]=30
    
    # Ground surfaces
    [2_Roads]=200
    [3_Sidewalks]=150
    [4_OtherGround]=100
    [5_TrafficIslands]=100
    
    # Other
    [1_Other]=50
    [18_Noise]=30
)

if [[ "$ALGO" != "euclidean" && "$ALGO" != "dbscan" ]]; then
    echo "ERROR: Algorithm must be 'euclidean' or 'dbscan', got: $ALGO" >&2
    exit 1
fi

CHUNKS_DIR="$JOB_ROOT/chunks"

if [[ ! -d "$CHUNKS_DIR" ]]; then
    echo "ERROR: Chunks directory not found: $CHUNKS_DIR" >&2
    exit 1
fi

echo "INFO: Starting smart clustering with class-specific parameters"
echo "Algorithm: $ALGO"
echo ""
echo "INFO: Cleaning previous clustering results..."
find "$CHUNKS_DIR" -name "*_*" -type d -path "*/filtred_by_classes/*" -exec rm -rf {} \; 2>/dev/null || true
echo "✓ Previous clustering results cleaned"
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
        
        mkdir -p "$MAIN_CLUSTER_DIR"
        mkdir -p "$INSTANCES_DIR"
        
        # Copy original class file to main_cluster
        cp "$CLASS_FILE" "$MAIN_CLUSTER_DIR/"
        
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
      "type": "filters.range",
      "limits": "ClusterID![65535:65535]"
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
      "eps": $TOLERANCE,
      "min_points": $MIN_POINTS
    },
    {
      "type": "filters.range",
      "limits": "ClusterID![0:0]"
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
        
        if timeout 600 pdal pipeline "$PIPELINE_FILE" --metadata "$METADATA_FILE" >/dev/null 2>&1; then
            
            # Count and rename clusters with unique IDs
            TEMP_CLUSTERS=($(find "$INSTANCES_DIR" -name "temp_cluster_*.laz" 2>/dev/null | sort -V))
            
            CLUSTER_COUNT=${#TEMP_CLUSTERS[@]}
            
            if [[ $CLUSTER_COUNT -gt 0 ]]; then
                echo "        INFO: Generated $CLUSTER_COUNT potential cluster(s)"
                
                CLASS_INSTANCES=0
                # Process each cluster
                for temp_file in "${TEMP_CLUSTERS[@]}"; do
                    # Check cluster point count
                    cluster_points=$(pdal info "$temp_file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
                    
                    # Use a lower threshold for final instances (half of clustering min_points)
                    INSTANCE_MIN_POINTS=$((MIN_POINTS / 2))
                    if [[ $INSTANCE_MIN_POINTS -lt 10 ]]; then
                        INSTANCE_MIN_POINTS=10
                    fi
                    
                    if [[ $cluster_points -ge $INSTANCE_MIN_POINTS ]]; then
                        # Generate instance name with class name + UID
                        CLASS_INSTANCE_ID=$((CLASS_INSTANCES + 1))
                        INSTANCE_NAME="${CLASS_FILENAME}_$(printf "%03d" $CLASS_INSTANCE_ID)"
                        NEW_FILE="$INSTANCES_DIR/${INSTANCE_NAME}.laz"
                        
                        mv "$temp_file" "$NEW_FILE"
                        echo "          ✓ $INSTANCE_NAME ($cluster_points points)"
                        
                        GLOBAL_INSTANCE_ID=$((GLOBAL_INSTANCE_ID + 1))
                        CLASS_INSTANCES=$((CLASS_INSTANCES + 1))
                    else
                        echo "          ✗ Removing small cluster ($cluster_points < $INSTANCE_MIN_POINTS points)"
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
    "tolerance": $TOLERANCE,
    "min_points": $MIN_POINTS,
    "instance_min_points": $INSTANCE_MIN_POINTS
  },
  "input_points": $POINT_COUNT,
  "instances_created": $CLASS_INSTANCES,
  "processing_timestamp": "$(date -Iseconds)"
}
EOF
                    
                    echo "        ✅ Created $CLASS_INSTANCES instances for $CLASS_FILENAME"
                    TOTAL_CLASSES_PROCESSED=$((TOTAL_CLASSES_PROCESSED + 1))
                    TOTAL_INSTANCES_CREATED=$((TOTAL_INSTANCES_CREATED + CLASS_INSTANCES))
                else
                    echo "        ⚠ No valid instances created"
                    # Clean up empty directories
                    rm -rf "$CLASS_DIR"
                fi
            else
                echo "        ⚠ No clusters generated"
                rm -rf "$CLASS_DIR"
            fi
        else
            echo "        ✗ Clustering failed or timed out"
            rm -rf "$CLASS_DIR"
        fi
        
        # Clean up pipeline file
        rm -f "$PIPELINE_FILE"
    done
done

echo ""
echo "========================================="
echo "SMART CLUSTERING COMPLETE"
echo "========================================="
echo "Algorithm: $ALGO"
echo "Classes processed: $TOTAL_CLASSES_PROCESSED"
echo "Total instances created: $TOTAL_INSTANCES_CREATED"
echo "Total chunks processed: ${#CHUNK_DIRS[@]}"

# Show class-wise results
echo ""
echo "📊 Results by Class:"
find "$CHUNKS_DIR" -name "clustering_summary.json" 2>/dev/null | while read -r summary_file; do
    python3 << 'PYEOF'
import json
import sys
import os

summary_file = sys.stdin.readline().strip()
if summary_file and os.path.exists(summary_file):
    with open(summary_file, 'r') as f:
        data = json.load(f)
    
    chunk_name = data['chunk_name']
    class_name = data['class_name']
    input_points = data['input_points']
    instances = data['instances_created']
    tolerance = data['parameters']['tolerance']
    min_points = data['parameters']['min_points']
    
    print(f"  {chunk_name:12} {class_name:20} {input_points:>8} pts → {instances:>3} instances (tol={tolerance}m)")
PYEOF << EOF
$summary_file
EOF
done

echo ""
echo "🎯 Instance Naming Convention:"
echo "  Examples: 17_Stationary4w_001.laz, 17_Stationary4w_002.laz"
echo "           6_Buildings_001.laz, 9_TrafficLights_001.laz"
echo ""
echo "📊 Class-Specific Parameters Used:"
echo "  🚗 Vehicles: 0.3-0.4m tolerance (tight for individual cars)"
echo "  🏢 Buildings: 2.0m tolerance (loose for large structures)"  
echo "  🌳 Trees: 0.8-1.2m tolerance (medium for tree clusters)"
echo "  🚦 Small objects: 0.3m tolerance (tight for signs/lights)"
echo "  🛣️  Ground surfaces: 1.5-3.0m tolerance (loose for surfaces)"
echo "========================================="