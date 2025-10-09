#!/bin/bash

# Organize complete structure: chunks, filtered classes, LAZ, and LAS files
# Usage: ./organize_complete_structure.sh JOB_ROOT

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "ERROR: Usage: $0 JOB_ROOT" >&2
    echo "  JOB_ROOT: Job directory containing chunks" >&2
    exit 1
fi

JOB_ROOT="$1"
CHUNKS_DIR="$JOB_ROOT/chunks"

if [[ ! -d "$CHUNKS_DIR" ]]; then
    echo "ERROR: Chunks directory not found: $CHUNKS_DIR" >&2
    exit 1
fi

echo "INFO: Creating complete organized structure in: $JOB_ROOT"
echo "========================================="

# Create organized directory structure
ORGANIZED_DIR="$JOB_ROOT/organized"
ORIGINAL_CHUNKS_DIR="$ORGANIZED_DIR/01_original_chunks"
FILTERED_CLASSES_DIR="$ORGANIZED_DIR/02_filtered_classes" 
COMPRESSED_LAZ_DIR="$ORGANIZED_DIR/03_compressed_laz"
VISUALIZATION_LAS_DIR="$ORGANIZED_DIR/04_visualization_las"

mkdir -p "$ORIGINAL_CHUNKS_DIR"
mkdir -p "$FILTERED_CLASSES_DIR"
mkdir -p "$COMPRESSED_LAZ_DIR"
mkdir -p "$VISUALIZATION_LAS_DIR"

echo "INFO: Creating 4-tier organized structure:"
echo "  01_original_chunks/     - Original LAZ chunk files"
echo "  02_filtered_classes/    - Mixed LAZ/LAS by class"
echo "  03_compressed_laz/      - LAZ files only (storage)"
echo "  04_visualization_las/   - LAS files only (viewing)"

CHUNKS_MOVED=0
LAZ_MOVED=0
LAS_MOVED=0
TOTAL_FILES_MOVED=0

# Find all chunk files and filtered class directories
CHUNK_FILES=($(find "$CHUNKS_DIR" -name "part_*.laz" 2>/dev/null || true))
CLASS_DIRS=()
while IFS= read -r -d '' dir; do
    if [[ $(basename "$dir") == *"_filtred_by_classes" ]]; then
        CLASS_DIRS+=("$dir")
    fi
done < <(find "$CHUNKS_DIR" -type d -print0 2>/dev/null)

echo "INFO: Found ${#CHUNK_FILES[@]} chunk files and ${#CLASS_DIRS[@]} filtered directories"

# 1. Organize original chunks
echo ""
echo "Step 1: Organizing original chunks..."
for CHUNK_FILE in "${CHUNK_FILES[@]}"; do
    CHUNK_NAME=$(basename "$CHUNK_FILE")
    SOURCE_DIR=$(dirname "$CHUNK_FILE")
    SOURCE_DIR_NAME=$(basename "$SOURCE_DIR")
    
    # Create directory structure: original_chunks/source_dir_name/
    TARGET_DIR="$ORIGINAL_CHUNKS_DIR/$SOURCE_DIR_NAME"
    mkdir -p "$TARGET_DIR"
    
    cp "$CHUNK_FILE" "$TARGET_DIR/"
    echo "  ✓ $SOURCE_DIR_NAME/$CHUNK_NAME"
    CHUNKS_MOVED=$((CHUNKS_MOVED + 1))
done

