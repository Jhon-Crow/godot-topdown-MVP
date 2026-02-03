# FPS Performance Analysis - Issue #407

## Issue Report

**User Report:** "сейчас постоянно очень низкий FPS в игре" (now constantly very low FPS in the game)

**Log Files Analyzed:**
- `game_log_20260203_115652.txt` (746 lines, 26 seconds gameplay)
- `game_log_20260203_115723.txt` (4416 lines, 78 seconds gameplay)

## Timeline of Events

| Time | Event | Puddles Count |
|------|-------|---------------|
| 11:57:23 | Game started | 1 (initial blood puddle at 640, 360) |
| 11:57:25 | First overlap check | 0 puddles |
| 11:57:28 | First gunshot fired | 0 puddles |
| 11:57:42 | Combat intensifies | 62 puddles |
| 11:57:45 | Heavy firefight | 164 puddles |
| 11:57:57 | Grenade thrown | 476 puddles |
| 11:58:01 | Level restart | Puddles cleared, then rebuild begins |

## Root Cause Analysis

### Primary Performance Issue: BloodyFeetComponent

**Location:** `scripts/components/bloody_feet_component.gd`

**Problem:** The `_check_blood_puddle_by_distance()` function iterates through ALL blood puddles every physics frame for EVERY character.

```gdscript
func _check_blood_puddle_by_distance() -> void:
    var blood_puddles := get_tree().get_nodes_in_group("blood_puddle")  # O(n) - gets all puddles

    for puddle in blood_puddles:  # O(n) - iterates all puddles
        if puddle is Node2D:
            var dist := parent_pos.distance_to(puddle.global_position)  # O(1) per puddle
```

**Performance Impact Calculation:**

| Parameter | Value |
|-----------|-------|
| Characters (enemies + player) | 11 |
| Physics frames per second | 60 |
| Blood puddles (worst case) | 476 |
| Distance calculations per second | **314,160** |

The function `_is_on_blood_puddle()` has the same O(n) pattern, potentially doubling the impact.

### Secondary Issues Found

1. **Detector not in scene tree properly:**
   - Log shows: `detector_global=(0, 0), in_tree=false`
   - The `_blood_detector` Area2D is not properly attached, causing the fallback distance-based detection to always run

2. **Excessive logging:**
   - Debug logging runs every 120 frames even when `debug_logging` is externally set
   - Still iterates all puddles for "closest puddle" calculation

3. **Blood puddle accumulation:**
   - Each bullet impact creates 10 blood decals (`Blood decals scheduled: 10 to spawn`)
   - Lethal hits create 20 blood decals
   - No cleanup/pooling mechanism for old puddles

## Evidence from Logs

### Puddle Count Growth
```
[11:57:42] Overlap check: areas=0, puddles=62, ...
[11:57:45] Overlap check: areas=0, puddles=164, ...
[11:57:57] Overlap check: areas=0, puddles=476, ...
```

### Detector Position Issue
Every overlap check shows:
```
detector_global=(0, 0), in_tree=false
```
This indicates the Area2D physics detection is broken, forcing the expensive fallback.

## Proposed Solutions

### Solution 1: Spatial Partitioning (Recommended)

Use Godot's built-in physics for detection instead of distance calculations:
1. Fix the Area2D detector so it's properly in the scene tree
2. Remove the fallback distance-based detection
3. Use collision layers/masks correctly

### Solution 2: Throttling

Reduce check frequency:
```gdscript
var _check_interval: int = 6  # Check every 6 physics frames (~10Hz at 60fps)
var _frame_counter: int = 0

func _physics_process(delta: float) -> void:
    _frame_counter += 1
    if _frame_counter >= _check_interval:
        _frame_counter = 0
        _check_blood_puddle_overlap()
```

### Solution 3: Blood Puddle Pooling/Cleanup

Limit the number of active blood puddles:
```gdscript
const MAX_BLOOD_PUDDLES := 100

func _on_blood_puddle_created() -> void:
    var puddles := get_tree().get_nodes_in_group("blood_puddle")
    while puddles.size() > MAX_BLOOD_PUDDLES:
        var oldest := puddles[0]
        oldest.queue_free()
        puddles.remove_at(0)
```

### Solution 4: Fix Area2D Detection (Immediate Fix)

The root issue is `in_tree=false`. The detector is added to parent but may not be initialized correctly. Ensure it's added after the parent is ready:

```gdscript
func _ready() -> void:
    # ... existing code ...
    # Defer setup to ensure parent is fully in scene tree
    call_deferred("_setup_blood_detector")
```

## Impact Assessment

| Issue | Severity | Fix Complexity |
|-------|----------|----------------|
| Distance-based fallback loop | Critical | Medium |
| Area2D not in tree | High | Low |
| Blood puddle accumulation | High | Medium |
| Excessive logging | Low | Low |

