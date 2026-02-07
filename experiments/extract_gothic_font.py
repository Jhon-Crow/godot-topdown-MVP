#!/usr/bin/env python3
"""Extract Gothic character glyphs from calligraphy image (v5).

Refined character boundaries based on pixel-level alpha density analysis
combined with 4x zoomed grid overlay visual verification.

Uses transparent-background source image for clean alpha extraction.
Produces a BMFont-compatible sprite sheet and .fnt file for Godot 4.x.
"""

from PIL import Image, ImageDraw
import numpy as np
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)

INPUT_IMAGE = os.path.join(PROJECT_DIR, "assets", "fonts", "gothic_source_nobg.png")
OUTPUT_DIR = os.path.join(PROJECT_DIR, "assets", "fonts")
EXPERIMENT_DIR = SCRIPT_DIR

# Row definitions with manually specified x-split points for each character.
# Based on zoomed 4x grid images with 10px grid lines.
# Format: (chars, y1, y2, x_splits)
#   where x_splits is list of x-boundaries: [x_start, split1, split2, ..., x_end]
#   giving len(chars)+1 values

ROWS = [
    # Row 1: A B C D E F G (y=130-213)
    # Row boundaries from horizontal density valleys (density < 40)
    # Column splits from per-column alpha density analysis + 4x zoom visual verification
    (list("ABCDEFG"), 130, 213,
     [93, 155, 200, 248, 282, 322, 360, 398]),

    # Row 2: H I J K L M N O P (y=210-296)
    # Density dips at x: 99(2), 133(1), 175(3), 216(2), 252, 293, 336, 390
    (list("HIJKLMNOP"), 210, 296,
     [78, 99, 133, 175, 216, 252, 293, 336, 390, 435]),

    # Row 3: Q R S T U V W X Y Z (y=295-380)
    # Density dips at x: 82, 122, 157, 200, 228(1), 275(6), 314, 348, 418
    (list("QRSTUVWXYZ"), 295, 380,
     [45, 82, 122, 157, 200, 240, 278, 320, 360, 418, 467]),

    # Row 4: 0 1 2 3 4 5 6 7 8 9 (y=380-458)
    # Density dips at x: 130, 152, 190, 224, 252, 288, 322, 358, 390
    (list("0123456789"), 380, 458,
     [93, 130, 152, 190, 224, 252, 288, 322, 358, 390, 416]),

    # Row 5: : & ? ! - (y=462-527)
    # Clear gap at x=169-172 (between : and &)
    (list(":&?!-"), 462, 527,
     [156, 170, 237, 268, 306, 342]),
]


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


def main():
    print(f"Loading image: {INPUT_IMAGE}")
    if not os.path.exists(INPUT_IMAGE):
        print(f"ERROR: Image not found at {INPUT_IMAGE}")
        return

    img = Image.open(INPUT_IMAGE).convert('RGBA')
    width, height = img.size
    print(f"Image size: {width}x{height}")

    all_chars = []

    for char_list, y1, y2, x_splits in ROWS:
        assert len(x_splits) == len(char_list) + 1, \
            f"Expected {len(char_list)+1} splits, got {len(x_splits)}"

        for i, char in enumerate(char_list):
            cx1, cx2 = x_splits[i], x_splits[i + 1]

            # Crop from RGBA source
            crop = img.crop((cx1, y1, cx2, y2))

            # Convert to white-on-alpha
            crop_arr = np.array(crop)
            result = np.zeros_like(crop_arr)
            result[:, :, 0] = 255
            result[:, :, 1] = 255
            result[:, :, 2] = 255
            result[:, :, 3] = crop_arr[:, :, 3]
            glyph = Image.fromarray(result)

            # Auto-trim transparent borders
            glyph = auto_trim_alpha(glyph, min_alpha=20)

            all_chars.append({
                'char': char,
                'glyph': glyph,
                'width': glyph.size[0],
                'height': glyph.size[1],
                'bbox': (cx1, y1, cx2, y2),
            })
            print(f"  '{char}': x={cx1}-{cx2} -> trimmed {glyph.size[0]}x{glyph.size[1]}")

    # Debug visualization
    debug_bg = Image.new('RGBA', (width, height), (255, 255, 255, 255))
    debug_bg.paste(img, (0, 0), img)
    debug_rgb = debug_bg.convert('RGB')
    draw = ImageDraw.Draw(debug_rgb)
    colors = ['red', 'lime', 'cyan', 'yellow', 'magenta', 'orange', 'blue', 'white', 'pink', 'gray']
    for i, c in enumerate(all_chars):
        x1, y1, x2, y2 = c['bbox']
        color = colors[i % len(colors)]
        draw.rectangle([x1, y1, x2 - 1, y2 - 1], outline=color, width=2)
        draw.text((x1 + 2, y1 + 2), c['char'], fill=color)

    debug_path = os.path.join(EXPERIMENT_DIR, "gothic_debug_v5.png")
    debug_rgb.save(debug_path)
    print(f"\nDebug image saved: {debug_path}")

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
    x_char = next(c for c in all_chars if c['char'] == 'X')
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

    # Save
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    sheet_path = os.path.join(OUTPUT_DIR, "gothic_bitmap.png")
    sheet.save(sheet_path)
    print(f"\nSprite sheet saved: {sheet_path}")

    debug_sheet = Image.new('RGBA', (sheet_w, sheet_h), (30, 30, 30, 255))
    debug_sheet.paste(sheet, (0, 0), sheet)
    debug_sheet_path = os.path.join(EXPERIMENT_DIR, "gothic_sheet_debug_v5.png")
    debug_sheet.save(debug_sheet_path)
    print(f"Debug sheet saved: {debug_sheet_path}")

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
