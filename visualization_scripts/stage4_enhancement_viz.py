#!/usr/bin/env python3
"""
Stage 4: Enhancement Processing Visualization
Shows the detailed enhancement pipeline for different object types
"""

import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
from matplotlib.patches import FancyBboxPatch, Circle, Polygon
import os

def create_stage4_visualization():
    """Create visualization showing enhancement processing for different object types"""

    fig = plt.figure(figsize=(20, 14))
    fig.suptitle('Stage 4: Enhanced Object Processing - Class-Specific Optimization',
                fontsize=18, fontweight='bold')

    # Create grid layout
    gs = fig.add_gridspec(3, 4, height_ratios=[1, 1, 1])

    # Building Processing Pipeline
    ax1 = fig.add_subplot(gs[0, 0])
    ax1.set_title('🏢 Building Processing\n(Instance-based)', fontsize=12, fontweight='bold')

    # Simulate building point cloud and polygon
    np.random.seed(42)
    # Create rectangular building shape
    building_x = np.concatenate([
        np.linspace(2, 8, 20), np.full(15, 8), np.linspace(8, 2, 20), np.full(15, 2)
    ])
    building_y = np.concatenate([
        np.full(20, 2), np.linspace(2, 6, 15), np.full(20, 6), np.linspace(6, 2, 15)
    ])
    # Add some noise
    building_x += np.random.normal(0, 0.2, len(building_x))
    building_y += np.random.normal(0, 0.2, len(building_y))

    ax1.scatter(building_x, building_y, c='blue', alpha=0.6, s=8)

    # Draw concave hull polygon
    building_outline = Polygon([(2, 2), (8, 2), (8, 6), (2, 6)], fill=False,
                              edgecolor='red', linewidth=3, linestyle='--')
    ax1.add_patch(building_outline)

    ax1.set_xlim(0, 10)
    ax1.set_ylim(0, 8)
    ax1.text(5, 7, 'Concave Hull (α=4.0m)\nDouglas-Peucker simplification',
             ha='center', fontsize=9, bbox=dict(boxstyle="round", facecolor='white', alpha=0.8))

    # Building parameters
    ax2 = fig.add_subplot(gs[0, 1])
    ax2.set_title('Building Parameters', fontsize=11, fontweight='bold')

    params_building = [
        'Voxel: 0.3m (precision)',
        'Height: 30th percentile',
        'Outlier: 1.5σ (tight)',
        'DBSCAN: eps=3.0, min=150',
        'Size: 20-5000 m²',
        'Alpha shapes: α=4.0m'
    ]

    for i, param in enumerate(params_building):
        ax2.text(0.1, 0.9 - i*0.13, f'• {param}', fontsize=9, transform=ax2.transAxes)

    ax2.set_xlim(0, 1)
    ax2.set_ylim(0, 1)
    ax2.set_xticks([])
    ax2.set_yticks([])
    for spine in ax2.spines.values():
        spine.set_visible(False)

    # Vegetation Processing Pipeline
    ax3 = fig.add_subplot(gs[0, 2])
    ax3.set_title('🌿 Vegetation Processing\n(Natural boundaries)', fontsize=12, fontweight='bold')

    # Simulate vegetation with organic shapes
    theta = np.linspace(0, 2*np.pi, 50)
    r = 2 + 0.5 * np.sin(5*theta) + np.random.normal(0, 0.1, 50)  # Organic shape
    veg_x = 5 + r * np.cos(theta)
    veg_y = 4 + r * np.sin(theta)

    # Add scattered points
    scatter_x = np.random.normal(5, 2, 100)
    scatter_y = np.random.normal(4, 1.5, 100)

    ax3.scatter(scatter_x, scatter_y, c='green', alpha=0.6, s=8)
    ax3.plot(veg_x, veg_y, 'g-', linewidth=3, alpha=0.8)

    ax3.set_xlim(0, 10)
    ax3.set_ylim(0, 8)
    ax3.text(5, 7, 'Natural boundary detection\nCurved polygons',
             ha='center', fontsize=9, bbox=dict(boxstyle="round", facecolor='lightgreen', alpha=0.8))

    # Vegetation parameters
    ax4 = fig.add_subplot(gs[0, 3])
    ax4.set_title('Vegetation Parameters', fontsize=11, fontweight='bold')

    params_vegetation = [
        'Voxel: 0.4m (balanced)',
        'Height: 20th percentile',
        'Outlier: 1.8σ (moderate)',
        'DBSCAN: eps=4.0, min=80',
        'Size: 10-2000 m²',
        'Preserve edges'
    ]

    for i, param in enumerate(params_vegetation):
        ax4.text(0.1, 0.9 - i*0.13, f'• {param}', fontsize=9, transform=ax4.transAxes)

    ax4.set_xlim(0, 1)
    ax4.set_ylim(0, 1)
    ax4.set_xticks([])
    ax4.set_yticks([])
    for spine in ax4.spines.values():
        spine.set_visible(False)

    # Wire Processing Pipeline
    ax5 = fig.add_subplot(gs[1, 0])
    ax5.set_title('📡 Wire Processing\n(Height-aware lines)', fontsize=12, fontweight='bold')

    # Simulate wire with sag
    wire_x = np.linspace(1, 9, 50)
    wire_y = 4 + 0.5 * np.sin(np.pi * (wire_x - 1) / 8)  # Catenary-like sag

    # Add scattered wire points
    wire_points_x = wire_x + np.random.normal(0, 0.1, 50)
    wire_points_y = wire_y + np.random.normal(0, 0.1, 50)

    ax5.scatter(wire_points_x, wire_points_y, c='orange', alpha=0.7, s=12)
    ax5.plot(wire_x, wire_y, 'r-', linewidth=3, alpha=0.8)

    ax5.set_xlim(0, 10)
    ax5.set_ylim(0, 8)
    ax5.text(5, 6.5, '3D clustering for sag\nPCA line generation',
             ha='center', fontsize=9, bbox=dict(boxstyle="round", facecolor='yellow', alpha=0.8))

    # Wire parameters
    ax6 = fig.add_subplot(gs[1, 1])
    ax6.set_title('Wire Parameters', fontsize=11, fontweight='bold')

    params_wire = [
        'Voxel: 0.2m (preserve detail)',
        'Height: 10th percentile',
        'Outlier: 2.5σ (conservative)',
        'DBSCAN 3D: eps=5.0, min=30',
        'Length: ≥5m wires',
        'Aspect ratio: ≥3:1'
    ]

    for i, param in enumerate(params_wire):
        ax6.text(0.1, 0.9 - i*0.13, f'• {param}', fontsize=9, transform=ax6.transAxes)

    ax6.set_xlim(0, 1)
    ax6.set_ylim(0, 1)
    ax6.set_xticks([])
    ax6.set_yticks([])
    for spine in ax6.spines.values():
        spine.set_visible(False)

    # Processing Flow Comparison
    ax7 = fig.add_subplot(gs[1, 2:])
    ax7.set_title('Processing Flow Comparison by Object Type', fontsize=12, fontweight='bold')

    flow_steps = ['Voxel\nFiltering', 'Height\nFiltering', 'Outlier\nRemoval',
                  'Clustering', 'Shape\nGeneration', 'Validation']

    y_positions = [4, 3, 2]  # Buildings, Vegetation, Wires
    colors = ['#8B4513', '#90EE90', '#FF6600']
    labels = ['Buildings', 'Vegetation', 'Wires']

    for i, (y_pos, color, label) in enumerate(zip(y_positions, colors, labels)):
        ax7.text(-0.5, y_pos, label, fontsize=11, fontweight='bold', ha='right')

        for j, step in enumerate(flow_steps):
            # Draw step box
            box = FancyBboxPatch((j*1.5, y_pos-0.2), 1.3, 0.4, boxstyle="round,pad=0.05",
                               facecolor=color, edgecolor='black', alpha=0.7)
            ax7.add_patch(box)
            ax7.text(j*1.5 + 0.65, y_pos, step, ha='center', va='center', fontsize=8)

            # Draw arrow
            if j < len(flow_steps) - 1:
                arrow = patches.FancyArrowPatch((j*1.5 + 1.3, y_pos), ((j+1)*1.5, y_pos),
                                              arrowstyle='->', mutation_scale=10, color='black')
                ax7.add_patch(arrow)

    ax7.set_xlim(-1, 9)
    ax7.set_ylim(1, 5)
    ax7.set_xticks([])
    ax7.set_yticks([])
    for spine in ax7.spines.values():
        spine.set_visible(False)

    # Results Summary
    ax8 = fig.add_subplot(gs[2, :])
    ax8.set_title('Stage 4 Processing Results & Quality Metrics', fontsize=14, fontweight='bold')

    results_text = """
🏢 BUILDINGS: 302 polygons | ~25,000 m² | Precise footprints with sub-meter accuracy
   • Enhanced instance-based extraction with aggressive filtering
   • Concave hull generation maintains natural building shapes
   • Size validation (20-5000 m²) prevents false positives

🌿 VEGETATION: 131 polygons | ~1,200 m² | Natural curved boundaries
   • Balanced processing preserves vegetation edges while filtering noise
   • Organic shape detection with moderate clustering parameters
   • Multi-area support handles scattered vegetation patches

📡 WIRES: 103 lines | ~2,100m total | Continuous infrastructure mapping
   • Height-aware 3D clustering accounts for natural wire sag
   • PCA-based line generation creates smooth continuous paths
   • Conservative filtering preserves critical wire endpoints
   • Linearity validation ensures wire-like characteristics (aspect ratio ≥3:1)

🎯 QUALITY ACHIEVEMENTS:
   ✅ Sub-meter coordinate accuracy maintained throughout pipeline
   ✅ Class-specific optimization provides optimal results per object type
   ✅ Automated validation prevents false positives and ensures data quality
   ✅ Scalable processing handles datasets with 50M+ points per chunk
    """

    ax8.text(0.05, 0.95, results_text, fontsize=10, transform=ax8.transAxes,
             verticalalignment='top', bbox=dict(boxstyle="round,pad=0.02", facecolor='lightblue', alpha=0.3))

    ax8.set_xlim(0, 1)
    ax8.set_ylim(0, 1)
    ax8.set_xticks([])
    ax8.set_yticks([])
    for spine in ax8.spines.values():
        spine.set_visible(False)

    plt.tight_layout()

    # Create output directory
    os.makedirs('/home/prodair/Desktop/MORIUS5090/clustering/presentation_images', exist_ok=True)

    # Save the plot
    plt.savefig('/home/prodair/Desktop/MORIUS5090/clustering/presentation_images/stage4_enhancement_processing.png',
                dpi=300, bbox_inches='tight', facecolor='white')
    plt.close()

    print("✅ Stage 4 visualization saved: presentation_images/stage4_enhancement_processing.png")

if __name__ == "__main__":
    create_stage4_visualization()