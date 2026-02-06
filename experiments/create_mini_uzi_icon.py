#!/usr/bin/env python3
"""
Create Mini UZI icon sprite for the Godot top-down game.
Creates armory icon (60x18) - side view matching the real UZI reference.

Reference: Classic full-size UZI with folding wire stock, boxy receiver,
ribbed barrel shroud, magazine in pistol grip, trigger guard.

Style matches existing weapon sprites (shotgun, M16).
"""

from PIL import Image, ImageDraw

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


def create_mini_uzi_icon():
    """
    Create 60x18 side-view UZI icon matching the real UZI reference photo.

    Key silhouette features from reference:
    - Folding wire stock (extended) on left
    - Tall boxy receiver body
    - Ribbed/grooved barrel shroud
    - Pistol grip with magazine inserted
    - Trigger guard
    - Short barrel tip
    """
    width, height = 60, 18
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Build UZI silhouette pixel by pixel
    # Layout (pointing right): [wire stock] [receiver] [barrel shroud] [muzzle]
    # Grip+magazine hangs below receiver

    # === FOLDING WIRE STOCK (extended) - x: 0-10 ===
    # Top arm of stock
    for x in range(0, 10):
        img.putpixel((x, 4), COLORS['metal_dark'])
    # Bottom arm of stock
    for x in range(0, 10):
        img.putpixel((x, 8), COLORS['metal_dark'])
    # Stock end plate (left side)
    for y in range(3, 10):
        img.putpixel((0, y), COLORS['metal_medium'])
        img.putpixel((1, y), COLORS['metal_dark'])
    # Stock hinge connection (where it meets receiver)
    for y in range(4, 9):
        img.putpixel((9, y), COLORS['metal_dark'])
        img.putpixel((10, y), COLORS['metal_dark'])

    # === RECEIVER BODY (tall, boxy) - x: 11-32 ===
    # Top edge of receiver
    for x in range(11, 33):
        img.putpixel((x, 2), COLORS['black'])
    # Bottom edge of receiver
    for x in range(11, 33):
        img.putpixel((x, 9), COLORS['black'])
    # Left/right edges
    for y in range(2, 10):
        img.putpixel((11, y), COLORS['black'])
        img.putpixel((32, y), COLORS['black'])
    # Fill receiver body
    for y in range(3, 9):
        for x in range(12, 32):
            if y <= 3:
                img.putpixel((x, y), COLORS['metal_dark'])
            elif y >= 8:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Receiver details: ejection port / cocking slot
    for x in range(16, 26):
        img.putpixel((x, 4), COLORS['lighter_gray'])
    # Cocking handle knob
    img.putpixel((20, 3), COLORS['lighter_gray'])

    # Rear sight nub on top
    img.putpixel((14, 1), COLORS['black'])
    img.putpixel((15, 1), COLORS['black'])

    # Front sight on top of receiver
    img.putpixel((30, 1), COLORS['black'])
    img.putpixel((31, 1), COLORS['black'])

    # === PISTOL GRIP + MAGAZINE (below receiver) - x: 17-24 ===
    # The UZI has the magazine inside the pistol grip (key feature)
    # Grip shape: slightly angled back
    for y in range(10, 17):
        offset = (y - 10) // 3  # slight backward angle
        gx_start = 18 - offset
        gx_end = 24 - offset
        for x in range(gx_start, gx_end + 1):
            if x == gx_start or x == gx_end or y == 16:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['dark_gray'])
    # Magazine base plate (slightly wider at bottom)
    for x in range(16, 24):
        img.putpixel((x, 17), COLORS['black'])

    # Grip texture lines (horizontal)
    for y in [11, 13, 15]:
        offset = (y - 10) // 3
        for x in range(19 - offset, 24 - offset):
            img.putpixel((x, y), COLORS['metal_dark'])

    # === TRIGGER GUARD - x: 25-30, below receiver ===
    for x in range(25, 31):
        img.putpixel((x, 12), COLORS['black'])
    img.putpixel((25, 10), COLORS['black'])
    img.putpixel((25, 11), COLORS['black'])
    img.putpixel((30, 10), COLORS['black'])
    img.putpixel((30, 11), COLORS['black'])
    # Trigger
    img.putpixel((27, 10), COLORS['metal_dark'])
    img.putpixel((27, 11), COLORS['metal_dark'])

    # === BARREL SHROUD (ribbed) - x: 33-50 ===
    # Top and bottom edges
    for x in range(33, 51):
        img.putpixel((x, 4), COLORS['black'])
        img.putpixel((x, 8), COLORS['black'])
    # Fill barrel shroud body
    for y in range(5, 8):
        for x in range(33, 51):
            img.putpixel((x, y), COLORS['metal_medium'])

    # Ribbing/grooves on barrel shroud (vertical lines every 2 pixels)
    for x in range(34, 50, 2):
        for y in range(5, 8):
            img.putpixel((x, y), COLORS['metal_dark'])

    # === MUZZLE / BARREL TIP - x: 51-59 ===
    # Barrel extends from shroud
    for x in range(51, 59):
        img.putpixel((x, 5), COLORS['black'])
        img.putpixel((x, 7), COLORS['black'])
        img.putpixel((x, 6), COLORS['metal_light'])

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
