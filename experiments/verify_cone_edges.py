#!/usr/bin/env python3
"""Verify cone texture edge quality by analyzing alpha transitions.

This script examines the cone boundary pixels to check for smooth anti-aliased
transitions vs. hard staircase edges.
"""

from PIL import Image
import math

TEXTURE_PATH = "../assets/sprites/effects/flashlight_cone_18deg.png"


def analyze_edge_quality():
    img = Image.open(TEXTURE_PATH)
    pixels = img.load()
    width, height = img.size
    print(f"Texture size: {width}x{height}")

    center_x = width / 2.0
    center_y = height / 2.0

    # Sample along a horizontal line at several Y offsets to check the cone edge
    # At the cone edge (9 degrees from horizontal), y = x * tan(9°)
    # So at x=256 (max radius for 512, or 1024 for 2048), y = x * 0.158

    print("\n=== Edge analysis along radial lines ===")
    # Check alpha transitions at various distances from center
    for dist_frac in [0.25, 0.5, 0.75, 0.95]:
        dist = int(width / 2.0 * dist_frac)
        # At this distance, the cone edge is at y = dist * tan(9°)
        edge_y = int(dist * math.tan(math.radians(9.0)))
        print(f"\n--- Distance {dist}px ({dist_frac*100:.0f}% of radius) ---")
        print(f"  Expected edge at ~{edge_y}px from center")

        # Sample alpha values across the edge (center_y - edge_y area)
        x = int(center_x + dist)
        start_y = int(center_y - edge_y - 5)
        end_y = int(center_y - edge_y + 5)

        alphas = []
        for y in range(max(0, start_y), min(height, end_y + 1)):
            a = pixels[x, y][3]
            alphas.append((y, a))
            if a > 0:
                print(f"  pixel[{x},{y}] alpha={a}")

    # Also check the bottom edge (positive y)
    print("\n=== Bottom edge check at 75% radius ===")
    dist = int(width / 2.0 * 0.75)
    edge_y = int(dist * math.tan(math.radians(9.0)))
    x = int(center_x + dist)
    start_y = int(center_y + edge_y - 5)
    end_y = int(center_y + edge_y + 5)
    for y in range(max(0, start_y), min(height, end_y + 1)):
        a = pixels[x, y][3]
        if a > 0 or (y >= int(center_y + edge_y - 2)):
            print(f"  pixel[{x},{y}] alpha={a}")

    # Count unique alpha values to verify gradual transitions
    all_alphas = set()
    for y in range(height):
        for x in range(width):
            a = pixels[x, y][3]
            if 0 < a < 255:
                all_alphas.add(a)
    print(f"\n=== Unique intermediate alpha values: {len(all_alphas)} ===")
    print(f"  (More = smoother transitions)")

    # Create a visualization showing the edge region magnified
    vis_size = 400
    vis = Image.new("RGBA", (vis_size, vis_size), (0, 0, 0, 255))
    vis_pixels = vis.load()

    # Show a section of the cone edge at 75% radius, magnified 4x
    dist = int(width / 2.0 * 0.75)
    edge_y_center = int(dist * math.tan(math.radians(9.0)))
    src_x_start = int(center_x + dist - vis_size // 8)
    src_y_start = int(center_y - edge_y_center - vis_size // 8)

    for vy in range(vis_size):
        for vx in range(vis_size):
            src_x = src_x_start + vx // 4
            src_y = src_y_start + vy // 4
            if 0 <= src_x < width and 0 <= src_y < height:
                r, g, b, a = pixels[src_x, src_y]
                # Show alpha as grayscale on dark background
                vis_pixels[vx, vy] = (a, a, a, 255)

    vis.save("cone_edge_magnified.png")
    print(f"\nSaved magnified edge visualization to: experiments/cone_edge_magnified.png")


if __name__ == "__main__":
    analyze_edge_quality()
