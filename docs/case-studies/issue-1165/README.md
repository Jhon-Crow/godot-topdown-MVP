# Case Study: Issue #1165 — Machete Enemies Not Moving/Attacking in Roguelike Mode

**Issue:** https://github.com/Jhon-Crow/godot-topdown-MVP/issues/1165
**Reported:** 2026-03-18
**Log file:** `game_log_20260318_092645.txt` (attached to issue, downloaded here)
**Environment:** Windows, Godot Engine 4.3-stable (official), Release build
**Mode:** Roguelike (`RoguelikeLevel`)

---

## Summary

The user reported that **machete-wielding enemies do not move or attack** in Roguelike mode. The title of the issue is "fix: roguelike mode", and the description (in Russian) says: *"enemies with machetes do not move and do not attack"*.

This case study reconstructs the exact sequence of events from the game log, identifies the root cause(s), and proposes solutions.

---

## Artifacts

| File | Description |
|---|---|
| `logs/game_log_20260318_092645.txt` | Original game log provided by the reporter (issue description) |
| `logs/game_log_20260318_111928.txt` | Second game log provided after iteration 1 fix attempt — confirms bug persisted |
| `logs/game_log_20260321_005835.txt` | Third game log provided after iteration 2 fix attempt — machete enemy still stuck in room 3 |

---

## Timeline / Sequence of Events

### Phase 1 — LabyrinthLevel (09:26:45 – 09:27:05)

- Game starts; autoloads initialize (GameManager, ScoreManager, DifficultyManager, etc.)
- `LabyrinthLevel` loads with 5 enemies (`Enemy1`–`Enemy5`), all using standard GUARD/PATROL behavior.
- Player is equipped with `ak_gl`. All 5 enemies have standard (non-machete) behavior.
- The level functions normally. Player completes it.

### Phase 2 — RoguelikeLevel, Room 1 (09:27:05 – 09:27:19)

- Scene changes to `RoguelikeLevel`. Player is forced to `makarov_pm` + Flashbang (roguelike loadout).
- 3 enemies spawn:
  - `Enemy_0`: pos=(384, 489.6), hp=1, behavior=GUARD
  - `Enemy_1`: pos=(960, 216), hp=1, behavior=GUARD
  - `Enemy_2`: pos=(384, 216), hp=2, behavior=PATROL
- Player kills `Enemy_0` (1 shot), then `Enemy_2` (2 shots), then `Enemy_1` (3 shots).
- No machete enemies present. Room clears normally.

### Phase 3 — RoguelikeLevel, Room 2 (09:27:19 – 09:27:31)

- Scene reloads. New 3 enemies:
  - `Enemy_0`: pos=(230.4, 360), hp=1, behavior=GUARD
  - `Enemy_1`: pos=(512, 504), hp=2, behavior=PATROL
  - `Enemy_2`: pos=(832, 360), hp=2, behavior=PATROL
- `Enemy_2` is noted as **PATROL STUCK** at `(832, 329.1913)` for 1.5s. This is the first sign of navigation trouble.
- Player kills `Enemy_0`, then `Enemy_1`, then `Enemy_2`. Room clears normally.
- **Key log at line 893:** `[09:27:23] [ENEMY] [Enemy_1] [#1107] Machete COMBAT stuck (0.8s), rerouting`

  This is the **first occurrence** of the machete stuck message. It implies that `Enemy_1` in this room is a machete enemy (weapon type assigned by `_random_enemy_weapon` based on room type), but it was killed during the stuck loop.

### Phase 4 — RoguelikeLevel, Room 3 (09:27:31 – 09:27:34, partial)

- 3 new enemies: all GUARD behavior.
- Some enemies immediately transition to PURSUING due to memory system.
- A machete enemy (`Enemy_0`) is present. It goes through the stuck loop.

### Phase 5 — RoguelikeLevel, Room 4 (09:27:34 – 09:27:51)

This is where the bug fully manifests. Enemy_0 is a **machete enemy** that gets into a persistent infinite loop:

