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

First follow-up PR feedback on 2026-04-16 refined the art direction:

- Use `tactic_line_poster_close_quarters.png` as the base direction.
- Remove player and enemy models from the poster artwork.
- Remove the bright curved center lines.
- Add subtler route lines with nodes in the background, like planned paths on a map.
- Put armory weapons in the foreground, crossed or arranged in knolling-style layouts.
- Provide four revised variants for selection.

Second follow-up PR feedback on 2026-04-16 changed the requested batch:

- Move away from a dense pile of weapons.
- Try centered one-weapon versions, with ASVK called out as an example.
- Use only side-view armory weapon versions, not gameplay/player/enemy models.
- Provide versions for each weapon plus several multi-weapon versions.
- Keep red/black variants mostly black, with red only for letters, contours, or glow.
- Produce roughly 20 images and attach them in a PR comment.

## Collected Data

- `issue-data.json` contains the GitHub issue title/body/metadata.
- `issue-comments.json` contains current issue comments.
- `pr-comments.json` contains PR conversation feedback, including the 2026-04-16 owner revision request.
- `pr-review-comments.json` and `pr-reviews.json` preserve review-thread data; both were empty at collection time.
- Generated posters are stored in `../../../assets/posters/`.
- The reproducible generator is `../../../experiments/generate_tactic_line_posters.py`.
- The validation script is `../../../experiments/validate_tactic_line_posters.py`.

## Online Research Notes

Steam's graphical asset overview lists the main store capsule as `1232px x 706px` and describes that capsule as game logo plus artwork. That size remains the target for every poster so the result can work as a wide capsule-style preview.

Steam's graphical asset rules emphasize that base capsule images should be limited to game artwork, the game name, and an official subtitle, and that the capsule should contain a readable product logo/name. The revised posters therefore keep visible text limited to the required `Tactic Line` title.

Google Play's feature graphic guidance is useful as general game preview-art guidance even though this repository is not shipping a Play Store asset: it recommends conveying the app/game experience, keeping the focal point near the center, avoiding overloading the image with fine details, and using color/brand consistency. The revised posters use centered weapon silhouettes, reduced route-line brightness, and repo-native weapon sprites to keep the image legible at thumbnail size.

Nielsen Norman Group's visual hierarchy guidance emphasizes contrast, scale, and grouping as the way to guide attention. The second revision therefore makes the central weapon the dominant object, groups multi-weapon variants into calm rows or cells, and limits red accents so red remains a controlled emphasis color instead of flooding the whole image.

Pillow's `ImageDraw.textbbox` API returns text bounds for TrueType fonts, which makes the title placement reproducible and keeps the title from relying on generated/OCR text. Godot's `Image.save_png` API remains a viable future in-engine route for generated assets, but Pillow is used here because the issue asks for standalone repository artwork rather than runtime integration.

Sources:

- Steamworks graphical assets overview: https://partner.steamgames.com/doc/store/assets
- Steamworks graphical asset rules: https://partner.steamgames.com/doc/store/assets/rules
- Google Play preview asset guidance: https://support.google.com/googleplay/android-developer/answer/9866151
- Nielsen Norman Group visual hierarchy: https://www.nngroup.com/articles/visual-hierarchy-ux-definition/
- Pillow `ImageDraw.textbbox`: https://pillow.readthedocs.io/en/stable/reference/ImageDraw.html#PIL.ImageDraw.ImageDraw.textbbox
- Godot `Image.save_png`: https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-save-png

## Existing Repository Inputs

The revised posters reuse current project assets instead of introducing unrelated stock art:

- `assets/sprites/weapons/asvk_topdown.png`
- `assets/sprites/weapons/ak_gl_icon.png`
- `assets/sprites/weapons/m16_rifle.png`
- `assets/sprites/weapons/shotgun_icon.png`
- `assets/sprites/weapons/revolver_icon.png`
- `assets/sprites/weapons/mini_uzi_icon.png`
- `assets/sprites/weapons/silenced_pistol_icon.png`
- `assets/sprites/weapons/makarov_pm_icon.png`
- `assets/sprites/effects/casing_rifle.png`
- `assets/sprites/effects/casing_pistol.png`
- `assets/sprites/effects/casing_shotgun.png`
- `assets/sprites/effects/flashlight_cone_18deg.png`
- `assets/fonts/neon/Comfortaa-Bold.ttf`
- `assets/fonts/neon/Beon-Regular.ttf`
- `assets/fonts/rye/Rye-Regular.ttf`

