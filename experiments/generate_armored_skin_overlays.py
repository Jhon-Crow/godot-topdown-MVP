#!/usr/bin/env python3
"""
Generate crystal armor overlay sprites for the Armored Skin item (Issue #1142).

The overlay sprites use the same silhouette as the player body parts, but are
rendered as semi-transparent blue crystal/glass overlays — similar to how The
Binding of Isaac renders item overlays on the character.

Each overlay is: crystal blue tint (RGBA: 0,160,255) at ~60% opacity, applied
to every non-transparent pixel of the source sprite.
"""

from PIL import Image
import os

SRC_DIR = "assets/sprites/characters/player"
OUT_DIR = "assets/sprites/characters/player/armored_skin"

# Crystal armor color: light blue, semi-transparent
# Opacity 120/255 (~47%) so the player character is visible underneath
CRYSTAL_RGBA = (100, 200, 255, 120)  # R,G,B,A — azure crystal tint

PARTS = [
    "player_body.png",
    "player_head.png",
    "player_left_arm.png",
    "player_right_arm.png",
    "player_armband.png",
]

os.makedirs(OUT_DIR, exist_ok=True)

for filename in PARTS:
    src_path = os.path.join(SRC_DIR, filename)
    out_name = filename.replace("player_", "armored_skin_")
    out_path = os.path.join(OUT_DIR, out_name)

    img = Image.open(src_path).convert("RGBA")
    w, h = img.size

    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    src_pixels = img.load()
    out_pixels = overlay.load()

    for y in range(h):
        for x in range(w):
            r, g, b, a = src_pixels[x, y]
            if a > 10:  # non-transparent pixel
                # Fill with crystal color but scale alpha by original alpha
                scaled_alpha = int(CRYSTAL_RGBA[3] * (a / 255))
                out_pixels[x, y] = (CRYSTAL_RGBA[0], CRYSTAL_RGBA[1], CRYSTAL_RGBA[2], scaled_alpha)

    overlay.save(out_path)
    print(f"  Generated: {out_path} ({w}x{h})")

print("Done! Overlay sprites created in:", OUT_DIR)
