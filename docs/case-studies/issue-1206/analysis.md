# Case Study: Issue #1206 — Add Warm Light Sources to Building Map Rooms

## Summary

**Issue:** Add warm light sources to the centers of large rooms in the BuildingLevel scene to improve visual aesthetics.

**Request (original Russian):** "добавь в середину больших комнат источники тёплого света (чтоб было красивее)" — "add warm light sources to the center of large rooms (to make it more beautiful)"

---

## Room Layout Analysis

The `BuildingLevel.tscn` is a 2400×2000 pixel building with the following rooms (derived from `RoomLabels` node bounds):

| Room Name        | Bounds (x1,y1)–(x2,y2)     | Center         | Size      |
|------------------|-----------------------------|----------------|-----------|
| OFFICE 1         | (80, 80) – (500, 688)       | (290, 384)     | 420×608   |
| OFFICE 2         | (524, 712) – (912, 1000)    | (718, 856)     | 388×288   |
| CONFERENCE ROOM  | (1388, 80) – (2448, 600)    | (1918, 340)    | 1060×520  |
| BREAK ROOM       | (1388, 800) – (2448, 1188)  | (1918, 994)    | 1060×388  |
| SERVER ROOM      | (1700, 1212) – (2448, 2048) | (2074, 1630)   | 748×836   |
| STORAGE          | (80, 1612) – (500, 2048)    | (290, 1830)    | 420×436   |
| MAIN HALL        | (912, 1400) – (1488, 2048)  | (1200, 1724)   | 576×648   |

**Large rooms** (area > 200,000 px²): Conference Room, Break Room, Server Room, Main Hall.
**Smaller rooms**: Office 1, Office 2, Storage.

---

## Existing Lighting Architecture

The level already uses Godot 4 2D lighting:
- `LightOccluder2D` on all walls and covers for realistic shadow casting
- `PointLight2D` via `_setup_window_lights()` — cool blue moonlight from exterior windows
- `DirectionalLight2D` via `_create_ambient_moonlight()` — scene-wide ambient moonlight glow
- `CanvasModulate` (added by `RealisticVisibilityComponent`) — darkens the scene for visibility

## Existing Pattern Reference

`_create_window_light()` / `_create_window_light_texture()` in `building_level.gd` demonstrate the established pattern:
- Create `GradientTexture2D` with radial fill, fading to zero at ~55% radius
- Set large `texture_scale` (6.0) so gradient dissipates before reaching the quad edge
- Enable `shadow_enabled = true` with `SHADOW_FILTER_PCF5` for soft wall shadows
- Low `energy` (0.12) to avoid washing out the dark atmosphere

---

## Solution Chosen

Added two new methods to `building_level.gd`:

### `_setup_room_warm_lights()`
- Called from `_ready()` after `_setup_window_lights()`
- Creates a `Node2D` container "RoomLights" under "Environment"
- Places one warm `PointLight2D` at the geometric center of each room
- Large rooms: energy=0.85–0.9, texture_scale=4.5–5.0
- Small rooms: energy=0.7, texture_scale=3.5

### `_create_room_warm_light(parent, pos, energy, scale, room_name)`
- Adds a small visual fixture `ColorRect` (pale amber, semi-transparent) at the lamp position
- Adds a `PointLight2D` with warm amber-orange color `Color(1.0, 0.75, 0.3, 1.0)`
- `shadow_enabled = true` with PCF5 filtering — furniture and walls cast natural shadows
- Uses `_create_warm_light_texture()` for the radial gradient

### `_create_warm_light_texture()`
- Gradient fades to absolute zero at 60% radius (40% black buffer zone)
- Same "early fadeout" design as the moonlight texture to prevent visible edges
- Produces soft, natural-looking overhead illumination

---

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Warm amber color `(1.0, 0.75, 0.3)` | Mimics incandescent/halogen ceiling lights — classic office/building feel |
| Shadows enabled | Desks, cabinets, and walls cast realistic shadows, depth and atmosphere |
| 60% fade-out (vs 55% for moonlight) | Warm lights are larger; extra buffer prevents edge artifacts at high energy |
| Separate container node "RoomLights" | Clean scene hierarchy, easy to find/toggle in editor |
| Small amber ColorRect fixture | Provides visual anchor for where the light "comes from" |
| Dynamic creation in script (not baked into .tscn) | Consistent with existing window lights pattern; keeps .tscn diff small |

---

## Alternative Approaches Considered

1. **Bake lights directly into BuildingLevel.tscn** — Would clutter the scene file with many new sub-resources; harder to maintain. Rejected in favor of the existing dynamic pattern.
2. **Sprite-based lamp fixtures** — Would require art assets that don't exist; overkill for procedural ColorRect-based level. Rejected.
3. **Tiled/per-cell lighting** — The level is not tile-based, so a simpler per-room approach is appropriate.

---

## Incident: Performance Drop (2026-03-20T20:43)

### Timeline

