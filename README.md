# LiDAR Clustering Pipeline

A robust, production-ready bash + JSON pipeline for LiDAR point cloud processing using PDAL CLI. Designed for processing large LAS/LAZ files through a 3-stage pipeline: chunking, class separation, and clustering.

## Features

- 🚀 **Scalable**: Handles files up to 50M+ points via intelligent chunking
- 🎯 **Deterministic**: Reproducible results with stable output structure  
- 🔧 **Configurable**: Support for Euclidean and DBSCAN clustering algorithms
- 📊 **Comprehensive**: Generates detailed metrics and statistics at each stage
- ⚡ **Streaming**: Uses PDAL's streaming capabilities where possible
- 🛡️ **Robust**: Fail-fast with clear error messages and validation

## Requirements

- **PDAL >= 2.6** with CLI tools
- **Python 3** for metadata processing  
- **Linux** environment (tested on Ubuntu/CentOS)
- **Disk Space**: 2-3x input file size for intermediate files

## Quick Start

```bash
# Validate installation
./validate_pipeline.sh

# Run complete pipeline with defaults
./lidar_cluster_pipeline.sh data/cloud.laz

# Custom parameters with DBSCAN
./lidar_cluster_pipeline.sh -a dbscan -t 0.5 -m 20 data/*.laz

# Run only specific stages
./lidar_cluster_pipeline.sh -j existing_job -s 2,3
```

## Pipeline Stages

### Stage 1: Point Count Splitting
Splits input LAS/LAZ files into chunks of ~10M points each using `filters.divider`.

**Input**: 1+ LAS/LAZ files  
**Output**: `chunks/<basename>/part_*.laz` files  
**Purpose**: Enable parallel processing of large datasets

### Stage 2: Class Discovery & Separation  
Auto-discovers point classes and physically separates each class into individual LAZ files.

**Input**: Chunk files from Stage 1  
**Output**: `classes/<code>-<name>/class.laz` + metrics  
**Purpose**: Prepare homogeneous point sets for clustering

### Stage 3: Clustering
Applies Euclidean or DBSCAN clustering to each class, generating per-instance LAZ files.

**Input**: Class files from Stage 2  
**Output**: `classes/*/instances/cluster_*.laz` + statistics  
**Purpose**: Identify individual objects/structures

## Output Structure

```
$JOB_ROOT/
├── manifest.json                     # Execution manifest & metadata
├── chunks/                           # Stage 1: Point count chunks
│   └── <src-basename>/
│       ├── part_1.laz               # ~10M points
│       ├── part_2.laz
│       └── split_metadata.json
├── classes/                          # Stage 2: Class separation
│   ├── classes_enum.json            # Discovered classes summary
│   └── <classCode>-<ClassName>/
│       ├── class.laz                # All points of this class
│       ├── metrics.json             # Class-level statistics
│       └── instances/               # Stage 3: Clustering results
│           ├── cluster_1.laz        # Individual cluster instances
│           ├── cluster_2.laz
│           ├── cluster_summary.json # Per-cluster statistics
│           └── instance_metrics.json
```

## Usage Examples

### Basic Processing
```bash
# Process single file with defaults (Euclidean clustering)
./lidar_cluster_pipeline.sh sample.laz

# Process multiple files
./lidar_cluster_pipeline.sh data/area1.laz data/area2.laz data/area3.laz
```

### Algorithm Selection
```bash
# Euclidean clustering (default)
./lidar_cluster_pipeline.sh -a euclidean -t 1.0 -m 300 data.laz

# DBSCAN clustering  
./lidar_cluster_pipeline.sh -a dbscan -t 0.5 -m 20 data.laz
```

### Partial Pipeline Execution
```bash
# Run only splitting stage
./lidar_cluster_pipeline.sh -s 1 -j my_job data/*.laz

# Run only clustering stage (assumes stages 1-2 completed)  
./lidar_cluster_pipeline.sh -s 3 -j my_job -a dbscan -t 1.0 -m 15

# Run stages 2 and 3
./lidar_cluster_pipeline.sh -s 2,3 -j existing_job
```

### Custom Job Directory
```bash
# Specify output location
./lidar_cluster_pipeline.sh -j results/forest_analysis data/forest.laz

# Time-stamped job (default behavior)
./lidar_cluster_pipeline.sh data.laz  # Creates out/job-YYYYMMDDHHMMSS/
```

## Algorithm Parameters

### Euclidean Clustering (`filters.cluster`)
- **tolerance** (`-t`): Maximum distance between points in same cluster (meters)
- **min_points** (`-m`): Minimum points required to form a cluster  
- **is3d**: Always enabled for 3D clustering

**Recommended values:**
- Buildings: `-t 0.5 -m 500`
- Vegetation: `-t 2.0 -m 300`  
- Ground: `-t 1.0 -m 1000`

