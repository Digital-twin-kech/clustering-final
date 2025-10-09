#!/usr/bin/env python3
"""
Add Buildings from new_data Dataset to Visualization
"""

import os
import shutil
import json
from pathlib import Path

# Configuration
SOURCE_BASE = "/home/prodair/Desktop/clustering/datasetclasified/new_data/new_data"
TARGET_BASE = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final/server/data_buildings"
DATASET_PREFIX = "newdata"

# Chunks available in new_data
CHUNKS = [2, 5, 6, 7, 8]

def main():
    print(f"\n{'='*70}")
    print(f"🏢 ADDING NEW_DATA BUILDINGS TO VISUALIZATION")
    print(f"{'='*70}")
    print(f"📂 Source: {SOURCE_BASE}")
    print(f"📁 Target: {TARGET_BASE}")
    print(f"📊 Chunks: {CHUNKS}")
    print(f"{'='*70}\n")

    # Target directory
    polygons_dir = os.path.join(TARGET_BASE, "polygons", "buildings")

    total_buildings = 0
    files_copied = 0
    chunks_processed = 0

    # Process each chunk
    for chunk_num in CHUNKS:
        chunk_name = f"chunk_{chunk_num}"

        # Source file path
        source_file = os.path.join(
            SOURCE_BASE,
            chunk_name,
            "compressed/filtred_by_classes/6_Buildings/polygons/6_Buildings_polygons.geojson"
        )

        # Target file path with renamed format
        target_file = os.path.join(
            polygons_dir,
            f"{DATASET_PREFIX}_{chunk_name}_buildings_polygons.geojson"
        )

        # Check if source exists
        if os.path.exists(source_file):
            # Read the file to count buildings
            try:
                with open(source_file, 'r') as f:
                    data = json.load(f)
                    num_buildings = len(data.get('features', []))

                # Copy file
                shutil.copy2(source_file, target_file)

                print(f"✅ {chunk_name}: {num_buildings} buildings -> {os.path.basename(target_file)}")

                total_buildings += num_buildings
                files_copied += 1
                chunks_processed += 1

            except Exception as e:
                print(f"❌ {chunk_name}: Error processing file - {e}")
        else:
            print(f"⚠️  {chunk_name}: No building file found")

    print(f"\n{'='*70}")
    print(f"📊 NEW_DATA BUILDINGS ADDED")
    print(f"{'='*70}")
    print(f"✅ Chunks processed: {chunks_processed}")
    print(f"✅ Files copied: {files_copied}")
    print(f"✅ Buildings added: {total_buildings}")
    print(f"📁 Output directory: {polygons_dir}")
    print(f"{'='*70}\n")

    # Update manifest
    manifest_file = os.path.join(TARGET_BASE, "manifest.json")

    try:
        with open(manifest_file, 'r') as f:
            manifest = json.load(f)
    except:
        manifest = {}

    # Add new_data info
    manifest["datasets"] = {
        "berkan": {
            "chunks": list(range(9, 18)),
            "buildings": manifest.get("total_buildings", 169)
        },
        "newdata": {
            "chunks": CHUNKS,
            "buildings": total_buildings
        }
    }
    manifest["total_buildings_combined"] = manifest.get("total_buildings", 169) + total_buildings

    with open(manifest_file, 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f"✅ Updated manifest: {manifest_file}")
    print(f"📊 Total buildings in visualization: {manifest['total_buildings_combined']}")
    print(f"\n🎉 New_data buildings added successfully!\n")

if __name__ == "__main__":
    main()
