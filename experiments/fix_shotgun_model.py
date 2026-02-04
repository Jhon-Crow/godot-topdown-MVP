#!/usr/bin/env python3
"""
Fix shotgun model according to issue #485:
1. Main shotgun body should be completely iron/metal colored (remove brown/wood parts)
2. Pump remains brown/wood colored (for the movable part)
3. z_index adjustment handled in .tscn file

This script creates:
- shotgun_topdown.png - Completely metal/iron colored main body
"""

from PIL import Image

# Color palette - using only metal colors for main body
COLORS = {
    'black': (30, 30, 30, 255),
    'dark_gray': (45, 45, 45, 255),
    'medium_gray': (60, 60, 60, 255),
    'light_gray': (70, 70, 70, 255),
    'lighter_gray': (90, 90, 90, 255),
    'lightest_gray': (100, 100, 100, 255),
    'metal_dark': (35, 35, 40, 255),
    'metal_medium': (50, 50, 55, 255),
    'metal_light': (70, 70, 75, 255),
    'metal_highlight': (85, 85, 90, 255),
    'transparent': (0, 0, 0, 0),
}


def create_metal_shotgun_topdown():
    """
    Create 64x16 top-down view shotgun sprite.
    Completely metal/iron colored - no wood parts.
    Layout: [stock] [receiver] [forend area] [barrel]

    The pump (wood-colored movable part) is a separate sprite.
    """
    width, height = 64, 16
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Pump-action shotgun top-down layout (pointing right):
    # [stock] [receiver] [magazine tube area] [barrel]
    # All metal colored now

    # Stock (metal, rear part) - x: 0-12
    for y in range(5, 11):
        for x in range(0, 13):
            if y == 5 or y == 10:
                if x >= 3:
                    img.putpixel((x, y), COLORS['black'])
            elif y in [6, 9]:
                if x >= 1:
                    img.putpixel((x, y), COLORS['black'] if x <= 1 else COLORS['metal_dark'])
            else:  # y in [7, 8] - center of stock
                if x >= 0:
                    img.putpixel((x, y), COLORS['metal_medium'] if x > 0 else COLORS['black'])

    # Receiver (metal body) - x: 13-30
    for y in range(4, 12):
        for x in range(13, 31):
            if y == 4 or y == 11:
                img.putpixel((x, y), COLORS['black'])
            elif y in [5, 10]:
                img.putpixel((x, y), COLORS['dark_gray'])
            else:
                img.putpixel((x, y), COLORS['medium_gray'])

    # Trigger guard area - small detail at bottom
    for y in range(12, 15):
        for x in range(18, 25):
            if y == 12:
                img.putpixel((x, y), COLORS['black'])
            elif x == 18 or x == 24:
                img.putpixel((x, y), COLORS['black'])
            elif y == 14:
                img.putpixel((x, y), COLORS['black'])

    # Magazine tube area / forend base (metal) - x: 31-45
    # This is the area where the pump slides - it's metal under the pump
    for y in range(5, 11):
        for x in range(31, 46):
            if y == 5 or y == 10:
                img.putpixel((x, y), COLORS['black'])
            elif y in [6, 9]:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:  # middle part
                img.putpixel((x, y), COLORS['metal_medium'])

    # Barrel (metal tube) - x: 46-63
    for y in range(6, 10):
        for x in range(46, 64):
            if y == 6 or y == 9:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['light_gray'])

    # Muzzle end detail
    for y in range(5, 11):
        img.putpixel((63, y), COLORS['black'])

    return img


if __name__ == '__main__':
    # Create the metal shotgun sprite
    topdown = create_metal_shotgun_topdown()

    # Save to experiments folder first
    topdown.save('experiments/shotgun_topdown_metal.png')
    print(f"Created shotgun_topdown_metal.png: {topdown.size}")

    # Also save to assets folder
    topdown.save('assets/sprites/weapons/shotgun_topdown.png')
    print("\nSprites saved to:")
    print("  - experiments/shotgun_topdown_metal.png")
    print("  - assets/sprites/weapons/shotgun_topdown.png")
