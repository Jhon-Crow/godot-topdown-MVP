#!/usr/bin/env python3
"""Generate poster variants for issue #1815.

The script builds deterministic promotional art from existing repository
sprites and fonts. It intentionally does not touch any Godot scene or game
resource reference; the output PNG files are standalone assets.
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

FONT_TITLE = ROOT / "assets" / "fonts" / "neon" / "Comfortaa-Bold.ttf"
FONT_NEON = ROOT / "assets" / "fonts" / "neon" / "Beon-Regular.ttf"
FONT_ACCENT = ROOT / "assets" / "fonts" / "rye" / "Rye-Regular.ttf"

SPRITES = ROOT / "assets" / "sprites"
PLAYER = SPRITES / "characters" / "player" / "player_combined_preview.png"
ENEMY = SPRITES / "characters" / "enemy" / "enemy_combined_preview.png"
M16 = SPRITES / "weapons" / "m16_rifle_topdown.png"
SHOTGUN = SPRITES / "weapons" / "shotgun_topdown.png"
REVOLVER = SPRITES / "weapons" / "revolver_topdown.png"
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


NEON = Palette(
    bg=(5, 8, 11),
    floor=(15, 26, 28),
    wall=(43, 62, 58),
    accent=(232, 61, 72),
    accent2=(74, 226, 188),
    text=(245, 246, 230),
    dark=(3, 5, 7),
)

BLUEPRINT = Palette(
    bg=(4, 13, 24),
    floor=(10, 31, 46),
    wall=(34, 78, 99),
    accent=(244, 171, 54),
    accent2=(80, 210, 229),
    text=(235, 248, 252),
    dark=(2, 8, 14),
)

CQB = Palette(
    bg=(11, 9, 7),
    floor=(29, 29, 22),
    wall=(74, 62, 40),
    accent=(215, 54, 48),
    accent2=(218, 185, 86),
    text=(249, 236, 201),
    dark=(5, 4, 3),
)

RED_BLACK = Palette(
    bg=(0, 0, 0),
    floor=(15, 0, 0),
    wall=(63, 0, 0),
    accent=(255, 0, 0),
    accent2=(255, 0, 0),
    text=(255, 0, 0),
    dark=(0, 0, 0),
)


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size)


def rgba(color: tuple[int, int, int], alpha: int = 255) -> tuple[int, int, int, int]:
    return color[0], color[1], color[2], alpha


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def blend(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)


def make_base(pal: Palette, seed: int, vignette: bool = True) -> Image.Image:
    rng = random.Random(seed)
    img = Image.new("RGBA", (W, H), rgba(pal.bg))
    pix = img.load()
    center_x = W * 0.54
    center_y = H * 0.50
    max_dist = math.hypot(center_x, center_y)

    for y in range(H):
        gy = y / H
        for x in range(W):
            gx = x / W
            t = (gx * 0.56 + gy * 0.44)
            base = blend(pal.bg, pal.floor, min(1.0, t * 1.25))
            noise = rng.randint(-7, 7)
            if vignette:
                d = math.hypot(x - center_x, y - center_y) / max_dist
                shade = max(0.35, 1.0 - d * 0.95)
            else:
                shade = 1.0
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
    blur: int = 12,
    alpha: int = 255,
) -> None:
    points = list(xy)
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.line(points, fill=rgba(color, alpha), width=width + blur, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(blur))
    overlay(img, glow, 0.65)
    draw = ImageDraw.Draw(img)
    draw.line(points, fill=rgba(color, alpha), width=width, joint="curve")


def draw_room_grid(img: Image.Image, pal: Palette, seed: int, red_black: bool = False) -> None:
    rng = random.Random(seed)
    draw = ImageDraw.Draw(img, "RGBA")

    if red_black:
        floor_fill = (10, 0, 0, 255)
        wall_fill = (105, 0, 0, 255)
        line_fill = (255, 0, 0, 45)
    else:
        floor_fill = rgba(pal.floor, 198)
        wall_fill = rgba(pal.wall, 210)
        line_fill = rgba(pal.accent2, 30)

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
        draw.rectangle(rect, fill=floor_fill)

    for rect in rooms:
        draw.rectangle(rect, outline=wall_fill, width=8)
    for rect in corridors:
        draw.rectangle(rect, outline=rgba(pal.wall, 120), width=3)

    for x in range(72, W, 44):
        draw.line((x, 62, x, H - 52), fill=line_fill, width=1)
    for y in range(66, H, 44):
        draw.line((54, y, W - 54, y), fill=line_fill, width=1)

    for _ in range(34):
        x = rng.randrange(80, W - 80)
        y = rng.randrange(90, H - 70)
        w = rng.randrange(14, 56)
        h = rng.randrange(8, 26)
        fill = rgba(pal.wall if not red_black else (120, 0, 0), rng.randrange(92, 170))
        draw.rectangle((x, y, x + w, y + h), fill=fill)


def paste_sprite(
    img: Image.Image,
    path: Path,
    center: tuple[int, int],
    scale: int,
    angle: float,
    tint: tuple[int, int, int] | None = None,
    alpha: int = 255,
) -> None:
    sprite = Image.open(path).convert("RGBA")
    if tint is not None:
        alpha_channel = sprite.getchannel("A")
        gray = sprite.convert("L")
        tinted = Image.new("RGBA", sprite.size, rgba(tint, 0))
        tinted.putalpha(alpha_channel.point(lambda v: min(alpha, v)))
        sprite = Image.composite(tinted, sprite, gray.point(lambda v: 255 if v > 8 else 0))
    elif alpha != 255:
        a = sprite.getchannel("A")
        sprite.putalpha(a.point(lambda v: int(v * alpha / 255)))

    sprite = sprite.resize((sprite.width * scale, sprite.height * scale), Image.Resampling.NEAREST)
    sprite = sprite.rotate(angle, expand=True, resample=Image.Resampling.NEAREST)

    shadow = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    shadow.putalpha(sprite.getchannel("A").filter(ImageFilter.GaussianBlur(6)))
    x = int(center[0] - sprite.width / 2)
    y = int(center[1] - sprite.height / 2)
    img.alpha_composite(shadow, (x + 10, y + 16))
    img.alpha_composite(sprite, (x, y))


def draw_title(
    img: Image.Image,
    pal: Palette,
    xy: tuple[int, int],
    size: int,
    align: str = "left",
    glow: bool = True,
    font_path: Path = FONT_TITLE,
    stroke: int = 3,
) -> None:
    title_font = font(font_path, size)
    draw = ImageDraw.Draw(img, "RGBA")
    bbox = draw.textbbox((0, 0), TITLE, font=title_font, stroke_width=stroke)
    text_w = bbox[2] - bbox[0]
    x, y = xy
    if align == "center":
        x -= text_w // 2
    elif align == "right":
        x -= text_w

    if glow:
        glow_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow_layer)
        for off in range(14, 0, -3):
            gd.text(
                (x, y),
                TITLE,
                font=title_font,
                fill=rgba(pal.accent, 20 + off * 8),
                stroke_width=stroke + off // 3,
                stroke_fill=rgba(pal.accent, 20 + off * 8),
            )
        glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(8))
        overlay(img, glow_layer, 0.8)

    draw.text(
        (x, y),
        TITLE,
        font=title_font,
        fill=rgba(pal.text),
        stroke_width=stroke,
        stroke_fill=rgba(pal.dark),
    )

    underline_y = y + bbox[3] - bbox[1] + 18
    glow_line(
        img,
        [(x + 8, underline_y), (x + text_w - 8, underline_y)],
        pal.accent,
        width=max(4, size // 18),
        blur=10,
        alpha=220,
    )


def draw_weapon_badge(
    img: Image.Image,
    path: Path,
    center: tuple[int, int],
    scale: int,
    angle: float,
    pal: Palette,
) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    cx, cy = center
    draw.rounded_rectangle(
        (cx - 108, cy - 42, cx + 108, cy + 42),
        radius=8,
        fill=rgba(pal.dark, 160),
        outline=rgba(pal.accent2, 120),
        width=2,
    )
    paste_sprite(img, path, center, scale, angle)


def add_scanlines(img: Image.Image, color: tuple[int, int, int], alpha: int = 28, step: int = 5) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    for y in range(0, H, step):
        draw.line((0, y, W, y), fill=rgba(color, alpha), width=1)


def add_corner_frame(img: Image.Image, pal: Palette, thick: int = 5) -> None:
    draw = ImageDraw.Draw(img, "RGBA")
    pad = 26
    length = 130
    for sx in (pad, W - pad):
        for sy in (pad, H - pad):
            xsign = 1 if sx == pad else -1
            ysign = 1 if sy == pad else -1
            draw.line((sx, sy, sx + xsign * length, sy), fill=rgba(pal.accent, 190), width=thick)
            draw.line((sx, sy, sx, sy + ysign * length), fill=rgba(pal.accent, 190), width=thick)


def poster_neon_crossfire() -> Image.Image:
    img = make_base(NEON, 181501)
    draw_room_grid(img, NEON, 181502)

    glow_line(img, [(205, 515), (374, 402), (595, 352), (837, 238), (1052, 166)], NEON.accent2, 6, 16, 210)
    glow_line(img, [(1006, 506), (828, 432), (612, 392), (390, 281), (180, 180)], NEON.accent, 5, 14, 210)
    glow_line(img, [(285, 500), (472, 486), (636, 430), (818, 374), (1000, 358)], (248, 221, 90), 3, 10, 180)

    paste_sprite(img, PLAYER, (284, 495), 5, -28)
    paste_sprite(img, ENEMY, (1001, 170), 4, 148)
    paste_sprite(img, ENEMY, (915, 490), 3, 204)
    paste_sprite(img, PLAYER, (620, 346), 3, -8, alpha=220)

    draw_weapon_badge(img, M16, (973, 606), 5, -11, NEON)
    draw_weapon_badge(img, REVOLVER, (740, 113), 5, 21, NEON)

    add_scanlines(img, NEON.accent2, 8, 8)
    draw_title(img, NEON, (72, 54), 108, "left", True)
    add_corner_frame(img, NEON)
    return img


def poster_red_black() -> Image.Image:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    draw_room_grid(img, RED_BLACK, 181503, red_black=True)
    draw = ImageDraw.Draw(img, "RGBA")

    for x in range(-250, W + 250, 80):
        draw.line((x, 0, x + 390, H), fill=(80, 0, 0, 90), width=10)
    for y in range(85, H, 75):
        draw.line((0, y, W, y), fill=(255, 0, 0, 38), width=2)

    glow_line(img, [(174, 548), (368, 437), (620, 350), (846, 248), (1085, 156)], RED_BLACK.accent, 11, 18, 255)
    glow_line(img, [(1058, 551), (872, 452), (656, 376), (408, 284), (150, 154)], RED_BLACK.accent, 5, 8, 210)

    paste_sprite(img, PLAYER, (218, 526), 7, -30, tint=RED_BLACK.accent)
    paste_sprite(img, ENEMY, (1008, 155), 6, 150, tint=RED_BLACK.accent)
    paste_sprite(img, ENEMY, (916, 518), 4, 198, tint=(110, 0, 0))
    paste_sprite(img, M16, (582, 344), 7, -7, tint=RED_BLACK.accent)

    title_font = font(FONT_TITLE, 118)
    bbox = draw.textbbox((0, 0), TITLE, font=title_font, stroke_width=2)
    title_w = bbox[2] - bbox[0]
    title_x = (W - title_w) // 2
    title_y = 62
    for off in (18, 12, 7):
        draw.text(
            (title_x, title_y),
            TITLE,
            font=title_font,
            fill=(255, 0, 0, 30),
            stroke_width=off,
            stroke_fill=(255, 0, 0, 24),
        )
    draw.text(
        (title_x, title_y),
        TITLE,
        font=title_font,
        fill=(255, 0, 0, 255),
        stroke_width=3,
        stroke_fill=(0, 0, 0, 255),
    )
    draw.rectangle((title_x + 4, title_y + 136, title_x + title_w - 4, title_y + 148), fill=(255, 0, 0, 255))

    add_corner_frame(img, RED_BLACK, thick=7)
    img = to_red_black(img)
    return img


def poster_blueprint() -> Image.Image:
    img = make_base(BLUEPRINT, 181504, vignette=False)
    draw_room_grid(img, BLUEPRINT, 181505)
    draw = ImageDraw.Draw(img, "RGBA")

    for r in (78, 128, 182, 246, 318):
        draw.ellipse((W // 2 - r, H // 2 - r, W // 2 + r, H // 2 + r), outline=rgba(BLUEPRINT.accent2, 36), width=2)
    for angle in range(0, 360, 15):
        a = math.radians(angle)
        draw.line(
            (W // 2, H // 2, W // 2 + math.cos(a) * 620, H // 2 + math.sin(a) * 620),
            fill=rgba(BLUEPRINT.accent2, 22),
            width=1,
        )

    path = [(156, 514), (288, 464), (456, 403), (604, 348), (750, 316), (948, 218), (1080, 188)]
    glow_line(img, path, BLUEPRINT.accent, 4, 10, 230)
    for point in path:
        draw.ellipse((point[0] - 10, point[1] - 10, point[0] + 10, point[1] + 10), fill=rgba(BLUEPRINT.accent, 220))

    paste_sprite(img, PLAYER, (156, 514), 5, -38)
    paste_sprite(img, ENEMY, (1080, 188), 4, 145)
    paste_sprite(img, ENEMY, (762, 318), 3, 110, alpha=210)
    paste_sprite(img, SHOTGUN, (480, 545), 6, 12)
    paste_sprite(img, REVOLVER, (965, 510), 6, -24)

    add_scanlines(img, BLUEPRINT.accent2, 9, 7)
    draw_title(img, BLUEPRINT, (616, 52), 102, "center", True, FONT_NEON, stroke=2)
    add_corner_frame(img, BLUEPRINT, thick=4)
    return img


def poster_close_quarters() -> Image.Image:
    img = make_base(CQB, 181506)
    draw_room_grid(img, CQB, 181507)

    cone = Image.open(FLASHLIGHT).convert("RGBA")
    cone = cone.resize((640, 640), Image.Resampling.BILINEAR)
    cone = cone.rotate(-34, expand=True, resample=Image.Resampling.BILINEAR)
    cone = ImageEnhance.Color(cone).enhance(0.4)
    cone = ImageEnhance.Brightness(cone).enhance(1.55)
    a = cone.getchannel("A").point(lambda v: int(v * 0.25))
    cone.putalpha(a)
    img.alpha_composite(cone, (166, 120))

    glow_line(img, [(258, 500), (438, 430), (636, 355), (810, 306), (1004, 250)], CQB.accent2, 7, 18, 220)
    glow_line(img, [(1015, 240), (878, 296), (714, 334), (535, 416), (350, 542)], CQB.accent, 4, 12, 190)
    glow_line(img, [(328, 225), (480, 282), (620, 330), (812, 396), (1000, 466)], (230, 90, 70), 3, 9, 150)

    paste_sprite(img, PLAYER, (257, 499), 7, -31)
    paste_sprite(img, ENEMY, (1015, 240), 6, 150)
    paste_sprite(img, ENEMY, (790, 468), 4, 215)
    paste_sprite(img, M16, (604, 160), 7, 15)
    paste_sprite(img, SHOTGUN, (910, 586), 6, -18)

    draw_title(img, CQB, (70, 55), 106, "left", True, FONT_ACCENT, stroke=4)
    add_corner_frame(img, CQB, thick=5)
    return img


def to_red_black(img: Image.Image) -> Image.Image:
    result = Image.new("RGBA", img.size, (0, 0, 0, 255))
    src = img.convert("RGBA").load()
    dst = result.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = src[x, y]
            if a == 0:
                dst[x, y] = (0, 0, 0, 255)
                continue
            if r > 28 or (r + g + b) > 45:
                dst[x, y] = (255, 0, 0, 255)
            else:
                dst[x, y] = (0, 0, 0, 255)
    return result


def save_rgb(img: Image.Image, name: str) -> Path:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    img.convert("RGB").save(path, optimize=True)
    return path


def make_contact_sheet(paths: list[Path]) -> Path:
    thumb_w = 560
    thumb_h = int(thumb_w * H / W)
    pad = 34
    label_h = 46
    sheet = Image.new("RGB", (thumb_w * 2 + pad * 3, (thumb_h + label_h) * 2 + pad * 3), (8, 8, 8))
    draw = ImageDraw.Draw(sheet)
    label_font = font(FONT_TITLE, 24)
    labels = [
        "Neon Crossfire",
        "Red / Black",
        "Blueprint Route",
        "Close Quarters",
    ]
    for i, path in enumerate(paths):
        row = i // 2
        col = i % 2
        x = pad + col * (thumb_w + pad)
        y = pad + row * (thumb_h + label_h + pad)
        poster = Image.open(path).convert("RGB").resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        sheet.paste(poster, (x, y))
        draw.rectangle((x, y, x + thumb_w, y + thumb_h), outline=(210, 40, 50), width=2)
        draw.text((x, y + thumb_h + 12), labels[i], font=label_font, fill=(236, 236, 218))
    out = OUT_DIR / "tactic_line_poster_contact_sheet.png"
    sheet.save(out, optimize=True)
    return out


def main() -> None:
    os.chdir(ROOT)
    outputs = [
        save_rgb(poster_neon_crossfire(), "tactic_line_poster_neon_crossfire.png"),
        save_rgb(poster_red_black(), "tactic_line_poster_red_black.png"),
        save_rgb(poster_blueprint(), "tactic_line_poster_blueprint.png"),
        save_rgb(poster_close_quarters(), "tactic_line_poster_close_quarters.png"),
    ]
    outputs.append(make_contact_sheet(outputs))
    for path in outputs:
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
