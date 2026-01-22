#!/usr/bin/env python3
"""
Script to generate a combined preview of the player model with rifle-holding pose.

This creates a visual preview showing the player sprites arranged in a proper pose
where the soldier is holding the rifle in front of them.

The positions are based on:
- Player faces RIGHT (after 90-degree rotation)
- Head is behind/left of body (negative X)
- Arms extend forward (positive X) to hold the rifle
- Body is at center
"""

from PIL import Image
import os

# Paths
SPRITES_DIR = "/tmp/gh-issue-solver-1769042475678/assets/sprites/characters/player"
OUTPUT_PATH = "/tmp/gh-issue-solver-1769042475678/assets/sprites/characters/player/player_combined_preview.png"

# New positions for rifle-holding pose (player facing RIGHT)
# Format: (x_offset, y_offset) from center of canvas
# Positive X = forward (direction player faces)
# Positive Y = down
POSITIONS = {
    # Head: behind/left of body (player faces right, so head is at negative X)
    # Positioned to be behind the torso, slightly up
    "player_head.png": (-12, -2),
    # Body: center
    "player_body.png": (0, 0),
    # Left arm (foregrip hand): extended forward to support rifle
    # This arm reaches forward and up to hold the rifle foregrip
    "player_left_arm.png": (14, -4),
    # Right arm (trigger hand): extended forward holding trigger/pistol grip
    # This arm is at the rear of the rifle, closer to body
    "player_right_arm.png": (10, 6),
}

# Z-order for layering (lower = behind)
Z_ORDER = [
    "player_left_arm.png",  # Back arm (foregrip)
    "player_body.png",      # Body
    "player_head.png",      # Head
    "player_right_arm.png", # Front arm (trigger)
]


def generate_preview():
    """Generate a combined preview of the player model."""

    # Load all sprites
    sprites = {}
    for name in Z_ORDER:
        path = os.path.join(SPRITES_DIR, name)
        if os.path.exists(path):
            sprites[name] = Image.open(path).convert("RGBA")
            print(f"Loaded: {name} ({sprites[name].size})")
        else:
            print(f"WARNING: Sprite not found: {name}")

    # Calculate canvas size (needs to fit all sprites at their positions)
    min_x, min_y = 0, 0
    max_x, max_y = 0, 0

    for name, img in sprites.items():
        pos = POSITIONS.get(name, (0, 0))
        # Calculate bounds (centered on position)
        left = pos[0] - img.width // 2
        right = pos[0] + img.width // 2
        top = pos[1] - img.height // 2
        bottom = pos[1] + img.height // 2

        min_x = min(min_x, left)
        max_x = max(max_x, right)
        min_y = min(min_y, top)
        max_y = max(max_y, bottom)

    # Add padding
    padding = 8
    canvas_width = max_x - min_x + padding * 2
    canvas_height = max_y - min_y + padding * 2

    # Calculate offset to center everything on canvas
    offset_x = -min_x + padding
    offset_y = -min_y + padding

    print(f"\nCanvas size: {canvas_width}x{canvas_height}")
    print(f"Offset: ({offset_x}, {offset_y})")

    # Create canvas
    canvas = Image.new("RGBA", (canvas_width, canvas_height), (0, 0, 0, 0))

    # Paste sprites in z-order
    for name in Z_ORDER:
        if name not in sprites:
            continue

        img = sprites[name]
        pos = POSITIONS.get(name, (0, 0))

        # Calculate paste position (top-left corner)
        paste_x = pos[0] - img.width // 2 + offset_x
        paste_y = pos[1] - img.height // 2 + offset_y

        # Paste with alpha compositing
        canvas.alpha_composite(img, (int(paste_x), int(paste_y)))
        print(f"Pasted: {name} at ({paste_x}, {paste_y})")

    # Save result
    canvas.save(OUTPUT_PATH)
    print(f"\nSaved preview to: {OUTPUT_PATH}")

    return canvas_width, canvas_height, POSITIONS


if __name__ == "__main__":
    generate_preview()
