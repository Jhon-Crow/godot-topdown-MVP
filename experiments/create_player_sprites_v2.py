#!/usr/bin/env python3
"""
Create modular player sprites for the top-down shooter - Version 2.
Generates larger, more detailed pixel art sprites for body parts.
Style: Military soldier from top-down view (bird's eye) - similar to reference image.
License: CC0 - These are original creations for the project.
"""

from PIL import Image
import os

# Ensure output directory exists
output_dir = "../assets/sprites/characters/player"
os.makedirs(output_dir, exist_ok=True)

# Color palette (military colors - matching reference pixel art style)
COLORS = {
    'transparent': (0, 0, 0, 0),
    # Greens for uniform
    'dark_green': (35, 55, 35, 255),      # Darkest green (shadows)
    'green': (55, 80, 50, 255),           # Main military green
    'light_green': (75, 100, 65, 255),    # Highlights
    # Grays for gear/equipment
    'dark_gray': (45, 45, 50, 255),       # Dark gear
    'gray': (75, 75, 80, 255),            # Medium gear
    'light_gray': (110, 110, 115, 255),   # Light gear
    # Browns and tans
    'dark_brown': (60, 45, 30, 255),      # Dark brown
    'brown': (85, 65, 45, 255),           # Brown (belts, straps)
    'tan': (120, 100, 75, 255),           # Tan
    # Skin tones
    'skin_dark': (150, 110, 80, 255),     # Darker skin/shadow
    'skin': (175, 140, 105, 255),         # Main skin
    'skin_light': (195, 165, 130, 255),   # Skin highlight
    # Black for outlines/deep shadows
    'black': (25, 25, 30, 255),
}


def create_body_sprite():
    """
    Create the main body/torso sprite - 24x28 pixels.
    Top-down view shows shoulders, tactical vest, and torso from above.
    """
    width, height = 24, 28
    img = Image.new('RGBA', (width, height), COLORS['transparent'])
    pixels = img.load()

    # Body pattern - more detailed tactical vest appearance
    # Characters: . = transparent, D = dark_green, G = green, L = light_green
    #             d = dark_gray, g = gray, l = light_gray, B = brown, b = dark_brown
    body_pattern = [
        # Row 0-3: Upper back/neck area
        "........LLGGLL........",  # 0 - reduced width
        "......LLGGGGGGLL......",  # 1
        ".....GGGGGGGGGGGGG.....",  # 2
        "....DDGGGGGGGGGGGGDD....",  # 3
        # Row 4-7: Shoulder/vest area with tactical details
        "...DDDGGGGGGGGGGGGGDDD...",  # 4 - 27 chars, trim
        "..DDDDGGGGddddGGGGDDDD..",  # 5
        "..DDDDGGGdddddGGGGDDDD..",  # 6
        ".DDDDDGGGddddddGGGDDDDD.",  # 7
        # Row 8-11: Main torso - widest part
        ".DDDDDGGGddddddGGGDDDDD.",  # 8
        "DDDDDDGGGddddddGGGDDDDDD",  # 9
        "DDDDDDGGGddddddGGGDDDDDD",  # 10
        "DDDDDDGGGddddddGGGDDDDDD",  # 11
        # Row 12-15: Mid torso with belt
        ".DDDDDGGGddddddGGGDDDDD.",  # 12
        ".DDDDDGGGddddddGGGDDDDD.",  # 13
        "..DDDDBBBBBBBBBBBBbbbb..",  # 14 - belt
        "..DDDDBBBBBBBBBBBBbbbb..",  # 15
        # Row 16-19: Lower torso
        "...DDDGGGddddddGGGDDD...",  # 16
        "...DDDGGGddddddGGGDDD...",  # 17
        "....DDGGGGGGGGGGGDD....",  # 18
        "....DDGGGGGGGGGGGDD....",  # 19
        # Row 20-23: Waist/hip area
        ".....DGGGGGGGGGGD.....",  # 20
        ".....DGGGGGGGGGGD.....",  # 21
        "......GGGGGGGGGG......",  # 22
        "......GGGGGGGGGG......",  # 23
        # Row 24-27: Lower body
        ".......GGGGGGGG.......",  # 24
        ".......GGGGGGGG.......",  # 25
        "........GGGGGG........",  # 26
        "........GGGGGG........",  # 27
    ]

    color_map = {
        '.': COLORS['transparent'],
        'D': COLORS['dark_green'],
        'G': COLORS['green'],
        'L': COLORS['light_green'],
        'd': COLORS['dark_gray'],
        'g': COLORS['gray'],
        'l': COLORS['light_gray'],
        'B': COLORS['brown'],
        'b': COLORS['dark_brown'],
    }

    for y, row in enumerate(body_pattern):
        for x, char in enumerate(row[:width]):
            if char in color_map:
                pixels[x, y] = color_map[char]

    return img


