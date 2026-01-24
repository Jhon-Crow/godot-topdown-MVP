#!/usr/bin/env python3
"""
Script to add a red armband to the player's arm sprites.
Issue #234: Add a red armband to the player's forearm for visibility during 'last chance'.
"""

from PIL import Image
import os

# Define colors - More saturated/vivid red for better visibility
RED_ARMBAND_MAIN = (220, 40, 40, 255)      # Main red color - bright saturated red
RED_ARMBAND_DARK = (180, 30, 30, 255)      # Dark red for shading - still visible
RED_ARMBAND_LIGHT = (255, 70, 70, 255)     # Light red for highlight - very bright

# Original arm colors (for reference)
GREEN_DARK = (35, 55, 35, 255)     # #233723
GREEN_MID = (55, 80, 50, 255)      # #375032
GREEN_LIGHT = (75, 100, 65, 255)  # #4B6441

# Paths
BASE_PATH = "/tmp/gh-issue-solver-1769076723020/assets/sprites/characters/player"
LEFT_ARM_PATH = os.path.join(BASE_PATH, "player_left_arm.png")
RIGHT_ARM_PATH = os.path.join(BASE_PATH, "player_right_arm.png")
COMBINED_PATH = os.path.join(BASE_PATH, "player_combined_preview.png")


def add_armband_to_left_arm(img):
    """
    Add a red armband to the left arm sprite.
    Left arm structure (20x8):
    - Rows 1-4 contain visible arm pixels
    - Hand (skin) at x=0-3
    - Arm/sleeve at x=4-19 (forearm area around x=8-12)
    """
    pixels = img.load()
    width, height = img.size

    # The armband should be on the forearm, approximately 2 pixels wide
    # Looking at the left arm, the visible arm runs from y=1 to y=4
    # We'll place the armband at x=10-11 (in the middle of the forearm)
    armband_x_start = 10
    armband_x_end = 11  # inclusive

    for y in range(height):
        for x in range(armband_x_start, armband_x_end + 1):
            pixel = pixels[x, y]
            # Only modify non-transparent pixels
            if len(pixel) == 4 and pixel[3] > 0:
                # Replace green shades with red shades
                r, g, b, a = pixel
                if (r, g, b, a) == GREEN_DARK:
                    pixels[x, y] = RED_ARMBAND_DARK
                elif (r, g, b, a) == GREEN_MID:
                    pixels[x, y] = RED_ARMBAND_MAIN
                elif (r, g, b, a) == GREEN_LIGHT:
                    pixels[x, y] = RED_ARMBAND_LIGHT
                elif a > 0:  # Any other non-transparent pixel
                    # Make it red-ish based on brightness
                    brightness = (r + g + b) / 3
                    if brightness < 50:
                        pixels[x, y] = RED_ARMBAND_DARK
                    elif brightness < 80:
                        pixels[x, y] = RED_ARMBAND_MAIN
                    else:
                        pixels[x, y] = RED_ARMBAND_LIGHT

    return img


def add_armband_to_right_arm(img):
    """
    Add a red armband to the right arm sprite.
    Right arm structure (20x8):
    - Rows 3-6 contain visible arm pixels
    - Hand (skin) at x=0-3
    - Arm/sleeve at x=4-19 (forearm area around x=8-12)
    """
    pixels = img.load()
    width, height = img.size

    # Place the armband at x=10-11 (in the middle of the forearm)
    armband_x_start = 10
    armband_x_end = 11  # inclusive

    for y in range(height):
        for x in range(armband_x_start, armband_x_end + 1):
            pixel = pixels[x, y]
            # Only modify non-transparent pixels
            if len(pixel) == 4 and pixel[3] > 0:
                # Replace green shades with red shades
                r, g, b, a = pixel
                if (r, g, b, a) == GREEN_DARK:
                    pixels[x, y] = RED_ARMBAND_DARK
                elif (r, g, b, a) == GREEN_MID:
                    pixels[x, y] = RED_ARMBAND_MAIN
                elif (r, g, b, a) == GREEN_LIGHT:
                    pixels[x, y] = RED_ARMBAND_LIGHT
                elif a > 0:  # Any other non-transparent pixel
                    # Make it red-ish based on brightness
                    brightness = (r + g + b) / 3
                    if brightness < 50:
                        pixels[x, y] = RED_ARMBAND_DARK
                    elif brightness < 80:
                        pixels[x, y] = RED_ARMBAND_MAIN
                    else:
                        pixels[x, y] = RED_ARMBAND_LIGHT

    return img


def update_combined_preview():
    """
    Recreate the combined preview image with updated arm sprites.
    """
    body = Image.open(os.path.join(BASE_PATH, "player_body.png")).convert("RGBA")
    head = Image.open(os.path.join(BASE_PATH, "player_head.png")).convert("RGBA")
    left_arm = Image.open(LEFT_ARM_PATH).convert("RGBA")
    right_arm = Image.open(RIGHT_ARM_PATH).convert("RGBA")

    # Get dimensions
    body_w, body_h = body.size
    head_w, head_h = head.size
    left_w, left_h = left_arm.size
    right_w, right_h = right_arm.size

    # Based on Player.tscn positions:
    # Body position: (-4, 0)
    # LeftArm position: (24, 6)
    # RightArm position: (-2, 6)
    # Head position: (-6, -2)

    # Calculate canvas size to fit all sprites
    # Center will be at approximately (64, 64)
    canvas_size = (64, 64)
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 0))

    # Positions relative to center (32, 32)
    center_x, center_y = 32, 32

    # Paste sprites (accounting for z-index - lower z goes first)
    # z_index order: Body(1), Head(3), Arms(4)

    # Body at (-4, 0) relative to center, centered at sprite center
    body_x = center_x + (-4) - body_w // 2
    body_y = center_y + (0) - body_h // 2
    canvas.paste(body, (body_x, body_y), body)

    # Head at (-6, -2) relative to center
    head_x = center_x + (-6) - head_w // 2
    head_y = center_y + (-2) - head_h // 2
    canvas.paste(head, (head_x, head_y), head)

    # RightArm at (-2, 6) relative to center
    right_x = center_x + (-2) - right_w // 2
    right_y = center_y + (6) - right_h // 2
    canvas.paste(right_arm, (right_x, right_y), right_arm)

    # LeftArm at (24, 6) relative to center
    left_x = center_x + (24) - left_w // 2
    left_y = center_y + (6) - left_h // 2
    canvas.paste(left_arm, (left_x, left_y), left_arm)

    canvas.save(COMBINED_PATH)
    print(f"Updated combined preview at {COMBINED_PATH}")


def main():
    print("Adding red armband to player arm sprites...")

    # Load and modify left arm
    print(f"Processing {LEFT_ARM_PATH}")
    left_arm = Image.open(LEFT_ARM_PATH).convert("RGBA")
    left_arm = add_armband_to_left_arm(left_arm)
    left_arm.save(LEFT_ARM_PATH)
    print(f"Saved modified left arm")

    # Load and modify right arm
    print(f"Processing {RIGHT_ARM_PATH}")
    right_arm = Image.open(RIGHT_ARM_PATH).convert("RGBA")
    right_arm = add_armband_to_right_arm(right_arm)
    right_arm.save(RIGHT_ARM_PATH)
    print(f"Saved modified right arm")

    # Update combined preview
    print("Updating combined preview...")
    update_combined_preview()

    print("Done! Red armbands have been added to player sprites.")


if __name__ == "__main__":
    main()
