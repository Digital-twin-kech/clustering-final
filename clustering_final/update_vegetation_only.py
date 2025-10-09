#!/usr/bin/env python3
"""
Update Vegetation Polygons Only
Replace old vegetation data with newly reprocessed vegetation
"""

import os
import shutil
import json

# Configuration
SOURCE_BASE = "/home/prodair/Downloads/data-last-berkan/data-last-berkan"
TARGET_BASE = "/home/prodair/Downloads/data-last-berkan/data-last-berkan/data"
DATASET_PREFIX = "berkan"

# All chunks
CHUNKS = list(range(1, 18))  # 1-17

def main():
    print(f"\n{'='*70}")
    print(f"🌿 UPDATING VEGETATION POLYGONS")
    print(f"{'='*70}")
    print(f"📂 Source: {SOURCE_BASE}")
    print(f"📁 Target: {TARGET_BASE}/polygons/vegetation")
    print(f"📊 Chunks: {CHUNKS[0]}-{CHUNKS[-1]}")
    print(f"{'='*70}\n")

    # Target directory
    vegetation_dir = os.path.join(TARGET_BASE, "polygons", "vegetation")
    os.makedirs(vegetation_dir, exist_ok=True)

    total_vegetation = 0
    files_copied = 0

    # Process each chunk
    for chunk_num in CHUNKS:
        chunk_name = f"chunk_{chunk_num}"

        # Source file path
        source_file = os.path.join(
            SOURCE_BASE,
            chunk_name,
            "compressed/filtred_by_classes/8_OtherVegetation/polygons/8_OtherVegetation_polygons.geojson"
        )

        # Target file path
        target_file = os.path.join(
            vegetation_dir,
            f"{DATASET_PREFIX}_{chunk_name}_vegetation_polygons.geojson"
        )

        # Check if source exists
        if os.path.exists(source_file):
            try:
                # Read the file to count vegetation areas
                with open(source_file, 'r') as f:
                    data = json.load(f)
                    num_areas = len(data.get('features', []))

                # Copy file
                shutil.copy2(source_file, target_file)

                print(f"✅ {chunk_name}: {num_areas} vegetation areas -> {os.path.basename(target_file)}")

                total_vegetation += num_areas
                files_copied += 1

            except Exception as e:
                print(f"❌ {chunk_name}: Error - {e}")
        else:
            print(f"⚠️  {chunk_name}: No vegetation file found")

    print(f"\n{'='*70}")
    print(f"📊 VEGETATION UPDATE SUMMARY")
    print(f"{'='*70}")
    print(f"✅ Files updated: {files_copied}")
    print(f"✅ Total vegetation areas: {total_vegetation}")
    print(f"📁 Output directory: {vegetation_dir}")
    print(f"{'='*70}\n")

    print(f"🎉 Vegetation data updated successfully!\n")

if __name__ == "__main__":
    main()
