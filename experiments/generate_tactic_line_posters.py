#!/usr/bin/env python3
"""Generate ASVK-only Tactic Line poster variants for issue #1815.

The output is deterministic promotional artwork built from existing
repository assets. It intentionally does not touch Godot scenes or runtime
resources; the PNG files are standalone review assets.
"""

from __future__ import annotations

import math
import os
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "posters"

W = 1232
H = 706
TITLE = "Tactic Line"
CAPTION = "ASVK"

FONT_TITLE = ROOT / "assets" / "fonts" / "rye" / "Rye-Regular.ttf"
FONT_SANS = ROOT / "assets" / "fonts" / "neon" / "Comfortaa-Bold.ttf"

SPRITES = ROOT / "assets" / "sprites"
WEAPON_SPRITES = SPRITES / "weapons"
ASVK = WEAPON_SPRITES / "asvk_topdown.png"
FLASHLIGHT = SPRITES / "effects" / "flashlight_cone_18deg.png"


@dataclass(frozen=True)
class Palette:
    bg: tuple[int, int, int]
    floor: tuple[int, int, int]
    wall: tuple[int, int, int]
    accent: tuple[int, int, int]
    accent2: tuple[int, int, int]
    text: tuple[int, int, int]
    dark: tuple[int, int, int]


@dataclass(frozen=True)
class AsvkVariant:
    filename: str
    label: str
    seed: int
    center: tuple[int, int]
    scale: int
    angle: float
    glow: tuple[int, int, int]
    route_variant: int
    route_alpha: int
    node_alpha: int
    light_alpha: float
    brightness: float = 1.18
    contrast: float = 1.08
    caption_y: int = 588
    title_size: int = 106
    title_xy: tuple[int, int] = (70, 55)
    scanline_alpha: int = 10
    frame_alpha: int = 190


CQB = Palette(
    bg=(11, 9, 7),
    floor=(29, 29, 22),
    wall=(74, 62, 40),
    accent=(215, 54, 48),
    accent2=(218, 185, 86),
    text=(249, 236, 201),
    dark=(5, 4, 3),
)

