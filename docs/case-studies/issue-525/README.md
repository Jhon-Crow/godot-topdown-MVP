# Case Study: Issue #525 - Gothic Bitmap Font Not Rendering

## Summary

Issue #525 requested adding a Gothic font for score ratings and combo counter.
Multiple iterations were needed to get the font extraction correct. This case
study documents the root causes found across all iterations and the final fix.

## Timeline

1. **Issue created**: Owner posted a Gothic calligraphy specimen image and
   requested it be used as the font for score ratings.

2. **First attempt**: Used `UnifrakturMaguntia-Book.ttf` (a TTF Gothic font)
   instead of the actual image. Owner rejected this - wanted the exact image
   characters.

3. **Second attempt**: Extracted characters from the image into a BMFont sprite
   sheet. Used `FontFile.new().load_bitmap_font()` to load at runtime. Owner
   reported "the old font returned, new font is nowhere."

4. **Third attempt**: Fixed source path and loading method. Owner reported
   "font markup is incorrect" - glyph bounding boxes were wrong, producing
   garbled characters.

5. **Fourth attempt**: Owner provided transparent-background version
   of the source image. Rewrite of extraction script with per-pixel alpha
   analysis and manually specified bounding boxes. However, the manual
   boundary estimates were still inaccurate for some characters.

6. **Fifth attempt (final)**: Systematic pixel-level analysis using:
   - Horizontal density valleys (density < 40) to find row boundaries
   - Per-column alpha density analysis at multiple thresholds (8-10% of
     row height) to find character column boundaries
   - 4x zoomed grid overlay images for visual verification of every split
   - Iterative refinement comparing zoomed debug images with split lines
   All 44 glyphs correctly extracted with consistent character widths.

## Root Causes

### Root Cause 1: Empty Sprite Sheet (Iteration 2-3)

The font extraction script referenced a hardcoded temporary file path from a
previous AI session. When re-run, the source image wasn't found at the
hardcoded path. The resulting `gothic_bitmap.png` sprite sheet was nearly
empty (only a tiny artifact visible).

### Root Cause 2: Runtime Font Loading Method (Iteration 2-3)

The code used `FontFile.new().load_bitmap_font()` which can fail silently
in exported Godot builds (the raw `.fnt` file may not be included in
exports - only the imported `.fontdata` is). Changed to use
`load("res://assets/fonts/gothic_bitmap.fnt")` which uses Godot's resource
import system.

### Root Cause 3: Incorrect Glyph Bounding Boxes (Iteration 3)

Even after fixing the source path, the manually specified bounding boxes
for each character were inaccurate:

- Many boxes overlapped significantly with neighboring characters
- Some characters (G, Z, 8, 9) had extremely narrow boxes, capturing
  only slivers of the actual glyph
- The extraction used grayscale threshold conversion on an RGB image with
  white background, which produced poor alpha masks

**Evidence**: The debug overlay image (`gothic_debug_final.png`) showed
bounding boxes that were misaligned with character positions. The sprite
sheet (`gothic_sheet_debug.png`) showed garbled glyphs with fragments of
neighboring characters.

### Root Cause 4: No Transparent Background Source (Iteration 1-3)

The original source image had a white/beige background. Extracting character
outlines from this required grayscale thresholding, which was unreliable:
- Similar brightness between character edges and background
- Gold-colored title area interfered with thresholding
- Character strokes with anti-aliased edges were partially lost

The owner provided a transparent-background version of the image, which
made clean extraction possible using the alpha channel directly.

## Final Fix

### Fix 1: Transparent Background Source

Used the owner-provided `gothic_source_nobg.png` (RGBA with transparent
background) as the extraction source. This allows using the alpha channel
directly instead of unreliable grayscale thresholding.

### Fix 2: Careful Glyph Boundary Mapping

Complete rewrite of `experiments/extract_gothic_font.py`:

1. Generated 4x zoomed grid overlays of each character row
2. Analyzed per-column alpha density to find character body positions
3. Manually specified split points based on visual inspection and
   density valleys between characters
4. Used auto-trimming of transparent borders for clean glyph boundaries

The new extraction produces 44 correctly-shaped glyphs (A-Z, 0-9,
`:`, `&`, `?`, `!`, `-`, `+`, space, lowercase `x`).

### Fix 3: Godot Resource System Loading

All font loading uses `load("res://assets/fonts/gothic_bitmap.fnt")`:
- Works in both editor and exported builds
- Uses Godot's `font_data_bmfont` importer
- Diagnostic `push_warning()` calls at every failure point

## Lessons Learned

1. **Never hardcode temporary paths** - Scripts that generate assets should
   use relative paths from the project root.

2. **Use Godot's resource system** (`load()` / `preload()`) instead of
   raw file loading methods for assets that go through the import pipeline.

3. **Always add diagnostic logging** for resource loading. Silent failures
   are extremely hard to debug.

4. **Verify generated assets visually** - Always inspect sprite sheets and
   debug overlays before committing.

5. **Request clean source material** - When extracting from images, a
   transparent-background version dramatically simplifies the process.

6. **Use grid overlays for coordinate mapping** - When manually specifying
   bounding boxes, generating scaled grid overlay images is essential for
   accuracy.

7. **Use alpha channel analysis** - Per-column alpha density analysis helps
   find optimal character boundaries in tightly-packed calligraphy.

## Files

- `game_log_20260207_014459.txt` - Game log from owner's test showing
  silent font loading failure
- `../../experiments/extract_gothic_font.py` - Final extraction script
- `../../experiments/gothic_debug_v5.png` - Debug overlay showing final
  bounding boxes on source image
- `../../experiments/gothic_sheet_debug_v5.png` - Final sprite sheet on
  dark background for visual verification
- `../../assets/fonts/gothic_source_nobg.png` - Transparent-background
  source image (provided by owner)
