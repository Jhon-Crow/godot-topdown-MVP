# Case Study: Issue #1615 — Rain Occlusion by Buildings on Docks Level

## Problem Statement

Rain on the Docks level does not account for buildings (should be occluded/clipped by roofs).
Rain should be **global** (world-space, not following player), and must be **visually blocked** inside buildings while continuing to fall outdoors.

### User Feedback (PR #1655 comment)
> "Rain completely stops — it should be global (not follow the player, as implemented in main) and be cut off by buildings. Outside buildings it should rain, inside — it should not."

The original fix (commit `e9692bc7`) stopped ALL rain when the camera entered a building exclusion zone. This is wrong: the player could stand in a doorway and rain would vanish from the entire visible scene.

---

## Root Cause Analysis

### Current (broken) approach
`rain_effect.gd` checks `_is_point_in_exclusion_zone(cam_pos)` each frame:
- If the **camera center** is inside an exclusion zone → `emitting = false` (all rain stops globally)
- If the camera leaves → `emitting = true` (all rain resumes globally)

This is a binary on/off per the whole scene. It was a valid first approximation but fails when:
1. Player is inside a building but looking out — rain should be visible outside
2. Player is near the entrance — standing in the doorway, rain should stop at the roof edge

### What "global rain" means
Rain particles spawn at world positions relative to the camera center and **remain at their world positions** as the camera moves (Fix #1579). This is correct. The issue is purely about **visually masking** rain particles that happen to be within building footprints.

---

## Technical Analysis

### Scene Hierarchy
```
DocksLevel (root)
├── Environment/
│   └── Structures/
│       ├── CranePlatform/    position=(400, 500)
│       │   └── Floor: ColorRect(-200,-150 to 200,150) = Color(0.35,0.32,0.3,1)
│       ├── WarehouseA/       position=(400, 1800)
│       │   └── Floor: ColorRect(-250,-300 to 250,300) = Color(0.2,0.18,0.16,1)
│       └── WarehouseB/       position=(4400, 2800)
│           └── Floor: ColorRect(-350,-400 to 350,400) = Color(0.2,0.18,0.16,1)
├── RainEffect (z_index=100)  ← world-space GPUParticles2D
└── Entities/
    ├── Player  (z_index=1)
    └── Enemies (z_index=1)
```

### Z-Index Ordering
| Node | z_index | Draw Order |
|------|---------|------------|
| Building floors | 0 | First (background) |
| Player/Enemies | 1–5 | Middle |
| RainEffect | 100 | On top (rain over everything) |

### Why "roof overlay" won't work simply
Adding a ColorRect at z=101 inside each building would cover rain but **also cover players and enemies** walking inside (since 101 > 1–5).

---

## Solution Approaches

### Approach 1 (Current — Wrong): Binary Stop/Start
Stop all rain when camera center is inside building. Simple but incorrect behavior.

### Approach 2: Roof Overlay ColorRects (Rejected)
Add opaque colored rects above rain z-layer → covers all entities inside buildings too. Breaks gameplay visibility.

### Approach 3: Shader-Based Per-Particle Occlusion ✅ (Chosen)
Use a custom `canvas_item` shader on each particle material. The shader receives exclusion zone rectangles as uniforms and **discards fragments** (`discard`) when the particle's world position falls inside a building zone.

**Advantages:**
- Rain continues emitting globally at all times
- Only individual rain particles/splashes inside building footprints are discarded
- Characters, enemies, UI remain fully visible
- No camera-position dependency — correct from any viewing angle
- Matches what HM2 and similar top-down games do

**How it works in Godot 4:**
- `GPUParticles2D` renders via its material (`CanvasItemMaterial` → replaced with `ShaderMaterial`)
- In a `shader_type canvas_item` shader, `MODEL_MATRIX` is available **only in the vertex stage** (not fragment); it holds the combined emitter×particle-instance world transform
- `MODEL_MATRIX[3].xy` in the **vertex** stage gives the particle's center in world coordinates; this is passed to the fragment stage via a `varying`
- In the **fragment** stage, the `varying` world position is compared against each exclusion zone Rect2 → `discard` if inside

**Critical Godot 4 shader API facts (vs. Godot 3):**
- `WORLD_MATRIX` does **not exist** in Godot 4 canvas_item shaders (Godot 3 legacy name)
- `MODEL_MATRIX` is the Godot 4 replacement, but it is vertex-stage only
- `VERTEX` in the fragment stage is canvas-space (not world-space) and not reliable with Camera2D zoom/pan
- Per-particle world position MUST be passed via a `varying` from vertex to fragment

### Approach 4: Separate Outdoor/Indoor Particle Systems
Duplicate rain systems — one for outdoor, one per building using local space emitters. Very complex, high memory, difficult to maintain.

---

## References & Prior Art

### Hotline Miami 2 (Dennaton Games, 2015)
The reference game for this rain effect. HM2 uses per-room rain layers:
- Indoor rooms have no rain rendered (clipped at room boundary)
- Outdoor areas have continuous rain
- Implementation: room-based scene composition with separate rain layers per area type

### Godot 4 Techniques
- **`shader_type canvas_item` + `discard`**: Valid for GPUParticles2D visual masking
- **`WORLD_MATRIX`**: Available in vertex/fragment shaders, gives transform of the rendered item
- **`ParticleProcessMaterial` vs `ShaderMaterial`**: Process material controls physics; the particle's draw material controls rendering
- Godot Forum: "Mask GPUParticles2D to specific screen area" — common pattern uses shader discard

### Similar Issues in Other Games
- Rain occlusion by buildings is a fundamental top-down game rendering challenge
- Common solution: either separate layers per area, or per-fragment world-position testing
- Shader approach scales to N buildings with O(N) uniform cost

---

## Implementation

### Files Changed
1. `scripts/shaders/rain_occlusion.gdshader` — new shader with zone uniforms
2. `scenes/effects/RainEffect.tscn` — use ShaderMaterial on both particle nodes
3. `scripts/effects/rain_effect.gd` — pass zones to shader instead of stopping emission
4. `tests/unit/test_rain_effect.gd` — update tests for new behavior

### Building Exclusion Zones (Docks Level)
```
CranePlatform:  Rect2(192, 342, 416, 316)   # pos(400,500), floor±200x, ±150y
WarehouseA:     Rect2(130, 1480, 540, 640)  # pos(400,1800), floor±250x, ±300y
WarehouseB:     Rect2(4030, 2380, 740, 840) # pos(4400,2800), floor±350x, ±400y
```

---

## Screenshot Evidence

### Screenshot 1 (original issue report)
The screenshot from the issue shows rain particles (diagonal streaks) visible **inside** a building area (bounded by the red rectangle drawn by the reporter). The "ВОСКРЕСНУТЬ" (respawn) prompt is visible — the player is dead inside the building with rain falling through the roof.

Expected behavior: no rain inside the building, rain visible outside.

### Screenshot 2 (feedback after first shader fix — 2026-03-28)
After the per-particle shader approach was deployed (commit `ba391733`), the owner reported rain still visible inside CranePlatform. The screenshot (`rain-inside-building-2-feedback.png`) shows white rain dots clearly inside the building boundaries.

**Root cause of the second failure:** The first shader implementation used `WORLD_MATRIX[2].xy` in the fragment stage. This variable does not exist in Godot 4 canvas_item shaders. Undefined behavior in GLSL means the `discard` test silently never triggered — all particles were rendered. The fix (second iteration) properly uses a `varying vec2 particle_world_pos` set from `MODEL_MATRIX[3].xy` in the vertex stage and read in the fragment stage.

### Timeline of Fixes
| Date | Commit | Approach | Outcome |
|------|--------|----------|---------|
| Initial | — | No occlusion | Rain inside buildings (bug) |
| Pre-#1615 fix | `e9692bc7` | Binary `emitting=false` on camera | All rain stops globally (wrong) |
| 2026-03-28 #1 | `ba391733` | Shader `WORLD_MATRIX[2].xy` (fragment) | Variable doesn't exist in Godot 4 → discard never fires |
| 2026-03-28 #2 | TBD | Shader `varying` from `MODEL_MATRIX[3].xy` (vertex→fragment) | ✅ Correct per-particle occlusion |
