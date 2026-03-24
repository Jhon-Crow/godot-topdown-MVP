"""
Generate a screenshot mockup of the pause menu with updated icons.
Uses PIL/Pillow to draw the menu similar to the actual game appearance.
"""
from PIL import Image, ImageDraw, ImageFont
import math
import os

# Canvas size
W, H = 800, 600
BG_COLOR = (5, 0, 10)  # nearly black with slight purple tint
BUTTON_BG = (20, 5, 25)  # dark purple-black
BUTTON_BORDER = (200, 20, 80)  # pink/magenta border
TEXT_COLOR = (230, 150, 180)  # pink-ish text
ICON_COLOR = (230, 150, 180)  # same as text
TITLE_COLOR = (255, 100, 180)  # brighter pink for title

img = Image.new("RGB", (W, H), BG_COLOR)
draw = ImageDraw.Draw(img)

# Title
title_x, title_y = W // 2, 60
# Draw "PAUSED" with glow effect
for glow_offset in [(2, 2), (-2, 2), (2, -2), (-2, -2), (0, 2), (2, 0)]:
    draw.text((title_x + glow_offset[0], title_y + glow_offset[1]),
              "P A U S E D", fill=(120, 0, 60), anchor="mm",
              font=ImageFont.load_default(size=36))
draw.text((title_x, title_y), "P A U S E D", fill=TITLE_COLOR, anchor="mm",
          font=ImageFont.load_default(size=36))

# Button dimensions
btn_w, btn_h = 220, 44
btn_x = W // 2 - btn_w // 2
buttons = [
    ("Resume", "resume"),
    ("Armory", "armory"),
    ("Levels", "levels"),
    ("Training", "training"),
    ("Рогалик", "roguelike"),
    ("Arena", "arena"),
    ("Settings", "settings"),
    ("Quit", "quit"),
]

start_y = 110
spacing = 56

def draw_rounded_rect(draw, x, y, w, h, r, fill, outline, outline_width=1):
    """Draw a rounded rectangle."""
    draw.rounded_rectangle([x, y, x + w, y + h], radius=r, fill=fill, outline=outline, width=outline_width)

def draw_resume_icon(draw, cx, cy, size, color):
    """Play triangle ▶"""
    s = size // 2
    pts = [(cx - s + 2, cy - s), (cx - s + 2, cy + s), (cx + s, cy)]
    draw.polygon(pts, fill=color)

def draw_armory_icon(draw, cx, cy, size, color):
    """Crossed swords with guards near hilts (far from crossing)"""
    s = size
    lw = 2
    # Blade 1: top-left to bottom-right
    # Scale from 32x32 space to size*2 x size*2 around center
    def scale(v, from_range=32):
        return (v / from_range - 0.5) * size * 2

    def pt(x, y):
        return (cx + scale(x), cy + scale(y))

    # Blade 1: (4,4) -> (28,28)
    draw.line([pt(4, 4), pt(28, 28)], fill=color, width=lw)
    # Guard 1: (20,26)-(26,20)
    draw.line([pt(20, 26), pt(26, 20)], fill=color, width=3)
    # Hilt 1
    draw.line([pt(27, 29), pt(24, 26)], fill=color, width=3)

    # Blade 2: (28,4) -> (4,28)
    draw.line([pt(28, 4), pt(4, 28)], fill=color, width=lw)
    # Guard 2: (12,26)-(6,20)
    draw.line([pt(12, 26), pt(6, 20)], fill=color, width=3)
    # Hilt 2
    draw.line([pt(5, 29), pt(8, 26)], fill=color, width=3)

def draw_levels_icon(draw, cx, cy, size, color):
    """Map with location pin 🗺"""
    s = size - 2
    # Book/map outline
    draw.rectangle([cx - s, cy - s + 2, cx + s, cy + s], outline=color, width=2)
    # Fold line
    draw.line([cx, cy - s + 2, cx, cy + s], fill=color, width=1)
    # Pin dot
    draw.ellipse([cx - 2, cy - 3, cx + 2, cy + 1], fill=color)

def draw_training_icon(draw, cx, cy, size, color):
    """Target/crosshair 🎯"""
    for r in [size, size - 4, size - 8]:
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=1)
    draw.line([cx - size, cy, cx + size, cy], fill=color, width=1)
    draw.line([cx, cy - size, cx, cy + size], fill=color, width=1)

