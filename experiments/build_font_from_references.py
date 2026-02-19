#!/usr/bin/env python3
"""Build Gothic font sprite sheet from reference letter images.

This script takes individual letter images provided by the user
and combines them into a BMFont-compatible sprite sheet.
"""

from PIL import Image, ImageDraw
import numpy as np
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)

# Reference images directory
REFERENCE_DIR = "/tmp/gh-issue-solver-1771528529067/reference_letters"
OUTPUT_DIR = os.path.join(PROJECT_DIR, "assets", "fonts")
EXPERIMENT_DIR = SCRIPT_DIR

# Mapping of letter numbers to characters (from analysis of images)
# letter_01 = A, letter_02 = B, ..., letter_26 = Z
LETTER_MAPPING = {
    'letter_01.png': 'A', 'letter_02.png': 'B', 'letter_03.png': 'C',
    'letter_04.png': 'D', 'letter_05.png': 'E', 'letter_06.png': 'F',
    'letter_07.png': 'G', 'letter_08.png': 'H', 'letter_09.png': 'I',
    'letter_10.png': 'J', 'letter_11.png': 'K', 'letter_12.png': 'L',
    'letter_13.png': 'M', 'letter_14.png': 'N', 'letter_15.png': 'O',
    'letter_16.png': 'P', 'letter_17.png': 'Q', 'letter_18.png': 'R',
    'letter_19.png': 'S', 'letter_20.png': 'T', 'letter_21.png': 'U',
    'letter_22.png': 'V', 'letter_23.png': 'W', 'letter_24.png': 'X',
    'letter_25.png': 'Y', 'letter_26.png': 'Z',
}

# Full character set we want to include
# A-Z (from reference images), 0-9 (from original source), special chars (from original source)
FULL_CHARSET = list("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:&?!-+x ")


def convert_to_white_on_alpha(img):
    """Convert an image to white pixels on transparent background.

    Takes any image (including those with checkered transparency pattern)
    and extracts pixel density to create white letters.

    The reference images have a checkered pattern background:
    - White pixels [255,255,255] = transparent
    - Gray pixels [204,204,204] = transparent (checkered pattern)
    - Dark pixels = ink (should become white with alpha)
    """
    img_rgb = img.convert('RGB')
    arr = np.array(img_rgb)

    # Calculate grayscale
    rgb = arr.astype(float)
    gray = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]

    # The checkered background has values around 204 and 255
    # Consider anything >= 200 as background (transparent)
    # Anything darker is ink
    background_threshold = 200

    # For pixels darker than threshold, calculate ink density
    # Map grayscale 0 (black) -> 255 (full opacity), 200 (light gray) -> 0 (transparent)
    ink = np.zeros_like(gray)
    dark_mask = gray < background_threshold
    # Linear mapping: 0 -> 255, background_threshold -> 0
    ink[dark_mask] = 255 * (1 - gray[dark_mask] / background_threshold)
    ink = np.clip(ink, 0, 255)

    # Create white-on-transparent result
    result = np.zeros((arr.shape[0], arr.shape[1], 4), dtype=np.uint8)
    result[:, :, 0] = 255  # R
    result[:, :, 1] = 255  # G
    result[:, :, 2] = 255  # B
    result[:, :, 3] = ink.astype(np.uint8)  # A = ink density

    return Image.fromarray(result)


def auto_trim_alpha(img_rgba, min_alpha=20):
    """Trim transparent borders from an RGBA image."""
    arr = np.array(img_rgba)
    alpha = arr[:, :, 3]
    rows = np.any(alpha >= min_alpha, axis=1)
    cols = np.any(alpha >= min_alpha, axis=0)
    if not rows.any() or not cols.any():
        return img_rgba
    y1, y2 = np.where(rows)[0][[0, -1]]
    x1, x2 = np.where(cols)[0][[0, -1]]
    return img_rgba.crop((x1, y1, x2 + 1, y2 + 1))


