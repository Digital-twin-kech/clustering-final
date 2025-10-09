#!/usr/bin/env python3
"""
Complete Berkan Data Unification
Collects all processed data including new traffic lights and signs classes
Follows the structure of clustering/clustering_final/server/data
"""

import os
import shutil
import json
from pathlib import Path

# Configuration
SOURCE_BASE = "/home/prodair/Downloads/data-last-berkan/data-last-berkan"
TARGET_BASE = "/home/prodair/Downloads/data-last-berkan/data-last-berkan/data"
DATASET_PREFIX = "berkan"

# Chunks to process - ALL chunks from 1 to 17
CHUNKS = list(range(1, 18))  # 1-17

# Data types to collect
DATA_TYPES = {
    "centroids": [
        {
            "class_name": "7_Trees",
            "source_file": "7_Trees_centroids.json",
            "target_file": "7_Trees_centroids.json",
            "subdir": None
        },
        {
            "class_name": "12_Masts",
            "source_file": "12_Masts_centroids.json",
            "target_file": "12_Masts_centroids.json",
            "subdir": None
        },
        {
            "class_name": "9_TrafficLights",
            "source_file": "9_TrafficLights_centroids.json",
            "target_file": "9_TrafficLights_centroids.json",
            "subdir": None
        },
        {
            "class_name": "10_TrafficSigns",
            "source_file": "10_TrafficSigns_centroids.json",
            "target_file": "10_TrafficSigns_centroids.json",
            "subdir": None
        }
    ],
    "polygons": [
        {
            "class_name": "6_Buildings",
            "source_file": "6_Buildings_polygons.geojson",
            "target_file": "buildings_polygons.geojson",
            "subdir": "buildings"
        },
        {
            "class_name": "8_OtherVegetation",
            "source_file": "8_OtherVegetation_polygons.geojson",
            "target_file": "vegetation_polygons.geojson",
            "subdir": "vegetation"
        }
    ],
    "lines": [
        {
            "class_name": "11_Wires",
            "source_file": "11_Wires_lines.geojson",
            "target_file": "wires_lines.geojson",
            "subdir": "wires"
        }
    ]
}

