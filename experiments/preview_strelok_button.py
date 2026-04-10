#!/usr/bin/env python3
"""
Creates a preview screenshot of the Strelok difficulty button with:
- Glowing red background
- Cowboy-style font text "Стрелок"
This simulates what the button will look like in Godot.
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

OUTPUT_PATH = "/tmp/gh-issue-solver-1775844437743/docs/screenshots/strelok_button_preview.png"
os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)

# Simulate the difficulty menu panel
PANEL_W = 320
PANEL_H = 560
IMG_W = PANEL_W + 40
IMG_H = PANEL_H + 40

# Colors
BG_COLOR = (15, 15, 25)        # Dark blue-black menu background
PANEL_BG = (20, 20, 35)        # Panel background
PANEL_BORDER = (60, 120, 200)  # Neon blue border (neon theme)

# Button dimensions
BTN_W = 260
BTN_H = 44
BTN_X = (PANEL_W - BTN_W) // 2 + 20  # Centered in panel
MARGIN_LEFT = 40

def draw_glow(draw, x, y, w, h, glow_color, glow_size=8):
    """Draw a glowing effect around a rectangle."""
    for i in range(glow_size, 0, -1):
        alpha = int(200 * (i / glow_size))
        r, g, b = glow_color
        draw.rounded_rectangle(
            [x - i, y - i, x + w + i, y + h + i],
            radius=4 + i,
            outline=(r, g, b, alpha)
        )

def draw_button(draw, x, y, w, h, bg_color, text, font, text_color, glow_color=None, glow_size=0):
    """Draw a styled button."""
    # Draw glow layers if needed
    if glow_color and glow_size > 0:
        for i in range(glow_size, 0, -1):
            alpha = int(180 * (i / glow_size) ** 0.7)
            r, g, b = glow_color
            draw.rounded_rectangle(
                [x - i*2, y - i, x + w + i*2, y + h + i],
                radius=6,
                fill=(r, g, b, min(60, alpha))
            )

    # Draw button background
    draw.rounded_rectangle([x, y, x + w, y + h], radius=4, fill=bg_color)
    
    # Draw button text (centered)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = x + (w - tw) // 2 - bbox[0]
    ty = y + (h - th) // 2 - bbox[1]
    draw.text((tx, ty), text, font=font, fill=text_color)

# Load fonts
serif_bold_path = "/usr/share/fonts/truetype/freefont/FreeSerifBold.ttf"
serif_path = "/usr/share/fonts/truetype/freefont/FreeSerif.ttf"

try:
    font_cowboy = ImageFont.truetype(serif_bold_path, 20)
    font_regular = ImageFont.truetype(serif_path, 16)
    font_title = ImageFont.truetype(serif_bold_path, 22)
    font_small = ImageFont.truetype(serif_path, 13)
except Exception as e:
    print(f"Font loading error: {e}")
    font_cowboy = ImageFont.load_default()
    font_regular = font_cowboy
    font_title = font_cowboy
    font_small = font_cowboy

# Create image with RGBA for glow effects
img = Image.new('RGBA', (IMG_W, IMG_H), (0, 0, 0, 0))
draw = ImageDraw.Draw(img, 'RGBA')

# Draw background
draw.rectangle([0, 0, IMG_W, IMG_H], fill=BG_COLOR)

# Draw panel
px, py = 20, 20
draw.rounded_rectangle([px, py, px + PANEL_W, py + PANEL_H], radius=8, fill=PANEL_BG)
draw.rounded_rectangle([px, py, px + PANEL_W, py + PANEL_H], radius=8, outline=PANEL_BORDER, width=2)

# Title: "Difficulty"
title_text = "Difficulty"
tbbox = draw.textbbox((0, 0), title_text, font=font_title)
tw = tbbox[2] - tbbox[0]
draw.text((px + (PANEL_W - tw) // 2, py + 20), title_text, font=font_title, fill=(100, 200, 255))

# Night Mode row
draw.text((px + 20, py + 65), "Night Mode", font=font_regular, fill=(200, 200, 200))
draw.rounded_rectangle([px + PANEL_W - 60, py + 65, px + PANEL_W - 20, py + 87], radius=10, outline=(100, 200, 255), width=2)

# Separator line
draw.line([px + 15, py + 100, px + PANEL_W - 15, py + 100], fill=(60, 80, 120), width=1)

# Button Y positions
buttons_y_start = py + 115
btn_spacing = BTN_H + 12
btn_left = px + (PANEL_W - BTN_W) // 2

# Power Fantasy button (gradient-like simulation)
pf_y = buttons_y_start
draw.rounded_rectangle([btn_left, pf_y, btn_left + BTN_W, pf_y + BTN_H], radius=4, fill=(25, 25, 50))
# Gradient text simulation
pf_colors = [(0, 255, 255), (180, 0, 255), (255, 0, 255), (255, 140, 0), (255, 255, 0)]
pf_text = "Power Fantasy"
pf_bbox = draw.textbbox((0, 0), pf_text, font=font_regular)
pf_tw = pf_bbox[2] - pf_bbox[0]
pf_tx = btn_left + (BTN_W - pf_tw) // 2
pf_ty = pf_y + (BTN_H - (pf_bbox[3] - pf_bbox[1])) // 2 - pf_bbox[1]
# Draw each character with gradient color
for i, ch in enumerate(pf_text):
    t = i / max(len(pf_text) - 1, 1)
    seg = int(t * (len(pf_colors) - 1))
    seg = min(seg, len(pf_colors) - 2)
    st = (t * (len(pf_colors) - 1)) - seg
    c1, c2 = pf_colors[seg], pf_colors[seg + 1]
    c = tuple(int(c1[j] + (c2[j] - c1[j]) * st) for j in range(3))
    ch_bbox = draw.textbbox((0, 0), pf_text[:i], font=font_regular)
    ch_x = pf_tx + ch_bbox[2] - ch_bbox[0]
    draw.text((ch_x, pf_ty), ch, font=font_regular, fill=c)

# Стрелок button - GLOWING RED BACKGROUND (the main feature of this issue)
st_y = buttons_y_start + btn_spacing

# Draw glow layers (multiple passes with decreasing alpha)
glow_r, glow_g, glow_b = 255, 30, 30
for gi in range(12, 0, -1):
    alpha = int(120 * (gi / 12) ** 0.6)
    expand = gi * 2
    draw.rounded_rectangle(
        [btn_left - expand, st_y - expand//2, btn_left + BTN_W + expand, st_y + BTN_H + expand//2],
        radius=6 + expand//2,
        fill=(glow_r, glow_g, glow_b, min(alpha, 80))
    )

# Draw the main red button
draw.rounded_rectangle(
    [btn_left, st_y, btn_left + BTN_W, st_y + BTN_H],
    radius=4,
    fill=(140, 5, 5)
)
# Button border highlight
draw.rounded_rectangle(
    [btn_left, st_y, btn_left + BTN_W, st_y + BTN_H],
    radius=4,
    outline=(220, 40, 40),
    width=1
)

# Cowboy-style amber/gold text
st_text = "Стрелок"
st_bbox = draw.textbbox((0, 0), st_text, font=font_cowboy)
st_tw = st_bbox[2] - st_bbox[0]
st_tx = btn_left + (BTN_W - st_tw) // 2 - st_bbox[0]
st_ty = st_y + (BTN_H - (st_bbox[3] - st_bbox[1])) // 2 - st_bbox[1]
# Draw slight text shadow for depth
draw.text((st_tx + 1, st_ty + 1), st_text, font=font_cowboy, fill=(80, 20, 0, 150))
draw.text((st_tx, st_ty), st_text, font=font_cowboy, fill=(255, 220, 100))

# Easy button
ez_y = buttons_y_start + btn_spacing * 2
draw.rounded_rectangle([btn_left, ez_y, btn_left + BTN_W, ez_y + BTN_H], radius=4, fill=(25, 25, 50))
draw.text((btn_left + BTN_W//2 - 20, ez_y + 12), "Easy", font=font_regular, fill=(200, 200, 200))

# Normal button (selected - disabled state) 
nm_y = buttons_y_start + btn_spacing * 3
draw.rounded_rectangle([btn_left, nm_y, btn_left + BTN_W, nm_y + BTN_H], radius=4, fill=(30, 40, 30))
draw.text((btn_left + BTN_W//2 - 55, nm_y + 12), "Normal (Selected)", font=font_regular, fill=(160, 220, 160))

# Hard button
hd_y = buttons_y_start + btn_spacing * 4
draw.rounded_rectangle([btn_left, hd_y, btn_left + BTN_W, hd_y + BTN_H], radius=4, fill=(25, 25, 50))
draw.text((btn_left + BTN_W//2 - 20, hd_y + 12), "Hard", font=font_regular, fill=(200, 200, 200))

# Black Metal button
bm_y = buttons_y_start + btn_spacing * 5
draw.rounded_rectangle([btn_left, bm_y, btn_left + BTN_W, bm_y + BTN_H], radius=4, fill=(10, 10, 10))
draw.text((btn_left + BTN_W//2 - 50, bm_y + 12), "BLACK METAL", font=font_regular, fill=(200, 200, 200))

# Status label
sl_y = buttons_y_start + btn_spacing * 6 + 5
draw.text((px + 30, sl_y), "Normal mode: Classic gameplay", font=font_small, fill=(150, 150, 150))

# Back button
bk_y = buttons_y_start + btn_spacing * 6 + 35
draw.rounded_rectangle([btn_left, bk_y, btn_left + BTN_W, bk_y + BTN_H], radius=4, fill=(25, 25, 50))
draw.text((btn_left + BTN_W//2 - 20, bk_y + 12), "Back", font=font_regular, fill=(200, 200, 200))

# Add label annotations
ann_x = btn_left + BTN_W + 15
ann_y_strelok = st_y + BTN_H // 2 - 10
draw.line([btn_left + BTN_W, st_y + BTN_H//2, ann_x - 5, ann_y_strelok + 10], fill=(255, 200, 0), width=1)
draw.text((ann_x, ann_y_strelok), "← Glowing red bg\n   + Cowboy font", font=font_small, fill=(255, 220, 100))

# Save to docs/screenshots
img_rgb = img.convert('RGB')
img_rgb.save(OUTPUT_PATH)
print(f"Saved preview: {OUTPUT_PATH}")
print(f"Image size: {IMG_W}x{IMG_H}")
