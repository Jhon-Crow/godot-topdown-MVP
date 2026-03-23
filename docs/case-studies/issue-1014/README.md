# Case Study: Issue #1014 - Update Difficulty Fonts

## Problem Statement

The difficulty selection menu needs visual enhancements for two specific difficulty modes:
1. **Power Fantasy** - Text should display with a bright gradient (from first letter to last)
2. **Black Metal** - Text should use a Black metal style font with an appropriate dark color

## Timeline of Events

### Initial Implementation (2026-03-11T20:31 - 2026-03-11T20:39)

1. AI solution draft was created with the following approach:
   - Power Fantasy: RichTextLabel with per-character BBCode color tags for gradient effect
   - Black Metal: Gothic bitmap font applied via `add_theme_font_override()`

2. Implementation was committed with:
   - Gradient colors: Cyan → Purple → Magenta → Orange → Yellow
   - Gothic font loaded from `assets/fonts/gothic_bitmap.fnt`
   - RichTextLabel positioned with `PRESET_CENTER` anchor

### User Feedback (2026-03-11T20:55)

User reported: "оба шрифта отображаются не правильно" (both fonts display incorrectly)

Screenshot showed:
- **Black Metal**: Displayed as boxes `▯▯▯▯▯ ▯▯▯▯▯` (missing character glyphs)
- **Power Fantasy**: Gradient appeared as vertical line of colored dots (layout issue)

## Root Cause Analysis

### Issue 1: Black Metal Font Shows Boxes

**Symptom:** The text "Black Metal" renders as rectangular boxes (▯) instead of gothic letters.

**Root Cause:** The `gothic_bitmap.fnt` font has a **limited character set**:
- Uppercase letters A-Z (Unicode 65-90) ✅
- Numbers 0-9 (Unicode 48-57) ✅
- Special characters: `:` `&` `?` `!` `-` `+` `x` ` ` ✅
- **Lowercase letters a-z (Unicode 97-122) ❌ NOT INCLUDED**

The text "Black Metal" contains lowercase letters (`l`, `a`, `c`, `k`, `e`, `t`) which are not present in the font, causing Godot to display fallback boxes.

**Evidence from `gothic_bitmap.fnt`:**
```
chars count=44
char id=65    # A
char id=66    # B
...
char id=90    # Z
char id=48    # 0
...
char id=57    # 9
char id=120   # x (lowercase, special case - scaled from X)
# NO entries for id=97-122 (a-z)
```

**Solution:** Convert button text to uppercase: `"BLACK METAL"` instead of `"Black Metal"`

### Issue 2: Power Fantasy Gradient Shows as Dots

**Symptom:** Gradient colors appear as a vertical line of dots in the center of the screen, not as gradient-colored text.

**Root Cause:** The RichTextLabel setup had incorrect positioning:

```gdscript
# Original problematic code:
_power_fantasy_label.set_anchors_preset(Control.PRESET_CENTER)  # Only centers anchor point
_power_fantasy_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
_power_fantasy_label.grow_vertical = Control.GROW_DIRECTION_BOTH
_power_fantasy_label.fit_content = true  # Fits to text size
```

With `fit_content = true` and `PRESET_CENTER`, the label collapses to fit its content but doesn't properly expand within the button's area. The `[center]` BBCode tag centers text horizontally within the label's width, but if the label itself has zero or minimal width, each character renders on its own line vertically.

**Solution:** Use a `CenterContainer` to properly center the RichTextLabel within the button:

```gdscript
var center_container := CenterContainer.new()
center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

_power_fantasy_label = RichTextLabel.new()
_power_fantasy_label.fit_content = true  # Now works correctly within CenterContainer
_power_fantasy_label.autowrap_mode = TextServer.AUTOWRAP_OFF

center_container.add_child(_power_fantasy_label)
power_fantasy_button.add_child(center_container)
```

## Technical Details

### Godot 4 RichTextLabel Limitations

1. **No vertical alignment in BBCode**: The `[center]` tag only aligns horizontally. Vertical centering requires container nodes or anchors.

2. **fit_content behavior**: When enabled, the label sizes to fit its content. Combined with wrong anchor presets, this can cause the label to collapse to minimal size.

3. **Reference**: [Godot Proposals #6674](https://github.com/godotengine/godot-proposals/issues/6674) - Add vertical alignment option to RichTextLabel

### BMFont Character Set Requirements

The BMFont format (`.fnt`) requires explicit character definitions. Characters not defined in the file will render as replacement characters (boxes).

**Reference**: [Godot Documentation - Using Fonts](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_fonts.html)

## Solution Summary

| Issue | Root Cause | Fix |
|-------|------------|-----|
| Black Metal boxes | Gothic font missing lowercase letters | Use uppercase text: `"BLACK METAL"` |
| Gradient dots | RichTextLabel positioning collapsed | Wrap in CenterContainer with PRESET_FULL_RECT |

## Lessons Learned

1. **Always verify font character coverage** when using custom bitmap fonts. Check the `.fnt` file for which characters are actually defined.

2. **Test UI layouts visually** before declaring implementation complete. Layout issues often only become apparent at runtime.

3. **RichTextLabel centering requires containers** - BBCode `[center]` only handles horizontal alignment within the label's bounds.

4. **Anchor presets matter** - `PRESET_CENTER` positions the anchor point at center but doesn't fill the parent; use `PRESET_FULL_RECT` for filling containers.

## Files Changed

- `scripts/ui/difficulty_menu.gd` - Fixed RichTextLabel positioning and uppercase text

## References

- [Godot BBCode in RichTextLabel](https://docs.godotengine.org/en/stable/tutorials/ui/bbcode_in_richtextlabel.html)
- [Godot Using Fonts](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_fonts.html)
- [BMFont Character Set Issues (GitHub)](https://github.com/godotengine/godot/issues/74200)
- [Vertical Alignment Proposal](https://github.com/godotengine/godot-proposals/issues/6674)
