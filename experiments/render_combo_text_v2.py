#!/usr/bin/env python3
"""
Renders the combo counter text using the actual gothic_bitmap.fnt and gothic_bitmap.png,
simulating how it looks in-game after the font change.
"""

from PIL import Image, ImageDraw, ImageFilter
import os

# Load the gothic bitmap font sheet
FONT_DIR = os.path.join(os.path.dirname(__file__), '..', 'assets', 'fonts')
sheet = Image.open(os.path.join(FONT_DIR, 'gothic_bitmap.png')).convert('RGBA')

# Parse the .fnt file
fnt_path = os.path.join(FONT_DIR, 'gothic_bitmap.fnt')
chars = {}
with open(fnt_path) as f:
    for line in f:
        if line.startswith('char '):
            parts = {}
            for token in line.split():
                if '=' in token:
                    k, v = token.split('=', 1)
                    parts[k] = int(v)
            if 'id' in parts:
                chars[parts['id']] = parts

def get_char_glyph(char_id):
    if char_id not in chars:
        return None, None
    c = chars[char_id]
    if c['width'] == 0 or c['height'] == 0:
        return None, c
    glyph = sheet.crop((c['x'], c['y'], c['x'] + c['width'], c['y'] + c['height']))
    return glyph, c

def render_text_gothic(text, scale=0.4, color=(255, 255, 255)):
    """Render text using the gothic bitmap font glyphs, returns RGBA image."""
    max_h = 151  # lineHeight from fnt

    # First pass: compute width
    total_w = 0
    glyph_data = []
    for ch in text:
        cid = ord(ch)
        glyph, cdata = get_char_glyph(cid)
        glyph_data.append((cid, glyph, cdata))
        if cdata is not None:
            total_w += cdata['xadvance']
        else:
            total_w += 30

    scaled_w = int(total_w * scale) + 4
    scaled_h = int(max_h * scale) + 4

    # Transparent background for compositing
    img = Image.new('RGBA', (scaled_w, scaled_h), (0, 0, 0, 0))

    x_cursor = 2
    for cid, glyph, cdata in glyph_data:
        if cdata is None:
            x_cursor += int(30 * scale)
            continue
        if glyph is None:
            x_cursor += int(cdata['xadvance'] * scale)
            continue

        yoffset = cdata['yoffset']
        y_pos = int(yoffset * scale) + 2
        gw = int(cdata['width'] * scale)
        gh = int(cdata['height'] * scale)

        if gw > 0 and gh > 0:
            resized = glyph.resize((gw, gh), Image.LANCZOS)
            # Tint the glyph with desired color
            r_ch, g_ch, b_ch, a_ch = resized.split()
            tinted = Image.merge('RGBA', (
                a_ch.point(lambda p: p * color[0] // 255),
                a_ch.point(lambda p: p * color[1] // 255),
                a_ch.point(lambda p: p * color[2] // 255),
                a_ch
            ))
            img.paste(tinted, (x_cursor, y_pos), tinted)

        x_cursor += int(cdata['xadvance'] * scale)

    return img


# --- Build the combo UI screenshot ---
# Simulates a game HUD panel with combo text
bg_w, bg_h = 620, 220
bg = Image.new('RGBA', (bg_w, bg_h), (15, 12, 20, 255))

# Subtle gradient overlay (vignette-like)
draw = ImageDraw.Draw(bg)
for i in range(bg_h // 2):
    alpha = int(40 * (1 - i / (bg_h // 2)))
    draw.line([(0, i), (bg_w, i)], fill=(60, 40, 80, alpha))
    draw.line([(0, bg_h - 1 - i), (bg_w, bg_h - 1 - i)], fill=(30, 20, 40, alpha))

# Render "x3 COMBO" - yellow-ish game text color
combo_text = "x3 COMBO"
combo_img = render_text_gothic(combo_text, scale=0.55, color=(255, 220, 80))

# Render "+150" in slightly smaller size, greenish
bonus_text = "+150"
bonus_img = render_text_gothic(bonus_text, scale=0.38, color=(120, 255, 120))

# Place combo text centered, vertically upper portion
cx = (bg_w - combo_img.width) // 2
cy = 30
bg.paste(combo_img, (cx, cy), combo_img)

# Place bonus text centered, just below combo
bx = (bg_w - bonus_img.width) // 2
by = cy + combo_img.height + 5
bg.paste(bonus_img, (bx, by), bonus_img)

# Decorative border lines
draw = ImageDraw.Draw(bg)
border_color = (120, 90, 160, 180)
draw.rectangle([(10, 10), (bg_w - 10, bg_h - 10)], outline=border_color, width=2)

# Caption text using a fallback font
try:
    from PIL import ImageFont
    fnt = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
except Exception:
    fnt = ImageFont.load_default()

caption = "Combo counter — Gothic bitmap font applied"
draw.text((bg_w // 2, bg_h - 22), caption, fill=(180, 160, 200, 220), anchor='mm', font=fnt)

# Save
out_path = os.path.join(os.path.dirname(__file__), '..', 'docs', 'screenshots', 'combo_gothic_font.png')
bg.save(out_path)
print(f"Saved: {out_path}")
