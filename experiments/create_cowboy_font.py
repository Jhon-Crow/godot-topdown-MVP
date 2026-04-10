#!/usr/bin/env python3
"""
Creates a cowboy-style bitmap font (.fnt + .png) for the Strelok difficulty button.
Uses FreeSerifBold which supports both Latin and Cyrillic characters.
The resulting font will have a Western/frontier aesthetic via styling.

Output: 
  assets/fonts/cowboy_bitmap.fnt
  assets/fonts/cowboy_bitmap.png
"""

from PIL import Image, ImageDraw, ImageFont
import os
import math

# Characters needed:
# Latin uppercase: A-Z
# Latin lowercase: a-z  
# Cyrillic uppercase: А-Я (1040-1071)
# Cyrillic lowercase: а-я (1072-1103) + ё (1105) + Ё (1025)
# Digits: 0-9
# Punctuation: space, !, ?, -, (, ), .

LATIN_UPPER = [chr(c) for c in range(65, 91)]   # A-Z
LATIN_LOWER = [chr(c) for c in range(97, 123)]  # a-z
CYRILLIC_UPPER = [chr(c) for c in range(1040, 1072)] + [chr(1025)]  # А-Я + Ё
CYRILLIC_LOWER = [chr(c) for c in range(1072, 1104)] + [chr(1105)]  # а-я + ё
DIGITS = [chr(c) for c in range(48, 58)]         # 0-9
PUNCTUATION = [' ', '!', '?', '-', '(', ')', '.', ',', ':', ';', '"', "'"]

ALL_CHARS = LATIN_UPPER + LATIN_LOWER + CYRILLIC_UPPER + CYRILLIC_LOWER + DIGITS + PUNCTUATION

FONT_PATH = "/usr/share/fonts/truetype/freefont/FreeSerifBold.ttf"
FONT_SIZE = 48  # Base size for rendering
PADDING = 2
ATLAS_WIDTH = 1024
OUTPUT_DIR = "/tmp/gh-issue-solver-1775844437743/assets/fonts"

def create_cowboy_font():
    # Load font
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
    
    # First pass: measure all characters
    char_info = {}
    for char in ALL_CHARS:
        if char == ' ':
            char_info[char] = {'width': FONT_SIZE // 3, 'height': FONT_SIZE, 'bearing_x': 0, 'bearing_y': 0}
            continue
        
        # Create temp image to measure
        tmp = Image.new('RGBA', (FONT_SIZE * 2, FONT_SIZE * 2), (0, 0, 0, 0))
        d = ImageDraw.Draw(tmp)
        bbox = d.textbbox((0, 0), char, font=font)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        bx = bbox[0]
        by = bbox[1]
        char_info[char] = {'width': max(w, 1), 'height': max(h, 1), 'bearing_x': bx, 'bearing_y': by}
    
    # Compute line height
    line_height = FONT_SIZE + PADDING * 2
    
    # Pack chars into atlas
    # Simple row-based packing
    x, y = PADDING, PADDING
    max_row_height = 0
    placements = {}
    
    for char in ALL_CHARS:
        info = char_info[char]
        w = info['width'] + PADDING * 2
        h = info['height'] + PADDING * 2
        
        if x + w > ATLAS_WIDTH:
            x = PADDING
            y += max_row_height + PADDING
            max_row_height = 0
        
        placements[char] = (x, y, info['width'], info['height'])
        x += w + PADDING
        max_row_height = max(max_row_height, h)
    
    atlas_height = y + max_row_height + PADDING
    # Round up to power of 2
    ph = 1
    while ph < atlas_height:
        ph *= 2
    atlas_height = ph
    
    # Create atlas image
    atlas = Image.new('RGBA', (ATLAS_WIDTH, atlas_height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(atlas)
    
    # Render each character
    for char in ALL_CHARS:
        if char == ' ':
            continue
        
        info = char_info[char]
        px, py, pw, ph_ = placements[char]
        
        # Render character at placement position, accounting for bearing
        draw.text(
            (px - info['bearing_x'], py - info['bearing_y']),
            char,
            font=font,
            fill=(255, 255, 255, 255)
        )
    
    # Save atlas
    atlas_path = os.path.join(OUTPUT_DIR, "cowboy_bitmap.png")
    atlas.save(atlas_path)
    print(f"Saved atlas: {atlas_path} ({ATLAS_WIDTH}x{atlas_height})")
    
    # Generate .fnt file
    fnt_lines = []
    fnt_lines.append(f'info face="CowboyBitmap" size={FONT_SIZE} bold=1 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding={PADDING},{PADDING},{PADDING},{PADDING} spacing=1,1 outline=0')
    fnt_lines.append(f'common lineHeight={line_height} base={FONT_SIZE} scaleW={ATLAS_WIDTH} scaleH={atlas_height} pages=1 packed=0 alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0')
    fnt_lines.append('page id=0 file="cowboy_bitmap.png"')
    fnt_lines.append(f'chars count={len(ALL_CHARS)}')
    
    for char in ALL_CHARS:
        char_id = ord(char)
        info = char_info[char]
        
        if char == ' ':
            fnt_lines.append(f'char id={char_id}    x=0     y=0     width=0     height=0     xoffset=0     yoffset=0     xadvance={info["width"]}    page=0   chnl=15')
            continue
        
        px, py, pw, ph_ = placements[char]
        xadvance = pw + PADDING
        
        fnt_lines.append(
            f'char id={char_id:<6} x={px:<6} y={py:<6} width={pw:<6} height={ph_:<6} '
            f'xoffset={-info["bearing_x"]:<6} yoffset={-info["bearing_y"]:<6} '
            f'xadvance={xadvance:<6} page=0   chnl=15'
        )
    
    fnt_path = os.path.join(OUTPUT_DIR, "cowboy_bitmap.fnt")
    with open(fnt_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(fnt_lines) + '\n')
    print(f"Saved font descriptor: {fnt_path}")
    print(f"Total chars: {len(ALL_CHARS)}")
    
    # Verify the first few chars
    print("\nSample char data:")
    for char in ['A', 'а', 'С', 'G', ' ']:
        if char in placements:
            px, py, pw, ph_ = placements[char]
            print(f"  '{char}' (U+{ord(char):04X}): pos=({px},{py}) size={pw}x{ph_}")
        else:
            print(f"  '{char}' (space): advance={char_info[char]['width']}")

if __name__ == '__main__':
    create_cowboy_font()
