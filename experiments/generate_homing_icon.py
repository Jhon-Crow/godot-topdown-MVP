#!/usr/bin/env python3
"""
Generate a homing bullets icon for the armory menu.
Size: 64x48 pixels, RGBA PNG with transparent background.

The icon depicts a stylized bullet with curved motion trail lines
and a small crosshair/target, conveying "guided" or "homing" behavior.
Uses cyan/teal sci-fi color palette with subtle glow effects.

Issue #677: Add homing bullets as an active item.
"""

from PIL import Image, ImageDraw

# --- Color palette ---
TRANSPARENT = (0, 0, 0, 0)

# Bullet body - metallic cyan/teal tones
BULLET_TIP = (180, 230, 240, 255)       # Bright cyan tip highlight
BULLET_BODY = (50, 180, 200, 255)       # Main teal body
BULLET_BODY_DARK = (30, 130, 155, 255)  # Darker teal for shading
BULLET_BASE = (35, 100, 125, 255)       # Dark teal base
BULLET_HIGHLIGHT = (210, 250, 255, 255) # Near-white specular highlight

# Casing - brass/copper tones
CASING = (180, 140, 60, 255)
CASING_DARK = (140, 105, 40, 255)
CASING_HIGHLIGHT = (210, 175, 90, 255)

# Trail / motion lines - cyan glow
TRAIL_BRIGHT = (0, 220, 255, 200)
TRAIL_MID = (0, 180, 220, 140)
TRAIL_DIM = (0, 140, 180, 80)
TRAIL_FAINT = (0, 100, 140, 40)

# Crosshair / target
CROSSHAIR = (255, 80, 80, 220)          # Red-orange crosshair
CROSSHAIR_DIM = (255, 80, 80, 120)      # Dimmer crosshair

# Glow around bullet
GLOW_BRIGHT = (0, 200, 240, 60)
GLOW_DIM = (0, 160, 200, 30)

# Outline
OUTLINE = (15, 60, 80, 255)


def put(img, x, y, color):
    """Safe pixel placement within bounds."""
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), color)


def blend_pixel(img, x, y, color):
    """Blend a color onto an existing pixel (simple alpha over)."""
    if not (0 <= x < img.width and 0 <= y < img.height):
        return
    r2, g2, b2, a2 = color
    if a2 == 0:
        return
    existing = img.getpixel((x, y))
    r1, g1, b1, a1 = existing
    if a1 == 0:
        img.putpixel((x, y), color)
        return
    # Simple alpha blend
    af = a2 / 255.0
    r = int(r1 * (1 - af) + r2 * af)
    g = int(g1 * (1 - af) + g2 * af)
    b = int(b1 * (1 - af) + b2 * af)
    a = min(255, a1 + a2)
    img.putpixel((x, y), (r, g, b, a))


