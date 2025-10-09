# LiDAR Clustering Pipeline - Complete Guide

## Introduction

This guide provides detailed instructions for using the LiDAR clustering pipeline to process mobile mapping point cloud data and extract individual object instances.

## Pipeline Architecture

The pipeline consists of 4 main stages plus utilities:

```
Input LAZ → Stage 1 → Stage 2 → Stage 3 → Stage 4 → Output Instances
           (Split)   (Classes) (Cluster) (Clean)
```

### Data Flow

1. **Large LAZ file** (50M+ points)
2. **Chunks** (~10M points each)
3. **Class-separated files** per chunk
4. **Individual instances** per class
5. **Quality-filtered instances**

## Detailed Stage Descriptions

### Stage 1: Chunk Splitting

**Objective**: Make large files manageable for processing

**Technical Details**:
- Uses PDAL `filters.tail` and `filters.head` for precise point extraction
- Maintains original point attributes and precision
- Creates sequential chunks with no overlap

**Parameters**:
- `chunk_size`: Target points per chunk (default: 10M)
- `output_format`: LAZ compression for storage efficiency

**Example Pipeline**:
```json
[
  {"type": "readers.las", "filename": "input.laz"},
  {"type": "filters.tail", "count": 40000000},
  {"type": "filters.head", "count": 10000000},
  {"type": "writers.las", "filename": "chunk.laz", "compression": "laszip"}
]
```

### Stage 2: Class Extraction

**Objective**: Separate semantic classes for targeted clustering

**Technical Details**:
- Uses PDAL `filters.range` with classification codes
- Extracts only classes suitable for instance clustering
- Preserves original point attributes

**Class Selection Strategy**:
- **Include**: Objects with distinct instances (vehicles, poles, signs)
- **Exclude**: Continuous surfaces (ground, buildings, large vegetation)

**Example Pipeline**:
```json
[
  {"type": "readers.las", "filename": "chunk.laz"},
  {"type": "filters.range", "limits": "Classification[12:12]"},
  {"type": "writers.las", "filename": "masts.laz", "compression": "laszip"}
]
```

### Stage 3: Instance Clustering

**Objective**: Separate individual objects within each class

**Technical Details**:
- Uses PDAL `filters.cluster` with EUCLIDEAN algorithm
- Adds ClusterID dimension to identify instances
- Creates main cluster file and individual instance files

**Parameter Tuning**:
- `tolerance`: 3D distance threshold for grouping points
- `min_points`: Minimum points required for valid cluster

**Class-Specific Considerations**:
- **Masts**: Very tight tolerance (0.5m) for thin vertical objects
- **Vehicles**: Medium tolerance (1.0m) for compact objects
- **Trees**: Loose tolerance (1.5m) for irregular shapes

**Example Pipeline**:
```json
[
  {"type": "readers.las", "filename": "masts.laz"},
  {"type": "filters.cluster", "tolerance": 0.5, "min_points": 30},
  {"type": "writers.las", "filename": "clustered.laz", "extra_dims": "ClusterID=uint32"}
]
```

### Stage 4: Quality Filtering

**Objective**: Remove noise and improve instance quality

**Technical Details**:
- Applies class-specific size and dimensional filters
- Identifies and merges over-segmented instances
- Preserves all original point data

**Quality Metrics**:
- **Point Count**: Sufficient detail for object representation
- **Height**: Realistic dimensional constraints
- **Spatial Coherence**: Detection of fragmented instances

**Merge Logic**:
- Distance-based candidate identification
- Priority system for small/fragmented instances
- PDAL merge operations preserve all points

## Utilities Documentation

### Tree Combining Utility

**Purpose**: Merge complementary tree classes before clustering

**When to Use**:
- When dataset has separate tree crowns and trunk classifications
- To create more complete tree instances
- Before running Stage 3 clustering

**Technical Process**:
```bash
# Identifies both 7_Trees and 40_TreeTrunks
# Creates merge pipeline combining both classes
# Outputs 7_Trees_Combined for clustering
```