The ASVK asset is the current armory-menu path even though its file name says `topdown`; visually it is a side-profile armory-style sprite. The revised generator intentionally does not use player or enemy character preview sprites and no longer uses the previous non-armory weapon gameplay sprites for the poster batch.

## Solution Options Considered

### Option A: Deterministic poster generator from repo assets

Use Pillow to compose existing weapon sprites, game-like map geometry, subdued route/node paths, glow effects, and exact title text. This remains the chosen option because it is reproducible, easy to review, does not modify game scenes, and keeps the artwork visually tied to actual repository assets.

### Option B: Godot-rendered promotional scene

Build a dedicated Godot scene, render it through a viewport, and save via `Image.save_png`. This would match the engine more closely, but it adds scene maintenance overhead for a standalone poster and risks accidentally coupling the poster to runtime resources.

### Option C: External AI image generation

Generate fully painted marketing art. This could produce richer illustration, but this environment did not expose the built-in image generation tool, and the CLI fallback requires an explicit API-key-backed request. It also risks incorrect in-image title text unless the title is composited afterward.

## Implemented Assets

All 20 individual posters use `1232x706` PNG dimensions:

- `assets/posters/tactic_line_single_asvk.png`
- `assets/posters/tactic_line_single_m16.png`
- `assets/posters/tactic_line_single_shotgun.png`
- `assets/posters/tactic_line_single_mini_uzi.png`
- `assets/posters/tactic_line_single_silenced_pistol.png`
- `assets/posters/tactic_line_single_revolver.png`
- `assets/posters/tactic_line_single_ak_gl.png`
- `assets/posters/tactic_line_single_makarov_pm.png`
- `assets/posters/tactic_line_multi_primary_rifles.png`
- `assets/posters/tactic_line_multi_sidearms.png`
- `assets/posters/tactic_line_multi_full_armory.png`
- `assets/posters/tactic_line_multi_precision_cell.png`
- `assets/posters/tactic_line_multi_breach_cell.png`
- `assets/posters/tactic_line_multi_quiet_entry.png`
- `assets/posters/tactic_line_multi_heavy_wall.png`
- `assets/posters/tactic_line_multi_compact_sweep.png`
- `assets/posters/tactic_line_multi_unlock_progression.png`
- `assets/posters/tactic_line_multi_balanced_loadout.png`
- `assets/posters/tactic_line_red_black_asvk.png`
- `assets/posters/tactic_line_red_black_loadout.png`

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

- The 20 poster variants exist under `assets/posters/`.
- Each individual poster is `1232x706`.
- The old four rejected poster files are removed from `assets/posters/`.
- The generator no longer references player or enemy character preview assets.
- The generator no longer references previous non-armory gameplay weapon sprites such as `m16_rifle_topdown.png`, `shotgun_topdown.png`, `revolver_topdown.png`, `pkm_topdown.png`, or `rpg_topdown.png`.
- The red/black variants keep red-dominant pixels under 10% of the full image.
- The title is drawn as literal text by the script: `Tactic Line`.
- No scenes, scripts, resources, import metadata, or project settings reference the posters, so the images are not added to the game itself.

## Recommendation

Use `tactic_line_single_asvk.png` as the strongest direct response to the latest feedback: one side-view armory weapon centered, subtle planned-route background, readable `Tactic Line` title, and no character/gameplay model clutter.

Use `tactic_line_multi_full_armory.png` or `tactic_line_multi_primary_rifles.png` when a reviewer wants to compare multiple weapons without returning to the earlier dense weapon-pile direction. Use `tactic_line_red_black_asvk.png` if a red/black direction is still desired; it keeps red limited to typography, contours, and glow.
