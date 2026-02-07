#!/usr/bin/env python3
"""Extract Gothic character glyphs from the calligraphy specimen image.

Uses carefully tuned bounding boxes for each character in the 505x626 image.
Produces a BMFont-compatible sprite sheet and .fnt file for Godot 4.x.

Characters overlap significantly in the source calligraphy art, so some
overlap artifacts in the extracted glyphs are expected and add to the
authentic handwritten Gothic aesthetic.
"""

from PIL import Image, ImageDraw
import numpy as np
import os

# Use the source image saved in assets/fonts
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
INPUT_IMAGE = os.path.join(PROJECT_DIR, "assets", "fonts", "gothic_source.png")
OUTPUT_DIR = os.path.join(PROJECT_DIR, "assets", "fonts")
EXPERIMENT_DIR = SCRIPT_DIR

# Carefully tuned bounding boxes based on pixel-level analysis of 505x626 image.
# The calligraphy has characters that overlap, so boxes are placed
# to capture the main body of each character.
#
# Row layout in the source image:
#   Title "GOTHIC" at top (y~0-100)
#   Row 1: A B C D E F G (y~126-232)
#   Row 2: H I J K L M N O P (y~224-337)
#   Row 3: Q R S T U V W X Y Z (y~313-431)
#   Row 4: 0 1 2 3 4 5 6 7 8 9 (y~409-511)
#   Row 5: : & ? ! - (y~487-555)

CHAR_DEFS = [
    # Row 1: A-G
    ('A', 78, 126, 115, 244),
    ('B', 103, 126, 156, 232),
    ('C', 148, 126, 203, 232),
    ('D', 195, 126, 263, 232),
    ('E', 255, 126, 315, 232),
    ('F', 305, 126, 363, 232),
    ('G', 355, 126, 427, 232),

    # Row 2: H-P
    ('H', 79, 224, 148, 337),
    ('I', 143, 224, 177, 337),
    ('J', 171, 227, 216, 337),
    ('K', 209, 224, 267, 337),
    ('L', 259, 227, 299, 337),
    ('M', 291, 224, 349, 337),
    ('N', 339, 224, 386, 337),
    ('O', 377, 224, 426, 337),
    ('P', 417, 224, 466, 337),

    # Row 3: Q-Z
    ('Q', 62, 313, 125, 431),
    ('R', 117, 313, 167, 431),
    ('S', 159, 317, 203, 431),
    ('T', 195, 313, 243, 431),
    ('U', 237, 313, 281, 431),
    ('V', 273, 313, 327, 431),
    ('W', 317, 313, 379, 431),
    ('X', 369, 313, 411, 431),
    ('Y', 401, 313, 439, 431),
    ('Z', 431, 313, 467, 370),

    # Row 4: 0-9
    ('0', 92, 409, 135, 457),
    ('1', 130, 409, 162, 493),
    ('2', 154, 409, 201, 511),
    ('3', 194, 409, 241, 511),
    ('4', 232, 415, 275, 511),
    ('5', 267, 415, 311, 511),
    ('6', 303, 415, 345, 510),
    ('7', 337, 415, 375, 493),
    ('8', 370, 415, 413, 457),
    ('9', 401, 415, 420, 448),

    # Row 5: specials
    (':', 155, 487, 171, 502),
    ('&', 171, 487, 235, 524),
    ('?', 235, 487, 281, 528),
    ('!', 277, 487, 312, 520),
    ('-', 320, 497, 344, 511),
]


