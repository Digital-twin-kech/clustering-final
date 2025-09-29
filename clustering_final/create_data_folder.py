#!/usr/bin/env python3
"""
Data Organization Script for LiDAR Clustering Visualization
Creates a centralized 'data' folder containing all visualization data
Copies and organizes JSON/GeoJSON files for server deployment
"""

import os
import json
import glob
import shutil
from pathlib import Path
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Base directories
BASE_DIR = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final"
SOURCE_DIR = f"{BASE_DIR}/outlast/chunks"
TARGET_DATA_DIR = f"{BASE_DIR}/server/data"

def create_directory_structure():
    """Create the organized directory structure for server deployment"""
    directories = [
        f"{TARGET_DATA_DIR}/centroids",
        f"{TARGET_DATA_DIR}/polygons/trees",
        f"{TARGET_DATA_DIR}/polygons/buildings",
        f"{TARGET_DATA_DIR}/polygons/vegetation",
        f"{TARGET_DATA_DIR}/lines/wires",
        f"{TARGET_DATA_DIR}/metadata"
    ]

    for directory in directories:
        Path(directory).mkdir(parents=True, exist_ok=True)
        logger.info(f"Created directory: {directory}")

def copy_centroid_files():
    """Copy and organize centroid JSON files (masts)"""
    logger.info("Processing centroid files (masts)...")

    # Find all centroid files, prioritizing clean versions
    clean_files = glob.glob(f"{SOURCE_DIR}/**/centroids/*_centroids_clean.json", recursive=True)
    regular_files = glob.glob(f"{SOURCE_DIR}/**/centroids/*_centroids.json", recursive=True)

    # Remove regular files if clean versions exist
    for clean_file in clean_files:
        regular_file = clean_file.replace('_clean.json', '.json')
        if regular_file in regular_files:
            regular_files.remove(regular_file)

    all_centroid_files = clean_files + regular_files

    logger.info(f"Found {len(all_centroid_files)} centroid files")

    for file_path in all_centroid_files:
        # Extract chunk and class info from path
        path_parts = Path(file_path).parts
        chunk = None
        class_name = None

        for part in path_parts:
            if part.startswith('chunk_'):
                chunk = part
            elif '_' in part and part != 'centroids':
                class_name = part

        if chunk and class_name:
            filename = f"{chunk}_{class_name}_centroids.json"
            target_path = f"{TARGET_DATA_DIR}/centroids/{filename}"

            shutil.copy2(file_path, target_path)
            logger.info(f"Copied: {filename}")

def copy_polygon_files():
    """Copy and organize polygon GeoJSON files (trees, buildings, vegetation)"""
    logger.info("Processing polygon files...")

    # Mapping of class folders to organized names
    class_mapping = {
        '7_Trees': 'trees',
        '6_Buildings': 'buildings',
        '8_OtherVegetation': 'vegetation'
    }

    for class_folder, organized_name in class_mapping.items():
        pattern = f"{SOURCE_DIR}/**/compressed/filtred_by_classes/{class_folder}/polygons/*_polygons.geojson"
        files = glob.glob(pattern, recursive=True)

        logger.info(f"Found {len(files)} {organized_name} polygon files")

        for file_path in files:
            # Extract chunk info
            path_parts = Path(file_path).parts
            chunk = None

            for part in path_parts:
                if part.startswith('chunk_'):
                    chunk = part
                    break

            if chunk:
                filename = f"{chunk}_{organized_name}_polygons.geojson"
                target_path = f"{TARGET_DATA_DIR}/polygons/{organized_name}/{filename}"

                shutil.copy2(file_path, target_path)
                logger.info(f"Copied: {filename}")

def copy_line_files():
    """Copy and organize line GeoJSON files (wires)"""
    logger.info("Processing line files (wires)...")

    # Find wire line files, excluding roads and sidewalks
    all_line_files = glob.glob(f"{SOURCE_DIR}/**/lines/*_lines.geojson", recursive=True)
    wire_files = []

    for file_path in all_line_files:
        # Filter out road and sidewalk files
        if not any(excluded in file_path for excluded in ['12_Roads_lines', '13_Sidewalks_lines', '2_Roads_lines', '3_Sidewalks_lines']):
            wire_files.append(file_path)

    logger.info(f"Found {len(wire_files)} wire line files")

    for file_path in wire_files:
        # Extract chunk info
        path_parts = Path(file_path).parts
        chunk = None

        for part in path_parts:
            if part.startswith('chunk_'):
                chunk = part
                break

        if chunk:
            filename = f"{chunk}_wires_lines.geojson"
            target_path = f"{TARGET_DATA_DIR}/lines/wires/{filename}"

            shutil.copy2(file_path, target_path)
            logger.info(f"Copied: {filename}")

