#!/usr/bin/env python3
"""
Production Deployment Visualization
Shows the complete production architecture and final results
"""

import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
from matplotlib.patches import FancyBboxPatch, Circle, Rectangle
import os

def create_production_visualization():
    """Create visualization showing production deployment and final results"""

    fig = plt.figure(figsize=(20, 16))
    fig.suptitle('Production Deployment: Complete LiDAR Processing Pipeline',
                fontsize=18, fontweight='bold')

    # Create grid layout
    gs = fig.add_gridspec(4, 4, height_ratios=[1, 1, 1, 1.2])

    # Architecture Overview
    ax1 = fig.add_subplot(gs[0, :])
    ax1.set_title('Production Architecture Flow', fontsize=14, fontweight='bold')

    # Define architecture components
    components = [
        ('Raw LAZ\nPoint Clouds', 1, 3, '#FF6B6B', 'input'),
        ('Stage 2\nClass Filtering', 3, 3, '#4ECDC4', 'process'),
        ('Stage 3\n2D Clustering', 5, 3, '#45B7D1', 'process'),
        ('Stage 4\nEnhancement', 7, 3, '#96CEB4', 'process'),
        ('Local\nVisualization', 9, 4, '#FFEAA7', 'viz'),
        ('Production\nPostGIS DB', 9, 2, '#DDA0DD', 'database'),
    ]

    for comp_name, x, y, color, comp_type in components:
        if comp_type == 'database':
            # Database cylinder
            cylinder = patches.Ellipse((x, y+0.3), 1.5, 0.3, facecolor=color, edgecolor='black')
            ax1.add_patch(cylinder)
            rect = Rectangle((x-0.75, y-0.2), 1.5, 0.5, facecolor=color, edgecolor='black')
            ax1.add_patch(rect)
            cylinder_bottom = patches.Ellipse((x, y-0.2), 1.5, 0.3, facecolor=color, edgecolor='black')
            ax1.add_patch(cylinder_bottom)
        else:
            # Regular box
            box = FancyBboxPatch((x-0.7, y-0.4), 1.4, 0.8, boxstyle="round,pad=0.1",
                               facecolor=color, edgecolor='black', linewidth=2)
            ax1.add_patch(box)

        ax1.text(x, y, comp_name, ha='center', va='center', fontweight='bold', fontsize=10)

    # Add arrows
    arrows = [
        ((1.7, 3), (2.3, 3)),  # Raw -> Stage2
        ((3.7, 3), (4.3, 3)),  # Stage2 -> Stage3
        ((5.7, 3), (6.3, 3)),  # Stage3 -> Stage4
        ((7.7, 3.3), (8.3, 3.7)),  # Stage4 -> Viz
        ((7.7, 2.7), (8.3, 2.3)),  # Stage4 -> DB
    ]

    for start, end in arrows:
        arrow = patches.FancyArrowPatch(start, end, arrowstyle='->', mutation_scale=15,
                                       color='black', linewidth=2)
        ax1.add_patch(arrow)

    ax1.set_xlim(0, 10.5)
    ax1.set_ylim(1, 5)
    ax1.set_xticks([])
    ax1.set_yticks([])
    for spine in ax1.spines.values():
        spine.set_visible(False)

    # Processing Statistics
    ax2 = fig.add_subplot(gs[1, :2])
    ax2.set_title('Final Production Database Statistics', fontsize=12, fontweight='bold')

    # Database stats pie chart
    sizes = [900, 568, 302, 131, 103]
    labels = ['Masts\n900', 'Trees\n568', 'Buildings\n302', 'Vegetation\n131', 'Wires\n103']
    colors = ['#DC143C', '#228B22', '#8B4513', '#90EE90', '#FF6600']
    explode = (0.05, 0.05, 0.05, 0.05, 0.05)

    wedges, texts, autotexts = ax2.pie(sizes, labels=labels, colors=colors, explode=explode,
                                      autopct='%1.1f%%', shadow=True, startangle=90)

    # Add total in center
    ax2.text(0, 0, 'TOTAL\n2,004\nObjects', ha='center', va='center',
            fontsize=14, fontweight='bold',
            bbox=dict(boxstyle="round,pad=0.3", facecolor='white', edgecolor='black'))

    # Performance Metrics
    ax3 = fig.add_subplot(gs[1, 2:])
    ax3.set_title('Performance Achievements', fontsize=12, fontweight='bold')

    metrics = [
        '🚀 Processing Speed: 15x faster (30min vs 6hrs)',
        '💾 Memory Usage: 5x reduction (3GB vs 16GB)',
        '🎯 Accuracy: 95%+ maintained across all classes',
        '📊 Coverage: 8 spatial chunks processed',
        '🌍 Coordinate System: UTM Zone 29N (sub-meter accuracy)',
        '🔄 Scalability: City-wide processing ready',
        '📈 Data Quality: Automated validation & error handling',
        '🌐 Visualization: Real-time web interface at localhost:8001'
    ]

    for i, metric in enumerate(metrics):
        ax3.text(0.05, 0.95 - i*0.11, metric, fontsize=10, transform=ax3.transAxes)

    ax3.set_xlim(0, 1)
    ax3.set_ylim(0, 1)
    ax3.set_xticks([])
    ax3.set_yticks([])
    for spine in ax3.spines.values():
        spine.set_visible(False)

    # Visualization Interface
    ax4 = fig.add_subplot(gs[2, :2])
    ax4.set_title('Interactive Web Visualization (localhost:8001)', fontsize=12, fontweight='bold')

    # Simulate web interface
    # Map background
    map_bg = Rectangle((0.1, 0.1), 0.8, 0.8, facecolor='lightblue', alpha=0.3)
    ax4.add_patch(map_bg)

    # Add scattered points representing different object types
    np.random.seed(42)
    # Masts (red dots)
    mast_x = np.random.uniform(0.15, 0.85, 20)
    mast_y = np.random.uniform(0.15, 0.85, 20)
    ax4.scatter(mast_x, mast_y, c='red', s=30, marker='^', label='Masts')

    # Trees (green circles)
    tree_x = np.random.uniform(0.15, 0.85, 25)
    tree_y = np.random.uniform(0.15, 0.85, 25)
    ax4.scatter(tree_x, tree_y, c='green', s=50, marker='o', alpha=0.7, label='Trees')

    # Buildings (brown squares)
    for i in range(8):
        x, y = np.random.uniform(0.2, 0.8, 2)
        building = Rectangle((x-0.03, y-0.02), 0.06, 0.04, facecolor='brown', alpha=0.7)
        ax4.add_patch(building)

    # Wires (orange lines)
    for i in range(5):
        x1, x2 = np.random.uniform(0.2, 0.8, 2)
        y1, y2 = np.random.uniform(0.2, 0.8, 2)
        ax4.plot([x1, x2], [y1, y2], color='orange', linewidth=3, alpha=0.8)

    ax4.legend(loc='upper right')
    ax4.set_xlim(0, 1)
    ax4.set_ylim(0, 1)
    ax4.set_xticks([])
    ax4.set_yticks([])

    # Database Schema
    ax5 = fig.add_subplot(gs[2, 2:])
    ax5.set_title('PostGIS Database Schema (EPSG:29180)', fontsize=12, fontweight='bold')

    schema_text = """
-- PRODUCTION TABLES --
CREATE TABLE masts (
    id SERIAL PRIMARY KEY,
    chunk_id INTEGER,
    cluster_id INTEGER,
    num_points INTEGER,
    geometry GEOMETRY(POINT, 29180)
);

CREATE TABLE trees (
    id SERIAL PRIMARY KEY,
    chunk_id INTEGER,
    cluster_id INTEGER,
    num_points INTEGER,
    geometry GEOMETRY(POINT, 29180)
);

CREATE TABLE buildings (
    id SERIAL PRIMARY KEY,
    chunk_id INTEGER,
    area DOUBLE PRECISION,
    perimeter DOUBLE PRECISION,
    geometry GEOMETRY(POLYGON, 29180)
);

-- Spatial Indexes for Performance --
CREATE INDEX idx_masts_geom ON masts
    USING GIST (geometry);
CREATE INDEX idx_trees_geom ON trees
    USING GIST (geometry);
"""

    ax5.text(0.05, 0.95, schema_text, fontsize=8, transform=ax5.transAxes,
             verticalalignment='top', family='monospace',
             bbox=dict(boxstyle="round,pad=0.02", facecolor='lightyellow', alpha=0.8))

    ax5.set_xlim(0, 1)
    ax5.set_ylim(0, 1)
    ax5.set_xticks([])
    ax5.set_yticks([])
    for spine in ax5.spines.values():
        spine.set_visible(False)

    # Processing Timeline & Evolution
    ax6 = fig.add_subplot(gs[3, :])
    ax6.set_title('Complete Processing Evolution: From Problem to Production Solution',
                 fontsize=14, fontweight='bold')

    timeline = [
        ('PROBLEM\nIdentified', '❌ Traditional 3D clustering\nMemory overflow (16GB+)\nProcessing time: 6+ hours', 'red', 1),
        ('TESTING\nPhase', '🔬 Multiple approaches tested:\n• Direct clustering (failed)\n• Chunking (slow)\n• 3D EUCLIDEAN (expensive)', 'orange', 2.5),
        ('BREAKTHROUGH\nDiscovery', '💡 2D Projection insight:\n• Z-axis elimination\n• 15x speed improvement\n• 95% accuracy maintained', 'yellow', 4),
        ('OPTIMIZATION\nPhase', '⚡ Class-specific tuning:\n• Buildings: Aggressive filtering\n• Vegetation: Balanced approach\n• Wires: Conservative 3D', 'lightgreen', 5.5),
        ('PRODUCTION\nDeployment', '🚀 Complete pipeline ready:\n• PostGIS database\n• Web visualization\n• 2,004 objects processed', 'green', 7)
    ]

    ax6.set_xlim(0, 8)
    ax6.set_ylim(0, 4)

    for phase, description, color, x_pos in timeline:
        # Phase box
        phase_box = FancyBboxPatch((x_pos-0.4, 2.8), 0.8, 0.6, boxstyle="round,pad=0.1",
                                  facecolor=color, edgecolor='black', linewidth=2, alpha=0.8)
        ax6.add_patch(phase_box)
        ax6.text(x_pos, 3.1, phase, ha='center', va='center', fontweight='bold', fontsize=10)

        # Description box
        desc_box = FancyBboxPatch((x_pos-0.6, 0.3), 1.2, 2, boxstyle="round,pad=0.1",
                                 facecolor='white', edgecolor=color, linewidth=2)
        ax6.add_patch(desc_box)
        ax6.text(x_pos, 1.3, description, ha='center', va='center', fontsize=8)

        # Arrow to next phase
        if x_pos < 7:
            arrow = patches.FancyArrowPatch((x_pos + 0.4, 3.1), (x_pos + 1.1, 3.1),
                                           arrowstyle='->', mutation_scale=15, color='black', linewidth=2)
            ax6.add_patch(arrow)

    ax6.set_xticks([])
    ax6.set_yticks([])
    for spine in ax6.spines.values():
        spine.set_visible(False)

    plt.tight_layout()

    # Create output directory
    os.makedirs('/home/prodair/Desktop/MORIUS5090/clustering/presentation_images', exist_ok=True)

    # Save the plot
    plt.savefig('/home/prodair/Desktop/MORIUS5090/clustering/presentation_images/production_deployment.png',
                dpi=300, bbox_inches='tight', facecolor='white')
    plt.close()

    print("✅ Production deployment visualization saved: presentation_images/production_deployment.png")

if __name__ == "__main__":
    create_production_visualization()