# Issue 1827 Case Study: Rank Letter Contour Shine

## Request
Issue 1827 asks for the score-screen rank text to receive a contour shine animation matching the first armory weapon-selection shine animation. Follow-up review clarified that the animated effect must not be a full card/background animation: every rank letter should be cut out and assembled into one transparent image so the shine passes along the letter edges only.

## Collected Local Evidence
- Original issue: `docs/case-studies/issue-1827/issue.json`
- PR state and review discussion: `docs/case-studies/issue-1827/pr-1853.json`
- Raw PR comments: `docs/case-studies/issue-1827/raw-comments/`
- Owner feedback log from 2026-04-17: `docs/case-studies/issue-1827/logs/game_log_20260417_040452.txt`
- Relevant implementation: `scripts/ui/animated_score_screen.gd`
- Armory-style shader reused by existing UI: `scripts/shaders/gold_shine.gdshader`
- Alpha-aware rank shader added for this issue: `scripts/shaders/rank_letter_shine.gdshader`
- Focused tests: `tests/unit/test_animated_score_screen.gd`

## Online Research Notes
Official Godot documentation for using a SubViewport as a texture confirms that viewport-rendered content can be reused as a texture, and that transparent viewport backgrounds require care because alpha can bleed with transparent backgrounds. Community reports around Godot 4 label masking and SubViewport transparency describe the same class of problem: a shader applied directly to a Control can visibly affect rectangular control bounds unless the rendered content is constrained by an alpha mask or by per-glyph content.

## Root Cause
The first PR version attached an outline-only Label child with a shader to the rank label. Even with transparent font fill, the shader still evaluated over the label/control rectangle, so visually the effect could still read as an animated background instead of a cutout rank graphic.

The second PR version moved to one Label per character, but still applied the additive armory `gold_shine.gdshader` directly to Control/Label nodes. The 2026-04-17 owner feedback says the result was animated rectangles while the actual font disappeared. That matches the rendering path: the shared armory shader writes `COLOR` without sampling the label glyph alpha, so when used as a Label material it can replace the glyph draw with a rectangular shader output instead of preserving transparent pixels.

## Considered Solutions
1. Keep a whole-label shader overlay and tune colors. Rejected because it preserves the rectangular shader surface that the reviewer objected to.
2. Render the whole rank string into one transparent texture using a SubViewport and apply a sprite/material to that texture. This is close to the requested “one picture without background”, but it makes per-letter assembly harder to verify and can be sensitive to transparent viewport alpha issues.
3. Build the rank graphic from individual character masks and apply an alpha-aware shine shader to transparent letter textures. Chosen because each letter is explicitly rendered into a transparent texture before being assembled, avoids a large rectangular overlay child, and clips all shine output to glyph alpha.

## Implemented Direction
The score screen now creates a `RankLetterCutout` container and adds one `RankLetterMask_*` TextureRect per visible rank character. Each TextureRect is backed by a transparent SubViewport rendering the gothic Label glyph with outline. The new `rank_letter_shine.gdshader` samples that texture, adds an armory-style sweep only where texture alpha exists, and preserves `COLOR.a = tex.a`. The fullscreen reveal and final score rank both use these assembled cutout textures instead of a background shine overlay or whole-label contour child.

## Verification Plan
- Unit tests assert that rank cutouts split text into per-character masks.
- Unit tests assert that each rank mask is a TextureRect with a kept-alive transparent render viewport and alpha-texture metadata.
- Unit tests assert no `RankContourShineOverlay` or old `RankContourShineLabel` is used under big/final rank nodes.
- Local build/check commands should be run before pushing.
