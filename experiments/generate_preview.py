#!/usr/bin/env python3
"""
Generate a side-by-side preview screenshot showing:
  LEFT:  Normal player (all body parts composited)
  RIGHT: Player with crystal armor overlay (body parts + overlays on top)

Matches the positions from Player.tscn:
  Body:     position = Vector2(-4, 0),   z_index=1
  LeftArm:  position = Vector2(24, 6),   z_index=4
  RightArm: position = Vector2(-2, 6),   z_index=4
  Armband:  position = Vector2(-2, 6),   z_index=5
  Head:     position = Vector2(-6, -2),  z_index=3
"""

from PIL import Image, ImageDraw, ImageFont
import os

SPRITE_DIR = "assets/sprites/characters/player"
OVERLAY_DIR = "assets/sprites/characters/player/armored_skin"
OUT_PATH = "docs/screenshots/armored_skin_preview.png"
os.makedirs("docs/screenshots", exist_ok=True)

SCALE = 6  # Scale up 6x for visibility (sprites are tiny ~28x24)
CANVAS_W = 80  # canvas width in original pixels
CANVAS_H = 60  # canvas height in original pixels

# Offsets to center the player in the canvas
ORIGIN_X = 20
ORIGIN_Y = 20

# (filename, dx, dy, z_index)
PARTS = [
    ("player_body.png",      -4,  0, 1),
    ("player_right_arm.png", -2,  6, 4),
    ("player_armband.png",   -2,  6, 5),
    ("player_left_arm.png",  24,  6, 4),
    ("player_head.png",      -6, -2, 3),
]

OVERLAYS = [
    ("armored_skin_body.png",      -4,  0, 10),
    ("armored_skin_right_arm.png", -2,  6, 14),
    ("armored_skin_armband.png",   -2,  6, 15),
    ("armored_skin_left_arm.png",  24,  6, 14),
    ("armored_skin_head.png",      -6, -2, 13),
]


def composite_player(canvas_w, canvas_h, parts, sprite_dir):
    canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    sorted_parts = sorted(parts, key=lambda p: p[3])
    for fname, dx, dy, _ in sorted_parts:
        sprite = Image.open(os.path.join(sprite_dir, fname)).convert("RGBA")
        x = ORIGIN_X + dx
        y = ORIGIN_Y + dy
        canvas.paste(sprite, (x, y), sprite)
    return canvas


def scale_up(img, scale):
    w, h = img.size
    return img.resize((w * scale, h * scale), Image.NEAREST)


# Normal player
normal_canvas = composite_player(CANVAS_W, CANVAS_H, PARTS, SPRITE_DIR)

# Armored player: base + overlays on top (alpha-composited correctly)
armored_canvas = composite_player(CANVAS_W, CANVAS_H, PARTS, SPRITE_DIR)
for fname, dx, dy, z in OVERLAYS:
    overlay_sprite = Image.open(os.path.join(OVERLAY_DIR, fname)).convert("RGBA")
    x = ORIGIN_X + dx
    y = ORIGIN_Y + dy
    # Use alpha_composite to properly blend transparent overlay over base
    temp = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    temp.paste(overlay_sprite, (x, y), overlay_sprite)
    armored_canvas = Image.alpha_composite(armored_canvas, temp)

# Scale up for visibility
normal_big = scale_up(normal_canvas, SCALE)
armored_big = scale_up(armored_canvas, SCALE)

W = normal_big.width
H = normal_big.height
LABEL_H = 40
GAP = 20

# Compose side by side on a dark background
result_w = W * 2 + GAP * 3
result_h = H + LABEL_H * 2
result = Image.new("RGBA", (result_w, result_h), (30, 30, 30, 255))

result.paste(normal_big, (GAP, LABEL_H), normal_big)
result.paste(armored_big, (W + GAP * 2, LABEL_H), armored_big)

draw = ImageDraw.Draw(result)
# Labels
draw.text((GAP + W // 2 - 40, 8), "Without Armor", fill=(220, 220, 220, 255))
draw.text((W + GAP * 2 + W // 2 - 55, 8), "Armored Skin (overlay)", fill=(100, 200, 255, 255))
# Bottom caption
draw.text((10, H + LABEL_H + 8), "Crystal armor overlays match player body part positions — like The Binding of Isaac",
          fill=(160, 160, 160, 255))

result = result.convert("RGB")
result.save(OUT_PATH)
print(f"Preview saved: {OUT_PATH}")
