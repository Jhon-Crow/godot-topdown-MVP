# Issue #960: Neon Sign Font Styling - Implementation

## Solution Overview

Implemented a neon sign visual style for the main font using:

1. **LabelSettings Resource** (`resources/themes/neon_label_settings.tres`)
   - Cyan/aqua neon color (Color: 0.4, 1.0, 1.0)
   - Outline for edge glow effect
   - Shadow with blur for soft glow

2. **Glow Shader** (`resources/themes/neon_glow.gdshader`)
   - Custom canvas_item shader for enhanced glow effect
   - Configurable parameters:
     - `glow_color`: Neon color for the glow
     - `glow_intensity`: Brightness of the glow
     - `glow_size`: Spread of the glow effect
     - `blur_iterations`: Quality of the blur
     - `enable_flicker`: Optional neon tube flicker animation
     - `flicker_speed` and `flicker_intensity`: Animation control

3. **Button Theme** (`resources/themes/neon_button_theme.tres`)
   - Consistent neon colors for button text
   - Hover and pressed states with brighter variants

## Files Modified

### New Files Created
- `resources/themes/neon_label_settings.tres` - LabelSettings for neon text
- `resources/themes/neon_glow.gdshader` - Custom glow shader
- `resources/themes/neon_glow_material.tres` - ShaderMaterial using the shader
- `resources/themes/neon_button_theme.tres` - Theme for buttons
- `docs/case-studies/issue-960/research.md` - Research documentation
- `docs/case-studies/issue-960/implementation.md` - This file

### Modified Scenes
- `scenes/main/Main.tscn` - Applied neon styling to title label
- `scenes/ui/PauseMenu.tscn` - Applied neon theme to menu
- `scenes/ui/ControlsMenu.tscn` - Applied neon theme to menu
- `scenes/ui/DifficultyMenu.tscn` - Applied neon theme to menu
- `scenes/ui/SoundMenu.tscn` - Applied neon theme to menu
- `scenes/ui/ExperimentalMenu.tscn` - Applied neon theme to menu

## Technical Details

### Shader Approach
The glow shader samples surrounding pixels in a circular pattern and applies a weighted blur. The result is mixed with the original text to create the characteristic neon glow where:
- The center of the text appears brighter (simulating the gas tube)
- The edges have a soft color glow
- Optional flicker effect uses sine waves for realistic neon tube animation

### Color Scheme
- Primary color: Cyan (0.4, 1.0, 1.0) - bright, energetic neon
- Outline color: Darker cyan (0.0, 0.8, 0.9) - edge definition
- Shadow/glow color: Soft cyan (0.0, 0.6, 0.8, 0.6) - ambient glow
- Hover color: Brighter cyan (0.6, 1.0, 1.0)
- Pressed color: White (1.0, 1.0, 1.0) - fully lit

### Compatibility
This implementation works with `gl_compatibility` renderer (which the project uses) by not relying on WorldEnvironment glow which requires forward_plus or mobile renderer.

## Usage

To apply neon styling to new UI elements:

1. **For Labels (titles)**:
   ```gdscript
   label.label_settings = preload("res://resources/themes/neon_label_settings.tres")
   label.material = preload("res://resources/themes/neon_glow_material.tres")
   ```

2. **For entire UI containers (buttons, checkboxes, etc.)**:
   ```gdscript
   control.theme = preload("res://resources/themes/neon_button_theme.tres")
   ```

3. **To enable flicker effect** (in shader material):
   - Set `enable_flicker = true`
   - Adjust `flicker_speed` (higher = faster)
   - Adjust `flicker_intensity` (higher = more dramatic)

## Future Enhancements

1. Add more neon color variants (pink, green, orange)
2. Create animated neon sign that flickers on when scene loads
3. Add HDR bloom support if renderer is changed to forward_plus