def draw_roguelike_icon(draw, cx, cy, size, color):
    """Dice 🎲"""
    s = size - 1
    draw.rectangle([cx - s, cy - s, cx + s, cy + s], outline=color, width=2)
    dot_r = 2
    for dx, dy in [(-4, -4), (0, 0), (4, 4), (-4, 4), (4, -4)]:
        draw.ellipse([cx + dx - dot_r, cy + dy - dot_r, cx + dx + dot_r, cy + dy + dot_r], fill=color)

def draw_arena_icon(draw, cx, cy, size, color):
    """Shield with star 🛡"""
    s = size
    # Shield shape
    pts = [(cx, cy - s), (cx + s, cy - s + 4), (cx + s, cy + 2), (cx, cy + s), (cx - s, cy + 2), (cx - s, cy - s + 4)]
    draw.polygon(pts, outline=color, width=2)
    # Star
    draw.text((cx, cy - 2), "★", fill=color, anchor="mm", font=ImageFont.load_default(size=10))

def draw_settings_icon(draw, cx, cy, size, color):
    """Gear with 6 rounded teeth ⚙"""
    inner_r = size * 9 / 14
    outer_r = size
    n_teeth = 6
    tooth_half_deg = 15

    def to_rad(d):
        return d * math.pi / 180

    # Build gear path
    tooth_centers_math = [90, 30, -30, -90, -150, -210]

    # Collect all polygon points
    pts = []
    for i in range(n_teeth):
        tc = tooth_centers_math[i]
        leading = tc + tooth_half_deg
        trailing = tc - tooth_half_deg
        next_tc = tooth_centers_math[(i + 1) % n_teeth]
        next_leading = next_tc + tooth_half_deg

        # Outer arc approximation (just use 3 points for the arc)
        mid_angle = (leading + trailing) / 2
        pts.append((cx + outer_r * math.cos(to_rad(leading)), cy - outer_r * math.sin(to_rad(leading))))
        pts.append((cx + outer_r * math.cos(to_rad(mid_angle)), cy - outer_r * math.sin(to_rad(mid_angle))))
        pts.append((cx + outer_r * math.cos(to_rad(trailing)), cy - outer_r * math.sin(to_rad(trailing))))

        # Inner valley arc
        v_mid = (trailing + next_leading) / 2
        pts.append((cx + inner_r * math.cos(to_rad(trailing)), cy - inner_r * math.sin(to_rad(trailing))))
        pts.append((cx + inner_r * math.cos(to_rad(v_mid)), cy - inner_r * math.sin(to_rad(v_mid))))
        pts.append((cx + inner_r * math.cos(to_rad(next_leading)), cy - inner_r * math.sin(to_rad(next_leading))))

    draw.polygon(pts, fill=color)
    # Center hole
    hole_r = size * 5 / 14
    draw.ellipse([cx - hole_r, cy - hole_r, cx + hole_r, cy + hole_r], fill=BG_COLOR)

def draw_quit_icon(draw, cx, cy, size, color):
    """Power button ⏻"""
    # Circle with gap at top
    draw.arc([cx - size, cy - size, cx + size, cy + size], start=40, end=320, fill=color, width=2)
    # Vertical line at top
    draw.line([cx, cy - size - 1, cx, cy - size // 2 + 1], fill=color, width=2)

icon_funcs = {
    "resume": draw_resume_icon,
    "armory": draw_armory_icon,
    "levels": draw_levels_icon,
    "training": draw_training_icon,
    "roguelike": draw_roguelike_icon,
    "arena": draw_arena_icon,
    "settings": draw_settings_icon,
    "quit": draw_quit_icon,
}

for i, (label, icon_key) in enumerate(buttons):
    y = start_y + i * spacing
    # Draw button background
    draw_rounded_rect(draw, btn_x, y, btn_w, btn_h, r=6,
                      fill=BUTTON_BG, outline=BUTTON_BORDER, outline_width=1)

    # Icon position
    icon_cx = btn_x + 24
    icon_cy = y + btn_h // 2
    icon_size = 10

    if icon_key in icon_funcs:
        icon_funcs[icon_key](draw, icon_cx, icon_cy, icon_size, ICON_COLOR)

    # Label
    draw.text((btn_x + 46, y + btn_h // 2), label, fill=TEXT_COLOR,
              anchor="lm", font=ImageFont.load_default(size=18))

# Save
out_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        "docs", "screenshots", "pause_menu_with_icons.png")
img.save(out_path)
print(f"Screenshot saved to: {out_path}")
