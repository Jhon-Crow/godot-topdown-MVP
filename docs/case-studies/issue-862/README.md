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

## Existing Alternatives / Libraries Considered

| Option | Assessment |
|--------|-----------|
| **Godot MultiMesh** | Can render thousands of identical meshes cheaply, but requires manual collision tracking; overkill for <200 concurrent bullets with complex per-bullet logic (ricochet, penetration, homing). |
| **EasyPool addon** (<https://godotassetlibrary.com/asset/o5JHgu/easypool>) | Generic object pool addon. Our custom pool is simpler and integrates directly with the existing bullet lifecycle. No external dependency needed. |
| **godot-object-pool** (<https://github.com/godot-addons/godot-object-pool>) | Similar to above. |
| **Reduce bullet lifetime** | Lowering `lifetime = 3.0 s` would reduce concurrent bullets but would change visible gameplay. Excluded per issue requirement "no visible/audible cutbacks". |
| **Area2D→RayCast2D bullets** | Hitscan bullets (instant raycast) eliminate node churn entirely but are a major gameplay mechanic change. Excluded. |

---

## Expected Performance Impact

| Fix | Estimated Frame-Time Saving |
|-----|----------------------------|
| BulletPool (no instantiate/free) | ~1–3 ms/frame at 20 enemies, 10 Hz |
| Blood decal cap (300) | ~0.5–2 ms/frame for scenes with 1000+ decals |
| Bullet hole cap (200) | ~0.2–0.5 ms/frame |
| Disable DebugPenetration | ~0.3–1 ms/frame (eliminates file I/O) |
| **Total** | **~2–7 ms/frame** in peak bullet-hell scenarios |

At 60 FPS, each frame budget is ~16.7 ms. A 2–7 ms saving in the worst case
represents a **12–42% improvement** in available frame time during heavy combat.

---

## Files Changed

| File | Change |
|------|--------|
| `Scripts/Projectiles/Bullet.cs` | `DebugPenetration = false` |
| `scripts/projectiles/bullet.gd` | `_debug_penetration = false`, `reset_for_pool()`, `_return_to_pool()`, replace `queue_free()` |
| `scripts/autoload/impact_effects_manager.gd` | `MAX_BLOOD_DECALS = 300`, `MAX_BULLET_HOLES = 200` |
| `scripts/autoload/bullet_pool.gd` | **New** — BulletPool autoload |
| `project.godot` | Register `BulletPool` autoload |
| `scripts/characters/player.gd` | Use pool in `_shoot()` |
| `scripts/objects/enemy.gd` | Use pool in `_spawn_projectile()` |
| `tests/unit/test_bullet_pool.gd` | **New** — unit tests for pool API |
