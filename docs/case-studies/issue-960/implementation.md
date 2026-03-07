# Issue #960: Neon Sign Font Styling - Implementation

## Solution Overview

Implemented a neon sign visual style for the main font using:

1. **Beon Font** (`assets/fonts/neon/Beon-Regular.ttf`)
   - Professional neon-style font with rounded tube-like letterforms
   - Free for commercial use under SIL Open Font License
   - Provides authentic neon sign appearance

2. **LabelSettings Resource** (`resources/themes/neon_label_settings.tres`)
   - Pink/magenta neon color scheme (matching reference images)
   - White-pink core color for realistic tube appearance
   - Outline for edge definition
   - Shadow with blur for soft glow

3. **Enhanced Glow Shader** (`resources/themes/neon_glow.gdshader`)
   - Multi-layer glow effect:
     - Inner glow (tight, bright)
     - Outer glow (diffuse, softer)
     - Bright core (white center like real neon tubes)
   - Configurable parameters:
     - `glow_color`: Pink/magenta neon color
     - `core_color`: Bright white-pink center
     - `glow_intensity`: Overall brightness
     - `inner_glow_size`: Tight glow around text
     - `outer_glow_size`: Diffuse ambient glow
     - `core_brightness`: How bright the tube center appears
     - `enable_flicker`: Optional neon tube flicker animation

4. **Button Theme** (`resources/themes/neon_button_theme.tres`)
   - Consistent neon colors for button text
   - Uses Beon font for all buttons
   - Hover and pressed states with brighter variants

## Visual Reference

The implementation was improved based on feedback to match these reference styles:

- **Reference 1**: `images/reference-neon-1.png` - Pink neon with white outline stroke
- **Reference 2**: `images/reference-neon-2.png` - Pink/magenta with bright white core
- **Initial attempt**: `images/initial-implementation.png` - Cyan glow (before improvement)

Key visual improvements in v2:
1. Changed from cyan to pink/magenta color scheme
2. Added bright white center to simulate real neon tube luminosity
3. Added dedicated neon-style font (Beon) instead of default system font
4. Enhanced shader with multi-layer glow for more realistic effect

## Fix History

### v3 Fix: Remove Opaque Outline

