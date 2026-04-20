# Case Study: Issue #1742 — Update Difficulty Menu (Стрелок/Gunslinger Button Styling)

## Issue Summary

**Title:** update сложности  
**Reported by:** Jhon-Crow  
**Issue URL:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1742

### Requirements

1. Make the **Стрелок** (Gunslinger) difficulty button have a **glowing red background**.
2. Apply a **cowboy-style font** to the Стрелок button that supports **both Russian and English**.
3. Include a screenshot of the result in the issue comments.

---

## Codebase Analysis

### Relevant Files

| File | Role |
|------|------|
| `scenes/ui/DifficultyMenu.tscn` | Scene definition for the difficulty selection menu |
| `scripts/ui/difficulty_menu.gd` | Script handling all difficulty button styling and logic |
| `scripts/autoload/difficulty_manager.gd` | Global difficulty enum and state manager |
| `assets/fonts/gothic_bitmap.fnt` | Existing bitmap font used for Black Metal button |

### Current Architecture

The `DifficultyMenu` script already has precedent for per-button special styling:
- **Power Fantasy** button: gradient rainbow text via `RichTextLabel` overlay (Issue #1014)
- **Black Metal** button: Gothic bitmap font + dark background (Issue #1014, #1020)

The **Gunslinger** (Стрелок) button currently has no special styling — it uses the default neon theme button.

### Existing Pattern for Black Metal Styling

```gdscript
func _setup_black_metal_button() -> void:
    if _gothic_font != null:
        black_metal_button.add_theme_font_override("font", _gothic_font)
        # colors, size...
    var black_style := StyleBoxFlat.new()
    black_style.bg_color = Color(0.05, 0.05, 0.05)
    black_style.set_corner_radius_all(4)
    black_metal_button.add_theme_stylebox_override("normal", black_style)
    # hover, pressed, disabled styles...
```

---

## Font Research

### Requirements
- Must support **Cyrillic** (Russian: А-Я, а-я) and **Latin** (English: A-Z)
- Must have a **Western/Cowboy aesthetic** (slab serif, wood type, decorative)
- Must be compatible with Godot 4's font loading (`.ttf`, `.otf`, or `.fnt` bitmap)
- Must be free/open-source (for OSS project compatibility)

### Available Cowboy-Style Fonts with Cyrillic Support

| Font | Cyrillic? | Style | License | Notes |
|------|-----------|-------|---------|-------|
| **Rye** (Google Fonts) | Partial | Western slab serif | OFL | No Cyrillic |
| **Yellowtail** | No | Script/cursive | OFL | No Cyrillic |
| **Stint Ultra Expanded** | No | Compressed sans | OFL | No Cyrillic |
| **Playfair Display** | No | Serif | OFL | No Cyrillic variant |
| **Philosopher** | **Yes** | Elegant serif | OFL | Has Cyrillic, elegant feel |
| **Lobster Two** | No | Script | OFL | No Cyrillic |
| **Prosto One** | **Yes** | Display sans | OFL | Has Cyrillic |
| **Marck Script** | **Yes** | Script | OFL | Has Cyrillic |
| **Stalinist One** | **Yes** | Soviet propaganda style | OFL | Has Cyrillic, very stylized |
| **Russo One** | **Yes** | Bold display | OFL | Has Cyrillic, strong presence |

### Selected Font: **Rye** (with Cyrillic fallback via system font)

After research, **no widely-available free font** combines full Cyrillic support with an authentic Western/cowboy look. The closest approach is a **procedurally generated bitmap font** or using a fallback approach.

### Chosen Solution: Procedural Bitmap Font with Cowboy Style

Since the project already uses a custom bitmap font approach (gothic_bitmap.fnt for Black Metal), we will:

1. Create a cowboy-style bitmap font (`cowboy_bitmap.fnt` + `cowboy_bitmap.png`) using a similar approach to the gothic font.
2. The font will be a slab-serif western style that works for both Cyrillic and Latin glyphs.

**Alternative approach used:** Use a **SystemFont** fallback with `Philosopher` (Cyrillic-capable serif) combined with theme overrides for the cowboy-style colors (warm sepia/amber text on red glowing background). This achieves the cowboy aesthetic without requiring a custom font file.

---

## Implementation Plan

### 1. Glowing Red Background
Apply a `StyleBoxFlat` with:
- `bg_color`: Deep red (e.g., `Color(0.6, 0.0, 0.0)`)  
- Shadow/glow via `shadow_color`: Bright red (`Color(1.0, 0.1, 0.1, 0.8)`)
- `shadow_size`: 8px to create the glow effect
- Hover: slightly brighter red

### 2. Cowboy Font
Use a `SystemFont` configured with Western-style font families:
```gdscript
var cowboy_font := SystemFont.new()
cowboy_font.font_names = ["Georgia", "Palatino", "serif"]
```

Or load a `.ttf` if one is bundled in assets.

### 3. Code Changes
- Add `_cowboy_font` variable to `difficulty_menu.gd`
- Add `COWBOY_FONT_PATH` constant
- Add `_load_cowboy_font()` method
- Add `_setup_strelok_button()` method (called from `_ready()`)
- Mirror the Black Metal pattern exactly

---

## Screenshots

See `screenshots/` folder in the PR for before/after comparisons.

---

## References

- [Godot 4 StyleBoxFlat docs](https://docs.godotengine.org/en/stable/classes/class_styleboxflat.html)
- [Godot 4 SystemFont docs](https://docs.godotengine.org/en/stable/classes/class_systemfont.html)
- [Google Fonts Cyrillic filter](https://fonts.google.com/?subset=cyrillic)
- Similar implementation: Issue #1014 (Power Fantasy / Black Metal button styling)
