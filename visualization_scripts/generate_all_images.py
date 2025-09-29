#!/usr/bin/env python3
"""
Generate All Presentation Images
Runs all visualization scripts to create presentation images
"""

import subprocess
import sys
import os

def run_script(script_name):
    """Run a visualization script and handle errors"""
    try:
        print(f"🔄 Running {script_name}...")
        result = subprocess.run([sys.executable, script_name],
                               capture_output=True, text=True, check=True)
        print(f"✅ {script_name} completed successfully")
        if result.stdout:
            print(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"❌ Error running {script_name}:")
        print(f"Exit code: {e.returncode}")
        if e.stdout:
            print(f"STDOUT: {e.stdout}")
        if e.stderr:
            print(f"STDERR: {e.stderr}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error running {script_name}: {e}")
        return False
    return True

def main():
    """Generate all presentation images"""

    # Get the directory containing the visualization scripts
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Change to script directory
    original_dir = os.getcwd()
    os.chdir(script_dir)

    print("🎨 Generating all presentation images...")
    print("=" * 50)

    # List of visualization scripts to run
    scripts = [
        'stage1_data_preparation_viz.py',
        'stage2_class_filtering_viz.py',
        'stage3_clustering_evolution_viz.py',
        'stage4_enhancement_viz.py',
        'production_deployment_viz.py'
    ]

    success_count = 0

    for script in scripts:
        if os.path.exists(script):
            if run_script(script):
                success_count += 1
        else:
            print(f"⚠️  Script not found: {script}")

    # Restore original directory
    os.chdir(original_dir)

    print("=" * 50)
    print(f"📊 Generation complete: {success_count}/{len(scripts)} scripts successful")

    # List generated images
    images_dir = '/home/prodair/Desktop/MORIUS5090/clustering/presentation_images'
    if os.path.exists(images_dir):
        print(f"\n📁 Generated images in {images_dir}:")
        for file in sorted(os.listdir(images_dir)):
            if file.endswith('.png'):
                print(f"   • {file}")

    return success_count == len(scripts)

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)