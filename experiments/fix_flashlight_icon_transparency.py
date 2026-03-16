#!/usr/bin/env python3
"""
Fix flashlight icon by removing white background and making it transparent.

This script loads the existing flashlight_icon.png, identifies the white
background pixels, and replaces them with transparent pixels while keeping
the flashlight artwork intact.

According to the armory icon standard, all weapon and item icons should have
transparent backgrounds (RGBA format with alpha=0 for background).

Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/670
"""

from PIL import Image


def fix_flashlight_icon_transparency(input_path: str, output_path: str):
    """
    Remove white background from flashlight icon and make it transparent.

    Args:
        input_path: Path to the original flashlight icon with white background
        output_path: Path to save the fixed icon with transparent background
    """
    # Load the original icon
    img = Image.open(input_path).convert('RGBA')
    pixels = img.load()
    width, height = img.size

    print(f"Processing image: {width}x{height} pixels")

    # Replace white/near-white background pixels with transparent
    # We consider a pixel as "white background" if:
    # - R, G, B are all >= 240 (very light/white)
    # This preserves any intentional highlights on the flashlight itself

    white_threshold = 240
    pixels_made_transparent = 0

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]

            # Check if this is a white background pixel
            if r >= white_threshold and g >= white_threshold and b >= white_threshold:
                # Make it transparent
                pixels[x, y] = (0, 0, 0, 0)
                pixels_made_transparent += 1

    print(f"Made {pixels_made_transparent} white pixels transparent")
    print(f"Remaining visible pixels: {width * height - pixels_made_transparent}")

    # Save the fixed icon
    img.save(output_path, 'PNG')
    print(f"Saved fixed icon to: {output_path}")

    return img


if __name__ == '__main__':
    input_path = '../assets/sprites/weapons/flashlight_icon.png'
    output_experiments = 'flashlight_icon_fixed.png'
    output_assets = '../assets/sprites/weapons/flashlight_icon.png'

    print("=" * 60)
    print("Fixing flashlight icon transparency")
    print("=" * 60)

    # Create the fixed icon
    fixed_icon = fix_flashlight_icon_transparency(input_path, output_experiments)

    # Also save directly to assets folder (overwriting the original)
    fixed_icon.save(output_assets, 'PNG')
    print(f"Also saved to: {output_assets}")

    print("\n" + "=" * 60)
    print("Done! White background has been removed.")
    print("=" * 60)
