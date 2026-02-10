#!/usr/bin/env python3
"""Create a breaker bullets icon for the armory.

The icon shows a bullet (copper/brass colored) with fracture lines
and small explosion/shrapnel particles around the tip, on a transparent background.
Size: 64x64 pixels, RGBA mode.
"""

from PIL import Image, ImageDraw
import math

def create_breaker_bullets_icon():
    size = 64
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Colors
    bullet_body = (180, 140, 60, 255)       # Brass/copper bullet body
    bullet_tip = (200, 160, 80, 255)        # Lighter tip
    bullet_dark = (140, 100, 40, 255)       # Darker shade
    bullet_base = (120, 85, 35, 255)        # Base of bullet
    casing = (160, 130, 50, 255)            # Casing color
    explosion_orange = (255, 140, 30, 230)  # Explosion orange
    explosion_yellow = (255, 200, 40, 200)  # Explosion yellow
    explosion_red = (220, 80, 20, 180)      # Explosion red
    fracture = (80, 60, 20, 255)            # Fracture line color
    shrapnel_color = (180, 140, 60, 200)    # Shrapnel pieces

    # Draw bullet body (pointing right, centered vertically)
    # Bullet is ~36px long, ~12px wide, centered at (24, 32)
    cx, cy = 24, 32

    # Bullet casing (rear rectangle)
    draw.rectangle([cx - 14, cy - 6, cx + 4, cy + 6], fill=casing)
    draw.rectangle([cx - 16, cy - 7, cx - 14, cy + 7], fill=bullet_base)  # Rim

    # Bullet body (main ogive shape - front part)
    draw.rectangle([cx + 4, cy - 5, cx + 14, cy + 5], fill=bullet_body)

    # Bullet tip (pointed)
    tip_points = [
        (cx + 14, cy - 5),
        (cx + 22, cy),
        (cx + 14, cy + 5),
    ]
    draw.polygon(tip_points, fill=bullet_tip)

    # Add highlight on bullet body
    draw.line([(cx - 12, cy - 4), (cx + 12, cy - 4)], fill=(220, 180, 100, 200), width=1)

    # Add darker bottom edge
    draw.line([(cx - 12, cy + 5), (cx + 12, cy + 5)], fill=bullet_dark, width=1)

    # Fracture lines on bullet (showing it's about to break)
    draw.line([(cx + 8, cy - 5), (cx + 12, cy + 2)], fill=fracture, width=1)
    draw.line([(cx + 10, cy - 3), (cx + 16, cy + 4)], fill=fracture, width=1)

    # Explosion/shrapnel effect at the tip
    # Small triangular shrapnel pieces flying outward
    shrapnel_positions = [
        # (x, y, angle) - relative to tip
        (cx + 28, cy - 10, -30),
        (cx + 32, cy - 4, -10),
        (cx + 30, cy + 2, 10),
        (cx + 26, cy + 10, 30),
        (cx + 34, cy - 8, -20),
        (cx + 36, cy + 6, 20),
        (cx + 30, cy - 14, -45),
        (cx + 28, cy + 14, 45),
    ]

    for sx, sy, angle in shrapnel_positions:
        # Small diamond-shaped shrapnel pieces
        rad = math.radians(angle)
        s = 2  # size
        points = [
            (sx - s, sy),
            (sx, sy - s),
            (sx + s, sy),
            (sx, sy + s),
        ]
        draw.polygon(points, fill=shrapnel_color)

    # Explosion glow at detonation point (between bullet and shrapnel)
    # Orange-yellow glow
    for r in range(8, 2, -1):
        alpha = int(60 * (8 - r) / 6)
        glow_color = (255, 160, 40, alpha)
        draw.ellipse([cx + 22 - r, cy - r, cx + 22 + r, cy + r], fill=glow_color)

    # Small bright center at detonation point
    draw.ellipse([cx + 20, cy - 3, cx + 26, cy + 3], fill=(255, 220, 100, 150))

    # Explosion lines radiating from tip
    line_color = (255, 160, 40, 160)
    for angle_deg in [-40, -20, 0, 20, 40]:
        rad = math.radians(angle_deg)
        x1 = cx + 23
        y1 = cy
        length = 10
        x2 = x1 + int(length * math.cos(rad))
        y2 = y1 + int(length * math.sin(rad))
        draw.line([(x1, y1), (x2, y2)], fill=line_color, width=1)

    # Small smoke/dust particles
    smoke_positions = [(cx + 35, cy - 12), (cx + 38, cy + 10), (cx + 40, cy - 2)]
    for sx, sy in smoke_positions:
        draw.ellipse([sx - 1, sy - 1, sx + 1, sy + 1], fill=(150, 150, 150, 100))

    return img


if __name__ == '__main__':
    icon = create_breaker_bullets_icon()
    output_path = '/tmp/gh-issue-solver-1770592260660/assets/sprites/weapons/breaker_bullets_icon.png'
    icon.save(output_path)
    print(f"Icon saved to {output_path}")

    # Also save preview
    preview_path = '/tmp/gh-issue-solver-1770592260660/experiments/breaker_icon_preview.png'
    icon.save(preview_path)
    print(f"Preview saved to {preview_path}")
