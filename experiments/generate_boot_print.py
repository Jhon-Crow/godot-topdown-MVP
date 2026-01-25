#!/usr/bin/env python3
"""
Generate a bloody boot print texture for Godot game.
Based on reference image showing military/work boot sole with tread pattern.
"""

from PIL import Image, ImageDraw
import math


def create_boot_print(width=11, height=20, output_path="boot_print.png"):
    """
    Create a boot print texture with visible tread pattern.

    The boot print consists of:
    - An elongated boot sole outline (wider toe, narrower arch, wide heel)
    - Horizontal tread lines (gaps) across the sole
    - Clear tread pattern visible at game scale
    - Extra vertical padding to prevent cropping during rotation
    """
    # Create image with transparency
    img = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Blood colors - bright red for visibility
    blood_main = (180, 25, 25, 255)     # Main blood color
    blood_edge = (140, 15, 15, 255)     # Edge color
    transparent = (0, 0, 0, 0)          # Tread gaps

    # Boot sole parameters (scaled for smaller size)
    # Added extra vertical margin to prevent cropping during rotation
    margin_x = 1
    margin_y = 2  # Increased from 1 to 2 for top/bottom padding

    sole_left = margin_x
    sole_right = width - margin_x
    sole_top = margin_y
    sole_bottom = height - margin_y
    sole_height = sole_bottom - sole_top

    def get_width_factor(rel_y):
        """Get width factor based on vertical position (boot shape)."""
        if rel_y < 0.30:  # Toe area - round and wide
            return 0.90 + 0.10 * math.cos(rel_y / 0.30 * math.pi / 2)
        elif rel_y < 0.50:  # Upper arch - narrowing
            progress = (rel_y - 0.30) / 0.20
            return 0.90 - 0.25 * progress
        elif rel_y < 0.60:  # Narrow arch
            return 0.65
        else:  # Heel area - widening again
            progress = (rel_y - 0.60) / 0.40
            return 0.65 + 0.30 * progress

    # First pass: draw the solid boot sole
    for y in range(sole_top, sole_bottom):
        rel_y = (y - sole_top) / sole_height
        width_factor = get_width_factor(rel_y)

        half_width = (sole_right - sole_left) // 2
        actual_half = int(half_width * width_factor)
        center_x = width // 2

        x_left = max(0, center_x - actual_half)
        x_right = min(width - 1, center_x + actual_half)

        for x in range(x_left, x_right + 1):
            # Slight variation for organic feel
            img.putpixel((x, y), blood_main)

    # Second pass: add horizontal tread gaps (make them transparent)
    # Scaled for smaller texture: 2 pixels spacing, 1 pixel gap
    tread_spacing = 2  # Pixels between tread lines
    tread_gap = 1      # Pixel height of gap (transparent area)

    for tread_y in range(sole_top + 1, sole_bottom - 1, tread_spacing):
        rel_y = (tread_y - sole_top) / sole_height
        width_factor = get_width_factor(rel_y)

        half_width = (sole_right - sole_left) // 2
        actual_half = int(half_width * width_factor)
        center_x = width // 2

        # Inset the treads from edge (smaller inset for small texture)
        x_left = max(0, center_x - actual_half + 1)
        x_right = min(width - 1, center_x + actual_half - 1)

        # Draw the tread gap
        for gap in range(tread_gap):
            if tread_y + gap < sole_bottom - 1:
                for x in range(x_left, x_right + 1):
                    img.putpixel((x, tread_y + gap), transparent)

    # Third pass: darken edges for definition
    for y in range(sole_top, sole_bottom):
        rel_y = (y - sole_top) / sole_height
        width_factor = get_width_factor(rel_y)

        half_width = (sole_right - sole_left) // 2
        actual_half = int(half_width * width_factor)
        center_x = width // 2

        x_left = max(0, center_x - actual_half)
        x_right = min(width - 1, center_x + actual_half)

        # Darken left and right edges (1 pixel each side for small texture)
        for edge_offset in range(1):
            if x_left + edge_offset < width:
                current = img.getpixel((x_left + edge_offset, y))
                if current[3] > 0:
                    img.putpixel((x_left + edge_offset, y), blood_edge)
            if x_right - edge_offset >= 0:
                current = img.getpixel((x_right - edge_offset, y))
                if current[3] > 0:
                    img.putpixel((x_right - edge_offset, y), blood_edge)

    # Fourth pass: add some texture/splatter effect around edges
    import random
    random.seed(42)  # Consistent output
    for _ in range(5):  # Fewer droplets for smaller texture
        # Add small blood droplets near the boot
        angle = random.uniform(0, 2 * math.pi)
        dist = random.uniform(0, 1.5)  # Smaller distance for small texture
        base_y = random.randint(sole_top, sole_bottom - 1)
        rel_y = (base_y - sole_top) / sole_height
        width_factor = get_width_factor(rel_y)

        half_width = (sole_right - sole_left) // 2
        actual_half = int(half_width * width_factor)
        center_x = width // 2

        # Pick left or right edge
        if random.random() > 0.5:
            edge_x = center_x - actual_half
        else:
            edge_x = center_x + actual_half

        splat_x = int(edge_x + dist * math.cos(angle))
        splat_y = int(base_y + dist * math.sin(angle))

        if 0 <= splat_x < width and 0 <= splat_y < height:
            current = img.getpixel((splat_x, splat_y))
            if current[3] == 0:  # Only on transparent areas
                # Small droplet with lower alpha
                img.putpixel((splat_x, splat_y), (180, 25, 25, 150))

    # Save the image
    img.save(output_path)
    print(f"Boot print saved to: {output_path}")
    print(f"Size: {width}x{height} pixels")

    return img


def create_left_right_boot_prints():
    """Create both left and right boot prints (11x20 pixels with padding)."""
    import os

    # Determine correct output path based on script location
    script_dir = os.path.dirname(os.path.abspath(__file__))
    assets_dir = os.path.join(os.path.dirname(script_dir), "assets", "sprites", "effects")
    os.makedirs(assets_dir, exist_ok=True)

    right_path = os.path.join(assets_dir, "boot_print_right.png")
    left_path = os.path.join(assets_dir, "boot_print_left.png")

    # Create right boot print - 11x20 pixels (added 4px height for padding)
    # This prevents cropping when footprints are rotated
    right_print = create_boot_print(
        width=11,
        height=20,
        output_path=right_path
    )

    # Create left boot print (mirrored)
    left_print = right_print.transpose(Image.FLIP_LEFT_RIGHT)
    left_print.save(left_path)
    print(f"Left boot print saved (mirrored) to: {left_path}")


if __name__ == "__main__":
    create_left_right_boot_prints()