def create_head_sprite():
    """
    Create the head/helmet sprite - 18x14 pixels.
    Top-down view shows helmet from above with slight 3D depth.
    """
    width, height = 18, 14
    img = Image.new('RGBA', (width, height), COLORS['transparent'])
    pixels = img.load()

    # Helmet pattern with depth shading
    head_pattern = [
        "......LLLLLL......",  # 0 - top highlight
        "....LLGGGGGGLL....",  # 1
        "...LGGGGGGGGGGL...",  # 2
        "..LGGGGGGGGGGGGLL..",  # 3
        ".LGGGGGGGGGGGGGGL.",  # 4
        ".GGGGGGGGGGGGGGGGG.",  # 5
        "GGGGGGGGGGGGGGGGGGG",  # 6 - widest
        "GGGGGGGGGGGGGGGGGGG",  # 7
        "DGGGGGGGGGGGGGGGGGG",  # 8
        ".DGGGGGGGGGGGGGGGD.",  # 9
        ".DDGGGGGGGGGGGGGDD.",  # 10
        "..DDGGGGGGGGGGGDD..",  # 11
        "...DDDGGGGGGGDDD...",  # 12
        ".....DDDDDDDDD.....",  # 13 - bottom shadow
    ]

    color_map = {
        '.': COLORS['transparent'],
        'D': COLORS['dark_green'],
        'G': COLORS['green'],
        'L': COLORS['light_green'],
    }

    for y, row in enumerate(head_pattern):
        for x, char in enumerate(row[:width]):
            if char in color_map:
                pixels[x, y] = color_map[char]

    return img


def create_left_arm_sprite():
    """
    Create the left arm sprite - 8x20 pixels.
    Top-down view showing arm extended forward (holding position).
    """
    width, height = 8, 20
    img = Image.new('RGBA', (width, height), COLORS['transparent'])
    pixels = img.load()

    # Left arm - extended forward for weapon holding
    arm_pattern = [
        "..GGL...",  # 0 - shoulder attachment
        ".GGGL...",  # 1
        ".DGGL...",  # 2
        ".DGGL...",  # 3
        ".DGGL...",  # 4
        ".DGGL...",  # 5
        ".DGGL...",  # 6
        ".DGGL...",  # 7
        ".DGGL...",  # 8 - upper arm
        ".DGGL...",  # 9
        ".DGGL...",  # 10
        ".DGGL...",  # 11 - elbow
        ".DGGL...",  # 12
        "..DGL...",  # 13
        "..DGL...",  # 14
        "..dGL...",  # 15 - forearm (glove)
        "..dsS...",  # 16 - wrist
        "..sSS...",  # 17 - hand
        "...SS...",  # 18 - fingers
        "...SS...",  # 19
    ]

    color_map = {
        '.': COLORS['transparent'],
        'D': COLORS['dark_green'],
        'G': COLORS['green'],
        'L': COLORS['light_green'],
        'd': COLORS['dark_gray'],
        's': COLORS['skin_dark'],
        'S': COLORS['skin'],
    }

    for y, row in enumerate(arm_pattern):
        for x, char in enumerate(row[:width]):
            if char in color_map:
                pixels[x, y] = color_map[char]

    return img


