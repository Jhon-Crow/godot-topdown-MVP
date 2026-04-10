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

- `export_presets.cfg`: `application/icon` set to `res://assets/icon.ico`, `application/modify_resources=true`
- `icon.svg`: Updated root project icon (used by Godot editor, taskbar, window title)
- `assets/icon.ico`: Multi-size Windows ICO (16, 24, 32, 48, 64, 128, 256 px)
- `.github/workflows/build-windows.yml`: Installs Wine and passes `wine_path` to `firebelley/godot-export`

---

## Root Cause: EXE Still Shows Default Icon

### First Fix (session 1)
Only `assets/icon.ico` was added and `export_presets.cfg` was updated, but the root `icon.svg`
was still the default Godot blue triangle. This caused the running game to show the default icon
in the taskbar/window title.

**Fix**: Updated root `icon.svg` with the custom design.

### Second Issue (reported by Jhon-Crow on 2026-03-30)
"значок запущенной игры правильный, но у самого exe всё ещё дэфолтный"
(The running game icon is correct, but the exe file itself still has the default icon)

**Root Cause**: Godot uses the `rcedit` tool to embed the ICO into the Windows EXE binary during
export. On Linux/CI, rcedit can only run via **Wine** (since rcedit is a Windows-only tool).

The CI workflow (`build-windows.yml`) was using `firebelley/godot-export@v7.0.0` but did **not**:
1. Install Wine on the Ubuntu runner
2. Pass `wine_path` to the action

Without Wine, Godot silently skips the rcedit step, leaving the EXE with the default icon even
though `export_presets.cfg` has `application/icon="res://assets/icon.ico"` configured.

**Fix**: Added Wine installation step and `wine_path` parameter to the CI workflow.

### How Godot EXE Icon Works
1. During Windows export, Godot calls `rcedit` to patch the EXE binary
2. `rcedit` is a Windows-only tool — on Linux/macOS it must be run through Wine
3. Godot's Editor Settings has `Export > Windows > rcedit` path setting
4. The `firebelley/godot-export` action exposes a `wine_path` input that configures this
5. If Wine is not available, rcedit is skipped and the EXE keeps the default icon

---

## References

- Hotline Miami visual design: https://en.wikipedia.org/wiki/Hotline_Miami
- Door Kickers 2 tactical aesthetic: https://en.wikipedia.org/wiki/Door_Kickers_2
- Godot export icon docs: https://docs.godotengine.org/en/stable/tutorials/export/changing_application_icon_for_windows.html
- firebelley/godot-export action: https://github.com/firebelley/godot-export
- rcedit Wine issue: https://github.com/godotengine/godot/issues/14441
- Reddit discussion on exe icon: https://www.reddit.com/r/godot/comments/j8tka9/how_do_you_change_the_exe_files_icon_the_taskbar/