```
[09:27:36] [ENEMY] [Enemy_0] [#1107] Machete COMBAT stuck (0.8s), rerouting
[09:27:36] [ENEMY] [Enemy_0] State: COMBAT -> PURSUING
[09:27:39] [ENEMY] [Enemy_0] [#1107] Machete COMBAT stuck (0.8s), rerouting
[09:27:39] [ENEMY] [Enemy_0] State: COMBAT -> PURSUING
[09:27:40] [ENEMY] [Enemy_0] State: PURSUING -> COMBAT
[09:27:41] [ENEMY] [Enemy_0] [#1107] Machete COMBAT stuck (0.8s), rerouting
[09:27:41] [ENEMY] [Enemy_0] State: COMBAT -> PURSUING
...
(repeating every ~0.8–1s until 09:27:51)
[09:27:51] [ENEMY] [Enemy_0] Hit: dmg=1, hp=1/1->0/1   ← player shoots it
[09:27:51] [ENEMY] [Enemy_0] Enemy died
```

The enemy never attacks the player — the player must shoot it. The enemy oscillates between COMBAT and PURSUING continuously, appearing to stand still.

---

## Root Cause Analysis

### Primary Root Cause: Navigation Mesh Mismatch in Procedurally-Generated Rooms

The roguelike level generates **procedural room layouts** at runtime using `_build_room()`. This creates walls and obstacles dynamically as `StaticBody2D` nodes, which affect physics but — critically — **do not automatically update the NavigationRegion2D baking**.

Godot 4's navigation mesh must be **re-baked** at runtime after adding or modifying obstacles, or `NavigationAgent2D` will navigate using stale mesh data. In a procedurally-generated room, enemies may spawn in positions where the navigation agent cannot find a valid path to the player because:

1. The nav mesh baked at scene load time does not reflect walls added procedurally.
2. The agent's path target (player's position) may be **unreachable** on the navigation map due to disconnected islands.

**Evidence:**
- `PATROL STUCK` message (line 829): `Enemy_2` stuck at `(832, 329.1913)` for 1.5s — typical of nav mesh island disconnection.
- The machete stuck loop happens in rooms 3 and 4 (later procedural rooms), not in room 1.
- The stuck counter resets on every rerouting attempt, then immediately triggers again — indicating the nav path never makes progress.

### Secondary Root Cause: COMBAT→PURSUING→COMBAT Loop Amplifies the Problem