### DBSCAN Clustering (`filters.dbscan`)
- **eps** (`-t`): Maximum distance between core points (meters)
- **min_points** (`-m`): Minimum points to form dense region
- **Rule of thumb**: `min_points >= 2 * dimensions` (6 for 3D)

**Recommended values:**
- Dense objects: `-t 0.3 -m 10`
- Sparse structures: `-t 1.0 -m 20`
- Large features: `-t 2.0 -m 50`

## Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-j, --job-root DIR` | Output directory | `out/job-YYYYMMDDHHMMSS` |
| `-a, --algorithm ALGO` | Clustering: `euclidean` or `dbscan` | `euclidean` |
| `-t, --tolerance VAL` | Distance parameter | `1.0` |
| `-m, --min-points NUM` | Minimum cluster points | `300` (euclidean), `10` (dbscan) |
| `-s, --stage NUM` | Stages to run: `1,2,3` or `1-3` | `1,2,3` |
| `-v, --verbose` | Enable verbose output | `false` |
| `-h, --help` | Show help | - |

## Validation & Testing

```bash
# Validate installation and templates
./validate_pipeline.sh

# Test individual stages
./stage1_split.sh test_job sample.laz
./stage2_classes.sh test_job  
./stage3_cluster.sh test_job euclidean 1.0 300
```

## Performance Guidelines

### Input File Size Recommendations
- **Small** (< 5M points): Process directly, minimal chunking benefit
- **Medium** (5-20M points): Optimal for default 10M chunk size  
- **Large** (20-50M points): Benefits significantly from chunking
- **Very Large** (> 50M points): Consider pre-processing or multiple jobs

### Memory Usage
- **Stage 1**: Low memory, streaming operation
- **Stage 2**: Moderate, loads all chunks of a class  
- **Stage 3**: High, loads entire class file for clustering

### Disk Usage
Temporary disk usage is approximately:
- **Stage 1**: 1.1x input size (compressed chunks)
- **Stage 2**: 1.5x input size (class files + chunks)  
- **Stage 3**: 2.0x input size (clusters + intermediate files)

## Troubleshooting

### Common Issues

**Error: "pdal command not found"**
```bash
# Install PDAL on Ubuntu
sudo apt-get install pdal pdal-tools

# Install PDAL on CentOS/RHEL  
sudo yum install pdal pdal-devel
```

**Error: "Pipeline validation failed"**
- Check PDAL version: `pdal --version` 
- Validate templates: `./validate_pipeline.sh`
- Ensure input files are valid LAS/LAZ

**Error: "No classes found"**  
- Verify input has Classification dimension: `pdal info input.laz`
- Check for non-zero classification codes
- Some files may have only class 0 (unclassified)

**Error: "Insufficient disk space"**
- Monitor disk usage: `df -h`  
- Clean up previous jobs: `rm -rf out/job-*`
- Use different output directory: `-j /path/to/large/disk`

### Performance Issues

**Stage 1 is slow**
- Check input file fragmentation
- Ensure sufficient I/O bandwidth
- Consider SSD storage for working directory

**Stage 2 uses too much memory**
- Reduce chunk size in Stage 1 (modify template)
- Process classes individually using `-s 3` per class

**Stage 3 clustering fails**
- Reduce tolerance/eps parameters
- Increase min_points for noisy data
- Check for degenerate point clouds (2D data, etc.)

## Technical Details

### Pipeline Templates
JSON templates in `templates/` directory:
- `split_by_points.json`: Point-count based splitting
- `class_discovery.json`: Classification enumeration  
- `class_extract.json`: Class-specific point extraction
- `cluster_euclidean.json`: Euclidean clustering pipeline
- `cluster_dbscan.json`: DBSCAN clustering pipeline

### Metadata Structure
The pipeline generates comprehensive metadata at each stage:

**manifest.json**: Complete execution log
```json
{
  "stage1": {"input_files": [...], "chunks": {...}},
  "stage2": {"extracted_classes": [...], "classes_enum_file": "..."},  
  "stage3": {"algorithm": "...", "total_clusters": N, "class_results": [...]}
}
```

**Class metrics**: Bounds, statistics, point counts per class
**Cluster metrics**: Centroids, bounds, point counts per cluster instance

### ASPRS Classification Codes
Standard point class mappings:
- 0: Never Classified, 1: Unassigned, 2: Ground
- 3: Low Vegetation, 4: Medium Vegetation, 5: High Vegetation  
- 6: Building, 9: Water, 11: Road Surface
- 14: Wire Conductor, 15: Transmission Tower

## Contributing

This pipeline uses only PDAL CLI operations and standard bash/Python for maximum compatibility. When contributing:

1. Maintain PDAL CLI-only approach (no Python PDAL bindings)
2. Ensure streaming operations where possible  
3. Add comprehensive error checking
4. Update templates and validation scripts
5. Test with various LiDAR datasets

## License

This project is provided as-is for educational and research purposes. Ensure compliance with PDAL licensing requirements.