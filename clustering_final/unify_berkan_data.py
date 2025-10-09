#!/usr/bin/env python3
"""
Unify Berkan Dataset to Server Data Structure
Copies and organizes processed LiDAR data from data-last-berkan chunks
into the server data_new_2 directory with proper naming convention
"""

import os
import json
import shutil
from pathlib import Path
from datetime import datetime

# Configuration
SOURCE_BASE = "/home/prodair/Downloads/data-last-berkan/data-last-berkan"
TARGET_BASE = "/home/prodair/Desktop/MORIUS5090/clustering/clustering_final/server/data_new_2"
DATASET_PREFIX = "berkan"  # Prefix for file naming

# Class mappings
CLASS_TYPES = {
    "7_Trees": {"type": "centroids", "subdir": None, "suffix": "7_Trees_centroids.json", "source_file": "7_Trees_centroids.json"},
    "12_Masts": {"type": "centroids", "subdir": None, "suffix": "12_Masts_centroids.json", "source_file": "12_Masts_centroids.json"},
    "6_Buildings": {"type": "polygons", "subdir": "buildings", "suffix": "buildings_polygons.geojson", "source_file": "6_Buildings_polygons.geojson"},
    "8_OtherVegetation": {"type": "polygons", "subdir": "vegetation", "suffix": "vegetation_polygons.geojson", "source_file": "8_OtherVegetation_polygons.geojson"},
    "11_Wires": {"type": "lines", "subdir": "wires", "suffix": "wires_lines.geojson", "source_file": "11_Wires_lines.geojson"}
}

def create_directory_structure(base_path):
    """Create the target directory structure"""
    print(f"\n📁 Creating directory structure at: {base_path}")

    # Main directories
    dirs = [
        base_path,
        f"{base_path}/centroids",
        f"{base_path}/polygons",
        f"{base_path}/polygons/buildings",
        f"{base_path}/polygons/vegetation",
        f"{base_path}/lines",
        f"{base_path}/lines/wires"
    ]

    for directory in dirs:
        os.makedirs(directory, exist_ok=True)
        print(f"  ✅ {directory}")

    print()

def find_chunk_directories(source_base):
    """Find all chunk directories in source"""
    chunks = []
    for item in sorted(os.listdir(source_base)):
        if item.startswith("chunk_") and os.path.isdir(os.path.join(source_base, item)):
            chunks.append(item)
    return chunks

def process_chunk(chunk_name, source_base, target_base, dataset_prefix):
    """Process a single chunk and copy its data"""
    print(f"\n🔄 Processing {chunk_name}...")

    chunk_path = os.path.join(source_base, chunk_name)
    classes_path = os.path.join(chunk_path, "compressed/filtred_by_classes")

    if not os.path.exists(classes_path):
        print(f"  ⚠️  No filtred_by_classes directory found")
        return {}

    # Extract chunk number
    chunk_num = chunk_name.replace("chunk_", "")

    stats = {
        "centroids": 0,
        "polygons": 0,
        "lines": 0
    }

    # Process each class type
    for class_name, config in CLASS_TYPES.items():
        class_dir = os.path.join(classes_path, class_name)

        if not os.path.exists(class_dir):
            continue

        # Determine source file path based on type
        if config["type"] == "centroids":
            source_file = os.path.join(class_dir, "centroids", config["source_file"])
        elif config["type"] == "polygons":
            source_file = os.path.join(class_dir, "polygons", config["source_file"])
        elif config["type"] == "lines":
            source_file = os.path.join(class_dir, "lines", config["source_file"])
        else:
            continue

        if not os.path.exists(source_file):
            print(f"  ⚠️  {class_name}: File not found - {os.path.basename(source_file)}")
            continue

        # Build target file path
        if config["subdir"]:
            target_dir = os.path.join(target_base, config["type"], config["subdir"])
        else:
            target_dir = os.path.join(target_base, config["type"])

        # Create target filename: berkan_chunk_9_7_Trees_centroids.json
        target_filename = f"{dataset_prefix}_chunk_{chunk_num}_{config['suffix']}"
        target_file = os.path.join(target_dir, target_filename)

        # Copy file
        try:
            shutil.copy2(source_file, target_file)
            file_size = os.path.getsize(target_file)
            stats[config["type"]] += 1
            print(f"  ✅ {class_name}: {target_filename} ({file_size:,} bytes)")
        except Exception as e:
            print(f"  ❌ {class_name}: Failed to copy - {e}")

    return stats