**Benefits**:
- More complete tree representations
- Better clustering results for vegetation
- Unified tree instance management

### Format Conversion Utility

**Purpose**: Convert between LAZ and LAS formats

**Use Cases**:
- **LAZ→LAS**: For visualization in software preferring uncompressed format
- **Batch Processing**: Convert entire directory structures
- **Integration**: Prepare data for external tools

**Performance Notes**:
- LAS files are ~3-4x larger than LAZ
- Faster loading in some visualization software
- No data loss during conversion

### Analysis Utility

**Purpose**: Generate comprehensive processing statistics

**Output Metrics**:
- Instance counts per class and chunk
- Processing success rates
- Quality improvement measurements
- Performance statistics

**Report Formats**:
- JSON for automated processing
- Human-readable summaries
- Integration with monitoring systems

## Best Practices

### Data Preparation

**Input Quality**:
- Verify classification codes match expected mobile mapping schema
- Ensure consistent coordinate system across all data
- Check for corrupt or incomplete LAZ files

**Storage Planning**:
- Allocate 2-3x input size for temporary files
- Use SSD storage for intermediate processing
- Plan for final output storage requirements

### Parameter Optimization

**Clustering Tolerance**:
- Start with default values
- Analyze results and adjust iteratively
- Consider object size and point density

**Quality Thresholds**:
- Balance between completeness and quality
- Adjust based on downstream application requirements
- Document parameter choices for reproducibility

### Performance Optimization

**System Resources**:
- Monitor memory usage during processing
- Use appropriate chunk sizes for available RAM
- Consider disk I/O bottlenecks

**Parallel Processing**:
- Process different classes simultaneously
- Use multiple chunks for large datasets
- Balance system load across available cores

### Quality Assurance

**Validation Steps**:
1. Visual inspection of sample instances
2. Statistical analysis of results
3. Comparison with ground truth data
4. Integration testing with downstream tools

**Common Issues**:
- Under-segmentation: Reduce tolerance values
- Over-segmentation: Increase tolerance or implement merging
- Missing instances: Lower minimum point thresholds
- Noise instances: Increase quality filter thresholds

## Advanced Topics

### Custom Class Definitions

**Adding New Classes**:
1. Update class mapping in Stage 2
2. Define clustering parameters in Stage 3
3. Add quality criteria in Stage 4
4. Test with representative data

**Mobile Mapping Specifics**:
- Consider vehicle-mounted sensor characteristics
- Account for point density variations
- Handle occlusion and viewpoint effects

### Integration with External Tools

**Visualization**:
- CloudCompare: Direct LAS/LAZ import
- QGIS: Point cloud visualization plugins
- ArcGIS: Native LAS support

**Analysis Software**:
- PCL (Point Cloud Library): For advanced processing
- Open3D: Python-based point cloud analysis
- PDAL: Extended pipeline operations

**Data Management**:
- GeoPackage: Spatial database integration
- PostGIS: Spatial database with point cloud support
- Cloud Storage: S3, GCS compatible workflows

### Troubleshooting Guide

**Pipeline Failures**:
1. Check PDAL installation and version
2. Verify input file integrity
3. Review available disk space
4. Check file permissions

**Quality Issues**:
1. Analyze clustering parameters
2. Review class definitions
3. Inspect input data quality
4. Validate coordinate systems

**Performance Problems**:
1. Monitor system resources
2. Optimize chunk sizes
3. Consider hardware limitations
4. Review processing order

## Conclusion

This pipeline provides a robust, scalable solution for LiDAR instance clustering. Success depends on:

- Proper parameter tuning for specific datasets
- Understanding of input data characteristics
- Appropriate quality validation procedures
- Integration with downstream processing workflows

For optimal results, start with default parameters and iteratively refine based on output quality assessment.

---

*Pipeline Guide v1.0 - September 2025*