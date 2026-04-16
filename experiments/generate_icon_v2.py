#!/usr/bin/env python3
"""
Generate a Hotline Miami / Door Kickers 2 style icon for the game's .exe
Produces a proper multi-size ICO file using PNG compression inside ICO container.
"""
import io
import os
import struct
from PIL import Image, ImageDraw, ImageFilter

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def draw_icon(size: int) -> Image.Image:
    """Draw the icon at the given square size."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    s = size / 256.0  # scale factor

    def sc(v):
        return v * s

    cx, cy = size / 2, size / 2

    # ─── Background (dark circle) ───────────────────────────────────────────
    r_bg = int(size / 2)
    for r in range(r_bg, 0, -max(1, r_bg // 60)):
        t = r / r_bg
        dark = int(13 + t * 13)  # 0x0d to 0x1a
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(dark, dark, dark + 14, 255),
        )

    # ─── Blood splash dots (Hotline Miami energy) ──────────────────────────
    if size >= 32:
        splats = [
            (60, 55, 6, 0.18),
            (195, 70, 4, 0.12),
            (45, 185, 5, 0.15),
            (210, 195, 7, 0.10),
            (170, 40, 3, 0.20),
        ]
        for sx, sy, sr, alpha in splats:
            x, y, r = sc(sx), sc(sy), max(1, sc(sr))
            a = int(255 * alpha)
            draw.ellipse([x - r, y - r, x + r, y + r], fill=(255, 34, 68, a))

    # ─── Top-down figure ───────────────────────────────────────────────────
    fg = (17, 17, 17, 255)

    # Torso
    tx, ty = cx, sc(122)
    trx, try_ = max(2, sc(18)), max(3, sc(26))
    draw.ellipse([tx - trx, ty - try_, tx + trx, ty + try_], fill=fg)

    # Head
    hx, hy = cx, sc(92)
    hr = max(2, sc(14))
    draw.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(15, 15, 15, 255))

    # Arms
    if size >= 32:
        lax, lay = sc(104), sc(116)
        arx, ary = max(1, sc(8)), max(1, sc(5))
        draw.ellipse([lax - arx, lay - ary, lax + arx, lay + ary], fill=fg)
        rax, ray = sc(152), sc(116)
        draw.ellipse([rax - arx, ray - ary, rax + arx, ray + ary], fill=fg)

    # Gun barrel
    draw.rectangle(
        [cx - sc(5), sc(58), cx + sc(5), sc(90)],
        fill=(26, 26, 26, 255),
    )

    # Legs
    lx1, lx2 = sc(116), sc(140)
    ly1, ly2 = sc(140), sc(164)
    lr = max(1, sc(9))
    draw.ellipse([lx1 - lr, ly1, lx1 + lr, ly2], fill=fg)
    draw.ellipse([lx2 - lr, ly1, lx2 + lr, ly2], fill=fg)

    # ─── Crosshair (neon red) ──────────────────────────────────────────────
    neon = (255, 34, 68, 230)
    neon_dim = (255, 34, 68, 140)
    lw = max(1, int(sc(2.5)))

    # Outer ring
    r_out = sc(68)
    draw.ellipse(
        [cx - r_out, cy - r_out, cx + r_out, cy + r_out],
        outline=neon, width=lw,
    )

    # Inner ring
    if size >= 32:
        r_in = sc(44)
        draw.ellipse(
            [cx - r_in, cy - r_in, cx + r_in, cy + r_in],
            outline=(255, 34, 68, 160), width=max(1, int(sc(1.5))),
        )

    # Crosshair lines
    def line(x1, y1, x2, y2, col=neon, w=None):
        draw.line(
            [(sc(x1), sc(y1)), (sc(x2), sc(y2))],
            fill=col,
            width=w or lw,
        )

    line(50, 128, 80, 128)
    line(176, 128, 206, 128)
    line(128, 50, 128, 80)
    line(128, 176, 128, 206)

    # Center dot
    r_dot = max(1, sc(3.5))
    draw.ellipse([cx - r_dot, cy - r_dot, cx + r_dot, cy + r_dot], fill=neon)

    # Corner brackets (tactical HUD)
    if size >= 48:
        bw = max(1, int(sc(2)))
        for bx1, by1, bx2, by2 in [
            (30, 30, 50, 50),
            (226, 30, 206, 50),
            (30, 226, 50, 206),
            (226, 226, 206, 206),
        ]:
            mx = (bx1 + bx2) / 2
            my = (by1 + by2) / 2
            draw.line([(sc(bx1), sc(by1)), (sc(mx), sc(by1))], fill=neon_dim, width=bw)
            draw.line([(sc(mx), sc(by1)), (sc(mx), sc(my))], fill=neon_dim, width=bw)

    # Glow at larger sizes
    if size >= 64:
        radius = max(1, int(sc(1.5)))
        glow = img.filter(ImageFilter.GaussianBlur(radius=radius))
        img = Image.alpha_composite(glow, img)

    return img


def draw_small_icon(size: int) -> Image.Image:
    """Draw a pixel-aligned icon for Windows Explorer's smallest slots."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    center = size // 2
    bg = (0, 0, 0, 255)
    neon = (255, 34, 68, 255)
    figure = (10, 10, 12, 255)

    margin = 1
    draw.ellipse(
        [margin, margin, size - margin - 1, size - margin - 1],
        fill=bg,
    )

    ring_margin = max(2, size // 5)
    draw.ellipse(
        [ring_margin, ring_margin, size - ring_margin - 1, size - ring_margin - 1],
        outline=neon,
        width=1,
    )

    arm_y = center - 1
    draw.line([(center - 4, arm_y), (center + 4, arm_y)], fill=figure, width=2)
    draw.rectangle([center - 1, center - 6, center + 1, center + 1], fill=figure)
    draw.ellipse([center - 2, center - 5, center + 2, center - 1], fill=figure)
    draw.rectangle([center - 2, center - 1, center + 2, center + 4], fill=figure)
    draw.point((center, center), fill=neon)

    if size >= 24:
        draw.line([(center, ring_margin - 1), (center, ring_margin + 2)], fill=neon)
        draw.line([(center, size - ring_margin - 3), (center, size - ring_margin)], fill=neon)
        draw.line([(ring_margin - 1, center), (ring_margin + 2, center)], fill=neon)
        draw.line([(size - ring_margin - 3, center), (size - ring_margin, center)], fill=neon)

    return img


def save_ico_proper(images, path):
    """Save a proper multi-size ICO with PNG-compressed entries (ICNS-style)."""
    # ICO format: header + directory + image data
    # Use PNG-compressed entries for sizes >= 32 (Vista+ ICO)
    num = len(images)
    header = struct.pack("<HHH", 0, 1, num)  # reserved, type=1 (ICO), count

    entries = []
    img_data_list = []

    for img in images:
        w, h = img.size
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        data = buf.getvalue()
        img_data_list.append(data)
        # Directory entry: width(1), height(1), color_count(1), reserved(1),
        #                  planes(2), bit_count(2), size(4), offset(4)
        # width/height 0 means 256
        icon_w = w if w < 256 else 0
        icon_h = h if h < 256 else 0
        entries.append((icon_w, icon_h, 0, 0, 1, 32, len(data)))

    # Calculate offsets
    header_size = 6
    dir_entry_size = 16
    dir_size = dir_entry_size * num
    offset = header_size + dir_size

    with open(path, "wb") as f:
        f.write(header)
        offsets = []
        for icon_w, icon_h, cc, res, planes, bpp, size in entries:
            f.write(struct.pack(
                "<BBBBHHII",
                icon_w, icon_h, cc, res,
                planes, bpp, size, offset,
            ))
            offsets.append(offset)
            offset += size
        for data in img_data_list:
            f.write(data)


def main():
    out_dir = os.path.join(BASE_DIR, "assets")
    os.makedirs(out_dir, exist_ok=True)

    sizes = [16, 24, 32, 48, 64, 128, 256]
    images = []
    for size in sizes:
        print(f"  Rendering {size}x{size}...")
        im = draw_small_icon(size) if size <= 32 else draw_icon(size)
        images.append(im)

    # Save proper multi-size ICO
    ico_path = os.path.join(out_dir, "icon.ico")
    save_ico_proper(images, ico_path)
    print(f"Saved: {ico_path} ({os.path.getsize(ico_path)} bytes)")

    # Save 256x256 PNG preview
    png_path = os.path.join(out_dir, "icon_preview.png")
    images[-1].save(png_path, format="PNG")
    print(f"Saved: {png_path}")

    # Save docs screenshot for PR
    docs_dir = os.path.join(BASE_DIR, "docs", "screenshots")
    os.makedirs(docs_dir, exist_ok=True)
    screenshot_path = os.path.join(docs_dir, "issue-1736-exe-icon.png")
    images[-1].save(screenshot_path, format="PNG")
    print(f"Saved: {screenshot_path}")

    # Verify ICO
    ico_check = Image.open(ico_path)
    print(f"ICO format verified: {ico_check.format}, size: {ico_check.size}")


if __name__ == "__main__":
    main()
