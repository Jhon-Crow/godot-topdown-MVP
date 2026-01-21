#!/usr/bin/env python3
"""
Create modular player sprites for the top-down shooter.
Generates pixel art sprites for body parts: body, head, left arm, right arm.
Style: Military soldier from top-down view (bird's eye).
License: CC0 - These are original creations for the project.
"""

from PIL import Image
import os

# Ensure output directory exists
output_dir = "../assets/sprites/characters/player"
os.makedirs(output_dir, exist_ok=True)

# Color palette (military colors)
COLORS = {
    'transparent': (0, 0, 0, 0),
    'dark_green': (45, 68, 42, 255),      # Dark military green
    'green': (62, 88, 58, 255),           # Military green
    'light_green': (78, 108, 72, 255),    # Light military green
    'brown': (101, 67, 33, 255),          # Brown for skin/gear
    'tan': (139, 119, 101, 255),          # Tan for skin
    'dark_gray': (50, 50, 50, 255),       # Dark gray for shadows
    'gray': (90, 90, 90, 255),            # Gray for gear
    'light_gray': (130, 130, 130, 255),   # Light gray highlights
    'skin': (186, 154, 122, 255),         # Skin tone
    'black': (20, 20, 20, 255),           # Near black
}

def create_body_sprite():
    """
    Create the main body/torso sprite - 16x20 pixels.
    Top-down view shows shoulders and torso from above.
    """
    width, height = 16, 20
    img = Image.new('RGBA', (width, height), COLORS['transparent'])
    pixels = img.load()

    # Body shape - oval torso from top-down
    body_pattern = [
        # Row 0-2: Top of torso (back/neck area)
        "      gggg      ",  # row 0
        "    GGggggGG    ",  # row 1
        "   GGGggggGGG   ",  # row 2
        # Row 3-5: Upper back with backpack indication
        "  GGGGggggGGGG  ",  # row 3
        " GGGGGggggGGGGG ",  # row 4
        " GGGGGggggGGGGG ",  # row 5
        # Row 6-9: Middle torso - widest part (shoulders)
        "GGGGGGgggGGGGGGG",  # row 6 (17 chars - will trim)
        "GGGGGGgggGGGGGGG",  # row 7
        "GGGGGGgggGGGGGGG",  # row 8
        " GGGGGgggGGGGGG ",  # row 9
        # Row 10-14: Lower torso
        " GGGGGgggGGGGGG ",  # row 10
        "  GGGGgggGGGGG  ",  # row 11
        "  GGGGgggGGGGG  ",  # row 12
        "   GGGgggGGGG   ",  # row 13
        "    GGgggGGG    ",  # row 14
        # Row 15-19: Belt/waist area
        "    GGgggGGG    ",  # row 15
        "     GgggGG     ",  # row 16
        "     GgggGG     ",  # row 17
        "      gggg      ",  # row 18
        "      gggg      ",  # row 19
    ]

    color_map = {
        ' ': COLORS['transparent'],
        'g': COLORS['green'],
        'G': COLORS['dark_green'],
    }

    for y, row in enumerate(body_pattern):
        for x, char in enumerate(row[:width]):  # Ensure we don't exceed width
            if char in color_map:
                pixels[x, y] = color_map[char]

    return img


def create_head_sprite():
    """
    Create the head/helmet sprite - 12x10 pixels.
    Top-down view shows helmet from above.
    """
    width, height = 12, 10
    img = Image.new('RGBA', (width, height), COLORS['transparent'])
    pixels = img.load()

    # Helmet shape from above
    head_pattern = [
        "    gggg    ",  # row 0
        "  GGggggGG  ",  # row 1
        " GGGggggGGG ",  # row 2
        " GGGGggGGGG ",  # row 3
        "GGGGGggGGGGG",  # row 4
        "GGGGGggGGGGG",  # row 5
        " GGGGggGGGG ",  # row 6
        " GGGGggGGGG ",  # row 7
        "  GGggggGG  ",  # row 8
        "    gggg    ",  # row 9
    ]

    color_map = {
        ' ': COLORS['transparent'],
        'g': COLORS['green'],
        'G': COLORS['dark_green'],
    }

    for y, row in enumerate(head_pattern):
        for x, char in enumerate(row[:width]):
            if char in color_map:
                pixels[x, y] = color_map[char]

    return img


