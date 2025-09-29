#!/usr/bin/env python3
"""
Stage 1: Data Preparation Visualization
Shows the initial data organization and chunking process
"""

import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
from matplotlib.patches import FancyBboxPatch
import os

def create_stage1_visualization():
    """Create visualization showing data preparation stage"""

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 8))
    fig.suptitle('Stage 1: Data Preparation & Organization', fontsize=16, fontweight='bold')

    # Left plot: Raw data input
    ax1.set_xlim(0, 10)
    ax1.set_ylim(0, 10)
    ax1.set_title('Raw LiDAR Point Clouds', fontsize=14, fontweight='bold')

    # Draw raw LAZ files
    laz_files = [
        ('cloud_point_part_1.laz', 2, 8, '#FF6B6B'),
        ('cloud_point_part_2.laz', 2, 6.5, '#4ECDC4'),
        ('cloud_point_part_3.laz', 2, 5, '#45B7D1'),
        ('cloud_point_part_4.laz', 2, 3.5, '#96CEB4'),
        ('cloud_point_part_5.laz', 2, 2, '#FFEAA7')
    ]

    for filename, x, y, color in laz_files:
        # File box
        file_box = FancyBboxPatch((x-0.5, y-0.3), 6, 0.6, boxstyle="round,pad=0.1",
                                 facecolor=color, edgecolor='black', linewidth=2)
        ax1.add_patch(file_box)
        ax1.text(x+2.5, y, filename, ha='center', va='center', fontweight='bold')
        ax1.text(x+2.5, y-0.15, '300-350MB', ha='center', va='center', fontsize=9, style='italic')

    # Add properties text
    ax1.text(0.5, 9.5, 'Properties:', fontweight='bold', fontsize=12)
    properties = [
        '• 50+ million points per chunk',
        '• Mixed object classes (1-19)',
        '• UTM Zone 29N coordinates',
        '• Western Morocco region'
    ]
    for i, prop in enumerate(properties):
        ax1.text(0.5, 9.2-i*0.3, prop, fontsize=10)

    ax1.set_xticks([])
    ax1.set_yticks([])
    ax1.spines['top'].set_visible(False)
    ax1.spines['right'].set_visible(False)
    ax1.spines['bottom'].set_visible(False)
    ax1.spines['left'].set_visible(False)

    # Right plot: Organized structure
    ax2.set_xlim(0, 10)
    ax2.set_ylim(0, 10)
    ax2.set_title('Organized Chunk Structure', fontsize=14, fontweight='bold')

    # Draw organized chunks
    chunks = [
        ('chunk_1/', 1, 8.5, '#FF6B6B'),
        ('chunk_2/', 1, 7, '#4ECDC4'),
        ('chunk_3/', 1, 5.5, '#45B7D1'),
        ('chunk_4/', 1, 4, '#96CEB4'),
        ('chunk_5/', 1, 2.5, '#FFEAA7')
    ]

    for chunk_name, x, y, color in chunks:
        # Main chunk folder
        chunk_box = FancyBboxPatch((x, y-0.2), 8, 1.2, boxstyle="round,pad=0.1",
                                  facecolor=color, edgecolor='black', linewidth=2, alpha=0.7)
        ax2.add_patch(chunk_box)
        ax2.text(x+0.5, y+0.3, chunk_name, fontweight='bold', fontsize=11)

        # Subfolders
        ax2.text(x+0.5, y, '├── compressed/', fontsize=9, family='monospace')
        ax2.text(x+0.5, y-0.2, '├── metadata/', fontsize=9, family='monospace')
        ax2.text(x+0.5, y-0.4, '└── validation/', fontsize=9, family='monospace')

        # Size info
        ax2.text(x+6, y, f'~{np.random.randint(45, 55)}M pts', fontsize=9,
                style='italic', bbox=dict(boxstyle="round,pad=0.3", facecolor='white', alpha=0.8))

    # Add coordinate system info
    coord_box = FancyBboxPatch((1, 0.5), 8, 1, boxstyle="round,pad=0.1",
                              facecolor='lightblue', edgecolor='navy', linewidth=2, alpha=0.3)
    ax2.add_patch(coord_box)
    ax2.text(5, 1, 'Coordinate System: UTM Zone 29N (EPSG:29180)',
            ha='center', va='center', fontweight='bold', fontsize=10)
    ax2.text(5, 0.7, 'Region: Western Morocco | Units: Meters',
            ha='center', va='center', fontsize=9, style='italic')

    ax2.set_xticks([])
    ax2.set_yticks([])
    ax2.spines['top'].set_visible(False)
    ax2.spines['right'].set_visible(False)
    ax2.spines['bottom'].set_visible(False)
    ax2.spines['left'].set_visible(False)

    plt.tight_layout()

    # Create output directory if it doesn't exist
    os.makedirs('/home/prodair/Desktop/MORIUS5090/clustering/presentation_images', exist_ok=True)

    # Save the plot
    plt.savefig('/home/prodair/Desktop/MORIUS5090/clustering/presentation_images/stage1_data_preparation.png',
                dpi=300, bbox_inches='tight', facecolor='white')
    plt.close()

    print("✅ Stage 1 visualization saved: presentation_images/stage1_data_preparation.png")

if __name__ == "__main__":
    create_stage1_visualization()