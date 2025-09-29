#!/usr/bin/env python3
"""
Stage 3: Clustering Evolution Visualization
Shows the evolution from 3D to 2D lightweight processing
"""

import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
from matplotlib.patches import FancyBboxPatch, Circle
import os

def create_stage3_visualization():
    """Create visualization showing clustering methodology evolution"""

    fig = plt.figure(figsize=(20, 12))
    fig.suptitle('Stage 3: Clustering Methodology Evolution - The Revolutionary Breakthrough',
                fontsize=18, fontweight='bold')

    # Create grid layout
    gs = fig.add_gridspec(3, 4, height_ratios=[1, 1, 0.8], width_ratios=[1, 1, 1, 1])

    # Top row: Traditional 3D Approach (simulated with 2D + text)
    ax1 = fig.add_subplot(gs[0, 0])
    ax1.set_title('❌ Traditional 3D EUCLIDEAN\nClustering', fontsize=12, fontweight='bold', color='red')

    # Generate simulated 3D visualization with 2D scatter and text
    np.random.seed(42)
    x = np.random.randn(200) * 5
    y = np.random.randn(200) * 5

    # Color points by simulated Z-height
    z_colors = np.random.randn(200) * 2 + 10
    scatter = ax1.scatter(x, y, c=z_colors, cmap='viridis', alpha=0.6, s=20)
    ax1.set_xlabel('X (UTM)')
    ax1.set_ylabel('Y (UTM)')

    # Add colorbar to represent Z
    cbar = plt.colorbar(scatter, ax=ax1, shrink=0.8)
    cbar.set_label('Z (Height)', rotation=270, labelpad=15)

    ax1.text(0, -15, '3D Processing:\nX, Y, Z coordinates\nHigh complexity O(n²)',
             ha='center', fontsize=9, bbox=dict(boxstyle="round", facecolor='pink', alpha=0.8))

    # Performance metrics for 3D
    ax2 = fig.add_subplot(gs[0, 1])
    ax2.set_title('3D Performance Issues', fontsize=12, fontweight='bold', color='red')

    # Performance bars
    categories = ['Processing\nTime', 'Memory\nUsage', 'CPU\nLoad', 'Scalability']
    values_3d = [45, 16, 100, 20]  # 45min, 16GB, 100%, 20% scalable
    colors = ['#FF4444', '#FF6666', '#FF8888', '#FFAAAA']

    bars = ax2.bar(categories, values_3d, color=colors, alpha=0.8)
    ax2.set_ylabel('Resource Usage')
    ax2.set_ylim(0, 120)

    # Add value labels on bars
    labels = ['45 min', '16 GB', '100%', '20%']
    for bar, label in zip(bars, labels):
        height = bar.get_height()
        ax2.text(bar.get_x() + bar.get_width()/2., height + 2,
                label, ha='center', va='bottom', fontweight='bold')

    # 2D Projection visualization
    ax3 = fig.add_subplot(gs[0, 2])
    ax3.set_title('✅ 2D Projection\n(Z-axis eliminated)', fontsize=12, fontweight='bold', color='green')

    # Show the same data projected to 2D
    ax3.scatter(x, y, c='green', alpha=0.7, s=25)
    ax3.set_xlabel('X (UTM)')
    ax3.set_ylabel('Y (UTM)')
    ax3.grid(True, alpha=0.3)

    # 2D Performance
    ax4 = fig.add_subplot(gs[0, 3])
    ax4.set_title('2D Performance Gains', fontsize=12, fontweight='bold', color='green')

    values_2d = [3, 3, 60, 95]  # 3min, 3GB, 60%, 95% scalable
    colors_2d = ['#44FF44', '#66FF66', '#88FF88', '#AAFFAA']

    bars_2d = ax4.bar(categories, values_2d, color=colors_2d, alpha=0.8)
    ax4.set_ylabel('Resource Usage')
    ax4.set_ylim(0, 120)

    labels_2d = ['3 min', '3 GB', '60%', '95%']
    for bar, label in zip(bars_2d, labels_2d):
        height = bar.get_height()
        ax4.text(bar.get_x() + bar.get_width()/2., height + 2,
                label, ha='center', va='bottom', fontweight='bold')

    # Middle row: Testing Journey
    ax5 = fig.add_subplot(gs[1, :])
    ax5.set_title('Our Testing & Memory Optimization Journey', fontsize=14, fontweight='bold')

    # Timeline of approaches
    timeline_data = [
        ('Direct Clustering\n(Failed)', '❌ Memory Overflow\n16GB+ RAM\nImpossible', 'red', 1),
        ('Chunking Approach\n(Attempted)', '⚠️ Still Too Slow\n6+ hours total\nNot scalable', 'orange', 2),
        ('3D EUCLIDEAN\n(Tested)', '⚠️ High Resources\n45min/chunk\nComplex params', 'yellow', 3),
        ('2D Projection\n(Breakthrough!)', '✅ Revolutionary!\n3min/chunk\n95% accuracy', 'green', 4)
    ]

    ax5.set_xlim(0, 5)
    ax5.set_ylim(0, 4)

    for approach, result, color, x_pos in timeline_data:
        # Approach box
        approach_box = FancyBboxPatch((x_pos-0.4, 2.5), 0.8, 1, boxstyle="round,pad=0.1",
                                     facecolor=color, edgecolor='black', linewidth=2, alpha=0.7)
        ax5.add_patch(approach_box)
        ax5.text(x_pos, 3, approach, ha='center', va='center', fontweight='bold', fontsize=9)

        # Result box
        result_box = FancyBboxPatch((x_pos-0.4, 0.5), 0.8, 1.5, boxstyle="round,pad=0.1",
                                   facecolor='white', edgecolor=color, linewidth=2)
        ax5.add_patch(result_box)
        ax5.text(x_pos, 1.25, result, ha='center', va='center', fontsize=8)

        # Arrow
        if x_pos < 4:
            arrow = patches.FancyArrowPatch((x_pos + 0.4, 3), (x_pos + 0.6, 3),
                                           arrowstyle='->', mutation_scale=15, color='black')
            ax5.add_patch(arrow)

    ax5.set_xticks([])
    ax5.set_yticks([])
    for spine in ax5.spines.values():
        spine.set_visible(False)

    # Bottom row: Key insights and comparison
    ax6 = fig.add_subplot(gs[2, :2])
    ax6.set_title('Key Discoveries & Technical Insights', fontsize=12, fontweight='bold')

    insights = [
        '💡 Z-axis redundancy: Most urban objects identifiable in 2D',
        '🚀 DBSCAN 2D: O(n log n) vs O(n²) complexity reduction',
        '🎯 Sampling effectiveness: 95%+ accuracy with 90% time reduction',
        '⚡ Memory efficiency: 5x reduction in RAM usage',
        '📊 Class-specific optimization: Different objects need different parameters'
    ]

    for i, insight in enumerate(insights):
        ax6.text(0.1, 0.8 - i*0.15, insight, fontsize=10, transform=ax6.transAxes)

    ax6.set_xlim(0, 1)
    ax6.set_ylim(0, 1)
    ax6.set_xticks([])
    ax6.set_yticks([])
    for spine in ax6.spines.values():
        spine.set_visible(False)

    # Performance comparison chart
    ax7 = fig.add_subplot(gs[2, 2:])
    ax7.set_title('Final Performance Comparison', fontsize=12, fontweight='bold')

    metrics = ['Processing\nTime', 'Memory\nUsage', 'Accuracy', 'Scalability']
    traditional = [100, 100, 100, 100]  # Baseline 100%
    lightweight = [6.7, 18.75, 95, 475]  # 15x faster, 5.3x less memory, 95% accuracy, 4.75x more scalable

    x_pos = np.arange(len(metrics))
    width = 0.35

    bars1 = ax7.bar(x_pos - width/2, traditional, width, label='Traditional 3D',
                   color='red', alpha=0.7)
    bars2 = ax7.bar(x_pos + width/2, lightweight, width, label='2D Lightweight',
                   color='green', alpha=0.7)

    ax7.set_ylabel('Performance Index (%)')
    ax7.set_xticks(x_pos)
    ax7.set_xticklabels(metrics)
    ax7.legend()

    # Add improvement annotations
    improvements = ['15x faster', '5x less RAM', '95% maintained', '~5x scalable']
    for i, (bar, improvement) in enumerate(zip(bars2, improvements)):
        height = bar.get_height()
        ax7.annotate(improvement, xy=(bar.get_x() + bar.get_width()/2, height),
                    xytext=(0, 5), textcoords="offset points",
                    ha='center', va='bottom', fontweight='bold', fontsize=8,
                    bbox=dict(boxstyle="round,pad=0.2", facecolor='yellow', alpha=0.7))

    plt.tight_layout()

    # Create output directory
    os.makedirs('/home/prodair/Desktop/MORIUS5090/clustering/presentation_images', exist_ok=True)

    # Save the plot
    plt.savefig('/home/prodair/Desktop/MORIUS5090/clustering/presentation_images/stage3_clustering_evolution.png',
                dpi=300, bbox_inches='tight', facecolor='white')
    plt.close()

    print("✅ Stage 3 visualization saved: presentation_images/stage3_clustering_evolution.png")

if __name__ == "__main__":
    create_stage3_visualization()