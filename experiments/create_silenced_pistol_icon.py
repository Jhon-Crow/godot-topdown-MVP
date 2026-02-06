#!/usr/bin/env python3
"""
Create Silenced Pistol icon sprite for the Godot top-down game.
Creates armory icon (80x24) - side view matching the Beretta M9 with suppressor reference.

Reference: Beretta M92-style pistol with suppressor, tactical light/laser
mounted under the barrel, ergonomic grip with finger grooves, visible trigger
guard, rear sight, and long cylindrical suppressor.

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
    'highlight': (100, 100, 100, 255),
    'metal_dark': (35, 35, 40, 255),
    'metal_medium': (50, 50, 55, 255),
    'metal_light': (70, 70, 75, 255),
    'transparent': (0, 0, 0, 0),
}


def create_silenced_pistol_icon():
    """
    Create 80x24 side-view Beretta M9 with suppressor icon.

    Key silhouette features from reference:
    - Ergonomic grip with finger grooves (rear, angled back)
    - Magazine base plate visible at bottom of grip
    - Trigger guard with trigger
    - Slide on top (with rear sight, front sight)
    - Frame/dust cover with accessory rail
    - Tactical light/laser mounted under rail
    - Short exposed barrel
    - Long cylindrical suppressor
    """
    width, height = 80, 24
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Layout (pointing right):
    # [grip] [frame+trigger guard] [slide on top, frame below] [barrel] [suppressor]

    # === GRIP (ergonomic, angled back) - right side of image ===
    # Beretta grip is at x: 52-63 roughly, below the slide
    # In the reference, grip is on the RIGHT side (gun points LEFT with suppressor on left)
    # But we draw gun pointing RIGHT, so grip is on the LEFT side

    # Let's lay out from left to right:
    # Grip area: x 4-16
    # Frame/trigger: x 17-38
    # Slide: x 8-42
    # Barrel: x 43-47
    # Suppressor: x 48-78

    # === SLIDE (top section) - x: 8-42, y: 4-9 ===
    for x in range(8, 43):
        img.putpixel((x, 4), COLORS['black'])
        img.putpixel((x, 9), COLORS['black'])
    for y in range(4, 10):
        img.putpixel((8, y), COLORS['black'])
        img.putpixel((42, y), COLORS['black'])
    for y in range(5, 9):
        for x in range(9, 42):
            if y == 5:
                img.putpixel((x, y), COLORS['metal_dark'])
            elif y == 8:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Slide serrations (rear of slide) - vertical lines
    for x in range(10, 18, 2):
        for y in range(5, 9):
            img.putpixel((x, y), COLORS['dark_gray'])

    # Ejection port
    for x in range(22, 28):
        img.putpixel((x, 5), COLORS['lighter_gray'])
        img.putpixel((x, 6), COLORS['lighter_gray'])

    # Rear sight
    img.putpixel((12, 3), COLORS['black'])
    img.putpixel((13, 3), COLORS['black'])

    # Front sight
    img.putpixel((39, 3), COLORS['black'])
    img.putpixel((40, 3), COLORS['black'])

    # Safety/decocker lever (small detail on slide)
    img.putpixel((16, 5), COLORS['highlight'])

    # === FRAME (lower receiver) - x: 17-42, y: 10-13 ===
    for x in range(17, 43):
        img.putpixel((x, 10), COLORS['metal_dark'])
    for y in range(10, 14):
        for x in range(17, 43):
            if y == 13:
                img.putpixel((x, y), COLORS['black'])
            elif y == 10:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:
                img.putpixel((x, y), COLORS['dark_gray'])

    # Accessory rail grooves on frame
    for x in range(30, 40, 3):
        img.putpixel((x, 12), COLORS['metal_dark'])

    # === GRIP (ergonomic, angled backward) - x: 4-16, y: 9-21 ===
    # The grip connects to the frame and angles backward
    for y in range(9, 22):
        # Grip gets wider at middle, tapers at bottom
        progress = (y - 9) / 12.0
        # Angle: grip leans back as it goes down
        offset = int(progress * 4)  # backward lean
        gx_start = 8 - offset
        gx_end = 16 - offset

        # Grip widens in middle section
        if 3 <= (y - 9) <= 8:
            gx_end += 1

        for x in range(max(0, gx_start), gx_end + 1):
            if x == gx_start or x == gx_end or y == 21:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['dark_gray'])

    # Grip texture - finger grooves (horizontal lines)
    for y in [12, 14, 16, 18]:
        if y < 22:
            progress = (y - 9) / 12.0
            offset = int(progress * 4)
            for x in range(max(1, 9 - offset), 16 - offset):
                img.putpixel((x, y), COLORS['metal_dark'])

    # Magazine base plate (bottom of grip)
    for y_off in range(0, 2):
        progress = (21 + y_off - 9) / 12.0
        offset = int(progress * 4)
        gx_start = 7 - offset
        gx_end = 16 - offset
        for x in range(max(0, gx_start), gx_end + 1):
            img.putpixel((x, 22 + y_off), COLORS['black'])

    # Beaver tail / grip safety area (top of grip, where hand meets frame)
    for x in range(8, 12):
        img.putpixel((x, 9), COLORS['metal_dark'])

    # === TRIGGER GUARD - x: 17-28, y: 14-18 ===
    # Front of trigger guard
    img.putpixel((28, 14), COLORS['black'])
    img.putpixel((28, 15), COLORS['black'])
    img.putpixel((28, 16), COLORS['black'])
    img.putpixel((28, 17), COLORS['black'])
    # Bottom of trigger guard
    for x in range(17, 29):
        img.putpixel((x, 18), COLORS['black'])
    # Back of trigger guard (connects to grip)
    img.putpixel((17, 14), COLORS['black'])
    img.putpixel((17, 15), COLORS['black'])
    img.putpixel((17, 16), COLORS['black'])
    img.putpixel((17, 17), COLORS['black'])

    # Trigger
    for y in range(14, 17):
        img.putpixel((22, y), COLORS['metal_dark'])
        img.putpixel((23, y), COLORS['metal_dark'])

    # === TACTICAL LIGHT/LASER (mounted under rail) - x: 30-38, y: 14-17 ===
    for y in range(14, 18):
        for x in range(30, 39):
            if y == 14 or y == 17 or x == 30 or x == 38:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['medium_gray'])
    # Laser lens (front)
    img.putpixel((38, 15), COLORS['lighter_gray'])
    img.putpixel((38, 16), COLORS['lighter_gray'])
    # Activation button on top
    img.putpixel((34, 13), COLORS['metal_medium'])

    # === BARREL (short exposed section) - x: 43-48, y: 6-8 ===
    for x in range(43, 49):
        img.putpixel((x, 6), COLORS['metal_dark'])
        img.putpixel((x, 7), COLORS['metal_medium'])
        img.putpixel((x, 8), COLORS['metal_dark'])

    # === SUPPRESSOR (long cylindrical tube) - x: 49-78, y: 4-10 ===
    # Suppressor is wider than barrel
    # Back cap
    for y in range(4, 11):
        img.putpixel((49, y), COLORS['black'])

    # Suppressor body
    for x in range(50, 78):
        img.putpixel((x, 4), COLORS['black'])
        img.putpixel((x, 10), COLORS['black'])
    for y in range(5, 10):
        for x in range(50, 78):
            if y == 5 or y == 9:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Front cap
    for y in range(4, 11):
        img.putpixel((78, y), COLORS['black'])
    # Front face
    for y in range(3, 12):
        img.putpixel((79, y), COLORS['black'])

    # Suppressor details: subtle ring marks
    for x in [55, 62, 69, 75]:
        for y in range(5, 10):
            img.putpixel((x, y), COLORS['dark_gray'])

    # Suppressor end holes/ports (decorative)
    for y in [6, 8]:
        img.putpixel((77, y), COLORS['lighter_gray'])

    return img


if __name__ == '__main__':
    # Create sprite
    icon = create_silenced_pistol_icon()

    # Save to experiments folder first
    icon.save('experiments/silenced_pistol_icon.png')
    print(f"Created silenced_pistol_icon.png: {icon.size}")

    # Also save to assets folder (replacing the previous version)
    icon.save('assets/sprites/weapons/silenced_pistol_icon.png')

    print("\nSprite saved to:")
    print("  - experiments/silenced_pistol_icon.png")
    print("  - assets/sprites/weapons/silenced_pistol_icon.png")
    print("\nNote: This replaces the previous icon with a more accurate version")
    print("matching the Beretta M9 with suppressor and tactical light reference.")
