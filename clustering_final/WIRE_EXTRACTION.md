# Enhanced Wire Line Extraction Documentation

## Overview
Enhanced wire line extraction for LiDAR point clouds using line-based segmentation with height-aware clustering. Designed specifically for continuous linear wire/cable infrastructure.

## Implementation Details

### Script: `python_wire_enhanced.py`
- **Method**: Line segmentation + height-aware clustering
- **Output**: GeoJSON LineString geometries for wire infrastructure
- **Visualization**: Saddle Brown color (`#8B4513`) to represent wire cables
- **Geometry**: Natural curved lines following actual wire paths

### Enhanced Processing Pipeline

#### Step 1: Light Voxel Filtering
- **Voxel Size**: 0.2m (preserve wire detail and continuity)
- **Purpose**: Light downsampling while maintaining linear wire structure
- **Typical Reduction**: ~85-87% point reduction (preserving connectivity)

#### Step 2: Height-Based Filtering for Elevated Wires
- **Threshold**: 10th percentile (keeps upper 90% of points)
- **Purpose**: Focus on elevated wire infrastructure, remove ground clutter
- **Typical Retention**: ~90% of voxel-filtered points

#### Step 3: Conservative Outlier Removal
- **Method**: K-nearest neighbors (k=8) statistical analysis
- **Threshold**: Mean + 2.5σ (conservative to preserve wire endpoints)
- **Purpose**: Remove noise while preserving critical wire connection points
- **Typical Retention**: ~99% of height-filtered points

#### Step 4: Height-Aware Wire Line Clustering
- **Algorithm**: DBSCAN with 3D coordinates
- **Parameters**: eps=5.0m, min_samples=30 points
- **3D Clustering**: Accounts for wire sag and height variations
- **Purpose**: Group wire points into continuous linear segments

#### Step 5: Wire Line Generation
- **Method**: PCA-based principal direction analysis
- **Line Fitting**: Order points along principal axis for continuous lines
- **Sampling**: Up to 50 points per line for clean visualization
- **Quality Filters**:
  - Minimum length: 5m
  - Minimum aspect ratio: 3:1 (linear structure)
  - Minimum points: 20 points per line

## Performance Results

### Final Wire Line Results:
- **chunk_1**: 1 wire line (37.05m)
- **chunk_2**: 3 wire lines (118.50m)
- **chunk_3**: 3 wire lines (173.48m)
- **chunk_4**: 4 wire lines (233.21m) - **Best coverage**
- **chunk_5**: 3 wire lines (145.79m)

**Total**: **14 wire lines** across **708.03 meters** of wire infrastructure

### Key Advantages Over Polygon-Based Methods:
1. **Linear Representation**: True line geometries instead of approximated polygons
2. **Continuous Paths**: Maintains wire connectivity across spans
3. **Height Awareness**: 3D clustering accounts for natural wire sag
4. **Precise Endpoints**: Conservative filtering preserves connection points
5. **Scalable**: Efficient processing of large wire datasets (121K+ points)

## Technical Parameters

### Optimized for Wire Characteristics:
- **Light filtering**: Preserves wire continuity and endpoints
- **3D clustering**: Handles height variations from wire sag
- **Linear validation**: Ensures high aspect ratios typical of wire infrastructure
- **PCA direction**: Orders points along natural wire direction
- **Endpoint preservation**: Conservative outlier removal maintains connections

### Wire-Specific Metrics:
- **Length**: Measured along principal direction
- **Width**: Perpendicular extent (should be narrow)
- **Aspect Ratio**: Length/width ratio (high for linear wires)
- **Height Stats**: Min/max/average elevation along wire
- **Point Density**: Points per meter for quality assessment

### Coordinate System:
- **Input**: UTM Zone 29N (meters)
- **Output**: GeoJSON LineString in UTM coordinates
- **Visualization**: Auto-converted to WGS84 for web display

## Quality Assurance
- **Linearity Check**: Aspect ratio ≥ 3:1 ensures linear structure
- **Length Validation**: Minimum 5m eliminates short noise segments
- **Point Density**: Minimum 20 points ensures adequate sampling
- **Height Consistency**: Natural wire sag patterns validated
- **Visual Verification**: Saddle brown lines in web viewer

## Usage
```bash
python3 python_wire_enhanced.py <chunk_name>
# Example: python3 python_wire_enhanced.py chunk_4
```

## Output Files
- `{chunk}/11_Wires/lines/11_Wires_lines.geojson`
- LineString geometry with natural wire curves
- Metadata: length, width, height stats, aspect ratio, point count
- Web visualization: http://localhost:8001

## Wire Line Properties
Each wire line includes:
```json
{
  "line_id": 1,
  "class": "11_Wires",
  "chunk": "chunk_4",
  "length_m": 44.53,
  "width_m": 1.39,
  "point_count": 499,
  "aspect_ratio": 32.11,
  "min_height_m": 194.23,
  "max_height_m": 196.0,
  "avg_height_m": 195.06,
  "extraction_method": "python_wire_enhanced"
}
```

## Large Dataset Performance
Successfully tested on chunks with up to **37,404 wire points** (chunk_5), demonstrating scalability for bigger datasets. The line-based approach efficiently processes thousands of points into clean, continuous wire representations.

---
*Generated with enhanced line-based extraction for precise wire infrastructure mapping*