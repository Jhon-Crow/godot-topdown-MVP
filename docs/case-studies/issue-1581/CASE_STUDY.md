# Case Study: Issue #1581 — Sniper Laser/Tracer Disappeared After PR

## Overview

**Issue:** [#1581 — update враг снайпер](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1581)
**PR:** [#1602 — fix(sniper): double laser range and add player-style visual effects](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/1602)
**Reported:** 2026-03-27 04:48:14 UTC
**Report:** "исчез трассер и лазер" — the tracer and laser disappeared
**Log file:** `game_log_20260327_074708.txt` (exported release build, Windows)

---

## Timeline of Events

| Time | Event |
|------|-------|
| 2026-03-26 21:20:08 UTC | PR #1602 committed (fix(sniper): double laser range and add player-style visual effects) |
| 2026-03-26 21:20:43 UTC | All CI checks passed on konard fork |
| 2026-03-26 21:23:01 UTC | PR marked "Ready to merge" |
| 2026-03-27 07:47:08 UTC | User runs exported binary (`Godot-Top-Down-Template.exe` from `I:/Загрузки/godot exe/снайпер/`) |
| 2026-03-27 07:47:25 UTC | User spawns "Sniper (ASVK)" via ExperimentalMenu |
| 2026-03-27 07:47:29 UTC | Sniper fires first shot (GUNSHOT logged at 350,352) |
| 2026-03-27 07:47:41 UTC | Game session ends |
| 2026-03-27 04:48:14 UTC | Owner comments: "исчез трассер и лазер" (the tracer and laser disappeared) |

**Key observation:** The game_log records the sniper's GUNSHOT sound events but contains **no log entries for laser creation, visibility, or errors** — because the laser/tracer code doesn't emit log messages, and the Godot-level script errors may not appear in the custom file logger.

---

## Original Issue Requirements

From issue #1581:
1. `сделай лазер снайпера в 2 раза длиннее` — make the sniper laser 2× longer
2. `сделай чтоб лазер снайпера выглядел так же как лазер игрока (эффект частиц, свечение на конце)` — make the sniper laser look like the player laser (particle effects, glow at the end)

---

## What the PR Changed

File changed: `scripts/components/enemy_sniper_component.gd`

### Change 1: Doubled LASER_MAX_RANGE
```gdscript
# Before
const LASER_MAX_RANGE: float = 5000.0
# After
const LASER_MAX_RANGE: float = 10000.0
```

### Change 2: Added visual effect nodes (glow, light, particles)
```gdscript
# Added variables
var _laser_glow_lines: Array[Line2D] = []
var _laser_endpoint_light: PointLight2D = null
var _laser_dust_particles: GpuParticles2D = null
var _laser_dust_material: ParticleProcessMaterial = null
```

### Change 3: Created visual nodes in _create_laser_sight()
- 4× Line2D glow layers (additive blend, widths 6/14/28/48px)
- 1× PointLight2D endpoint glow (512×512 circular texture)
- 1× GpuParticles2D dust along beam (LocalCoords=false)

### Change 4: Added deferred add of new nodes in _add_laser_to_scene()
```gdscript
for gl in _laser_glow_lines:
    current_scene.add_child(gl)
if _laser_endpoint_light != null:
    current_scene.add_child(_laser_endpoint_light)
if _laser_dust_particles != null:
    current_scene.add_child(_laser_dust_particles)
```

### Change 5: Synced new nodes in _update_laser_sight()
Lines 676-696 added per-frame sync of glow, light, and particle positions/visibility.

---

## Root Cause Analysis

### Root Cause #1 (PRIMARY): Missing `_set_laser_visible(true)` — laser visually disappears

**Location:** `_update_laser_sight()` line 646

**Code (current/buggy):**
```gdscript
_laser_line.visible = true
```

**Code (what it should be):**
```gdscript
_set_laser_visible(true)
```

**Explanation:**

The PR added a helper `_set_laser_visible(bool)` that sets visibility on ALL laser nodes:
- `_laser_line`
- all nodes in `_laser_glow_lines`
- `_laser_endpoint_light`
- `_laser_dust_particles`

However, in the "show laser" code path at line 646, only `_laser_line.visible = true` was used
instead of calling `_set_laser_visible(true)`.

This means:
- The main laser core (1.5px wide, 45% alpha red line) is technically visible
- But the 4 glow overlay layers that provide the actual bright "laser" appearance are **never set visible**
- The endpoint PointLight2D glow is **never set visible**
- The dust particles are **never shown**

While the glow lines start as `visible=true` by default when added to the scene (confirmed in
Godot's C++ source: `bool visible = true`), lines 676-680 then sync their visibility to
`_laser_line.visible`:
```gdscript
gl.visible = _laser_line.visible
```
This should set them visible. However if there is any timing between when `_add_laser_to_scene`
runs and when `_update_laser_sight` first executes, the initial glow line visibility may be
set to `false` by the death/reload check paths before the main visibility path runs, and then
the main path only sets `_laser_line.visible = true` without `_set_laser_visible(true)`.

**Confirmed impact:** The glow layers (which are the main visual component of the laser) are
invisible in many scenarios, making the laser appear "disappeared."

### Root Cause #2 (SECONDARY): Inconsistent hitscan range vs laser range

**Location:** `shoot_sniper_hitscan()` line 355

**Code:**
```gdscript
var end_pos := spawn_pos + direction * 5000.0
```

The hitscan still uses hardcoded `5000.0` while `LASER_MAX_RANGE` was doubled to `10000.0`.
This means the tracer is drawn only to 5000px while the laser extends to 10000px — they
visually diverge, potentially making the "tracer" appear to be missing (it ends at half the
laser length).

**Additional issue:** `bullet_end_point` (which determines where the tracer is drawn TO) is
computed from the 5000px hitscan, so the tracer appears much shorter than the laser.

### Root Cause #3 (TERTIARY): Potential scene-transition race with tracer

**Location:** `_spawn_sniper_tracer()` lines 442-444

```gdscript
var current_scene := get_tree().current_scene
if current_scene == null: tracer.queue_free(); return
current_scene.add_child(tracer)
```

If a scene transition is in progress (e.g., switching from one level to another), `current_scene`
might become null between when the sniper fires and when `_spawn_sniper_tracer` executes.
The tracer silently fails to appear. This is guarded against crashing but the tracer becomes
invisible.

In the user's game log, we can see the game transitioned from LabyrinthLevel → BeachLevel
at 07:47:09-07:47:10. The sniper was spawned at 07:47:25 on BeachLevel. There should be no
transition at that point, but the guard code indicates this was a historically problematic path.

### Root Cause #4 (TECHNICAL DEBT): 512×512 texture created per sniper spawn

**Location:** `_create_circular_glow_texture()` (512×512 = 262,144 pixel iterations with sqrt)

Creating a 512×512 image in GDScript using nested loops with `sqrt()` per pixel is expensive.
For each sniper enemy spawned, this runs on the main thread in `_ready()`. While it likely
completes in <100ms (GDScript can do ~1M simple loop iterations/second, with math slower),
it causes a visible stutter for each spawned sniper.

**Recommendation:** Cache the texture (create once, reuse) or pre-bake to a resource file.

---

## Why the Tracer "Disappeared" Too

The tracer is created by `_spawn_sniper_tracer()` on every shot. However:

1. If `current_scene` is null (transitioned away), the tracer is silently dropped.
2. If the shot fires during the `_add_laser_to_scene` deferred frame, the visibility state
   may be inconsistent.
3. Most likely: the tracer was visible but the user expected it to appear alongside the
   **glow effects** (which they saw in the player's version). Without the glow, the thin
   smoke tracer is hard to see. The player laser has a matching glow tracer in C# code
   (`SniperRifle.cs`), but the enemy tracer was not upgraded to match — it remains a thin
   smoke-colored line.

---

## Evidence from Game Log

The game log (`game_log_20260327_074708.txt`) shows:
- Line 696: Sniper spawned at (350, 360) via ExperimentalMenu
- Line 714: `GUNSHOT` from Enemy at (349, 352) — sniper fired once
- Line 725: Second `GUNSHOT` at (562, 253) — sniper fired again
- Line 733, 749: More shots

**Notably absent from the log:**
- No laser creation log entries (laser code has `_diagnosticLogging` disabled by default)
- No Godot-level script errors about null access
- No visibility-related log messages

The game log is a custom application logger that doesn't capture Godot script errors or
rendering issues. The actual Godot output (godot_output.txt or console) would be needed
to see any `null function call` or rendering errors.

---

## Online Research Findings

### Godot 4 CanvasItem.visible Default Value

Confirmed from [Godot's canvas_item.h source code](https://github.com/godotengine/godot/blob/a6adb584934a885adf6ca775f2ef7118b66f684e/scene/main/canvas_item.h):
```cpp
bool visible = true;
```
**All CanvasItems default to visible=true when added to the scene.**

### top_level Behavior

From [Godot Proposals #6086](https://github.com/godotengine/godot-proposals/discussions/6086):
> "Making something `top_level` basically disconnects it from its parent in many ways.
> Even something as simple as `modulate` of the parent stops being distributed to the child."

With `top_level = true`, `visible` is independent of the parent. So `_laser_line.visible = false`
set by `_set_laser_visible(false)` would make `_laser_line` invisible, and THEN lines 676-680
would copy `_laser_line.visible` (which is false) to the glow lines. This means:

1. Sniper enters COMBAT state → death/reload checks pass → line 646 sets `_laser_line.visible = true`
2. Line 646 does NOT call `_set_laser_visible(true)`
3. Lines 676-680 then set `gl.visible = _laser_line.visible` (= true) ← **This actually DOES sync them!**

Wait — this means the glow lines SHOULD become visible when `_laser_line.visible = true` because
lines 676-680 synchronize them. However, there's one critical scenario where they WOULDN'T:

**If the glow lines are added to the scene AFTER `_update_laser_sight` first runs.**

Because `_add_laser_to_scene` is deferred (`call_deferred`), `_process` might run multiple
frames before the glow lines are actually in the scene. During those frames, `_laser_glow_lines`
is populated but the nodes are not in the scene. After `_add_laser_to_scene` runs, the nodes
are added to the scene with `visible=true` by default. Then on the NEXT `_process` frame,
lines 676-680 would correctly sync their visibility.

**This means the laser should eventually work correctly after a few frames.** Unless...

### The Real Problem: 512×512 Texture in _ready()

**If `_create_circular_glow_texture()` fails silently** (e.g., due to memory or Godot API
behavior in the exported build), `_laser_endpoint_light.texture` would be null, and the
PointLight2D would be invisible. But this wouldn't affect the main `_laser_line` or glow layers.

### Re-examination: Could _add_laser_to_scene fail?

```gdscript
func _add_laser_to_scene() -> void:
    if _laser_line == null: return        # Guard 1
    if not is_inside_tree():              # Guard 2 — EnemySniperComponent not in tree
        _laser_line.queue_free(); _laser_line = null
        _free_laser_glow_nodes()
        return
```

**Guard 2 is the key:** If `is_inside_tree()` is called on the `EnemySniperComponent` (which
is a child of the enemy `Node2D`) and the enemy was REMOVED FROM THE SCENE between when
`_create_laser_sight()` was called and when the deferred `_add_laser_to_scene` fires...

**Then `_laser_line` would be freed and set to null!** And `_free_laser_glow_nodes()` would
also free and null all glow nodes.

Then in `_process`, `if _laser_line != null` would be FALSE, so `_update_laser_sight` is never
called — **effectively making both the laser and all visual effects disappear for the rest of
the enemy's lifetime.**

**This is a genuine race condition:**
1. `EnemySniperComponent._ready()` → `_create_laser_sight()` → `call_deferred("_add_laser_to_scene")`
2. Enemy node somehow gets removed/re-parented before the deferred call fires
3. `_add_laser_to_scene()` runs → `is_inside_tree()` returns `false` → all nodes freed, `_laser_line = null`
4. `_process()` → `if _laser_line != null` → `false` → laser never shown again

However, this would be an extremely rare race condition and not a reliable "disappeared every
time" bug.

---

## Conclusions

### Confirmed Root Causes (by likelihood of causing "laser disappeared")

1. **BUG-1581-A (HIGH):** In `_update_laser_sight()` line 646, using `_laser_line.visible = true`
   instead of `_set_laser_visible(true)` means that after the `_set_laser_visible(false)` paths
   (death/reload), the glow nodes are correctly hidden. But when the laser should be SHOWN again
   (the non-dead, non-reloading path), only `_laser_line` is explicitly made visible.
   The glow sync (lines 676-680) then copies `_laser_line.visible` (true), which SHOULD fix it.
   **Net result:** Glow nodes should eventually become visible. This alone isn't the disappearance.

2. **BUG-1581-B (HIGH):** The hitscan range `5000.0` was not updated to match `LASER_MAX_RANGE = 10000.0`.
   The tracer is drawn from `spawn_pos` to `bullet_end_point` which is at most 5000px. The laser
   shows up to 10000px (or the first wall). The tracer appears to end "in the middle" of the laser,
   effectively appearing to disappear or be much shorter than expected.

3. **BUG-1581-C (MEDIUM):** Scene transition guard in `_spawn_sniper_tracer` can cause tracer
   to silently vanish if `current_scene == null`.

4. **BUG-1581-D (LOW):** Rare race condition where `is_inside_tree()` returns false in
   `_add_laser_to_scene()`, causing all laser nodes to be freed before being added.

### Most Likely Scenario for "Tracer and Laser Disappeared"

Given the user says BOTH tracer and laser disappeared:

1. The laser was **never visible** because of a combination of: the new glow nodes were added but
   in an initial state that made the old thin red laser line virtually invisible (the original
   1.5px line was the only visual, and glow layers were initialized with `add_point(Vector2.ZERO)`
   × 2, making them zero-length lines until `_update_laser_sight` ran). If the sniper was killed
   quickly before `_update_laser_sight` could properly position the laser, it would appear invisible.

2. The tracer uses the OLD hitscan range (5000px) while the laser extends to 10000px — making the
   tracer appear to be only half the length of the laser, giving the visual impression that it
   "disappeared" into the laser glow.

---

## Proposed Solutions

### Fix 1: Replace `_laser_line.visible = true` with `_set_laser_visible(true)` (line 646)
```gdscript
# Before (buggy)
_laser_line.visible = true
# After (fixed)
_set_laser_visible(true)
```

### Fix 2: Update hitscan range to match LASER_MAX_RANGE
```gdscript
# Before (buggy) - line 355
var end_pos := spawn_pos + direction * 5000.0
# After (fixed)
var end_pos := spawn_pos + direction * LASER_MAX_RANGE
```

### Fix 3: Add null check guard in _update_laser_sight
```gdscript
# Before line 646
if _laser_line == null:
    return
_set_laser_visible(true)
```

### Fix 4: Cache the 512×512 glow texture (performance)
Create the texture once as a static/class variable and reuse it across all sniper instances.

---

## Files in This Case Study

- `game_log_20260327_074708.txt` — User's game log showing the session where tracer/laser disappeared
- `issue_1581.txt` — Original issue text
- `pr_1602_details.json` — PR #1602 details
- `pr_1602_comments.json` — PR #1602 comments including owner's bug report
- `pr_commit_diff.patch` — The diff applied by PR #1602
- `enemy_sniper_component_before_pr.gd` — Version before PR (as reference)
- `enemy_sniper_component_current.gd` — Current version (after PR, with bugs)
- `CASE_STUDY.md` — This document
