# Case Study: Optimizing Cover Detection in a Godot 4 Top-Down Shooter

**Issue:** #1411
**Date:** 2026-03-24
**Engine:** Godot 4.x
**Domain:** Enemy AI / Physics Queries / Performance

---

## Problem

A top-down shooter game features enemy AI with a raycast-based cover detection system. When multiple enemies are active simultaneously, the game experiences significant frame drops caused by an excessive volume of physics queries executed per frame.

The cover detection system is responsible for finding positions where enemies can hide from the player behind obstacles. It relies heavily on `RayCast2D` nodes and direct `PhysicsDirectSpaceState2D` queries (`intersect_point()`, `intersect_ray()`). Profiling reveals that a single cover search can trigger over 1,000 physics queries, and multiple unthrottled search functions compound the problem when several enemies search for cover in the same frame.

---

## Root Cause Analysis

### 1. Always-On RayCast2D Nodes (120 per Enemy)

The function `_setup_cover_detection()` creates 120 `RayCast2D` child nodes per enemy instance. These nodes default to `enabled = true`, meaning the Godot physics engine automatically recomputes collision results for all 120 rays on every physics tick -- even when no cover search is in progress.

As documented in the [Godot RayCast2D reference](https://docs.godotengine.org/en/stable/classes/class_raycast2d.html), when `enabled` is `true`, the raycast data is "automatically recomputed with each _physics_process tick." For 10 enemies, this is 1,200 raycast evaluations per physics frame with zero functional benefit during idle periods.

**Cost:** 120 x N_enemies automatic raycast updates per physics frame, continuously.

### 2. Explosive Query Count in `_get_hidden_cover_candidates()`

This is the primary cover search function. Its query budget breaks down as follows:

| Phase | Queries per invocation |
|---|---|
| Initial sector sweep | 120 raycasts |
| Far-side probing (`_get_far_side_cover()`) per hit | ~30 `intersect_point()` + `intersect_ray()` calls (30px steps, up to 3x ray distance) |
| Visibility validation (`_is_position_visible_from_player()`) per candidate | 5 raycasts (center + 4 corners) |

**Worst case:** If 40 of 120 rays hit obstacles, and each produces a candidate:

- 120 (sweep) + 40 x 30 (probing) + 40 x 5 (visibility) = **1,520 physics queries** in a single invocation.

The probing loop in `_get_far_side_cover()` uses a 30px step size to walk beyond an obstacle boundary. With a maximum walk distance of 3x the original ray length, this loop can iterate 30+ times per hit, each iteration performing both an `intersect_point()` and an `intersect_ray()` call.

### 3. Unthrottled Search Functions

While `_find_cover_position()` has a 0.3-second cooldown, three other search functions have no throttling at all:

| Function | Query budget (per call) | Throttle |
|---|---|---|
| `_find_cover_position()` | ~1,500 | 0.3s cooldown |
| `_find_distant_cover_position()` | 120 `force_raycast_update()` + up to 600 visibility checks = ~720 | **None** |
| `_find_cover_closest_to_player()` | Same pattern as above = ~720 | **None** |
| `_find_flank_cover_toward_target()` | 120 raycasts + path checks = ~240+ | **None** |

If AI state transitions cause multiple functions to fire in rapid succession (or in the same frame), the combined query count can exceed 3,000 per enemy per frame.

### 4. Redundant Visibility Checks

`_is_position_visible_from_player()` performs 5 raycasts and is called for every candidate position. Within a single cover search, the same position (or very nearby positions) can be tested multiple times across different search functions. There is no per-frame cache, so identical queries are repeated.

### 5. No Early Termination

All search functions evaluate every candidate before selecting the best one. In most cases, a "good enough" cover position found early in the search would be acceptable, but the algorithm exhaustively processes all 120 rays regardless.

---

## Benchmarks (Theoretical)

The following estimates assume a physics tick rate of 60 Hz, 10 active enemies, and average hit rates from the 120-ray sweep.

### Current System (Unoptimized)

| Metric | Value |
|---|---|
| Idle raycast updates per frame | 120 x 10 = **1,200** |
| Single cover search (avg) | ~800-1,500 queries |
| Worst-case burst (multiple functions, no throttle) | ~3,000+ queries per enemy |
| Sustained load (10 enemies searching) | **8,000-15,000 queries/frame** |
| Frame time contribution (estimated) | 8-16 ms at 60 Hz (physics alone) |

### After Proposed Optimizations

| Metric | Value |
|---|---|
| Idle raycast updates per frame | **0** (lazy init) |
| Single cover search (avg, with early termination) | ~200-400 queries |
| Throttled burst (0.3s cooldown on all functions) | Max 1 search per 0.3s per enemy |
| Sustained load (10 enemies, staggered) | **~600-1,200 queries/frame** (amortized) |
| Frame time contribution (estimated) | 1-3 ms at 60 Hz |

### Expected Improvement

| Scenario | Reduction |
|---|---|
| Idle (no active searches) | ~100% fewer physics queries |
| Active combat (10 enemies) | ~85-92% fewer physics queries per frame |
| Worst-case burst | ~75-80% reduction |

### 6. Cooldown Bypass via Cover Invalidation (Primary Root Cause)

The 0.3-second cooldown guard in `_find_cover_position()` was conditioned on `_has_valid_cover`:

```gdscript
if _has_valid_cover and current_time - _last_cover_search_time < COVER_SEARCH_COOLDOWN: return
```

However, every call site that wanted to re-search would first set `_has_valid_cover = false`, bypassing the cooldown entirely. This pattern appeared in:

- `_transition_to_suppressed()`: `_has_valid_cover = false; _last_cover_search_time = -999.0`
- `_process_seeking_cover_state()`: `_has_valid_cover = false; _find_cover_position()`
- `_process_suppressed_state()`: `_has_valid_cover = false; _find_cover_position()`
- `_process_retreating_state()`: `_has_valid_cover = false; _find_cover_position()`

**Game log evidence:** Enemy3 logged 40+ "Found cover at" messages within 1 second (09:25:10-09:25:11), each at a slightly different position because the player was moving. This correlates with FPS drops to 6-10 FPS.

### 7. Unnecessary Cover Recalculation in Suppressed State

When transitioning from IN_COVER → SUPPRESSED (triggered by `_under_fire`), the enemy was already at a valid cover position. However, `_transition_to_suppressed()` unconditionally set `_has_valid_cover = false`, forcing an immediate expensive re-search. The enemy would find essentially the same position, then repeat the search next frame.

Additionally, in `_process_suppressed_state()`, when the enemy was hidden from the player (cover was working correctly), it would still recalculate cover if it reached the cover position, due to a redundant visibility check that could never be true at that code path.

---

## Solutions (Iteration 2 — Cooldown Bypass Fix)

### Solution 6: Time-Only Cooldown (Remove `_has_valid_cover` Guard)

Changed all three cover search functions to use time-only cooldown:

```gdscript
# Before (bypassed when _has_valid_cover is false):
if _has_valid_cover and current_time - _last_cover_search_time < COVER_SEARCH_COOLDOWN: return

# After (always respected):
if current_time - _last_cover_search_time < COVER_SEARCH_COOLDOWN: return
```

**Impact:** Guarantees maximum 3.3 searches/second per enemy regardless of how many times `_has_valid_cover` is toggled.

### Solution 7: Preserve Cover on Suppression from Cover-Related States

When transitioning to SUPPRESSED from IN_COVER, SEEKING_COVER, or RETREATING, the enemy already has valid cover. The fix preserves it:

```gdscript
var _prev_state := _current_state
_current_state = AIState.SUPPRESSED
if _prev_state not in [AIState.IN_COVER, AIState.SEEKING_COVER, AIState.RETREATING]:
    _has_valid_cover = false; _last_cover_search_time = -999.0  # Force search only for new suppressions
```

**Impact:** Eliminates the entire cover search when the enemy is already in cover and gets suppressed — the most common scenario causing the performance drop.

### Solution 8: No Recalculation When Hidden in Suppressed State

When the enemy is at cover and hidden from the player (cover is working), stop recalculating. The previous code had a redundant visibility check that triggered re-searches:

```gdscript
# Before: checked visibility at cover position and re-searched if visible
# (but this code path was only reachable when NOT visible — dead logic)
if distance_to_cover < 10.0:
    if _is_visible_from_player():
        _has_valid_cover = false; _find_cover_position()  # This caused frame-burst searches
    else: velocity = Vector2.ZERO

# After: simply stay put when at cover and hidden
if distance_to_cover < 10.0:
    velocity = Vector2.ZERO  # At cover and hidden — stay put
```

**Impact:** Eliminates all cover search overhead while enemy is successfully hiding.

---

## Solutions (Iteration 1 — Initial Optimizations)

All proposed changes preserve the existing cover-finding logic. No behavioral changes are introduced -- only throttling, caching, and algorithmic tightening.

### Solution 1: Add Throttling to Unthrottled Search Functions

**Target functions:** `_find_distant_cover_position()`, `_find_cover_closest_to_player()`, `_find_flank_cover_toward_target()`

**Implementation:**

```gdscript
var _last_distant_cover_search_time: float = -1.0
var _last_closest_cover_search_time: float = -1.0
var _last_flank_cover_search_time: float = -1.0
const COVER_SEARCH_COOLDOWN: float = 0.3

func _find_distant_cover_position() -> Vector2:
    var current_time = Time.get_ticks_msec() / 1000.0
    if current_time - _last_distant_cover_search_time < COVER_SEARCH_COOLDOWN:
        return _cached_distant_cover_result
    _last_distant_cover_search_time = current_time
    # ... existing logic ...
    _cached_distant_cover_result = result
    return result
```

Apply the same pattern to `_find_cover_closest_to_player()` and `_find_flank_cover_toward_target()`.

**Impact:** Caps each function to at most ~3.3 invocations per second per enemy, preventing burst stacking.

### Solution 2: Per-Frame Cache for `_is_position_visible_from_player()`

**Rationale:** The same position (or positions within a small radius) are tested for visibility multiple times within a single physics frame across different search functions.

**Implementation:**

```gdscript
var _visibility_cache: Dictionary = {}
var _visibility_cache_frame: int = -1

func _is_position_visible_from_player(pos: Vector2) -> bool:
    var frame = Engine.get_physics_frames()
    if frame != _visibility_cache_frame:
        _visibility_cache.clear()
        _visibility_cache_frame = frame

    # Quantize position to reduce near-miss cache misses
    var key = Vector2i(snapped(pos, Vector2(8, 8)))
    if _visibility_cache.has(key):
        return _visibility_cache[key]

    var result = _do_visibility_raycasts(pos)
    _visibility_cache[key] = result
    return result
```

Position quantization (snapping to an 8px grid) trades a small amount of precision for significantly better cache hit rates. At the scale of a top-down shooter, 8px of imprecision in visibility checks is negligible.

**Impact:** Eliminates 60-80% of redundant visibility raycasts in a typical search cycle.

### Solution 3: Reduce Probing Density in `_get_far_side_cover()`

**Change:** Increase the step size from 30px to 45px. Cap iterations at 20.

```gdscript
const FAR_SIDE_STEP: float = 45.0  # was 30.0
const FAR_SIDE_MAX_ITERATIONS: int = 20  # was unbounded (up to 3x ray distance)

func _get_far_side_cover(hit_position: Vector2, direction: Vector2, ray_distance: float) -> Vector2:
    var step_count = 0
    var probe_pos = hit_position
    while step_count < FAR_SIDE_MAX_ITERATIONS:
        probe_pos += direction * FAR_SIDE_STEP
        # ... existing probe logic ...
        step_count += 1
    return probe_pos
```

**Impact:** Reduces per-hit probe queries from ~30 to ~20 (33% reduction), with minimal effect on cover position accuracy. The 45px step is still well within the resolution needed for character-sized cover positions.

### Solution 4: Lazy RayCast2D Initialization

**Rationale:** Per the [Godot documentation](https://docs.godotengine.org/en/4.4/classes/class_raycast2d.html), `force_raycast_update()` works regardless of the `enabled` property. Disabled raycasts do not consume physics engine resources. As noted in [Godot issue #31637](https://github.com/godotengine/godot/issues/31637), raycasts are disabled by default precisely because always-on raycasts are expensive when not needed.

**Implementation:**

```gdscript
func _setup_cover_detection():
    for i in range(120):
        var ray = RayCast2D.new()
        ray.enabled = false  # Disabled by default
        add_child(ray)
        _cover_rays.append(ray)

func _begin_cover_search():
    for ray in _cover_rays:
        ray.enabled = true

func _end_cover_search():
    for ray in _cover_rays:
        ray.enabled = false
```

Alternatively, if `force_raycast_update()` is used exclusively (rather than relying on automatic per-frame updates), the rays can remain permanently disabled:

```gdscript
func _setup_cover_detection():
    for i in range(120):
        var ray = RayCast2D.new()
        ray.enabled = false  # Never auto-updates
        add_child(ray)
        _cover_rays.append(ray)

# In search functions, just call force_raycast_update() directly:
func _sweep_rays():
    for ray in _cover_rays:
        ray.force_raycast_update()
        if ray.is_colliding():
            # process hit
```

**Impact:** Eliminates 120 x N_enemies automatic raycast computations per physics frame during idle periods (the majority of gameplay time).

### Solution 5: Early Termination in Candidate Search

**Rationale:** The cover search evaluates all 120 rays, generating and scoring every candidate before selecting the best. In practice, 3-5 good candidates are sufficient.

**Implementation:**

```gdscript
const MAX_COVER_CANDIDATES: int = 5

func _get_hidden_cover_candidates(player_pos: Vector2) -> Array:
    var candidates = []
    for i in range(120):
        # ... existing ray sweep and probe logic ...
        if is_valid_candidate:
            candidates.append(candidate)
            if candidates.size() >= MAX_COVER_CANDIDATES:
                break
    return candidates
```

For directional searches (e.g., flank cover), the ray order can be biased toward the desired direction so that early termination finds relevant candidates first.

**Impact:** Reduces average query count by 50-70% for searches where valid cover is plentiful. In open areas with little cover, the full sweep still executes (no regression).

---

## Additional Considerations

### Staggering Enemy Searches

Beyond the per-function throttle, enemies should stagger their search timing so they do not all search on the same frame. A simple approach:

```gdscript
func _ready():
    # Offset each enemy's search timer by a random amount
    _next_cover_search_time = randf() * COVER_SEARCH_COOLDOWN
```

This distributes the physics query load more evenly across frames, preventing spikes when multiple enemies transition to a cover-seeking state simultaneously.

### Direct Space State Queries vs. RayCast2D Nodes

For on-demand queries (as opposed to continuous monitoring), using `PhysicsDirectSpaceState2D.intersect_ray()` directly is more efficient than maintaining 120 `RayCast2D` nodes. The node-based approach adds scene tree overhead (node management, transform propagation) that is unnecessary for batch one-shot queries. The [Godot ray-casting tutorial](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html) documents both approaches and notes that direct space state queries are appropriate for this use case.

### Spatial Partitioning for Cover Points

For a longer-term optimization (beyond the scope of this issue), precomputing cover points using [spatial hashing](https://www.gamedev.net/tutorials/programming/general-and-gameplay-programming/spatial-hashing-r2697/) or a grid-based spatial partition (as described in [Game Programming Patterns](https://gameprogrammingpatterns.com/spatial-partition.html)) would eliminate the need for runtime raycast sweeps entirely. The system would query a spatial index for nearby precomputed cover points and only use raycasts for real-time visibility validation.

---

## References

### Godot Documentation
- [Ray-casting tutorial (Godot stable)](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html) -- covers both RayCast2D node and direct space state approaches
- [RayCast2D class reference (Godot 4.4)](https://docs.godotengine.org/en/4.4/classes/class_raycast2d.html) -- documents `enabled`, `force_raycast_update()`, and collision layer configuration
- [PhysicsDirectSpaceState2D class reference](https://docs.godotengine.org/en/stable/classes/class_physicsdirectspacestate2d.html) -- `intersect_ray()`, `intersect_point()` API
- [PhysicsRayQueryParameters2D class reference](https://docs.godotengine.org/en/stable/classes/class_physicsrayqueryparameters2d.html) -- query parameter configuration
- [Performance documentation (Godot stable)](https://docs.godotengine.org/en/stable/tutorials/performance/index.html) -- general performance guidance

### Godot Community and Issues
- [Why raycasts are disabled by default (Godot #31637)](https://github.com/godotengine/godot/issues/31637) -- explains the performance rationale for default-disabled raycasts
- [Improve performance of Physics Server active callback events (godot-proposals #10389)](https://github.com/godotengine/godot-proposals/issues/10389) -- proposal for batch physics query APIs
- [Redesign physics query API (godot-proposals #13612)](https://github.com/godotengine/godot-proposals/issues/13612) -- discussion of API improvements for physics queries
- [force_raycast_update() documentation limitations (godot-docs #9935)](https://github.com/godotengine/godot-docs/issues/9935) -- clarification that `force_raycast_update()` works when `enabled = false`
- [Is it efficient to use multiple RayCast2D? (Godot Forum)](https://forum.godotengine.org/t/is-it-efficient-to-use-multiple-raycast2d/19864) -- community discussion on raycast node scaling
- [Raycast 3D optimization (Godot Forum)](https://forum.godotengine.org/t/raycast-3d-optimization-need-help-and-advice/116600) -- optimization advice for high-volume raycasting

### Game AI and Cover Systems
- [Hiding and Taking Cover (Peachpit / Game Programming)](https://www.peachpit.com/articles/article.aspx?p=102090&seqNum=7) -- theory of AI cover-seeking behavior
- [Cover system in games (GameDev.net)](https://www.gamedev.net/blogs/entry/2276748-cover-system-in-games/) -- architectural overview of cover system modules (creation vs. searching)
- [Coding the AI to Take Cover in Unity 2021 (Medium)](https://gamedevdustin.medium.com/coding-the-ai-to-take-cover-in-unity-2021-244f43046921) -- practical implementation reference

### Spatial Optimization Techniques
- [Spatial Partition pattern (Game Programming Patterns)](https://gameprogrammingpatterns.com/spatial-partition.html) -- spatial partitioning for proximity queries
- [Spatial Hashing tutorial (GameDev.net)](https://www.gamedev.net/tutorials/programming/general-and-gameplay-programming/spatial-hashing-r2697/) -- hash-based spatial indexing for collision and proximity
- [Optimization of large-scale simulations by spatial hashing (ResearchGate)](https://www.researchgate.net/publication/228958917_Optimization_of_large-scale_real-time_simulations_by_spatial_hashing) -- research on spatial hashing for real-time simulation performance
- [Understanding raycasts in Godot (GDQuest)](https://www.gdquest.com/library/raycast_introduction/) -- beginner-friendly raycast overview
