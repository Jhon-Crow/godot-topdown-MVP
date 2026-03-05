# Case Study: F-1 Grenade Lag in Enclosed Spaces (Issue #937)

## Problem Statement

The F-1 (defensive) grenade causes significant lag (lag spike) when exploding near walls in enclosed spaces (LabyrinthLevel), while performance on open levels (BuildingLevel/polygon) is nearly unaffected.

**Report (issue text):** "в замкнутых пространствах взрыв ф-1 вызывает большие пролаги чем на полигоне (на полигоне почти нет пролагов)" — In enclosed spaces, F-1 explosion causes large lag spikes compared to the open polygon (almost no lag there).

## Data Sources

| Source | Description |
|--------|-------------|
| `game_log_20260301_032300.txt` | Full 26,682-line user game log from Windows build |
| `scripts/projectiles/defensive_grenade.gd` | F-1 grenade implementation |
| `scripts/projectiles/shrapnel.gd` | Shrapnel projectile implementation |
| `scripts/autoload/last_chance_effects_manager.gd` | Time-freeze system triggered on explosion |
| `scripts/autoload/impact_effects_manager.gd` | Explosion visual effects system |
| `scripts/autoload/projectile_pool_manager.gd` | Object pooling for projectiles |
| `docs/case-studies/issue-724/fps_drop_investigation_2026-02-14.md` | Prior FPS drop analysis |
| Online research (Godot community forums, GitHub issues, docs) | Performance analysis facts |

## Timeline Reconstruction from Game Log

### Sequence of events when F-1 grenade explodes in LabyrinthLevel

```
[03:23:37] [GrenadeBase] EXPLODED at (642.3918, 679.3748)!
[03:23:37] [PowerFantasy] Grenade exploded - triggering last chance time-freeze effect for 2000ms
[03:23:37] [LastChance] Grenade explosion triggering last chance effect for 2.00 seconds
[03:23:37] [LastChance] Starting last chance effect...
[03:23:37] [LastChance] Set player Player and all 37 children to PROCESS_MODE_ALWAYS
[03:23:37] [LastChance] Set StaticBody2D 'WallTop' to PROCESS_MODE_ALWAYS for collision  (×37 walls + furniture = 38 items)
...
[03:23:37] [LastChance] Froze all nodes except player and autoloads
[03:23:37] [DefensiveGrenade] Spawned shrapnel #1 at angle -9.1 degrees
... (40 shrapnel pieces spawned)
[03:23:37] [DefensiveGrenade] Spawned shrapnel #40 at angle 359.9 degrees
[03:23:37] [LastChance] Freezing newly created shrapnel (×40 pieces)
[03:23:39] [LastChance] Effect duration expired after 2.00 real seconds
[03:23:39] [LastChance] Unfroze shrapnel: Shrapnel ... (×40 pieces)
... (40 shrapnel pieces all resume simultaneously, bouncing off walls)
```

**Key observations from the log:**
1. Every explosion triggers the `LastChance` time-freeze system
2. The LastChance system iterates all scene nodes to set `PROCESS_MODE_ALWAYS` on 38 StaticBody2D objects + player + dozens of other nodes
3. DefensiveGrenade spawns **40 shrapnel pieces** (vs 4 for FragGrenade)
4. All 40 shrapnel pieces are unfrozen simultaneously after 2 seconds
5. In LabyrinthLevel (enclosed): 40 shrapnel pieces simultaneously bounce in a small space with many walls

### Open space (BuildingLevel) vs Enclosed space (LabyrinthLevel) comparison

| Factor | BuildingLevel (open, low lag) | LabyrinthLevel (enclosed, high lag) |
|--------|-------------------------------|--------------------------------------|
| Wall count | Fewer walls (open level) | 38 walls + furniture = ~38 StaticBody2D objects |
| Shrapnel behavior | Most shrapnel travels far before hitting walls | Shrapnel immediately hits walls in narrow corridors |
| Ricochet count per shrapnel | Few ricochets, disappears quickly | Up to 3 ricochets × 40 pieces = 120 wall collisions |
| Raycasts per frame | Low | Up to 40 simultaneous `intersect_ray()` calls/frame |
| Collision pairs | Low density | High density: 40 Area2D objects clustering in small rooms |
| Physics engine work | Linear with sparse distribution | O(N²) due to dense clustering |

## Root Cause Analysis

### Root Cause 1 (PRIMARY): LastChance freeze triggers expensive scene traversal on every explosion

