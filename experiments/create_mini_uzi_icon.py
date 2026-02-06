#!/usr/bin/env python3
"""
Create Mini UZI icon sprite for the Godot top-down game.
Creates armory icon (60x18) - side view matching the real UZI reference.

Reference: Mini UZI - compact submachine gun, slightly larger than a pistol.
Key features: boxy receiver dominates, very short barrel, folding stock (folded),
magazine in pistol grip. Overall shape is COMPACT and STUBBY, NOT like a rifle.

Issue #530: The icon should look like a submachine gun (pistol-sized),
not like a full-sized assault rifle. Short barrel, narrow body.

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
    Create 60x18 side-view Mini UZI icon matching reference photos.

    Issue #530 feedback: UZI is a submachine gun (slightly larger than a pistol),
    current icon looks like a full-sized assault rifle. Must be compact and stubby.

    Key design decisions:
    - Stock is FOLDED (shown as small bump on the left) - makes it compact
    - Receiver body is the dominant feature (~40% of visible weapon)
    - Barrel shroud is VERY short (~15% of visible weapon)
    - Muzzle barely extends beyond shroud
    - Overall weapon occupies only about 35px of the 60px canvas (compact)
    - Prominent pistol grip with magazine (defining UZI feature)

    Proportions (within 60x18 canvas, weapon centered):
    - Folded stock bump: ~4px
    - Receiver body: ~16px (dominant)
    - Barrel shroud: ~6px (very short)
    - Muzzle: ~2px
    - Total weapon width: ~28px (compact, leaves padding on both sides)
    """
    width, height = 60, 18
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Center the weapon horizontally in the 60px canvas
    # Weapon is about 28px wide, offset from left by ~16px to center it
    ox = 16  # horizontal offset for centering

    # === FOLDED STOCK (small bump on left) - compact, not extended ===
    # When folded, the stock sits on top/alongside the receiver as a small element
    # Just a small plate visible at the back
    for y in range(4, 8):
        img.putpixel((ox + 0, y), COLORS['metal_dark'])
        img.putpixel((ox + 1, y), COLORS['metal_dark'])
    # Stock hinge pin
    img.putpixel((ox + 2, 5), COLORS['lighter_gray'])
    img.putpixel((ox + 2, 6), COLORS['lighter_gray'])

    # === RECEIVER BODY (tall, boxy - DOMINANT section) ===
    # x: ox+3 to ox+18 (16px wide) - this is the main body
    rx_start = ox + 3
    rx_end = ox + 19  # exclusive

    # Top edge of receiver
    for x in range(rx_start, rx_end):
        img.putpixel((x, 3), COLORS['black'])
    # Bottom edge of receiver
    for x in range(rx_start, rx_end):
        img.putpixel((x, 9), COLORS['black'])
    # Left/right edges
    for y in range(3, 10):
        img.putpixel((rx_start, y), COLORS['black'])
        img.putpixel((rx_end - 1, y), COLORS['black'])
    # Fill receiver body
    for y in range(4, 9):
        for x in range(rx_start + 1, rx_end - 1):
            if y <= 4:
                img.putpixel((x, y), COLORS['metal_dark'])
            elif y >= 8:
                img.putpixel((x, y), COLORS['metal_dark'])
            else:
                img.putpixel((x, y), COLORS['metal_medium'])

    # Receiver details: ejection port / cocking slot
    for x in range(rx_start + 3, rx_start + 10):
        img.putpixel((x, 5), COLORS['lighter_gray'])
    # Cocking handle knob
    img.putpixel((rx_start + 6, 4), COLORS['lighter_gray'])

    # Rear sight nub on top
    img.putpixel((rx_start + 2, 2), COLORS['black'])
    img.putpixel((rx_start + 3, 2), COLORS['black'])

    # Front sight on top of receiver (near front)
    img.putpixel((rx_end - 3, 2), COLORS['black'])
    img.putpixel((rx_end - 2, 2), COLORS['black'])

    # === PISTOL GRIP + MAGAZINE (below receiver) ===
    # UZI's defining feature: magazine inside the pistol grip
    # Grip at the center of the receiver
    grip_cx = rx_start + 6  # center of grip
    for y in range(10, 16):
        offset = (y - 10) // 3  # slight backward angle
        gx_start = grip_cx - 2 - offset
        gx_end = grip_cx + 2 - offset
        for x in range(gx_start, gx_end + 1):
            if x == gx_start or x == gx_end or y == 15:
                img.putpixel((x, y), COLORS['black'])
            else:
                img.putpixel((x, y), COLORS['dark_gray'])
    # Magazine base plate (slightly wider at bottom)
    for x in range(grip_cx - 3 - 1, grip_cx + 2 - 1):
        img.putpixel((x, 16), COLORS['black'])

    # Grip texture lines (horizontal)
    for y in [11, 13]:
        offset = (y - 10) // 3
        for x in range(grip_cx - 1 - offset, grip_cx + 2 - offset):
            img.putpixel((x, y), COLORS['metal_dark'])

    # === TRIGGER GUARD ===
    tg_start = grip_cx + 3
    tg_end = tg_start + 4
    for x in range(tg_start, tg_end):
        img.putpixel((x, 12), COLORS['black'])
    img.putpixel((tg_start, 10), COLORS['black'])
    img.putpixel((tg_start, 11), COLORS['black'])
    img.putpixel((tg_end - 1, 10), COLORS['black'])
    img.putpixel((tg_end - 1, 11), COLORS['black'])
    # Trigger
    img.putpixel((tg_start + 1, 10), COLORS['metal_dark'])
    img.putpixel((tg_start + 1, 11), COLORS['metal_dark'])

    # === BARREL SHROUD (very short, thicker) ===
    # x: rx_end to rx_end+5 (6px) - much shorter than receiver
    # The shroud is cylindrical and thick (almost as tall as receiver mid-section)
    bx_start = rx_end
    bx_end = rx_end + 6

    # Top and bottom edges of shroud
    for x in range(bx_start, bx_end):
        img.putpixel((x, 4), COLORS['black'])
        img.putpixel((x, 9), COLORS['black'])
    # Fill barrel shroud body (4px tall - substantial cylinder)
    for y in range(5, 9):
        for x in range(bx_start, bx_end):
            img.putpixel((x, y), COLORS['metal_medium'])

    # Ribbing/grooves on barrel shroud (vertical lines for texture)
    for x in range(bx_start + 1, bx_end - 1, 2):
        for y in range(5, 9):
            img.putpixel((x, y), COLORS['metal_dark'])

    # === MUZZLE / BARREL TIP (barely extends) ===
    # Just 2 pixels past the shroud
    mx = bx_end
    for y in range(5, 9):
        img.putpixel((mx, y), COLORS['black'])
    img.putpixel((mx + 1, 6), COLORS['metal_light'])
    img.putpixel((mx + 1, 7), COLORS['metal_light'])

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