# 2. Organize filtered classes (preserving mixed LAZ/LAS structure)
echo ""
echo "Step 2: Organizing filtered classes..."
for CLASS_DIR in "${CLASS_DIRS[@]}"; do
    DIR_NAME=$(basename "$CLASS_DIR")
    CHUNK_NAME=${DIR_NAME%_filtred_by_classes}
    
    echo "  Processing: $CHUNK_NAME"
    
    # Create target directory: filtered_classes/chunk_name/
    TARGET_CLASS_DIR="$FILTERED_CLASSES_DIR/$CHUNK_NAME"
    mkdir -p "$TARGET_CLASS_DIR"
    
    # Copy all files (both LAZ and LAS)
    ALL_FILES=($(find "$CLASS_DIR" -name "*.laz" -o -name "*.las" 2>/dev/null || true))
    if [[ ${#ALL_FILES[@]} -gt 0 ]]; then
        for file in "${ALL_FILES[@]}"; do
            filename=$(basename "$file")
            cp "$file" "$TARGET_CLASS_DIR/"
        done
        echo "    ✓ Copied ${#ALL_FILES[@]} files to filtered_classes/$CHUNK_NAME/"
        TOTAL_FILES_MOVED=$((TOTAL_FILES_MOVED + ${#ALL_FILES[@]}))
    fi
done

# 3. Organize LAZ files only
echo ""
echo "Step 3: Organizing LAZ files (compressed)..."
for CLASS_DIR in "${CLASS_DIRS[@]}"; do
    DIR_NAME=$(basename "$CLASS_DIR")
    CHUNK_NAME=${DIR_NAME%_filtred_by_classes}
    
    # Create LAZ target directory
    LAZ_CHUNK_DIR="$COMPRESSED_LAZ_DIR/$CHUNK_NAME"
    mkdir -p "$LAZ_CHUNK_DIR"
    
    # Copy only LAZ files
    LAZ_FILES=($(find "$CLASS_DIR" -name "*.laz" 2>/dev/null || true))
    if [[ ${#LAZ_FILES[@]} -gt 0 ]]; then
        echo "  $CHUNK_NAME: ${#LAZ_FILES[@]} LAZ files"
        for laz_file in "${LAZ_FILES[@]}"; do
            filename=$(basename "$laz_file")
            cp "$laz_file" "$LAZ_CHUNK_DIR/"
        done
        LAZ_MOVED=$((LAZ_MOVED + ${#LAZ_FILES[@]}))
    fi
done

# 4. Organize LAS files only
echo ""
echo "Step 4: Organizing LAS files (visualization)..."
for CLASS_DIR in "${CLASS_DIRS[@]}"; do
    DIR_NAME=$(basename "$CLASS_DIR")
    CHUNK_NAME=${DIR_NAME%_filtred_by_classes}
    
    # Create LAS target directory
    LAS_CHUNK_DIR="$VISUALIZATION_LAS_DIR/$CHUNK_NAME"
    mkdir -p "$LAS_CHUNK_DIR"
    
    # Copy only LAS files
    LAS_FILES=($(find "$CLASS_DIR" -name "*.las" 2>/dev/null || true))
    if [[ ${#LAS_FILES[@]} -gt 0 ]]; then
        echo "  $CHUNK_NAME: ${#LAS_FILES[@]} LAS files"
        for las_file in "${LAS_FILES[@]}"; do
            filename=$(basename "$las_file")
            cp "$las_file" "$LAS_CHUNK_DIR/"
        done
        LAS_MOVED=$((LAS_MOVED + ${#LAS_FILES[@]}))
    fi
done

echo ""
echo "========================================="
echo "COMPLETE ORGANIZATION FINISHED"
echo "========================================="
echo "Original chunks moved: $CHUNKS_MOVED"
echo "Total class files organized: $TOTAL_FILES_MOVED"
echo "LAZ files organized: $LAZ_MOVED"
echo "LAS files organized: $LAS_MOVED"

# Show the complete organized structure
echo ""
echo "📁 Complete Organized Structure:"
echo ""
echo "$ORGANIZED_DIR/"

# Show structure for each directory
for organized_subdir in "$ORIGINAL_CHUNKS_DIR" "$FILTERED_CLASSES_DIR" "$COMPRESSED_LAZ_DIR" "$VISUALIZATION_LAS_DIR"; do
    subdir_name=$(basename "$organized_subdir")
    echo "├── $subdir_name/"
    
    # Show first few subdirectories and files
    find "$organized_subdir" -maxdepth 1 -type d | grep -v "^$organized_subdir$" | sort | head -3 | while read -r chunk_dir; do
        chunk_name=$(basename "$chunk_dir")
        echo "│   ├── $chunk_name/"
        
        # Show file count and types
        laz_count=$(find "$chunk_dir" -name "*.laz" 2>/dev/null | wc -l)
        las_count=$(find "$chunk_dir" -name "*.las" 2>/dev/null | wc -l)
        
        if [[ $laz_count -gt 0 && $las_count -gt 0 ]]; then
            echo "│   │   ├── ($laz_count LAZ files, $las_count LAS files)"
        elif [[ $laz_count -gt 0 ]]; then
            echo "│   │   ├── ($laz_count LAZ files)"
        elif [[ $las_count -gt 0 ]]; then
            echo "│   │   ├── ($las_count LAS files)"
        fi
        
        # Show first few files as examples
        find "$chunk_dir" -name "*.laz" -o -name "*.las" | head -2 | while read -r file; do
            filename=$(basename "$file")
            point_count=$(pdal info "$file" --summary 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('summary', {}).get('num_points', 0))" 2>/dev/null || echo "0")
            printf "│   │   ├── %-25s %8s points\n" "$filename" "$point_count"
        done
    done
    
    # Show if there are more directories
    total_dirs=$(find "$organized_subdir" -maxdepth 1 -type d | grep -v "^$organized_subdir$" | wc -l)
    if [[ $total_dirs -gt 3 ]]; then
        echo "│   └── ... ($(($total_dirs - 3)) more directories)"
    fi
    echo "│"
done

# Create master index
MASTER_INDEX="$ORGANIZED_DIR/README.md"
cat > "$MASTER_INDEX" << EOF
# Organized LiDAR Data Structure

Generated: $(date)

## Directory Structure

### 01_original_chunks/
- **Purpose**: Original LAZ chunk files from Stage 1
- **Format**: LAZ (compressed)
- **Use**: Backup, re-processing, archival
- **Files**: $(find "$ORIGINAL_CHUNKS_DIR" -name "*.laz" | wc -l) chunk files

### 02_filtered_classes/
- **Purpose**: Classes extracted per chunk (mixed formats)
- **Format**: Both LAZ and LAS files
- **Use**: Complete class data with both formats
- **Files**: $(find "$FILTERED_CLASSES_DIR" -name "*.laz" -o -name "*.las" | wc -l) class files

### 03_compressed_laz/
- **Purpose**: Compressed class files for storage
- **Format**: LAZ only (compressed)
- **Use**: Long-term storage, processing pipelines
- **Files**: $(find "$COMPRESSED_LAZ_DIR" -name "*.laz" | wc -l) LAZ files

### 04_visualization_las/
- **Purpose**: Uncompressed files for visualization
- **Format**: LAS only (uncompressed)
- **Use**: CloudCompare, QGIS, analysis tools
- **Files**: $(find "$VISUALIZATION_LAS_DIR" -name "*.las" | wc -l) LAS files

## Mobile Mapping Classes

Your data contains these semantic classes:
- Roads, Sidewalks, Buildings, Trees
- TrafficLights, TrafficSigns, Wires, Masts
- Mobile4w (cars), Stationary4w (parked cars), 2Wheel (bikes)
- Pedestrians, TreeTrunks, OtherVegetation
- Other, OtherGround, TrafficIslands, Noise

## Usage Recommendations

- **For visualization**: Use \`04_visualization_las/\`
- **For storage**: Use \`03_compressed_laz/\`
- **For reprocessing**: Use \`01_original_chunks/\`
- **For mixed workflows**: Use \`02_filtered_classes/\`
EOF

echo ""
echo "✓ Created master index: $MASTER_INDEX"
echo ""
echo "🎯 Usage Guide:"
echo "  📁 01_original_chunks/     → Reprocessing and backup"
echo "  📁 02_filtered_classes/    → Complete class data (mixed formats)" 
echo "  📁 03_compressed_laz/      → Storage and archival"
echo "  📁 04_visualization_las/   → Load in CloudCompare, QGIS, etc."
echo ""
echo "========================================="