**Location:** `scripts/autoload/last_chance_effects_manager.gd`, `_freeze_node_except_player()`

**What happens:** On every grenade explosion (triggered by `PowerFantasy` grenade effect signal), the `LastChance` system traverses the **entire scene tree recursively** to find and set `process_mode` on every node.

**Evidence from log:** 38 individual `Set StaticBody2D '...' to PROCESS_MODE_ALWAYS` log entries per explosion, plus all enemies, furniture, and other objects. In LabyrinthLevel this is more nodes due to more room dividers and corridors.

**Why this causes lag:**
- Setting `process_mode` on a node causes that node to notify the physics server (Godot engine internals). For physics bodies (StaticBody2D), this registers or deregisters the body in the physics space.
- Per Godot core contributor **smix8**: "Physics nodes that cannot process get removed from the physics space and that can cost a lot of performance." (Source: [Godot Forum - Bad Pooling Performance from process_mode](https://forum.godotengine.org/t/solved-bad-pooling-performance-thanks-to-set-deferred-process-mode/68200))
- In LabyrinthLevel, there are more walls (38+) vs fewer in open levels — **more nodes affected = more expensive traversal**

**Why it's WORSE near walls (not just any explosion):**
- The LabyrinthLevel has more walls close together
- The traversal cost is proportional to the total number of scene nodes
- When the explosion is near walls, there are more "active" StaticBody2D nodes within the frustum, requiring more physics server notifications

### Root Cause 2 (SECONDARY): 40 simultaneous shrapnel pieces resume at once after LastChance freeze ends

**Location:** `scripts/projectiles/defensive_grenade.gd` `shrapnel_count = 40`; `scripts/autoload/last_chance_effects_manager.gd` unfreeze logic

**What happens:** After the 2-second freeze, all 40 shrapnel pieces resume simultaneously. In a closed room with 38 walls, these immediately bounce and ricochet creating up to 120 wall collisions in a short time window.

**Evidence from log:**
```
[03:23:39] [LastChance] Unfroze shrapnel: Shrapnel
[03:23:39] [LastChance] Unfroze shrapnel: @Area2D@3079
... (40 total unfroze lines)
```

**Why this causes lag:**
1. **40 Area2D nodes simultaneously active in small space** → O(N²) collision pair problem.
   - Per [Godot Forum research](https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027): "When 100 entities cluster together, the engine creates up to 10,000 collision pair checks per frame." With 40 in a room, ~1600 pairs.
2. **40 simultaneous `intersect_ray()` calls** from `_get_surface_normal()` in `shrapnel.gd:186-203` — called every time shrapnel hits a wall.
   - In open level: most shrapnel leaves the bounded area quickly. In enclosed level: all 40 pieces ricochet repeatedly off walls.
3. **BVH tree thrashing**: Every moving Area2D body must update the BVH spatial partitioning tree each physics frame. 40 fast-moving shrapnel pieces = 40 BVH updates/frame.
   - Per [Godot proposals #13604](https://github.com/godotengine/godot-proposals/issues/13604): "Whenever [bodies] move, the BVH tree has to be modified (a potentially expensive operation)."

### Root Cause 3 (CONTRIBUTING): Shrapnel uses `_get_surface_normal()` via raycast on every wall hit

**Location:** `scripts/projectiles/shrapnel.gd:186-203`

```gdscript
func _get_surface_normal(body: Node2D) -> Vector2:
    var space_state := get_world_2d().direct_space_state
    var ray_start := global_position - direction * 50.0
    var ray_end := global_position + direction * 10.0
    var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end)
    query.collision_mask = collision_mask
    query.exclude = [self]
    var result := space_state.intersect_ray(query)
    ...
```

In an enclosed room, 40 pieces hit walls repeatedly — each triggering `intersect_ray()`. This is an additional batch of raycasts layered on top of the regular collision detection.

**In open level:** Low frequency — shrapnel quickly exits the bounded area and expires.
**In enclosed level:** High frequency — all 40 pieces bounce up to 3 times each = potentially 120 raycasts in rapid succession.

### Root Cause 4 (CONTRIBUTING): Blood decal spawning cascade from explosion damage

**Location:** `scripts/autoload/impact_effects_manager.gd`

When the explosion damages enemies (99 damage applied via on_hit_with_info called 99 times per enemy), each hit spawns blood effects with `await` timers for delayed decal spawning. In the log, dozens of blood decals are scheduled:

```
[03:23:37] [ImpactEffects] Blood decals scheduled: 10 to spawn at particle landing times
[03:23:37] [ImpactEffects] Blood decals scheduled: 20 to spawn at particle landing times
```

Each `await tree.create_timer(delay).timeout` creates a signal connection that runs a raycast (for wall detection) when the timer fires. These compound with shrapnel work.

## Performance Cost Summary

| Operation | Frequency at explosion | Cost driver |
|-----------|----------------------|-------------|
| LastChance scene traversal (set PROCESS_MODE) | 1× per explosion | O(scene_nodes) per call |
| Shrapnel spawn (40 pieces) | 1× per explosion | 40 instantiations from pool |
| Shrapnel unfreeze + resume | 1× after 2 second freeze | Physics server 40 body re-activations |
| Shrapnel wall collision + raycast | Up to 40×3 = 120 times | 120 `intersect_ray()` calls in short burst |
| Blood decal timer callbacks with raycast | 30+ deferred timers | 30+ raycasts over 1-2 second window |
| BVH tree updates from 40 moving Area2D | Every physics frame | 40 × O(log N) per frame |
| Collision pair checks | Every physics frame | O(40²) = 1,600 pairs in enclosed space |

## Why Enclosed Spaces Amplify the Problem

1. **More StaticBody2D nodes** in LabyrinthLevel (rooms + corridors = ~38 named walls) vs fewer walls in open level
2. **Shrapnel stays bounded**: In open levels, shrapnel travels far and expires. In rooms, it bounces multiple times before expiring
3. **Collision pair density**: 40 bodies in a 700px radius room → much higher pair density than 40 bodies spread across an open level
4. **Wall reflection raycasts**: Every bounce triggers `_get_surface_normal()` raycast. More walls = more bounces = more raycasts

## Proposed Solutions

### Solution A: Reduce DefensiveGrenade shrapnel count in enclosed spaces (LOW RISK, MEDIUM IMPACT)

**Approach:** Keep the 40-shrapnel spec, but reduce `max_ricochets` for shrapnel when used in enclosed spaces. Or: add a configuration option to reduce shrapnel count based on level type.

**Alternative simpler approach:** Reduce `max_ricochets` from 3 to 1 for shrapnel in defensive grenade. Each shrapnel still bounces once but doesn't create secondary and tertiary ricochets.

```gdscript
# In defensive_grenade.gd _spawn_shrapnel():
shrapnel.max_ricochets = 1  # Reduce from default 3 to limit ricochet count
```

**Impact:** Reduces ricochets from ~120 to ~40 in worst case.

### Solution B: Cache the LastChance wall list instead of traversing scene tree every explosion (HIGH IMPACT, MEDIUM RISK)

**Approach:** In `LastChance` manager, cache the list of StaticBody2D nodes once (at level load) and iterate the cached list instead of traversing the entire scene tree on every explosion.

**Why this helps:** The current code traverses `get_tree().root` recursively on every explosion. LabyrinthLevel has 38+ StaticBody2D nodes. Caching this list eliminates O(scene_nodes) traversal per explosion.

```gdscript
# In last_chance_effects_manager.gd:
var _cached_static_bodies: Array[StaticBody2D] = []

func _cache_static_bodies() -> void:
    _cached_static_bodies.clear()
    var scene := get_tree().current_scene
    if scene:
        _collect_static_bodies(scene, _cached_static_bodies)

func _collect_static_bodies(node: Node, result: Array) -> void:
    if node is StaticBody2D:
        result.append(node)
    for child in node.get_children():
        _collect_static_bodies(child, result)
```

**Impact:** Eliminates the recursive traversal overhead on explosion. The 38-node traversal itself is fast (O(38)), but combined with process_mode changes it creates significant overhead.

### Solution C: Stagger shrapnel unfreeze instead of simultaneous resume (HIGH IMPACT, LOW RISK)

**Approach:** When unfreezing 40 shrapnel pieces after the LastChance freeze, add a tiny stagger (1-2 physics frames) between pieces instead of activating all 40 simultaneously.

**Why this helps:** The primary performance hit is 40 physics bodies all resuming in the same frame, triggering simultaneous BVH updates and collision resolution. Staggering distributes this cost across multiple frames.

```gdscript
# In last_chance_effects_manager.gd _unfreeze_time():
var delay := 0
for shrapnel in _frozen_shrapnel:
    if is_instance_valid(shrapnel):
        if delay > 0:
            await get_tree().create_timer(delay * 0.016).timeout  # 1 frame delay
        shrapnel.process_mode = Node.PROCESS_MODE_INHERIT
        delay += 1
```

**Impact:** Spreads the physics re-activation cost over 40 frames (0.67 seconds at 60fps) instead of 1 frame spike.

### Solution D (MAIN RECOMMENDED): Pre-cache static body list in LastChance and limit shrapnel max ricochets

The combination of two targeted fixes addresses both identified root causes:

1. **Cache StaticBody2D list** at scene load in LastChance manager — eliminates scene traversal overhead
2. **Limit shrapnel `max_ricochets` to 1 for DefensiveGrenade** — reduces the ricochet cascade in enclosed spaces

These are the most surgical changes that address root cause 1 and 2 without changing gameplay significantly.

## Bug Fix: Game Crash on Grenade Explosion (PR Feedback)

### Issue Report

After initial PR implementation, user reported game crash during grenade explosion (comment from 2026-03-02):
- "при взрыве гранаты вылетела игра" (game crashed when grenade exploded)
- Attached log: `game_log_20260302_194309.txt`

### Analysis

The crash log showed:
1. Game running normally until 19:44:28 (frame 1020)
2. DefensiveGrenade exploded, spawned 40 shrapnel pieces
3. Log ends abruptly with no error message — indicating hard crash (SEGFAULT)

### Root Cause

**Issue 1: Unsafe property check in `defensive_grenade.gd`**

```gdscript
# BEFORE (unsafe):
if shrapnel.has_method("is_pooled") or "max_ricochets" in shrapnel:
    shrapnel.max_ricochets = shrapnel_max_ricochets

# AFTER (safe):
if "max_ricochets" in shrapnel:
    shrapnel.max_ricochets = shrapnel_max_ricochets
```

The `or` condition meant that if a shrapnel had `is_pooled()` method but somehow lacked the `max_ricochets` property, the code would crash trying to access a nonexistent property.

**Issue 2: Missing `max_ricochets` reset in `shrapnel.gd` pooling**

```gdscript
# BEFORE: _reset_state() did NOT reset max_ricochets
# Pool reuse would carry over the previous max_ricochets value

# AFTER: Added to _reset_state():
max_ricochets = _original_max_ricochets  # Reset to default (3)
```

This caused shrapnel reused from the pool to keep the `max_ricochets = 1` value from defensive grenades, even when reused for frag grenades which expect the default of 3.

### Fix Applied

1. Changed `defensive_grenade.gd` property check from `or` to simple property existence check
2. Added `_original_max_ricochets` variable to `shrapnel.gd` for reset
3. Added `max_ricochets = _original_max_ricochets` to `_reset_state()` function

## Related Prior Issues

| Issue | Connection |
|-------|-----------|
| Issue #724 | FPS drops from projectile spawning — solved with ProjectilePoolManager |
| Issue #724 (Feb 14 investigation) | F-1 grenade FPS drop from shadow-enabled PointLight2D — partially fixed |
| Issue #505 | LastChance freezing explosion visual effects |
| Issue #343 | Shader warmup to prevent first-shot freeze |
| Issue #470 | Wall-aware explosion visual effects |

## References

- [Godot Forum: Collision Pairs Optimization for Bullet Hell Games](https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027)
- [Godot Forum: Bad Pooling Performance from process_mode](https://forum.godotengine.org/t/solved-bad-pooling-performance-thanks-to-set-deferred-process-mode/68200)
- [Godot Proposals #13604: BVH-less body type proposal](https://github.com/godotengine/godot-proposals/issues/13604)
- [Godot Issue #54171: BVH performance drop with 4000+ monitorable areas](https://github.com/godotengine/godot/issues/54171)
- [Godot Forum: How to Optimize Collision Shapes](https://forum.godotengine.org/t/how-to-optimize-collision-shapes/74658)
- [Godot Forum: Multithreading intersect_ray() Raycasts](https://forum.godotengine.org/t/multithreading-intersect-ray-raycasts/52663)
- [Godot Troubleshooting: Physics Spiral of Death](https://trinovantes.github.io/godot-docs/tutorials/physics/troubleshooting_physics_issues.html)
- [Godot Forum: Raycast vs ShapeCast vs Area performance](https://forum.godotengine.org/t/raycast-vs-shapecast-vs-area/95569)
- [Godot Forum: Lots of RigidBodies and CollisionShape2D Lead to Low FPS](https://forum.godotengine.org/t/lots-of-rigidbodies-and-collisionshape2d-lead-to-low-fps/22438)
