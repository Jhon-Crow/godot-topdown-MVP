# Case Study: AI Performance Optimization — Issue #1184

## Problem Statement

**Issue:** When all enemies on the map enter the SEARCHING state simultaneously, FPS drops to 1–5 frames.

**Reported by:** Jhon-Crow
**Original report:** "сейчас если все враги на карте войдут в состояние поиска fps падает до 1-5 кадров"
(*"currently if all enemies on the map enter the search state, fps drops to 1-5 frames"*)

---

## Root Cause Analysis

After thorough code analysis of `scripts/objects/enemy.gd`, several performance bottlenecks were identified that compound when all enemies simultaneously enter SEARCHING state.

### Bottleneck 1: `get_nodes_in_group("enemies")` Called Every Physics Frame Per Enemy

**Location:** `_count_enemies_in_combat()` (line 3086–3110), called every frame via `_update_goap_state()` (line 882).

```gdscript
func _count_enemies_in_combat() -> int:
    var enemies := get_tree().get_nodes_in_group("enemies")  # ← allocates new array every frame
    for enemy in enemies:
        ...
```

**Cost analysis:**
- `get_nodes_in_group()` allocates a **new Array** on every call.
- If 10 enemies each call this every physics frame (60fps), that is **600 array allocations/second** just for this function.
- With 20 enemies: **1200 allocations/second**, plus O(N²) iteration (each enemy iterates all others).
- **Complexity: O(N²) per frame** — quadratic scaling with enemy count.

**Same issue also occurs in:**
- `_share_intel_with_nearby_enemies()` (line 3740): called every 0.5s per enemy — less severe but still allocates.
- `_notify_nearby_enemies_of_ally_death()` (line 4344): event-driven, not per-frame.

### Bottleneck 2: GOAP World State Update Every Frame (Including Expensive Calls)

**Location:** `_update_goap_state()` (line 868), called every physics frame.

```gdscript
_goap_world_state["enemies_in_combat"] = _count_enemies_in_combat()  # O(N²) per frame
_goap_world_state["player_distracted"] = _is_player_distracted()     # trig calc + viewport query
```

The `enemies_in_combat` value is queried every frame for every enemy, but:
- The value **doesn't change rapidly** — combat state transitions happen rarely relative to frame rate.
- It's only used for GOAP action selection, which doesn't need per-frame accuracy.

### Bottleneck 3: NavigationServer2D Waypoint Validation in `_generate_search_waypoints()`

**Location:** `_generate_search_waypoints()` (line 2251–2279).

```gdscript
while waypoints_generated < 20 and ... and iters < 100:
    var next_pos := current_pos + offset
    if _is_waypoint_navigable(next_pos) and not _is_zone_visited(next_pos):  # ← NavServer query per waypoint
```

```gdscript
func _is_waypoint_navigable(pos: Vector2) -> bool:
    var nav_map := get_world_2d().navigation_map    # ← RID lookup every call
    var closest := NavigationServer2D.map_get_closest_point(nav_map, pos)  # ← NavServer synchronous query
    return pos.distance_to(closest) < 50.0
```

When waypoints are exhausted (radius expanded), `_generate_search_waypoints()` is called again — up to 100 iterations each, each doing a synchronous `NavigationServer2D.map_get_closest_point()` call.

With 20 enemies all expanding their search simultaneously, this creates a burst of up to **2000 synchronous NavServer queries in a single frame**, completely saturating the navigation server.

### Bottleneck 4: `_get_zone_key()` String Formatting on Every Waypoint Check

**Location:** `_get_zone_key()` (line 2288–2289), called on every zone check.

```gdscript
func _get_zone_key(pos: Vector2) -> String:
    return "%d,%d" % [int(pos.x / SEARCH_ZONE_SNAP_SIZE) * int(SEARCH_ZONE_SNAP_SIZE), ...]
```

String formatting is expensive in GDScript. This is called:
- In `_is_zone_visited()` → called in `_generate_search_waypoints()` up to 100 times per call
- In `_mark_zone_visited()` → called when reaching each waypoint

