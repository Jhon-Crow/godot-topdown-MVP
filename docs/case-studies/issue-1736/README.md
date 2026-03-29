# Case Study: Issue #1736 — Add Icon to EXE

## Issue Summary

Add an application icon to the Windows `.exe` that conveys the game's aesthetic, similar to **Hotline Miami (1 & 2)** and **Door Kickers 2**.

---

## Reference Games Visual Analysis

### Hotline Miami 1 & 2
- **Genre**: Top-down shooter, ultra-violent action
- **Aesthetic**: Neon pink/purple/cyan palette, dark noir atmosphere, pixelated sprites
- **Visual motifs**: Animal masks, splattered blood, dark geometric shapes, bold silhouettes
- **Color palette**: Hot pink (#FF006E), electric purple (#9900FF), cyan (#00FFFF), black, neon yellow
- **Typography**: Bold, sharp, retro-digital
- **Icon mood**: Intense, threatening, minimal-yet-striking

### Door Kickers 2
- **Genre**: Real-time tactical top-down
- **Aesthetic**: Military/tactical, muted greens and browns, clean operational imagery
- **Visual motifs**: Soldier silhouettes, breaching doors, crosshairs, tactical gear
- **Color palette**: Dark olive green, military tan, black, white
- **Icon mood**: Professional, tactical, precise

---

## Design Decisions for This Game's Icon

This game is described as a **Godot Top-Down Template** with a shooter focus. The icon should:

1. Combine HM's **neon/dark contrast** with DK2's **top-down perspective**
2. Use a **masked/silhouetted figure** (top-down view) aiming
3. Employ **dark background** with **neon accent color** (hot pink/purple)
4. Include **crosshair or aim indicator** for the top-down shooter feel
5. Be **readable at small sizes** (16x16 up to 256x256)

---

## Chosen Design

A top-down silhouette of a figure (player character) in black on a dark background, with a bright neon crosshair overlay and a splash of color — referencing HM's violent energy.

- Background: Near-black dark (#1A1A2E)
- Figure: Black silhouette of a person viewed from above
- Crosshair: Neon pink-red (#FF2244)
- Glow/accent: Subtle neon purple outline

This is stored as:
- `assets/icon.svg` — vector source
- `assets/icon.ico` — Windows ICO (multi-size: 16, 32, 48, 64, 128, 256)

---

## Implementation

- `export_presets.cfg`: `application/icon` set to `res://assets/icon.ico`
- `icon.svg`: Updated root project icon (Godot editor icon)

---

## References

- Hotline Miami visual design: https://en.wikipedia.org/wiki/Hotline_Miami
- Door Kickers 2 tactical aesthetic: https://en.wikipedia.org/wiki/Door_Kickers_2
- Godot export icon docs: https://docs.godotengine.org/en/stable/tutorials/export/feature_tags.html