## Conclusion

The FPS drop is caused by the BloodyFeetComponent's distance-based blood detection fallback, which runs every physics frame for each character and iterates through all blood puddles (up to 476 in the logs). With 11 characters at 60fps, this results in over 300,000 distance calculations per second.

**Immediate recommendation:** Fix the Area2D detection so the fallback isn't needed, and add throttling as a safety measure.

## Update: Additional Performance Issues Found (2026-02-03)

### New Log File Analyzed
- `game_log_20260203_121003.txt` (3445 lines, ~82 seconds gameplay)

### Issues Discovered

#### Issue 1: GrenadeAvoidanceComponent State Thrashing

**Problem:** When an enemy is at the edge of the grenade danger zone, they rapidly oscillate between `EVADING_GRENADE` and `PURSUING` states - **dozens of times per second**.

**Evidence from logs:**
```
[12:11:19] [ENEMY] [Enemy1] EVADING_GRENADE: Escaped danger zone, returning to PURSUING
[12:11:19] [ENEMY] [Enemy1] State: EVADING_GRENADE -> PURSUING
[12:11:19] [ENEMY] [Enemy1] GRENADE DANGER: Entering EVADING_GRENADE state from PURSUING
[12:11:19] [ENEMY] [Enemy1] EVADING_GRENADE started: escaping to (1384.423, 525.4119)
... (repeats 40+ times in 1 second)
```

**Root cause:** The danger zone boundary creates oscillation:
1. Enemy moves to edge of danger zone
2. Exits danger → returns to PURSUING
3. State machine immediately rechecks → still in danger
4. Re-enters EVADING_GRENADE
5. Repeat every frame

**Fix applied:** Added 1-second cooldown (`EXIT_COOLDOWN_DURATION`) after exiting danger zone.

#### Issue 2: Expensive Scene Tree Search

**Problem:** `GrenadeAvoidanceComponent._find_grenades_in_scene()` was recursively searching the entire scene tree every frame when no grenades were in the "grenades" group.

**Performance impact:** O(n) where n = total scene nodes (potentially thousands).

**Fix applied:** Removed recursive scene tree search. Grenades should be in the "grenades" group; if not, the grenade system needs fixing, not expensive workarounds.

#### Issue 3: Debug Logging Still Enabled in Scenes

**Problem:** BloodyFeetComponent had `debug_logging = true` in scene files:
- `scenes/objects/Enemy.tscn`
- `scenes/characters/Player.tscn`
- `scenes/characters/csharp/Player.tscn`

This caused thousands of log lines even when the code default was false.

**Fix applied:** Changed all scene files to `debug_logging = false`.

### Summary of All Performance Fixes Applied

| Fix | Component | Impact |
|-----|-----------|--------|
| Signal-based detection | BloodyFeetComponent | Eliminates per-frame puddle iteration |
| Throttled fallback check | BloodyFeetComponent | 660 → 22 checks/sec |
| Distance squared optimization | BloodyFeetComponent | Eliminates ~314k sqrt/sec |
| Puddle check limit (50 max) | BloodyFeetComponent | Caps worst-case iterations |
| Exit cooldown (1s) | GrenadeAvoidanceComponent | Prevents state thrashing |
| Removed scene tree search | GrenadeAvoidanceComponent | Eliminates O(n) recursion |
| Disabled debug logging | Scene files | Reduces log overhead |

### Note on Original Grenade Avoidance Feature (Issue #407)

## Implementation (Applied Fix)

The following optimizations were applied to `scripts/components/bloody_feet_component.gd`:

1. **Signal-based detection**: Added `area_exited` signal handler and `_is_overlapping_blood` state tracking
2. **Deferred detector setup**: Used `call_deferred()` to ensure Area2D is properly in scene tree
3. **Throttled fallback**: Fallback distance check now runs every 30 frames (~0.5s) instead of every frame
4. **Distance squared**: Replaced `distance_to()` with `distance_squared_to()` to avoid sqrt
5. **Puddle limit**: Added `MAX_PUDDLES_TO_CHECK = 50` to prevent O(n) explosion

**Performance Impact (Estimated):**

| Metric | Before | After |
|--------|--------|-------|
| Distance calculations per frame | ~5236 | ~0-17 |
| Fallback checks per second | 660 | 22 |
| sqrt() operations per second | ~314,160 | ~0-1100 |

## References

- [Making the most of Godot's speed - GDQuest](https://www.gdquest.com/tutorial/godot/gdscript/optimization-engine/)
- [General optimization tips - Godot Docs](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [Using Area2D - Godot Docs](https://docs.godotengine.org/en/stable/tutorials/physics/using_area_2d.html)
- [Performance - Godot Docs](https://docs.godotengine.org/en/stable/tutorials/performance/index.html)
