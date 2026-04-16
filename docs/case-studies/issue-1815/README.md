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

Feedback timeline:

- First follow-up on 2026-04-16: use `tactic_line_poster_close_quarters.png` as the base direction, remove player/enemy models, remove the bright center curves, add subtler route lines with nodes, and place armory weapons in the foreground.
- Second follow-up on 2026-04-16: move away from a dense weapon pile, try one-weapon centered versions, use only side-view armory sprites, include ASVK, produce roughly 20 images, and keep red/black variants mostly black.
- Third/latest follow-up on 2026-04-16: the submitted 20-image batch did not follow the requested `assets/posters/tactic_line_poster_close_quarters.png` style. The owner specifically asked for that background and lettering, no oval on the background, a single ASVK on the foreground/top layer, a caption, and 20 ASVK-only versions.

The current implementation addresses the third/latest follow-up.

## Collected Data

- `issue-data.json` contains the GitHub issue title/body/metadata.
- `issue-comments.json` contains current issue comments.
- `pr-comments.json` contains PR conversation feedback, including the three 2026-04-16 owner revision requests.
- `pr-review-comments.json` and `pr-reviews.json` preserve review-thread data; both were empty at collection time.
- Generated posters are stored in `../../../assets/posters/`.
- The reproducible generator is `../../../experiments/generate_tactic_line_posters.py`.
- The validation script is `../../../experiments/validate_tactic_line_posters.py`.

## Online Research Notes

Steam's graphical asset overview lists the main store capsule as `1232px x 706px` and describes that capsule as game logo plus artwork. That size remains the target for every poster so the result can work as a wide capsule-style preview.

Steam's graphical asset rules emphasize that base capsule images should be limited to game artwork, the game name, and an official subtitle, and that the capsule should contain a readable product logo/name. The current posters therefore keep visible text limited to the required `Tactic Line` title and `ASVK` caption.

Google Play's feature graphic guidance is useful as general game preview-art guidance even though this repository is not shipping a Play Store asset: it recommends conveying the app/game experience, keeping the focal point near the center, avoiding overloading the image with fine details, and using color/brand consistency. The current posters use one centered weapon, restrained route-node background detail, and repo-native sprites.

Nielsen Norman Group's visual hierarchy guidance emphasizes contrast, scale, and grouping as ways to guide attention. The latest revision makes the ASVK the only dominant foreground object and keeps the map, routes, glow, and typography secondary.

Pillow's `ImageDraw.textbbox` API returns text bounds for TrueType fonts, which makes title placement reproducible and keeps the title from relying on generated/OCR text. Godot's `Image.save_png` API remains a viable future in-engine route for generated assets, but Pillow is used here because the issue asks for standalone repository artwork rather than runtime integration.

Sources:

- Steamworks graphical assets overview: https://partner.steamgames.com/doc/store/assets
- Steamworks graphical asset rules: https://partner.steamgames.com/doc/store/assets/rules
- Google Play preview asset guidance: https://support.google.com/googleplay/android-developer/answer/9866151
- Nielsen Norman Group visual hierarchy: https://www.nngroup.com/articles/visual-hierarchy-ux-definition/
- Pillow `ImageDraw.textbbox`: https://pillow.readthedocs.io/en/stable/reference/ImageDraw.html#PIL.ImageDraw.ImageDraw.textbbox
- Godot `Image.save_png`: https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-save-png

## Existing Repository Inputs

The current posters reuse project assets instead of introducing unrelated stock art:

- `assets/sprites/weapons/asvk_topdown.png`
- `assets/sprites/effects/flashlight_cone_18deg.png`
- `assets/fonts/rye/Rye-Regular.ttf`
- `assets/fonts/neon/Comfortaa-Bold.ttf`

The ASVK asset is the current armory-menu path even though its file name says `topdown`; visually it is a side-profile armory-style sprite. The latest generator intentionally does not use player sprites, enemy sprites, non-ASVK weapon sprites, or the previous oval/focus-field treatment.

## Current Implementation

All 20 individual posters use `1232x706` PNG dimensions. The first file intentionally restores the reviewer-referenced path as the current ASVK-only close-quarters variant:

- `assets/posters/tactic_line_poster_close_quarters.png`
- `assets/posters/tactic_line_asvk_close_quarters_02.png`
- `assets/posters/tactic_line_asvk_close_quarters_03.png`
- `assets/posters/tactic_line_asvk_close_quarters_04.png`
- `assets/posters/tactic_line_asvk_close_quarters_05.png`
- `assets/posters/tactic_line_asvk_close_quarters_06.png`
- `assets/posters/tactic_line_asvk_close_quarters_07.png`
- `assets/posters/tactic_line_asvk_close_quarters_08.png`
- `assets/posters/tactic_line_asvk_close_quarters_09.png`
- `assets/posters/tactic_line_asvk_close_quarters_10.png`
- `assets/posters/tactic_line_asvk_close_quarters_11.png`
- `assets/posters/tactic_line_asvk_close_quarters_12.png`
- `assets/posters/tactic_line_asvk_close_quarters_13.png`
- `assets/posters/tactic_line_asvk_close_quarters_14.png`
- `assets/posters/tactic_line_asvk_close_quarters_15.png`
- `assets/posters/tactic_line_asvk_close_quarters_16.png`
- `assets/posters/tactic_line_asvk_close_quarters_17.png`
- `assets/posters/tactic_line_asvk_close_quarters_18.png`
- `assets/posters/tactic_line_asvk_close_quarters_19.png`
- `assets/posters/tactic_line_asvk_close_quarters_20.png`

A review contact sheet is also included:

- `assets/posters/tactic_line_poster_contact_sheet.png`

![ASVK-only poster contact sheet](../../../assets/posters/tactic_line_poster_contact_sheet.png)

## Iteration History

- Iteration 0: initial four broad style directions were posted to the issue thread.
- Iteration 1: the four posters were revised toward the close-quarters/armory direction after the first feedback round.
- Iteration 2: a 20-image side-view armory batch was generated after the second feedback round, but it used several weapon types and an oval focus field.
- Iteration 3: the current batch replaces the mixed-weapon output with 20 ASVK-only close-quarters variants using the requested background and Rye-style lettering, without the oval.

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

- The 20 current ASVK-only poster variants exist under `assets/posters/`.
- Each individual poster is `1232x706`.
- The contact sheet exists and has valid PNG dimensions.
- Stale non-ASVK poster files from the second iteration are removed from `assets/posters/`.
- The generator does not reference player or enemy character preview assets.
- The generator does not reference non-ASVK weapon sprite assets.
- The generator does not use the previous oval/focus-field/plinth drawing functions.
- The red-dominant pixel ratio stays limited so the close-quarters batch does not become a red/black variant set.
- The title and caption are drawn as literal text by the script: `Tactic Line` and `ASVK`.
- No scenes, scripts, resources, import metadata, or project settings reference the posters, so the images are not added to the game itself.

## Recommendation

Use `tactic_line_poster_close_quarters.png` or `tactic_line_asvk_close_quarters_20.png` as the primary current candidates. Both follow the requested close-quarters background and lettering, avoid the oval, and keep a single ASVK as the only foreground weapon.