def load_original_font_chars():
    """Load digits and special characters from the original source."""
    from extract_gothic_font import INPUT_IMAGE, ROWS

    chars = {}
    if not os.path.exists(INPUT_IMAGE):
        print(f"Warning: Original source not found: {INPUT_IMAGE}")
        return chars

    img = Image.open(INPUT_IMAGE).convert('RGBA')

    # Get rows 4 and 5 (digits and special chars)
    for char_list, y1, y2, x_splits in ROWS[3:]:  # Skip first 3 rows (letters)
        for i, char in enumerate(char_list):
            cx1, cx2 = x_splits[i], x_splits[i + 1]
            crop = img.crop((cx1, y1, cx2, y2))

            # Convert to white-on-alpha
            crop_arr = np.array(crop)
            result = np.zeros_like(crop_arr)
            result[:, :, 0] = 255
            result[:, :, 1] = 255
            result[:, :, 2] = 255
            result[:, :, 3] = crop_arr[:, :, 3]
            glyph = Image.fromarray(result)
            glyph = auto_trim_alpha(glyph, min_alpha=20)

            chars[char] = glyph
            print(f"  Loaded original '{char}': {glyph.size[0]}x{glyph.size[1]}")

    return chars


def main():
    print("Building Gothic font from reference letter images...")
    print(f"Reference directory: {REFERENCE_DIR}")

    all_chars = []

    # Load reference letters (A-Z)
    print("\nLoading reference letters...")
    for filename, char in sorted(LETTER_MAPPING.items(), key=lambda x: x[1]):
        filepath = os.path.join(REFERENCE_DIR, filename)
        if not os.path.exists(filepath):
            print(f"  Warning: {filepath} not found, skipping {char}")
            continue

        img = Image.open(filepath)
        glyph = convert_to_white_on_alpha(img)
        glyph = auto_trim_alpha(glyph, min_alpha=20)

        all_chars.append({
            'char': char,
            'glyph': glyph,
            'width': glyph.size[0],
            'height': glyph.size[1],
        })
        print(f"  '{char}': {glyph.size[0]}x{glyph.size[1]} (from {filename})")

    # Load digits and special characters from original source
    print("\nLoading digits and special chars from original source...")
    original_chars = load_original_font_chars()

    for char in "0123456789:&?!-":
        if char in original_chars:
            glyph = original_chars[char]
            all_chars.append({
                'char': char,
                'glyph': glyph,
                'width': glyph.size[0],
                'height': glyph.size[1],
            })

    # Build sprite sheet
    max_w = max(c['width'] for c in all_chars)
    max_h = max(c['height'] for c in all_chars)
    print(f"\nMax glyph size: {max_w}x{max_h}")

    cell_padding = 2
    cell_w = max_w + cell_padding * 2
    cell_h = max_h + cell_padding * 2
    cols_per_row = 10

    # +3 for '+', ' ', 'x'
    total_glyphs = len(all_chars) + 3
    num_sheet_rows = (total_glyphs + cols_per_row - 1) // cols_per_row
    sheet_w = cols_per_row * cell_w
    sheet_h = num_sheet_rows * cell_h

    print(f"Sprite sheet: {sheet_w}x{sheet_h}, cell={cell_w}x{cell_h}")

    sheet = Image.new('RGBA', (sheet_w, sheet_h), (0, 0, 0, 0))
    fnt_chars = []

    for idx, c in enumerate(all_chars):
        row = idx // cols_per_row
        col = idx % cols_per_row

        dest_x = col * cell_w + cell_padding
        y_offset = (cell_h - cell_padding * 2) - c['height']
        dest_y = row * cell_h + cell_padding + y_offset

        sheet.paste(c['glyph'], (dest_x, dest_y), c['glyph'])

        fnt_chars.append({
            'id': ord(c['char']),
            'x': dest_x,
            'y': dest_y,
            'width': c['width'],
            'height': c['height'],
            'xoffset': 0,
            'yoffset': y_offset,
            'xadvance': c['width'] + 2,
            'page': 0,
            'chnl': 15
        })

    # Synthetic '+' character
    plus_idx = len(all_chars)
    plus_row = plus_idx // cols_per_row
    plus_col = plus_idx % cols_per_row
    plus_size = 30
    plus_thick = 6
    plus_img = Image.new('RGBA', (plus_size, plus_size), (0, 0, 0, 0))
    pd = ImageDraw.Draw(plus_img)
    pd.rectangle([2, plus_size // 2 - plus_thick // 2, plus_size - 2, plus_size // 2 + plus_thick // 2],
                  fill=(255, 255, 255, 255))
    pd.rectangle([plus_size // 2 - plus_thick // 2, 2, plus_size // 2 + plus_thick // 2, plus_size - 2],
                  fill=(255, 255, 255, 255))

    plus_dest_x = plus_col * cell_w + cell_padding
    plus_y_offset = (cell_h - cell_padding * 2) - plus_size
    plus_dest_y = plus_row * cell_h + cell_padding + plus_y_offset
    sheet.paste(plus_img, (plus_dest_x, plus_dest_y), plus_img)

    fnt_chars.append({
        'id': ord('+'),
        'x': plus_dest_x,
        'y': plus_dest_y,
        'width': plus_size,
        'height': plus_size,
        'xoffset': 0,
        'yoffset': plus_y_offset,
        'xadvance': plus_size + 2,
        'page': 0,
        'chnl': 15
    })

    # Space
    space_width = max_w // 3
    fnt_chars.append({
        'id': ord(' '),
        'x': 0,
        'y': 0,
        'width': 0,
        'height': 0,
        'xoffset': 0,
        'yoffset': 0,
        'xadvance': space_width,
        'page': 0,
        'chnl': 15
    })

    # Lowercase 'x' (scaled-down X)
    x_char = next((c for c in all_chars if c['char'] == 'X'), None)
    if x_char:
        x_scaled = x_char['glyph'].resize(
            (int(x_char['width'] * 0.7), int(x_char['height'] * 0.7)),
            Image.LANCZOS
        )
        x_idx = plus_idx + 2
        x_row = x_idx // cols_per_row
        x_col = x_idx % cols_per_row
        x_dest_x = x_col * cell_w + cell_padding
        x_y_offset = (cell_h - cell_padding * 2) - x_scaled.height
        x_dest_y = x_row * cell_h + cell_padding + x_y_offset
        sheet.paste(x_scaled, (x_dest_x, x_dest_y), x_scaled)

        fnt_chars.append({
            'id': ord('x'),
            'x': x_dest_x,
            'y': x_dest_y,
            'width': x_scaled.width,
            'height': x_scaled.height,
            'xoffset': 0,
            'yoffset': x_y_offset,
            'xadvance': x_scaled.width + 2,
            'page': 0,
            'chnl': 15
        })

    # Save sprite sheet
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    sheet_path = os.path.join(OUTPUT_DIR, "gothic_bitmap.png")
    sheet.save(sheet_path)
    print(f"\nSprite sheet saved: {sheet_path}")

    # Debug sheet with dark background
    debug_sheet = Image.new('RGBA', (sheet_w, sheet_h), (30, 30, 30, 255))
    debug_sheet.paste(sheet, (0, 0), sheet)
    debug_sheet_path = os.path.join(EXPERIMENT_DIR, "gothic_sheet_from_refs.png")
    debug_sheet.save(debug_sheet_path)
    print(f"Debug sheet saved: {debug_sheet_path}")

    # Save BMFont file
    fnt_path = os.path.join(OUTPUT_DIR, "gothic_bitmap.fnt")
    with open(fnt_path, 'w') as f:
        f.write(f'info face="GothicBitmap" size={cell_h} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=0,0 outline=0\n')
        f.write(f'common lineHeight={cell_h} base={cell_h - cell_padding} scaleW={sheet_w} scaleH={sheet_h} pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0\n')
        f.write(f'page id=0 file="gothic_bitmap.png"\n')
        f.write(f'chars count={len(fnt_chars)}\n')
        for fc in fnt_chars:
            f.write(f'char id={fc["id"]:<6d}x={fc["x"]:<6d}y={fc["y"]:<6d}width={fc["width"]:<6d}height={fc["height"]:<6d}xoffset={fc["xoffset"]:<6d}yoffset={fc["yoffset"]:<6d}xadvance={fc["xadvance"]:<6d}page={fc["page"]:<4d}chnl={fc["chnl"]}\n')

    print(f"BMFont file saved: {fnt_path}")
    print(f"\nTotal glyphs: {len(fnt_chars)}")
    print("\nDone!")


if __name__ == "__main__":
    main()
