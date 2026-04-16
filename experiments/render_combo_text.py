#!/usr/bin/env python3
"""
Renders the combo counter text using the actual gothic_bitmap.fnt and gothic_bitmap.png,
simulating how it looks in-game after the font change.
"""

from PIL import Image, ImageDraw, ImageFont
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
    """Extract a single character glyph from the font sheet."""
    if char_id not in chars:
        return None, 0
    c = chars[char_id]
    if c['width'] == 0 or c['height'] == 0:
        return None, c['xadvance']
    glyph = sheet.crop((c['x'], c['y'], c['x'] + c['width'], c['y'] + c['height']))
    return glyph, c

def render_text_gothic(text, scale=0.4):
    """Render text using the gothic bitmap font glyphs."""
    # Compute total width first
    total_w = 0
    max_h = 151  # lineHeight from fnt

    glyph_data = []
    for ch in text:
        cid = ord(ch)
        glyph, cdata = get_char_glyph(cid)
        glyph_data.append((cid, glyph, cdata))
        if glyph is not None:
            total_w += cdata['xadvance']
        elif isinstance(cdata, int):  # space
            total_w += cdata
        else:
            total_w += 30

    scaled_w = int(total_w * scale) + 10
    scaled_h = int(max_h * scale) + 10

    # White glyphs on dark background
    img = Image.new('RGBA', (scaled_w, scaled_h), (30, 30, 30, 255))

    x_cursor = 5
    for cid, glyph, cdata in glyph_data:
        if glyph is None:
            if isinstance(cdata, int):
                x_cursor += int(cdata * scale)
            else:
                x_cursor += int(30 * scale)
            continue

        yoffset = cdata['yoffset']
        y_pos = int((yoffset) * scale) + 5
        gw = int(cdata['width'] * scale)
        gh = int(cdata['height'] * scale)

        if gw > 0 and gh > 0:
            resized = glyph.resize((gw, gh), Image.LANCZOS)
            img.paste(resized, (x_cursor, y_pos), resized)

        x_cursor += int(cdata['xadvance'] * scale)

    return img

# --- Build the combo UI screenshot ---
# Simulate game UI: dark background, combo text in gothic
bg_w, bg_h = 600, 180
bg = Image.new('RGBA', (bg_w, bg_h), (20, 20, 20, 255))

# Render "x3 COMBO" at the top
combo_text = "x3 COMBO"
combo_img = render_text_gothic(combo_text, scale=0.5)

# Render "(+150)" smaller below
bonus_text = "+150"
bonus_img = render_text_gothic(bonus_text, scale=0.35)

# Center combo text horizontally
cx = (bg_w - combo_img.width) // 2
bg.paste(combo_img, (cx, 20), combo_img)

# Center bonus text below
bx = (bg_w - bonus_img.width) // 2
bg.paste(bonus_img, (bx, 20 + combo_img.height + 10), bonus_img)

# Add a label note at bottom
draw = ImageDraw.Draw(bg)
note = "Combo counter in Gothic bitmap font"
draw.text((bg_w // 2, bg_h - 18), note, fill=(180, 180, 180, 200), anchor='mm')

# Save
out_path = os.path.join(os.path.dirname(__file__), '..', 'docs', 'screenshots', 'combo_gothic_font.png')
bg.save(out_path)
print(f"Saved: {out_path}")
print(f"Combo img size: {combo_img.size}")
print(f"Bonus img size: {bonus_img.size}")
