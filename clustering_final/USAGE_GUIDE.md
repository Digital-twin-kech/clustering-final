# LiDAR Clustering Pipeline - Usage Guide

## 🚀 Quick Start Guide

This guide walks you through running the complete 3-stage LiDAR clustering pipeline from raw data to interactive web visualization.

## 📋 Prerequisites

### System Requirements
```bash
# Install PDAL (Point Data Abstraction Library)
sudo apt update
sudo apt install pdal

# Install Python dependencies
pip install -r requirements.txt
```

### Input Data
- **Format**: LAZ or LAS file
- **Size**: Any size (tested with 50M+ points)
- **Classification**: Should contain semantic classes (1-18, 40+)
- **Coordinate System**: UTM Zone 29N (Morocco region)

## 📁 Pipeline Overview

```
Raw LiDAR Data (.laz)
    ↓ Stage 1
Spatial Chunks (chunk_1.laz, chunk_2.laz, ...)
    ↓ Stage 2
Class-filtered Files (12_Masts.laz, 7_Trees.laz, ...)
    ↓ Stage 3
Centroids + Visualization (JSON + Web Map)
```

---

## 🔧 Stage 1: Spatial Chunking

### Purpose
Split large LiDAR files into manageable spatial chunks for parallel processing.

### Command
```bash
./stage1_simple_chunking.sh INPUT_FILE.laz
```

### Example
```bash
# Process your LiDAR file
./stage1_simple_chunking.sh /path/to/your/data.laz
```

### What it does
- Splits large files using point-count-based chunking
- Creates 25M points per chunk (adjustable)
- Preserves ALL points (no data loss)
- Uses PDAL `filters.divider` for reliable splitting

### Output
```
outlast/chunks/
├── spatial_segment_1.laz  (25M points)
├── spatial_segment_2.laz  (25M points)
├── spatial_segment_3.laz  (remaining points)
└── ...
```

### Verification
```bash
# Check chunks were created
ls -lh outlast/chunks/spatial_segment_*.laz

# Analyze chunks (optional)
./analyze_chunks.sh
```

---

## 🎯 Stage 2: Class Filtering

### Purpose
Extract individual semantic classes from spatial chunks for targeted processing.

### Command
```bash
./stage2_class_filtering.sh
```

### What it does
- Processes ALL spatial chunks automatically
- Extracts each semantic class (1-18, 40+) into separate files
- Creates organized directory structure
- Maintains full point cloud data for each class

### Output Structure
```
outlast/chunks/
├── chunk_1/compressed/filtred_by_classes/
│   ├── 7_Trees/7_Trees.laz
│   ├── 12_Masts/12_Masts.laz
│   ├── 40_TreeTrunks/40_TreeTrunks.laz
│   └── ... (one directory per class)
├── chunk_2/compressed/filtred_by_classes/
│   └── ... (same structure)
└── ...
```

### Verification
```bash
# Check class extraction results
find outlast/chunks -name "*.laz" | head -10

# Check specific class across all chunks
find outlast/chunks -path "*/12_Masts/12_Masts.laz" -ls
```

---

## 🗂️ Optional: Tree Merging

### Purpose
Combine Trees (class 7) and TreeTrunks (class 40) into TreesCombined (class 41).

### Command
```bash
./merge_trees.sh CHUNK_FOLDER
```

### Example
```bash
# Merge trees for specific chunk
./merge_trees.sh outlast/chunks/chunk_1

# Or merge for all chunks
for chunk in outlast/chunks/chunk_*; do
    ./merge_trees.sh "$chunk"
done
```

---

## 🎯 Stage 3: Clustering & Visualization

### Option A: Single Class Processing
```bash
./stage3_lightweight_clustering.sh CLASSES_DIRECTORY CLASS_NAME
```

### Example
```bash
# Process Masts in chunk_1
./stage3_lightweight_clustering.sh \
    outlast/chunks/chunk_1/compressed/filtred_by_classes \
    12_Masts
```

### Option B: Batch Processing (Recommended)
```bash
./process_all_chunks.sh CLASS_NAME
```

### Example
```bash
# Process all Masts across all chunks
./process_all_chunks.sh 12_Masts

# Process all default classes
./process_all_chunks.sh
```

### What it does
- **2D Clustering**: Eliminates Z-axis for faster processing
- **Lightweight**: 10x-100x faster than traditional 3D clustering
- **JSON Output**: Creates centroids with UTM coordinates
- **Dashboard Ready**: Optimized for web visualization

### Output
```
*/centroids/
└── 12_Masts_centroids.json  # Contains object centroids + metadata
```

---

## 🗺️ Web Visualization

### Start the Map Server
```bash
python3 map_server.py
```

### Access the Map
- **URL**: http://localhost:8001
- **Features**: Interactive map with clustered objects
- **Controls**: Filter by class/chunk, zoom to data
- **Coordinates**: Automatic UTM → WGS84 conversion

### API Endpoints
```bash
# Get all clustering data
curl http://localhost:8001/api/clustering-data

# Get available classes
curl http://localhost:8001/api/classes

# Simple test map
curl http://localhost:8001/test
```

---

## 🎯 Complete Workflow Examples

### Example 1: Process Masts Only
```bash
# 1. Chunk your data
./stage1_simple_chunking.sh /path/to/your/data.laz

# 2. Extract classes
./stage2_class_filtering.sh

# 3. Process all Masts
./process_all_chunks.sh 12_Masts

# 4. Start visualization
python3 map_server.py
# Open: http://localhost:8001
```

