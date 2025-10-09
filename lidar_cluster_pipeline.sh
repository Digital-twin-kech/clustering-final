#!/bin/bash

# LiDAR Clustering Pipeline - Main orchestrator script
# Runs the complete 3-stage pipeline for LiDAR point cloud clustering
# 
# Usage: ./lidar_cluster_pipeline.sh [OPTIONS] INPUT_FILES...
#
# Options:
#   -j, --job-root DIR     Job output directory (default: out/job-YYYYMMDDHHMMSS)
#   -a, --algorithm ALGO   Clustering algorithm: euclidean|dbscan (default: euclidean)
#   -t, --tolerance VAL    Euclidean tolerance or DBSCAN eps (default: 1.0)
#   -m, --min-points NUM   Minimum points for clustering (default: 300 for euclidean, 10 for dbscan)
#   -s, --stage NUM        Run only specific stage(s): 1,2,3 or 1-3 (default: all stages)
#   -v, --verbose          Enable verbose output
#   -h, --help             Show this help

set -euo pipefail

# Default parameters
DEFAULT_JOB_ROOT=""
DEFAULT_ALGORITHM="euclidean"
DEFAULT_TOLERANCE="1.0"
DEFAULT_MIN_POINTS_EUCLIDEAN="300"
DEFAULT_MIN_POINTS_DBSCAN="10"
DEFAULT_STAGES="1,2,3"
VERBOSE=false

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to show help
show_help() {
    cat << EOF
LiDAR Clustering Pipeline

DESCRIPTION:
    Robust 3-stage pipeline for processing LiDAR point clouds:
    Stage 1: Split large files into ~10M point chunks
    Stage 2: Auto-discover and separate point classes
    Stage 3: Cluster each class using Euclidean or DBSCAN algorithms

USAGE:
    $0 [OPTIONS] INPUT_FILES...

OPTIONS:
    -j, --job-root DIR     Job output directory (default: out/job-YYYYMMDDHHMMSS)
    -a, --algorithm ALGO   Clustering algorithm: euclidean|dbscan (default: euclidean)
    -t, --tolerance VAL    Euclidean tolerance or DBSCAN eps (default: 1.0)
    -m, --min-points NUM   Minimum points for clustering (default: 300 for euclidean, 10 for dbscan)
    -s, --stage NUM        Run specific stages: 1,2,3 or ranges like 1-3 (default: 1,2,3)
    -v, --verbose          Enable verbose output
    -h, --help             Show this help

EXAMPLES:
    # Basic usage - process all stages with defaults
    $0 data/cloud1.laz data/cloud2.laz

    # Custom job directory and DBSCAN clustering
    $0 -j results/my_job -a dbscan -t 0.5 -m 20 data/*.laz

    # Run only stages 2 and 3 (assumes stage 1 already completed)
    $0 -j existing_job -s 2,3 -a euclidean

    # Verbose output with custom parameters
    $0 -v -a euclidean -t 2.0 -m 500 data/large_cloud.laz

OUTPUT STRUCTURE:
    \$JOB_ROOT/
      manifest.json                    # Pipeline execution manifest
      chunks/                          # Stage 1 output
        <src-basename>/
          part_*.laz                   # ~10M point chunks
      classes/                         # Stage 2 output  
        <classCode>-<ClassName>/
          class.laz                    # All points of this class
          metrics.json                 # Class-level statistics
          instances/                   # Stage 3 output
            cluster_*.laz              # Individual cluster instances
            cluster_summary.json       # Per-cluster statistics

REQUIREMENTS:
    - PDAL >= 2.6 with CLI tools
    - Python 3 for metadata processing
    - Sufficient disk space for intermediate files

EOF
}

# Function for verbose logging
log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "VERBOSE: $*" >&2
    fi
}

# Function to validate stage specification
validate_stages() {
    local stage_spec="$1"
    local valid_stages=(1 2 3)
    
    # Replace ranges like 1-3 with explicit list
    stage_spec=$(echo "$stage_spec" | sed 's/1-3/1,2,3/g' | sed 's/2-3/2,3/g' | sed 's/1-2/1,2/g')
    
    # Split by comma and validate each stage
    IFS=',' read -ra STAGES <<< "$stage_spec"
    for stage in "${STAGES[@]}"; do
        stage=$(echo "$stage" | tr -d ' ')
        if [[ ! " ${valid_stages[@]} " =~ " ${stage} " ]]; then
            echo "ERROR: Invalid stage '$stage'. Valid stages: 1, 2, 3" >&2
            return 1
        fi
    done
    
    echo "$stage_spec"
}

# Parse command line arguments
TEMP=$(getopt -o j:a:t:m:s:vh --long job-root:,algorithm:,tolerance:,min-points:,stage:,verbose,help -n "$0" -- "$@")
if [[ $? != 0 ]]; then exit 1; fi
eval set -- "$TEMP"

JOB_ROOT="$DEFAULT_JOB_ROOT"
ALGORITHM="$DEFAULT_ALGORITHM"
TOLERANCE="$DEFAULT_TOLERANCE"
MIN_POINTS=""
STAGES="$DEFAULT_STAGES"

while true; do
    case "$1" in
        -j|--job-root)
            JOB_ROOT="$2"
            shift 2
            ;;
        -a|--algorithm)
            ALGORITHM="$2"
            if [[ "$ALGORITHM" != "euclidean" && "$ALGORITHM" != "dbscan" ]]; then
                echo "ERROR: Algorithm must be 'euclidean' or 'dbscan'" >&2
                exit 1
            fi
            shift 2
            ;;
        -t|--tolerance)
            TOLERANCE="$2"
            shift 2
            ;;
        -m|--min-points)
            MIN_POINTS="$2"
            shift 2
            ;;
        -s|--stage)
            STAGES=$(validate_stages "$2") || exit 1
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "ERROR: Unknown option $1" >&2
            exit 1
            ;;
    esac
done

# Remaining arguments are input files
INPUT_FILES=("$@")

# Set default min_points based on algorithm if not specified
if [[ -z "$MIN_POINTS" ]]; then
    if [[ "$ALGORITHM" == "euclidean" ]]; then
        MIN_POINTS="$DEFAULT_MIN_POINTS_EUCLIDEAN"
    else
        MIN_POINTS="$DEFAULT_MIN_POINTS_DBSCAN"
    fi
fi

# Set default job root if not specified
if [[ -z "$JOB_ROOT" ]]; then
    JOB_ROOT="out/job-$(date +%Y%m%d%H%M%S)"
fi

# Validate inputs for stage 1
IFS=',' read -ra STAGE_ARRAY <<< "$STAGES"
if [[ " ${STAGE_ARRAY[@]} " =~ " 1 " ]]; then
    if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
        echo "ERROR: No input files specified for stage 1" >&2
        echo "Use --help for usage information" >&2
        exit 1
    fi
    
    # Validate input files exist
    for file in "${INPUT_FILES[@]}"; do
        if [[ ! -f "$file" ]]; then
            echo "ERROR: Input file not found: $file" >&2
            exit 1
        fi
        
        # Check file extension
        if [[ ! "$file" =~ \.(las|laz)$ ]]; then
            echo "ERROR: Input file must be LAS or LAZ format: $file" >&2
            exit 1
        fi
    done
fi

# Validate PDAL installation
if ! command -v pdal >/dev/null 2>&1; then
    echo "ERROR: pdal command not found. Please install PDAL >= 2.6" >&2
    exit 1
fi

# Get PDAL version for informational purposes
PDAL_VERSION=$(pdal --version 2>/dev/null | head -n1 || echo "unknown")

# Show configuration
echo "========================================="
echo "LiDAR Clustering Pipeline Configuration"
echo "========================================="
echo "PDAL Version: $PDAL_VERSION"
echo "Job Root: $JOB_ROOT"
echo "Stages to run: $STAGES"
echo "Algorithm: $ALGORITHM"
if [[ "$ALGORITHM" == "euclidean" ]]; then
    echo "Tolerance: $TOLERANCE"
else
    echo "Eps: $TOLERANCE"
fi
echo "Min Points: $MIN_POINTS"
if [[ " ${STAGE_ARRAY[@]} " =~ " 1 " ]]; then
    echo "Input Files: ${#INPUT_FILES[@]} file(s)"
    log_verbose "Input files: ${INPUT_FILES[*]}"
fi
echo "Verbose: $VERBOSE"
echo "========================================="

# Create job root directory
mkdir -p "$JOB_ROOT"
echo "INFO: Created job directory: $JOB_ROOT"

# Initialize pipeline start time
PIPELINE_START=$(date +%s)

# Execute requested stages
for stage in "${STAGE_ARRAY[@]}"; do
    stage=$(echo "$stage" | tr -d ' ')
    STAGE_START=$(date +%s)
    
    echo ""
    echo "========================================="
    echo "STAGE $stage: Starting at $(date)"
    echo "========================================="
    
    case "$stage" in
        1)
            log_verbose "Executing: $SCRIPT_DIR/stage1_split.sh \"$JOB_ROOT\" \"${INPUT_FILES[@]}\""
            if "$SCRIPT_DIR/stage1_split.sh" "$JOB_ROOT" "${INPUT_FILES[@]}"; then
                STAGE_END=$(date +%s)
                STAGE_DURATION=$((STAGE_END - STAGE_START))
                echo "SUCCESS: Stage 1 completed in ${STAGE_DURATION}s"
            else
                echo "ERROR: Stage 1 failed" >&2
                exit 1
            fi
            ;;
        2)
            log_verbose "Executing: $SCRIPT_DIR/stage2_classes.sh \"$JOB_ROOT\""
            if "$SCRIPT_DIR/stage2_classes.sh" "$JOB_ROOT"; then
                STAGE_END=$(date +%s)
                STAGE_DURATION=$((STAGE_END - STAGE_START))
                echo "SUCCESS: Stage 2 completed in ${STAGE_DURATION}s"
            else
                echo "ERROR: Stage 2 failed" >&2
                exit 1
            fi
            ;;
        3)
            log_verbose "Executing: $SCRIPT_DIR/stage3_cluster.sh \"$JOB_ROOT\" \"$ALGORITHM\" \"$TOLERANCE\" \"$MIN_POINTS\""
            if "$SCRIPT_DIR/stage3_cluster.sh" "$JOB_ROOT" "$ALGORITHM" "$TOLERANCE" "$MIN_POINTS"; then
                STAGE_END=$(date +%s)
                STAGE_DURATION=$((STAGE_END - STAGE_START))
                echo "SUCCESS: Stage 3 completed in ${STAGE_DURATION}s"
            else
                echo "ERROR: Stage 3 failed" >&2
                exit 1
            fi
            ;;
        *)
            echo "ERROR: Unknown stage: $stage" >&2
            exit 1
            ;;
    esac
done

# Pipeline completion summary
PIPELINE_END=$(date +%s)
PIPELINE_DURATION=$((PIPELINE_END - PIPELINE_START))

echo ""
echo "========================================="
echo "PIPELINE COMPLETED SUCCESSFULLY"
echo "========================================="
echo "Total Duration: ${PIPELINE_DURATION}s"
echo "Job Directory: $JOB_ROOT"
echo "Manifest: $JOB_ROOT/manifest.json"

# Show output summary if all stages were run
if [[ "$STAGES" == "1,2,3" ]] || [[ "$STAGES" == "1-3" ]]; then
    echo ""
    echo "Output Summary:"
    if [[ -f "$JOB_ROOT/manifest.json" ]]; then
        python3 << EOF
import json
import os
import glob

try:
    with open('$JOB_ROOT/manifest.json', 'r') as f:
        manifest = json.load(f)
    
    # Stage 1 summary
    if 'stage1' in manifest:
        chunk_count = sum(info.get('chunk_count', 0) for info in manifest['stage1'].get('chunks', {}).values())
        print(f"  Chunks created: {chunk_count}")
    
    # Stage 2 summary  
    if 'stage2' in manifest:
        class_count = len(manifest['stage2'].get('extracted_classes', []))
        print(f"  Classes extracted: {class_count}")
    
    # Stage 3 summary
    if 'stage3' in manifest:
        total_clusters = manifest['stage3'].get('total_clusters', 0)
        processed_classes = manifest['stage3'].get('processed_classes', 0)
        print(f"  Classes clustered: {processed_classes}")
        print(f"  Total clusters: {total_clusters}")
        print(f"  Algorithm: {manifest['stage3'].get('algorithm', 'unknown')}")
        
        params = manifest['stage3'].get('parameters', {})
        if params:
            param_str = ', '.join(f"{k}={v}" for k, v in params.items())
            print(f"  Parameters: {param_str}")

except Exception as e:
    print(f"  Could not read manifest summary: {e}")
EOF
    fi
fi

echo ""
echo "Use the following to inspect results:"
echo "  View manifest: cat $JOB_ROOT/manifest.json | python3 -m json.tool"
echo "  List chunks: find $JOB_ROOT/chunks -name '*.laz'"
echo "  List classes: find $JOB_ROOT/classes -name 'class.laz'"
echo "  List clusters: find $JOB_ROOT/classes -name 'cluster_*.laz'"
echo "========================================="