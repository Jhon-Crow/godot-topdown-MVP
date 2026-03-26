# Case Study: Issue #1520 — FPS Drop with Enemies in IDLE State

## Issue Summary

**Reporter:** Jhon-Crow
**Description (RU):** "Когда в performance включено только idle состояние врагов, FPS всё равно падает до 30 кадров" — "When only the idle state of enemies is enabled in performance settings, FPS still drops to 30 frames."
**Log file:** `game_log_20260326_065401.txt`
**Level tested:** BuildingLevel (20 enemies)
**Engine:** Godot 4.3-stable

---

## Evidence from Game Log

### Timeline of Events

| Time     | Event                                    | FPS     |
|----------|------------------------------------------|---------|
| 06:54:01 | Game starts (LabyrinthLevel, 5 enemies)  | nominal |
| 06:54:03 | First FPS drop                           | 12 fps  |
| 06:54:09 | User disables ALL AI states              | —       |
| 06:54:21 | FPS still dropping (all states disabled) | 20–29 fps |
| 06:54:39 | User re-enables all AI states            | —       |
| 06:54:50 | FPS drops harder (IDLE re-enabled)       | 5–17 fps |
| 06:55:11 | User disables ALL AI states again        | —       |
| 06:56:02 | User re-enables all AI states            | —       |

**Key observation:** Disabling all AI states via PerformanceSettings *still results in FPS drops of ~20 fps* with 20 enemies on screen. This proves the bottleneck is **not in the state-specific logic** (`_process_idle_state`, `_process_patrol`, `_process_guard`) but rather in the **per-frame overhead that runs unconditionally in `_physics_process` before the state switch**.

### Logging Flood Evidence

The log contains 30,734 lines for a ~2.5 minute session. The IDLE state generates a massive volume of `ROT_CHANGE` log entries — several per second *per enemy* — indicating the rotation-reason logging is itself a CPU cost that compounds with enemy count.

Sample density:
```
[06:56:12] [ENEMY] [LoadingDock_UZI] ROT_CHANGE: P3:corner -> P4:velocity, ...
[06:56:12] [ENEMY] [LoadingDock_Rifle1] ROT_CHANGE: P3:corner -> P4:velocity, ...
[06:56:12] [ENEMY] [ContainerYardB_Rifle] ROT_CHANGE: P4:velocity -> P3:corner, ...
[06:56:12] [ENEMY] [LoadingDock_Rifle1] ROT_CHANGE: P4:velocity -> P3:corner, ...
```

Multiple rotation priority changes per enemy per second × 20 enemies = hundreds of log writes/second.

---

## Root Cause Analysis

### RC1: `_count_enemies_in_combat()` — O(N) Group Query Every Frame Per Enemy = O(N²)

**Location:** `scripts/objects/enemy.gd:3186–3210` — called from `_update_goap_state()` at line `948`, which is called at line `886` unconditionally on every physics frame for every enemy.

```gdscript
func _count_enemies_in_combat() -> int:
    var enemies := get_tree().get_nodes_in_group("enemies")  # allocates Array every frame
    for enemy in enemies:                                      # iterates ALL enemies
        ...
```

**Cost:** With N=20 enemies, this runs 20 times/frame × iterating 20 enemies = **400 iterations/frame**. At 60 fps physics = **24,000 iterations/second**. Each call also allocates a new Array.

### RC2: `_apply_separation_force()` — O(N) Group Query Every Frame Per Enemy = O(N²)

**Location:** `scripts/objects/enemy.gd:4760–4769` — called unconditionally every physics frame for every alive enemy.

```gdscript
func _apply_separation_force(vel: Vector2, delta: float) -> Vector2:
    for body in get_tree().get_nodes_in_group("enemies"):  # allocates Array every frame
        ...
        var dist: float = diff.length()  # expensive length() called for every pair
```

**Cost:** Same O(N²) — 400 iterations/frame for N=20, 24,000/second at 60 fps physics. Worse: this is in addition to RC1.

**Combined RC1+RC2 cost:** With 20 enemies, these two alone produce **48,000 iterations/second** through enemy lists with Array allocations.

### RC3: `_can_hit_target_from_current_position()` Calls Raycast Every Frame in GOAP Update

**Location:** `scripts/objects/enemy.gd:947` — called in `_update_goap_state()` for every enemy every frame.

```gdscript
_goap_world_state["can_hit_from_cover"] = _can_hit_target_from_current_position()
```

And `_can_hit_target_from_current_position()` → `_is_shot_clear_of_cover()` → `space_state.intersect_ray()`.

**Cost:** 1 raycast per enemy per frame × 20 enemies × 60 fps = **1,200 raycasts/second** just for GOAP cover-shot checks. All wasted when the enemy is in IDLE with no player visible.

### RC4: `_check_player_visibility()` — Multi-Point Raycasts for IDLE Enemies Not Facing Player

**Location:** `scripts/objects/enemy.gd:3610–3653`

The code throttles with `VISION_CHECK_INTERVAL = 6` frames (approx 10 Hz) — good. But it still runs raycast checks for enemies in IDLE state. For a GUARD enemy not facing the player at all, the FOV check should short-circuit, but for PATROL enemies moving toward the player direction, multiple body-point raycasts still fire.

### RC5: Log File I/O — `_log_to_file()` Called on Every Rotation Priority Change

**Location:** `scripts/objects/enemy.gd:1004–1007`

```gdscript
if rotation_reason != _last_rotation_reason:
    _log_to_file("ROT_CHANGE: ...")
```

