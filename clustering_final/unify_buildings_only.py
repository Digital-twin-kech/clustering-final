#!/usr/bin/env python3
"""
Unify Buildings Data Only - For Fixed Building Extraction Testing
"""

import os
import shutil
import json
from pathlib import Path

# Configuration
SOURCE_BASE = "/home/prodair/Downloads/data-last-berkan/data-last-berkan"
TARGET_BASE = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final/server/data_buildings"
DATASET_PREFIX = "berkan"

# Chunks to process
CHUNKS = list(range(9, 18))  # 9-17

def main():
    print(f"\n{'='*70}")
    print(f"🏢 UNIFYING BUILDING POLYGONS - FIXED VERSION")
    print(f"{'='*70}")
    print(f"📂 Source: {SOURCE_BASE}")
    print(f"📁 Target: {TARGET_BASE}")
    print(f"📊 Chunks: {CHUNKS[0]}-{CHUNKS[-1]}")
    print(f"{'='*70}\n")

    # Create target directory structure
    polygons_dir = os.path.join(TARGET_BASE, "polygons", "buildings")
    os.makedirs(polygons_dir, exist_ok=True)

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
    print(f"📊 UNIFICATION SUMMARY")
    print(f"{'='*70}")
    print(f"✅ Chunks processed: {chunks_processed}")
    print(f"✅ Files copied: {files_copied}")
    print(f"✅ Total buildings: {total_buildings}")
    print(f"📁 Output directory: {TARGET_BASE}")
    print(f"{'='*70}\n")

    # Create manifest
    manifest = {
        "dataset": "berkan_buildings_fixed",
        "extraction_method": "python_instance_enhanced_fixed1",
        "chunks": CHUNKS,
        "total_buildings": total_buildings,
        "files": files_copied,
        "structure": {
            "polygons/buildings/": "Building footprint polygons (GeoJSON)"
        }
    }

    manifest_file = os.path.join(TARGET_BASE, "manifest.json")
    with open(manifest_file, 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f"✅ Created manifest: {manifest_file}")
    print(f"\n🎉 Building data unification complete!\n")

if __name__ == "__main__":
    main()
