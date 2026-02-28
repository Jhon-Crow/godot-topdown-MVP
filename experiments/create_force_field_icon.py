#!/usr/bin/env python3
"""
Create a force field icon (64x48 pixels) with a blue shield and glow effect.
"""

from PIL import Image, ImageDraw
import sys

def create_force_field_icon(output_path: str):
    """Create a 64x48 pixel force field icon with a blue shield and glow."""
    # Create a new image with transparency
    width, height = 64, 48
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Center of the image
    cx, cy = width // 2, height // 2

    # Draw outer glow (light blue, semi-transparent)
    for i in range(5, 0, -1):
        alpha = int(30 * (i / 5.0))  # Fade out
        radius = 18 + i * 2
        draw.ellipse(
            [cx - radius, cy - radius, cx + radius, cy + radius],
            fill=(100, 150, 255, alpha),
            outline=None
        )

    # Draw shield shape (hexagonal/circular)
    shield_points = []
    import math
    num_points = 6
    radius = 18
    for i in range(num_points):
        angle = (2 * math.pi * i / num_points) - (math.pi / 2)
        x = cx + radius * math.cos(angle)
        y = cy + radius * math.sin(angle)
        shield_points.append((x, y))

    # Draw filled shield
    draw.polygon(shield_points, fill=(50, 100, 200, 200), outline=None)

    # Draw shield border (bright blue)
    for i in range(len(shield_points)):
        x1, y1 = shield_points[i]
        x2, y2 = shield_points[(i + 1) % len(shield_points)]
        draw.line([(x1, y1), (x2, y2)], fill=(100, 180, 255, 255), width=2)

    # Draw energy lines (diagonal)
    line_color = (150, 200, 255, 180)
    draw.line([(cx - 12, cy - 8), (cx + 12, cy + 8)], fill=line_color, width=1)
    draw.line([(cx - 12, cy + 8), (cx + 12, cy - 8)], fill=line_color, width=1)

    # Add center glow
    for i in range(3, 0, -1):
        alpha = int(80 * (i / 3.0))
        radius = 4 + i
        draw.ellipse(
            [cx - radius, cy - radius, cx + radius, cy + radius],
            fill=(200, 220, 255, alpha),
            outline=None
        )

    # Save the image
    img.save(output_path, 'PNG')
    print(f"Force field icon created: {output_path}")
    print(f"Size: {width}x{height} pixels")

if __name__ == "__main__":
    output = "/tmp/gh-issue-solver-1771185705683/assets/sprites/weapons/force_field_icon.png"
    create_force_field_icon(output)
