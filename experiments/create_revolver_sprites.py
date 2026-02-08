#!/usr/bin/env python3
"""
Create RSh-12 revolver sprites for the Godot top-down game.
Creates two sprites:
1. revolver_icon.png - Armory icon (80x24) - side view
2. revolver_topdown.png - In-hand view (34x14) - top-down perspective

The RSh-12 is a massive Russian revolver chambered in 12.7x55mm STs-130.
It is distinctly larger and bulkier than the Makarov PM, with a visible
cylinder, short thick barrel, and heavy frame.

Style matches existing weapon sprites (shotgun, M16, silenced pistol).
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
    'grip_dark': (50, 40, 30, 255),
    'grip_medium': (70, 55, 40, 255),
    'grip_light': (85, 70, 50, 255),
    'transparent': (0, 0, 0, 0),
}


def create_revolver_icon():
    """
    Create 80x24 side-view RSh-12 revolver icon.

    Key silhouette features:
    - Large, bulky frame (heavy revolver)
    - Visible cylinder (5-round, 12.7mm)
    - Short, thick barrel with ventilated rib on top
    - Ergonomic rubber grip
    - Exposed hammer at rear
    - Overall massive proportions
    """
    width, height = 80, 24
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Layout (pointing right):
    # [grip] [frame+cylinder] [barrel]
    # Grip: x 4-18
    # Frame/cylinder: x 18-50
    # Barrel: x 50-75

    # === BARREL (short, thick for 12.7mm) - x: 50-75, y: 5-11 ===
    # Top rib / barrel shroud
    for x in range(50, 76):
        img.putpixel((x, 5), COLORS['black'])
        img.putpixel((x, 11), COLORS['black'])
    for y in range(5, 12):
        img.putpixel((75, y), COLORS['black'])

    # Barrel body
    for y in range(6, 11):
        for x in range(50, 75):
            if y == 6:
                img.putpixel((x, y), COLORS['metal_light'])
            elif y == 10:
                img.putpixel((x, y), COLORS['metal_dark'])
            elif y == 7:
                img.putpixel((x, y), COLORS['lighter_gray'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Ventilated rib (top of barrel) - small slots
    for x in range(54, 73, 4):
        img.putpixel((x, 6), COLORS['dark_gray'])
        img.putpixel((x + 1, 6), COLORS['dark_gray'])

    # Muzzle opening
    img.putpixel((75, 7), COLORS['dark_gray'])
    img.putpixel((75, 8), COLORS['dark_gray'])
    img.putpixel((75, 9), COLORS['dark_gray'])

    # Under-barrel lug / weight
    for y in range(11, 14):
        for x in range(50, 68):
            if y == 13 or x == 50 or x == 67:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['metal_dark'])

    # Front sight
    img.putpixel((72, 4), COLORS['black'])
    img.putpixel((73, 4), COLORS['black'])
    img.putpixel((72, 5), COLORS['lighter_gray'])
    img.putpixel((73, 5), COLORS['lighter_gray'])

    # === FRAME (upper part above cylinder) - x: 18-50, y: 4-8 ===
    for y in range(4, 9):
        for x in range(18, 51):
            if y == 4 or y == 8:
                img.putpixel((x, y), COLORS['black'])
            elif x == 18:
                img.putpixel((x, y), COLORS['black'])
            elif y == 5:
                img.putpixel((x, y), COLORS['metal_light'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Rear sight
    img.putpixel((22, 3), COLORS['black'])
    img.putpixel((23, 3), COLORS['black'])
    img.putpixel((24, 3), COLORS['black'])

    # Hammer (exposed, at rear top)
    img.putpixel((19, 2), COLORS['black'])
    img.putpixel((20, 2), COLORS['black'])
    img.putpixel((19, 3), COLORS['metal_medium'])
    img.putpixel((20, 3), COLORS['metal_medium'])
    img.putpixel((19, 4), COLORS['metal_dark'])
    img.putpixel((20, 4), COLORS['metal_dark'])

    # === CYLINDER (large, distinctive revolver feature) - x: 28-48, y: 8-16 ===
    # The cylinder is the most distinctive part of a revolver
    for y in range(8, 17):
        for x in range(28, 49):
            # Create rounded cylinder shape
            cy = 12  # center y
            cx = 38  # center x
            ry = 4   # radius y
            rx = 10  # radius x

            # Check if point is within ellipse
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            dist = dx * dx + dy * dy

            if dist <= 1.0:
                if dist > 0.75:
                    img.putpixel((x, y), COLORS['black'])
                elif dist > 0.6:
                    img.putpixel((x, y), COLORS['metal_dark'])
                elif y <= 10:
                    img.putpixel((x, y), COLORS['metal_light'])
                elif y >= 14:
                    img.putpixel((x, y), COLORS['dark_gray'])
                else:
                    img.putpixel((x, y), COLORS['metal_medium'])

    # Cylinder flutes (vertical lines showing chambers)
    for x in [33, 36, 39, 42, 45]:
        for y in range(9, 16):
            cy = 12
            ry = 4
            dx = (x - 38) / 10
            dy = (y - cy) / ry
            if dx * dx + dy * dy < 0.7:
                img.putpixel((x, y), COLORS['dark_gray'])

    # Cylinder pin / axis
    img.putpixel((38, 8), COLORS['lighter_gray'])
    img.putpixel((38, 16), COLORS['lighter_gray'])

    # === FRAME (lower, connecting cylinder to grip) - x: 18-30, y: 8-16 ===
    for y in range(8, 17):
        for x in range(18, 30):
            if y == 16:
                img.putpixel((x, y), COLORS['black'])
            elif x == 18:
                img.putpixel((x, y), COLORS['black'])
            else:
                # Only fill if not already part of cylinder
                px = img.getpixel((x, y))
                if px == COLORS['transparent']:
                    img.putpixel((x, y), COLORS['metal_medium'])

    # === TRIGGER GUARD - x: 24-38, y: 16-20 ===
    # Front of guard
    img.putpixel((38, 16), COLORS['black'])
    img.putpixel((38, 17), COLORS['black'])
    img.putpixel((38, 18), COLORS['black'])
    img.putpixel((38, 19), COLORS['black'])
    # Bottom of guard
    for x in range(24, 39):
        img.putpixel((x, 20), COLORS['black'])
    # Back of guard (connects to grip)
    img.putpixel((24, 16), COLORS['black'])
    img.putpixel((24, 17), COLORS['black'])
    img.putpixel((24, 18), COLORS['black'])
    img.putpixel((24, 19), COLORS['black'])

    # Trigger
    for y in range(16, 19):
        img.putpixel((30, y), COLORS['metal_dark'])
        img.putpixel((31, y), COLORS['metal_dark'])

    # === GRIP (ergonomic rubber grip, angled back) - x: 4-18, y: 10-23 ===
    for y in range(10, 24):
        progress = (y - 10) / 13.0
        offset = int(progress * 5)  # backward lean
        gx_start = 14 - offset
        gx_end = 20 - offset

        # Grip widens slightly in the middle
        if 3 <= (y - 10) <= 9:
            gx_end += 1

        for x in range(max(0, gx_start), min(width, gx_end + 1)):
            if x == gx_start or x == gx_end or y == 23:
                img.putpixel((x, y), COLORS['black'])
            elif (x + y) % 3 == 0:
                # Rubber grip texture (checkered pattern)
                img.putpixel((x, y), COLORS['grip_dark'])
            elif (x + y) % 3 == 1:
                img.putpixel((x, y), COLORS['grip_medium'])
            else:
                img.putpixel((x, y), COLORS['grip_light'])

    # Connect grip top to frame
    for y in range(8, 11):
        for x in range(14, 19):
            px = img.getpixel((x, y))
            if px == COLORS['transparent']:
                img.putpixel((x, y), COLORS['metal_dark'])

    return img


def create_revolver_topdown():
    """
    Create 34x14 top-down view RSh-12 revolver sprite.

    The RSh-12 is significantly larger than the Makarov PM (30x12),
    with a visible cylinder bulge and thicker barrel.
    """
    width, height = 34, 14
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # RSh-12 top-down layout (pointing right):
    # [grip] [cylinder] [barrel]

    # === GRIP (rubber, rear part) - x: 0-9, y: 2-11 ===
    for y in range(2, 12):
        for x in range(0, 10):
            if y == 2 or y == 11:
                if 2 <= x <= 9:
                    img.putpixel((x, y), COLORS['black'])
            elif x == 0:
                if 3 <= y <= 10:
                    img.putpixel((x, y), COLORS['black'])
            elif x == 9:
                if 3 <= y <= 10:
                    img.putpixel((x, y), COLORS['black'])
            elif y == 3 or y == 10:
                img.putpixel((x, y), COLORS['grip_dark'])
            elif y in (4, 9):
                img.putpixel((x, y), COLORS['grip_medium'])
            else:
                img.putpixel((x, y), COLORS['grip_light'])

    # Grip texture (checkered rubber)
    for y in range(4, 10):
        for x in range(2, 8):
            if (x + y) % 2 == 0:
                img.putpixel((x, y), COLORS['grip_dark'])

    # === FRAME (connecting grip to cylinder) - x: 9-12, y: 3-10 ===
    for y in range(3, 11):
        for x in range(9, 13):
            if y == 3 or y == 10:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # === CYLINDER (large, bulging outward - key revolver feature) - x: 12-22, y: 1-12 ===
    # The cylinder is wider than the frame, creating the distinctive revolver bulge
    for y in range(1, 13):
        for x in range(12, 23):
            # Create elliptical cylinder shape
            cy = 6.5  # center y
            cx = 17   # center x
            ry = 5.5  # radius y
            rx = 5.5  # radius x

            dx = (x - cx) / rx
            dy = (y - cy) / ry
            dist = dx * dx + dy * dy

            if dist <= 1.0:
                if dist > 0.75:
                    img.putpixel((x, y), COLORS['black'])
                elif dist > 0.55:
                    img.putpixel((x, y), COLORS['metal_dark'])
                elif y <= 4:
                    img.putpixel((x, y), COLORS['metal_light'])
                elif y >= 9:
                    img.putpixel((x, y), COLORS['dark_gray'])
                else:
                    img.putpixel((x, y), COLORS['metal_medium'])

    # Cylinder chamber details (circles visible from top)
    # Center chamber
    img.putpixel((17, 6), COLORS['dark_gray'])
    img.putpixel((17, 7), COLORS['dark_gray'])
    # Surrounding chambers (visible from top as darker spots)
    for cx, cy in [(15, 4), (19, 4), (15, 9), (19, 9)]:
        img.putpixel((cx, cy), COLORS['dark_gray'])

    # === BARREL (thick, short for 12.7mm) - x: 22-33, y: 4-9 ===
    for y in range(4, 10):
        for x in range(22, 33):
            # Only draw if not already part of cylinder
            px = img.getpixel((x, y))
            if px == COLORS['transparent'] or x >= 23:
                if y == 4 or y == 9:
                    img.putpixel((x, y), COLORS['black'])
                elif y == 5:
                    img.putpixel((x, y), COLORS['metal_light'])
                elif y == 8:
                    img.putpixel((x, y), COLORS['metal_dark'])
                else:
                    img.putpixel((x, y), COLORS['metal_medium'])

    # Muzzle tip
    img.putpixel((33, 5), COLORS['black'])
    img.putpixel((33, 6), COLORS['dark_gray'])
    img.putpixel((33, 7), COLORS['dark_gray'])
    img.putpixel((33, 8), COLORS['black'])

    # Front sight
    img.putpixel((32, 5), COLORS['lighter_gray'])
    img.putpixel((32, 8), COLORS['lighter_gray'])

    # Rear sight (on frame, behind cylinder)
    img.putpixel((10, 4), COLORS['lighter_gray'])
    img.putpixel((10, 9), COLORS['lighter_gray'])

    return img


if __name__ == '__main__':
    # Create sprites
    icon = create_revolver_icon()
    topdown = create_revolver_topdown()

    # Save to experiments folder first
    icon.save('experiments/revolver_icon.png')
    topdown.save('experiments/revolver_topdown.png')

    print(f"Created revolver_icon.png: {icon.size}")
    print(f"Created revolver_topdown.png: {topdown.size}")

    # Also save to assets folder
    icon.save('assets/sprites/weapons/revolver_icon.png')
    topdown.save('assets/sprites/weapons/revolver_topdown.png')

    print("\nSprites saved to:")
    print("  - experiments/revolver_icon.png")
    print("  - experiments/revolver_topdown.png")
    print("  - assets/sprites/weapons/revolver_icon.png")
    print("  - assets/sprites/weapons/revolver_topdown.png")
    print("\nNote: The RSh-12 is larger than the PM to reflect its 12.7mm caliber")
    print("and heavy revolver design.")
