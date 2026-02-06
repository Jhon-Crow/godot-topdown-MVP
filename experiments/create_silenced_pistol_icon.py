#!/usr/bin/env python3
"""
Create Silenced Pistol icon sprite for the Godot top-down game.
Creates armory icon (80x24) - side view (replacing the top-down view).

This is a Beretta M9 with suppressor in side profile.
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


def create_silenced_pistol_icon():
    """
    Create 80x24 side-view Beretta M9 with suppressor icon.
    Semi-automatic pistol design with:
    - Grip at rear
    - Slide/receiver
    - Barrel
    - Suppressor attached to barrel
    """
    width, height = 80, 24
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Silenced Pistol side view (pointing right):
    # [grip] [trigger guard] [slide/receiver] [barrel] [suppressor]

    # Grip (angled backward) - x: 0-12
    for y in range(6, 20):
        for x in range(0, 13):
            # Create angled grip shape
            if y <= 12:
                min_x = 12 - (y - 6) // 2
            else:
                min_x = (y - 12)

            if x >= min_x and x <= 12:
                if x == min_x or x == 12 or y == 19:
                    img.putpixel((x, y), COLORS['black'])
                else:
                    img.putpixel((x, y), COLORS['dark_gray'])

    # Trigger guard - x: 13-22
    for y in range(13, 18):
        for x in range(13, 23):
            if y == 13 or y == 17:
                img.putpixel((x, y), COLORS['black'])
            elif x == 13 or x == 22:
                img.putpixel((x, y), COLORS['black'])

    # Slide/Receiver (top part) - x: 13-45
    for y in range(5, 11):
        for x in range(13, 46):
            if y == 5 or y == 10:
                img.putpixel((x, y), COLORS['black'])
            elif y == 6 or y == 9:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Frame (lower part of receiver) - x: 13-38
    for y in range(10, 14):
        for x in range(13, 39):
            if y == 13:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['metal_dark'])

    # Magazine (protruding from grip) - x: 7-11
    for y in range(19, 23):
        for x in range(7, 12):
            if y == 19:
                continue  # skip top line (already part of grip bottom)
            elif x == 7 or x == 11:
                img.putpixel((x, y), COLORS['black'])
            elif y == 22:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['dark_gray'])

    # Barrel (short, before suppressor) - x: 46-52
    for y in range(7, 9):
        for x in range(46, 53):
            if y == 7 or y == 8:
                img.putpixel((x, y), COLORS['metal_dark'])

    # Suppressor (long cylindrical tube) - x: 53-78
    for y in range(5, 11):
        for x in range(53, 79):
            if y == 5 or y == 10:
                img.putpixel((x, y), COLORS['black'])
            elif y == 6 or y == 9:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Suppressor end cap
    for y in range(4, 12):
        img.putpixel((79, y), COLORS['black'])

    # Front sight (on top of slide, before suppressor)
    for y in range(3, 5):
        img.putpixel((43, y), COLORS['black'])
        img.putpixel((44, y), COLORS['black'])

    # Rear sight (on top of slide, at back)
    for y in range(3, 5):
        img.putpixel((15, y), COLORS['black'])
        img.putpixel((16, y), COLORS['black'])

    # Suppressor ventilation holes (decorative detail)
    for x in range(58, 75, 8):
        for y in range(7, 9):
            img.putpixel((x, y), COLORS['black'])

    return img


if __name__ == '__main__':
    # Create sprite
    icon = create_silenced_pistol_icon()

    # Save to experiments folder first
    icon.save('experiments/silenced_pistol_icon.png')
    print(f"Created silenced_pistol_icon.png: {icon.size}")

    # Also save to assets folder (replacing the topdown version)
    icon.save('assets/sprites/weapons/silenced_pistol_icon.png')

    print("\nSprite saved to:")
    print("  - experiments/silenced_pistol_icon.png")
    print("  - assets/sprites/weapons/silenced_pistol_icon.png")
    print("\nNote: This replaces the top-down view with a side view for the armory.")
