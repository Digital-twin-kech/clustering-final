# LiDAR Point Cloud Clustering Pipeline Guide

Complete step-by-step guide for processing LiDAR data from raw LAZ files to clustered object instances.

## Overview

This pipeline processes large LiDAR files through 4 stages:
1. **Stage 1**: Split large files into manageable chunks (~10M points each)
2. **Stage 2**: Extract classes from each chunk separately (memory-efficient)
3. **Stage 3**: Cluster each class within each chunk into individual object instances
4. **Stage 4**: Convert instances to LAS files for visualization

## Prerequisites

- **PDAL >= 2.6** with CLI tools
- **Python 3** for metadata processing
- **Sufficient disk space** (2-3x input file size)

## Directory Structure

After completion, you'll have:
```
out/job-YYYYMMDDHHMMSS/
├── manifest.json                     # Complete pipeline metadata
├── chunks/                           # Stage 1 output
│   ├── input_file_1/
│   │   ├── part_1.laz               # ~10M point chunks
│   │   ├── part_2.laz
│   │   ├── part_N.laz
│   │   └── classes/                 # Stage 2 output - classes from this chunk
│   │       ├── 01-Unassigned/
│   │       │   ├── class.laz        # Class points from this chunk only
│   │       │   └── instances/       # Stage 3 output - clustered objects
│   │       │       ├── cluster_1.las
│   │       │       ├── cluster_2.las
│   │       │       └── ...
│   │       ├── 03-Low_Vegetation/
│   │       │   ├── class.laz
│   │       │   └── instances/
│   │       │       ├── cluster_1.las  # Individual vegetation clusters
│   │       │       └── ...
│   │       └── ... (other classes)
│   └── input_file_2/                # Additional input files
│       └── ... (same structure)
└── visualization/                   # Stage 4 output
    └── ... (LAS files organized by chunk/class)
```

## Step-by-Step Instructions

### Step 1: Prepare Input Data

Ensure your LAS/LAZ files are accessible:
```bash
# Example input files
ls data/
# cloud_part_1.laz
# cloud_part_2.laz
```

### Step 2: Create Job Directory

```bash
# The scripts will create a timestamped job directory
JOB_ROOT="out/job-$(date +%Y%m%d%H%M%S)"
echo "Job will be created at: $JOB_ROOT"
```

### Step 3: Stage 1 - Split Large Files

Split input files into ~10M point chunks:

```bash
./stage1_split.sh "$JOB_ROOT" data/cloud_part_1.laz data/cloud_part_2.laz

# Or use the main pipeline script:
./lidar_cluster_pipeline.sh -s 1 -j "$JOB_ROOT" data/*.laz
```

**Output**: Creates chunk files in `$JOB_ROOT/chunks/`

### Step 4: Stage 2 - Per-Chunk Class Extraction

Extract classification classes from each chunk separately:

```bash
./stage2_per_chunk.sh "$JOB_ROOT"
```

**What this does**:
- Processes each chunk file individually (memory-efficient)
- Extracts 18 different classes (Ground, Building, Vegetation, etc.)
- Creates `classes/` folder in each chunk directory
- Each class contains only points from that specific chunk

**Classes extracted**:
- 01-Unassigned, 02-Ground, 03-Low_Vegetation
- 04-Medium_Vegetation, 05-High_Vegetation, 06-Building
- 07-Low_Point, 08-Reserved, 09-Water, 10-Rail
- 11-Road_Surface, 12-Reserved, 13-Wire_Guard
- 15-Transmission_Tower, 16-Wire_Structure_Connector
- 17-Bridge_Deck, 18-High_Noise, 40-Class_40

### Step 5: Stage 3 - Per-Chunk Clustering (Excluding Ground & Building)

Cluster each class into individual object instances, skipping large classes:

```bash
# Create modified clustering script that skips Ground and Building
./stage3_per_chunk_selective.sh "$JOB_ROOT" euclidean 1.0 300
```

**Modified Script Creation**:
First, create the selective clustering script:

```bash
cp stage3_per_chunk.sh stage3_per_chunk_selective.sh

# Edit the script to skip Ground and Building classes
# Add this check in the clustering loop:
```

```bash
# In the script, add this condition before clustering:
if [[ "$CLASS_NAME" =~ (02-Ground|06-Building) ]]; then
    echo "  Skipping $CLASS_NAME - excluded from clustering"
    continue
fi
```

**Alternative - Use loose parameters for large classes**:
```bash
# For faster processing of all classes including Ground/Building:
./stage3_per_chunk.sh "$JOB_ROOT" euclidean 3.0 1000
```

