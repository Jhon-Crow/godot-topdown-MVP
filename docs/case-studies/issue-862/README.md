# Issue #862 — Fix Performance (Bullet Hell)

## Summary

Performance degrades noticeably during active firefights (bullet hell — many
projectiles simultaneously).  The issue explicitly references PR #845, which
analysed FPS drops for issue #844 and identified seven bottlenecks.  Several
of those bottlenecks were **never fixed** and remain in the codebase.  The
single most serious problem for bullet-hell scenarios is the combination of:

1. **Node churn** — every bullet is instantiated and freed on hit/expiry.
2. **Unbounded node accumulation** — blood decals and bullet holes grow without
   limit, so the scene tree keeps expanding over a session.
3. **Per-shot I/O** — `DebugPenetration = true` triggers synchronous file
   writes on every wall collision.

This document records the research, root-cause analysis, and proposed
solutions that were implemented in PR #863.

---

## Codebase Context

| Component | Path | Language |
|-----------|------|----------|
| GDScript bullet projectile | `scripts/projectiles/bullet.gd` | GDScript |
| C# bullet projectile | `Scripts/Projectiles/Bullet.cs` | C# |
| Impact / decal spawner | `scripts/autoload/impact_effects_manager.gd` | GDScript |
| Player shooting | `scripts/characters/player.gd` | GDScript |
| Enemy shooting | `scripts/objects/enemy.gd` | GDScript |
| Bullet pool (new) | `scripts/autoload/bullet_pool.gd` | GDScript |

The game targets Godot 4.3+ with both GDScript and C# (`.NET`) nodes.

---

## Online Research: Godot 4 Bullet-Hell Optimisation

### Object Pooling

**Why it matters:**
Godot's `PackedScene.instantiate()` registers every new node with the physics
server, inserts it into the scene tree, and runs `_ready()`. `queue_free()` does
the reverse asynchronously. In a bullet-hell with 20 enemies firing at 10 Hz
each, that is **200 alloc+free cycles per second**. Each cycle has both CPU
and GC overhead.

**Recommended approach (Godot community consensus, 2024–2026):**
Pre-allocate a pool of nodes, disable them (set `process = false`, `visible = false`,
`monitoring = false`), and re-enable them on demand. The pool size for this
game: 20 enemies × 10 rps × ~1 s average bullet lifetime = **200 concurrent
bullets**. A pool of 200 was chosen.

References:
- <https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/>
- <https://github.com/godot-addons/godot-object-pool>
- Godot 4 Recipes — "Shooting projectiles": <https://kidscancode.org/godot_recipes/4.x/2d/2d_shooting/>

### Node Count Matters

