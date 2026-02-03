#!/usr/bin/env python3
"""
Create left arm sprites by horizontally mirroring existing right arm sprites.

The current arm naming is confusing:
- LeftArm sprite (at position 24,6) is actually the RIGHT SHOULDER
- RightArm sprite (at position -2,6) is actually the RIGHT FOREARM

We need to:
1. Rename existing sprites properly (right_shoulder, right_forearm)
2. Create left arm equivalents by horizontal mirroring (left_shoulder, left_forearm)

For Issue #448: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/448
"""

from PIL import Image
import os

def create_mirrored_sprites():
    """Create left arm sprites by mirroring right arm sprites."""

    # Base directories
    player_dir = "/tmp/gh-issue-solver-1770143631008/assets/sprites/characters/player"
    enemy_dir = "/tmp/gh-issue-solver-1770143631008/assets/sprites/characters/enemy"

    # Mapping: source file -> [destination file(s)]
    # The "left_arm" sprite is actually the right shoulder
    # The "right_arm" sprite is actually the right forearm
    sprite_mappings = [
        # Player sprites
        {
            "dir": player_dir,
            "source": "player_left_arm.png",  # This is actually right shoulder
            "rename_to": "player_right_shoulder.png",
            "mirror_to": "player_left_shoulder.png"
        },
        {
            "dir": player_dir,
            "source": "player_right_arm.png",  # This is actually right forearm
            "rename_to": "player_right_forearm.png",
            "mirror_to": "player_left_forearm.png"
        },
        # Enemy sprites
        {
            "dir": enemy_dir,
            "source": "enemy_left_arm.png",  # This is actually right shoulder
            "rename_to": "enemy_right_shoulder.png",
            "mirror_to": "enemy_left_shoulder.png"
        },
        {
            "dir": enemy_dir,
            "source": "enemy_right_arm.png",  # This is actually right forearm
            "rename_to": "enemy_right_forearm.png",
            "mirror_to": "enemy_left_forearm.png"
        },
    ]

    for mapping in sprite_mappings:
        dir_path = mapping["dir"]
        source_path = os.path.join(dir_path, mapping["source"])
        rename_path = os.path.join(dir_path, mapping["rename_to"])
        mirror_path = os.path.join(dir_path, mapping["mirror_to"])

        if not os.path.exists(source_path):
            print(f"[SKIP] Source not found: {source_path}")
            continue

        # Load source image
        img = Image.open(source_path)
        print(f"[LOAD] {source_path} ({img.width}x{img.height})")

        # Save copy with new name (keeping original for now to avoid breaking anything)
        img.save(rename_path)
        print(f"[COPY] -> {rename_path}")

        # Create horizontally mirrored version for left arm
        mirrored = img.transpose(Image.FLIP_LEFT_RIGHT)
        mirrored.save(mirror_path)
        print(f"[MIRROR] -> {mirror_path}")

    print("\nDone! Created the following new sprites:")
    print("- player_right_shoulder.png (copy of original left_arm)")
    print("- player_left_shoulder.png (mirrored)")
    print("- player_right_forearm.png (copy of original right_arm)")
    print("- player_left_forearm.png (mirrored)")
    print("- enemy_right_shoulder.png (copy of original left_arm)")
    print("- enemy_left_shoulder.png (mirrored)")
    print("- enemy_right_forearm.png (copy of original right_arm)")
    print("- enemy_left_forearm.png (mirrored)")
    print("\nNote: Original files (left_arm.png, right_arm.png) are kept for now.")
    print("They will be removed after updating scene files.")

if __name__ == "__main__":
    create_mirrored_sprites()
