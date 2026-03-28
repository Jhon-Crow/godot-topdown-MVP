#!/usr/bin/env python3
"""Generate realistic irregular puddle sprites for the Docks map.

Requirements from user feedback:
- Plain matte dark gray — NO highlights, NO bright center spot, NO glow
- Darker than the floor (floor is RGB ~64,59,56 = Color(0.25,0.23,0.22))
- Realistic irregular shapes (not circles, not perfect ovals)
- Clean crisp edges — NOT blurry/glowing
- Transparent so floor shows through at edges (alpha ~120–160 body)
"""

import math
import random
from PIL import Image, ImageDraw, ImageFilter

SIZE = 256  # larger canvas for more detail

# Floor color is RGB ~(64, 59, 56).
# Puddles = wet pavement = DARKER than floor, matte gray, no highlights.
PUDDLE_BODY_COLOR = (38, 36, 35)   # dark matte charcoal — darker than floor
BODY_ALPHA = 140                    # solid enough to see clearly


def make_puddle(
    seed: int,
    shape_roughness: float = 0.35,
    num_control: int = 14,
    elongate: tuple = (1.0, 0.7),
) -> Image.Image:
    """Create a single puddle RGBA image with a realistic irregular organic shape.

    Uses a perturbed ellipse approach: control points are placed around an
    ellipse and randomly displaced radially, then smoothly interpolated.
    The result is a flat matte fill with no center highlight and clean edges.
    """
    random.seed(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    cx, cy = SIZE // 2, SIZE // 2
    base_rx = int(cx * 0.82 * elongate[0])
    base_ry = int(cy * 0.82 * elongate[1])

    # ── 1. Generate irregular boundary via perturbed control points ──────────
    angles = [i * 2 * math.pi / num_control for i in range(num_control)]
    radii = []
    for _ in angles:
        r = 1.0 + random.uniform(-shape_roughness, shape_roughness)
        radii.append(r)

    # Add extra "lobe" perturbations for more organic look
    # Pick 2-3 random control points to push outward (lobe) and 1-2 inward
    num_lobes = random.randint(2, 4)
    lobe_indices = random.sample(range(num_control), min(num_lobes, num_control))
    for li in lobe_indices:
        radii[li] += random.uniform(0.10, 0.30)
    num_indents = random.randint(1, 3)
    indent_indices = random.sample(range(num_control), min(num_indents, num_control))
    for ii in indent_indices:
        radii[ii] -= random.uniform(0.08, 0.22)
    # Clamp radii so shape stays within canvas
    radii = [max(0.3, min(1.6, r)) for r in radii]

    # ── 2. Interpolate polygon at high resolution ────────────────────────────
    def build_polygon(scale: float = 1.0) -> list:
        poly = []
        steps = 300
        for s in range(steps):
            angle = s * 2 * math.pi / steps
            idx = int(angle / (2 * math.pi) * num_control) % num_control
            next_idx = (idx + 1) % num_control
            a0 = angles[idx]
            a1 = angles[next_idx] if next_idx > idx else angles[next_idx] + 2 * math.pi
            seg_len = a1 - a0
            t = ((angle - a0) % (2 * math.pi)) / seg_len if seg_len > 0 else 0
            t = max(0.0, min(1.0, t))
            # Smooth (cosine) interpolation between control radii
            t_smooth = (1 - math.cos(t * math.pi)) / 2
            r = radii[idx] * (1 - t_smooth) + radii[next_idx] * t_smooth
            x = cx + math.cos(angle) * base_rx * r * scale
            y = cy + math.sin(angle) * base_ry * r * scale
            poly.append((x, y))
        return poly

    outer_poly = build_polygon(1.0)

    # ── 3. Draw flat matte puddle — single solid fill, no gradient ───────────
    draw = ImageDraw.Draw(img)
    draw.polygon(outer_poly, fill=(*PUDDLE_BODY_COLOR, BODY_ALPHA))

    # ── 4. Soft-feather ONLY the outermost 4 pixels for natural edge blend ──
    # Use a very tight blur just to anti-alias the polygon edge (not a glow).
    edge_blur = img.filter(ImageFilter.GaussianBlur(radius=2))

    # Create a mask that only applies the blur near the edges.
    # Inner mask = fully sharp. Outer region fades from sharp→blurred.
    mask_img = Image.new("L", (SIZE, SIZE), 0)
    mask_draw = ImageDraw.Draw(mask_img)
    # The inner (shrunk) polygon stays crisp
    inner_poly = build_polygon(0.88)
    mask_draw.polygon(outer_poly, fill=255)
    mask_draw.polygon(inner_poly, fill=0)
    # Blur the mask itself to create a smooth blend zone at the edges
    mask_img = mask_img.filter(ImageFilter.GaussianBlur(radius=3))

    # Composite: use sharp original inside, blurred at edges
    img = Image.composite(img, edge_blur, mask_img)

    return img


def main():
    import os
    out_dir = os.path.join(os.path.dirname(__file__), "../assets/sprites/effects")
    os.makedirs(out_dir, exist_ok=True)

    # 8 variants — distinct elongations, roughness, and seed for organic variety.
    # Shapes span a range from narrow elongated to roundish irregular blobs.
    configs = [
        # (filename,      seed, roughness, num_ctrl, elongate_x, elongate_y)
        ("puddle.png",     42,   0.28,     12,       1.20, 0.68),   # elongated blob
        ("puddle_2.png",    7,   0.42,     16,       1.35, 0.62),   # wide splat
        ("puddle_3.png",   13,   0.32,     10,       0.95, 0.90),   # roundish amoeba
        ("puddle_4.png",   99,   0.48,     14,       1.28, 0.58),   # irregular wide
        ("puddle_5.png",   17,   0.38,     18,       1.10, 0.74),   # lumpy elongated
        ("puddle_6.png",   53,   0.52,     11,       1.40, 0.55),   # very wide narrow
        ("puddle_7.png",   81,   0.30,     13,       0.85, 0.82),   # near-round rough
        ("puddle_8.png",   37,   0.44,      9,       1.15, 0.65),   # tri-lobe
    ]

    for fname, seed, roughness, num_ctrl, ex, ey in configs:
        img = make_puddle(
            seed=seed,
            shape_roughness=roughness,
            num_control=num_ctrl,
            elongate=(ex, ey),
        )
        img.save(os.path.join(out_dir, fname))
        print(f"Saved {fname} ({img.size[0]}x{img.size[1]})")

    print("\nDone! 8 puddle sprites: dark matte gray, crisp edges, realistic shapes.")


if __name__ == "__main__":
    main()