def create_right_arm_sprite():
    """
    Create the right arm sprite - 8x20 pixels.
    Top-down view, mirror of left arm.
    """
    width, height = 8, 20
    img = Image.new('RGBA', (width, height), COLORS['transparent'])
    pixels = img.load()

    # Right arm - mirrored, extended forward
    arm_pattern = [
        "...LGG..",  # 0
        "...LGGG.",  # 1
        "...LGGD.",  # 2
        "...LGGD.",  # 3
        "...LGGD.",  # 4
        "...LGGD.",  # 5
        "...LGGD.",  # 6
        "...LGGD.",  # 7
        "...LGGD.",  # 8
        "...LGGD.",  # 9
        "...LGGD.",  # 10
        "...LGGD.",  # 11
        "...LGGD.",  # 12
        "...LGD..",  # 13
        "...LGD..",  # 14
        "...LGd..",  # 15
        "...Ssd..",  # 16
        "...SSs..",  # 17
        "...SS...",  # 18
        "...SS...",  # 19
    ]

    color_map = {
        '.': COLORS['transparent'],
        'D': COLORS['dark_green'],
        'G': COLORS['green'],
        'L': COLORS['light_green'],
        'd': COLORS['dark_gray'],
        's': COLORS['skin_dark'],
        'S': COLORS['skin'],
    }

    for y, row in enumerate(arm_pattern):
        for x, char in enumerate(row[:width]):
            if char in color_map:
                pixels[x, y] = color_map[char]

    return img


def create_combined_sprite():
    """
    Create a combined preview sprite showing all parts assembled - 48x48 pixels.
    This is for reference and can also be used as a fallback single sprite.
    """
    width, height = 48, 48
    img = Image.new('RGBA', (width, height), COLORS['transparent'])

    # Load individual parts
    body = create_body_sprite()
    head = create_head_sprite()
    left_arm = create_left_arm_sprite()
    right_arm = create_right_arm_sprite()

    # Calculate center position
    cx = width // 2
    cy = height // 2

    # Position body at center (slightly lower to leave room for head)
    body_x = cx - body.width // 2
    body_y = cy - body.height // 2 + 4
    img.paste(body, (body_x, body_y), body)

    # Position head above body (overlapping slightly)
    head_x = cx - head.width // 2
    head_y = body_y - head.height + 6
    img.paste(head, (head_x, head_y), head)

    # Position left arm (attached to left shoulder)
    left_arm_x = body_x - left_arm.width + 4
    left_arm_y = body_y + 3
    img.paste(left_arm, (left_arm_x, left_arm_y), left_arm)

    # Position right arm (attached to right shoulder)
    right_arm_x = body_x + body.width - 4
    right_arm_y = body_y + 3
    img.paste(right_arm, (right_arm_x, right_arm_y), right_arm)

    return img


def main():
    """Generate all player sprites."""
    print("Creating modular player sprites (v2)...")

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

    # Print positioning data for Godot scene
    print("\n--- Godot Scene Positioning Data ---")
    body = sprites['body']
    head = sprites['head']
    left_arm = sprites['left_arm']
    right_arm = sprites['right_arm']
    combined = sprites['combined_preview']

    print(f"Combined size: {combined.width}x{combined.height}")
    print(f"Body size: {body.width}x{body.height}")
    print(f"Head size: {head.width}x{head.height}")
    print(f"Left arm size: {left_arm.width}x{left_arm.height}")
    print(f"Right arm size: {right_arm.width}x{right_arm.height}")

    print("\nRecommended Node2D positions (origin at center of combined):")
    print(f"  Body: (0, 4)")
    print(f"  Head: (0, -10)")
    print(f"  LeftArm: (-12, 5)")
    print(f"  RightArm: (12, 5)")


if __name__ == "__main__":
    main()
