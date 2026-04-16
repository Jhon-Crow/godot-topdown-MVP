# Issue 1827 Case Study: Rank Letter Contour Shine

## Request
Issue 1827 asks for the score-screen rank text to receive a contour shine animation matching the first armory weapon-selection shine animation. Follow-up review clarified that the animated effect must not be a full card/background animation: every rank letter should be cut out and assembled into one transparent image so the shine passes along the letter edges only.

## Collected Local Evidence
- Original issue: `docs/case-studies/issue-1827/issue.json`
- PR state and review discussion: `docs/case-studies/issue-1827/pr-1853.json`
- Raw PR comments: `docs/case-studies/issue-1827/raw-comments/`
- Relevant implementation: `scripts/ui/animated_score_screen.gd`
- Armory-style shader reused by existing UI: `scripts/shaders/gold_shine.gdshader`
- Focused tests: `tests/unit/test_animated_score_screen.gd`

## Online Research Notes
Official Godot documentation for using a SubViewport as a texture confirms that viewport-rendered content can be reused as a texture, and that transparent viewport backgrounds require care because alpha can bleed with transparent backgrounds. Community reports around Godot 4 label masking and SubViewport transparency describe the same class of problem: a shader applied directly to a Control can visibly affect rectangular control bounds unless the rendered content is constrained by an alpha mask or by per-glyph content.

## Root Cause
The previous PR version attached an outline-only Label child with a shader to the rank label. Even with transparent font fill, the shader still evaluated over the label/control rectangle, so visually the effect could still read as an animated background instead of a cutout rank graphic.

## Considered Solutions
1. Keep a whole-label shader overlay and tune colors. Rejected because it preserves the rectangular shader surface that the reviewer objected to.
2. Render the whole rank string into one transparent texture using a SubViewport and apply a sprite/material to that texture. This is close to the requested “one picture without background”, but it makes per-letter assembly harder to verify and can be sensitive to transparent viewport alpha issues.
3. Build the rank graphic from individual character masks and apply the armory shader only to those letter nodes. Chosen because each letter is explicitly separated/cut out before being assembled, avoids a large rectangular overlay child, and is straightforward to test.

## Implemented Direction
The score screen now creates a `RankLetterCutout` container and adds one `RankLetterMask_*` child per visible rank character. Each letter carries the existing `gold_shine.gdshader` material with the armory-style horizontal sweep and outline settings. The fullscreen reveal and final score rank both use these assembled cutout controls instead of a background shine overlay or whole-label contour child.

## Verification Plan
- Unit tests assert that rank cutouts split text into per-character masks.
- Unit tests assert no `RankContourShineOverlay` or old `RankContourShineLabel` is used under big/final rank nodes.
- Local build/check commands should be run before pushing.
