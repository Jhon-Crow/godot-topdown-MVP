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