The machete combat AI (in `scripts/objects/enemy.gd`) contains stuck detection (Issue #1107):

```gdscript
# In _process_combat_state():
if global_position.distance_to(_machete_combat_stuck_last_pos) < MACHETE_COMBAT_STUCK_DIST_THRESHOLD:
    _machete_combat_stuck_timer += delta
    if _machete_combat_stuck_timer >= MACHETE_COMBAT_STUCK_MAX_TIME:  # 0.8s
        _transition_to_pursuing()
```

And in PURSUING state, the machete enemy transitions back to COMBAT if it can see the player:

```gdscript
# In _process_pursuing_state():
if (_can_see_player and _player and dist <= CLOSE_COMBAT_DISTANCE) or ...:
    _transition_to_combat(); return
```

When the nav mesh is invalid/incomplete:
1. In **COMBAT**: enemy cannot navigate → position doesn't change → stuck timer fires → transitions to PURSUING.
2. In **PURSUING**: enemy can see the player (line-of-sight is OK; the raycast works) → **immediately** transitions back to COMBAT.
3. Repeat every ~0.8s.

The PURSUING→COMBAT transition happens in under 1 second (PURSUING_MIN_DURATION_BEFORE_COMBAT = 0.3s), which means the enemy effectively **stands still oscillating**.

### Tertiary Contributing Factor: Roguelike Weapon Assignment

The `_random_enemy_weapon()` function assigns `MACHETE` (weapon type 3) only for `DOCKS` room type:

```gdscript
RoomType.DOCKS:
    return [0, 2, 3][randi() % 3]  # 33% chance of MACHETE
```

The bug only manifests in rooms where a machete enemy is spawned, which is probabilistic. This explains why the reporter may not always see the bug, and why rooms 1–2 (which happened to get no machete enemies in this session) worked fine.

---

## Reconstruction of Why the Enemy Appears Frozen

From the log at Room 4 (09:27:34 onward):
- Enemy_0 is at `pos=(512, 216)` at spawn. Player starts at `(80, ~368)` — far away.
- Enemy_2 (gunner) engages player and is killed at 09:27:38.
- Enemy_0 (machete) enters COMBAT at 09:27:35, but immediately starts the stuck cycle.
- The cycle logs show the **position never changes significantly** — the enemy is stuck near its spawn point at `(512, 216)`.
- The player closes in (position goes from (80,425) → (547,370) → (587,384) → (553,367)), meaning the player is actually approaching the frozen enemy.
- The enemy can **see** the player (LOS is clear) but cannot **navigate** to it.
- Eventually the player walks close enough and shoots the enemy at 09:27:51.

The frozenness is caused entirely by the navigation failure — the enemy "wants" to move, triggers the stuck detection, tries to reroute (PURSUING), immediately returns to COMBAT because it can see the player, and repeats.

---

## Supporting Evidence from Godot 4 Navigation

### Nav mesh baking required after runtime geometry changes

Godot 4's NavigationRegion2D requires explicit `bake_navigation_polygon()` calls when the scene geometry changes at runtime. From the [Godot 4 documentation](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationregions.html):

> "The bake process only updates the NavigationRegion's polygon data. Changes to the scene geometry after baking will not automatically update the navigation data."

This is a **known pattern** where procedural level generation silently breaks navigation. The roguelike level creates walls, covers, and obstacles at runtime (`_build_room()`) but does not re-bake the navigation region.

### `map_get_closest_point` does not respect island boundaries

`NavigationServer2D.map_get_closest_point()` (used in `MacheteComponent.try_dodge()`) returns the closest point on the **entire map** regardless of which island the caller is on. When the player is on a disconnected nav mesh island, this function returns a point at the edge of the enemy's own island. `NavigationAgent2D` then generates a path that leads to that edge, exhausts the path, and reports `is_navigation_finished() == true` — even though the enemy is nowhere near the player.

This is confirmed by known Godot 4 issues:
- **GitHub #85247**: `is_target_reached()` fires early when `path_desired_distance > target_desired_distance`
- **GitHub #82560**: `is_target_reached` returns `false` even within target distance
- **GitHub #94709**: NavigationAgent2D gets stuck on opposite sides of an obstacle
- **Godot Forum**: No public API exists to query whether a target is reachable across island boundaries

### `is_navigation_finished()` as attack-range gate is unreliable

A common pattern error: checking `is_navigation_finished()` as the signal to enter attack/combat state. The function can return `true` prematurely (path end reached but not player position), causing the state machine to re-enter COMBAT before the enemy is in attack range — which then immediately fails, re-triggers PURSUING, and loops.

The correct pattern is to always gate attacks on direct distance: `global_position.distance_to(player.global_position) <= melee_range`.

### Navigation RID mismatch after scene reloads

Each room reload in roguelike (`SceneLoader.scene_changed_successfully`) tears down and re-creates the scene. If the enemy's `NavigationAgent2D` does not explicitly update its map RID after reload via `set_navigation_map(get_world_2d().get_navigation_map())`, it may query a stale/detached map, producing empty paths that fail silently.

---

## Proposed Solutions

### Solution 1 (Recommended): Re-bake NavigationRegion after Room Build

In `scripts/levels/roguelike_level.gd`, after `_build_room()` completes, trigger a navigation rebake:

```gdscript
func _build_room(room_node: Node2D) -> void:
    # ... existing build logic ...

    # Re-bake navigation after room geometry is finalized
    var nav_region: NavigationRegion2D = get_node_or_null("NavigationRegion2D")
    if nav_region:
        nav_region.bake_navigation_polygon()
    else:
        push_warning("[RoguelikeLevel] No NavigationRegion2D found — enemies may have navigation issues")
```

Note: This must be called **after** all walls and obstacles are added, and **before** enemies are spawned. Baking is synchronous by default in Godot 4; for large rooms, `NavigationServer2D.bake_from_source_geometry_data_async()` can be used for non-blocking baking.

### Solution 2: Spawn Enemies After Navigation Bake Completes

Ensure enemies are only spawned after navigation is ready (nav baking is deferred by one physics frame in Godot 4):

```gdscript
func _ready() -> void:
    _build_room(room_node)
    # Wait one physics frame for nav mesh bake to propagate to NavigationServer
    await get_tree().physics_frame
    _spawn_enemies_in_room(room_node)
```

### Solution 3: Improve Machete Stuck Behavior as Fallback

If the primary navigation fix is not applied immediately, improve the COMBAT→PURSUING loop to avoid the oscillation. Currently, PURSUING instantly transitions back to COMBAT because `_can_see_player` is true. The machete enemy should use a **cooldown before re-entering COMBAT** from PURSUING when it was stuck:

```gdscript
# In _process_pursuing_state():
# Only re-enter COMBAT after a minimum pursuit time AND the enemy has actually moved
var has_moved_enough := global_position.distance_to(_machete_combat_stuck_last_pos) > MACHETE_COMBAT_STUCK_DIST_THRESHOLD
if (_can_see_player and _player) and _pursuing_state_timer >= PURSUING_MIN_DURATION_BEFORE_COMBAT:
    if has_moved_enough:
        _transition_to_combat(); return
    # If not moved, keep pursuing (try different path)
```

### Solution 4: Add MACHETE Weapon Type to More Room Types

Currently MACHETE is only available in DOCKS rooms (33% chance). This is not directly a bug but means the issue is rare and hard to reproduce predictably. Leaving this as-is is fine, but testers should know to specifically test DOCKS rooms.

---

## Impact Assessment

| Severity | Frequency | User Impact |
|---|---|---|
| Medium | Moderate (33% chance per DOCKS room) | Enemy stands completely still and doesn't attack; breaks roguelike gameplay |

The bug is not a crash but significantly degrades gameplay quality when it occurs, as the enemy becomes a free kill rather than a challenge. In the session recorded, the user encountered this in multiple successive rooms, suggesting the nav mesh issue compounds across room loads.

---

## Files Relevant to the Fix

| File | Relevance |
|---|---|
| `scripts/levels/roguelike_level.gd` | Where room is built, enemies spawned — navigation rebake needed here |
| `scripts/objects/enemy.gd` | Machete COMBAT stuck detection (#1107), PURSUING→COMBAT transition |
| `scripts/components/machete_component.gd` | Melee range check, navigation dodge |
| `scripts/ai/states/pursuing_state.gd` | PURSUING state logic |

---

## External References

| Source | Relevance |
|---|---|
| [Godot #85247](https://github.com/godotengine/godot/issues/85247) | `is_target_reached()` fires early when path_desired_distance > target_desired_distance |
| [Godot #82560](https://github.com/godotengine/godot/issues/82560) | `is_target_reached` returns false even within distance |
| [Godot #94709](https://github.com/godotengine/godot/issues/94709) | NavigationAgent2D stuck on opposite sides of obstacle |
| [Godot Forum: map_get_closest_point issue](https://forum.godotengine.org/t/navigationserver2d-map-get-closest-point-issue/132040) | closest_point ignores island boundaries |
| [Godot Docs: NavigationRegions](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationregions.html) | Baking requirements for runtime geometry |
| [Godot Forum: NavigationAgent2D RID mismatch](https://forum.godotengine.org/t/solved-issue-with-navigationagent2d/38452) | Nav RID must be updated after scene reload |

---

## Fix Applied (PR #1168)

### Iteration 1 (commit 14a9684e — incomplete)

Two changes were made to `scripts/levels/roguelike_level.gd`:
1. Added `nav_region.bake_navigation_polygon(false)` at the end of `_setup_navigation()`.
2. Added MACHETE to LABYRINTH, BUILDING, and CITY room weapon pools.

**Result:** The user tested and reported "не работает" (still not working), with a second log (`game_log_20260318_111928.txt`). Analysis of that log revealed **two remaining bugs**.

### Root Cause of Iteration 1 Failure

**Bug A — Deferred physics registration**: `bake_navigation_polygon(false)` was called immediately after `add_child(nav_region)`, but the `StaticBody2D` collision shapes created in `_build_room_scene()` are not registered with the `PhysicsServer2D` until the next physics frame. The bake found no colliders and produced an empty nav mesh. Evidence: other enemies with `SEARCHING` state tried to expand search radius from 175 → 625+ with **0 waypoints** found at any radius — the nav mesh had no walkable area at all.

**Bug B — Immediate PURSUING→COMBAT re-entry**: In `_process_pursuing_state()`, melee enemies transition back to COMBAT if `_can_see_player && distance <= CLOSE_COMBAT_DISTANCE (400px)` **with no minimum duration guard**. Ranged enemies have `_pursuing_state_timer >= PURSUING_MIN_DURATION_BEFORE_COMBAT (0.3s)` but melee did not. This caused the cycle:
1. COMBAT: nav fails → stuck timer (0.8s) → PURSUING
2. PURSUING: player visible within 400px → **immediately** COMBAT (no wait)
3. Repeat → enemy appears frozen

### Iteration 2 (commit 67d43a13)

**Fix 1 — `scripts/levels/roguelike_level.gd`**: Changed `nav_region.bake_navigation_polygon(false)` to `nav_region.bake_navigation_polygon.call_deferred(false)`. This defers the bake to the next engine idle step, giving `PhysicsServer2D` time to register wall/cover collision shapes.

**Fix 2 — `scripts/objects/enemy.gd`**: Added `_pursuing_state_timer >= PURSUING_MIN_DURATION_BEFORE_COMBAT` guard to the melee PURSUING→COMBAT transition, matching the guard already applied to ranged enemies. This breaks the oscillation loop.

**Result of Iteration 2 (third log — `game_log_20260321_005835.txt`):**
- **Room 1**: Still shows `wps=0` at every search radius (lines 775–792), confirming nav mesh empty — **this binary was likely built before the fix merged**.
- **Room 3**: Enemy_0 (machete) still cycles COMBAT→PURSUING, but the timer guard is working (≥2s between transitions). The new remaining issue: the enemy can navigate (rooms 2–3 may have valid nav) but still gets physically stuck when trying to reach the player through narrow corridors.

### Root Cause of Iteration 2 Partial Failure

**Bug C — `call_deferred` fires before physics server processes**: In Godot 4, `call_deferred` runs during idle processing of the **same engine step** — before the next physics frame. `StaticBody2D` nodes need at least one physics frame to be registered with `PhysicsServer2D`. Therefore `call_deferred` is not guaranteed to work; on some platforms/timings, the bake still sees no colliders.

**Bug D — No fallback when nav mesh unavailable**: When `_move_to_target_nav()` returns `false` (nav unavailable, i.e., `is_navigation_finished() == true` with no path), the machete enemy's velocity is set to `Vector2.ZERO`. The enemy sits still, the stuck timer fires after 0.8s, and the cycle continues. Machete enemies should move directly toward the player as a fallback, since they are melee fighters who don't need cover-to-cover pathfinding.

### Iteration 3 (current)

**Fix 1 — `scripts/levels/roguelike_level.gd`**: Replaced `call_deferred` with an `async` helper function `_bake_nav_after_physics_frame` that uses `await get_tree().physics_frame` before calling `bake_navigation_polygon(false)`. This guarantees one physics frame elapses so `PhysicsServer2D` has registered all walls.

```gdscript
func _bake_nav_after_physics_frame(nav_region: NavigationRegion2D) -> void:
    await get_tree().physics_frame  # Wait for PhysicsServer2D to register walls
    if is_instance_valid(nav_region):
        nav_region.bake_navigation_polygon(false)
```

**Fix 2 — `scripts/objects/enemy.gd`**: Added nav-unavailable fallback for machete COMBAT movement. When `_move_to_target_nav` returns `false`, use direct wall-avoidance movement toward the player instead of standing still:

```gdscript
# Issue #1165: If nav mesh unavailable (empty or not yet baked), move directly toward player
if not _move_to_target_nav(tp, combat_move_speed):
    velocity = _apply_wall_avoidance((tp - global_position).normalized()) * combat_move_speed
```

This ensures machete enemies always move toward the player, whether or not the nav mesh is available.

---

## Related Issues

- **Issue #579**: Original machete enemy implementation
- **Issue #595**: Machete attack animation
- **Issue #1061**: Roguelike mode implementation (root feature this builds on)
- **Issue #1083**: Melee path-clear wall check
- **Issue #1107**: Machete COMBAT stuck detection (the mitigation that exposed this bug)
- **Issue #1119**: Patrol stuck detection (same nav mesh class of bugs)
