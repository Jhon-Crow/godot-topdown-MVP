#!/usr/bin/env python3
"""
Create shotgun sprites for the Godot top-down game.
Creates two sprites:
1. shotgun_topdown.png - In-hand view (64x16) - top-down perspective
2. shotgun_icon.png - Armory icon (80x24) - side view

Style matches existing M16 rifle sprites.
"""

from PIL import Image

# Color palette matching M16 style
COLORS = {
    'black': (30, 30, 30, 255),
    'dark_gray': (45, 45, 45, 255),
    'brown': (50, 40, 30, 255),
    'medium_gray': (60, 60, 60, 255),
    'light_gray': (70, 70, 70, 255),
    'lighter_gray': (90, 90, 90, 255),
    'lightest_gray': (100, 100, 100, 255),
    'wood_dark': (65, 45, 25, 255),
    'wood_medium': (85, 60, 35, 255),
    'wood_light': (100, 75, 45, 255),
    'metal_dark': (35, 35, 40, 255),
    'metal_medium': (50, 50, 55, 255),
    'metal_light': (70, 70, 75, 255),
    'transparent': (0, 0, 0, 0),
}


def create_shotgun_topdown():
    """
    Create 64x16 top-down view shotgun sprite.
    Similar layout to m16_rifle_topdown.png but with shotgun characteristics:
    - Thicker barrel
    - Pump/forend section
    - Stock at the back
    """
    width, height = 64, 16
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Pump-action shotgun top-down layout (pointing right):
    # [stock] [receiver] [pump/forend] [barrel]

    # Stock (wooden, rear part) - x: 0-12
    for y in range(5, 11):
        for x in range(0, 13):
            if y == 5 or y == 10:
                if x >= 3:
                    img.putpixel((x, y), COLORS['black'])
            elif y in [6, 9]:
                if x >= 1:
                    img.putpixel((x, y), COLORS['black'] if x <= 1 else COLORS['wood_dark'])
            else:  # y in [7, 8]
                if x >= 0:
                    img.putpixel((x, y), COLORS['wood_medium'] if x > 0 else COLORS['black'])

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

    # Pump/Forend (wooden, sliding part) - x: 31-45
    for y in range(5, 11):
        for x in range(31, 46):
            if y == 5 or y == 10:
                img.putpixel((x, y), COLORS['black'])
            elif y in [6, 9]:
                img.putpixel((x, y), COLORS['wood_dark'])
            else:  # middle part
                img.putpixel((x, y), COLORS['wood_medium'])

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


def create_shotgun_icon():
    """
    Create 80x24 side-view armory icon.
    Similar layout to m16_rifle.png but with shotgun characteristics:
    - Pump-action design
    - Wooden stock and forend
    - Thicker barrel
    """
    width, height = 80, 24
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Shotgun side view (pointing right):
    # [stock] [grip] [receiver] [pump/forend] [barrel]

    # Stock (wooden, curved) - x: 0-18
    for y in range(6, 17):
        for x in range(0, 19):
            # Create angled stock shape
            if y <= 8:
                min_x = 14 - (y - 6) * 3
            elif y <= 11:
                min_x = 0
            else:
                min_x = (y - 11) * 2

            if x >= min_x:
                if y == 6 or y == 16 or x == min_x or x == 18:
                    img.putpixel((x, y), COLORS['metal_dark'])
                else:
                    img.putpixel((x, y), COLORS['wood_medium'])

    # Receiver (metal body) - x: 19-38
    for y in range(5, 15):
        for x in range(19, 39):
            if y == 5 or y == 14:
                img.putpixel((x, y), COLORS['metal_dark'])
            elif y == 6 or y == 13:
                img.putpixel((x, y), COLORS['metal_medium'])
            else:
                img.putpixel((x, y), COLORS['metal_light'])

    # Pistol grip - below receiver
    for y in range(14, 22):
        for x in range(22, 30):
            if y == 14:
                continue  # skip top (part of receiver)
            grip_width = 8 - (y - 14) // 2
            start_x = 22 + (8 - grip_width) // 2
            if start_x <= x < start_x + grip_width:
                if y == 21 or x == start_x or x == start_x + grip_width - 1:
                    img.putpixel((x, y), COLORS['metal_dark'])
                else:
                    img.putpixel((x, y), COLORS['wood_dark'])

    # Trigger guard
    for y in range(14, 19):
        for x in range(30, 38):
            if y == 14 or y == 18:
                img.putpixel((x, y), COLORS['metal_dark'])
            elif x == 30 or x == 37:
                img.putpixel((x, y), COLORS['metal_dark'])

    # Pump/Forend (wooden) - x: 39-55
    for y in range(7, 13):
        for x in range(39, 56):
            if y == 7 or y == 12:
                img.putpixel((x, y), COLORS['metal_dark'])
            elif y == 8 or y == 11:
                img.putpixel((x, y), COLORS['wood_dark'])
            else:
                img.putpixel((x, y), COLORS['wood_medium'])

    # Barrel (metal, thicker for shotgun) - x: 56-79
    for y in range(8, 12):
        for x in range(56, 80):
            if y == 8 or y == 11:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Magazine tube (below barrel)
    for y in range(12, 14):
        for x in range(39, 75):
            if y == 12:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Muzzle end
    for y in range(7, 13):
        img.putpixel((79, y), COLORS['metal_dark'])

    # Front sight
    for y in range(5, 8):
        img.putpixel((75, y), COLORS['metal_dark'])
        img.putpixel((76, y), COLORS['metal_dark'])

    return img


if __name__ == '__main__':
    # Create sprites
    topdown = create_shotgun_topdown()
    icon = create_shotgun_icon()

    # Save to experiments folder first
    topdown.save('experiments/shotgun_topdown.png')
    icon.save('experiments/shotgun_icon.png')

    print(f"Created shotgun_topdown.png: {topdown.size}")
    print(f"Created shotgun_icon.png: {icon.size}")

    # Also save to assets folder
    topdown.save('assets/sprites/weapons/shotgun_topdown.png')
    icon.save('assets/sprites/weapons/shotgun_icon.png')

    print("\nSprites saved to:")
    print("  - experiments/shotgun_topdown.png")
    print("  - experiments/shotgun_icon.png")
    print("  - assets/sprites/weapons/shotgun_topdown.png")
    print("  - assets/sprites/weapons/shotgun_icon.png")
