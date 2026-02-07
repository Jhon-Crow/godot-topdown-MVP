#!/usr/bin/env python3
"""Generate comparison visualizations of old vs new cone texture edges."""

from PIL import Image
import math

def visualize_edge(img_path, output_path, label):
    """Create a magnified view of the cone edge at 75% radius."""
    img = Image.open(img_path)
    pixels = img.load()
    width, height = img.size

    center_x = width / 2.0
    center_y = height / 2.0

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
                vis_pixels[vx, vy] = (a, a, a, 255)

    vis.save(output_path)
    print(f"Saved {label}: {output_path}")

# Generate old edge from the original texture stored in git
import subprocess
import tempfile, os

# Extract original 512x512 texture from before our changes
result = subprocess.run(
    ["git", "show", "4580fb6:assets/sprites/effects/flashlight_cone_18deg.png"],
    capture_output=True
)
old_path = "/tmp/original_512_texture.png"
with open(old_path, "wb") as f:
    f.write(result.stdout)

visualize_edge(old_path, "../docs/case-studies/issue-585/edge_original_512.png", "Original 512x512 edge")
visualize_edge("../assets/sprites/effects/flashlight_cone_18deg.png", "../docs/case-studies/issue-585/edge_new_2048.png", "New 2048x2048 edge")
