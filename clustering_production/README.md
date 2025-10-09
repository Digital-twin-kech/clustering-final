# LiDAR Clustering Production Pipeline

## Overview

This production-ready pipeline processes large LiDAR point cloud files (LAZ format) for mobile mapping data, performing semantic class extraction and instance clustering to create individual object instances.

## Pipeline Stages

### Stage 1: Split Chunks
**Purpose**: Split large LAZ files into manageable chunks
- **Script**: `scripts/stage1_split_chunks.sh`
- **Input**: Single large LAZ file (up to 50M points)
- **Output**: Multiple chunks (~10M points each)
- **Usage**: `./stage1_split_chunks.sh input_file.laz [chunk_size]`

### Stage 2: Extract Classes
**Purpose**: Extract semantic classes from each chunk
- **Script**: `scripts/stage2_extract_classes.sh`
- **Input**: Job directory with chunks
- **Output**: Class-separated LAZ files per chunk
- **Usage**: `./stage2_extract_classes.sh /path/to/job-directory`

**Supported Classes**:
- `7_Trees` - Tree vegetation
- `10_TrafficSigns` - Traffic signs
- `11_Wires` - Wire/cable infrastructure
- `12_Masts` - Poles, masts, posts
- `15_2Wheel` - Motorcycles, bicycles
- `16_Mobile4w` - Cars, mobile 4-wheel vehicles
- `17_Stationary4w` - Parked cars, stationary vehicles
- `40_TreeTrunks` - Tree trunk segments

### Stage 3: Cluster Instances
**Purpose**: Apply EUCLIDEAN clustering to create individual object instances
- **Script**: `scripts/stage3_cluster_instances.sh`
- **Input**: Job directory with extracted classes
- **Output**: Individual instance LAZ files per class
- **Usage**: `./stage3_cluster_instances.sh /path/to/job-directory [class_name]`

**Clustering Parameters**:
```
Class            Tolerance    Min Points
12_Masts         0.5m        30
15_2Wheel        0.5m        30
16_Mobile4w      1.0m        50
17_Stationary4w  1.0m        50
7_Trees          1.5m        50
40_TreeTrunks    1.0m        30
```

### Stage 4: Clean Instances
**Purpose**: Apply quality filtering and merge over-segmented instances
- **Script**: `scripts/stage4_clean_instances.sh`
- **Input**: Job directory with clustered instances
- **Output**: High-quality filtered instances
- **Usage**: `./stage4_clean_instances.sh /path/to/job-directory`

**Quality Criteria**:
```
Class              Min Points    Min Height
12_Masts          100           2.0m
15_2Wheel         80            0.8m
7_Trees_Combined  150           2.0m
```

## Utilities (Not Part of Main Pipeline)

### Combine Trees and Trunks
**Purpose**: Merge 7_Trees and 40_TreeTrunks into combined class
- **Script**: `utilities/combine_trees_trunks.sh`
- **Usage**: `./combine_trees_trunks.sh /path/to/job-directory`
- **Note**: Run BEFORE stage3 if you want combined tree instances

### Convert to LAS
**Purpose**: Convert LAZ files to uncompressed LAS format
- **Script**: `utilities/convert_to_las.sh`
- **Usage**: `./convert_to_las.sh /path/to/input-directory`
- **Output**: `input-directory_las` with all LAS files

### Convert Folder LAZ to LAS
**Purpose**: Convert all LAZ files in a folder to LAS format
- **Script**: `utilities/convert_folder_laz_to_las.sh`
- **Usage**: `./convert_folder_laz_to_las.sh /path/to/folder`
- **Output**: `folder/output_las/` with converted LAS files
- **Features**: Recursive search, preserves directory structure, detailed statistics

### Analyze Results
**Purpose**: Generate comprehensive statistics and analysis
- **Script**: `utilities/analyze_results.sh`
- **Usage**: `./analyze_results.sh /path/to/job-directory`
- **Output**: `clustering_analysis.json` with detailed statistics

## Quick Start

