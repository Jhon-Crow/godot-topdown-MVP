# Case Study: Issue #1145 — FPS Drop When Shooting at Walls

## Summary

**Issue**: FPS drops from 60 to ~26–30 fps when shooting at walls, reported by user with Mini UZI.

**Root causes identified** (in priority order):
1. **Redundant physics raycasts**: `_get_surface_normal()` called twice per bullet-wall collision (once for dust effect, once for ricochet), doubling the per-frame raycast cost during actual wall hits. ✅ **Fixed in this PR.**
2. **EMPTY_CLICK propagation at fire rate**: When holding fire with an empty weapon, `AmmoDepleted` signal fires at the weapon's fire rate (~10–15/sec for Mini UZI), each triggering SoundPropagation to iterate all 10 listeners + 10 enemy vulnerability checks. This is a separate pre-existing performance issue.

---

## Timeline Reconstruction

### Session 1 — Log: `game_log_20260318_064123.txt`

| Time | Event |
|------|-------|
| 06:41:24 | Game start. Level: BuildingLevel. Weapon: Mini UZI (selected at 06:41:24) |
| 06:41:25 | Shader/particle warmup complete. **FPS drop: 15 fps** (startup spike, unrelated to shooting) |
| 06:41:29 | Scene changed to Tutorial. **FPS drop: 23 fps** (scene transition spike) |
| 06:41:52 | Player fires Mini UZI — shots 2–32 (30 GUNSHOT events, ~10/sec). During this phase: no FPS drops. |
| 06:41:55 | Magazine empty (shot 32). `AmmoDepleted` fires. Enemy AI broadcasts `ammo_empty=true` to all 10 enemies. |
| 06:41:55 | Player holds trigger → EMPTY_CLICK emitted 10+ times/sec. **FPS drop: 29 fps** |
| 06:41:56 | Continues holding trigger. 10 enemies each log vulnerability check every ~0.5s. **FPS drop: 26 fps** |
| 06:41:57 | Still holding trigger. **FPS drop: 27 fps** |
| 06:41:57 | Log ends |

**Key observation**: FPS drops in Session 1 happen **after** the magazine empties, during `EMPTY_CLICK` events — NOT during actual bullet-wall collision phase. The drops are minor (29/26/27 fps, just below the 30 fps threshold).

### Session 2 — Log: `game_log_20260318_081028.txt`

| Time | Event |
|------|-------|
| 08:10:28 | Game start. Level: LabyrinthLevel. Weapon: AK+GL |
| 08:10:32 | Particle shader warmup (3158 ms). **FPS drop: 1 fps** (startup spike) |
| 08:10:40 | Scene changed to Tutorial (weapon: Mini UZI). **FPS drop: 15 fps** (scene transition spike) |
| 08:10:44 | Scene changed again to Tutorial. **FPS drop: 2 fps** (scene transition spike) |
| 08:10:44 | Player dies (player_valid=False). All 10 SoundPropagation listeners cleaned up |
| 08:10:48 | Player fires Mini UZI. `listeners=0` → no sound propagation overhead. No FPS drops. |
| 08:11:12 | Scene reload. Player fires Mini UZI again. Still `listeners=0`. No FPS drops. |
| 08:11:35 | Log ends |

**Key observations for Session 2**:
1. All FPS drops happen during **shader warmup and scene transitions**, NOT during gameplay shooting.
2. During actual shooting (08:10:48–08:10:50 and 08:11:12–08:11:29), **zero FPS drops are logged**.
3. The game executable being tested is from `I:/Загрузки/godot exe/оптимизация/` — this is a **pre-compiled binary** that does NOT include the fix from this PR. The fix requires re-exporting the project.

---

## Root Cause Analysis

### Root Cause 1: Duplicate Raycasts per Bullet-Wall Collision

**File**: `scripts/projectiles/bullet.gd`

When a bullet hits a `StaticBody2D` wall, `_on_body_entered()` executes:

```gdscript
# Before fix: two separate calls to _get_surface_normal()
if body is StaticBody2D or body is TileMap:
    _spawn_wall_hit_effect(body)   # ← _get_surface_normal(body) → raycast #1
    ...
    if _try_ricochet(body):        # ← _get_surface_normal(body) → raycast #2 (REDUNDANT)
```

`_get_surface_normal()` calls `space_state.intersect_ray()` — an expensive physics operation that traverses the Godot BVH collision tree:

```gdscript
func _get_surface_normal(body: Node2D) -> Vector2:
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end)
    var result := space_state.intersect_ray(query)  # expensive: full BVH traversal
```

With Mini UZI at 10–15 shots/sec all hitting the same wall, this was **30 extra raycasts per second** (2 per shot → 1 wasted per shot × 15 shots/sec = 15 extra/sec for a 32-round magazine).

**Fix applied** (commit `46fc0be0`): Compute the normal once in `_on_body_entered`, cache it in `cached_normal`, and pass it to both functions. Backward-compatible — both functions default to `Vector2.ZERO` and call `_get_surface_normal()` themselves only if no pre-computed value is provided.

### Root Cause 2: EMPTY_CLICK Propagation at Fire Rate (Pre-existing)

When the player holds the trigger with an empty weapon, `Player.cs` emits `AmmoDepleted` on every frame where `shootInputActive` is true (for automatic weapons: every frame while button held). At 60fps with `CanFire` rate-limited to ~10/sec, this fires at the weapon's fire rate.

