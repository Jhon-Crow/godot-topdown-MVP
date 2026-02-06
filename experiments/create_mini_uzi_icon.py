#!/usr/bin/env python3
"""
Create Mini UZI icon sprite for the Godot top-down game.
Creates a smaller armory icon (60x18) - side view to match the standard.

Style matches existing weapon sprites (shotgun, M16).
"""

from PIL import Image

# Color palette matching other weapon sprites
COLORS = {
    'black': (30, 30, 30, 255),
    'dark_gray': (45, 45, 45, 255),
    'medium_gray': (60, 60, 60, 255),
    'light_gray': (70, 70, 70, 255),
    'lighter_gray': (90, 90, 90, 255),
    'metal_dark': (35, 35, 40, 255),
    'metal_medium': (50, 50, 55, 255),
    'metal_light': (70, 70, 75, 255),
    'transparent': (0, 0, 0, 0),
}


def create_mini_uzi_icon():
    """
    Create 60x18 side-view Mini UZI icon.
    Compact submachine gun design with:
    - Compact body
    - Folding stock (simplified)
    - Magazine protruding from bottom
    - Short barrel
    """
    width, height = 60, 18
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Mini UZI side view (pointing right):
    # [folding stock] [receiver/body] [barrel] [magazine below]

    # Folding stock (compact, metal) - x: 0-10
    for y in range(4, 10):
        for x in range(0, 11):
            if y == 4 or y == 9:
                if x >= 3:
                    img.putpixel((x, y), COLORS['black'])
            elif x >= 2:
                if y in [5, 8]:
                    img.putpixel((x, y), COLORS['metal_dark'])
                else:
                    img.putpixel((x, y), COLORS['metal_medium'])

    # Receiver/Body (blocky, metal) - x: 11-42
    for y in range(3, 11):
        for x in range(11, 43):
            if y == 3 or y == 10:
                img.putpixel((x, y), COLORS['black'])
            elif y == 4 or y == 9:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Grip/Handle - below receiver at rear
    for y in range(10, 16):
        for x in range(14, 22):
            if y == 10:
                continue  # skip top (part of receiver)
            grip_width = 8 - (y - 10) // 2
            start_x = 14 + (8 - grip_width) // 2
            if start_x <= x < start_x + grip_width:
                if y == 15 or x == start_x or x == start_x + grip_width - 1:
                    img.putpixel((x, y), COLORS['black'])
                else:
                    img.putpixel((x, y), COLORS['dark_gray'])

    # Magazine (protruding from bottom, forward of grip) - x: 24-32
    for y in range(10, 17):
        for x in range(24, 33):
            if y == 10:
                img.putpixel((x, y), COLORS['black'])
            elif x == 24 or x == 32:
                img.putpixel((x, y), COLORS['black'])
            elif y == 16:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['dark_gray'])

    # Barrel (short, thick for UZI) - x: 43-59
    for y in range(5, 9):
        for x in range(43, 60):
            if y == 5 or y == 8:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['metal_light'])

    # Front sight
    for y in range(2, 5):
        img.putpixel((56, y), COLORS['black'])
        img.putpixel((57, y), COLORS['black'])

    # Muzzle end
    for y in range(4, 9):
        img.putpixel((59, y), COLORS['black'])

    return img


if __name__ == '__main__':
    # Create sprite
    icon = create_mini_uzi_icon()

    # Save to experiments folder first
    icon.save('experiments/mini_uzi_icon.png')
    print(f"Created mini_uzi_icon.png: {icon.size}")

    # Also save to assets folder
    icon.save('assets/sprites/weapons/mini_uzi_icon.png')

    print("\nSprite saved to:")
    print("  - experiments/mini_uzi_icon.png")
    print("  - assets/sprites/weapons/mini_uzi_icon.png")