ASVK_VARIANTS: tuple[AsvkVariant, ...] = (
    AsvkVariant("tactic_line_poster_close_quarters.png", "01 Close Quarters", 181701, (620, 382), 12, 0, (218, 185, 86), 0, 62, 132, 0.22),
    AsvkVariant("tactic_line_asvk_close_quarters_02.png", "02 Entry Line", 181702, (610, 372), 12, -2, (215, 54, 48), 1, 56, 122, 0.18),
    AsvkVariant("tactic_line_asvk_close_quarters_03.png", "03 Overwatch", 181703, (642, 390), 12, 2, (232, 198, 102), 2, 50, 116, 0.26),
    AsvkVariant("tactic_line_asvk_close_quarters_04.png", "04 Low Sweep", 181704, (622, 414), 11, -4, (186, 52, 48), 3, 46, 110, 0.15, caption_y=598),
    AsvkVariant("tactic_line_asvk_close_quarters_05.png", "05 High Cover", 181705, (604, 348), 12, 3, (218, 185, 86), 0, 58, 126, 0.20),
    AsvkVariant("tactic_line_asvk_close_quarters_06.png", "06 Gold Grid", 181706, (626, 376), 13, 0, (232, 204, 116), 1, 42, 116, 0.14, title_size=102),
    AsvkVariant("tactic_line_asvk_close_quarters_07.png", "07 Red Trace", 181707, (624, 384), 12, -1, (215, 54, 48), 2, 72, 148, 0.19, scanline_alpha=8),
    AsvkVariant("tactic_line_asvk_close_quarters_08.png", "08 Room Clear", 181708, (596, 394), 11, 4, (218, 185, 86), 3, 54, 124, 0.23),
    AsvkVariant("tactic_line_asvk_close_quarters_09.png", "09 Door Hold", 181709, (654, 370), 12, -3, (235, 216, 146), 0, 48, 112, 0.16),
    AsvkVariant("tactic_line_asvk_close_quarters_10.png", "10 Silent Lane", 181710, (618, 396), 12, 1, (174, 170, 132), 1, 38, 102, 0.11, brightness=1.12),
    AsvkVariant("tactic_line_asvk_close_quarters_11.png", "11 Hard Angle", 181711, (630, 360), 13, -2, (218, 185, 86), 2, 66, 136, 0.21, caption_y=604),
    AsvkVariant("tactic_line_asvk_close_quarters_12.png", "12 Cross Hall", 181712, (606, 404), 11, 2, (215, 54, 48), 3, 52, 120, 0.24),
    AsvkVariant("tactic_line_asvk_close_quarters_13.png", "13 Dark Map", 181713, (620, 384), 12, 0, (190, 160, 78), 0, 34, 96, 0.08, brightness=1.10, contrast=1.14),
    AsvkVariant("tactic_line_asvk_close_quarters_14.png", "14 Bright Steel", 181714, (640, 388), 12, 3, (236, 214, 132), 1, 60, 130, 0.28, brightness=1.26),
    AsvkVariant("tactic_line_asvk_close_quarters_15.png", "15 Red Corner", 181715, (612, 370), 12, -1, (215, 54, 48), 2, 44, 108, 0.12, frame_alpha=220),
    AsvkVariant("tactic_line_asvk_close_quarters_16.png", "16 Yellow Route", 181716, (628, 402), 11, 4, (218, 185, 86), 3, 76, 152, 0.20),
    AsvkVariant("tactic_line_asvk_close_quarters_17.png", "17 Tight Title", 181717, (626, 386), 12, 0, (232, 198, 102), 0, 50, 116, 0.17, title_size=98, title_xy=(76, 64)),
    AsvkVariant("tactic_line_asvk_close_quarters_18.png", "18 Far Wall", 181718, (638, 356), 11, -5, (215, 54, 48), 1, 42, 104, 0.18, caption_y=602),
    AsvkVariant("tactic_line_asvk_close_quarters_19.png", "19 Heavy Shadow", 181719, (600, 398), 12, 2, (206, 175, 84), 2, 36, 98, 0.10, contrast=1.18),
    AsvkVariant("tactic_line_asvk_close_quarters_20.png", "20 Final Select", 181720, (624, 378), 13, 0, (218, 185, 86), 3, 58, 126, 0.24, title_size=108),
)

POSTER_NAMES = [variant.filename for variant in ASVK_VARIANTS]

STALE_OUTPUTS = (
    "tactic_line_poster_neon_crossfire.png",
    "tactic_line_poster_red_black.png",
    "tactic_line_poster_blueprint.png",
    "tactic_line_single_asvk.png",
    "tactic_line_single_m16.png",
    "tactic_line_single_shotgun.png",
    "tactic_line_single_mini_uzi.png",
    "tactic_line_single_silenced_pistol.png",
    "tactic_line_single_revolver.png",
    "tactic_line_single_ak_gl.png",
    "tactic_line_single_makarov_pm.png",
    "tactic_line_multi_primary_rifles.png",
    "tactic_line_multi_sidearms.png",
    "tactic_line_multi_full_armory.png",
    "tactic_line_multi_precision_cell.png",
    "tactic_line_multi_breach_cell.png",
    "tactic_line_multi_quiet_entry.png",
    "tactic_line_multi_heavy_wall.png",
    "tactic_line_multi_compact_sweep.png",
    "tactic_line_multi_unlock_progression.png",
    "tactic_line_multi_balanced_loadout.png",
    "tactic_line_red_black_asvk.png",
    "tactic_line_red_black_loadout.png",
)


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size)


def rgba(color: tuple[int, int, int], alpha: int = 255) -> tuple[int, int, int, int]:
    return color[0], color[1], color[2], alpha


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)


