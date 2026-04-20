#!/usr/bin/env python3
"""
Generate a Hotline Miami / Door Kickers 2 style icon for the game's .exe
Produces: assets/icon.ico (multi-size Windows ICO)
          assets/icon_preview.png (256x256 preview)
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def draw_icon(size: int) -> Image.Image:
    """Draw the icon at the given square size."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    s = size / 256.0  # scale factor

    def sc(v):
        return v * s

    # ─── Background ────────────────────────────────────────────────────────
    # Dark radial gradient via concentric circles
    for r in range(int(sc(130)), 0, -1):
        t = r / sc(130)
        c = int(26 + t * (13 - 26))  # 0x1a → 0x0d
        draw.ellipse(
            [size // 2 - r, size // 2 - r, size // 2 + r, size // 2 + r],
            fill=(c, c, c + 14, 255),
        )

    cx, cy = size / 2, size / 2

    # ─── Blood splash dots (Hotline Miami energy) ──────────────────────────
    splats = [
        (60, 55, 6, 0.18),
        (195, 70, 4, 0.12),
        (45, 185, 5, 0.15),
        (210, 195, 7, 0.10),
        (170, 40, 3, 0.20),
        (80, 210, 4, 0.13),
    ]
    for sx, sy, sr, alpha in splats:
        x, y, r = sc(sx), sc(sy), sc(sr)
        a = int(255 * alpha)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 34, 68, a))

    # ─── Top-down figure (viewed from above) ───────────────────────────────
    fg_color = (17, 17, 17, 255)

    # Torso
    tx, ty, trx, try_ = cx, sc(122), sc(18), sc(26)
    draw.ellipse([tx - trx, ty - try_, tx + trx, ty + try_], fill=fg_color)

    # Head
    hx, hy, hr = cx, sc(92), sc(14)
    draw.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(15, 15, 15, 255))

    # Arms
    # Left arm
    lax, lay = sc(104), sc(116)
    lar_x, lar_y = sc(8), sc(5)
    draw.ellipse([lax - lar_x, lay - lar_y, lax + lar_x, lay + lar_y], fill=fg_color)
    # Right arm
    rax, ray = sc(152), sc(116)
    draw.ellipse([rax - lar_x, ray - lar_y, rax + lar_x, ray + lar_y], fill=fg_color)

    # Gun barrel (pointing up)
    gx = cx - sc(5)
    draw.rectangle(
        [gx, sc(58), gx + sc(10), sc(90)],
        fill=(26, 26, 26, 255),
    )
    # Gun body
    draw.rectangle(
        [cx - sc(8), sc(78), cx + sc(8), sc(98)],
        fill=(34, 34, 34, 255),
    )

    # Legs
    draw.ellipse(
        [sc(107) - sc(9), sc(140), sc(107) + sc(9), sc(164)],
        fill=fg_color,
    )
    draw.ellipse(
        [sc(149) - sc(9), sc(140), sc(149) + sc(9), sc(164)],
        fill=fg_color,
    )

    # ─── Crosshair (neon pink-red) ─────────────────────────────────────────
    neon = (255, 34, 68, 230)
    neon_dim = (255, 34, 68, 160)
    lw = max(1, int(sc(2.5)))

    # Outer ring
    r_out = sc(68)
    draw.ellipse(
        [cx - r_out, cy - r_out, cx + r_out, cy + r_out],
        outline=neon, width=lw,
    )

    # Inner ring
    r_in = sc(44)
    draw.ellipse(
        [cx - r_in, cy - r_in, cx + r_in, cy + r_in],
        outline=(255, 34, 68, 178), width=max(1, int(sc(1.5))),
    )

    # Crosshair lines
    def line(x1, y1, x2, y2, color=neon, width=None):
        draw.line([(sc(x1), sc(y1)), (sc(x2), sc(y2))], fill=color, width=width or lw)

    line(50, 128, 80, 128)
    line(176, 128, 206, 128)
    line(128, 50, 128, 80)
    line(128, 176, 128, 206)

    # Center dot
    r_dot = sc(3.5)
    draw.ellipse(
        [cx - r_dot, cy - r_dot, cx + r_dot, cy + r_dot],
        fill=neon,
    )

    # Tick marks on outer ring
    tick_w = max(1, int(sc(2)))
    line(128, 58, 128, 65, color=neon_dim, width=tick_w)
    line(128, 191, 128, 198, color=neon_dim, width=tick_w)
    line(58, 128, 65, 128, color=neon_dim, width=tick_w)
    line(191, 128, 198, 128, color=neon_dim, width=tick_w)

    # ─── Corner brackets (Door Kickers 2 tactical HUD) ─────────────────────
    bw = max(1, int(sc(2)))
    # top-left
    draw.line([(sc(30), sc(30)), (sc(50), sc(30))], fill=(255, 34, 68, 128), width=bw)
    draw.line([(sc(50), sc(30)), (sc(50), sc(50))], fill=(255, 34, 68, 128), width=bw)
    # top-right
    draw.line([(sc(226), sc(30)), (sc(206), sc(30))], fill=(255, 34, 68, 128), width=bw)
    draw.line([(sc(206), sc(30)), (sc(206), sc(50))], fill=(255, 34, 68, 128), width=bw)
    # bottom-left
    draw.line([(sc(30), sc(226)), (sc(50), sc(226))], fill=(255, 34, 68, 128), width=bw)
    draw.line([(sc(50), sc(226)), (sc(50), sc(206))], fill=(255, 34, 68, 128), width=bw)
    # bottom-right
    draw.line([(sc(226), sc(226)), (sc(206), sc(226))], fill=(255, 34, 68, 128), width=bw)
    draw.line([(sc(206), sc(226)), (sc(206), sc(206))], fill=(255, 34, 68, 128), width=bw)

    # Apply slight neon glow to the whole image at larger sizes
    if size >= 64:
        glow = img.filter(ImageFilter.GaussianBlur(radius=max(1, int(sc(1.5)))))
        img = Image.alpha_composite(glow, img)

    return img


def main():
    out_dir = os.path.join(BASE_DIR, "assets")
    os.makedirs(out_dir, exist_ok=True)

    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = []
    for size in sizes:
        print(f"  Rendering {size}x{size}...")
        im = draw_icon(size)
        images.append(im)

    # Save ICO (Windows multi-size icon)
    ico_path = os.path.join(out_dir, "icon.ico")
    images[0].save(
        ico_path,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=images[1:],
    )
    print(f"Saved: {ico_path}")

    # Save 256x256 PNG preview
    png_path = os.path.join(out_dir, "icon_preview.png")
    images[-1].save(png_path, format="PNG")
    print(f"Saved: {png_path}")

    # Also save docs screenshot for PR
    docs_dir = os.path.join(BASE_DIR, "docs", "screenshots")
    os.makedirs(docs_dir, exist_ok=True)
    screenshot_path = os.path.join(docs_dir, "issue-1736-exe-icon.png")
    images[-1].save(screenshot_path, format="PNG")
    print(f"Saved: {screenshot_path}")


if __name__ == "__main__":
    main()