def main():
    print(f"\n{'='*70}")
    print(f"📦 COMPLETE BERKAN DATA UNIFICATION")
    print(f"{'='*70}")
    print(f"📂 Source: {SOURCE_BASE}")
    print(f"📁 Target: {TARGET_BASE}")
    print(f"📊 Chunks: {CHUNKS[0]}-{CHUNKS[-1]}")
    print(f"🎯 Classes: Trees, Masts, TrafficLights (NEW), TrafficSigns (NEW),")
    print(f"           Buildings, Vegetation, Wires")
    print(f"{'='*70}\n")

    # Create target directory structure
    centroids_dir = os.path.join(TARGET_BASE, "centroids")
    polygons_base = os.path.join(TARGET_BASE, "polygons")
    lines_base = os.path.join(TARGET_BASE, "lines")

    os.makedirs(centroids_dir, exist_ok=True)
    os.makedirs(polygons_base, exist_ok=True)
    os.makedirs(lines_base, exist_ok=True)

    # Statistics
    stats = {
        "centroids": {},
        "polygons": {},
        "lines": {}
    }
    total_files = 0

    # Process each data type
    for data_type, configs in DATA_TYPES.items():
        print(f"\n{'='*70}")
        print(f"📋 Processing {data_type.upper()}")
        print(f"{'='*70}\n")

        for config in configs:
            class_name = config["class_name"]
            source_file = config["source_file"]
            target_file = config["target_file"]
            subdir = config["subdir"]

            print(f"🔍 {class_name}:")

            # Determine source and target paths
            if data_type == "centroids":
                source_subpath = f"{class_name}/centroids/{source_file}"
                target_base_dir = centroids_dir
            elif data_type == "polygons":
                source_subpath = f"{class_name}/polygons/{source_file}"
                target_base_dir = os.path.join(polygons_base, subdir)
                os.makedirs(target_base_dir, exist_ok=True)
            elif data_type == "lines":
                source_subpath = f"{class_name}/lines/{source_file}"
                target_base_dir = os.path.join(lines_base, subdir)
                os.makedirs(target_base_dir, exist_ok=True)

            files_copied = 0
            items_counted = 0

            # Process each chunk
            for chunk_num in CHUNKS:
                chunk_name = f"chunk_{chunk_num}"

                # Source file path
                source_path = os.path.join(
                    SOURCE_BASE,
                    chunk_name,
                    "compressed/filtred_by_classes",
                    source_subpath
                )

                # Target file path with renamed format
                target_filename = f"{DATASET_PREFIX}_{chunk_name}_{target_file}"
                target_path = os.path.join(target_base_dir, target_filename)

                # Check if source exists
                if os.path.exists(source_path):
                    try:
                        # Read the file to count items
                        with open(source_path, 'r') as f:
                            data = json.load(f)

                        if data_type == "centroids":
                            num_items = len(data.get('centroids', []))
                        else:  # polygons or lines
                            num_items = len(data.get('features', []))

                        # Copy file
                        shutil.copy2(source_path, target_path)

                        print(f"   ✅ {chunk_name}: {num_items} items -> {target_filename}")

                        files_copied += 1
                        items_counted += num_items

                    except Exception as e:
                        print(f"   ❌ {chunk_name}: Error - {e}")
                else:
                    print(f"   ⚠️  {chunk_name}: Not found")

            # Update statistics
            if files_copied > 0:
                stats[data_type][class_name] = {
                    "files": files_copied,
                    "items": items_counted
                }
                total_files += files_copied

                print(f"   📊 Total: {files_copied} files, {items_counted} items\n")

    # Generate summary
    print(f"\n{'='*70}")
    print(f"📊 UNIFICATION SUMMARY")
    print(f"{'='*70}")

    print(f"\n✅ CENTROIDS:")
    for class_name, stat in stats["centroids"].items():
        print(f"   • {class_name}: {stat['files']} files, {stat['items']} objects")

    print(f"\n✅ POLYGONS:")
    for class_name, stat in stats["polygons"].items():
        print(f"   • {class_name}: {stat['files']} files, {stat['items']} polygons")

    print(f"\n✅ LINES:")
    for class_name, stat in stats["lines"].items():
        print(f"   • {class_name}: {stat['files']} files, {stat['items']} lines")

    print(f"\n📁 Total files: {total_files}")
    print(f"📂 Output directory: {TARGET_BASE}")

    # Create comprehensive manifest
    manifest = {
        "dataset": "berkan_complete",
        "source": SOURCE_BASE,
        "chunks": CHUNKS,
        "classes": {
            "centroids": {
                "7_Trees": "Tree centroids",
                "12_Masts": "Utility pole/mast centroids",
                "9_TrafficLights": "Traffic light centroids (NEW)",
                "10_TrafficSigns": "Traffic sign centroids (NEW)"
            },
            "polygons": {
                "6_Buildings": "Building footprint polygons",
                "8_OtherVegetation": "Vegetation area polygons"
            },
            "lines": {
                "11_Wires": "Wire/cable line geometries"
            }
        },
        "statistics": stats,
        "structure": {
            "centroids/": "Object centroids (JSON)",
            "polygons/buildings/": "Building footprints (GeoJSON)",
            "polygons/vegetation/": "Vegetation areas (GeoJSON)",
            "lines/wires/": "Wire lines (GeoJSON)"
        },
        "coordinate_system": "UTM Zone 29N (EPSG:32629)",
        "extraction_methods": {
            "buildings": "python_instance_enhanced_fixed1",
            "vegetation": "python_vegetation_enhanced (or _fixed1)",
            "wires": "python_wire_enhanced",
            "centroids": "stage3_lightweight_clustering (2D projection)"
        }
    }

    manifest_file = os.path.join(TARGET_BASE, "manifest.json")
    with open(manifest_file, 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f"\n✅ Created manifest: {manifest_file}")

    # Create README
    readme_content = f"""# Berkan LiDAR Dataset - Complete Unified Data

## Overview
This directory contains the complete processed LiDAR data from the Berkan dataset (chunks 9-17).

## Data Structure
```
data/
├── centroids/              # Object centroids (point features)
│   ├── berkan_chunk_X_7_Trees_centroids.json
│   ├── berkan_chunk_X_12_Masts_centroids.json
│   ├── berkan_chunk_X_9_TrafficLights_centroids.json    (NEW)
│   └── berkan_chunk_X_10_TrafficSigns_centroids.json    (NEW)
├── polygons/
│   ├── buildings/          # Building footprints
│   │   └── berkan_chunk_X_buildings_polygons.geojson
│   └── vegetation/         # Vegetation areas
│       └── berkan_chunk_X_vegetation_polygons.geojson
├── lines/
│   └── wires/             # Wire/cable lines
│       └── berkan_chunk_X_wires_lines.geojson
├── manifest.json          # Dataset metadata
└── README.md             # This file
```

## Classes Included

### Centroids (Point Features)
- **7_Trees**: Tree centroids with point counts
- **12_Masts**: Utility pole/mast centroids
- **9_TrafficLights**: Traffic light positions (NEW)
- **10_TrafficSigns**: Traffic sign positions (NEW)

### Polygons (Area Features)
- **6_Buildings**: Building footprint polygons
- **8_OtherVegetation**: Vegetation area polygons

### Lines (Linear Features)
- **11_Wires**: Wire/cable line geometries

## Coordinate System
- **SRID**: EPSG:32629 (UTM Zone 29N)
- All coordinates are in UTM meters

## Extraction Methods
- **Buildings**: python_instance_enhanced_fixed1.py (DBSCAN with relaxed parameters)
- **Vegetation**: python_vegetation_enhanced.py or _fixed1.py
- **Wires**: python_wire_enhanced.py
- **Centroids**: stage3_lightweight_clustering.sh (2D projection method)

## Statistics
Total chunks processed: {len(CHUNKS)} (chunks {CHUNKS[0]}-{CHUNKS[-1]})
Total files: {total_files}

## Usage
This data is ready for:
1. Visualization in web dashboards
2. GIS analysis
3. Machine learning training
4. Urban planning applications
5. Database ingestion (PostGIS)

## Notes
- Traffic lights and signs are new additions to the dataset
- All files follow the naming convention: `berkan_chunk_{{N}}_{{type}}_{{feature}}.{{ext}}`
- JSON files contain centroids with object counts
- GeoJSON files contain polygon/line geometries
"""

    readme_file = os.path.join(TARGET_BASE, "README.md")
    with open(readme_file, 'w') as f:
        f.write(readme_content)

    print(f"✅ Created README: {readme_file}")

    print(f"\n{'='*70}")
    print(f"🎉 COMPLETE DATA UNIFICATION SUCCESSFUL!")
    print(f"{'='*70}\n")

if __name__ == "__main__":
    main()
