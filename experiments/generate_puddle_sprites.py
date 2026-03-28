#!/usr/bin/env python3
"""Generate multiple irregular-shaped puddle sprites for the Docks map.

The reference image shows:
- Dark charcoal puddle (dark blue-grey, nearly black)
- Quite transparent so the floor shows through
- Irregular/organic shape (not a perfect circle or oval)
- Subtle lighter center highlight (sky reflection)

We generate 4 variants with different irregular shapes.
"""

import math
import random
from PIL import Image, ImageDraw, ImageFilter

SIZE = 128  # pixels square for each sprite


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
    # Goal: quite transparent so the floor shows through clearly.
    # The puddle is a dark-tinted overlay — like a wet sheen on pavement.
    draw = ImageDraw.Draw(img)

    # Layer 1: main body — very transparent dark tint (wet pavement)
    # Alpha ~80 means floor still strongly visible (reference shows ~30-40% opacity)
    draw.polygon(poly, fill=(25, 30, 42, 80))

    # Layer 2: inner area — slightly darker to suggest depth / water body
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

    draw.polygon(inner_poly, fill=(30, 38, 55, 95))

    # Layer 3: small center highlight (sky/light reflection — subtle bright spot)
    highlight_r = int(min(base_rx, base_ry) * 0.18)
    hx = cx + random.randint(-6, 6)
    hy = cy + random.randint(-5, 5)
    draw.ellipse(
        (hx - highlight_r, hy - highlight_r, hx + highlight_r, hy + highlight_r),
        fill=(90, 105, 130, 55),
    )

    # Apply blur: larger blur for very soft, natural edges
    img = img.filter(ImageFilter.GaussianBlur(radius=4))

    return img


def main():
    import os
    out_dir = os.path.join(os.path.dirname(__file__), "../assets/sprites/effects")
    os.makedirs(out_dir, exist_ok=True)

    # Sprite 0: roughly oval (main puddle, replaces existing puddle.png)
    img0 = make_puddle(seed=42, shape_roughness=0.25, num_control=10, elongate=(1.1, 0.72))
    img0.save(os.path.join(out_dir, "puddle.png"))
    print("Saved puddle.png")

    # Sprite 1: wider irregular shape
    img1 = make_puddle(seed=7, shape_roughness=0.40, num_control=14, elongate=(1.25, 0.65))
    img1.save(os.path.join(out_dir, "puddle_2.png"))
    print("Saved puddle_2.png")

    # Sprite 2: rounder with bumps
    img2 = make_puddle(seed=13, shape_roughness=0.30, num_control=9, elongate=(1.0, 0.85))
    img2.save(os.path.join(out_dir, "puddle_3.png"))
    print("Saved puddle_3.png")

    # Sprite 3: elongated narrow shape
    img3 = make_puddle(seed=99, shape_roughness=0.45, num_control=11, elongate=(1.35, 0.58))
    img3.save(os.path.join(out_dir, "puddle_4.png"))
    print("Saved puddle_4.png")

    print("Done! All puddle sprites generated.")


if __name__ == "__main__":
    main()