**Owner feedback (v3)**: "у больших надписей не прозрачная обводка, выглядит не как свечение" (large text has non-transparent outline, doesn't look like glow) — see `images/owner-feedback-opaque-outline.png`.

**Root cause**: `neon_label_settings.tres` had `outline_size = 3` with solid `outline_color = Color(1.0, 0.3, 0.55, 1.0)` (fully opaque). This created a hard pink border ring around each letter, making text look "outlined" rather than glowing.

**Changes in v3**:
- Set `outline_size = 0` to remove solid outline
- Increased shadow size from 12 to 16 pixels for stronger ambient glow
- Applied neon glow shader to sub-menu TitleLabels (Controls, Difficulty, Sound, Experimental)

### v4 Fix: Semi-Transparent Outline (20% Opacity)

**Owner feedback (v4)**: "маленький шрифт выглядит хорошо, но обводка больших букв не прозрачная, выглядит некрасиво (если можно сделать обводку непрозрачной на 20% было бы хорошо)" (small font looks good, but large letters have non-transparent outline — if possible make outline 20% opaque) — see `images/owner-feedback-v4-opaque-outline.png`.

After removing the outline entirely in v3, the owner found large text still had visible outlines. Investigation revealed the shadow rendering at large font sizes was creating a visible ring effect, and a subtle semi-transparent outline would look better than none at all.

**Changes in v4**:
- Set `outline_size = 3` with `outline_color = Color(1.0, 0.3, 0.55, 0.2)` — pink outline at 20% alpha
- Applied same 20% opacity outline to `neon_button_theme.tres` Label styles

## Files Created/Modified

### New Files
- `assets/fonts/neon/Beon-Regular.ttf` - Neon-style font
- `assets/fonts/neon/OFL-LICENSE.txt` - Font license
- `resources/themes/neon_label_settings.tres` - LabelSettings for neon text
- `resources/themes/neon_glow.gdshader` - Custom multi-layer glow shader
- `resources/themes/neon_glow_material.tres` - ShaderMaterial
- `resources/themes/neon_button_theme.tres` - Theme for buttons
- `docs/case-studies/issue-960/` - Research and implementation docs

### Modified Scenes
- `scenes/ui/PauseMenu.tscn` - Applied neon theme
- `scenes/ui/ControlsMenu.tscn` - Applied neon theme
- `scenes/ui/DifficultyMenu.tscn` - Applied neon theme
- `scenes/ui/SoundMenu.tscn` - Applied neon theme
- `scenes/ui/ExperimentalMenu.tscn` - Applied neon theme

### Modified Scripts
- `scripts/ui/armory_menu.gd` - Added neon label settings to title
- `scripts/ui/levels_menu.gd` - Added neon label settings to title

## Technical Details

### Shader Algorithm

The enhanced glow shader uses a two-pass sampling approach:

1. **Inner Glow Pass**: Samples pixels within a tight radius (default 2px) with high falloff
2. **Outer Glow Pass**: Samples pixels within a larger radius (default 8px) with gradual falloff

The shader then composites the layers:
- Layer 1: Outer diffuse glow (colored, low opacity)
- Layer 2: Inner glow (brighter colored glow)
- Layer 3: Original text with bright core effect (white center fading to glow color)

### Color Scheme (v2 - Pink/Magenta)

- Primary glow color: `Color(1.0, 0.2, 0.6)` - Vibrant pink/magenta
- Core color: `Color(1.0, 0.9, 0.95)` - Bright white-pink (tube center)
- Font color: `Color(1.0, 0.85, 0.92)` - Light pink
- Outline color: `Color(1.0, 0.3, 0.55)` - Darker pink
- Shadow color: `Color(1.0, 0.1, 0.4, 0.5)` - Deep magenta glow

### Compatibility

This implementation works with `gl_compatibility` renderer by using a custom shader instead of WorldEnvironment glow (which requires forward_plus renderer).

## Usage

To apply neon styling to new UI elements:

### For Labels (titles)
```gdscript
label.label_settings = load("res://resources/themes/neon_label_settings.tres")
label.material = load("res://resources/themes/neon_glow_material.tres")
```

### For entire UI containers
```gdscript
control.theme = load("res://resources/themes/neon_button_theme.tres")
```

### To customize colors
Modify the shader material parameters:
```gdscript
var material = label.material as ShaderMaterial
material.set_shader_parameter("glow_color", Color(0.0, 1.0, 0.5))  # Green neon
material.set_shader_parameter("core_color", Color(0.9, 1.0, 0.95))  # Green-white core
```

### To enable flicker effect
```gdscript
var material = label.material as ShaderMaterial
material.set_shader_parameter("enable_flicker", true)
material.set_shader_parameter("flicker_speed", 3.0)
material.set_shader_parameter("flicker_intensity", 0.05)
```

## Font Resources

The Beon font was selected based on research into neon-style fonts:

**Font**: Beon
- **Source**: [1001fonts.com](https://www.1001fonts.com/beon-font.html)
- **License**: SIL Open Font License (OFL) - Free for commercial use
- **Designer**: Bastien Sozoo / Noir Blanc Rouge
- **Characteristics**:
  - Rounded letterforms resembling bent neon tubes
  - Clean, modern sans-serif style
  - Full Latin character support

## Notes for Gothic Font Exclusion

The Gothic bitmap font (`assets/fonts/gothic_bitmap.fnt`) is used only in specific score screen contexts via explicit `add_theme_font_override()` calls in level scripts. The neon styling uses a different Theme/LabelSettings system, so the Gothic font is not affected.

Files using Gothic font (unchanged):
- `scripts/ui/animated_score_screen.gd` - Score screen labels
- `scripts/levels/*.gd` - Level completion rank labels
