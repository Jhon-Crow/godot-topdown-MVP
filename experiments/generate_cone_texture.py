#!/usr/bin/env python3
"""Generate an 18-degree cone-shaped light texture for the flashlight.

This creates a 2048x2048 PNG image with a narrow cone pointing to the right (+X).
The cone has:
- 18 degrees total beam angle (9 degrees each side)
- Smooth distance falloff (brighter near center, fades at edges)
- Gentle angular falloff for soft beam edges
- Transparent background outside the cone
- Per-pixel 4x4 supersampling for smooth anti-aliased edges

The higher resolution (2048x2048 vs 512x512) combined with supersampling ensures
the cone edges remain smooth even when scaled up by Godot's texture_scale (6x).
At 6x scale, each texture pixel covers ~3 screen pixels, and supersampling
smooths the sub-pixel transitions so no staircase artifacts are visible.

The resulting texture is used by Godot's PointLight2D as its light mask.
"""

import math
from PIL import Image

SIZE = 2048
HALF_ANGLE_DEG = 9.0  # 18 degrees total = 9 each side
HALF_ANGLE_RAD = math.radians(HALF_ANGLE_DEG)
SAMPLES = 4  # 4x4 = 16 sub-samples per pixel for anti-aliasing

OUTPUT_PATH = "../assets/sprites/effects/flashlight_cone_18deg.png"


def sample_intensity(sx, sy, center_x, center_y, max_radius):
    """Compute light intensity for a single sub-pixel sample point."""
    dx = sx - center_x
    dy = sy - center_y
    dist = math.sqrt(dx * dx + dy * dy)

    if dist == 0:
        return 1.0

    if dist > max_radius:
        return 0.0

    # Angle from +X axis (0 = right)
    angle = abs(math.atan2(dy, dx))

    if angle > HALF_ANGLE_RAD:
        return 0.0

    # Distance falloff: brighter near center, fading toward edge
    dist_factor = 1.0 - (dist / max_radius)
    dist_factor = max(0.0, min(1.0, dist_factor))

    # Angular falloff: soft edges at cone boundary
    ang_factor = 1.0 - (angle / HALF_ANGLE_RAD)
    ang_factor = math.pow(ang_factor, 0.5)  # gentle roll-off

    return dist_factor * ang_factor


def generate_cone_texture():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pixels = img.load()

    center_x = SIZE / 2.0
    center_y = SIZE / 2.0
    max_radius = SIZE / 2.0

    total_samples = SAMPLES * SAMPLES

    for y in range(SIZE):
        for x in range(SIZE):
            # Quick reject: if even the closest corner of this pixel
            # is outside the max radius, skip entirely
            dx = x - center_x
            dy = y - center_y
            rough_dist = math.sqrt(dx * dx + dy * dy)

            if rough_dist > max_radius + 1.5:
                continue

            # Quick reject: if this pixel is far from the cone edge,
            # we can skip supersampling and just sample the center
            rough_angle = abs(math.atan2(dy, dx)) if rough_dist > 0 else 0.0
            # Pixel angular width at this distance (how much angle one pixel spans)
            pixel_ang_width = (1.0 / max(rough_dist, 1.0))

            if rough_angle > HALF_ANGLE_RAD + pixel_ang_width * 2:
                # Well outside the cone - skip
                continue

            if rough_angle < HALF_ANGLE_RAD - pixel_ang_width * 2 and rough_dist < max_radius - 2:
                # Well inside the cone - no need for supersampling
                intensity = sample_intensity(x + 0.5, y + 0.5, center_x, center_y, max_radius)
                alpha = int(intensity * 255)
                if alpha > 0:
                    pixels[x, y] = (255, 255, 255, alpha)
                continue

            # Near the cone edge or radius edge - use supersampling
            total_intensity = 0.0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    sub_x = x + (sx + 0.5) / SAMPLES
                    sub_y = y + (sy + 0.5) / SAMPLES
                    total_intensity += sample_intensity(
                        sub_x, sub_y, center_x, center_y, max_radius
                    )

            intensity = total_intensity / total_samples
            alpha = int(intensity * 255)
            if alpha > 0:
                pixels[x, y] = (255, 255, 255, alpha)

    img.save(OUTPUT_PATH)
    print(f"Generated cone texture: {OUTPUT_PATH}")
    print(f"  Size: {SIZE}x{SIZE}")
    print(f"  Beam angle: {HALF_ANGLE_DEG * 2}°")
    print(f"  Supersampling: {SAMPLES}x{SAMPLES} ({total_samples} samples/pixel)")

    # Verify: count non-transparent pixels
    total = SIZE * SIZE
    non_zero = sum(1 for y in range(SIZE) for x in range(SIZE) if pixels[x, y][3] > 0)
    print(f"  Non-transparent pixels: {non_zero}/{total} ({100*non_zero/total:.1f}%)")


if __name__ == "__main__":
    generate_cone_texture()