Each `Sprite2D`, `Area2D`, and `CollisionShape2D` node in the scene tree
contributes to the **scene-tree traversal cost** on every frame. Godot 4's
renderer and physics server iterate all active nodes each frame. Unlimited
blood decals (3,640+ per session in profiling from issue #844) and bullet holes
add up to measurable frame-time even when they are off-screen.

**Fix:** cap both with a FIFO (ring-buffer) cleanup, which was already
implemented in `impact_effects_manager.gd` but disabled by `MAX_BLOOD_DECALS = 0`.

Reference:
- Godot 4 official docs — "Optimization using Servers": <https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html>
- Godot 4 performance guide: <https://docs.godotengine.org/en/stable/tutorials/performance/general_tips.html>

### Physics Server Overhead

Each `Area2D` with `monitoring = true` adds a physics body to Godot's
`PhysicsServer2D`. The more active `Area2D` nodes, the more overlap tests the
server must perform per frame. Disabling `monitoring` and `monitorable` on
pooled/idle bullets avoids unnecessary collision queries.

### Debug Logging in Hot Paths

`print()` + file I/O are among the **most expensive** single operations in
GDScript. The `LogPenetration` method in `Bullet.cs` (and its equivalent in
`bullet.gd`) was called on **every** wall collision event: entry, exit, raycast
checks, and distance updates — i.e., multiple times per bullet per physics frame
while inside a wall. During a bullet-hell with 50+ active bullets, this can mean
100+ synchronous file writes per frame.

---

## Root-Cause Analysis

### Bottleneck 1 (CRITICAL) — Node churn from bullet instantiate/free

**File:** `scripts/characters/player.gd:683`, `scripts/objects/enemy.gd:3858`
**Symptom:** Every fired bullet calls `PackedScene.instantiate()` and every
terminated bullet calls `queue_free()`.
**Impact:** 200+ alloc/free cycles per second at 20 enemies × 10 Hz. Each
cycle triggers physics-server registration, scene-tree callbacks, and GC.
**Fix:** Introduce `BulletPool` autoload (200 pre-allocated bullets). Player
and enemy both call `BulletPool.acquire()` / `BulletPool.activate()` instead
of `instantiate()` + `add_child()`. Bullets call `_return_to_pool()` instead of
`queue_free()`.

### Bottleneck 2 (HIGH) — Unbounded blood decal accumulation

**File:** `scripts/autoload/impact_effects_manager.gd:34`
**Symptom:** `MAX_BLOOD_DECALS = 0` (unlimited). Each lethal hit spawns
10–20 `Sprite2D` + `Area2D` blood decal nodes. In a session with 50+ enemies,
this grows to thousands of persistent nodes.
**Measurement (issue #844):** 3,640+ blood decal nodes after one play session.
**Fix:** `MAX_BLOOD_DECALS = 300`. FIFO cleanup was already implemented.

### Bottleneck 3 (HIGH) — Unbounded bullet hole accumulation

**File:** `scripts/autoload/impact_effects_manager.gd:45`
**Symptom:** `MAX_BULLET_HOLES = 0` (unlimited). Each wall-penetrating bullet
leaves a persistent `Sprite2D` node.
**Fix:** `MAX_BULLET_HOLES = 200`. FIFO cleanup was already implemented.

### Bottleneck 4 (MEDIUM-HIGH) — DebugPenetration = true in release build

**File:** `Scripts/Projectiles/Bullet.cs:181`, `scripts/projectiles/bullet.gd:103`
**Symptom:** `DebugPenetration = true` / `_debug_penetration = true` causes
`LogPenetration()` / `_log_penetration()` to fire synchronously on every wall
collision. Each call writes to a file via `FileLogger`.
**Impact:** Multiple file writes per bullet per physics frame while penetrating.
**Fix:** Set both flags to `false`.

---

## Solutions Implemented

### Fix 1 — BulletPool autoload (`scripts/autoload/bullet_pool.gd`)

New singleton registered in `project.godot`. Pre-allocates 200 bullet nodes
in a `Node2D` container, parking them with physics/visibility disabled. Public
API: `acquire() → Node2D`, `activate(bullet, scene_root)`, `release(bullet)`.

```gdscript
# Before (player.gd):
var bullet := bullet_scene.instantiate()
get_tree().current_scene.add_child(bullet)

# After (player.gd):
var bullet := BulletPool.acquire()   # or fallback instantiate
# ... set properties ...
BulletPool.activate(bullet, get_tree().current_scene)
```

`bullet.gd` gains:
- `reset_for_pool()` — clears all mutable runtime state (timers, ricochet,
  penetration, homing, breaker flags, trail history).
- `_return_to_pool()` — calls `BulletPool.release(self)` with a
  `queue_free()` fallback when the pool is unavailable.
- All `queue_free()` calls in bullet logic replaced with `_return_to_pool()`.

### Fix 2 — Blood decal / bullet hole limits

```gdscript
# Before:
const MAX_BLOOD_DECALS: int = 0   # unlimited
const MAX_BULLET_HOLES: int = 0   # unlimited

# After:
const MAX_BLOOD_DECALS: int = 300
const MAX_BULLET_HOLES: int = 200
```

The FIFO cleanup code was already in place (`_blood_decals.pop_front()` +
`queue_free()`). Enabling it caps the scene tree size during extended sessions
without any visible change to nearby blood effects.

### Fix 3 — Disable DebugPenetration flags

```csharp
// Bullet.cs — before:
private const bool DebugPenetration = true;
// After:
private const bool DebugPenetration = false;
```

```gdscript
# bullet.gd — before:
var _debug_penetration: bool = true
# After:
var _debug_penetration: bool = false
```

---

## Online Research Findings (2024–2026)

### Why node pooling is non-optional in Godot 4

The engine team acknowledged in [godotengine/godot#71182](https://github.com/godotengine/godot/issues/71182) that
Godot 4.x creates nodes ~4× slower than Godot 3.x due to the new
scene-tree architecture.  Without pooling, GC spikes cause visible frame
drops; community benchmarks show framerate swinging between 10–50 FPS,
while with pooling a constant 60 FPS is maintained.

Reference: <https://uhiyama-lab.com/en/notes/godot/godot-object-pooling-basics/>

### Collision pair count grows O(n²)

With 100 enemies clustered together, Godot generates ~10,000 collision
pairs per frame.  Exceeding 5,000 starts degrading performance on
mid-range hardware.

Reference: <https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027>

Relevant to this fix: disabling `monitoring = false` on idle pooled
bullets eliminates their contribution to the broadphase query set.

### Direct PhysicsServer2D / rendering (future consideration)

For scenarios with 1,000+ simultaneous bullets, bypassing the scene tree
entirely and communicating directly with `PhysicsServer2D` + a single
`_draw()` call can reduce per-physics-step cost from ~230 ms to near-zero.
This is the approach used by the [PerfBullets](https://github.com/Moonzel/Godot-PerfBullets)
and [BlastBullets2D](https://github.com/nikoladevelops/godot-blast-bullets-2d)
plugins.  Not implemented here because the game's bullet count
(≤200 concurrent) is well within the pool approach's sweet spot.

### Single manager vs. per-bullet `_physics_process`

Moving bullet movement logic into a single centralized manager that
iterates an array is more efficient than 200 individual `_physics_process`
callbacks due to ScriptLanguage dispatch overhead.  This is a potential
future optimisation if profiling reveals per-bullet callback overhead
remains a bottleneck after the pool is in place.

Reference: <https://docs.godotengine.org/en/stable/tutorials/best_practices/node_alternatives.html>

---

## Existing Alternatives / Libraries Considered

| Option | Assessment |
|--------|-----------|
| **Godot MultiMesh** | Can render thousands of identical meshes cheaply, but requires manual collision tracking; overkill for <200 concurrent bullets with complex per-bullet logic (ricochet, penetration, homing). |
| **PerfBullets / BlastBullets2D** | Direct PhysicsServer2D plugins. Optimal for 1000+ bullets; adds external dependency. Current bullet count does not require it. |
| **EasyPool addon** (<https://godotassetlibrary.com/asset/o5JHgu/easypool>) | Generic object pool addon. Our custom pool is simpler and integrates directly with the existing bullet lifecycle. No external dependency needed. |
| **godot-object-pool** (<https://github.com/godot-addons/godot-object-pool>) | Similar to above. |
| **Reduce bullet lifetime** | Lowering `lifetime = 3.0 s` would reduce concurrent bullets but would change visible gameplay. Excluded per issue requirement "no visible/audible cutbacks". |
| **Area2D→RayCast2D bullets** | Hitscan bullets (instant raycast) eliminate node churn entirely but are a major gameplay mechanic change. Excluded. |

---

## Real-World Measurement — game_log_20260220_001039.txt

The owner provided a real game log (`docs/case-studies/issue-862/game_log_20260220_001039.txt`)
recorded on Windows (Godot 4.3-stable, non-debug build) on 2026-02-20.

### Session Overview

| Phase | Enemy Count | Observed FPS |
|-------|-------------|--------------|
| 00:10:39 – 00:10:49 | 5 enemies | 60 FPS (smooth) |
| 00:10:50 – 00:11:26 | 10 enemies | 60 FPS (smooth) |
| 00:11:27 – 00:11:47 | 10 enemies (combat) | 48–60 FPS (mild drops) |
| 00:11:48 – 00:12:01 | 20 enemies | 40 FPS average |
| 00:12:20 – 00:12:28 | 20 enemies (peak) | **~7.5 FPS (worst)** |
| 00:12:34 – 00:13:52 | 20 enemies | 33–40 FPS |

FPS was derived from `[ReplayManager] Recording frame N (Xs)` log entries:
60 game frames should occur in 1.0 real second at target 60 FPS; the log
shows 60 frames taking 8 real seconds at worst, equivalent to ~7.5 FPS.

### Bottleneck Confirmation from Log

| Bottleneck | Log Evidence |
|-----------|--------------|
| BulletPool NOT active | No `[BulletPool]` lines at all — bullets were instantiate/freed each shot |
| 2,920 BloodDecal nodes | `grep -c "Blood puddle created" log` → 2,920 events, no cleanup logged |
| ~1,490 ImpactEffects log writes | `grep -c "\[ImpactEffects\]" log` → 1,490 (file I/O on each) |
| 275 unconditional `spawn_blood_effect` log calls | All at `_log_info()` level (always write to FileLogger) |
| Footprint accumulation | "12 footprints to spawn" × multiple enemies, no cleanup logged |
| SoundPropagation O(n) | `listeners=25` then "Cleaned up 15 invalid listeners" on first gunshot |

### Why the Log Was from a Pre-Fix Build

The log session shows no `[BulletPool]` lines, confirming this was recorded before
PR #863 changes were applied. The analysis above validates all three original fixes
and identified two additional bottlenecks addressed in subsequent commits.

---

## Additional Fixes (from game log analysis)

### Bottleneck 5 (HIGH) — Unconditional FileLogger writes per blood hit

**File:** `scripts/autoload/impact_effects_manager.gd:254`

`spawn_blood_effect()` called `_log_info()` 4× unconditionally on every
blood effect spawn — at entry, instantiation, scheduling, and wall-splatter
detection. With 275 blood effect spawns in the logged session (and more
in longer sessions), this produced **~1,100+ file I/O operations** just for
blood effects, on top of the wall-splatter and decal-scheduled log lines.

`_log_info()` writes to both `print()` (stdout/OS buffer) and `FileLogger`
(synchronous disk write). In the hot path during peak combat, these calls
directly steal frame time from the physics thread.

**Fix:** All per-bullet/per-hit `_log_info()` calls removed or moved behind
`_debug_effects = false`. Genuine errors use `push_error()` (recorded in
Godot's error log, no file I/O). One-time events (ready, init, warmup,
scene change) keep their log lines.

**Estimated impact:** ~0.5–1.5 ms/frame during 20-enemy combat with 275+
blood effects per session (eliminates ~1,100 synchronous disk writes).

### Bottleneck 6 (MEDIUM) — Unbounded footprint node accumulation

**File:** `scripts/components/bloody_feet_component.gd`

`_spawn_footprint()` added `Sprite2D` (BloodFootprint) nodes to the scene
tree with **no tracking array and no cap**. With 20 enemies each capable
of spawning 12 footprints per blood contact, a single firefight produces
240+ nodes. Over multiple rooms and encounters these accumulate indefinitely
(unlike blood decals, no cleanup was previously in place at all).

**Fix:** Added `static var _all_footprints: Array` shared across all
`BloodyFeetComponent` instances and FIFO eviction at `MAX_FOOTPRINTS = 150`.
The cap is well above any single room's visible footprint count (150 ÷ 12
= 12.5 enemies worth of full footprint trails visible simultaneously).

**Estimated impact:** ~0.2–0.5 ms/frame in sessions with 20+ enemies and
repeated blood contacts.

---

## Expected Performance Impact (All Fixes)

| Fix | Estimated Frame-Time Saving |
|-----|----------------------------|
| BulletPool (no instantiate/free) | ~1–3 ms/frame at 20 enemies, 10 Hz |
| Blood decal cap (300) | ~0.5–2 ms/frame for scenes with 1000+ decals |
| Bullet hole cap (200) | ~0.2–0.5 ms/frame |
| Disable DebugPenetration | ~0.3–1 ms/frame (eliminates file I/O) |
| Remove per-bullet FileLogger writes | ~0.5–1.5 ms/frame (1,100+ writes eliminated) |
| Footprint cap (150) | ~0.2–0.5 ms/frame |
| **Total** | **~2.7–9.5 ms/frame** in peak bullet-hell scenarios |

At 60 FPS, each frame budget is ~16.7 ms. The combined saving in the worst
case represents a **16–57% improvement** in available frame time during heavy
combat. This should bring the worst-case 7.5 FPS scenario back to 30–45+ FPS
even before further optimisations.

---

## Files Changed

| File | Change |
|------|--------|
| `Scripts/Projectiles/Bullet.cs` | `DebugPenetration = false` |
| `scripts/projectiles/bullet.gd` | `_debug_penetration = false`, `reset_for_pool()`, `_return_to_pool()`, replace `queue_free()` |
| `scripts/autoload/impact_effects_manager.gd` | `MAX_BLOOD_DECALS = 300`, `MAX_BULLET_HOLES = 200`; per-bullet log calls removed/guarded |
| `scripts/autoload/bullet_pool.gd` | **New** — BulletPool autoload |
| `project.godot` | Register `BulletPool` autoload |
| `scripts/characters/player.gd` | Use pool in `_shoot()` |
| `scripts/objects/enemy.gd` | Use pool in `_spawn_projectile()` |
| `tests/unit/test_bullet_pool.gd` | **New** — unit tests for pool API |
| `scripts/components/bloody_feet_component.gd` | `MAX_FOOTPRINTS = 150` FIFO cleanup |
| `docs/case-studies/issue-862/game_log_20260220_001039.txt` | Real session log provided by owner |
