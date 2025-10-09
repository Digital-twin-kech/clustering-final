#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
from pathlib import Path

def convert_laz_to_las(input_dir, output_dir):
    total_converted = 0
    total_failed = 0

    # Walk through all LAZ files
    for root, dirs, files in os.walk(input_dir):
        for file in files:
            if file.endswith('.laz'):
                # Input file path
                input_file = os.path.join(root, file)

                # Calculate relative path and create output structure
                rel_path = os.path.relpath(root, input_dir)
                output_subdir = os.path.join(output_dir, rel_path)
                os.makedirs(output_subdir, exist_ok=True)

                # Output file path (change extension)
                output_file = os.path.join(output_subdir, file.replace('.laz', '.las'))

                print(f"Converting: {os.path.basename(input_file)}")

                try:
                    # Use PDAL translate to convert LAZ to LAS
                    result = subprocess.run([
                        'pdal', 'translate', input_file, output_file,
                        '--writers.las.compression=false'
                    ], capture_output=True, text=True, timeout=30)

                    if result.returncode == 0:
                        total_converted += 1
                    else:
                        print(f"  ERROR: {result.stderr.strip()}")
                        total_failed += 1

                except subprocess.TimeoutExpired:
                    print(f"  ERROR: Timeout converting {file}")
                    total_failed += 1
                except Exception as e:
                    print(f"  ERROR: {str(e)}")
                    total_failed += 1

            elif file.endswith('.json'):
                # Copy JSON files as-is
                input_file = os.path.join(root, file)
                rel_path = os.path.relpath(root, input_dir)
                output_subdir = os.path.join(output_dir, rel_path)
                os.makedirs(output_subdir, exist_ok=True)
                output_file = os.path.join(output_subdir, file)
                shutil.copy2(input_file, output_file)

    return total_converted, total_failed

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: convert_batch.py <input_dir> <output_dir>")
        sys.exit(1)

    input_dir = sys.argv[1]
    output_dir = sys.argv[2]

    converted, failed = convert_laz_to_las(input_dir, output_dir)

    print(f"\nConversion completed!")
    print(f"Converted: {converted}")
    print(f"Failed: {failed}")
    if converted + failed > 0:
        print(f"Success rate: {converted*100/(converted+failed):.1f}%")
