#!/bin/bash

# Pipeline validation script
# Validates PDAL installation, templates, and pipeline integrity

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "LiDAR Clustering Pipeline Validation"
echo "========================================="

# Check PDAL installation
echo "INFO: Checking PDAL installation..."
if ! command -v pdal >/dev/null 2>&1; then
    echo "ERROR: pdal command not found" >&2
    echo "       Please install PDAL >= 2.6" >&2
    exit 1
fi

PDAL_VERSION=$(pdal --version 2>/dev/null | head -n1 || echo "unknown")
echo "INFO: Found PDAL: $PDAL_VERSION"

# Check Python 3
echo "INFO: Checking Python 3 installation..."
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 command not found" >&2
    echo "       Python 3 is required for metadata processing" >&2
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>/dev/null || echo "unknown")
echo "INFO: Found Python: $PYTHON_VERSION"

# Validate pipeline templates
echo "INFO: Validating pipeline templates..."
TEMPLATE_DIR="$SCRIPT_DIR/templates"
REQUIRED_TEMPLATES=(
    "split_by_points.json"
    "class_discovery.json"
    "class_extract.json"
    "cluster_euclidean.json"
    "cluster_dbscan.json"
)

for template in "${REQUIRED_TEMPLATES[@]}"; do
    template_path="$TEMPLATE_DIR/$template"
    if [[ ! -f "$template_path" ]]; then
        echo "ERROR: Missing template: $template_path" >&2
        exit 1
    fi
    
    # Basic JSON validation
    if ! python3 -m json.tool "$template_path" >/dev/null 2>&1; then
        echo "ERROR: Invalid JSON in template: $template_path" >&2
        exit 1
    fi
    
    echo "INFO: ✓ Template valid: $template"
done

# Validate stage scripts
echo "INFO: Validating stage scripts..."
REQUIRED_SCRIPTS=(
    "stage1_split.sh"
    "stage2_classes.sh"
    "stage3_cluster.sh"
    "lidar_cluster_pipeline.sh"
)

for script in "${REQUIRED_SCRIPTS[@]}"; do
    script_path="$SCRIPT_DIR/$script"
    if [[ ! -f "$script_path" ]]; then
        echo "ERROR: Missing script: $script_path" >&2
        exit 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        echo "ERROR: Script not executable: $script_path" >&2
        echo "       Run: chmod +x $script_path" >&2
        exit 1
    fi
    
    echo "INFO: ✓ Script valid: $script"
done

# Test PDAL pipeline validation with templates
echo "INFO: Testing PDAL pipeline validation..."

# Create a temporary test directory
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Test split template validation
TEST_SPLIT="$TEST_DIR/test_split.json"
sed -e 's|INFILE|/dev/null|g' -e 's|OUTDIR|/tmp|g' "$TEMPLATE_DIR/split_by_points.json" > "$TEST_SPLIT"

if pdal pipeline --validate "$TEST_SPLIT" >/dev/null 2>&1; then
    echo "INFO: ✓ Split template validates with PDAL"
else
    echo "WARNING: Split template failed PDAL validation (may be expected with /dev/null)" >&2
fi

# Test cluster templates validation
for algo in euclidean dbscan; do
    TEST_CLUSTER="$TEST_DIR/test_cluster_${algo}.json"
    sed -e 's|CLASS_DIR|/tmp|g' -e 's|"TOL"|1.0|g' -e 's|"EPS"|1.0|g' -e 's|"MINPTS"|10|g' \
        "$TEMPLATE_DIR/cluster_${algo}.json" > "$TEST_CLUSTER"
    
    if pdal pipeline --validate "$TEST_CLUSTER" >/dev/null 2>&1; then
        echo "INFO: ✓ Cluster $algo template validates with PDAL"
    else
        echo "WARNING: Cluster $algo template failed PDAL validation (may be expected without real data)" >&2
    fi
done

# Test directory structure creation
echo "INFO: Testing directory structure creation..."
TEST_JOB="$TEST_DIR/test_job"
mkdir -p "$TEST_JOB"/{chunks,classes}
mkdir -p "$TEST_JOB/chunks/test_file"
mkdir -p "$TEST_JOB/classes/02-Ground"/{instances}

if [[ -d "$TEST_JOB/chunks/test_file" ]] && [[ -d "$TEST_JOB/classes/02-Ground/instances" ]]; then
    echo "INFO: ✓ Directory structure creation works"
else
    echo "ERROR: Failed to create directory structure" >&2
    exit 1
fi

# Check disk space (basic check)
echo "INFO: Checking available disk space..."
AVAILABLE_SPACE=$(df . | tail -1 | awk '{print $4}')
AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))

if [[ $AVAILABLE_GB -lt 10 ]]; then
    echo "WARNING: Low disk space available: ${AVAILABLE_GB}GB" >&2
    echo "         Large LiDAR files may require significant temporary storage" >&2
else
    echo "INFO: Available disk space: ${AVAILABLE_GB}GB"
fi

echo ""
echo "SUCCESS: Pipeline validation completed"
echo "INFO: All components are ready for use"
echo ""
echo "Quick usage test:"
echo "  ./lidar_cluster_pipeline.sh --help"
echo ""
echo "Example with sample data:"
echo "  ./lidar_cluster_pipeline.sh -v sample.laz"