def make_base(seed: int) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("RGBA", (W, H), rgba(CQB.bg))
    pix = img.load()
    center_x = W * 0.54
    center_y = H * 0.50
    max_dist = math.hypot(center_x, center_y)

    for y in range(H):
        gy = y / H
        for x in range(W):
            gx = x / W
            t = gx * 0.56 + gy * 0.44
            base = blend(CQB.bg, CQB.floor, min(1.0, t * 1.25))
            d = math.hypot(x - center_x, y - center_y) / max_dist
            shade = max(0.35, 1.0 - d * 0.95)
            noise = rng.randint(-7, 7)
            pix[x, y] = (
                max(0, min(255, int(base[0] * shade) + noise)),
                max(0, min(255, int(base[1] * shade) + noise)),
                max(0, min(255, int(base[2] * shade) + noise)),
                255,
            )

    return img


def overlay(img: Image.Image, layer: Image.Image, alpha: float = 1.0) -> None:
    if alpha < 1.0:
        layer = layer.copy()
        a = layer.getchannel("A")
        layer.putalpha(a.point(lambda v: int(v * alpha)))
    img.alpha_composite(layer)


def glow_line(
    img: Image.Image,
    xy: Iterable[tuple[float, float]],
    color: tuple[int, int, int],
    width: int,
    *,
    blur: int = 10,
    alpha: int = 180,
) -> None:
    points = list(xy)
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.line(points, fill=rgba(color, alpha), width=width + blur, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(blur))
    overlay(img, glow, 0.55)
    draw = ImageDraw.Draw(img)
    draw.line(points, fill=rgba(color, alpha), width=width, joint="curve")


def draw_room_grid(img: Image.Image, seed: int, *, grid_alpha: int) -> None:
    rng = random.Random(seed)
    draw = ImageDraw.Draw(img, "RGBA")

    rooms = [
        (86, 112, 350, 308),
        (312, 92, 618, 214),
        (574, 148, 882, 358),
        (805, 94, 1122, 288),
        (170, 350, 452, 610),
        (505, 395, 741, 620),
        (764, 365, 1115, 612),
    ]
    corridors = [
        (333, 181, 600, 232),
        (380, 275, 654, 329),
        (644, 280, 840, 335),
        (306, 326, 382, 430),
        (668, 336, 720, 438),
        (806, 311, 860, 432),
    ]

    for rect in rooms + corridors:
        draw.rectangle(rect, fill=rgba(CQB.floor, 198))

    for rect in rooms:
        draw.rectangle(rect, outline=rgba(CQB.wall, 210), width=8)
    for rect in corridors:
        draw.rectangle(rect, outline=rgba(CQB.wall, 120), width=3)

    for x in range(72, W, 44):
        draw.line((x, 62, x, H - 52), fill=rgba(CQB.accent2, grid_alpha), width=1)
    for y in range(66, H, 44):
        draw.line((54, y, W - 54, y), fill=rgba(CQB.accent2, grid_alpha), width=1)

    for _ in range(34):
        x = rng.randrange(80, W - 80)
        y = rng.randrange(90, H - 70)
        w = rng.randrange(14, 56)
        h = rng.randrange(8, 26)
        draw.rectangle((x, y, x + w, y + h), fill=rgba(CQB.wall, rng.randrange(82, 156)))


def draw_tactical_routes(img: Image.Image, seed: int, variant: int, route_alpha: int, node_alpha: int) -> None:
    rng = random.Random(seed)
    draw = ImageDraw.Draw(img, "RGBA")
    routes = [
        [(150, 500), (246, 462), (342, 472), (430, 392), (566, 398), (668, 314), (808, 332), (940, 250)],
        [(250, 204), (376, 234), (520, 216), (636, 284), (760, 260), (880, 310), (1018, 284)],
        [(190, 596), (324, 552), (480, 562), (626, 512), (762, 540), (936, 474), (1070, 506)],
        [(130, 142), (286, 164), (428, 132), (566, 172), (718, 136), (878, 178), (1054, 146)],
    ]

    for i, path in enumerate(routes):
        shifted = []
        for x, y in path:
            jitter_x = rng.randrange(-10, 11)
            jitter_y = rng.randrange(-8, 9)
            shifted.append((x + jitter_x, y + jitter_y + variant * (i % 2) * 5))
        color = CQB.accent if i % 2 else CQB.accent2
        width = 2 if i != variant % len(routes) else 3
        draw.line(shifted, fill=rgba(color, route_alpha), width=width)
        for x, y in shifted:
            radius = 5 if i == variant % len(routes) else 4
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=rgba(color, node_alpha), width=2)
            draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=rgba(color, node_alpha))