def main():
    print(f"Loading image: {INPUT_IMAGE}")
    if not os.path.exists(INPUT_IMAGE):
        print(f"ERROR: Image not found at {INPUT_IMAGE}")
        return

    img = Image.open(INPUT_IMAGE).convert('RGBA')
    width, height = img.size
    print(f"Image size: {width}x{height}")

    gray = np.array(img.convert('L'))

    # Process each character
    chars = []
    for char, x1, y1, x2, y2 in CHAR_DEFS:
        # Clamp to image bounds
        x1 = max(0, x1)
        y1 = max(0, y1)
        x2 = min(width, x2)
        y2 = min(height, y2)
        glyph_w = x2 - x1
        glyph_h = y2 - y1

        chars.append({
            'char': char,
            'bbox': (x1, y1, x2, y2),
            'width': glyph_w,
            'height': glyph_h
        })
        print(f"  '{char}': ({x1},{y1},{x2},{y2}) size={glyph_w}x{glyph_h}")

    # Create debug visualization showing bounding boxes on source image
    debug_img = img.copy().convert('RGB')
    draw = ImageDraw.Draw(debug_img)
    colors = ['red', 'lime', 'cyan', 'yellow', 'magenta']
    for i, c in enumerate(chars):
        x1, y1, x2, y2 = c['bbox']
        color = colors[i % len(colors)]
        draw.rectangle([x1, y1, x2 - 1, y2 - 1], outline=color, width=2)
        draw.text((x1 + 2, y1 + 2), c['char'], fill=color)

    debug_path = os.path.join(EXPERIMENT_DIR, "gothic_debug_final.png")
    debug_img.save(debug_path)
    print(f"\nDebug image saved: {debug_path}")

    # Determine sprite sheet layout
    max_w = max(c['width'] for c in chars)
    max_h = max(c['height'] for c in chars)
    print(f"\nMax glyph size: {max_w}x{max_h}")

    # Use padding between cells
    cell_padding = 2
    cell_w = max_w + cell_padding * 2
    cell_h = max_h + cell_padding * 2

    cols_per_row = 10
    # +2 for '+' and ' ' and 'x'
    total_chars = len(chars) + 3
    num_rows = (total_chars + cols_per_row - 1) // cols_per_row
    sheet_w = cols_per_row * cell_w
    sheet_h = num_rows * cell_h

    print(f"Sprite sheet: {sheet_w}x{sheet_h}, cell={cell_w}x{cell_h}")

    sheet = Image.new('RGBA', (sheet_w, sheet_h), (0, 0, 0, 0))
    fnt_chars = []

    for idx, c in enumerate(chars):
        row = idx // cols_per_row
        col = idx % cols_per_row

        x1, y1, x2, y2 = c['bbox']

        # Extract glyph region from source image grayscale
        glyph_gray = gray[y1:y2, x1:x2].copy()

        # Create smooth alpha: dark pixels = opaque, light = transparent
        # Use threshold-based conversion with smooth falloff
        threshold = 140.0
        alpha = np.clip((threshold - glyph_gray.astype(np.float32)) * (255.0 / threshold), 0, 255).astype(np.uint8)

        # Create white glyph with alpha mask
        result_pixels = np.zeros((c['height'], c['width'], 4), dtype=np.uint8)
        result_pixels[:, :, 0] = 255  # R = white
        result_pixels[:, :, 1] = 255  # G = white
        result_pixels[:, :, 2] = 255  # B = white
        result_pixels[:, :, 3] = alpha
        result = Image.fromarray(result_pixels)

        # Place in sheet: align to bottom of cell
        dest_x = col * cell_w + cell_padding
        y_offset = (cell_h - cell_padding * 2) - c['height']
        dest_y = row * cell_h + cell_padding + y_offset

        sheet.paste(result, (dest_x, dest_y))

        fnt_chars.append({
            'id': ord(c['char']),
            'x': dest_x,
            'y': dest_y,
            'width': c['width'],
            'height': c['height'],
            'xoffset': 0,
            'yoffset': 0,
            'xadvance': c['width'] + 2,
            'page': 0,
            'chnl': 15
        })

    # Add '+' character (synthetic)
    plus_idx = len(chars)
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
    sheet.paste(plus_img, (plus_dest_x, plus_dest_y))

    fnt_chars.append({
        'id': ord('+'),
        'x': plus_dest_x,
        'y': plus_dest_y,
        'width': plus_size,
        'height': plus_size,
        'xoffset': 0,
        'yoffset': 0,
        'xadvance': plus_size + 2,
        'page': 0,
        'chnl': 15
    })

    # Add space character (no glyph, just advance)
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

    # Add lowercase 'x' for combo display (x1, x2, etc.)
    # Use same glyph as uppercase X but slightly smaller
    x_char = next(c for c in chars if c['char'] == 'X')
    x_x1, x_y1, x_x2, x_y2 = x_char['bbox']
    x_glyph_gray = gray[x_y1:x_y2, x_x1:x_x2].copy()
    x_alpha = np.clip((140.0 - x_glyph_gray.astype(np.float32)) * (255.0 / 140.0), 0, 255).astype(np.uint8)
    x_result_pixels = np.zeros((x_char['height'], x_char['width'], 4), dtype=np.uint8)
    x_result_pixels[:, :, 0] = 255
    x_result_pixels[:, :, 1] = 255
    x_result_pixels[:, :, 2] = 255
    x_result_pixels[:, :, 3] = x_alpha
    x_result = Image.fromarray(x_result_pixels)
    # Scale down for lowercase x
    x_scaled = x_result.resize((int(x_char['width'] * 0.7), int(x_char['height'] * 0.7)), Image.LANCZOS)

    x_idx = plus_idx + 2  # after + and space
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
        'yoffset': 0,
        'xadvance': x_scaled.width + 2,
        'page': 0,
        'chnl': 15
    })

    # Save sprite sheet
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    sheet_path = os.path.join(OUTPUT_DIR, "gothic_bitmap.png")
    sheet.save(sheet_path)
    print(f"Sprite sheet saved: {sheet_path}")

    # Save debug version with dark background for visual inspection
    debug_sheet = Image.new('RGBA', (sheet_w, sheet_h), (30, 30, 30, 255))
    debug_sheet.paste(sheet, (0, 0), sheet)
    debug_sheet_path = os.path.join(EXPERIMENT_DIR, "gothic_sheet_debug.png")
    debug_sheet.save(debug_sheet_path)
    print(f"Debug sheet saved: {debug_sheet_path}")

    # Generate BMFont .fnt file
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
    print("\nDone! Bitmap font generated successfully.")


if __name__ == "__main__":
    main()