**Fix:** Use integer tuple as key or a single 64-bit int key instead of string formatting.

### Bottleneck 5: Intel Sharing Uses `get_nodes_in_group()` Every 0.5s

**Location:** `_share_intel_with_nearby_enemies()` (line 3736–3764).

```gdscript
var enemies := get_tree().get_nodes_in_group("enemies")  # ← array allocation every 0.5s
for node in enemies:
    ...
    var distance := global_position.distance_to(other_enemy.global_position)  # ← O(N) distance checks
    if distance <= INTEL_SHARE_RANGE_LOS:
        can_share = _has_line_of_sight_to_position(...)  # ← raycast per enemy
```

With 20 enemies all doing this every 0.5s, that's 40 group array allocations/second plus O(N²) distance checks plus up to N² raycasts.

---

## Quantified Impact

| Bottleneck | Severity (20 enemies in SEARCH) | Per-frame cost |
|---|---|---|
| `_count_enemies_in_combat()` via `get_nodes_in_group()` | Critical — O(N²) | ~400 iterations + 20 array allocs |
| NavServer waypoint validation burst | Critical — up to 2000 sync queries | Occurs on radius expansion |
| GOAP world state update (full, every frame) | High | 20× per frame |
| Zone key string formatting | Medium | Up to 2000 string format ops per expansion |
| Intel sharing with raycasts | Medium | 20 allocs/s + O(N²) raycasts |

---

## Comparison with Existing Optimizations

The codebase already has some good optimizations:

| Optimization | Issue | What it does |
|---|---|---|
| Vision raycast staggering | #883 | Each enemy only raycasts every 6 frames, with frame offset per enemy |
| Cover search cooldown | #969 | 0.3s throttle between cover searches |
| Vision caching | — | Caches LOS check result per frame |

These show the right direction — **the same technique (throttling/staggering) should be applied to the remaining bottlenecks**.

---

## Proposed Solutions

### Solution 1: Cache Enemy Group List and Throttle `_count_enemies_in_combat()`

**Approach:** Cache the result of `get_nodes_in_group("enemies")` at the scene level or per enemy, and throttle `_count_enemies_in_combat()` to update at most every 0.5–1.0 seconds.

```gdscript
# Add these variables:
var _cached_combat_count: int = 0
var _combat_count_timer: float = 0.0
const COMBAT_COUNT_INTERVAL: float = 0.5

# Replace _count_enemies_in_combat() call in _update_goap_state():
_combat_count_timer += delta  # pass delta through or use get_physics_process_delta_time()
if _combat_count_timer >= COMBAT_COUNT_INTERVAL:
    _combat_count_timer = 0.0
    _cached_combat_count = _count_enemies_in_combat_internal()
_goap_world_state["enemies_in_combat"] = _cached_combat_count
```

**Impact:** Reduces O(N²) per-frame work to O(N²) per 0.5s — a **30× reduction** at 60fps.

