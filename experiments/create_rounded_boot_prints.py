#!/usr/bin/env python3
"""
Creates boot print textures with rounded edges for bloody footprints.

The boot prints feature:
- Rounded top and bottom (no square edges)
- Boot/shoe shape with heel and toe sections
- Organic, blob-like appearance similar to real bloody footprints
"""

from PIL import Image, ImageDraw

# Canvas size with padding for rotation (prevents cropping)
CANVAS_WIDTH = 22
CANVAS_HEIGHT = 40

# Boot print colors (will be modulated in-game)
BOOT_COLOR = (139, 0, 0, 255)  # Dark red
TRANSPARENT = (0, 0, 0, 0)

def create_boot_print(is_left: bool) -> Image.Image:
    """
    Creates a boot print with rounded edges.

    The boot print is designed to look like a realistic bloody boot mark:
    - Rounded heel at bottom
    - Narrower instep/arch area
    - Wider ball of foot
    - Rounded toe at top
    """
    img = Image.new('RGBA', (CANVAS_WIDTH, CANVAS_HEIGHT), TRANSPARENT)
    draw = ImageDraw.Draw(img)

    # Center of canvas
    cx = CANVAS_WIDTH // 2
    cy = CANVAS_HEIGHT // 2

    # Boot print dimensions (within the canvas)
    boot_width = 10
    boot_height = 18

    # Offset to center boot in canvas
    start_y = cy - boot_height // 2

    # Draw boot print with rounded sections
    # Using ellipses and rounded rectangles for organic shape

    # Mirror for left/right foot
    offset = 1 if is_left else -1

    # Heel section (rounded ellipse at bottom)
    heel_width = 7
    heel_height = 6
    heel_x = cx - heel_width // 2 + offset
    heel_y = start_y + boot_height - heel_height
    draw.ellipse([heel_x, heel_y, heel_x + heel_width, heel_y + heel_height], fill=BOOT_COLOR)

    # Arch/instep section (narrower, connecting heel to ball)
    arch_width = 4
    arch_height = 4
    arch_x = cx - arch_width // 2 + offset
    arch_y = start_y + boot_height - heel_height - arch_height + 2
    draw.ellipse([arch_x, arch_y, arch_x + arch_width, arch_y + arch_height + 2], fill=BOOT_COLOR)

    # Ball of foot section (wider rounded area)
    ball_width = 8
    ball_height = 6
    ball_x = cx - ball_width // 2 - offset
    ball_y = start_y + 4
    draw.ellipse([ball_x, ball_y, ball_x + ball_width, ball_y + ball_height], fill=BOOT_COLOR)

    # Toe section (rounded at top)
    toe_width = 7
    toe_height = 5
    toe_x = cx - toe_width // 2 - offset
    toe_y = start_y
    draw.ellipse([toe_x, toe_y, toe_x + toe_width, toe_y + toe_height], fill=BOOT_COLOR)

    # Add some texture/variation for organic look
    # Small connecting pixels to merge sections smoothly
    for y in range(start_y + 3, start_y + boot_height - 2):
        # Vary width based on section (narrower at arch)
        if y > start_y + boot_height - heel_height:
            # Heel area
            width = 5
        elif y > start_y + boot_height - heel_height - arch_height + 1:
            # Arch area (narrow)
            width = 3
        elif y > start_y + 6:
            # Between arch and ball
            width = 4
        else:
            # Ball and toe area
            width = 6

        x_start = cx - width // 2
        x_end = cx + width // 2
        for x in range(x_start, x_end + 1):
            if 0 <= x < CANVAS_WIDTH and 0 <= y < CANVAS_HEIGHT:
                img.putpixel((x, y), BOOT_COLOR)

    return img


def main():
    # Create left and right boot prints
    left_boot = create_boot_print(is_left=True)
    right_boot = create_boot_print(is_left=False)

    # Save to assets folder
    output_dir = "/tmp/gh-issue-solver-1769321361944/assets/sprites/effects"

    left_path = f"{output_dir}/boot_print_left.png"
    right_path = f"{output_dir}/boot_print_right.png"

    left_boot.save(left_path)
    right_boot.save(right_path)

    print(f"Created: {left_path}")
    print(f"Created: {right_path}")
    print(f"Texture size: {CANVAS_WIDTH}x{CANVAS_HEIGHT}")


if __name__ == "__main__":
    main()
