#!/usr/bin/env python3
"""
Stage 2: Class Filtering Visualization
Shows how mixed point clouds are separated into individual classes
"""

import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
from matplotlib.patches import FancyBboxPatch, Circle
import os

def create_stage2_visualization():
    """Create visualization showing class filtering process"""

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(16, 10))
    fig.suptitle('Stage 2: Class-based Filtering & Separation', fontsize=16, fontweight='bold')

    # Left plot: Mixed point cloud
    ax1.set_xlim(0, 10)
    ax1.set_ylim(0, 12)
    ax1.set_title('Mixed Point Cloud (All Classes)', fontsize=14, fontweight='bold')

    # Draw mixed point cloud with different colored dots representing classes
    np.random.seed(42)
    classes = [
        ('Trees', 7, '#228B22', 150),
        ('Masts', 12, '#DC143C', 50),
        ('Buildings', 6, '#8B4513', 200),
        ('Vegetation', 8, '#90EE90', 100),
        ('Wires', 11, '#FF6600', 80),
        ('Other', 1, '#CCCCCC', 300)
    ]

    legend_elements = []
    y_offset = 0
    for class_name, class_id, color, count in classes:
        # Generate random points for visualization
        x_points = np.random.uniform(1, 9, count // 10)  # Reduce for visualization
        y_points = np.random.uniform(2, 10, count // 10)

        ax1.scatter(x_points, y_points, c=color, s=8, alpha=0.7, label=f'Class {class_id}: {class_name}')
        legend_elements.append(plt.Line2D([0], [0], marker='o', color='w', markerfacecolor=color,
                                         markersize=8, label=f'Class {class_id}: {class_name}'))

    # Add input file info
    input_box = FancyBboxPatch((0.5, 0.5), 9, 1, boxstyle="round,pad=0.1",
                              facecolor='lightgray', edgecolor='black', linewidth=2)
    ax1.add_patch(input_box)
    ax1.text(5, 1, 'cloud_point_part_X.laz (50M+ mixed points)', ha='center', va='center',
            fontweight='bold', fontsize=11)

    ax1.legend(handles=legend_elements, loc='upper right', bbox_to_anchor=(0.98, 0.98))
    ax1.set_xticks([])
    ax1.set_yticks([])

    # Right plot: Separated classes
    ax2.set_xlim(0, 12)
    ax2.set_ylim(0, 12)
    ax2.set_title('Class-Separated LAZ Files', fontsize=14, fontweight='bold')

    # Draw separated class files
    separated_classes = [
        ('7_Trees', '#228B22', 1, 10),
        ('12_Masts', '#DC143C', 1, 8.5),
        ('6_Buildings', '#8B4513', 1, 7),
        ('8_OtherVegetation', '#90EE90', 1, 5.5),
        ('11_Wires', '#FF6600', 1, 4)
    ]

    for class_folder, color, x, y in separated_classes:
        # Class folder
        folder_box = FancyBboxPatch((x, y-0.3), 10, 1, boxstyle="round,pad=0.1",
                                   facecolor=color, edgecolor='black', linewidth=2, alpha=0.7)
        ax2.add_patch(folder_box)

        # Folder structure
        ax2.text(x+0.2, y+0.2, f'{class_folder}/', fontweight='bold', fontsize=11)
        ax2.text(x+0.5, y, f'├── {class_folder}.laz', fontsize=9, family='monospace')
        ax2.text(x+0.5, y-0.2, f'└── metadata.json', fontsize=9, family='monospace')

        # Point count (simulated)
        point_counts = {'7_Trees': '2.3M', '12_Masts': '45K', '6_Buildings': '8.7M',
                       '8_OtherVegetation': '1.2M', '11_Wires': '156K'}
        ax2.text(x+8, y, f'{point_counts.get(class_folder, "N/A")} pts',
                fontsize=10, style='italic',
                bbox=dict(boxstyle="round,pad=0.2", facecolor='white', alpha=0.8))

    # Add processing arrow
    arrow = patches.FancyArrowPatch((9.5, 6), (11.5, 6),
                                   connectionstyle="arc3", arrowstyle='->', mutation_scale=20,
                                   color='red', linewidth=3)
    ax1.add_patch(arrow)
    ax1.text(10.5, 6.5, 'PDAL\nFiltering', ha='center', va='center', fontweight='bold',
            bbox=dict(boxstyle="round,pad=0.3", facecolor='yellow', alpha=0.8))

    # Add command reference
    cmd_box = FancyBboxPatch((1, 2), 10, 1.5, boxstyle="round,pad=0.1",
                            facecolor='lightyellow', edgecolor='orange', linewidth=2)
    ax2.add_patch(cmd_box)
    ax2.text(6, 3, 'Processing Command:', ha='center', fontweight='bold', fontsize=10)
    ax2.text(6, 2.5, './stage2_class_filtering.sh cloud_point_part_X.laz',
            ha='center', family='monospace', fontsize=9,
            bbox=dict(boxstyle="round,pad=0.2", facecolor='white'))

    # Add output structure
    ax2.text(1, 1.5, 'Output Structure:', fontweight='bold')
    ax2.text(1, 1.2, 'chunk_X/compressed/filtred_by_classes/', fontsize=9, family='monospace')
    ax2.text(1, 0.9, '├── 7_Trees/7_Trees.laz', fontsize=8, family='monospace')
    ax2.text(1, 0.7, '├── 12_Masts/12_Masts.laz', fontsize=8, family='monospace')
    ax2.text(1, 0.5, '├── 6_Buildings/6_Buildings.laz', fontsize=8, family='monospace')
    ax2.text(1, 0.3, '└── ... (other classes)', fontsize=8, family='monospace')

    ax2.set_xticks([])
    ax2.set_yticks([])

    # Remove spines for both plots
    for ax in [ax1, ax2]:
        for spine in ax.spines.values():
            spine.set_visible(False)

    plt.tight_layout()

    # Create output directory
    os.makedirs('/home/prodair/Desktop/MORIUS5090/clustering/presentation_images', exist_ok=True)

    # Save the plot
    plt.savefig('/home/prodair/Desktop/MORIUS5090/clustering/presentation_images/stage2_class_filtering.png',
                dpi=300, bbox_inches='tight', facecolor='white')
    plt.close()

    print("✅ Stage 2 visualization saved: presentation_images/stage2_class_filtering.png")

if __name__ == "__main__":
    create_stage2_visualization()