| Time | Event |
|------|-------|
| 2026-03-20T07:42 | User reports 4 bugs (pause menu, square fixture, sharp edge, square light) in first implementation |
| 2026-03-20T07:47 | Bugs fixed: ColorRect → Sprite2D, ImageTexture per-pixel disc, PCF5 shadows enabled |
| 2026-03-20T08:25 | User reports Server Room light stuck in wall |
| 2026-03-20T09:16 | Server Room light moved to x=2200 |
| 2026-03-20T20:29 | User reports Office 2 light needs to move up; requests light placement rules |
| 2026-03-20T20:30 | User reports pause menu buttons still not working |
| 2026-03-20T20:35 | Office 2 shifted to y=780; placement rules documented in code |
| 2026-03-20T20:43 | **User reports severe performance drop; requests maximally optimized variant** |

### Root Causes of Performance Drop

Three compounding problems were introduced when fixing the visual issues:

#### 1. Six shadow-casting PointLight2D with PCF5 (primary GPU bottleneck)

Each `PointLight2D` with `shadow_enabled = true` requires a dedicated shadow-map render pass per frame. With 6 room ceiling lights all using `SHADOW_FILTER_PCF5` (the most expensive filter — 5×5 kernel) this adds 6 full shadow-map passes every frame, on top of the existing window moonlight shadow passes.

**Impact**: PCF5 shadow filtering is O(n²) in the filter kernel. Each additional shadow-casting light is multiplicative GPU cost. The level also has up to 10 enemies with flashlights that already add dynamic light passes, making the total light count very high.