Patrol enemies change rotation priority frequently (P3:corner → P4:velocity → P3:corner every ~0.3s). With 20 enemies and logging enabled, this produces hundreds of `FileLogger.log_enemy()` calls per second. File I/O (even buffered) is expensive at this rate.

### RC6: `NavigationAgent2D` Pathfinding Even When Idle

**Location:** `_process_patrol()` and `_move_to_target_nav()` — patrol enemies call `_nav_agent.get_next_path_position()` every frame via `_move_to_target_nav()`.

NavigationAgent2D queries the NavigationServer asynchronously, but with 20 patrolling enemies all querying simultaneously, the NavigationServer accumulates many path queries. Even though patrolling doesn't involve expensive A* searches (the targets don't change), the per-frame API overhead adds up.

### RC7: `_update_memory()` and Intel Sharing — `get_nodes_in_group()` Every 0.5s Per Enemy

**Location:** `scripts/objects/enemy.gd:3698–3702`

```gdscript
_intel_share_timer += delta
if _intel_share_timer >= INTEL_SHARE_INTERVAL:  # 0.5s
    _share_intel_with_nearby_enemies()           # iterates all enemies
```

With 20 enemies sharing intel every 0.5s, this produces 40 group iterations/second. Minor individually, but cumulative.

---

## Why Disabling IDLE State in PerformanceSettings Does NOT Help

The `filter_ai_state()` function (line 208) redirects disabled states but the redirect for IDLE is `SEARCHING` — which is *more* expensive. More importantly:

**The per-frame overhead in `_physics_process` (lines 794–928) runs REGARDLESS of which AI state is active.** The state-machine dispatch at line 1381 is only a small fraction of the per-frame cost. The majority of CPU time is spent in:

- `_check_player_visibility()` (line 880) — raycasts
- `_update_memory()` (line 885) — with intel sharing
- `_update_goap_state()` (line 886) — including `_count_enemies_in_combat()` and `_can_hit_target_from_current_position()` raycasts
- `_apply_separation_force()` (line 924) — O(N²) group iteration

These all run before the state filter is even consulted.

---

## Existing Mitigations

| Mitigation | Where | Effect |
|------------|-------|--------|
| Vision staggering | `VISION_CHECK_INTERVAL=6` (#883) | Reduces vision raycasts to ~10 Hz |
| Cover search throttling | `COVER_SEARCH_COOLDOWN=0.3s` | Limits cover raycast floods |
| Intel sharing throttle | `INTEL_SHARE_INTERVAL=0.5s` | Limits enemy-list iterations to 2/sec |
| Debug draw throttle | `DEBUG_DRAW_INTERVAL=0.1s` (#1220) | Limits FOV cone redraws |
| Per-state GOAP flags (cached) | Most GOAP keys are boolean | Cheap dictionary lookups |

**Notable gap:** `_count_enemies_in_combat()` and `_apply_separation_force()` are **not throttled** and run O(N²) every frame.

---

## Solutions Considered

### Solution A: Throttle GOAP update in IDLE state (recommended — low risk)

When in IDLE state and not seeing the player, skip the expensive GOAP state update entirely or run it at a reduced frequency (e.g., every 10–20 frames). The GOAP fields `enemies_in_combat`, `can_hit_from_cover`, `player_close` are irrelevant when enemy is idle with no player contact.

**Implementation:** Add a `_goap_update_frame_counter` and skip `_update_goap_state()` when `_current_state == AIState.IDLE` and `not _can_see_player`, except every N frames.

### Solution B: Cache `_count_enemies_in_combat()` result (recommended — low risk)

Replace per-frame O(N²) group iteration with a cached value updated every 0.5s. Exact combat count doesn't need frame-perfect accuracy for assault trigger logic.

### Solution C: Skip `_apply_separation_force()` for GUARD enemies (recommended — low risk)

GUARD enemies stand still — they generate zero separation velocity. Skip the entire O(N) loop for `velocity == Vector2.ZERO` before the loop.

### Solution D: `set_physics_process(false)` for pure GUARD enemies (higher impact, higher risk)

Disable physics processing entirely for GUARD enemies not currently detecting threats, use a periodic Timer at 0.5–1.0 Hz to check for player. Re-enable on player detection. This is the most effective fix but requires careful state management to avoid missing detections.

### Solution E: LOD-based AI throttling by distance to player

Enemies far from the player (beyond a configurable radius, e.g., 1500 px) run at reduced physics tick rate. Implemented by skipping `_physics_process` every N frames using a per-enemy counter based on distance.

---

## Recommended Fix (Implemented)

**Primary fix:** Throttle `_update_goap_state()` in IDLE state (Solution A) + add early-exit in `_apply_separation_force()` for stationary enemies (Solution C) + throttle the GOAP `_count_enemies_in_combat()` call via a cached value (Solution B).

These three changes together eliminate the O(N²) per-frame cost for idle enemies while preserving all existing behavior.

See `fix_summary.md` for implementation details.

---

## References

- [Godot Docs: Optimizing Navigation Performance](https://docs.godotengine.org/en/latest/tutorials/navigation/navigation_optimizing_performance.html)
- [Godot Docs: CPU Optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)
- [Godot Docs: Idle and Physics Processing](https://docs.godotengine.org/en/stable/tutorials/scripting/idle_and_physics_processing.html)
- [Godot Forum: get_nodes_in_group performance](https://forum.godotengine.org/t/question-about-group-does-it-iterate-over-the-whole-tree/116906)
- [Golden Tamarin: Godot Performant Nav Agent](https://www.golden-tamarin.com/2024/10/10/godot-performant-nav-agent/)
- Original log: `game_log_20260326_065401.txt`
