# Case Study: Issue #525 - Gothic Bitmap Font Not Rendering

## Summary

Issue #525 requested adding a Gothic font for score ratings and combo counter.
The initial implementation extracted character glyphs from a calligraphy specimen
image into a BMFont sprite sheet, but the font did not render in the exported
Godot build. This case study analyzes the root causes and the fix.

## Timeline

1. **Issue created**: Owner posted a Gothic calligraphy specimen image and
   requested it be used as the font for score ratings.

2. **First attempt**: Used `UnifrakturMaguntia-Book.ttf` (a TTF Gothic font)
   instead of the actual image. Owner rejected this - wanted the exact image
   characters.

3. **Second attempt**: Extracted characters from the image into a BMFont sprite
   sheet (`gothic_bitmap.png` + `gothic_bitmap.fnt`). Used
   `FontFile.new().load_bitmap_font()` to load at runtime. Owner reported
   "the old font returned, new font is nowhere."

4. **Root cause analysis and fix**: Identified two root causes (see below)
   and fixed both.

## Root Causes

### Root Cause 1: Empty Sprite Sheet

The font extraction script (`experiments/extract_gothic_font.py`) referenced
a hardcoded temporary file path from a previous AI session:

```python
INPUT_IMAGE = "/tmp/claude-1000/-tmp-gh-issue-solver-1770414816582/.../gothic_font_image.png"
```

This path did **not exist** in subsequent runs. The script ran without error
because the source image had already been saved to `assets/fonts/gothic_source.png`,
but the hardcoded path pointed to a non-existent location. The resulting
`gothic_bitmap.png` sprite sheet was 760x610 pixels but contained almost no
visible glyph data (only a tiny artifact in one corner from a previous run's
cached output).

**Evidence**: Viewing `gothic_bitmap.png` showed a nearly blank image. The
debug version (`gothic_sheet_debug.png` on dark background) confirmed
only 1-2 faint glyphs were present out of the expected 44.

### Root Cause 2: Runtime Font Loading Method

The code used `FontFile.new()` + `load_bitmap_font()` to load the BMFont
at runtime:

```gdscript
var font := FontFile.new()
var err := font.load_bitmap_font("res://assets/fonts/gothic_bitmap.fnt")
```

This approach has known issues in Godot 4.x:

- **In the editor**: `.fnt` files are imported by Godot's `font_data_bmfont`
  importer, which creates a `.fontdata` resource in `.godot/imported/`.
  Using `load("res://path/to/file.fnt")` accesses this imported resource.

- **`load_bitmap_font()` at runtime**: May bypass the import system entirely.
  In exported builds, the raw `.fnt` file may not be included (only the
  imported `.fontdata` is). This causes the font to silently fail to load,
  with the engine falling back to the default font.

- **No error logging**: The original code checked `err == OK` but had no
  `push_warning()` or `print()` calls, making the failure completely silent.
  The game log (`game_log_20260207_014459.txt`) contains zero font-related
  messages, confirming the silent failure.

**References**:
- [Godot Issue #74200: Bitmap fonts don't work in Godot 4](https://github.com/godotengine/godot/issues/74200)
- [Godot Issue #67495: Certain BMFont .fnt files don't work](https://github.com/godotengine/godot/issues/67495)
- [Godot Issue #95523: Can't import generated BMFont .fnt file](https://github.com/godotengine/godot/issues/95523)

## Fix Applied

### Fix 1: Proper Font Extraction

Updated `experiments/extract_gothic_font.py` to use the correct source path:

```python
INPUT_IMAGE = os.path.join(PROJECT_DIR, "assets", "fonts", "gothic_source.png")
```

Re-ran the extraction, producing a correct sprite sheet with all 44 glyphs
(A-Z, 0-9, special characters, lowercase 'x' for combo display).

### Fix 2: Godot Resource System Loading

Changed all font loading from `load_bitmap_font()` to `load()`:

```gdscript
# Before (broken in exports):
var font := FontFile.new()
var err := font.load_bitmap_font("res://assets/fonts/gothic_bitmap.fnt")

# After (works in both editor and exports):
var font = load("res://assets/fonts/gothic_bitmap.fnt")
```

This uses Godot's resource import system, which:
- Correctly imports `.fnt` files via the `font_data_bmfont` importer
- Includes the imported resource in exports
- Works in both the editor and exported builds

### Fix 3: Added Diagnostic Logging

Added `push_warning()` calls at every failure point so future font loading
issues will be visible in the game log:

```gdscript
if font != null:
    print("[AnimatedScoreScreen] Gothic bitmap font loaded successfully")
else:
    push_warning("[AnimatedScoreScreen] Failed to load Gothic font from: " + GOTHIC_FONT_PATH)
```

## Lessons Learned

1. **Never hardcode temporary paths** - Scripts that generate assets should
   use relative paths from the project root, not absolute temp paths.

2. **Use Godot's resource system** (`load()` / `preload()`) instead of
   raw file loading methods (`load_bitmap_font()`) for assets that go through
   the import pipeline.

3. **Always add diagnostic logging** for resource loading, especially for
   assets loaded at runtime. Silent failures are extremely hard to debug.

4. **Verify generated assets visually** - The broken sprite sheet would have
   been caught immediately if someone had viewed `gothic_bitmap.png` before
   committing.

## Files

- `game_log_20260207_014459.txt` - Game log from owner's test (no font errors
  visible, confirming silent failure)
