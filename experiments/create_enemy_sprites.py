#!/usr/bin/env python3
"""
Script to create enemy sprites based on player sprites.
Creates black versions with white skull decorations.
"""

from PIL import Image, ImageDraw
import os

# Paths
BASE_DIR = '/tmp/gh-issue-solver-1769066205054'
PLAYER_DIR = os.path.join(BASE_DIR, 'assets/sprites/characters/player')
ENEMY_DIR = os.path.join(BASE_DIR, 'assets/sprites/characters/enemy')

# Ensure enemy directory exists
os.makedirs(ENEMY_DIR, exist_ok=True)


def convert_to_dark(image):
    """Convert green/military colors to dark/black colors, preserving transparency."""
    img = image.convert('RGBA')
    pixels = img.load()

    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = pixels[x, y]
            if a > 0:  # Only modify non-transparent pixels
                # Convert to grayscale, then darken significantly
                gray = int(0.299 * r + 0.587 * g + 0.114 * b)
                # Make it dark - reduce to 20-40% of grayscale value
                dark = int(gray * 0.25)
                pixels[x, y] = (dark, dark, dark, a)

    return img


def draw_simple_skull_on_head(image):
    """Draw a simple white skull symbol on the head (helmet area)."""
    img = image.copy()
    draw = ImageDraw.Draw(img)

    # Head size is 14x18 - skull should be small and centered
    # Simple skull: circle for head, two dots for eyes
    cx, cy = 7, 8  # Center point for skull

    # Skull outline (small white oval)
    draw.ellipse([cx-3, cy-3, cx+3, cy+2], fill=(255, 255, 255, 255))

    # Eyes (two black dots)
    draw.point((cx-1, cy-1), fill=(0, 0, 0, 255))
    draw.point((cx+1, cy-1), fill=(0, 0, 0, 255))

    # Nose (small vertical line)
    draw.point((cx, cy), fill=(0, 0, 0, 255))

    # Teeth area (white rectangle at bottom)
    draw.rectangle([cx-2, cy+1, cx+2, cy+2], fill=(255, 255, 255, 255))

    # Tooth lines (black)
    draw.point((cx, cy+1), fill=(0, 0, 0, 255))

    return img


def draw_simple_skull_on_arm(image, is_left=True):
    """Draw a small white skull on the forearm."""
    img = image.copy()
    draw = ImageDraw.Draw(img)

    # Arm size is 20x8 - skull should be tiny
    # Position depends on left or right arm
    if is_left:
        cx, cy = 10, 4  # Center-right for left arm (forearm area)
    else:
        cx, cy = 10, 4  # Center-right for right arm (forearm area)

    # Very simple skull - just a few pixels
    # Small white circle/oval for skull
    draw.ellipse([cx-2, cy-2, cx+2, cy+1], fill=(255, 255, 255, 255))

    # Eyes (two black dots)
    draw.point((cx-1, cy-1), fill=(0, 0, 0, 255))
    draw.point((cx+1, cy-1), fill=(0, 0, 0, 255))

    return img


def create_enemy_body():
    """Create enemy body sprite (black version of player body)."""
    player_body = Image.open(os.path.join(PLAYER_DIR, 'player_body.png'))
    enemy_body = convert_to_dark(player_body)
    enemy_body.save(os.path.join(ENEMY_DIR, 'enemy_body.png'))
    print(f"Created enemy_body.png ({enemy_body.size})")
    return enemy_body


def create_enemy_head():
    """Create enemy head sprite (black with white skull)."""
    player_head = Image.open(os.path.join(PLAYER_DIR, 'player_head.png'))
    enemy_head = convert_to_dark(player_head)
    enemy_head = draw_simple_skull_on_head(enemy_head)
    enemy_head.save(os.path.join(ENEMY_DIR, 'enemy_head.png'))
    print(f"Created enemy_head.png ({enemy_head.size})")
    return enemy_head


def create_enemy_arms():
    """Create enemy arm sprites (black with skull on forearm)."""
    # Left arm
    player_left_arm = Image.open(os.path.join(PLAYER_DIR, 'player_left_arm.png'))
    enemy_left_arm = convert_to_dark(player_left_arm)
    enemy_left_arm = draw_simple_skull_on_arm(enemy_left_arm, is_left=True)
    enemy_left_arm.save(os.path.join(ENEMY_DIR, 'enemy_left_arm.png'))
    print(f"Created enemy_left_arm.png ({enemy_left_arm.size})")

    # Right arm
    player_right_arm = Image.open(os.path.join(PLAYER_DIR, 'player_right_arm.png'))
    enemy_right_arm = convert_to_dark(player_right_arm)
    enemy_right_arm = draw_simple_skull_on_arm(enemy_right_arm, is_left=False)
    enemy_right_arm.save(os.path.join(ENEMY_DIR, 'enemy_right_arm.png'))
    print(f"Created enemy_right_arm.png ({enemy_right_arm.size})")

    return enemy_left_arm, enemy_right_arm


def create_combined_preview(body, head, left_arm, right_arm):
    """Create a combined preview image showing all enemy parts assembled."""
    # Use same dimensions as player combined preview
    preview_width = 64
    preview_height = 64

    preview = Image.new('RGBA', (preview_width, preview_height), (0, 0, 0, 0))

    # Center point for assembly
    cx, cy = 32, 32

    # Paste body (positioned at center) - offset similar to Player.tscn (-4, 0)
    body_x = cx - body.width // 2 - 4
    body_y = cy - body.height // 2
    preview.paste(body, (body_x, body_y), body)

    # Paste head (above body) - offset similar to Player.tscn (-6, -2)
    head_x = cx - head.width // 2 - 6
    head_y = cy - body.height // 2 - head.height // 2 - 2
    preview.paste(head, (head_x, head_y), head)

    # Paste left arm - offset similar to Player.tscn (24, 6)
    left_arm_x = cx + 24 - left_arm.width // 2
    left_arm_y = cy + 6 - left_arm.height // 2
    preview.paste(left_arm, (left_arm_x, left_arm_y), left_arm)

    # Paste right arm - offset similar to Player.tscn (-2, 6)
    right_arm_x = cx - 2 - right_arm.width // 2
    right_arm_y = cy + 6 - right_arm.height // 2
    preview.paste(right_arm, (right_arm_x, right_arm_y), right_arm)

    preview.save(os.path.join(ENEMY_DIR, 'enemy_combined_preview.png'))
    print(f"Created enemy_combined_preview.png ({preview.size})")
    return preview


def main():
    print("Creating enemy sprites based on player sprites...")
    print(f"Player sprites from: {PLAYER_DIR}")
    print(f"Enemy sprites to: {ENEMY_DIR}")
    print()

    body = create_enemy_body()
    head = create_enemy_head()
    left_arm, right_arm = create_enemy_arms()
    create_combined_preview(body, head, left_arm, right_arm)

    print("\nAll enemy sprites created successfully!")


if __name__ == '__main__':
    main()
