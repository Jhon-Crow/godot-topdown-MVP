#!/usr/bin/env python3
"""
Extend the RSh-12 revolver barrel length by 2x.
Issue #646: Make the revolver barrel 2 times longer.

This script modifies the existing revolver sprites to extend the barrel length.
"""

from PIL import Image

# Color palette from create_revolver_sprites.py
COLORS = {
    'black': (30, 30, 30, 255),
    'dark_gray': (45, 45, 45, 255),
    'medium_gray': (60, 60, 60, 255),
    'light_gray': (70, 70, 70, 255),
    'lighter_gray': (90, 90, 90, 255),
    'highlight': (100, 100, 100, 255),
    'metal_dark': (35, 35, 40, 255),
    'metal_medium': (50, 50, 55, 255),
    'metal_light': (70, 70, 75, 255),
    'grip_dark': (50, 40, 30, 255),
    'grip_medium': (70, 55, 40, 255),
    'grip_light': (85, 70, 50, 255),
    'transparent': (0, 0, 0, 0),
}


def extend_icon_barrel(original_img):
    """
    Extend the icon barrel from ~25 pixels to ~50 pixels (2x).
    Original barrel: x 50-75
    New barrel: x 50-100

    The image will grow from 80x24 to ~105x24
    """
    orig_width, height = original_img.size
    barrel_extension = 25  # Add 25 pixels to double the barrel length
    new_width = orig_width + barrel_extension

    # Create new image with extended width
    new_img = Image.new('RGBA', (new_width, height), COLORS['transparent'])

    # Copy all pixels from original, but shift the barrel part to the right
    for y in range(height):
        for x in range(orig_width):
            pixel = original_img.getpixel((x, y))
            if x < 50:
                # Copy grip, frame, and cylinder as-is
                new_img.putpixel((x, y), pixel)
            elif x >= 50:
                # Shift barrel to the right by barrel_extension
                new_img.putpixel((x + barrel_extension, y), pixel)

    # Fill the gap with extended barrel (x: 50-75)
    # This extends the barrel body
    for x in range(50, 75):
        for y in range(5, 12):
            # Top edge
            if y == 5:
                new_img.putpixel((x, y), COLORS['black'])
            # Bottom edge
            elif y == 11:
                new_img.putpixel((x, y), COLORS['black'])
            # Barrel body shading
            elif y == 6:
                new_img.putpixel((x, y), COLORS['metal_light'])
            elif y == 10:
                new_img.putpixel((x, y), COLORS['metal_dark'])
            elif y == 7:
                new_img.putpixel((x, y), COLORS['lighter_gray'])
            else:
                new_img.putpixel((x, y), COLORS['metal_medium'])

    # Extend the under-barrel lug
    for y in range(11, 14):
        for x in range(50, 68):
            if y == 13:
                new_img.putpixel((x, y), COLORS['black'])
            elif x == 50:
                new_img.putpixel((x, y), COLORS['black'])
            else:
                new_img.putpixel((x, y), COLORS['metal_dark'])

    # Add ventilated rib slots on the extended barrel
    for x in range(54, 73, 4):
        new_img.putpixel((x, 6), COLORS['dark_gray'])
        new_img.putpixel((x + 1, 6), COLORS['dark_gray'])

    return new_img


def extend_topdown_barrel(original_img):
    """
    Extend the topdown barrel from ~11 pixels to ~22 pixels (2x).
    Original barrel: x 22-33
    New barrel: x 22-44

    The image will grow from 34x14 to ~45x14
    """
    orig_width, height = original_img.size
    barrel_extension = 11  # Add 11 pixels to double the barrel length
    new_width = orig_width + barrel_extension

    # Create new image with extended width
    new_img = Image.new('RGBA', (new_width, height), COLORS['transparent'])

    # Copy all pixels from original, but shift the barrel part to the right
    for y in range(height):
        for x in range(orig_width):
            pixel = original_img.getpixel((x, y))
            if x < 22:
                # Copy grip, frame, and cylinder as-is
                new_img.putpixel((x, y), pixel)
            elif x >= 22:
                # Shift barrel to the right by barrel_extension
                new_img.putpixel((x + barrel_extension, y), pixel)

    # Fill the gap with extended barrel (x: 22-33)
    for x in range(22, 33):
        for y in range(4, 10):
            # Top edge
            if y == 4:
                new_img.putpixel((x, y), COLORS['black'])
            # Bottom edge
            elif y == 9:
                new_img.putpixel((x, y), COLORS['black'])
            # Barrel body shading
            elif y == 5:
                new_img.putpixel((x, y), COLORS['metal_light'])
            elif y == 8:
                new_img.putpixel((x, y), COLORS['metal_dark'])
            else:
                new_img.putpixel((x, y), COLORS['metal_medium'])

    return new_img


if __name__ == '__main__':
    # Load original sprites
    icon_path = 'assets/sprites/weapons/revolver_icon.png'
    topdown_path = 'assets/sprites/weapons/revolver_topdown.png'

    print("Loading original sprites...")
    icon = Image.open(icon_path)
    topdown = Image.open(topdown_path)

    print(f"Original icon size: {icon.size}")
    print(f"Original topdown size: {topdown.size}")

    # Extend barrels
    print("\nExtending barrels by 2x...")
    new_icon = extend_icon_barrel(icon)
    new_topdown = extend_topdown_barrel(topdown)

    print(f"New icon size: {new_icon.size}")
    print(f"New topdown size: {new_topdown.size}")

    # Save to experiments folder for review
    new_icon.save('experiments/revolver_icon_extended.png')
    new_topdown.save('experiments/revolver_topdown_extended.png')

    print("\nExtended sprites saved to experiments folder:")
    print("  - experiments/revolver_icon_extended.png")
    print("  - experiments/revolver_topdown_extended.png")

    # Save to assets folder (replacing originals)
    new_icon.save(icon_path)
    new_topdown.save(topdown_path)

    print("\nOriginal sprites updated:")
    print(f"  - {icon_path}")
    print(f"  - {topdown_path}")
    print("\nBarrel length extended by 2x successfully!")
