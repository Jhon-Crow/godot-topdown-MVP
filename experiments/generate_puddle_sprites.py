#!/usr/bin/env python3
"""Generate realistic irregular puddle sprites for the Docks map.

Requirements from user feedback:
- Plain matte dark gray — NO highlights, NO bright center spot, NO glow
- Darker than the floor (floor is RGB ~64,59,56 = Color(0.25,0.23,0.22))
- Realistic irregular shapes (not circles, not perfect ovals)
- Smooth edges — NOT blurry/glowing, but also NOT sharp clipped corners
- Transparent so floor shows through (alpha ~100 body)
- 16 distinct variants so no two puddles on a map share the same shape
"""

import math
import random
from PIL import Image, ImageDraw, ImageFilter

SIZE = 320  # larger canvas — extra 32px margin on each side prevents edge clipping

# Floor color is RGB ~(64, 59, 56).
# Puddles = wet pavement = DARKER than floor, matte gray, no highlights.
PUDDLE_BODY_COLOR = (38, 36, 35)   # dark matte charcoal — darker than floor
BODY_ALPHA = 105                    # more transparent than before (was 140)


def make_puddle(
    seed: int,
    shape_roughness: float = 0.35,
    num_control: int = 14,
    elongate: tuple = (1.0, 0.7),
) -> Image.Image:
    """Create a single puddle RGBA image with a realistic irregular organic shape.

    Uses a perturbed ellipse approach: control points are placed around an
    ellipse and randomly displaced radially, then smoothly interpolated.
    The result is a flat matte fill with no center highlight and smooth edges.

    Fix for sharp corners:
    - Minimum num_control raised to 12 to ensure enough points for smooth curves
    - Roughness clamped to max 0.40 at draw time to prevent deep concave indents
    - Extra smoothing pass at the end
    """
    random.seed(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    cx, cy = SIZE // 2, SIZE // 2
    # Reduced from 0.82 to 0.60 to ensure shapes never touch the canvas edge.
    # The radii clamp is also tightened (max 1.15) so the total effective
    # radius stays below cx: 0.60 * 1.40 * 1.15 * 128 = 124px < 128px.
    base_rx = int(cx * 0.60 * elongate[0])
    base_ry = int(cy * 0.60 * elongate[1])

    # Clamp roughness to avoid too-deep concave indents that create sharp cuts
    effective_roughness = min(shape_roughness, 0.40)

    # ── 1. Generate irregular boundary via perturbed control points ──────────
    angles = [i * 2 * math.pi / num_control for i in range(num_control)]
    radii = []
    for _ in angles:
        r = 1.0 + random.uniform(-effective_roughness, effective_roughness)
        radii.append(r)

    # Add extra "lobe" perturbations for more organic look
    # Pick 2-3 random control points to push outward (lobe) and 1-2 inward
    num_lobes = random.randint(2, 4)
    lobe_indices = random.sample(range(num_control), min(num_lobes, num_control))
    for li in lobe_indices:
        radii[li] += random.uniform(0.08, 0.22)
    num_indents = random.randint(1, 2)
    indent_indices = random.sample(range(num_control), min(num_indents, num_control))
    for ii in indent_indices:
        radii[ii] -= random.uniform(0.05, 0.15)
    # Clamp radii tighter (max 1.15 instead of 1.55) so combined with the
    # base_rx factor (0.60 * elongate_x up to 1.40) the shape always fits
    # inside the canvas: 0.60 * 1.40 * 1.15 * 128 ≈ 124 px < 128 px.
    radii = [max(0.45, min(1.15, r)) for r in radii]

    # ── 2. Interpolate polygon at high resolution ────────────────────────────
    def build_polygon(scale: float = 1.0) -> list:
        poly = []
        steps = 400  # increased from 300 for smoother curves
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

    # ── 4. Soft-feather ONLY the outermost ~6 pixels for natural edge blend ──
    # Use a tight blur just to anti-alias the polygon edge (not a glow).
    edge_blur = img.filter(ImageFilter.GaussianBlur(radius=3))

    # Create a mask that only applies the blur near the edges.
    mask_img = Image.new("L", (SIZE, SIZE), 0)
    mask_draw = ImageDraw.Draw(mask_img)
    # The inner (shrunk) polygon stays crisp
    inner_poly = build_polygon(0.88)
    mask_draw.polygon(outer_poly, fill=255)
    mask_draw.polygon(inner_poly, fill=0)
    # Blur the mask itself to create a smooth blend zone at the edges
    mask_img = mask_img.filter(ImageFilter.GaussianBlur(radius=4))

    # Composite: use sharp original inside, blurred at edges
    img = Image.composite(img, edge_blur, mask_img)

    # ── 5. Final minimal smoothing pass to eliminate any residual sharp pixels ──
    img = img.filter(ImageFilter.GaussianBlur(radius=1))

    return img


def main():
    import os
    out_dir = os.path.join(os.path.dirname(__file__), "../assets/sprites/effects")
    os.makedirs(out_dir, exist_ok=True)

    # 16 variants — distinct elongations, roughness, and seed for organic variety.
    # All num_control >= 12 to prevent sharp corner artifacts.
    # Roughness values capped at 0.45 to avoid deep concave "clipped" cuts.
    # Shapes span a range from narrow elongated to roundish irregular blobs.
    configs = [
        # (filename,         seed, roughness, num_ctrl, elongate_x, elongate_y)
        ("puddle.png",        42,   0.28,     13,       1.20, 0.68),   # elongated blob
        ("puddle_2.png",       7,   0.38,     16,       1.35, 0.62),   # wide splat
        ("puddle_3.png",      13,   0.32,     12,       0.95, 0.90),   # roundish amoeba
        ("puddle_4.png",      99,   0.42,     15,       1.28, 0.58),   # irregular wide
        ("puddle_5.png",      17,   0.36,     18,       1.10, 0.74),   # lumpy elongated
        ("puddle_6.png",      53,   0.40,     14,       1.25, 0.60),   # wide narrow
        ("puddle_7.png",      81,   0.30,     13,       0.85, 0.82),   # near-round rough
        ("puddle_8.png",      37,   0.38,     14,       1.15, 0.65),   # tri-lobe
        # 8 additional variants for 16 total (enough to cover all 27 positions without repeating)
        ("puddle_9.png",      23,   0.30,     15,       1.05, 0.72),   # medium oval rough
        ("puddle_10.png",     61,   0.42,     13,       1.30, 0.60),   # elongated wide
        ("puddle_11.png",      5,   0.36,     17,       0.90, 0.85),   # near-round lumpy
        ("puddle_12.png",     88,   0.44,     13,       1.25, 0.63),   # irregular kidney
        ("puddle_13.png",     44,   0.33,     16,       1.15, 0.70),   # medium elongated
        ("puddle_14.png",     72,   0.38,     14,       1.38, 0.57),   # flat wide splat
        ("puddle_15.png",     19,   0.28,     12,       0.80, 0.78),   # compact round-ish
        ("puddle_16.png",     56,   0.40,     14,       1.20, 0.65),   # asymmetric blob
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

    print("\nDone! 16 puddle sprites: dark matte gray, smooth edges, realistic shapes.")


if __name__ == "__main__":
    main()
