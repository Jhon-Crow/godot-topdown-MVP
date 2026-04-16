# Issue #1815 Case Study: Tactic Line Preview Posters

## Summary

Issue #1815 requested standalone poster/preview artwork for the game, saved in the repository `assets` folder and not wired into the game itself.

Required constraints:

- Include a large, readable `Tactic Line` title.
- Create four different poster versions if possible.
- Include at least one red/black two-color version.
- Make the poster visually clickable.
- Attach the poster result back to the issue comment thread.
- Collect issue data and research in `docs/case-studies/issue-1815`.

## Collected Data

- `issue-data.json` contains the GitHub issue title/body/metadata.
- `issue-comments.json` contains the latest issue comments. At collection time, the issue had no comments.
- Generated posters are stored in `../../../assets/posters/`.
- The reproducible generator is `../../../experiments/generate_tactic_line_posters.py`.

## Online Research Notes

Steam's current graphical asset overview lists the main store capsule as `1232px x 706px` and describes it as game logo plus artwork. That size was selected for all four posters so the output is immediately usable as a wide capsule-style preview.

Steam's graphical asset rules also state that base capsules should be limited to game artwork, the game name, and an official subtitle, and that capsule images should contain a readable product logo/name and accurate dimensions. The generated posters therefore avoid extra marketing phrases and keep the text limited to the required `Tactic Line` title.

Pillow's `ImageDraw.textbbox` API returns text bounds for TrueType fonts, which makes the title placement reproducible and keeps the title from relying on generated/OCR text. Godot's `Image.save_png` API is a viable future in-engine route for screenshots or generated assets, but Pillow was used here because the issue asks for standalone repository artwork rather than runtime integration.

Sources:

- Steamworks graphical assets overview: https://partner.steamgames.com/doc/store/assets
- Steamworks graphical asset rules: https://partner.steamgames.com/doc/store/assets/rules
- Pillow `ImageDraw.textbbox`: https://pillow.readthedocs.io/en/stable/reference/ImageDraw.html#PIL.ImageDraw.ImageDraw.textbbox
- Godot `Image.save_png`: https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-save-png

## Existing Repository Inputs

The posters reuse current project assets instead of introducing unrelated stock art:

- `assets/sprites/characters/player/player_combined_preview.png`
- `assets/sprites/characters/enemy/enemy_combined_preview.png`
- `assets/sprites/weapons/m16_rifle_topdown.png`
- `assets/sprites/weapons/shotgun_topdown.png`
- `assets/sprites/weapons/revolver_topdown.png`
- `assets/sprites/effects/flashlight_cone_18deg.png`
- `assets/fonts/neon/Comfortaa-Bold.ttf`
- `assets/fonts/neon/Beon-Regular.ttf`
- `assets/fonts/rye/Rye-Regular.ttf`

## Solution Options Considered

### Option A: Deterministic poster generator from repo assets

Use Pillow to compose existing sprites, game-like map geometry, tactical route lines, glow effects, and the exact title text. This was chosen because it is reproducible, easy to review, does not modify game scenes, and keeps the art visually tied to the actual game.

### Option B: Godot-rendered promotional scene

Build a dedicated Godot scene, render it through a viewport, and save via `Image.save_png`. This would match the engine more closely, but it adds scene maintenance overhead for a one-off repository asset and risks accidentally coupling the poster to game runtime resources.

### Option C: External AI image generation

Generate fully painted marketing art. This could produce richer illustration, but this environment did not expose the built-in image generation tool, and the CLI fallback requires an explicit API-key-backed request. It also risks incorrect in-image title text unless the title is composited afterward.

## Implemented Assets

All four individual posters use `1232x706` PNG dimensions:

- `assets/posters/tactic_line_poster_neon_crossfire.png`
- `assets/posters/tactic_line_poster_red_black.png`
- `assets/posters/tactic_line_poster_blueprint.png`
- `assets/posters/tactic_line_poster_close_quarters.png`

A review contact sheet is also included:

- `assets/posters/tactic_line_poster_contact_sheet.png`

![Poster contact sheet](../../../assets/posters/tactic_line_poster_contact_sheet.png)

## Validation

Generation command:

```bash
python3 experiments/generate_tactic_line_posters.py
```

Validation checks performed:

- The four poster variants exist under `assets/posters/`.
- Each individual poster is `1232x706`.
- `tactic_line_poster_red_black.png` contains exactly two RGB colors: `(0, 0, 0)` and `(255, 0, 0)`.
- The title is drawn as literal text by the script: `Tactic Line`.
- No scenes, scripts, resources, import metadata, or project settings reference the posters, so the images are not added to the game itself.

## Recommendation

Use `tactic_line_poster_neon_crossfire.png` as the default issue preview because it has the clearest game identity at thumbnail size: title in the first read position, top-down room layout, player/enemy silhouettes, and crossing tactical lines.

Keep the red/black version as the strict two-color alternative requested by the issue owner, and keep the contact sheet in the PR description for quick review.
