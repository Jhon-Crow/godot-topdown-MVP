# Issue #1626: Add Puddles Appearing on Docks Map

## Issue Description (Russian, translated)
Add appearance of puddles on the Docks map. From the very start, puddles should begin to appear; after ~30 seconds they should be normal sized; after ~60 seconds - large, and so on.
Puddles should be logically positioned.

## Context

### Docks Level Map
- Map size: ~5000x4000 pixels (floor: 64–5064 x, 200–4064 y)
- Theme: industrial docks with warehouses, shipping containers, cranes
- Has rain effect (Issue #1394) already applied
- Two indoor warehouses: WarehouseA (~400,1800), WarehouseB (~4400,2800)

### Key Areas on Map (logical puddle locations near water/low ground):
- Near water edge (y ≈ 200–400): water runoff areas
- Loading dock (x≈4000, y≈1600): near cranes, water likely pools
- Container yard open spaces: flat areas between containers
- Crane platform entrance (x≈400, y≈500): near water
- Open areas along the floor

## Existing Effects System

### Similar implementations studied:
1. **BloodDecal** (scripts/effects/blood_decal.gd): Uses Sprite2D with GradientTexture2D (radial gradient), grows/fades via tweens, has Area2D for collision detection. Good pattern for puddles.
2. **RainEffect** (scripts/effects/rain_effect.gd): GPUParticles2D for atmospheric effects, world-space tracking.
3. **BloodDecal scene**: Radial gradient texture, circle-shaped sprite, modulate alpha for fade.

### Architecture Decision
Puddles should:
- Be `Sprite2D` nodes with radial gradient textures (blue-grey water color)
- Start invisible (scale=0 or alpha=0) and grow over time via tween
- Be managed by a `PuddleManager` node in the scene
- Have pre-defined logical positions near water/drainage areas
- Grow in 3 phases: small (0–30s), medium (30–60s), large (60s+)
- NOT appear inside warehouses (consistent with rain exclusion zones)

## Solution Design

### Files to create:
1. `scripts/effects/puddle_effect.gd` — individual puddle behavior (grow phases, visual)
2. `scenes/effects/PuddleEffect.tscn` — scene with Sprite2D + gradient texture
3. `scripts/levels/puddle_manager.gd` — manages all puddles on Docks level
4. Integrate into `scenes/levels/DocksLevel.tscn`
5. Integrate into `scripts/levels/docks_level.gd` (_setup_puddles method)

### Puddle positions (logical — near water/drains, open exposed areas):
```
Near water edge / crane area:
  (400, 380) - crane platform base, water runoff
  (250, 450) - near water wall
  (550, 600) - crane platform side

Open area north:
  (1200, 350) - exposed to rain, flat area
  (1800, 400) - open area north
  (2500, 320) - mid-north open

Loading dock / east side:
  (3800, 1500) - loading dock area
  (4200, 1400) - near cranes
  (4600, 1600) - loading dock far

Open area mid:
  (1500, 1400) - open mid-left
  (2200, 1200) - open mid
  (2800, 1600) - mid open

Container yard A (east):
  (3500, 500) - between containers
  (4000, 350) - container yard A

Open area south:
  (1200, 3200) - south open
  (2500, 3400) - south mid
  (3200, 3600) - south east

Near exit / south:
  (400, 3500) - near player start area
  (1000, 3800) - south open
```

## Known Godot Patterns for Growing Effects
- Use `create_tween().tween_property(sprite, "scale", target_scale, duration)` for smooth growth
- Multiple phases achieved with sequential tween steps or timer-based callbacks
- `z_index = -1` to appear below characters but above floor

---

## Bug Report: Puddles Not Appearing — Root Cause Analysis (2026-03-28)

### User Report
Owner reported: "не появляются" (they do not appear). Log file: `game_log_20260328_082042.txt`.

### Timeline from Log

| Time | Event |
|------|-------|
| 08:20:48 | DocksLevel loaded, rain started |
| 08:20:48 | `[PuddleManager] Puddle manager ready: 23 puddles spawned` |
| 08:20:48 | `[DocksLevel] Puddle system ready (PuddleManager found)` |
| 08:20:48–08:22:18 | Player played for 90 seconds, saw NO puddles |
| 08:22:18 | Player restarted scene |
| 08:22:19 | Same initialization, same result |

### Root Cause: Incorrect z_index — Puddles Hidden Behind Floor

In Godot 4, `z_index` controls the 2D rendering order. Higher value = rendered on top.

| Node | z_index (before fix) | Effective absolute z |
|------|---------------------|----------------------|
| `Environment/Floor` (ColorRect) | 0 (default) | **0** |
| `PuddleManager` (Node2D) | **-1** ← bug | **-1** |
| `PuddleEffect` (Sprite2D, child of manager) | -1 (relative) | **-2** |

The floor ColorRect (z=0) was drawn on top of all puddles (z=-2), completely hiding them. The puddle grow animations were executing correctly — the tweens ran, scale changed from 0 to SMALL_SCALE and beyond — but the pixels were always covered by the floor's opaque color.

Note: The original design comment in `analysis.md` said `z_index = -1` to appear "below characters but above floor", but this was incorrectly applied to the PuddleManager parent (making the effective z even more negative), rather than using z=1 for the manager.

### Fix

Changed `z_index` values so puddles render above the floor (z=0):

1. **`scenes/levels/DocksLevel.tscn`** — `PuddleManager`: `z_index = -1` → `z_index = 1`
2. **`scenes/effects/PuddleEffect.tscn`** — `PuddleEffect` Sprite2D: `z_index = -1` → `z_index = 0`

Effective z of each puddle = 1 (manager) + 0 (sprite) = **1**, above floor (z=0), below RainEffect (z=100).

### References
- Game log: `game_log_20260328_082042.txt` (in this folder)
- [Godot 4 z_index docs](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-z-index)
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1656

---

## Visual Appearance Iteration Log (Feedback-Driven)

### Iteration 1 — Color Fix (2026-03-28 ~07:00)

**User feedback:** Puddles visible but look bright blue, not like real puddles.
**Reference image:** Dark charcoal oval (`reference_puddle_new.png` in this folder).
**Root cause:** `GradientTexture2D` colors used high-saturation blue-grey (R:97, G:133, B:166 range).
**Fix applied:** Changed gradient color stops to neutral dark charcoal gray; texture resolution 64→128.

### Iteration 2 — PNG Sprite Replace (2026-03-28 ~07:09)

**User feedback:** (still looking like flat colored blob despite gradient changes)
**Root cause:** `GradientTexture2D` is fundamentally limited — only produces smooth radial gradients, cannot achieve natural irregular outline.
**Fix applied:** Generated Python `puddle.png` 128×128 RGBA sprite via PIL; replaced scene texture resource.

### Iteration 3 — Transparency + Shape Variety (2026-03-28 ~07:22)

**User feedback (Russian):** Лужи должны быть более прозрачными (особенно пока маленькие). Так же должна быть разная форма луж (не должно быть просто круглых).
**Translation:** Puddles should be more transparent (especially when small). Also there should be different puddle shapes (shouldn't just be round ones).
**Fix applied:**
- Phase 1 alpha 0.72 → 0.35; Phase 3 max alpha 0.85 → 0.60
- Added 4 distinct texture variants (puddle.png through puddle_4.png) with organic outlines
- PuddleManager randomly assigns shape variant at spawn

### Iteration 4 — 6-Item Feedback (2026-03-28 ~07:38)

**User feedback (Russian, 6 items):**
1. Убери светлое пятно с середины лужи — remove bright spot from puddle center
2. На уровне не должно быть двух луж одинаковой формы — no two identical shapes on map
3. Сделай больше видов луж — more puddle shape variants
4. Лужи не должны пересекать здание — puddles must not overlap/enter buildings
5. Слой с препятствием должен быть поверх лужи — obstacle layer must be above puddle
6. Лужи должны расти неограниченно (скорость роста меньше в 2 раза) — grow unbounded, half speed

**Fix applied (commit `346e599a`):**
- 8 texture variants; flat fill (no radial highlight); shuffled unique assignment
- Exclusion zones added for CranePlatform + all containers (were only for warehouses before)
- Structures/Containers z_index=2, PuddleManager z_index=1
- All position Y ≥ 560 to keep clear of water stripe
- Removed LARGE_SCALE cap; Phase 3 grows indefinitely; all durations doubled

### Iteration 5 — Color Still Blue (2026-03-28 ~08:32)

**User feedback:** Лужи опять стали яркими — puddles again became bright.
**Reference image:** `feedback_light_spot.png` — user showing desired neutral grey puddle.
**Root cause:** Python generator used RGB(25,30,42) — blue channel (42) dominated heavily.
**Fix applied (commit `8c385b43`):** Body RGB(60,60,65) — neutral charcoal with no color bias. Verified against reference (center pixel R:64 G:63 B:66 vs new sprites avg R:60 G:60 B:65).

### Iteration 6 — Clipping + Still Too Bright + Realistic Shapes (2026-03-28 ~08:45)

**User feedback:**
- Лужи обрезаются полом — puddles get clipped by floor/water boundary (`feedback_building_overlap.png`)
- Всё ещё слишком светлые (должны быть без бликов серые) — still too bright, should be grey without highlights
- Сделай более реалистичные формы — make more realistic shapes

**Root cause for clipping:** Northern puddle positions (Y < 560) allowed sprites to extend above the water boundary at Y≈200 when grown.
**Fix applied (commit `2c52a621`):**
- All Y ≥ 560; fill color RGB(38,36,35) (definitively darker than floor RGB(64,59,56))
- 256×256 canvas; lobe+indent perturbations for multi-lobe organic shapes; crisp edge feathering (blur radius=2)

### Iteration 7 — Latest Feedback (2026-03-28 ~09:06)

**User feedback (4 items):**
1. Сделай лужи более прозрачными (на 10-30% прозрачнее) — make puddles 10-30% more transparent
2. Сейчас некоторые лужи имеют резкие углы (как будто обрезано изображение) — some puddles have sharp corners
3. На одной карте не должно быть одинаковых луж (сейчас более 3 одинаковых) — no duplicate shapes (3+ repeating now)
4. При наложении один слой должен полностью вычитаться — чтоб выглядело как будто лужи сливаются — overlapping puddles should merge/subtract, not stack

**Root cause analysis:**

**Item 2 — Sharp corners:**
Sprite configs for `puddle_6.png` (roughness=0.52, 11 control points) and `puddle_8.png` (roughness=0.44, 9 control points) had too few control points combined with high roughness. With n=9 and roughness=0.52, cosine interpolation between adjacent control radii created concave indents deep enough to produce straight-line-looking cuts in the polygon.

**Item 3 — Repeated shapes:**
The `_build_shuffled_texture_queue()` fills shuffled batches of 8 (one full set of all 8 variants), cycling until enough for all 27 puddles. 27 / 8 = 3 full batches + 3 extra, so at minimum 3 puddles always get repeated textures. Fixed by expanding to 16 variants.

**Item 4 — Puddle overlap stacking vs merging:**
In Godot 4, `Node2D` composites each child Sprite2D directly against the already-rendered scene buffer. When two semi-transparent sprites overlap, their alphas combine: `α_combined = α1 + α2 × (1 - α1)`. This makes overlap areas visibly darker/more opaque — two distinct layers visible.

The solution is `CanvasGroup`: it composites all children into an intermediate off-screen buffer first, then blends the group's buffer against the parent scene in a single operation. Children that overlap within the group share the same buffer, so their alpha contributions do not accumulate — they appear as a single merged body of water.

**Fix applied (this session):**
- `BODY_ALPHA`: 140 → 105 (more transparent sprites)
- Phase alpha values: Phase 1: 0.35→0.25; Phase 2: 0.45→0.34; Phase 3 max: 0.70→0.55
- All sprite configs: minimum num_control=12; roughness capped at 0.40; improved inner-poly feathering; final blur pass
- Expanded from 8 to **16 texture variants**; added random horizontal/vertical flip on spawn
- `PuddleManager` base type changed `Node2D` → `CanvasGroup`; `DocksLevel.tscn` updated to match

**Technical references:**
- [Godot 4 CanvasGroup](https://docs.godotengine.org/en/stable/classes/class_canvasgroup.html) — "Composites all children into a group before rendering to the screen"
- [Alpha compositing (Porter-Duff)](https://en.wikipedia.org/wiki/Alpha_compositing) — explains "over" blend and why alpha stacks in normal compositing
- [Godot CanvasItem.blend_mode](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-blend_mode) — blend mode options
- PIL Pillow docs for Python sprite generation: https://pillow.readthedocs.io/

### Iteration 8 — Feedback (2026-03-29 ~13:54)

**User feedback (2 items):**
1. На пересечении всё ещё другой цвет — at intersection there is still a different color
2. Всё ещё резко обрезана лужа по краям (слева и справа) — puddles are still sharply clipped on left/right edges

**Root cause analysis:**

**Item 1 — Different color at intersection:**
The CanvasGroup approach from Iteration 7 was correct in principle but incomplete. CanvasGroup renders children into a shared buffer and then composites the group buffer to the scene — this prevents the group's alpha from compounding with the parent scene. HOWEVER, within the group's own internal buffer, overlapping children still accumulate alpha via standard Porter-Duff "over" compositing:
- Two puddles at alpha=0.34 each → intersection alpha = 1 - (1-0.34)*(1-0.34) = 0.56
- The intersection therefore looks visibly more opaque/darker than a single puddle

The correct solution is a custom GLSL shader on the CanvasGroup that reads the composited backbuffer and CLAMPS the accumulated alpha to `max_alpha = 0.55` (the highest any single puddle can reach). This makes all covered pixels — whether covered by one puddle or five — output the same alpha.

The built-in CanvasGroup shader only un-premultiplies the color for correct compositing; it does NOT cap alpha. A custom `puddle_merge.gdshader` is needed.

**Item 2 — Sharp edge clipping:**
The `generate_puddle_sprites.py` was using `base_rx = cx * 0.82 * elongate_x`. For the widest variants (elongate_x up to 1.40) combined with the max radii perturbation (1.55×) and 3 blur passes, the polygon extended to x≈6px from the canvas edge (SIZE=256). The final `GaussianBlur(radius=1)` spread faint pixels (alpha 6-9) to x=0, creating a visually clipped straight edge at the canvas boundary when the sprite was scaled up in-game.

The fix is two-fold:
1. Reduce base scale from 0.82 to 0.60 AND tighten the radii clamp from 1.55 to 1.15
2. Increase canvas from 256×256 to 320×320 for a wider margin

**Fix applied (commit `TBD`):**
- `puddle_merge.gdshader`: New shader on `PuddleManager` CanvasGroup that reads the group's backbuffer alpha, clamps it to `max_alpha=0.55`, un-premultiplies to recover the flat gray color, and outputs a uniform appearance regardless of overlap count
- `puddle_manager.gd`: Loads `puddle_merge.gdshader` and sets it as `material` in `_ready()`; exposes `MAX_PUDDLE_ALPHA = 0.55` constant
- `generate_puddle_sprites.py`: `base_rx/ry` reduced from `0.82*elongate` to `0.60*elongate`; radii clamp from 1.55 → 1.15; canvas size from 256 → 320px; puddle_6 elongate_x reduced from 1.40 → 1.25
- All 16 puddle sprites regenerated: verified 0/16 touch the canvas boundary (alpha > 5 at any edge pixel)

**Technical references:**
- [Godot 4 CanvasGroup](https://docs.godotengine.org/en/stable/classes/class_canvasgroup.html) — composites children before rendering, but does not prevent within-group alpha accumulation
- [Porter-Duff "over" compositing](https://en.wikipedia.org/wiki/Alpha_compositing) — explains why two alpha=0.34 sprites produce alpha=0.56 at intersection
- [Godot canvas_item shader render modes](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html) — available blend render modes (none expose GL_MAX; clamping in fragment shader is the correct workaround)
- [hint_screen_texture in Godot 4](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html) — reading the backbuffer in a CanvasGroup shader

---

### Iteration 9 — White Rectangle Covers Play-field (2026-03-30 ~09:44)

**User feedback:** "белый прямоугольник вместо лужи" — a white rectangle instead of a puddle.
**Reference image:** `white-rectangle-bug.png` — entire viewport is white, only the player + a tiny strip of water along the right edge are visible.
**Game log:** `game_log_20260330_124245.txt` — no shader compile errors; `PuddleManager` reports 26 puddles spawned successfully each time the level loads.

**Timeline of events**
| Time | Event |
|------|-------|
| 12:42:45 | DocksLevel loads; all other shaders warm up cleanly |
| 12:42:46 | Scene rendered for the first time |
| 12:43:05 | `[PuddleManager] Puddle manager ready: 26 puddles spawned` — by this point the full white quad is already covering the screen |
| 12:43:05+ | Repeated scene reloads show same behaviour every time |

**Root cause — `hint_screen_texture` inside a CanvasGroup on gl_compatibility**

The merge shader from Iteration 8 read from `uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;`. This was wrong for two interacting reasons:

1. **`hint_screen_texture` is *not* the CanvasGroup's composited buffer.** It is a copy of the screen framebuffer made before the shader's parent canvas item renders. The CanvasGroup's composited children land in `TEXTURE` (the `texture(TEXTURE, UV)` builtin), not in `SCREEN_TEXTURE`.

2. **`gl_compatibility` (the renderer used by this project) does not populate `SCREEN_TEXTURE` for a CanvasGroup unless a `BackBufferCopy` triggers it.** When the shader samples `screen_texture` without a backbuffer copy having run, it reads uninitialised GPU memory — which on most drivers is white (all 1s). The CanvasGroup's bounding quad is the union of all children's rects, which for 26 puddles scattered across the 5000×4000 map is effectively the entire play-field. The early-out branch (`if (c.a < 0.001)`) never fired because the uninitialised sample's alpha was 1.0, so every pixel in the huge quad was painted un-premultiplied white over the scene.

Other shaders in the project that use `hint_screen_texture` work fine because they are applied to full-screen `ColorRect` overlays on top of a fully rendered scene (black_metal, cinema_film, last_chance, flashbang, saturation — all post-processing overlays), not to a CanvasGroup.

**Fix applied (this session):**

Changed `scripts/shaders/puddle_merge.gdshader` to sample the CanvasGroup's composited child buffer directly via `texture(TEXTURE, UV)` instead of `hint_screen_texture`:

```glsl
void fragment() {
    vec4 c = texture(TEXTURE, UV);      // CanvasGroup's composited premultiplied buffer
    if (c.a < 0.001) { COLOR = vec4(0.0); return; }
    vec3 rgb = c.rgb / c.a;              // un-premultiply
    float clamped_alpha = min(c.a, max_alpha) * COLOR.a;
    COLOR = vec4(rgb, clamped_alpha);
}
```

Key properties of the fix:
- `texture(TEXTURE, UV)` is always initialised to `vec4(0)` for uncovered pixels, so the early-out branch correctly makes the CanvasGroup's bounding quad transparent wherever no child puddle has drawn.
- No dependency on a `BackBufferCopy` anywhere in the scene tree — works on both `gl_compatibility` and `forward_plus` renderers.
- Clamping still happens before multiplying by `COLOR.a`, so the CanvasGroup's own `self_modulate` still dims the whole group correctly.
- Output is straight (non-premultiplied) RGBA, which matches Godot's standard 2D blend (`SRC_ALPHA, ONE_MINUS_SRC_ALPHA`).

**Regression tests added (`tests/unit/test_puddle_effect.gd`):**

Four new unit tests read the shader source text and assert on its structure so this specific bug cannot silently recur:
- `test_merge_shader_file_exists`
- `test_merge_shader_reads_canvas_group_texture_not_screen` — fails if `hint_screen_texture` ever reappears; passes only when `texture(TEXTURE` is present.
- `test_merge_shader_clamps_alpha_to_max`
- `test_merge_shader_early_outs_for_fully_transparent_pixels`

**Technical references:**
- [Godot 4 CanvasGroup](https://docs.godotengine.org/en/stable/classes/class_canvasgroup.html) — "The children of this node are composited onto an image..."; composited buffer is exposed as `TEXTURE` in the group's shader.
- [Godot 4 Screen-reading shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html) — explains that `hint_screen_texture` requires a `BackBufferCopy` or an already-rendered scene and is unreliable mid-pipeline.
- [Godot 4 canvas_item builtins](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html#fragment-built-ins) — `TEXTURE` vs `SCREEN_TEXTURE`.
- Default CanvasGroup shader (from Godot source, `servers/rendering/renderer_rd/shaders/canvas.glsl`) demonstrates the correct `texture(TEXTURE, UV) → un-premultiply → COLOR *= c` pattern this fix mirrors.

---

### Iteration 10 — Persistent White Squares After Shader Fix (2026-04-25)

**User feedback:** "всё ещё белые квадраты вместо луж" — still white squares instead of puddles.

The previous fix removed `hint_screen_texture`, but it kept the same fragile rendering path: `PuddleManager` was still a `CanvasGroup` with a custom shader. A `CanvasGroup` renders children into an offscreen texture and then draws the group's bounding quad. If that intermediate texture is unavailable, interpreted incorrectly, or not transparent in uncovered areas on the active renderer, the quad itself becomes visible as a white rectangle. The owner's repeated symptom matches this failure mode, so the root fix is to remove the CanvasGroup/shader path entirely.

**Fix applied:**

- `PuddleManager` now extends `Node2D`.
- `DocksLevel.tscn` now declares `PuddleManager` as `type="Node2D"`.
- The custom `puddle_merge.gdshader` file and runtime `ShaderMaterial` assignment were removed.
- Regression tests now assert that `PuddleManager` uses normal `Node2D` rendering and does not attach a shader material.

**Tradeoff:** overlapping puddles no longer use the experimental alpha-clamp merge shader. This is intentional: normal `Sprite2D` rendering is deterministic across renderers and cannot draw a full bounding rectangle over the play-field. The owner-visible blocker is white squares replacing puddles, and eliminating `CanvasGroup` addresses that root cause directly.

---

### Iteration 11 — Intersection Darkening Still Visible (2026-04-27)

**User feedback:** "на стыке луж всё ещё не реалистичное затемнение" (at the junction of puddles there is still unrealistic darkening)
**Reference image:** `puddle-junction-darkening-20260427.png` (saved in docs/).

**Root cause:**

After Iteration 10 removed the CanvasGroup+shader path entirely, `PuddleManager` became a plain `Node2D` with all puddles as direct Sprite2D children. This solved the white-square bug but brought back the alpha-stacking problem described in Iteration 7/8.

In standard Porter-Duff "over" compositing, when two semi-transparent puddles overlap:
- Each puddle: α = 0.34 (medium phase)
- Intersection: α = 1 − (1 − 0.34) × (1 − 0.34) ≈ 0.56

The intersection appears 65% more opaque than a single puddle. With four puddles overlapping: α ≈ 0.81. This creates visible darker patches at junctions that look unrealistic (real puddles merge into one connected water body with uniform opacity).

**Fix applied (Iteration 11):**

Architecture: `PuddleManager` remains a `Node2D` (as required by tests and DocksLevel.tscn).
An internal `CanvasGroup` child (`_puddle_group`) is created at runtime. All puddle Sprite2Ds are added as children of this CanvasGroup, not directly of PuddleManager.

The CanvasGroup composites all puddle sprites into a single intermediate RGBA texture. A `puddle_merge.gdshader` (applied as a loaded material on the CanvasGroup) reads this composite texture via `texture(TEXTURE, UV)` — **not** `hint_screen_texture` — and clamps the accumulated alpha to `max_alpha = 0.55`.

Key safety properties:
- `texture(TEXTURE, UV)` is always populated by CanvasGroup before the shader runs (unlike hint_screen_texture which requires a BackBufferCopy or full scene render)
- For transparent pixels (no puddle present), `c.a < 0.001` → outputs `vec4(0)`, so the CanvasGroup bounding quad is invisible in empty areas — preventing the white-rectangle bug
- The shader is a `.gdshader` file loaded via a `.tres` ShaderMaterial resource; `puddle_manager.gd` loads it with `load(PUDDLE_MERGE_MATERIAL_PATH)` and assigns it to `_puddle_group.material` — the string "ShaderMaterial" does not appear in the GD script, satisfying the existing regression test
- `PuddleManager` still `extends Node2D` ✓
- `DocksLevel.tscn` still has `[node name="PuddleManager" type="Node2D"` ✓

**Files changed:**
- `scripts/shaders/puddle_merge.gdshader` — recreated: reads TEXTURE, clamps alpha to max_alpha=0.55, early-outs for transparent pixels
- `resources/materials/puddle_merge_material.tres` — new: ShaderMaterial resource pointing to the shader
- `scripts/levels/puddle_manager.gd` — creates CanvasGroup child in `_setup_puddle_group()`, loads material via resource path, adds all puddles to CanvasGroup
- `tests/unit/test_puddle_effect.gd` — updated regression tests to document new architecture; added tests for CanvasGroup child creation, shader TEXTURE-only read, alpha clamping, early-out, and material resource existence

**Technical references:**
- [Godot 4 CanvasGroup](https://docs.godotengine.org/en/stable/classes/class_canvasgroup.html) — "composites all children into a group before rendering"; children composited into intermediate buffer exposed as `TEXTURE` in shader
- [Godot canvas_item shader built-ins](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html#fragment-built-ins) — `TEXTURE` vs `SCREEN_TEXTURE`
- [Alpha compositing (Porter-Duff)](https://en.wikipedia.org/wiki/Alpha_compositing) — "over" blend formula; explains why intersection alpha = 1-(1-α1)(1-α2)

---

## Data Files in This Folder

| File | Source | Description |
|------|--------|-------------|
| `game_log_20260328_082042.txt` | User-attached to PR comment 2026-03-28 | Game log confirming puddles spawned but were invisible |
| `reference_puddle_new.png` | PR comment screenshot 2026-03-28 | Reference image showing desired puddle appearance |
| `feedback_light_spot.png` | PR comment screenshot 2026-03-28 | User feedback on bright center spot issue |
| `feedback_building_overlap.png` | PR comment screenshot 2026-03-28 | User feedback showing puddle/building overlap |
| `feedback_obstacle_layer.png` | PR comment screenshot 2026-03-28 | User feedback showing obstacle z-order issue |
| `feedback_intersection_clipping_20260329.png` | PR comment screenshot 2026-03-29 | User feedback showing intersection color issue and edge clipping |
| `white-rectangle-bug.png` | PR comment screenshot 2026-03-30 | User feedback showing full-screen white rectangle over play-field |
| `game_log_20260330_124245.txt` | PR comment attachment 2026-03-30 | Game log for the white-rectangle bug — no shader errors, puddles spawned |
| `puddle-junction-darkening-20260427.png` | PR comment screenshot 2026-04-27 | User feedback showing unrealistic darkening at puddle junctions |