**Reference:** This is the same pattern as `COVER_SEARCH_COOLDOWN` (Issue #969) and `INTEL_SHARE_INTERVAL` (line 316) already in the codebase.

### Solution 2: Stagger `_update_goap_state()` / `_count_enemies_in_combat()` Per Enemy

**Approach:** Apply the same frame-stagger technique used for vision checks (Issue #883) to the GOAP world state update. Each enemy uses a different frame offset so expensive calculations don't all run in the same physics frame.

```gdscript
const GOAP_UPDATE_INTERVAL: int = 6  # Update GOAP every 6 frames
var _goap_frame_counter: int = 0
var _goap_frame_offset: int = 0

# In _ready():
_goap_frame_offset = get_instance_id() % GOAP_UPDATE_INTERVAL

# In _physics_process():
_goap_frame_counter += 1
if (_goap_frame_counter % GOAP_UPDATE_INTERVAL) == _goap_frame_offset:
    _count_enemies_in_combat_full_update()
```

**Reference:** Same pattern as `VISION_CHECK_INTERVAL` (line 292–294, Issue #883).

### Solution 3: Use Integer Key for Zone Lookup (Replace String Formatting)

**Approach:** Replace string-based zone keys with a single 64-bit integer key:

```gdscript
func _get_zone_key(pos: Vector2) -> int:
    var gx: int = int(pos.x / SEARCH_ZONE_SNAP_SIZE)
    var gy: int = int(pos.y / SEARCH_ZONE_SNAP_SIZE)
    return gx * 100000 + gy  # Encodes both coordinates in one int
```

This eliminates string allocation and formatting — integer dictionary lookups are significantly faster in GDScript.

**Reference:** Game AI Pro, "Programming Game AI by Example" — recommends spatial grid representations using integer keys for performance.

### Solution 4: Cache Navigation Map RID in `_is_waypoint_navigable()`

**Approach:** Cache the `nav_map` RID at initialization instead of querying `get_world_2d().navigation_map` on every call:

```gdscript
var _nav_map_rid: RID  # cached in _ready()

# In _ready():
_nav_map_rid = get_world_2d().navigation_map

func _is_waypoint_navigable(pos: Vector2) -> bool:
    var closest := NavigationServer2D.map_get_closest_point(_nav_map_rid, pos)
    return pos.distance_to(closest) < 50.0
```

This avoids a property lookup and potential hash table access on every iteration of the waypoint generation loop.

### Solution 5: Throttle Intel Sharing Per Enemy with Staggered Offsets

**Approach:** Apply the same stagger technique to `_intel_share_timer` so not all enemies share intel simultaneously:

```gdscript
# In _ready():
_intel_share_timer = randf() * INTEL_SHARE_INTERVAL  # randomize start time
```

This is a one-line change that distributes the intel-sharing raycast load across multiple frames.

---

## Selected Implementation

The implementation addresses all five bottlenecks in priority order:

1. **Throttle `_count_enemies_in_combat()`** with a dedicated timer (Solution 1) — addresses the most severe O(N²) bottleneck.
2. **Stagger GOAP frame offsets** for enemies (Solution 2) — same pattern as vision staggering.
3. **Integer zone key** (Solution 3) — eliminates string allocation hot path.
4. **Cache nav map RID** (Solution 4) — reduces property lookup overhead.
5. **Stagger intel share timer** (Solution 5) — one-line fix for distributed load.

---

## External References

### Godot Documentation
- [Optimizing Navigation Performance — Godot Engine Docs](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html)
- [Groups — Godot Engine Documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/groups.html)
- [NavigationServer2D API Reference](https://docs.godotengine.org/en/stable/classes/class_navigationserver2d.html)
- [Navigation Server for Godot 4.0](https://godotengine.org/article/navigation-server-godot-4-0/)

### Game AI Optimization Theory
- [Time Slicing — Ming-Lun "Allen" Chou (2021)](https://allenchou.net/2021/05/time-slicing/) — Core concept for staggering AI updates across frames
- [Timeslicing Batched Algorithms — Allen Chou (2017)](https://allenchou.net/2017/03/timeslicing-batched-algorithms-across-multiple-frames/)
- [Squeeze These Last Milliseconds With CPU Time Slicing — GameDev.net](https://www.gamedev.net/tutorials/programming/general-and-gameplay-programming/squeeze-these-last-milliseconds-with-cpu-time-slicing-r5337/)
- [GameAIPro2 Chapter 13: Optimizing Practical Planning for Game AI (PDF)](https://www.gameaipro.com/GameAIPro2/GameAIPro2_Chapter13_Optimizing_Practical_Planning_for_Game_AI.pdf) — GOAP optimization techniques
- [Building the AI of F.E.A.R. with GOAP — Game Developer](https://www.gamedeveloper.com/design/building-the-ai-of-f-e-a-r-with-goal-oriented-action-planning) — Low replanning frequency principle
- [Programming Game AI by Example — O'Reilly](https://www.oreilly.com/library/view/programming-game-ai/9781556220784/) — Integer keys for spatial partitioning
- [Multi-Agent GOAP Performance Study 2025 (DIVA-portal)](https://www.diva-portal.org/smash/record.jsf?pid=diva2%3A1972169&dswid=-9889) — Linear scaling analysis

### Related Proposals and Issues
- [Godot Proposals: Add `get_node_count_in_group()` — Issue #7080](https://github.com/godotengine/godot-proposals/issues/7080)
- [Navigation Roadmap Issue #73566](https://github.com/godotengine/godot/issues/73566)

---

## Follow-Up Analysis: game_log_20260320_084817.txt (2026-03-20)

### New Issues Reported

After PR #1185 was drafted, the owner reported two new issues:
1. "Enemies start shooting randomly (where player isn't)"
2. "FPS not above 30 even when enemies are in IDLE"

### Log Analysis Summary

**Timeline (from game_log_20260320_084817.txt):**

| Time | Event | FPS |
|---|---|---|
| 08:48:17 | 5 enemies spawn, game starts | ~60fps |
| 08:48:19 | Shader warmup spike | 1fps (1-frame) |
| 08:48:22 | Level loads with 10 enemies | ~60fps |
| 08:48:28–08:49:07 | Player in combat with enemies | 10–29fps |
| 08:49:07–08:49:31 | Enemies back in IDLE | **60fps** ✅ |
| 08:49:20–08:49:25 | User toggles PerformanceSettings AI states | — |
| 08:50:00 | Player shoots → Enemy4 receives intel (conf=0.7) | — |
| 08:50:00–08:50:15 | Enemy4 loops IDLE→PURSUING→IDLE (360×/minute) | FPS drops |
| 08:50:15 | PURSUING re-enabled | Normal behavior resumes |

### Root Cause 1: Random Shooting (Muzzle Flash Detection)

The user had **`Invincibility: true`** and the invisible player feature. Enemy muzzle flash detection (Issue #910) was triggering:
- Enemy detected player's muzzle flash at position (441.7, 595.3)
- Fired suppressive shot toward that position
- Player had moved — looks like "random shooting to nowhere"

This is **correct expected behavior** for suppressive fire against invisible players. Not a regression.

### Root Cause 2: IDLE→PURSUING→IDLE State Loop (Regression)

**Critical bug introduced in commit `1231eceb`** (compact enemy.gd to 5000 lines):

The original 3-line spawn initialization was accidentally changed:

```gdscript
# BEFORE (main branch - correct):
if initial_state == AIState.SEARCHING: _has_left_idle = true; _transition_to_searching(global_position)
elif initial_state != AIState.IDLE: _current_state = initial_state
else: _transition_to_idle()  # Issue #1202: honor IDLE disable at spawn

# AFTER (PR #1185 - regression):
if initial_state != AIState.IDLE: _current_state = initial_state  # merged if/elif, lost else branch
if initial_state == AIState.SEARCHING: _has_left_idle = true; _transition_to_searching(global_position)
# else: _transition_to_idle() was MISSING
```

**Effect of missing `else: _transition_to_idle()`:**
1. `_transition_to_idle()` is never called on spawn → `_hits_taken_in_encounter`, `_idle_scan_timer`, etc. not reset
2. PerformanceSettings IDLE check at spawn is skipped (Issue #1202 regression)

### Root Cause 3: IDLE→PURSUING Loop When State Disabled

When PURSUING is disabled in PerformanceSettings:
- `_process_idle_state()` sees medium/high confidence in memory → calls `_transition_to_pursuing()`
- `_transition_to_pursuing()` checks: PURSUING disabled → calls `_transition_to_idle()` immediately
- `_transition_to_idle()` resets `_idle_scan_timer = 0.0`
- Next frame: same memory confidence → loop repeats → **360+ state transitions/second** observed

This explains both the "random shooting" (loop caused state thrashing, enemies entered COMBAT briefly) and "30fps in IDLE" (the loop has significant CPU overhead even in IDLE state).

### Fixes Applied

**Fix 1** (in `_initialize_components()`): Restore the `else: _transition_to_idle()` call at spawn, restoring Issue #1202 behavior and proper IDLE initialization.

**Fix 2** (in `_process_idle_state()`): Guard memory-based PURSUING transition with PerformanceSettings check. If PURSUING is disabled, skip the transition (stay in IDLE patrol) instead of creating a loop.

```gdscript
# Before (loops when PURSUING disabled):
if _memory and _memory.has_target():
    if _memory.is_high_confidence(): _transition_to_pursuing(); return

# After (safe when PURSUING disabled):
var _ps_idle := get_node_or_null("/root/PerformanceSettings"); var _pursuing_enabled := _ps_idle == null or _ps_idle.is_ai_state_pursuing_enabled()
if _memory and _memory.has_target() and _pursuing_enabled:
    if _memory.is_high_confidence(): _transition_to_pursuing(); return
```

---

## Follow-Up Analysis: game_log_20260320_092301.txt (2026-03-20)

### New Issue Reported

After applying the fixes for the IDLE→PURSUING loop, the owner reported:
- "ии полностью сломан" = "AI is completely broken"

### Log Analysis Summary

**Session duration: 4 seconds (09:23:01 → 09:23:05)**

| Field | Value |
|---|---|
| Level | LabyrinthLevel |
| Enemies | 5 (Enemy1–Enemy5) |
| PerformanceSettings | `ai: true` (all main toggles enabled) |
| Invincibility | OFF at start, turned ON at 09:23:03 |
| Enemy AI logs | **NONE** |
| Enemy tracking | `has_died_signal=false` for all enemies, 0 registered |

**Comparison with working log_082422:**

| Metric | log_082422 (working) | log_092301 (reported broken) |
|---|---|---|
| `has_died_signal` | `true` for all enemies | `false` for all enemies |
| Enemy AI messages | Present (`[ENEMY]` prefix) | Absent |
| Session duration | ~20 seconds | 4 seconds |
| Build commit | `686e194c` | `7a3b647a` |

### Root Cause Analysis

**Missing diagnostic data**: The 4-second session contains insufficient game data to determine whether AI is actually broken. No player–enemy interaction occurred during the session (player spawned, turned on invincibility, game closed). GUARD enemies stand still until seeing/hearing the player — this is expected behavior.

**`has_died_signal=false` anomaly**: The `died` signal is defined at class level in `enemy.gd` (line 96) and should always be present. Possible causes:
1. **FileLogger race condition**: `_log_to_file()` in `_init_death_animation()` calls `get_node_or_null("/root/FileLogger")` — if FileLogger isn't available when enemy `_ready()` runs, the log doesn't appear (but AI still works)
2. **Different build timing**: In Godot 4, node initialization order can vary by scene structure — LabyrinthLevel's `_setup_enemy_tracking()` may have run before enemy scripts completed `_ready()` in this build configuration
3. **Per-state AI toggle values**: The log only shows `ai: true` for the main toggle; individual state toggles (idle, combat, pursuing, etc.) are not logged at startup — their values are unknown for this session

**Note**: All individual AI state toggles were re-enabled at the end of session log_084817 (08:50:12–08:50:16), so the saved config should have them all `true`. However, if the game was closed abnormally between the "IDLE disabled" event (08:49:20) and "IDLE enabled" event (08:49:22), the config file could still have `ai_state_idle_enabled = false`.

### Improvements Applied (commit following `7a3b647a`)

**Improvement 1** (`performance_settings.gd`): Log ALL per-state AI toggle values at startup:
```
[PerformanceSettings] AI state toggles - idle: true, combat: true, ... pursuing: true, ...
```
This will immediately reveal if any per-state toggle is unexpectedly disabled.

**Improvement 2** (`enemy.gd`): Add deferred `_log_ready_complete()` call at end of `_ready()`:
```
[ENEMY] [Enemy1] _ready() complete — state: IDLE, player: true
```
This confirms `_ready()` completed successfully and shows the initial AI state and whether the player was found.

### Recommended Testing Protocol

To get actionable data on the "AI broken" complaint, a longer test session is needed:
1. Start the game on any level with enemies
2. Walk toward an enemy — do they react?
3. Fire a weapon — do nearby enemies respond?
4. Note: GUARD enemies (standing at a post) do NOT patrol; they scan and wait. This is expected behavior.
5. Collect a game log of at least 30 seconds of interaction
