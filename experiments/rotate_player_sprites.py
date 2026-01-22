#!/usr/bin/env python3
"""
Script to rotate player sprites 90 degrees clockwise.

The problem: The player model sprites are designed to face UP (head at top, body below),
but the weapon points to the RIGHT. This causes the player to appear at 90 degrees to
the rifle (the rifle appears at the player's left side instead of in front).

The fix: Rotate all player sprites 90 degrees clockwise so the player faces RIGHT
in the default orientation, matching the rifle direction.

Reference images show soldiers holding rifles in front of them, facing the same
direction as the rifle barrel points.
"""

from PIL import Image
import os

# Paths
SPRITES_DIR = "/tmp/gh-issue-solver-1769042475678/assets/sprites/characters/player"

# Sprite files to rotate
SPRITES = [
    "player_body.png",
    "player_head.png",
    "player_left_arm.png",
    "player_right_arm.png",
]


def rotate_sprite(input_path, angle=-90):
    """
    Rotate a sprite image by the specified angle.

    Args:
        input_path: Path to the input sprite file
        angle: Rotation angle in degrees (negative = clockwise)

    Returns:
        The rotated image
    """
    img = Image.open(input_path)

    # Rotate with expand=True to avoid clipping
    # Using NEAREST for pixel art to preserve crisp edges
    rotated = img.rotate(angle, expand=True, resample=Image.NEAREST)

    return rotated


def main():
    """Rotate all player sprites 90 degrees clockwise."""

    print("Rotating player sprites 90 degrees clockwise...")
    print(f"Source directory: {SPRITES_DIR}")
    print()

    for sprite_name in SPRITES:
        input_path = os.path.join(SPRITES_DIR, sprite_name)

        if not os.path.exists(input_path):
            print(f"ERROR: Sprite not found: {input_path}")
            continue

        # Load original dimensions
        with Image.open(input_path) as img:
            orig_size = img.size

        # Rotate the sprite
        rotated = rotate_sprite(input_path, angle=-90)  # -90 = clockwise
        new_size = rotated.size

        # Save back to the same file (overwrite)
        rotated.save(input_path)

        print(f"Rotated: {sprite_name}")
        print(f"  Original size: {orig_size}")
        print(f"  New size:      {new_size}")
        print()

    print("Done! All sprites rotated 90 degrees clockwise.")
    print()
    print("Note: You may also need to update sprite positions in Player.tscn")
    print("to adjust for the new orientation and create a proper rifle-holding pose.")


if __name__ == "__main__":
    main()