def add_flashlight_wash(img: Image.Image, alpha: float) -> None:
    if alpha <= 0:
        return
    cone = Image.open(FLASHLIGHT).convert("RGBA")
    cone = cone.resize((640, 640), Image.Resampling.BILINEAR)
    cone = cone.rotate(-34, expand=True, resample=Image.Resampling.BILINEAR)
    cone = ImageEnhance.Color(cone).enhance(0.4)
    cone = ImageEnhance.Brightness(cone).enhance(1.55)
    a = cone.getchannel("A").point(lambda v: int(v * alpha))
    cone.putalpha(a)
    img.alpha_composite(cone, (166, 120))


def add_scanlines(img: Image.Image, alpha: int, *, step: int = 5) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    for y in range(0, H, step):
        draw.line((0, y, W, y), fill=rgba(CQB.accent2, alpha), width=1)


def add_corner_frame(img: Image.Image, alpha: int, *, thick: int = 5) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    pad = 26
    length = 130
    for sx in (pad, W - pad):
        for sy in (pad, H - pad):
            xsign = 1 if sx == pad else -1
            ysign = 1 if sy == pad else -1
            draw.line((sx, sy, sx + xsign * length, sy), fill=rgba(CQB.accent, alpha), width=thick)
            draw.line((sx, sy, sx, sy + ysign * length), fill=rgba(CQB.accent, alpha), width=thick)


def draw_title(img: Image.Image, variant: AsvkVariant) -> None:
    title_font = font(FONT_TITLE, variant.title_size)
    draw = ImageDraw.Draw(img, "RGBA")
    bbox = draw.textbbox((0, 0), TITLE, font=title_font, stroke_width=4)
    text_w = bbox[2] - bbox[0]
    x, y = variant.title_xy

    glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    for off in range(14, 0, -3):
        glow_alpha = 20 + off * 8
        gd.text(
            (x, y),
            TITLE,
            font=title_font,
            fill=rgba(CQB.accent, glow_alpha),
            stroke_width=4 + off // 3,
            stroke_fill=rgba(CQB.accent, glow_alpha),
        )
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(8))
    overlay(img, glow_layer, 0.8)

    draw.text(
        (x, y),
        TITLE,
        font=title_font,
        fill=rgba(CQB.text),
        stroke_width=4,
        stroke_fill=rgba(CQB.dark),
    )

    underline_y = y + bbox[3] - bbox[1] + 18
    glow_line(
        img,
        [(x + 8, underline_y), (x + text_w - 8, underline_y)],
        CQB.accent,
        width=max(4, variant.title_size // 18),
        blur=10,
        alpha=220,
    )


def draw_caption(img: Image.Image, y: int) -> None:
    caption_font = font(FONT_SANS, 42)
    draw = ImageDraw.Draw(img, "RGBA")
    bbox = draw.textbbox((0, 0), CAPTION, font=caption_font, stroke_width=2)
    w = bbox[2] - bbox[0]
    x = W // 2 - w // 2

    glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow_layer)
    gd.text((x, y), CAPTION, font=caption_font, fill=rgba(CQB.accent2, 96), stroke_width=5, stroke_fill=rgba(CQB.accent2, 96))
    overlay(img, glow_layer.filter(ImageFilter.GaussianBlur(6)), 0.72)
    draw.text((x, y), CAPTION, font=caption_font, fill=rgba(CQB.text, 238), stroke_width=2, stroke_fill=rgba(CQB.dark, 250))