### Example 2: Process All Classes
```bash
# 1-2. Chunk and extract (same as above)

# 3. Process all default classes
./process_all_chunks.sh

# 4. Start visualization (same as above)
```

### Example 3: Trees with Merging
```bash
# 1-2. Chunk and extract (same as above)

# 3. Merge Trees + TreeTrunks
for chunk in outlast/chunks/chunk_*; do
    ./merge_trees.sh "$chunk"
done

# 4. Process TreesCombined
./process_all_chunks.sh 41_TreesCombined

# 5. Visualize
python3 map_server.py
```

---

## 📊 Understanding the Results

### Clustering Output
Each `*_centroids.json` file contains:
```json
{
  "class": "12_Masts",
  "chunk": "chunk_1",
  "results": {
    "instances_found": 43,
    "input_points": 55547,
    "coverage_percent": 100.0
  },
  "centroids": [
    {
      "object_id": 1,
      "centroid_x": 1108616.511,  // UTM X
      "centroid_y": 3885578.304,  // UTM Y
      "centroid_z": 190.438,      // Height
      "point_count": 247
    },
    // ... more objects
  ]
}
```

### Performance Metrics
- **Traditional 3D Clustering**: 10-30 minutes per class
- **Lightweight 2D Clustering**: 1-3 minutes per class
- **Speedup**: 10x-100x improvement
- **Storage**: JSON centroids vs heavy LAZ instances

---

## 🔧 Configuration & Customization

### Clustering Parameters
Edit `stage3_lightweight_clustering.sh`:
```bash
# 2D clustering settings
TOLERANCE_2D=1.0          # Distance tolerance (meters)
MIN_POINTS=15             # Minimum points per cluster
Z_AXIS_ELIMINATED=true    # Use 2D projection
```

### Chunk Size
Edit `stage1_simple_chunking.sh`:
```bash
POINTS_PER_CHUNK=25000000  # 25M points per chunk
```

### Classes to Process
Edit `process_all_chunks.sh`:
```bash
DEFAULT_CLASSES=(
    "12_Masts" "10_TrafficSigns" "11_Wires" "40_TreeTrunks"
    "41_TreesCombined" "7_Trees" "13_Pedestrians" "15_2Wheel"
    "16_Mobile4w" "17_Stationary4w"
)
```

---

## 🚨 Troubleshooting

### Common Issues & Solutions

#### 1. "No chunks found"
```bash
# Check if Stage 1 completed successfully
ls -la outlast/chunks/spatial_segment_*.laz
# If empty, re-run Stage 1 with correct input path
```

#### 2. "Class not found"
```bash
# Check available classes in chunks
find outlast/chunks -name "*.laz" | grep -E "(12_Masts|7_Trees)"
# Make sure Stage 2 completed for your target class
```

#### 3. "No clustering results"
```bash
# Check if class has enough points
pdal info outlast/chunks/chunk_1/compressed/filtred_by_classes/12_Masts/12_Masts.laz --summary
# Reduce MIN_POINTS if class has few points
```

#### 4. "Map shows no data"
```bash
# Test API directly
curl -s http://localhost:8001/api/clustering-data | jq '.summary'
# Check if centroids JSON files exist
find outlast/chunks -name "*_centroids.json" -ls
```

#### 5. "Port already in use"
```bash
# Kill existing servers
pkill -f "python3 map_server.py"
# Or use different port in map_server.py
```

### Verification Commands
```bash
# Check processing progress
find outlast/chunks -name "*_centroids.json" | wc -l

# Verify point counts
grep -r "instances_found" outlast/chunks/*/centroids/*.json

# Test coordinate conversion
python3 -c "
import pyproj
utm = pyproj.CRS('EPSG:32629')
wgs = pyproj.CRS('EPSG:4326')
t = pyproj.Transformer.from_crs(utm, wgs, always_xy=True)
print('UTM to WGS84:', t.transform(1108616, 3885578))
"
```

---

## 📈 Performance Tips

### For Large Datasets (100M+ points)
1. **Increase chunk size**: `POINTS_PER_CHUNK=50000000`
2. **Process in parallel**: Run multiple classes simultaneously
3. **Use SSD storage**: Faster I/O for LAZ files
4. **Monitor memory**: Each chunk uses ~2-4GB RAM

### For Production Use
1. **Automate the pipeline**: Create wrapper scripts
2. **Add logging**: Capture processing times and results
3. **Batch processing**: Process multiple datasets overnight
4. **Backup results**: Save centroids JSON files separately

---

## 🎯 Next Steps

After completing the pipeline:

1. **Export Results**: Convert JSON to GIS formats (GeoJSON, Shapefile)
2. **Advanced Visualization**: Add height-based coloring, statistics panels
3. **Integration**: Connect to existing GIS workflows
4. **Scaling**: Process multiple regions/datasets
5. **Analysis**: Perform spatial analysis on detected objects

---

## 📞 Support

If you encounter issues:

1. **Check logs**: All scripts provide detailed logging
2. **Verify prerequisites**: Ensure PDAL and Python deps installed
3. **Test with small dataset**: Validate pipeline with subset first
4. **Check file permissions**: Ensure scripts are executable (`chmod +x *.sh`)

---

**🎉 You're ready to process LiDAR data!** Start with a small test dataset and work your way up to production-scale processing.