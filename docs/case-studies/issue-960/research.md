# Issue #960: Neon Sign Font Styling Research

## Problem Statement
Style the main font to look like a neon sign with glow effect.

## Requirements (from issue)
- Style the main font to look like a neon sign ("неоновая вывеска")
- Add glow effect ("добавь свечение")

## Research Findings

### Approaches for Neon Text Effect in Godot 4

#### 1. WorldEnvironment with Glow/Bloom (Recommended for this project)
- **Pros**: Built-in, relatively simple, affects all HDR elements
- **Cons**: Requires HDR 2D rendering mode, can affect other elements
- **Requirements**:
  - Enable HDR 2D in Project Settings (Rendering > Viewport > HDR 2D)
  - Add WorldEnvironment node with Background Mode set to Canvas
  - Enable Glow/Bloom effect
  - Set text color to HDR values (>1.0 brightness) to trigger bloom

#### 2. Custom Shader on Label
- **Pros**: Full control, can work without WorldEnvironment
- **Cons**: More complex, requires shader knowledge
- **Popular shaders from godotshaders.com**:
  - "2D Glow Screen (No WorldEnvironment Node)" - 1240 likes
  - "Dynamic Glow" - 494 likes
  - "Gaussian Glow" - 212 likes

#### 3. LabelSettings with Outline/Shadow
- **Pros**: Simple, native Godot feature
- **Cons**: Limited glow effect, more like an outline
- **Method**: Use LabelSettings resource with outline_color and outline_size

#### 4. Duplicate Labels with Blur
- **Pros**: Simple, no shaders required
- **Cons**: Performance impact, requires multiple nodes
- **Method**: Stack multiple labels with increasing blur modulate

### Neon Sign Visual Characteristics
1. **Primary Color**: Bright neon color (cyan, pink, green, orange)
2. **Inner Glow**: Whitish center that fades to the primary color
3. **Outer Glow**: Soft bloom effect around the text
4. **Subtle Animation**: Optional flicker or pulse effect

### Project-Specific Considerations
- Project uses `gl_compatibility` rendering method (see project.godot line 145)
- **Important**: Glow effect will NOT work with `gl_compatibility` renderer
- Would need to switch to `forward_plus` or `mobile` renderer for WorldEnvironment glow
- Alternative: Use shader-based approach that works with compatibility renderer

## Recommended Solution

Since the project uses `gl_compatibility` renderer where WorldEnvironment glow doesn't work, we should use a **combination approach**:

1. **Create a custom neon theme/LabelSettings resource** with:
   - Bright neon font color
   - Outline with glow-like color
   - Shadow with blur for additional glow effect

2. **Create a simple glow shader** that can be applied to labels for enhanced effect

3. **Apply to main UI labels** (TitleLabel, menu buttons, etc.)

## Font Research

### Neon-Style Fonts Investigated

1. **Beon** (Selected)
   - License: SIL Open Font License (OFL) - Free for commercial use
   - Source: [1001fonts.com](https://www.1001fonts.com/beon-font.html)
   - Designer: Bastien Sozoo / Noir Blanc Rouge
   - Pros: Professional, rounded tube-like letterforms, free commercial license
   - Format: TTF/OTF available

2. **Klaxons**
   - License: Free for personal and commercial use
   - Thin, neon-influenced with tube-like glyphs
   - Good for thinner neon signs

3. **Neon Tubes**
   - Clean, elegant with smooth rounded corners
   - Open start/end points like real neon tubes
   - License varies by source - check before use

4. **God's Own Junkyard**
   - Very rounded neon sans-serif
   - Designer: Simon Stratford
   - Good for playful neon signs

### Selected Font: Beon

Beon was selected because:
- Free for commercial use (SIL OFL license)
- Modern, clean design
- Rounded letterforms that resemble bent neon tubes
- Full Latin character support (173 glyphs, 227 defined characters)
- Both TTF and OTF formats available

## Resources
- [Godot Forum: Glow Effect in Godot 4](https://forum.godotengine.org/t/how-to-use-glow-effect-in-godot-4/1626)
- [Godot Forum: Glow for Text](https://forum.godotengine.org/t/how-can-i-make-glow-effect-for-text-in-godot-4/79222)
- [Godot Shaders - Glow Collection](https://godotshaders.com/shader-tag/glow/)
- [Godot Asset Library - Glowing Shaders](https://godotengine.org/asset-library/asset/2366)
- [Onextrapixel - Best Neon Fonts](https://onextrapixel.com/best-neon-fonts/)
- [Fontesk - Free Neon Fonts](https://fontesk.com/tag/neon/)
- [1001fonts - Beon Font](https://www.1001fonts.com/beon-font.html)
