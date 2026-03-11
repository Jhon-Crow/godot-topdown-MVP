# Case Study: Issue #1014 - Update Difficulty Fonts

## Problem Statement

The difficulty selection menu needs visual enhancements for two specific difficulty modes:
1. **Power Fantasy** - Text should display with a bright gradient (from first letter to last)
2. **Black Metal** - Text should use a Black metal style font with an appropriate dark color

## Technical Analysis

### Current Implementation
- Difficulty menu is in `scenes/ui/DifficultyMenu.tscn`
- Button logic is in `scripts/ui/difficulty_menu.gd`
- Standard Godot Button nodes are used with plain text

### Godot 4 Capabilities

#### Gradient Text Options
1. **RichTextLabel with BBCode** - Supports `[rainbow]` effect but it cycles colors over time
2. **Per-character coloring** - Can use `[color=#RRGGBB]` tags per character
3. **Custom RichTextEffect** - Can create shader-based gradient effects
4. **Label with shader** - Apply a gradient shader to a Label node

For a static gradient from first letter to last, we need either:
- Per-character color BBCode tags
- A gradient shader applied to the button/label

#### Black Metal Font
The project already has `assets/fonts/gothic_bitmap.fnt` which is a gothic-style bitmap font that fits the Black Metal aesthetic.

## Solution Design

### Power Fantasy Button
Use a custom shader or RichTextLabel to create a bright gradient effect:
- Colors: Vibrant rainbow/neon gradient (e.g., from cyan to magenta to yellow)
- Implementation: Create a GradientLabel control that applies per-character colors

### Black Metal Button
- Use the existing `gothic_bitmap.fnt` font
- Color: Dark gray with slight red tint (#4A3030) or white on dark for contrast
- The gothic bitmap font already has the characteristic Black Metal letter styling

## Implementation Approach

1. Create a custom scene component for styled difficulty buttons
2. Modify `difficulty_menu.gd` to apply special styling to Power Fantasy and Black Metal buttons
3. Use RichTextLabel for Power Fantasy with per-character gradient coloring
4. Apply gothic_bitmap font to Black Metal button

## Resources

### Existing Project Assets
- `assets/fonts/gothic_bitmap.fnt` - Gothic style bitmap font
- `assets/fonts/gothic_bitmap.png` - Font texture atlas

### Godot Documentation
- BBCode in RichTextLabel: https://docs.godotengine.org/en/stable/tutorials/ui/bbcode_in_richtextlabel.html
- Font resources: https://docs.godotengine.org/en/stable/classes/class_font.html

## Color Palette

### Power Fantasy Gradient
- Start: #00FFFF (Cyan)
- Middle: #FF00FF (Magenta)
- End: #FFFF00 (Yellow)

Alternative vibrant gradient:
- Start: #FF6B6B (Coral Red)
- Middle: #FFE66D (Yellow)
- End: #4ECDC4 (Teal)

### Black Metal
- Primary: #C0C0C0 (Silver/Light Gray) - for visibility
- Background: Dark, or use with outline
- The gothic font style already conveys the Black Metal aesthetic
