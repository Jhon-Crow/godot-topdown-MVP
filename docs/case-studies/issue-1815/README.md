# Issue #1815 Case Study: Tactic Line Preview Posters

## Summary

Issue #1815 requested standalone poster/preview artwork for the game, saved in the repository `assets` folder and not wired into the game itself.

Original constraints:

- Include a large, readable `Tactic Line` title.
- Create four different poster versions if possible.
- Include at least one red/black two-color version.
- Make the poster visually clickable.
- Attach the poster result back to the issue comment thread.
- Collect issue data and research in `docs/case-studies/issue-1815`.

Follow-up PR feedback on 2026-04-16 refined the art direction:

- Use `tactic_line_poster_close_quarters.png` as the base direction.
- Remove player and enemy models from the poster artwork.
- Remove the bright curved center lines.
- Add subtler route lines with nodes in the background, like planned paths on a map.
- Put armory weapons in the foreground, crossed or arranged in knolling-style layouts.
- Provide four revised variants for selection.

## Collected Data

- `issue-data.json` contains the GitHub issue title/body/metadata.
- `issue-comments.json` contains current issue comments.
- `pr-comments.json` contains PR conversation feedback, including the 2026-04-16 owner revision request.
- `pr-review-comments.json` and `pr-reviews.json` preserve review-thread data; both were empty at collection time.
- Generated posters are stored in `../../../assets/posters/`.
- The reproducible generator is `../../../experiments/generate_tactic_line_posters.py`.
- The validation script is `../../../experiments/validate_tactic_line_posters.py`.

## Online Research Notes

Steam's graphical asset overview lists the main store capsule as `1232px x 706px` and describes that capsule as game logo plus artwork. That size remains the target for all four posters so the result can work as a wide capsule-style preview.

Steam's graphical asset rules emphasize that base capsule images should be limited to game artwork, the game name, and an official subtitle, and that the capsule should contain a readable product logo/name. The revised posters therefore keep visible text limited to the required `Tactic Line` title.

Google Play's feature graphic guidance is useful as general game preview-art guidance even though this repository is not shipping a Play Store asset: it recommends conveying the app/game experience, keeping the focal point near the center, avoiding overloading the image with fine details, and using color/brand consistency. The revised posters use centered weapon silhouettes, reduced route-line brightness, and repo-native weapon sprites to keep the image legible at thumbnail size.

Pillow's `ImageDraw.textbbox` API returns text bounds for TrueType fonts, which makes the title placement reproducible and keeps the title from relying on generated/OCR text. Godot's `Image.save_png` API remains a viable future in-engine route for generated assets, but Pillow is used here because the issue asks for standalone repository artwork rather than runtime integration.

Sources:

- Steamworks graphical assets overview: https://partner.steamgames.com/doc/store/assets
- Steamworks graphical asset rules: https://partner.steamgames.com/doc/store/assets/rules
- Google Play preview asset guidance: https://support.google.com/googleplay/android-developer/answer/9866151
- Pillow `ImageDraw.textbbox`: https://pillow.readthedocs.io/en/stable/reference/ImageDraw.html#PIL.ImageDraw.ImageDraw.textbbox
- Godot `Image.save_png`: https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-save-png

## Existing Repository Inputs

The revised posters reuse current project assets instead of introducing unrelated stock art:

- `assets/sprites/weapons/asvk_topdown.png`
- `assets/sprites/weapons/ak_gl_topdown.png`
- `assets/sprites/weapons/m16_rifle_topdown.png`
- `assets/sprites/weapons/shotgun_topdown.png`
- `assets/sprites/weapons/pkm_topdown.png`
- `assets/sprites/weapons/rpg_topdown.png`
- `assets/sprites/weapons/revolver_topdown.png`
- `assets/sprites/weapons/mini_uzi_topdown.png`
- `assets/sprites/weapons/silenced_pistol_topdown.png`
- `assets/sprites/weapons/makarov_pm_topdown.png`
- `assets/sprites/weapons/machete_topdown.png`
- `assets/sprites/weapons/frag_grenade.png`
- `assets/sprites/weapons/flashbang.png`
- `assets/sprites/effects/casing_rifle.png`
- `assets/sprites/effects/casing_pistol.png`
- `assets/sprites/effects/casing_shotgun.png`
- `assets/sprites/effects/flashlight_cone_18deg.png`
- `assets/fonts/neon/Comfortaa-Bold.ttf`
- `assets/fonts/neon/Beon-Regular.ttf`
- `assets/fonts/rye/Rye-Regular.ttf`

The revised generator intentionally does not use player or enemy character preview sprites.

## Solution Options Considered

### Option A: Deterministic poster generator from repo assets

Use Pillow to compose existing weapon sprites, game-like map geometry, subdued route/node paths, glow effects, and exact title text. This remains the chosen option because it is reproducible, easy to review, does not modify game scenes, and keeps the artwork visually tied to actual repository assets.

### Option B: Godot-rendered promotional scene

Build a dedicated Godot scene, render it through a viewport, and save via `Image.save_png`. This would match the engine more closely, but it adds scene maintenance overhead for a standalone poster and risks accidentally coupling the poster to runtime resources.

### Option C: External AI image generation

Generate fully painted marketing art. This could produce richer illustration, but this environment did not expose the built-in image generation tool, and the CLI fallback requires an explicit API-key-backed request. It also risks incorrect in-image title text unless the title is composited afterward.

## Implemented Assets

All four individual posters use `1232x706` PNG dimensions:

- `assets/posters/tactic_line_poster_neon_crossfire.png` - Neon Arsenal: crossed foreground weapons over a close-quarters tactical map.
- `assets/posters/tactic_line_poster_red_black.png` - Red / Black: strict two-color weapon silhouette poster.
- `assets/posters/tactic_line_poster_blueprint.png` - Blueprint Loadout: knolling-style armory layout over route-planning lines.
- `assets/posters/tactic_line_poster_close_quarters.png` - Close Quarters Armory: close-quarters base direction with foreground weapons and restrained route nodes.

A review contact sheet is also included:

- `assets/posters/tactic_line_poster_contact_sheet.png`

![Poster contact sheet](../../../assets/posters/tactic_line_poster_contact_sheet.png)

## Validation

Generation command:

```bash
python3 experiments/generate_tactic_line_posters.py
```

Validation command:

```bash
python3 experiments/validate_tactic_line_posters.py
```

Validation checks performed:

- The four poster variants exist under `assets/posters/`.
- Each individual poster is `1232x706`.
- `tactic_line_poster_red_black.png` contains exactly two RGB colors: `(0, 0, 0)` and `(255, 0, 0)`.
- The generator no longer references player or enemy character preview assets.
- The title is drawn as literal text by the script: `Tactic Line`.
- No scenes, scripts, resources, import metadata, or project settings reference the posters, so the images are not added to the game itself.

## Recommendation

Use `tactic_line_poster_close_quarters.png` as the strongest revised direction because it follows the owner feedback most directly: close-quarters base, no character models, subtle route planning, and weapons as the main foreground read.

Keep `tactic_line_poster_blueprint.png` as the cleanest alternate if the reviewer prefers a more ordered armory/knolling composition, and keep the red/black version as the strict two-color option requested in the original issue.