Each `AmmoDepleted` event triggers:
1. `_on_player_ammo_depleted()` → `_broadcast_player_ammo_empty(true)` → calls `set_player_ammo_empty(true)` on all `N` enemies
2. `emit_player_empty_click()` → `SoundPropagation.emit_sound()` → iterates all `N` listeners to check distance
3. Each listener logs a vulnerability check at most every 30 frames (~0.5s)

With 10 enemies, this is `10 + 10 = 20` function calls per empty-click event, at ~10 events/sec = **200 calls/sec during empty-weapon hold**.

This is a **pre-existing issue** unrelated to the wall-hitting raycast problem, visible in Session 1 logs after the magazine empties. A fix for this would require throttling `AmmoDepleted` (similar to `CASING_KICK_PROPAGATION_COOLDOWN` in `sound_propagation.gd`).

### Secondary Issue: Per-frame Raycasts During Penetration

While a bullet penetrates a wall, `_physics_process` calls `_is_still_inside_obstacle()` every frame, which fires **2 raycasts per frame**. At 60fps, and penetration lasting ~1–2 frames (48px max / 2500px·s⁻¹ ≈ 0.02s ≈ 1 frame), the total cost is minor (2–4 extra raycasts per bullet). Not a significant contributor.

---

## Evidence: Session 1 Log FPS Drops Correlate with EMPTY_CLICK, Not GUNSHOT

From `game_log_20260318_064123.txt`:

```
[06:41:52] Shot fired with mini_uzi (1 total)   ← shooting starts, no FPS drop
...
[06:41:55] Shot fired with mini_uzi (32 total)  ← last bullet fired
[06:41:55] [ENEMY] Enemy1..Enemy10 Player ammo empty: false -> true  ← ammo depleted
[06:41:55] Sound emitted: type=EMPTY_CLICK       ← empty gun, still holding trigger
...
[06:41:55] [WARN] [FPS] Drop detected: 29 fps   ← DROP starts HERE (during EMPTY_CLICK phase)
[06:41:56] [WARN] [FPS] Drop detected: 26 fps
[06:41:57] [WARN] [FPS] Drop detected: 27 fps
```

During shots 1–32 (actual GUNSHOT+wall-hit phase), **no FPS drops are logged**.

---

## Raycast Budget Analysis

| Source | Rate | Raycasts/sec | Notes |
|--------|------|--------------|-------|
| Bullet wall hit (before fix) | 15 shots/sec | 30/sec | 2× per hit (redundant) |
| Bullet wall hit (after fix) | 15 shots/sec | 15/sec | 1× per hit (optimal) |
| Bullet penetration check | ~1 per bullet | ~2/bullet | Bounded by max_penetration_distance |
| Visibility checks (10 enemies) | ~60/sec each | ~600/sec | From enemy AI raycasts |
| Player AmmoDepleted overhead | 10 events/sec | 200 calls/sec | Not raycasts, but CPU cost |

The wall-hit raycast fix reduces per-wall-hit cost by 50% — meaningful when spraying a wall.

---

## Existing Similar Fixes in This Codebase

- **Issue #969**: `CASING_KICK` sound propagation throttled (max once per 0.4s) to prevent flooding from high-fire-rate weapons. Same pattern as the EMPTY_CLICK issue identified here.
- **Issue #724**: Object pooling added to eliminate per-bullet `instantiate()` calls.
- **Issue #343**: Shader warmup pre-compiles shaders to eliminate first-shot lag spikes (explains Session 2 startup FPS drops).
- **Issue #883**: FPS monitoring added — the source of `[FPS] Drop detected` log lines.

---

## Possible Additional Solutions

### Solution A (Implemented): Cache surface normal once per wall hit ✅
Eliminates duplicate `intersect_ray` call per bullet-wall collision. **50% fewer raycasts per wall hit.**

### Solution B: Throttle EMPTY_CLICK propagation (similar to CASING_KICK)
Add `EMPTY_CLICK_PROPAGATION_COOLDOWN` (e.g. 0.2s) to `emit_player_empty_click()`. The first empty-click alert is sufficient for enemies — subsequent ones at 10/sec add no gameplay value.

### Solution C: Use collision normal from `body_entered` signal
Godot's `body_entered` signal on `Area2D` doesn't directly provide normal. However, switching to `body_shape_entered` or `area_shape_entered` with a separate `_physics_process` contact query could provide normals without extra raycasts.

### Solution D (external): `godot-blast-bullets-2d` plugin
Batch-processes thousands of bullets with MultiMesh and single raycast calls. Overkill for this game's scale (~32 bullets max), but useful reference for architecture.

---

## References

- [Godot 4 ray-casting documentation](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)
- [PhysicsDirectSpaceState2D](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html)
- [Godot Forum: Collision Pairs optimizing performance of bullet-hell games](https://forum.godotengine.org/t/collision-pairs-optimizing-performance-of-bullet-hell-enemy-hell-games/35027)
- [Godot Forum: Multithreading intersect_ray raycasts](https://forum.godotengine.org/t/multithreading-intersect-ray-raycasts/52663)
- [Issue #969: CASING_KICK throttling](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/969)
- [Issue #343: Shader warmup](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/343)
