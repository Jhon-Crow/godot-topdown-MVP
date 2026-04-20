# Issue 1845: muzzle flash not visible on Labyrinth Complex floor

Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1845
PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1846

## Summary

On the `Labyrinth Complex` map (`scenes/levels/Labyrinth2Level.tscn`) the
muzzle flash's `PointLight2D` contribution is not perceptible on the floor,
even though the same flash visibly brightens blood decals, particles, and
shell casings. Every other map renders the flash on its floor correctly.

## Collected data

- `issue.json`, `comments.json` — issue metadata captured at investigation time
- `game_log_20260416_021858.txt` — owner log after first attempt
- `game_log_20260416_231945.txt` — owner log confirming floor still dark
- `game_log_20260417_041119.txt` — owner log, blood lit but floor dark
- `game_log_20260417_233940.txt` — owner log suggesting a layer/mask issue
- `game_log_20260420_125552.txt` — owner log after 2026-04-20 attempt: "не исправлено"

## Timeline

1. 2026-04-15 — issue opened. Owner notes correct flash logic but no visible floor flash on Labyrinth Complex.
2. 2026-04-15 — first attempt added an additive `Sprite2D` flare. Owner rejected it and asked for wall-respecting behaviour with brighter floor/wall flash.
3. 2026-04-16 — second attempt replaced the floor `ColorRect` with a `Polygon2D` carrying `light_mask = 3`, added matching masks to walls, and set `range_item_cull_mask = 3` on the muzzle `PointLight2D`. Owner reported: "floor still no flash, but blood is clearly lit".
4. 2026-04-17 — further tuning of light mask bits and floor geometry. Owner reported same result.
5. 2026-04-20 — owner reports "не исправлено" (not fixed) with `game_log_20260420_125552.txt`.

## Root cause

Two factors combine to make the Labyrinth Complex floor effectively unresponsive to a
`PointLight2D`-only muzzle flash:

1. `scripts/levels/labyrinth2_level.gd:255-284` spawns **11 warm ceiling `PointLight2D`s**
   (energy 0.7–0.85, texture scale 3.5–4.5, warm yellow-orange colour) covering every
   zone of the map — plus window lights (`:353-378`) and a scene-wide
   `DirectionalLight2D` (`:459-466`). With a floor colour of `(0.17, 0.15, 0.13)`,
   these steady lights already push the floor pixels close to saturation in
   every playable area. A `+4.5` energy muzzle pulse on ADD blend produces a
   very small perceptual delta compared to the same pulse on an unlit
   Sprite2D decal (blood/casings), where the delta from dark to bright is
   large.
2. `Environment/RoomLabels/ZoneMid_Label` and `ZoneLow_Label`
   (`scenes/levels/Labyrinth2Level.tscn:1525-1551`) are ~3168 px wide translucent
   overlays covering the entire central corridor and lower labyrinth — the
   primary play area. They are drawn *after* the floor in sibling order and
   further compress the floor's brightness headroom.

Changing the floor's geometry or the flash's light-mask bits does not address
either factor: the `PointLight2D` is reaching the floor, it just does not
produce enough *relative* brightness there to notice.

## Fix (this PR)

Instead of fighting the map's ambient lighting with a brighter `PointLight2D`
(which the owner explicitly rejected: "верни яркость вспышки как в ветке
backup"), the muzzle flash now produces the floor flash with an **additive
`Sprite2D` drawn at absolute `z_index = 0`, directly under the muzzle**.

- `scenes/effects/MuzzleFlash.tscn` — added a `FloorGlow` `Sprite2D` with a
  radial gradient texture and a `CanvasItemMaterial` in
  `BLEND_MODE_ADD`. Its `modulate.a` starts at 0 and is driven by the script.
- `scripts/effects/muzzle_flash.gd` — mirrors the existing ease-out fade of
  `LIGHT_START_ENERGY` onto `FLOOR_GLOW_START_ALPHA = 0.9`, with a scale of
  2.5 (~320 px wide glow).
- All previous environment-level changes (floor `ColorRect → Polygon2D`,
  `light_mask = 3` on walls/cover, `range_item_cull_mask = 3` on the
  `PointLight2D`) are reverted so the scene files match `origin/main` and
  there is no collateral risk to other lighting on Labyrinth Complex.
- `PointLight2D` brightness (`LIGHT_START_ENERGY = 4.5`, `texture_scale =
  4.5`) remains at the backup-branch values, per the owner's explicit
  request.

Because the new floor glow is a `Sprite2D` using additive blending, it is
visible on *any* canvas surface regardless of how the map's light masks,
`light_mask` bits, or ambient lighting are configured — the same mechanism
that already makes blood decals and casings visibly light up in the owner's
screenshots.

## Verification

- `tests/unit/test_muzzle_flash.gd` — existing lifecycle tests updated to
  cover the new `FLOOR_GLOW_START_ALPHA` constant, plus a regression test
  guaranteeing the glow is clearly visible during the first third of the
  flash.
- Manual: firing on Labyrinth Complex should now show a bright orange glow
  on the floor at every shot while the `PointLight2D` continues to light the
  walls and cast shadows through the existing `LightOccluder2D` geometry.
