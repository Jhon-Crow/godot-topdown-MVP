# Case Study — Issue #1845: Muzzle flashes barely visible on the "Лабиринт Комплекс" (Labyrinth Complex) map

- **Issue:** [Jhon-Crow/godot-topdown-MVP#1845](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1845)
- **Prior PR (closed, not merged):** [#1846](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1846) on branch `issue-1845-7869d1b529b6`
- **Current WIP PR:** [#1913](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1913) on branch `issue-1845-9c7af31173aa`
- **Reporter:** @Jhon-Crow (project owner)
- **Map:** `Labyrinth2Level` (`scenes/levels/Labyrinth2Level.tscn`), displayed as "Лабиринт Комплекс"
- **Godot version:** 4.3-stable (official) — from game logs

## 1. Problem statement (verbatim, translated)

Original issue body (RU → EN):

> логика вспышек правильная, но вспышки не видно на полу (на врагах или на крови видно)
>
> _The flash logic is correct, but the flashes are not visible on the floor (they are visible on enemies or on blood)._

Latest comment on the issue (2026-04-20) after PR #1846 was closed:

> попробуй снова — _"try again"_

## 2. Timeline of events

All game-log files referenced below live next to this document.

| Date (UTC)            | Log file                                | Reporter feedback                                                                                                           |
| :-------------------- | :-------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------- |
| 2026-04-15 22:35      | `game_log_20260416_013506.txt` *(initial)* | First report: flashes invisible on floor, visible on enemies/blood.                                                         |
| 2026-04-15 23:22      | `game_log_20260416_021858.txt`          | "верни как было … сделай вспышку на полу ярче … мне нужно явная вспышка на стенах и явные тени от этой вспышки."              |
| 2026-04-16 20:21      | `game_log_20260416_231945.txt`          | "на полу нет вспышек, есть на частицах, крови, гильзах".                                                                    |
| 2026-04-17 01:12      | `game_log_20260417_041119.txt`          | "всё ещё нет вспышке на полу (на крови явно видно, на полу нет вообще)".                                                    |
| 2026-04-17 20:41      | `game_log_20260417_233940.txt`          | "вспышек на полу всё ещё нет (возможно проблема со слоями)" — first hint at a layer / light-mask problem.                    |
| 2026-04-17 22:31      | `game_log_20260418_013007.txt`          | "всё ещё нет вспышек на полу Лабиринт Комплекс".                                                                            |
| 2026-04-20 09:28      | `game_log_20260420_122659.txt`          | "сейчас вспышка слишком яркая (верни яркость вспышки как в ветке backup) … всё ещё нет вспышки на полу".                    |
| 2026-04-20 09:56      | `game_log_20260420_125552.txt`          | "не исправлено".                                                                                                            |
| 2026-04-20 10:27      | —                                       | "появилась странная квадратная вспышка" — the additive `FloorGlow` sprite introduced a visible square artefact.             |
| 2026-04-20 10:53      | `game_log_20260420_135251.txt`          | "не исправлено" → PR #1846 closed by owner.                                                                                 |
| 2026-04-20 10:54      | —                                       | New comment on the issue: "попробуй снова" — triggering the present attempt.                                                |

### 2.1 Previous attempts on branch `issue-1845-7869d1b529b6` (all rejected)

In commit order (oldest first):

1. `d9ed9c10` *Fix Labyrinth muzzle flash visibility.*
2. `1f94d305` *Brighten Labyrinth muzzle flash light.*
3. `4c3c6016` *Make Labyrinth Complex floor receive muzzle light.*
4. `6048bcf0` *Strengthen Labyrinth floor muzzle flash.*
5. `204cd467` *Match Labyrinth environment muzzle light mask.*
6. `8522874a` *Fix Labyrinth floor not receiving muzzle light by replacing ColorRect with Polygon2D.*
7. `b297d0cb` *Revert muzzle flash brightness to backup values per owner feedback.*
8. `608f0b22` *Add additive `FloorGlow` sprite to muzzle flash for visible floor flashes.*
9. `7adeb4bc` *Fix square artifact in FloorGlow by ensuring gradient alpha reaches 0 before texture edge.*

The final state of that branch kept the additive `FloorGlow` approach and reverted the environment-level edits. The owner still reported the problem unfixed *and* reported a new "square flash" artefact (comment at 2026-04-20 10:27), so the PR was closed.

## 3. System under investigation

### 3.1 Muzzle flash effect (current `main` state)

- Scene: `scenes/effects/MuzzleFlash.tscn`
  - `Node2D` root, `z_index = 10`
  - `GPUParticles2D` — orange particle burst (`lifetime = 0.04 s`, `amount = 5`)
  - `PointLight2D` — `color = (1, 0.8, 0.4, 1)`, `energy = 0`, `shadow_enabled = true`, `texture_scale = 4.5`, texture is a 512×512 radial gradient.
- Script: `scripts/effects/muzzle_flash.gd`
  - `FLASH_DURATION = 0.3 s`, `LIGHT_START_ENERGY = 4.5`.
  - `PointLight2D.energy` is pulsed to `LIGHT_START_ENERGY` on `_ready()` and faded with an ease-out curve `(1 − t)²` to zero over `FLASH_DURATION`.

### 3.2 Labyrinth Complex level

- Scene: `scenes/levels/Labyrinth2Level.tscn`, 3328 × 2528 pixels.
- `Environment/Background` = `ColorRect`, colour `(0.05, 0.05, 0.08, 1)` (near-black).
- `Environment/Floor` = **`ColorRect`**, colour `(0.17, 0.15, 0.13, 1)` (dark warm grey).
- Walls, interior walls, and cover are `ColorRect` children of `StaticBody2D`s, with `LightOccluder2D` children using `OccluderPolygon2D` shapes.
- Script: `scripts/levels/labyrinth2_level.gd`
  - `_setup_room_warm_lights()` (line 258) dynamically adds **11 warm `PointLight2D`s** at zone centres, `color = (1.0, 0.75, 0.3, 1.0)`, `energy = 0.7 – 0.85`, `texture_scale = 3.5 – 4.5`, `shadow_enabled = true`, `SHADOW_FILTER_PCF5`.
  - `_create_ambient_moonlight()` (line 463) adds a scene-wide `DirectionalLight2D`, `energy = 0.06`.
  - Additional window `PointLight2D`s are added by `_setup_window_lights()` (line 380+).

### 3.3 The critical Godot fact

In Godot 4, `Light2D`/`PointLight2D` modulate the pixels of **`CanvasItem`** nodes (`Sprite2D`, `AnimatedSprite2D`, `Polygon2D`, `TileMapLayer`, custom `_draw`, etc.). **`ColorRect` is a `Control` node**, and although `Control`s inherit from `CanvasItem`, the way `ColorRect` emits its quad in the renderer does participate in the 2D light pipeline, *but* it has no albedo texture — its colour is taken from `color`, which is multiplied by the computed light. On top of that, because `ColorRect`'s `light_mask` defaults to `1`, and the muzzle `PointLight2D` also defaults to `1`, the light-to-canvas matching is already aligned.

What actually causes the perceptual problem is **not** layering — it is **saturation plus dynamic range**:

- The 11 warm ceiling lights already push the floor colour from `(0.17, 0.15, 0.13)` to around `(0.35 – 0.55, 0.30 – 0.45, 0.18 – 0.28)` in mid-zones, and far higher right under the lamps.
- A muzzle-flash `PointLight2D` in Godot's additive `Light2D.BLEND_MODE_ADD` adds `light_texture.rgb × energy × color` on top. `energy = 4.5` with a falloff of `(1 − t)²` drops below perceptual threshold very quickly; and where ceiling light is already strong, any addition that does not exceed the already-bright floor value is not visible.
- Meanwhile, `GPUParticles2D` sparks, blood decals and casings start near black and unlit. Any flash "ADD" onto a near-black texel looks like a dramatic change.

So the bug is a **contrast** problem, not a wiring problem.

## 4. Root-cause analysis

Ranked by confidence.

### 4.1 Primary root cause: ambient saturation masks the pulse (high confidence)

Confirmed by walking through `_setup_room_warm_lights()` and comparing with `LabyrinthLevel` (first map), which has no such ambient lights. On `LabyrinthLevel` the floor is dark and every muzzle flash lights a visible disc; on `Labyrinth2Level` the same code path produces an imperceptible delta because `min(floor_after_ambient + flash_add, 1.0) ≈ floor_after_ambient`.

### 4.2 Secondary root cause: the flash texture itself has very low energy at radius > ~1.5× muzzle radius (medium confidence)

The gradient defined in `MuzzleFlash.tscn` falls from 1.0 → 0 over radius, multiplied again by the quadratic fade. Even under optimal conditions the total light contribution on the floor at ~80 px from the muzzle is small compared with the 4.5-energy ceiling cone at 512×4.5 = ~2300 px radius.

### 4.3 Tertiary issue: the attempted additive sprite (`FloorGlow`) produced a visible square artefact (reproducible from `7adeb4bc`)

The sprite used a `GradientTexture2D` with fill = radial. When you place a radial-gradient `Sprite2D` at a large scale with alpha that never quite reaches zero at the texture edge, the outline of the texture rectangle is visible as an abrupt brightness change — exactly what the owner reported ("странная квадратная вспышка"). The `7adeb4bc` fix bumped the final gradient stop to `(..., 0)` alpha but owner reported the artefact still present in `game_log_20260420_135251.txt`.

### 4.4 Ruled-out causes

- `light_mask`/`item_cull_mask`: both floor and light default to `1`, so the light already reaches the floor. Previous attempts to set these to `3` changed nothing.
- `ColorRect` not receiving light: verified by inspecting `main` `LabyrinthLevel`, which also uses `ColorRect` floors and shows perfectly visible muzzle flashes.
- `z_index`: both the floor and the muzzle flash are above 0, ordering is correct.
- Particles: work fine — confirmed by owner ("на частицах, крови, гильзах" видны).

## 5. Considerations for the next attempt

Given the owner's explicit constraints:

- *"верни яркость вспышки как в ветке backup"* — don't raise `LIGHT_START_ENERGY` further. `4.5` is already the requested value.
- *"мне нужно явная вспышка на стенах и явные тени от этой вспышки"* — the wall flash and the shadows from `LightOccluder2D` are already correct; they must not be removed.
- *"появилась странная квадратная вспышка"* — any added sprite/texture must have fully transparent edges and a gentle falloff. No visible quad outline.
- *"не исправлено"* (final verdict on PR #1846) — the additive `Sprite2D` approach alone is off the table; something else must happen.

### 5.1 Candidate directions

Each direction is independent; several can be combined.

1. **Reduce ambient saturation locally during the flash.** Temporarily drop the energy of the nearest `WarmLight_*` `PointLight2D`s while the muzzle flash is active so the floor's mid-grey level dips, making the `+4.5` pulse visible as a bright disc. Requires the muzzle flash to discover the N nearest room lights on `_start_effect` (use `get_tree().get_nodes_in_group("room_lights")` or scan under `Environment/RoomLights`) and pulse their energy down by, say, 40 % for 0.3 s.

2. **Additive floor-only decal via `CanvasGroup` or a dedicated `CanvasLayer`.** Put a `Sprite2D` with a premultiplied-alpha radial texture on a `CanvasGroup` that is set to `BLEND_MODE_ADD` and has `use_parent_material = false`. The premultiplied texture eliminates the edge artefact because the colour is 0 wherever alpha is 0. Use a circular alpha with a hard 0 floor — explicit `pow(1 − r, 2.2)` radial like the warm-light texture — to avoid the square edge.

3. **`BackBufferCopy` + shader.** A simple 2D shader on a sprite at the flash position can do `col.rgb = mix(col.rgb, col.rgb + vec3(1.0, 0.8, 0.4) * intensity * radial_falloff, 1.0)` while sampling from the back buffer. This guarantees any floor colour is ramped toward white, regardless of the ambient light level, and can cap at `vec3(1.0)` to avoid over-bright clipping. This is also how e.g. Brotato handles shooter impact lighting.

4. **Switch the floor `ColorRect` to a `Sprite2D` with a tileable texture** (subtle concrete noise) and enable `light_mask` matching. A textured floor receives light non-uniformly, which makes a local bright disc easier to see because the eye detects the *change* rather than a uniform brighter patch. This was partially attempted in commit `8522874a` (`ColorRect → Polygon2D`) and reverted; the key difference is that a *textured* surface shows the flash more clearly than a flat polygon.

5. **Increase the muzzle flash's `LIGHT_START_ENERGY` only on `Labyrinth2Level`.** Override via a per-level multiplier so the energy is, e.g., `4.5` on dark maps and `7.5` on Labyrinth Complex. Owner asked not to raise the flash brightness globally, but a local override targeted at this specific map may be acceptable.

### 5.2 Recommendation

Combine **(1) local ambient dip** + **(2) premultiplied additive sprite with true-zero edges**:

- The ambient dip removes the saturation problem that killed every earlier attempt, so `PointLight2D` alone becomes visible on the floor again.
- The premultiplied sprite adds a small, on-the-floor punch (the kind the owner kept asking for) without producing a square edge because its alpha is truly zero at the texture boundary.
- Neither change touches the wall lighting or the `LightOccluder2D` shadows, so the existing "явная вспышка на стенах и явные тени" behaviour is preserved.

This approach should be implemented in a single small PR with:

- a unit test that drives the ambient `PointLight2D`s for one frame and asserts the energy drop + recovery curve,
- an ad-hoc `experiments/` scene that places the muzzle flash in front of a `ColorRect` of the Labyrinth Complex floor colour under an 0.85-energy warm ceiling light, and visually confirms the disc is visible,
- baseline-and-after screenshots saved under `docs/screenshots/issue-1845/` so the owner can visually verify without re-running the game.

## 6. Attached evidence

- `issue.json` — raw issue body.
- `issue-comments.json` — every comment on issue #1845.
- `pr-1846.json`, `pr-1846-comments.json` — raw data of the closed PR (all nine rejected attempts).
- `pr-1913.json` — the current WIP PR.
- Eight `game_log_*.txt` files — the complete sequence of logs the owner attached across the feedback loop.

## 7. Open questions for the owner

1. Is it acceptable to *temporarily* dim the closest room lights (~40 % for 0.3 s) while a weapon is fired, or does that break the desired "museum of warm lights" ambience?
2. On dark maps where the muzzle flash is already highly visible, should the new floor glow also be active, or should it be Labyrinth-Complex-specific?
3. The "square flash" artefact appeared after commit `608f0b22`. Can the owner confirm whether any earlier attempt produced the desired floor flash, so we can triangulate from a known-good state?

## 8. References

- Godot 4 docs — 2D Lights and Shadows: <https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html>
- Godot 4 docs — `Light2D` blend modes: <https://docs.godotengine.org/en/stable/classes/class_light2d.html>
- Issue `#1291` — warm ceiling lights feature that created the saturation baseline in the first place.
- Issue `#1776`, `#1752` — prior muzzle/flashlight shadow enablement, informing the current `shadow_enabled = true` configuration.