**What this does**:
- Clusters each class within each chunk separately
- Uses Euclidean clustering (tolerance=1.0m, min_points=300)
- Creates `instances/` folder in each class directory
- Each cluster represents an individual object (tree, building, infrastructure, etc.)

**Clustering Parameters**:
- **euclidean**: Groups points within specified tolerance distance
- **tolerance=1.0**: Points within 1 meter are grouped together
- **min_points=300**: Each cluster needs at least 300 points

### Step 6: Stage 4 - Create Visualization Files

Convert clustered instances to LAS format for easy viewing:

```bash
./create_visualization.sh "$JOB_ROOT"
```

**Output**: Creates `visualization/` directory with:
- Individual LAS files for each cluster
- HTML index for easy browsing
- Organized by chunk → class → instances

## Usage Examples

### Complete Pipeline (All Stages)
```bash
# Set job directory
JOB_ROOT="out/job-$(date +%Y%m%d%H%M%S)"

# Stage 1: Split files
./stage1_split.sh "$JOB_ROOT" data/*.laz

# Stage 2: Extract classes per chunk
./stage2_per_chunk.sh "$JOB_ROOT"

# Stage 3: Cluster (excluding Ground & Building for speed)
./stage3_per_chunk_selective.sh "$JOB_ROOT" euclidean 1.0 300

# Stage 4: Create visualization
./create_visualization.sh "$JOB_ROOT"
```

### Process Specific Input Files
```bash
# Process only specific files
./stage1_split.sh out/my_job file1.laz file2.laz

# Continue with remaining stages...
```

### Alternative Clustering Parameters
```bash
# Faster clustering (larger tolerance, more points required)
./stage3_per_chunk.sh "$JOB_ROOT" euclidean 2.0 500

# DBSCAN clustering (density-based)
./stage3_per_chunk.sh "$JOB_ROOT" dbscan 1.0 20
```

## Expected Results

### Per-Chunk Processing Benefits
- **Memory efficient**: Processes one chunk at a time
- **Scalable**: Works with any number of chunks
- **Geographic organization**: Clusters are spatially local
- **Parallel-friendly**: Could run multiple chunks simultaneously

### Typical Output Numbers
For a 50M point dataset split into 5 chunks:
- **Stage 1**: 5 chunks × ~10M points each
- **Stage 2**: ~18 classes per chunk (90 class files total)
- **Stage 3**: 100-500 clusters per chunk (500-2500 total instances)
- **Stage 4**: 500-2500 individual LAS files for visualization

### Instance Types You'll Get
- **Vegetation**: Individual trees, bushes, grass patches
- **Infrastructure**: Power towers, wire segments, rail sections
- **Structures**: Bridge segments, individual buildings (if processed)
- **Surfaces**: Road segments, water features, ground patches (if processed)
- **Utilities**: Individual utility poles, wire connectors

## Troubleshooting

### Memory Issues
- Use per-chunk approach (already implemented)
- Increase swap space if needed
- Process chunks individually

### Timeout Issues
- Increase timeout in scripts (currently 300s = 5 minutes)
- Use looser clustering parameters
- Skip very large classes temporarily

### No Clusters Generated
- Reduce `min_points` parameter
- Increase `tolerance` parameter  
- Check if class has sufficient points

## Viewing Results

### File Browsing
```bash
# View HTML index
firefox $JOB_ROOT/visualization/index.html

# List all instances
find $JOB_ROOT/chunks -name "cluster_*.las" | wc -l
```

### Point Cloud Viewers
- **CloudCompare** (recommended): Free, powerful 3D viewer
- **PDAL View**: `pdal view cluster_1.las`
- **QGIS**: With point cloud plugins
- **MeshLab**: For 3D mesh processing

## Performance Tips

### Optimal Parameters by Class Type
- **Small objects** (poles, towers): tolerance=0.5, min_points=50
- **Medium objects** (trees, vehicles): tolerance=1.0, min_points=300
- **Large objects** (buildings, ground): tolerance=2.0, min_points=1000

### Speed vs Quality Trade-offs
- **High quality**: tolerance=0.5, min_points=100 (slower, more clusters)
- **Balanced**: tolerance=1.0, min_points=300 (recommended)
- **Fast processing**: tolerance=2.0, min_points=500 (faster, fewer clusters)

---

## Summary

This pipeline efficiently processes large LiDAR datasets by:
1. ✅ **Chunking** large files for memory management
2. ✅ **Per-chunk processing** for scalability  
3. ✅ **Class separation** for semantic organization
4. ✅ **Instance clustering** for individual object extraction
5. ✅ **Visualization preparation** for easy viewing

The result is hundreds or thousands of individual 3D object instances organized by geographic location (chunk) and semantic type (class), ready for visualization and analysis.