def draw_bullet(img, bx, by):
    """
    Draw a stylized bullet pointing to the upper-right.
    bx, by is the approximate center of the bullet body.

    Bullet structure (pointing right):
    - Pointed tip on the right
    - Cylindrical body (teal/cyan)
    - Brass casing on the left
    """
    # --- Casing (left portion) - brass colored ---
    for dy in range(-2, 3):
        put(img, bx - 7, by + dy, OUTLINE)
        put(img, bx - 6, by + dy, CASING_DARK)
        put(img, bx - 5, by + dy, CASING)
        put(img, bx - 4, by + dy, CASING)
        put(img, bx - 3, by + dy, CASING_HIGHLIGHT if dy <= -1 else CASING)
    # Casing top/bottom outline
    for dx in range(-7, -2):
        put(img, bx + dx, by - 3, OUTLINE)
        put(img, bx + dx, by + 3, OUTLINE)

    # Neck / crimp between casing and bullet
    for dy in range(-2, 3):
        put(img, bx - 2, by + dy, OUTLINE)
    for dy in range(-1, 2):
        put(img, bx - 2, by + dy, BULLET_BASE)

    # Bullet body (main cylinder) - teal/cyan, ~7px wide
    for dx in range(-1, 6):
        for dy in range(-2, 3):
            put(img, bx + dx, by + dy, OUTLINE)
        for dy in range(-1, 2):
            if dy == -1:
                c = BULLET_TIP  # top highlight
            elif dy == 0:
                c = BULLET_BODY
            else:
                c = BULLET_BODY_DARK  # bottom shadow
            put(img, bx + dx, by + dy, c)

    # Top and bottom outline of body
    for dx in range(-1, 6):
        put(img, bx + dx, by - 2, OUTLINE)
        put(img, bx + dx, by + 2, OUTLINE)

    # Specular highlight line along top of bullet
    for dx in range(0, 5):
        put(img, bx + dx, by - 1, BULLET_HIGHLIGHT)

    # Bullet tip (pointed) - narrowing to a point
    for dy in range(-1, 2):
        put(img, bx + 6, by + dy, BULLET_BODY if dy >= 0 else BULLET_TIP)
    put(img, bx + 6, by - 2, OUTLINE)
    put(img, bx + 6, by + 2, OUTLINE)

    put(img, bx + 7, by - 1, BULLET_TIP)
    put(img, bx + 7, by + 0, BULLET_BODY)
    put(img, bx + 7, by + 1, OUTLINE)
    put(img, bx + 7, by - 2, OUTLINE)

    put(img, bx + 8, by - 1, OUTLINE)
    put(img, bx + 8, by + 0, BULLET_TIP)

    put(img, bx + 9, by + 0, OUTLINE)

    # --- Glow effect around bullet ---
    glow_positions_bright = [
        (-1, -3), (0, -3), (1, -3), (2, -3), (3, -3), (4, -3),
        (-1, 3), (0, 3), (1, 3), (2, 3), (3, 3), (4, 3),
        (7, -1), (7, 1),
        (-8, -1), (-8, 0), (-8, 1),
    ]
    glow_positions_dim = [
        (-2, -4), (5, -4), (-2, 4), (5, 4),
        (8, -1), (8, 1), (9, -1), (9, 1),
        (-9, 0), (-9, -1), (-9, 1),
        (0, -4), (1, -4), (2, -4), (3, -4),
        (0, 4), (1, 4), (2, 4), (3, 4),
    ]
    for dx, dy in glow_positions_bright:
        blend_pixel(img, bx + dx, by + dy, GLOW_BRIGHT)
    for dx, dy in glow_positions_dim:
        blend_pixel(img, bx + dx, by + dy, GLOW_DIM)


