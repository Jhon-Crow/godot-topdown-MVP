#!/usr/bin/env python3
"""Generate multiple irregular-shaped puddle sprites for the Docks map.

The reference image shows:
- Dark NEUTRAL charcoal gray (R≈G≈B ≈ 55-65, NOT blue-tinted)
- Quite transparent so the floor shows through
- Irregular/organic shape (not a perfect circle or oval)
- NO bright center highlight — flat uniform gray fill

We generate 8 variants with different irregular shapes.
"""

import math
import random
from PIL import Image, ImageDraw, ImageFilter

SIZE = 128  # pixels square for each sprite

# Reference image analysis: the puddles are neutral dark charcoal gray
# RGB approximately (60, 60, 65) — nearly equal R,G,B with very slight cool tone
# No blue-dominant values. No highlight in center.
PUDDLE_BODY_COLOR = (60, 60, 65)     # neutral dark charcoal gray
PUDDLE_INNER_COLOR = (50, 50, 55)    # slightly darker inner area
BODY_ALPHA = 90                       # semi-transparent (floor still visible)
INNER_ALPHA = 110                     # slightly more opaque inner area


def make_puddle(
    seed: int,
    shape_roughness: float = 0.35,
    num_control: int = 12,
    elongate: tuple = (1.0, 0.7),
) -> Image.Image:
    """Create a single puddle RGBA image with an irregular organic shape."""
    random.seed(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    cx, cy = SIZE // 2, SIZE // 2
    base_rx = int(cx * 0.80 * elongate[0])
    base_ry = int(cy * 0.80 * elongate[1])

    # Generate irregular boundary via perturbed ellipse control points
    angles = [i * 2 * math.pi / num_control for i in range(num_control)]
    radii = []
    for _ in angles:
        # Vary radius randomly around the base ellipse
        r = 1.0 + random.uniform(-shape_roughness, shape_roughness)
        radii.append(r)

    # Build polygon points (interpolated around the ellipse)
    poly = []
    steps = 200
    for s in range(steps):
        angle = s * 2 * math.pi / steps
        # Find which control segment we're in
        idx = int(angle / (2 * math.pi) * num_control)
        next_idx = (idx + 1) % num_control
        t = (angle - angles[idx] if angle >= angles[idx] else angle + 2 * math.pi - angles[idx])
        seg_len = (angles[next_idx] - angles[idx]) if next_idx > idx else (angles[next_idx] + 2 * math.pi - angles[idx])
        t = t / seg_len if seg_len > 0 else 0
        # Smooth interpolation
        r = radii[idx] * (1 - t) + radii[next_idx] * t
        x = cx + math.cos(angle) * base_rx * r
        y = cy + math.sin(angle) * base_ry * r
        poly.append((x, y))

    # Draw puddle in layers for realistic appearance.
    # Neutral dark charcoal gray — NO blue tint, NO center highlight.
    draw = ImageDraw.Draw(img)

    # Layer 1: main body — neutral dark charcoal gray
    draw.polygon(poly, fill=(*PUDDLE_BODY_COLOR, BODY_ALPHA))

    # Layer 2: inner area — slightly darker to suggest depth
    inner_poly = []
    for s in range(steps):
        angle = s * 2 * math.pi / steps
        idx = int(angle / (2 * math.pi) * num_control)
        next_idx = (idx + 1) % num_control
        t = (angle - angles[idx] if angle >= angles[idx] else angle + 2 * math.pi - angles[idx])
        seg_len = (angles[next_idx] - angles[idx]) if next_idx > idx else (angles[next_idx] + 2 * math.pi - angles[idx])
        t = t / seg_len if seg_len > 0 else 0
        r = radii[idx] * (1 - t) + radii[next_idx] * t
        scale = 0.60
        x = cx + math.cos(angle) * base_rx * r * scale
        y = cy + math.sin(angle) * base_ry * r * scale
        inner_poly.append((x, y))

    draw.polygon(inner_poly, fill=(*PUDDLE_INNER_COLOR, INNER_ALPHA))

    # NO center highlight — user requested flat uniform gray (no bright spot)

    # Apply blur: larger blur for very soft, natural edges
    img = img.filter(ImageFilter.GaussianBlur(radius=4))

    return img


def main():
    import os
    out_dir = os.path.join(os.path.dirname(__file__), "../assets/sprites/effects")
    os.makedirs(out_dir, exist_ok=True)

    # 8 variants with different shapes (seeds, roughness, elongation)
    configs = [
        # (filename, seed, roughness, num_control, elongate)
        ("puddle.png",   42, 0.25, 10, (1.10, 0.72)),
        ("puddle_2.png",  7, 0.40, 14, (1.25, 0.65)),
        ("puddle_3.png", 13, 0.30,  9, (1.00, 0.85)),
        ("puddle_4.png", 99, 0.45, 11, (1.35, 0.58)),
        ("puddle_5.png", 17, 0.35, 13, (0.90, 0.78)),
        ("puddle_6.png", 53, 0.50, 10, (1.20, 0.60)),
        ("puddle_7.png", 81, 0.28, 12, (1.05, 0.70)),
        ("puddle_8.png", 37, 0.42,  8, (1.30, 0.62)),
    ]

    for fname, seed, roughness, num_ctrl, elongate in configs:
        img = make_puddle(
            seed=seed,
            shape_roughness=roughness,
            num_control=num_ctrl,
            elongate=elongate,
        )
        img.save(os.path.join(out_dir, fname))
        print(f"Saved {fname}")

    print("Done! All 8 puddle sprites regenerated with neutral dark charcoal gray.")


if __name__ == "__main__":
    main()