def generate_manifest(target_base, chunks_processed, total_stats, dataset_prefix):
    """Generate manifest.json file"""
    print(f"\n📋 Generating manifest.json...")

    manifest = {
        "dataset_info": {
            "name": "Berkan LiDAR Dataset Processing Results",
            "source": SOURCE_BASE,
            "processing_date": datetime.now().strftime("%Y-%m-%d"),
            "chunks_processed": sorted([int(c.replace("chunk_", "")) for c in chunks_processed]),
            "coordinate_system": "UTM Zone 29N (EPSG:32629)",
            "region": "Western Morocco"
        },
        "processing_summary": {
            "total_chunks": len(chunks_processed),
            "chunks_available": sorted(chunks_processed),
            "classes_processed": ["Trees", "Masts", "Buildings", "Vegetation", "Wires"],
            "processing_methods": {
                "trees": "Lightweight 2D projection clustering (DBSCAN)",
                "masts": "Lightweight 2D projection clustering (DBSCAN)",
                "buildings": "Enhanced footprint-based polygon extraction (alpha shapes)",
                "vegetation": "Natural boundary detection with curved polygons (concave hull)",
                "wires": "Height-aware 3D line segmentation (PCA-based)"
            }
        },
        "data_structure": {
            "centroids": {
                "description": "Point features (Trees + Masts)",
                "count": total_stats["centroids"],
                "format": "JSON with UTM coordinates"
            },
            "polygons": {
                "buildings": {
                    "description": "Building footprint polygons",
                    "count": sum(1 for f in os.listdir(f"{target_base}/polygons/buildings") if f.endswith(".geojson")),
                    "format": "GeoJSON with UTM coordinates"
                },
                "vegetation": {
                    "description": "Vegetation area polygons",
                    "count": sum(1 for f in os.listdir(f"{target_base}/polygons/vegetation") if f.endswith(".geojson")),
                    "format": "GeoJSON with UTM coordinates"
                }
            },
            "lines": {
                "wires": {
                    "description": "Wire infrastructure lines",
                    "count": sum(1 for f in os.listdir(f"{target_base}/lines/wires") if f.endswith(".geojson")),
                    "format": "GeoJSON LineString with UTM coordinates"
                }
            }
        },
        "statistics": {
            "files_total": total_stats["centroids"] + total_stats["polygons"] + total_stats["lines"],
            "centroids_files": total_stats["centroids"],
            "polygon_files": total_stats["polygons"],
            "line_files": total_stats["lines"],
            "data_quality": "High - comprehensive processing with strict quality filters"
        },
        "coordinate_conversion": {
            "input": "UTM Zone 29N (EPSG:32629)",
            "output": "WGS84 (EPSG:4326) for web visualization",
            "transformation": "Automatic via server-side conversion"
        },
        "file_naming_convention": {
            "pattern": f"{dataset_prefix}_chunk_<N>_<class>_<type>.<ext>",
            "examples": [
                f"{dataset_prefix}_chunk_9_7_Trees_centroids.json",
                f"{dataset_prefix}_chunk_10_buildings_polygons.geojson",
                f"{dataset_prefix}_chunk_11_wires_lines.geojson"
            ]
        }
    }

    manifest_file = os.path.join(target_base, "manifest.json")
    with open(manifest_file, 'w') as f:
        json.dump(manifest, f, indent=2)

    print(f"  ✅ Manifest saved: {manifest_file}")

def main():
    """Main execution function"""
    print("=" * 70)
    print("🚀 BERKAN DATASET UNIFICATION TOOL")
    print("=" * 70)
    print(f"📂 Source: {SOURCE_BASE}")
    print(f"📁 Target: {TARGET_BASE}")
    print(f"🏷️  Prefix: {DATASET_PREFIX}")
    print("=" * 70)

    # Create directory structure
    create_directory_structure(TARGET_BASE)

    # Find all chunks
    chunks = find_chunk_directories(SOURCE_BASE)
    print(f"📊 Found {len(chunks)} chunks to process: {', '.join(chunks)}")

    if not chunks:
        print("❌ No chunks found!")
        return

    # Process each chunk
    total_stats = {
        "centroids": 0,
        "polygons": 0,
        "lines": 0
    }

    chunks_processed = []

    for chunk in chunks:
        stats = process_chunk(chunk, SOURCE_BASE, TARGET_BASE, DATASET_PREFIX)
        if any(stats.values()):
            chunks_processed.append(chunk)
            for key in total_stats:
                total_stats[key] += stats.get(key, 0)

    # Generate manifest
    if chunks_processed:
        generate_manifest(TARGET_BASE, chunks_processed, total_stats, DATASET_PREFIX)

    # Final summary
    print("\n" + "=" * 70)
    print("✅ UNIFICATION COMPLETE!")
    print("=" * 70)
    print(f"📊 Summary:")
    print(f"   Chunks processed: {len(chunks_processed)}")
    print(f"   Centroid files: {total_stats['centroids']}")
    print(f"   Polygon files: {total_stats['polygons']}")
    print(f"   Line files: {total_stats['lines']}")
    print(f"   Total files: {sum(total_stats.values())}")
    print(f"\n📁 Output directory: {TARGET_BASE}")
    print(f"📋 Manifest: {TARGET_BASE}/manifest.json")
    print("=" * 70)

    # List some sample files
    print(f"\n📄 Sample files created:")
    sample_count = 0
    for root, dirs, files in os.walk(TARGET_BASE):
        for file in sorted(files)[:5]:
            if file.endswith(('.json', '.geojson')):
                rel_path = os.path.relpath(os.path.join(root, file), TARGET_BASE)
                print(f"   - {rel_path}")
                sample_count += 1
                if sample_count >= 5:
                    break
        if sample_count >= 5:
            break

    print("\n🎉 Ready for visualization server!")

if __name__ == "__main__":
    main()