def create_left_arm_sprite():
    """
    Create the left arm sprite - 6x14 pixels.
    Shows arm from top-down view, extended forward for holding position.
    """
    width, height = 6, 14
    img = Image.new('RGBA', (width, height), COLORS['transparent'])
    pixels = img.load()

    # Left arm from top-down (slightly bent forward)
    arm_pattern = [
        "  gg  ",  # row 0 - shoulder attachment
        " gGg  ",  # row 1
        " gGg  ",  # row 2
        " gGg  ",  # row 3
        " gGg  ",  # row 4
        " gGg  ",  # row 5
        " gGg  ",  # row 6
        " gGg  ",  # row 7
        " gGg  ",  # row 8 - elbow area
        " gGg  ",  # row 9
        " gGg  ",  # row 10
        "  sg  ",  # row 11 - forearm/hand
        "  ss  ",  # row 12 - hand (skin)
        "  ss  ",  # row 13 - hand
    ]

    color_map = {
        ' ': COLORS['transparent'],
        'g': COLORS['green'],
        'G': COLORS['dark_green'],
        's': COLORS['skin'],
    }

    for y, row in enumerate(arm_pattern):
        for x, char in enumerate(row[:width]):
            if char in color_map:
                pixels[x, y] = color_map[char]

    return img


def create_right_arm_sprite():
    """
    Create the right arm sprite - 6x14 pixels.
    Mirror of left arm but can be animated separately for reload.
    """
    width, height = 6, 14
    img = Image.new('RGBA', (width, height), COLORS['transparent'])
    pixels = img.load()

    # Right arm from top-down (slightly bent forward) - mirrored
    arm_pattern = [
        "  gg  ",  # row 0 - shoulder attachment
        "  gGg ",  # row 1
        "  gGg ",  # row 2
        "  gGg ",  # row 3
        "  gGg ",  # row 4
        "  gGg ",  # row 5
        "  gGg ",  # row 6
        "  gGg ",  # row 7
        "  gGg ",  # row 8 - elbow area
        "  gGg ",  # row 9
        "  gGg ",  # row 10
        "  gs  ",  # row 11 - forearm/hand
        "  ss  ",  # row 12 - hand (skin)
        "  ss  ",  # row 13 - hand
    ]

    color_map = {
        ' ': COLORS['transparent'],
        'g': COLORS['green'],
        'G': COLORS['dark_green'],
        's': COLORS['skin'],
    }

    for y, row in enumerate(arm_pattern):
        for x, char in enumerate(row[:width]):
            if char in color_map:
                pixels[x, y] = color_map[char]

    return img


def create_combined_sprite():
    """
    Create a combined preview sprite showing all parts assembled - 32x32 pixels.
    This is for reference only, actual game uses separate parts.
    """
    width, height = 32, 32
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Load individual parts
    body = create_body_sprite()
    head = create_head_sprite()
    left_arm = create_left_arm_sprite()
    right_arm = create_right_arm_sprite()

    # Position parts (center on 32x32 canvas)
    # Body at center
    body_x = (width - body.width) // 2
    body_y = 10
    img.paste(body, (body_x, body_y), body)

    # Head above body (overlapping slightly)
    head_x = (width - head.width) // 2
    head_y = 2
    img.paste(head, (head_x, head_y), head)

    # Left arm on left side
    left_arm_x = body_x - 3
    left_arm_y = body_y + 2
    img.paste(left_arm, (left_arm_x, left_arm_y), left_arm)

    # Right arm on right side
    right_arm_x = body_x + body.width - 3
    right_arm_y = body_y + 2
    img.paste(right_arm, (right_arm_x, right_arm_y), right_arm)

    return img


def main():
    """Generate all player sprites."""
    print("Creating modular player sprites...")

    # Create individual part sprites
    sprites = {
        'body': create_body_sprite(),
        'head': create_head_sprite(),
        'left_arm': create_left_arm_sprite(),
        'right_arm': create_right_arm_sprite(),
        'combined_preview': create_combined_sprite(),
    }

    # Save sprites
    for name, sprite in sprites.items():
        filepath = os.path.join(output_dir, f"player_{name}.png")
        sprite.save(filepath)
        print(f"  Saved: {filepath} ({sprite.width}x{sprite.height})")

    print("\nAll sprites created successfully!")
    print(f"Output directory: {os.path.abspath(output_dir)}")


if __name__ == "__main__":
    main()