def load_asvk_sprite(variant: AsvkVariant) -> Image.Image:
    sprite = Image.open(ASVK).convert("RGBA")
    alpha = sprite.getchannel("A")
    rgb = ImageEnhance.Brightness(sprite.convert("RGB")).enhance(variant.brightness)
    rgb = ImageEnhance.Contrast(rgb).enhance(variant.contrast)
    sprite = rgb.convert("RGBA")
    sprite.putalpha(alpha)
    sprite = sprite.resize((sprite.width * variant.scale, sprite.height * variant.scale), Image.Resampling.NEAREST)
    if variant.angle:
        sprite = sprite.rotate(variant.angle, expand=True, resample=Image.Resampling.NEAREST)
    return sprite


def paste_asvk(img: Image.Image, variant: AsvkVariant) -> None:
    sprite = load_asvk_sprite(variant)
    x = int(variant.center[0] - sprite.width / 2)
    y = int(variant.center[1] - sprite.height / 2)
    mask = sprite.getchannel("A")

    glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    glow_sprite = Image.new("RGBA", sprite.size, rgba(variant.glow, 0))
    glow_sprite.putalpha(mask.filter(ImageFilter.GaussianBlur(16)).point(lambda v: int(v * 0.62)))
    glow_layer.alpha_composite(glow_sprite, (x, y))
    overlay(img, glow_layer, 0.72)

    shadow = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(6)).point(lambda v: int(v * 0.74)))
    img.alpha_composite(shadow, (x + 10, y + 16))
    img.alpha_composite(sprite, (x, y))


def poster_variant(variant: AsvkVariant) -> Image.Image:
    img = make_base(variant.seed)
    draw_room_grid(img, variant.seed + 1, grid_alpha=30)
    draw_tactical_routes(img, variant.seed + 2, variant.route_variant, variant.route_alpha, variant.node_alpha)
    add_flashlight_wash(img, variant.light_alpha)
    add_scanlines(img, variant.scanline_alpha)
    draw_title(img, variant)
    add_corner_frame(img, variant.frame_alpha)
    paste_asvk(img, variant)
    draw_caption(img, variant.caption_y)
    return img


def save_rgb(img: Image.Image, name: str) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    img.convert("RGB").save(path, optimize=True)
    return path


def make_contact_sheet(paths: list[Path]) -> Path:
    thumb_w = 300
    thumb_h = int(thumb_w * H / W)
    pad = 22
    label_h = 42
    cols = 5
    rows = 4
    sheet = Image.new("RGB", (thumb_w * cols + pad * (cols + 1), (thumb_h + label_h) * rows + pad * (rows + 1)), (8, 8, 8))
    draw = ImageDraw.Draw(sheet)
    label_font = font(FONT_SANS, 18)

    for i, path in enumerate(paths):
        row = i // cols
        col = i % cols
        x = pad + col * (thumb_w + pad)
        y = pad + row * (thumb_h + label_h + pad)
        poster = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        sheet.paste(poster, (x, y))
        draw.rectangle((x, y, x + thumb_w, y + thumb_h), outline=CQB.accent, width=2)
        draw.text((x, y + thumb_h + 10), ASVK_VARIANTS[i].label, font=label_font, fill=(236, 236, 218))

    out = OUT_DIR / "tactic_line_poster_contact_sheet.png"
    sheet.save(out, optimize=True)
    return out


def remove_stale_outputs() -> None:
    for filename in STALE_OUTPUTS:
        path = OUT_DIR / filename
        if path.exists():
            path.unlink()


def generate_posters() -> list[Path]:
    remove_stale_outputs()
    outputs = [save_rgb(poster_variant(variant), variant.filename) for variant in ASVK_VARIANTS]
    make_contact_sheet(outputs)
    return outputs


def main() -> None:
    os.chdir(ROOT)
    outputs = generate_posters()
    for path in outputs + [OUT_DIR / "tactic_line_poster_contact_sheet.png"]:
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