def create_data_manifest():
    """Create a manifest file describing all available data"""
    logger.info("Creating data manifest...")

    manifest = {
        "data_structure": {
            "centroids": "Mast centroids (point data) in JSON format",
            "polygons": {
                "trees": "Tree polygon features in GeoJSON format",
                "buildings": "Building polygon features in GeoJSON format",
                "vegetation": "Other vegetation polygon features in GeoJSON format"
            },
            "lines": {
                "wires": "Wire line features in GeoJSON format"
            }
        },
        "coordinate_system": "UTM Zone 29N (EPSG:29180) for Morocco region",
        "file_naming": "{chunk}_{class}_{type}.{extension}",
        "statistics": {}
    }

    # Count files in each category
    centroid_count = len(glob.glob(f"{TARGET_DATA_DIR}/centroids/*.json"))
    tree_count = len(glob.glob(f"{TARGET_DATA_DIR}/polygons/trees/*.geojson"))
    building_count = len(glob.glob(f"{TARGET_DATA_DIR}/polygons/buildings/*.geojson"))
    vegetation_count = len(glob.glob(f"{TARGET_DATA_DIR}/polygons/vegetation/*.geojson"))
    wire_count = len(glob.glob(f"{TARGET_DATA_DIR}/lines/wires/*.geojson"))

    manifest["statistics"] = {
        "centroid_files": centroid_count,
        "tree_files": tree_count,
        "building_files": building_count,
        "vegetation_files": vegetation_count,
        "wire_files": wire_count,
        "total_files": centroid_count + tree_count + building_count + vegetation_count + wire_count
    }

    # Write manifest
    manifest_path = f"{TARGET_DATA_DIR}/manifest.json"
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)

    logger.info(f"Created manifest with {manifest['statistics']['total_files']} total files")

def create_readme():
    """Create README for the data folder"""
    readme_content = """# LiDAR Clustering Visualization Data

This folder contains organized LiDAR clustering data for visualization and server deployment.

## Directory Structure

```
data/
├── centroids/          # Mast centroid data (JSON)
│   └── {chunk}_{class}_centroids.json
├── polygons/           # Polygon features (GeoJSON)
│   ├── trees/         # Tree polygons
│   ├── buildings/     # Building polygons
│   └── vegetation/    # Other vegetation polygons
├── lines/             # Line features (GeoJSON)
│   └── wires/        # Wire line data
├── metadata/          # Processing metadata
├── manifest.json      # Data inventory and statistics
└── README.md         # This file
```

## Data Formats

- **Centroids**: JSON format with UTM coordinates and metadata
- **Polygons**: GeoJSON format with polygon geometries
- **Lines**: GeoJSON format with LineString geometries

## Coordinate System

All data uses **UTM Zone 29N (EPSG:29180)** coordinate system for the Morocco region.

## Usage

This organized data structure is designed for:
- Server deployment and visualization
- Database migration (PostGIS)
- API consumption
- Web map rendering

## File Naming Convention

Files follow the pattern: `{chunk}_{class}_{type}.{extension}`

Examples:
- `chunk_1_3_Masts_centroids.json`
- `chunk_2_trees_polygons.geojson`
- `chunk_3_wires_lines.geojson`
"""

    readme_path = f"{TARGET_DATA_DIR}/README.md"
    with open(readme_path, 'w') as f:
        f.write(readme_content)

    logger.info("Created README.md for data folder")

def main():
    """Main function to organize all visualization data"""
    logger.info("Starting data organization for server deployment...")

    # Check if source directory exists
    if not os.path.exists(SOURCE_DIR):
        logger.error(f"Source directory not found: {SOURCE_DIR}")
        return

    # Create directory structure
    create_directory_structure()

    # Copy and organize files
    copy_centroid_files()
    copy_polygon_files()
    copy_line_files()

    # Create metadata files
    create_data_manifest()
    create_readme()

    logger.info("=" * 60)
    logger.info("DATA ORGANIZATION COMPLETE")
    logger.info("=" * 60)
    logger.info(f"Data folder created at: {TARGET_DATA_DIR}")
    logger.info("Contents:")

    # Show final structure
    for root, dirs, files in os.walk(TARGET_DATA_DIR):
        level = root.replace(TARGET_DATA_DIR, '').count(os.sep)
        indent = ' ' * 2 * level
        logger.info(f"{indent}{os.path.basename(root)}/")
        subindent = ' ' * 2 * (level + 1)
        for file in files:
            logger.info(f"{subindent}{file}")

if __name__ == "__main__":
    main()