def draw_curved_trail(img, bx, by):
    """
    Draw curved motion trail lines behind the bullet to suggest homing/curving.
    The trails curve upward from the lower-left, showing the bullet changed direction.
    """
    # Trail 1: Main curved trail (stronger)
    trail1_pixels = [
        (-22, 12, TRAIL_FAINT),
        (-21, 11, TRAIL_FAINT),
        (-20, 10, TRAIL_DIM),
        (-19, 9, TRAIL_DIM),
        (-18, 8, TRAIL_DIM),
        (-17, 7, TRAIL_MID),
        (-16, 6, TRAIL_MID),
        (-15, 5, TRAIL_MID),
        (-14, 4, TRAIL_MID),
        (-13, 3, TRAIL_BRIGHT),
        (-12, 3, TRAIL_BRIGHT),
        (-11, 2, TRAIL_BRIGHT),
        (-10, 1, TRAIL_BRIGHT),
        (-9, 1, TRAIL_BRIGHT),
    ]

    for dx, dy, color in trail1_pixels:
        blend_pixel(img, bx + dx, by + dy, color)
        # Make trail 2px wide at the brighter parts
        if color in (TRAIL_BRIGHT, TRAIL_MID):
            blend_pixel(img, bx + dx, by + dy + 1,
                        (color[0], color[1], color[2], color[3] // 2))

    # Trail 2: Secondary trail (thinner, dimmer, offset)
    trail2_pixels = [
        (-20, 14, TRAIL_FAINT),
        (-19, 13, TRAIL_FAINT),
        (-18, 12, TRAIL_FAINT),
        (-17, 11, TRAIL_DIM),
        (-16, 10, TRAIL_DIM),
        (-15, 9, TRAIL_DIM),
        (-14, 8, TRAIL_DIM),
        (-13, 7, TRAIL_MID),
        (-12, 6, TRAIL_MID),
        (-11, 5, TRAIL_MID),
        (-10, 4, TRAIL_MID),
        (-9, 3, TRAIL_MID),
    ]

    for dx, dy, color in trail2_pixels:
        blend_pixel(img, bx + dx, by + dy,
                    (color[0], color[1], color[2], color[3] // 2))


def draw_crosshair(img, cx, cy):
    """
    Draw a small crosshair/target reticle near the bullet's path.
    Placed ahead and slightly above the bullet to show where it is homing toward.
    """
    # Outer ring (diamond shape at this scale)
    ring_pixels = [
        (0, -3), (1, -3),
        (-2, -2), (3, -2),
        (-3, -1), (4, -1),
        (-3, 0), (4, 0),
        (-3, 1), (4, 1),
        (-2, 2), (3, 2),
        (0, 3), (1, 3),
    ]
    for dx, dy in ring_pixels:
        put(img, cx + dx, cy + dy, CROSSHAIR)

    # Center dot
    put(img, cx, cy, CROSSHAIR)
    put(img, cx + 1, cy, CROSSHAIR)

    # Dim extensions of cross lines
    dim_pixels = [
        (0, -5), (1, -5), (0, -4), (1, -4),  # top
        (0, 4), (1, 4), (0, 5), (1, 5),       # bottom
        (-5, 0), (-4, 0),                       # left
        (5, 0), (6, 0),                         # right
    ]
    for dx, dy in dim_pixels:
        blend_pixel(img, cx + dx, cy + dy, CROSSHAIR_DIM)


def draw_small_sparkles(img, bx, by):
    """Draw small sparkle/energy dots around the bullet to suggest active guidance."""
    sparkles = [
        (bx + 3, by - 5, (100, 240, 255, 160)),
        (bx - 4, by + 5, (80, 220, 240, 120)),
        (bx + 10, by - 3, (120, 255, 255, 100)),
        (bx - 12, by + 7, (60, 200, 230, 80)),
        (bx + 6, by + 5, (100, 240, 255, 100)),
    ]
    for sx, sy, color in sparkles:
        blend_pixel(img, sx, sy, color)


def generate_homing_bullets_icon():
    """Generate the complete homing bullets icon."""
    width, height = 64, 48
    img = Image.new('RGBA', (width, height), TRANSPARENT)

    # Position the bullet in the upper-right area, pointing right.
    # This leaves room for the curved trail below-left.
    bullet_x = 30
    bullet_y = 17

    # Draw elements back-to-front
    draw_curved_trail(img, bullet_x, bullet_y)
    draw_bullet(img, bullet_x, bullet_y)
    draw_small_sparkles(img, bullet_x, bullet_y)

    # Draw crosshair ahead and slightly above the bullet
    crosshair_x = 52
    crosshair_y = 10
    draw_crosshair(img, crosshair_x, crosshair_y)

    # Draw a faint dotted line from bullet tip to crosshair (guidance beam)
    beam_points = [
        (40, 15), (42, 14), (44, 13), (46, 12), (48, 11),
    ]
    for bpx, bpy in beam_points:
        blend_pixel(img, bpx, bpy, TRAIL_DIM)

    return img


def main():
    img = generate_homing_bullets_icon()

    # Save to the weapons sprites directory
    output_path = '/tmp/gh-issue-solver-1770592188637/assets/sprites/weapons/homing_bullets_icon.png'
    img.save(output_path)
    print(f"Saved homing bullets icon to: {output_path}")
    print(f"Size: {img.size}, Mode: {img.mode}")

    # Also save a copy in experiments for reference
    exp_path = '/tmp/gh-issue-solver-1770592188637/experiments/homing_bullets_icon.png'
    img.save(exp_path)
    print(f"Also saved to: {exp_path}")


if __name__ == '__main__':
    main()
