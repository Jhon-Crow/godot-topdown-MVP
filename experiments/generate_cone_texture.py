#!/usr/bin/env python3
"""Generate an 18-degree cone-shaped light texture for the flashlight.

This creates a 512x512 PNG image with a narrow cone pointing to the right (+X).
The cone has:
- 18 degrees total beam angle (9 degrees each side)
- Smooth distance falloff (brighter near center, fades at edges)
- Gentle angular falloff for soft beam edges
- Transparent background outside the cone

The resulting texture is used by Godot's PointLight2D as its light mask.
"""

import math
from PIL import Image

SIZE = 512
HALF_ANGLE_DEG = 9.0  # 18 degrees total = 9 each side
HALF_ANGLE_RAD = math.radians(HALF_ANGLE_DEG)

OUTPUT_PATH = "../assets/sprites/effects/flashlight_cone_18deg.png"


def generate_cone_texture():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = img.load()

    center_x = SIZE / 2.0
    center_y = SIZE / 2.0
    max_radius = SIZE / 2.0

    for y in range(SIZE):
        for x in range(SIZE):
            dx = x - center_x
            dy = y - center_y
            dist = math.sqrt(dx * dx + dy * dy)

            if dist == 0:
                pixels[x, y] = (255, 255, 255, 255)
                continue

            if dist > max_radius:
                pixels[x, y] = (0, 0, 0, 0)
                continue

            # Angle from +X axis (0 = right)
            angle = abs(math.atan2(dy, dx))

            # Anti-aliasing: smooth transition at cone edge instead of hard cutoff
            # Creates a soft boundary zone to eliminate jagged "stair-step" edges
            EDGE_SMOOTHNESS = 0.15  # Width of anti-aliasing zone (15% of cone angle)
            edge_start = HALF_ANGLE_RAD * (1.0 - EDGE_SMOOTHNESS)
            edge_end = HALF_ANGLE_RAD * (1.0 + EDGE_SMOOTHNESS)

            # Angular falloff with smooth anti-aliased edges
            if angle > edge_end:
                # Outside cone boundary - fully transparent
                pixels[x, y] = (0, 0, 0, 0)
                continue
            elif angle > edge_start:
                # In anti-aliasing zone - smooth fade to transparent
                edge_progress = (angle - edge_start) / (edge_end - edge_start)
                ang_factor = 1.0 - edge_progress
                # Smooth S-curve for natural-looking fade
                ang_factor = ang_factor * ang_factor * (3.0 - 2.0 * ang_factor)
            else:
                # Inside cone - full brightness with gentle rolloff
                ang_factor = 1.0 - (angle / HALF_ANGLE_RAD)
                ang_factor = math.pow(ang_factor, 0.5)  # gentle roll-off

            # Distance falloff: brighter near center, fading toward edge
            dist_factor = 1.0 - (dist / max_radius)
            dist_factor = max(0.0, min(1.0, dist_factor))

            intensity = dist_factor * ang_factor
            alpha = int(intensity * 255)
            pixels[x, y] = (255, 255, 255, alpha)

    img.save(OUTPUT_PATH)
    print(f"Generated cone texture: {OUTPUT_PATH}")
    print(f"  Size: {SIZE}x{SIZE}")
    print(f"  Beam angle: {HALF_ANGLE_DEG * 2}°")

    # Verify: count non-transparent pixels
    total = SIZE * SIZE
    non_zero = sum(1 for y in range(SIZE) for x in range(SIZE) if pixels[x, y][3] > 0)
    print(f"  Non-transparent pixels: {non_zero}/{total} ({100*non_zero/total:.1f}%)")


if __name__ == "__main__":
    generate_cone_texture()