### Complete Pipeline Execution
```bash
# 1. Split large LAZ file into chunks
./scripts/stage1_split_chunks.sh /path/to/large_file.laz

# 2. Extract classes from chunks
./scripts/stage2_extract_classes.sh /path/to/job-directory

# 3. (Optional) Combine trees and trunks
./utilities/combine_trees_trunks.sh /path/to/job-directory

# 4. Cluster instances for all classes
./scripts/stage3_cluster_instances.sh /path/to/job-directory

# 5. Clean and filter instances
./scripts/stage4_clean_instances.sh /path/to/job-directory

# 6. Convert to LAS format for visualization
./utilities/convert_to_las.sh /path/to/job-directory/cleaned_data

# 7. Analyze results
./utilities/analyze_results.sh /path/to/job-directory
```

### Single Class Processing
```bash
# Process only masts class
./scripts/stage3_cluster_instances.sh /path/to/job-directory 12_Masts
```

## Output Structure

```
job-YYYYMMDDHHMMSS/
├── chunks/
│   ├── part_1_chunk.laz
│   ├── part_1_chunk/
│   │   └── compressed/
│   │       └── filtred_by_classes/
│   │           ├── 12_Masts/
│   │           │   ├── 12_Masts.laz
│   │           │   ├── main_cluster/
│   │           │   └── instances/
│   │           │       ├── 12_Masts_000.laz
│   │           │       ├── 12_Masts_001.laz
│   │           │       └── ...
│   │           └── 15_2Wheel/
│   └── part_2_chunk.laz
├── cleaned_data/
│   └── chunks/
│       └── part_1_chunk/
│           └── 12_Masts/
│               ├── 12_Masts_000.laz
│               └── cleaning_summary.json
└── clustering_analysis.json
```

## Requirements

### Software Dependencies
- **PDAL** (Point Data Abstraction Library)
- **Python 3** with json module
- **bash** shell
- **bc** calculator
- Standard Linux utilities (find, wc, etc.)

### Installation
```bash
# Install PDAL (Ubuntu/Debian)
sudo apt-get install pdal python3-pdal

# Make all scripts executable
chmod +x scripts/*.sh utilities/*.sh
```

### System Requirements
- **Memory**: 8GB+ RAM recommended for large datasets
- **Storage**: 2-3x input file size for intermediate files
- **CPU**: Multi-core recommended for faster processing

## Class Definitions

### Mobile Mapping Semantic Classes
| Code | Class Name          | Description                    |
|------|---------------------|--------------------------------|
| 2    | Ground              | Road surface, sidewalks        |
| 3    | Low Vegetation      | Grass, small plants           |
| 4    | Medium Vegetation   | Bushes, medium plants         |
| 5    | High Vegetation     | Large trees, tall vegetation  |
| 6    | Buildings           | Structures, facades           |
| 7    | Trees               | Individual tree crowns        |
| 8    | Other Vegetation    | Miscellaneous vegetation      |
| 9    | Water               | Water bodies                  |
| 10   | Traffic Signs       | Road signs                    |
| 11   | Wires              | Power lines, cables           |
| 12   | Masts              | Poles, posts, masts           |
| 13   | Bridges            | Bridge structures             |
| 15   | 2Wheel             | Motorcycles, bicycles         |
| 16   | Mobile 4w          | Cars in motion               |
| 17   | Stationary 4w      | Parked vehicles              |
| 40   | Tree Trunks        | Tree trunk segments          |

## Troubleshooting

### Common Issues

**1. "pdal: command not found"**
- Install PDAL: `sudo apt-get install pdal`

**2. "No instances created"**
- Check if class files exist and have sufficient points
- Adjust clustering parameters in scripts

**3. "Pipeline failed"**
- Verify input file format and integrity
- Check available disk space

**4. Memory errors**
- Reduce chunk size in stage1
- Process fewer classes simultaneously

### Performance Optimization

**For Large Datasets**:
- Use smaller chunk sizes (5-8M points)
- Process classes individually in stage3
- Monitor system resources during processing

**For Quality Improvement**:
- Adjust clustering tolerance values
- Modify minimum point thresholds
- Review class-specific parameters

## Support

For technical issues or questions about the clustering pipeline:
1. Check log files in job directories
2. Verify input data format and completeness
3. Ensure all dependencies are installed
4. Review parameter settings for your specific data

## Version History

- **v1.0**: Initial production release
- **Stage 4**: Quality filtering and instance merging
- **Utilities**: Tree combining, format conversion, analysis tools

---

*LiDAR Clustering Production Pipeline - September 2025*