**Godot 4 reference**: See [Godot docs on 2D lights and shadows](https://docs.godotengine.org/en/stable/tutorials/2d/2d_lights_and_shadows.html) — "shadow rendering is expensive; minimize the number of lights with `shadow_enabled = true`".

#### 2. Per-pixel GDScript image generation (startup CPU cost)

`_create_warm_light_texture()` ran a 512×512 double loop (262,144 iterations) in GDScript to write pixels. `_create_lamp_fixture_texture()` ran a 32×32 loop. Both were called 6 times (once per room) — creating 6 identical textures on both CPU and GPU.

GDScript loops are ~100× slower than C++ for numeric work. A 512×512 pixel loop in GDScript takes tens to hundreds of milliseconds, causing a noticeable hitch at level load.

#### 3. No texture caching — 6 duplicate GPU uploads

Each of the 6 `_create_room_warm_light()` calls created fresh `ImageTexture` objects. Although the pixels were identical, Godot treated each as a separate GPU texture resource, uploading 6×512×512×4 bytes = ~6 MB of redundant texture data.

### Fixes Applied (Performance Optimization — commit after 2026-03-20T20:43)

| Problem | Fix | Savings |
|---------|-----|---------|
| 6 PCF5 shadow-map passes | `shadow_enabled = false` on all ceiling lights | 6 shadow render passes removed per frame |
| Per-pixel 512×512 GDScript loops | Replaced with `GradientTexture2D` (GPU-generated, no GDScript loops) | ~1.6M GDScript pixel ops → 0 |
| 6 duplicate texture uploads | Single cached instance via `_warm_light_texture_cache` / `_lamp_fixture_texture_cache` | 5/6 GPU uploads eliminated |
| 512×512 texture per light | Reduced to 256×256 (ample at texture_scale 3.5–5×) | Texture memory halved |

**Rationale for disabling ceiling-light shadows**: Room ceiling lights are decorative ambient fills. The moonlight window lights already provide directional shadow detail from walls, furniture, and enemies. Disabling shadows on ceiling lights preserves the visual atmosphere while eliminating the dominant GPU cost.

### Light Placement Rules (added to code documentation)

1. **Default**: geometric centre of the room bounding box.
2. **Obstacle at centre**: shift toward the nearest open floor area with the most free space.
3. **Wall junction nearby (< 30 px)**: move light inward so shadows don't block the cone.
4. **Crowded lower half**: prefer the upper half of the room so the glow is visible from the entry direction.

---

## Files Changed

- `scripts/levels/building_level.gd` — Added `_setup_room_warm_lights()`, `_create_room_warm_light()`, `_get_warm_light_texture()`, `_get_lamp_fixture_texture()` and a call in `_ready()`.
- `Scripts/Components/LevelInitFallback.cs` — Added `SetupRoomWarmLights()`, `CreateRoomWarmLight()`, `CreateWarmLightTexture()`, `CreateLampFixtureTexture()` to handle the fallback path (Session 3 fix).
- `docs/case-studies/issue-1206/game_log_20260320_103853.txt` — Game runtime log captured before warm lights were added (no warm-light entries; baseline reference).
- `docs/case-studies/issue-1206/logs/game_log_20260321_140325.txt` — Game log showing lights completely absent (GDScript fallback path active).
- `docs/case-studies/issue-1206/analysis.md` — This document.

---

## Incident: Lights Completely Disappear (2026-03-21T14:03)

### Timeline

| Time | Event |
|------|-------|
| 2026-03-20T07:42 | Session 1: Warm ceiling lights implemented in GDScript `building_level.gd` |
| 2026-03-20T20:43 | Session 1: Performance drop reported; shadows disabled, GradientTexture2D used |
| 2026-03-21T10:54 | Session 2: Office 2 light spread fixed (shadow_enabled=false), menu buttons fixed (merge main) |
| 2026-03-21T14:03 | **User reports lights have completely disappeared** |

### Root Cause: GDScript `_ready()` Silently Fails in Exported Build

The game log at `14:03:30` contains this critical entry:

```
[LevelInitFallback] GDScript _ready() did NOT execute - performing C# fallback initialization
```

This is caused by the **Godot 4.3 binary tokenization bug** ([godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150), [#96065](https://github.com/godotengine/godot/issues/96065)):

- When Godot exports a project, GDScript files are compiled to binary tokens by default (`script_export_mode=2`).
- In Godot 4.3, the binary tokenizer can silently corrupt certain GDScript constructs, causing `_ready()` to fail without any error message.
- The game has a C# fallback (`LevelInitFallback.cs`) that detects when GDScript `_ready()` didn't run and re-performs critical gameplay initialization (enemy tracking, score, replay, etc.).
- **However, `LevelInitFallback.cs` did not include the warm ceiling lights setup** — only the gameplay-critical code was replicated.

### Evidence from Game Log

The expected log entry `[BuildingLevel] Warm ceiling lights placed in all rooms (Issue #1206)` is **completely absent** from the Session 3 log. All other initialization (enemy tracking, score, replay) was handled by `LevelInitFallback`.

The `ExperimentalSettings` log shows `Realistic visibility: false` — this means `CanvasModulate` darkening was NOT applied in this session, so even the existing window moonlight effects may have been less visible.

### Fix Applied (Session 3 — 2026-03-21)

Added `SetupRoomWarmLights()` and helper methods to `LevelInitFallback.cs`, mirroring the GDScript implementation exactly:

| Method | GDScript equivalent |
|--------|---------------------|
| `SetupRoomWarmLights()` | `_setup_room_warm_lights()` |
| `CreateRoomWarmLight()` | `_create_room_warm_light()` |
| `CreateWarmLightTexture()` | `_create_warm_light_texture()` |
| `CreateLampFixtureTexture()` | `_create_lamp_fixture_texture()` |

The same room positions, energy values, scales, and shadow settings are used. Textures are generated once and reused for all 6 rooms (same caching strategy as the GDScript version).

**Guard clause added**: If `Environment/RoomLights` already exists (meaning GDScript ran normally), the fallback skips light creation to prevent duplicates.

### Why the User Still Hit the Bug Despite `script_export_mode=0`

The current `export_presets.cfg` already has `script_export_mode=0` (Text) — the primary workaround for the binary tokenization bug, applied during issue #416. However, the user's log path was:

```
I:/Загрузки/godot exe/источники света/Godot-Top-Down-Template.exe
```

"Загрузки" is Russian for "Downloads". The user was running a **previously downloaded executable** built before `script_export_mode=0` was set. Future builds from this branch will export GDScript as text, so the GDScript `_ready()` path will run correctly — but the `LevelInitFallback` fallback remains important for:
1. Users who still have older exports
2. Any future scenario where GDScript loading unexpectedly fails

### Godot Binary Tokenization Bug — Research Findings

**Introduced in**: Godot 4.3 via [PR #87634](https://github.com/godotengine/godot/pull/87634) — reintroduced binary tokenization of GDScript on export (existed in Godot 3.x, was absent from 4.x until 4.3).

**Mechanism**: GDScript files are compiled to binary token format during export. The binary tokenizer silently corrupts certain constructs; the script "loads" successfully (a valid `GDScript` object is returned) but `.new()` fails silently — no error, no `null`, just a script that never instantiates. `_ready()` therefore never runs.

**Detection**: The only reliable programmatic detection is calling `.reload()` on the loaded script — a non-zero return means errors exist.

**Known triggers** ([#94150](https://github.com/godotengine/godot/issues/94150), [#96065](https://github.com/godotengine/godot/issues/96065), [#89403](https://github.com/godotengine/godot/issues/89403)):
- Scripts using `class_name` globals referenced across addon boundaries
- `preload`/`load()` chains involving globally registered script classes
- Certain coroutine/`await` patterns in complex level scripts

**Primary workaround**: Set `script_export_mode=0` (Text) in export settings — already applied in this project.

**References**:
- [godotengine/godot#94150](https://github.com/godotengine/godot/issues/94150) — Binary tokens break exported builds with some addons
- [godotengine/godot#96065](https://github.com/godotengine/godot/issues/96065) — `load()` returns GDScript despite parse error; `.new()` fails silently
- [godotengine/godot#113577](https://github.com/godotengine/godot/issues/113577) — Errors when exporting with binary tokens (still open)
- [godotengine/godot#87634](https://github.com/godotengine/godot/pull/87634) — PR that introduced the regression

### Why the Fallback Pattern Exists

The `LevelInitFallback.cs` component was introduced as a mitigation for the Godot 4.3 binary tokenization bug that caused GDScript autoloads and level scripts to silently fail. See:
- `docs/case-studies/issue-416/README.md` — Full investigation of the binary tokenization bug
- `docs/case-studies/issue-486/README.md` — ReplayManager C# rewrite (same root cause)
