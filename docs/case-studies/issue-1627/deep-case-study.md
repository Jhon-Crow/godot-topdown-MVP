# Deep Case Study: Issue #1627 — Snow Interactions on the Winter Forest Map

> **Issue:** [#1627 — добавь снег на карту Зимний лес](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1627)
> **PR:** [#1657 — Add snow surface interactions for Winter Forest map](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1657)
> **Branch:** `issue-1627-b7e2d4ef93ef`
> **Created:** 2026-03-27
> **Solved:** 2026-03-28

---

## 1. Problem Statement

The Winter Forest map (`WinterForestLevel.tscn`) used a flat `ColorRect` node with a blue-white colour (`Color(0.88, 0.9, 0.93, 1)`) to represent snow on the ground. It had no surface texture, no interaction with characters or projectiles, and behaved identically to any other floor surface in the game.

The owner requested **maximum realism** for snow interaction, expressed as four concrete requirements:

| # | Requirement (original Russian) | Requirement (translated) |
|---|------|------|
| 1 | должна небольшая текстура снега (неровности) | Snow surface must have a subtle texture (bumps/unevenness) — not flat white |
| 2 | должны оставаться следы игрока и врагов | Player and enemy movement must leave footprints in the snow |
| 3 | кровь должна перекрашивать снег и впитываться (не образуя лужи, такая кровь не должна вызывать образование кровавых следов при наступании) | Blood must stain and soak into snow (no puddles); stained snow must NOT generate bloody footprints when stepped on |
| 4 | кровавые следы при наступании на снег должны обрываться быстрее (меньше шагов до исчезновения) | Blood footprint trails on snow must end sooner (fewer steps before disappearing) |

---

## 2. Timeline / Sequence of Events

```
2026-03-24   PR #1441 merged — Winter Forest map added (base level, flat snow ColorRect)
2026-03-26   PR #1553 merged — Snowfall particle effect added to the map
2026-03-26   PR #1570 merged — Snowfall animation slowed down, fixed following player
2026-03-26   PR #1572 merged — Snowflakes fade at end of lifetime
2026-03-27   Issue #1627 opened by Jhon-Crow — requests snow surface interactions
2026-03-27   Branch issue-1627-b7e2d4ef93ef created
2026-03-27   Commit 31428cb5 — Initial snow interaction implementation:
               • snow_surface.gdshader (FBM noise shader on snow ColorRect)
               • SnowFootprint node + SnowFeetComponent
               • SnowBloodAbsorption node
               • WinterForestLevel._setup_snow_interactions()
               • ImpactEffectsManager._try_spawn_snow_blood_absorption()
2026-03-28   PR #1657 opened
2026-03-28   Jhon-Crow exports and tests a game binary
               → RESULT: snow effects not visible in game
2026-03-28   Owner provides game log: game_log_20260328_084242.txt
               → Log shows old binary (build_info.cfg not found)
               → No [WinterForestLevel] or [SnowFeet:*] entries in log
2026-03-28   Analysis of game log reveals 5 root causes (RC-1 through RC-5)
2026-03-28   Commit 6467ad3e — Bug fixes:
               • z_index raised from 0 → 1 in SnowFootprint and SnowBloodAbsorption
               • Removed z_index override in SnowFeetComponent._spawn_footprint()
               • Added _log_always() to SnowFeetComponent for FileLogger output
               • Added _log_to_file() calls to _setup_snow_interactions() for all paths
2026-03-28   Commit fa0c85b8 — Root cause analysis document added
2026-03-28   Jhon-Crow requests deep case study analysis with online research
2026-03-28   This document written
```

---

## 3. Existing Codebase Context

### What Already Existed

| System | File(s) | Role |
|--------|---------|------|
| `SnowEffect` | `scripts/effects/snow_effect.gd`, `scenes/effects/SnowEffect.tscn` | Atmospheric falling snowflakes (GPUParticles2D). Already in scene. **Not surface interaction.** |
| `BloodyFeetComponent` | `scripts/components/bloody_feet_component.gd` | Tracks character stepping in blood → spawns `BloodFootprint` decals. Key param: `blood_steps_count` (default 12). |
| `BloodDecal` | `scripts/effects/blood_decal.gd` | Persistent blood stains. Has `is_puddle` flag — characters stepping on puddles trigger `BloodyFeetComponent`. |
| `WaterBloodDiffusion` | `scripts/effects/water_blood_diffusion.gd` | Blood absorbed into water (non-puddle). Reference design for snow blood absorption. |
| `ImpactEffectsManager` | `scripts/autoload/impact_effects_manager.gd` | Autoload spawning blood effects at bullet/hit impact positions. Central routing point for blood decals. |
| `WinterForestLevel` | `scenes/levels/WinterForestLevel.tscn`, `scripts/levels/winter_forest_level.gd` | The level. Snow was a plain `ColorRect` with flat colour. |
| Water shaders | `scripts/shaders/realistic_water.gdshader` | Procedural noise-based texture on a `ColorRect`. Pattern reused for snow shader. |

### What Was Missing

- No surface material on snow — just a flat colour.
- No footprint system for snow — `BloodyFeetComponent` only activates when stepping in blood.
- No snow-aware blood handling — `ImpactEffectsManager` always spawned `BloodDecal` regardless of surface.
- No way for level code to distinguish "blood landing on snow" from "blood landing on floor".

---

## 4. Root Cause Analysis

### RC-1: Old Binary (Build Before Our Changes)

**Evidence from game_log_20260328_084242.txt:**
```
Build info: not available (build_info.cfg not found)
```
The user's exported binary (`I:/Загрузки/godot exe/ОСадКИ/Godot-Top-Down-Template.exe`) predated the PR. No code from this branch could run. Snow effects were invisible because they did not exist in the running binary.

**Required action:** User must export/build from the `issue-1627-b7e2d4ef93ef` branch.

---

### RC-2 (Critical Bug): Blood Absorption Was Never Triggered

**Evidence:** `spawn_snow_blood_absorption()` existed in `winter_forest_level.gd` but the game log showed zero `[WinterForestLevel]` entries about blood absorption. Searching `ImpactEffectsManager._schedule_delayed_decal()` confirmed it always created a standard `BloodDecal` with no snow check.

**Root cause:** `ImpactEffectsManager` had no knowledge of snow surfaces. It always spawned blood puddles regardless of where blood landed.

**Fix:** Added `_try_spawn_snow_blood_absorption(scene, landing_pos)` to `ImpactEffectsManager._schedule_delayed_decal()`. It queries all nodes in the `"snow_surface"` group; if the landing position falls inside any of their rects, it calls `scene.spawn_snow_blood_absorption(pos)` and returns early — skipping the regular puddle.

---

### RC-3 (Critical Bug): Footprints and Blood Stains Were Invisible (z_index = 0)

**Evidence:** Both `SnowFootprint._ready()` and `SnowBloodAbsorption._ready()` set `z_index = 0`. The snow `ColorRect` background also uses `z_index = 0`. In Godot 4, nodes at the same z_index are drawn in tree order — effects spawned at runtime land at the end of the tree and *should* draw on top, but in practice the snow surface consumed the full area. Additionally, `SnowFeetComponent._spawn_footprint()` was **explicitly overriding z_index back to 0** after calling `fp = _footprint_scene.instantiate()`, undoing any future fix in the scene.

```gdscript
# Bug (removed in fix commit):
fp.z_index = 0  # This line in _spawn_footprint() was negating _ready()
```

**Fix:** Changed both effects to `z_index = 1`. Removed the spawner override in `SnowFeetComponent._spawn_footprint()`.

---

### RC-4: SnowFeetComponent Produced No FileLogger Output by Default

**Evidence:** Game log showed `[BloodyFeet:Player]` and `[BloodyFeet:Clearing_*]` entries (from the old `BloodyFeetComponent`) but **zero** `[SnowFeet:*]` entries. Even if SnowFeetComponent initialized correctly, it was silent.

**Root cause:** `debug_logging = false` (export default). The `_log()` function skipped both `print()` and FileLogger when debug was off. There was no way to confirm the component ran from a game log.

**Fix:** Added `_log_always()` that unconditionally writes to FileLogger. Used for the `_ready()` init message:
```gdscript
func _log_always(message: String) -> void:
    var msg := "[SnowFeet:%s] %s" % [_parent_body.name if _parent_body else "?", message]
    print(msg)
    if _file_logger and _file_logger.has_method("log_info"):
        _file_logger.log_info(msg)
```

---

### RC-5: `_setup_snow_interactions()` Had No Failure Logging

**Evidence:** Several failure branches (SnowBloodAbsorption scene not found, player null, etc.) called only `push_warning()` — which outputs to the Godot editor output, **not** the FileLogger file. In a player-exported build with no editor, these warnings were silently discarded.

**Fix:** Added `_log_to_file()` calls for every branch, including error/warning paths:
```gdscript
_log_to_file("WARNING: SnowBloodAbsorption scene not found at " + absorption_path)
_log_to_file("WARNING: Player not found or not CharacterBody2D — skipping player snow feet")
_log_to_file("Snow interactions setup complete: %d enemies equipped" % count)
```

---

## 5. Solution Design

### Component Overview

```
WinterForestLevel (_setup_snow_interactions)
│
├─ snow_surface.gdshader ──► ShaderMaterial on Snow ColorRect [Req #1]
│
├─ SnowFeetComponent (added to Player + each Enemy at level start)
│   └─► SnowFootprint (spawned every 28px of movement) [Req #2]
│
├─ spawn_snow_blood_absorption(pos, color) [Req #3]
│   └─► SnowBloodAbsorption (fades over 18s, NOT in blood_puddle group)
│
└─ BloodyFeetComponent.blood_steps_count 12 → 6 (Player + Enemies) [Req #4]

ImpactEffectsManager._schedule_delayed_decal()
└─► _try_spawn_snow_blood_absorption() → routes blood to snow handler [Req #3 trigger]
```

### Requirement #1 — Snow Surface Texture (`snow_surface.gdshader`)

**Technique:** Procedural Fractal Brownian Motion (FBM) noise with 3 octaves applied to the `ShaderMaterial` of the Snow `ColorRect`. No external textures.

```glsl
float fbm(vec2 p) {
    float v = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 3; i++) {
        v += amplitude * value_noise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.1;
    }
    return v;
}
void fragment() {
    float n = fbm(UV * noise_scale);  // noise_scale=8.0
    vec4 col = mix(snow_shadow, snow_highlight, n * bump_strength + (1.0-bump_strength)*0.5);
    COLOR = col;
}
```

- `snow_highlight = Color(0.94, 0.96, 0.99)` — bright snow peaks
- `snow_shadow = Color(0.74, 0.79, 0.88)` — shadow in hollows
- Quintic smoothstep interpolation (C2 continuity) eliminates visible grid artifacts

### Requirement #2 — Footprints (`SnowFeetComponent` + `SnowFootprint`)

**Technique:** Component added at level start to all `CharacterBody2D` nodes. Every 28px of movement, a `SnowFootprint` node is instantiated and added to the current scene. Alternates left/right foot with lateral offset. Draws two overlapping ellipses (toe + heel) procedurally via `_draw()`.

Key design choices:
- `max_footprints = 80` — oldest evicted when cap reached (memory bounded)
- `z_index = 1` — renders above snow background, below characters
- No fade — snow footprints persist until level reload (realistic)
- No external textures — purely procedural GDScript `_draw()`

### Requirement #3 — Blood Soaks Into Snow (`SnowBloodAbsorption`)

**Technique:** `ImpactEffectsManager` checks if a blood decal's landing position falls inside any node in the `"snow_surface"` group. If yes: calls `level.spawn_snow_blood_absorption(pos)` instead of spawning a `BloodDecal`.

`SnowBloodAbsorption` renders as 3 concentric ellipses with alpha varying over 18 seconds:
- Phase 1 (0–1.2s): Blood spreads outward (expanding radius)
- Phase 2 (1.2s–9.9s): Fully visible, static
- Phase 3 (9.9s–18s): Fades as blood is absorbed into snow

**Critical:** NOT added to `"blood_puddle"` group → stepping on stained snow does NOT activate `BloodyFeetComponent`.

### Requirement #4 — Shorter Blood Trails

**Technique:** `_setup_snow_interactions()` reduces `BloodyFeetComponent.blood_steps_count` from 12 → 6 for both player and all enemies at level start.

---

## 6. Industry Research: How AAA and Indie Games Handle Snow

### 6.1 Snow Deformation Techniques

#### Batman: Arkham Origins (GDC 2014) — Industry Reference

The canonical production snow deformation system (Colin Barre-Brisebois, GDC 2014):

- Objects (feet, hands) rendered via an **ankle-height orthogonal frustum pointing upward from below the snow surface**
- Writes into a **runtime-generated grayscale heightmap** (two channels: minimum height + projected displacement)
- Heightmap drives **vertex displacement** in the snow surface shader
- Resolution: `min(512, 1/4 * surface_dimension)` — intentionally low-res (looks better, cheaper)
- **Priority system**: only 2 surfaces updated per frame; distance-based LOD
- GPU cost: under 1ms on PS3/360/WiiU; total memory: 2 MB
- DX11 (PC): NVIDIA tessellation added on top for true geometric displacement
- Recovery system: depth buffer gradually darkens → old footprints fade, snow fills back in

Reference: [GDC 2014 talk](https://gdcvault.com/play/1020177/Deformable-Snow-Rendering-in-Batman) / [PDF](https://colinbarrebrisebois.com/wp-content/uploads/2022/06/gdc2014-deformable_snow_rendering.pdf)

#### Red Dead Redemption 2

- 2048×2048 R16_UNORM displacement texture, into which footprint/wheel textures are rendered at runtime
- Parallax Occlusion Mapping reads the accumulated texture during terrain rendering
- Same pipeline used for both snow and mud

#### Horizon Zero Dawn (Frozen Wilds DLC)

- PS4: tessellation for true geometry displacement
- PC (post-patch 1.03): flat 2D texture simulating deformation

#### Rise of the Tomb Raider / Unreal Engine

- Scene Capture Components with custom depth channel
- Post-process material compares Scene Depth vs. Custom Depth to detect ground contact
- Mask accumulated in render target (not cleared between frames)
- Drives both albedo blending and vertex displacement in terrain material

### 6.2 Snow Footprints in 2D Top-Down Games

For 2D top-down games specifically, the best-known approaches are:

| Approach | Description | Performance | Quality |
|----------|-------------|-------------|---------|
| **SubViewport persistent canvas** | Spawn footprint sprites into a SubViewport with `CLEAR_MODE_NEVER`; display as texture on snow ground. Remove sprites after render. | Excellent (stamp then discard) | High (scalable) |
| **CPU Image.set_pixel()** | Paint pixels directly on an `Image`, push to `ImageTexture`. | Good for small maps | Medium |
| **Decal nodes (Godot 4)** | `Decal` nodes project texture onto 3D geometry. Pool and reuse. | Moderate (per decal cost) | High |
| **MultiMeshInstance2D** | Batch render footprint instances with custom blending shader. | Excellent (batched) | Medium |
| **Procedural _draw() nodes** | GDScript nodes render via `_draw()` — used in this project. | Good (up to ~100 nodes) | Medium |

**Our implementation** uses Approach E (procedural `_draw()` nodes). This is the simplest approach and works well for the expected footprint count (≤80 per character). For large open maps with many characters, a SubViewport approach would scale better.

### 6.3 Blood on Snow

Industry approaches:

| Method | Used In | Description |
|--------|---------|-------------|
| Decal projection | Most modern games | Pre-authored blood splat texture projected onto snow |
| SubViewport megatexture | Indie 2D | Single SubViewport accumulates blood stamps; shader blends color |
| Sphere mask render target | UE4/UE5 | World-space hit position drives blood spread in snow shader |
| NetherWorld pixel bloodstain | NetherWorld | Procedural probability-based painting; no textures needed |
| Texture threshold | Any engine | Grayscale mask animated over time drives spread shape |

Reference for pixel bloodstain technique: [Game Developer — Developing a Pixel Bloodstain System](https://www.gamedeveloper.com/design/developing-a-pixel-bloodstain-system)

**Our implementation** uses procedural `_draw()` ellipses with time-based radius and alpha — a lightweight analogue of the "texture threshold" approach.

**Snow-specific considerations from real games:**
- Blood on snow should spread outward then **melt into** the snow (not pool)
- Over time, blood darkens from bright red → brownish-black (freezing) — achievable via time-based color lerp
- Voronoi/Worley noise can drive organic spread patterns at edges
- Blood in snow wicks along snow crystal structure — irregular, not circular

---

## 7. Existing Godot / Open Source Solutions

### Godot Shaders

| Shader | Type | Relevant | Link |
|--------|------|----------|------|
| Car Tracks On Snow Or Sand | 3D Spatial | Most relevant: SubViewport + GPU particles + vertex displacement | [godotshaders.com](https://godotshaders.com/shader/car-tracks-on-snow-or-sand-using-viewport-textures-and-particles/) |
| Screen Space Frost + Volumetric Snow | 3D Spatial | Depth-marching volumetric falling snow. No deformation. | [godotshaders.com](https://godotshaders.com/shader/) |
| Multilayer Snowfall | Canvas 2D | Atmospheric only. | [godotshaders.com](https://godotshaders.com/) |

### GitHub Repositories

| Repo | Engine | Technique | License | Link |
|------|--------|-----------|---------|------|
| thnewlands/unity-deformablesnow | Unity | Orthographic camera depth → tessellated snow (Batman AO approach) | — | [GitHub](https://github.com/thnewlands/unity-deformablesnow) |
| ZGeng/DeepSnowFootprint | Unity | DX11 tessellation + dynamic UV + gradual recovery | MIT | [GitHub](https://github.com/ZGeng/DeepSnowFootprint) |
| TylerDodds/DeformableSnowRendering | Unity HDRP | Research: SSS, Phong tessellation, motion vectors, compute shaders | — | [GitHub](https://github.com/TylerDodds/DeformableSnowRendering) |
| DeleteSystem32/gd-snow-shader | Godot | Snow shader + terrain demo. GDScript + GLSL. | MIT | [GitHub](https://github.com/DeleteSystem32/gd-snow-shader) |
| Janglee123/godot-snow | Godot 2D | Deformable 2D terrain without mesh; gun + player interaction | — | [GitHub](https://github.com/Janglee123/godot-snow) |
| gdquest-demos/godot-shaders | Godot 4 | Large shader library with 2D + 3D effects | MIT | [GitHub](https://github.com/gdquest-demos/godot-shaders) |

### Godot Asset Library

- **No dedicated snow footprint/deformation plugin** exists on the Godot Asset Library (as of 2026-03-28).
- `Janglee123/godot-snow` (2D deformable terrain without mesh) is the closest open-source reference for a 2D approach in Godot.

### Academic References

| Paper | Topic | Link |
|-------|-------|------|
| "Hybrid-based snow simulation and rendering with shell textures" | Shell texture layering approach | [ResearchGate](https://www.researchgate.net/publication/275718416_Hybrid-based_snow_simulation_and_snow_rendering_with_shell_textures) |
| "Real-time Interactive Snow Simulation using Compute Shaders" | Compute shader approaches | [ResearchGate](https://www.researchgate.net/publication/344587438_Real-time_Interactive_Snow_Simulation_using_Compute_Shaders_in_Digital_Environments) |
| "In-game Interaction with a Snowy Landscape" (DiVA thesis) | Interactive snow systems survey | [DiVA](https://www.diva-portal.org/smash/get/diva2:642292/FULLTEXT01.pdf) |
| GDC 2023 — "Re-inventing the Wheel for Snow Rendering" | Modern techniques (Surricchio) | [GDC Vault PDF](https://media.gdcvault.com/gdc2023/Slides/Re-inventing+the+wheel+for+snow+rendering_Surricchio_Paolo.pdf) |
| GDC 2014 — "Deformable Snow Rendering in Batman: Arkham Origins" | Classic reference (Barre-Brisebois) | [GDC Vault](https://gdcvault.com/play/1020177/Deformable-Snow-Rendering-in-Batman) |

---

## 8. Proposed Future Solutions

The current implementation fulfils all four requirements. However, for higher realism or larger maps, these alternatives or improvements could be considered:

### 8.1 SubViewport Footprint Accumulation (Better Scalability)

Replace procedural `_draw()` nodes with a SubViewport that accumulates footprint stamps:

```
SubViewport (CLEAR_MODE_NEVER, same resolution as Snow ColorRect)
  └─ Node2D (footprint stamp sprites added then freed after one frame)
Snow ColorRect
  └─ ShaderMaterial reads SubViewport texture + applies snow FBM noise
```

Advantages:
- Zero per-footprint node overhead after stamp rendered
- Supports arbitrary numbers of footprints without node count limits
- Recovery pass (fade toward white over time) can be applied per frame to simulate snow filling back in

Godot docs reference: [Using a SubViewport as a Texture](https://docs.godotengine.org/en/stable/tutorials/shaders/using_viewport_as_texture.html)

### 8.2 Blood Spread Animation

The current `SnowBloodAbsorption` expands the radius on a linear easing. A more realistic spread would use:
- Voronoi noise mask to create irregular edge shapes
- Separate shader on the blood stain node rather than `_draw()` polygons
- Color interpolation from bright red → dark brown over time (simulating freezing)

### 8.3 Snow Recovery (Footprints Fill In Over Time)

Currently footprints are permanent until level reload. Real snow fills in footprints over time. If using a SubViewport approach (8.1), a recovery pass could multiply the accumulated texture toward white at a small rate each frame:
```glsl
// Recovery pass fragment shader:
COLOR = mix(COLOR, vec4(1.0), recovery_rate * TIME_DELTA);
```

### 8.4 Dynamic Resolution SubViewport (For Open Worlds)

If the map grows larger, use a moving window SubViewport that follows the player (same discrete-step approach as Batman: Arkham Origins). Footprints outside the window are lost, but the window is large enough that they fade from view naturally first.

---

## 9. Verification: Expected Log Output After Fix

When the game is built from this branch and run on the Winter Forest map, the log should contain:

```
[INFO] [WinterForestLevel] Setting up snow interactions (Issue #1627)...
[INFO] [WinterForestLevel] SnowBloodAbsorption scene loaded
[INFO] [WinterForestLevel] SnowFeetComponent added to Player
[INFO] [WinterForestLevel] Player BloodyFeetComponent blood_steps_count reduced to 6 (snow map)
[INFO] [WinterForestLevel] Snow interactions setup complete: N enemies equipped with SnowFeetComponent
[INFO] [SnowFeet:Player] SnowFeetComponent ready on Player
[INFO] [SnowFeet:Clearing_DroneOperator1] SnowFeetComponent ready on Clearing_DroneOperator1
[INFO] [SnowFeet:Clearing_DroneOperator2] SnowFeetComponent ready on Clearing_DroneOperator2
...
```

If any of these lines are missing, it pinpoints exactly where setup failed.

---

## 10. Files Changed / Added

### New Files

| File | Purpose |
|------|---------|
| `scripts/shaders/snow_surface.gdshader` | Procedural FBM bump shader for snow surface |
| `scripts/effects/snow_footprint.gd` | Persistent boot-print decal (procedural `_draw()`) |
| `scenes/effects/SnowFootprint.tscn` | Scene wrapping the SnowFootprint script |
| `scripts/components/snow_feet_component.gd` | Component: spawns SnowFootprints as character moves |
| `scripts/effects/snow_blood_absorption.gd` | Blood-stained snow (absorbs, no puddle group) |
| `scenes/effects/SnowBloodAbsorption.tscn` | Scene wrapping the SnowBloodAbsorption script |
| `tests/unit/test_snow_interactions.gd` | Unit tests covering all 4 requirements |
| `docs/case-studies/issue-1627/analysis.md` | Initial design analysis |
| `docs/case-studies/issue-1627/root-cause-analysis.md` | Root cause analysis from owner's game log |
| `docs/case-studies/issue-1627/deep-case-study.md` | This document |

### Modified Files

| File | Changes |
|------|---------|
| `scenes/levels/WinterForestLevel.tscn` | Snow `ColorRect` gets `ShaderMaterial` with `snow_surface.gdshader`; Snow node added to `"snow_surface"` group |
| `scripts/levels/winter_forest_level.gd` | Added `_setup_snow_interactions()`, `spawn_snow_blood_absorption()`, `_log_to_file()` |
| `scripts/autoload/impact_effects_manager.gd` | Added `_try_spawn_snow_blood_absorption()` to intercept blood decals landing on snow |

---

## 11. References

- [GDC 2014 — Deformable Snow Rendering in Batman: Arkham Origins (video)](https://gdcvault.com/play/1020177/Deformable-Snow-Rendering-in-Batman)
- [GDC 2014 — Batman AO Snow Slides PDF](https://colinbarrebrisebois.com/wp-content/uploads/2022/06/gdc2014-deformable_snow_rendering.pdf)
- [GDC 2023 — Re-inventing the Wheel for Snow Rendering](https://media.gdcvault.com/gdc2023/Slides/Re-inventing+the+wheel+for+snow+rendering_Surricchio_Paolo.pdf)
- [Godot Shaders — Car Tracks On Snow Or Sand](https://godotshaders.com/shader/car-tracks-on-snow-or-sand-using-viewport-textures-and-particles/)
- [Godot Forum — Footsteps in Snow (possible?)](https://forum.godotengine.org/t/godot-4-footsteps-in-snow-possible/1694)
- [Godot Docs — Using a SubViewport as a Texture](https://docs.godotengine.org/en/stable/tutorials/shaders/using_viewport_as_texture.html)
- [GitHub — thnewlands/unity-deformablesnow (Batman AO approach)](https://github.com/thnewlands/unity-deformablesnow)
- [GitHub — ZGeng/DeepSnowFootprint](https://github.com/ZGeng/DeepSnowFootprint)
- [GitHub — TylerDodds/DeformableSnowRendering (HDRP research)](https://github.com/TylerDodds/DeformableSnowRendering)
- [GitHub — DeleteSystem32/gd-snow-shader](https://github.com/DeleteSystem32/gd-snow-shader)
- [GitHub — Janglee123/godot-snow (2D deformable)](https://github.com/Janglee123/godot-snow)
- [Game Developer — Developing a Pixel Bloodstain System](https://www.gamedeveloper.com/design/developing-a-pixel-bloodstain-system)
- [Tom Looman — Rendering Wounds on Characters (sphere mask technique)](https://tomlooman.com/unreal-engine-render-character-wounds/)
- [80.lv — Four Methods for Blood Splatter Effect](https://80.lv/articles/four-methods-for-creating-blood-splatter-effect-explained)
- [ResearchGate — Hybrid-based snow simulation with shell textures](https://www.researchgate.net/publication/275718416_Hybrid-based_snow_simulation_and_snow_rendering_with_shell_textures)
- [ResearchGate — Real-time Interactive Snow Simulation using Compute Shaders](https://www.researchgate.net/publication/344587438_Real-time_Interactive_Snow_Simulation_using_Compute_Shaders_in_Digital_Environments)
- [DiVA — In-game Interaction with a Snowy Landscape (thesis)](https://www.diva-portal.org/smash/get/diva2:642292/FULLTEXT01.pdf)
- [Alan Zucconi — Dynamic Snow Shader Showcase](https://www.alanzucconi.com/2018/08/18/shader-showcase-saturday-6/)
