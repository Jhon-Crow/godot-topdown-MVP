# Case Study: Issue #1528 — Combat Performance (5–7 FPS)

## Summary

In-game FPS drops to 5–7 fps during combat with 20 enemies in DocksLevel. After three fix iterations (v1, v2, v3) the problem persists. This document reconstructs the timeline, traces the root causes found in each iteration, and documents the v4 root causes still active after v3.

---

## Game Logs Collected

| File | Timestamp | Build | Notes |
|------|-----------|-------|-------|
| `game_log_20260326_080756.txt` | 08:07:56 | Pre-fix | Original report, baseline data |
| `game_log_20260326_080958.txt` | 08:09:58 | Pre-fix | Second baseline, more combat |
| `game_log_20260326_135822.txt` | 13:58:22 | Post-v3 | Latest; still drops to 5–7 fps |

---

## Timeline of Events

### Baseline (pre-fix) — game_log_20260326_080756.txt

- **Level**: LabyrinthLevel (5 enemies then DocksLevel with 20)
- **FPS drops**: 17–29 fps in log 080756; 5–10 fps in log 080958
- **Dominant log volumes**: 990 BloodDecal entries in 4847 total lines
- **Key hotspots identified**:
  - Each enemy's `fire()` called `get_node_or_null("/root/AudioManager")` etc. (~5 lookups/shot)
  - `_log_to_file()` called `get_node_or_null("/root/FileLogger")` on every log call
  - `SoundPropagation._emit_sound_internal()` rebuilt listener Array with `filter()` + `has_method()` per call

### Fix v1 & v2 — Enemy AI cache (partial)

Cached `PerformanceSettings` and `DifficultyManager` per-enemy. Also added log throttle for COMBAT/PURSUING/FLANKING/ASSAULT states. Reduced ~4,800 lookups/sec.

### Fix v3 — commit b9e2bdee

- Cached AudioManager, SoundPropagation, GameManager, ProjectilePoolManager, ImpactEffectsManager, FileLogger, ExperimentalSettings in `_ready()` for each of 20 enemies
- All 10 `_transition_to_*` functions use `_cached_perf_settings`
- `_log_to_file` uses `_cached_file_logger`
- SEARCHING state added to log throttle
- SoundPropagation: replaced `filter()+has_method()` with lazy in-place removal + direct call

**Estimated savings**: ~1,200–1,500 get_node_or_null calls/sec eliminated on top of v2.

### Latest log — game_log_20260326_135822.txt (POST-v3, still broken)

- **FPS drops**: 5, 25, 12, 5, 6, 5, 7, 6, 6, 5 fps — **identical to baseline!**
- **Log density**: 98–271 lines/second during combat
- **BloodDecal entries**: **1,043 in 2,868 total lines** in a ~16 second combat session

---

## Root Cause Analysis

### Root Cause 1: BloodDecal node instantiation flood (PRIMARY, unresolved)

**Where**: `scripts/autoload/impact_effects_manager.gd`

Each bullet hit creates:
- **30 new BloodDecal nodes** (lethal hit) or 15 (non-lethal) via `_blood_decal_scene.instantiate()`
- Each BloodDecal's `_ready()` calls `get_node_or_null("/root/FileLogger")`
- Each BloodDecal's `_setup_puddle_area()` creates a new `Area2D` + `CollisionShape2D` + `CircleShape2D`

With 20 enemies firing at ~3 rounds/sec each = ~60 shots/sec:
- 60 × 30 = **1,800 new BloodDecal instantiations/sec**
- 1,800 × 1 FileLogger lookup = **1,800 get_node_or_null calls/sec** from BloodDecals alone
- 1,800 × 1 Area2D + CollisionShape + CircleShape = **5,400 physics objects created/sec**
- Each instantiate() triggers `tree_changed` signal → `_on_tree_changed()` in ImpactEffectsManager fires

Evidence from log: 1,043 `[BloodDecal]` log lines in 16 seconds ≈ **65 decals/second** (matches ~2 lethal shots/sec, 30 decals each).

This also explains why the Godot forum reports FPS drops to 4 fps with many Area2D nodes (see online research findings).

**Fix needed**: Cache FileLogger in BloodDecal OR suppress logging entirely. The logging itself is informational noise and not needed in production.

### Root Cause 2: ImpactEffectsManager hot-path get_node_or_null (HIGH, unresolved)

**Where**: `scripts/autoload/impact_effects_manager.gd`

Every bullet hit calls uncached `get_node_or_null`:

```gdscript
# Line 359: spawn_blood_effect() - called 60×/sec
var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
var _decals_on: bool = perf_settings == null or perf_settings.is_blood_decals_enabled()

# Line 412: spawn_blood_effect() - called 60×/sec
var gameplay_settings: Node = get_node_or_null("/root/GameplaySettings")
var blood_multiplier: float = gameplay_settings.get_blood_amount() if gameplay_settings else 1.0

# Line 432: spawn_sparks_effect() - non-lethal hits
var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")

# Line 481: spawn_muzzle_flash() - each shot
var perf_settings: Node = get_node_or_null("/root/PerformanceSettings")
```

At 60 shots/sec: **~4 lookups × 60 = 240 get_node_or_null calls/sec** from ImpactEffectsManager.

### Root Cause 3: Remaining uncached lookups in enemy.gd (MEDIUM, partially unresolved)

Lines 497, 588, 599, 745, 755, 2926, 4348, 4373, 4376, 4605 still call `get_node_or_null`.

The most impactful remaining ones:
- **Line 4348**: `_get_effective_detection_delay()` calls `get_node_or_null("/root/DifficultyManager")` — called every detection tick
- **Line 4605**: `_draw()` calls `get_node_or_null("/root/ExperimentalSettings")` — called every frame if debug draw enabled
- **Lines 588/599**: Sound listener registration/unregistration (one-time, acceptable)

### Root Cause 4: High log volume causing file I/O overhead (MEDIUM)

The game has `FPS drop logging: true` and `Logging: true` in ExperimentalSettings. With 98–271 log entries per second written to disk, file I/O itself adds latency. The `_log_to_file` calls throughout the codebase, even with v3 FileLogger caching in enemy.gd, are still voluminous.

Evidence: BloodDecal alone logs `"Blood puddle created at ..."` for every decal — 1,043 file writes in 16 seconds.

---

## Performance Data Summary

### Comparison Table

| Metric | Pre-fix (080756) | Post-v3 (135822) |
|--------|-----------------|-----------------|
| Minimum FPS in combat | 13 fps | 5 fps |
| BloodDecal log entries | 990 / 4847 lines | 1043 / 2868 lines |
| Sound emitted events | 88 | 121 |
| ROT_CHANGE events | ~50 | 37 |
| Log lines/combat-second (peak) | ~300 | 271 |
| FPS drops detected | 16 | 10 (in 12 seconds) |

**Conclusion**: The fix reduced ROT_CHANGE events (good) but FPS is actually *worse* in the post-v3 log (5 fps minimum vs 13 fps). The BloodDecal issue was not addressed and is the dominant remaining bottleneck.

---

## Proposed Solutions (v4 Fixes)

### Fix 1: Cache autoloads in ImpactEffectsManager (HIGH PRIORITY)

Cache `PerformanceSettings` and `GameplaySettings` once in `_ready()`:

```gdscript
var _cached_perf_settings: Node = null
var _cached_gameplay_settings: Node = null

func _ready() -> void:
    _cached_perf_settings = get_node_or_null("/root/PerformanceSettings")
    _cached_gameplay_settings = get_node_or_null("/root/GameplaySettings")
    ...
```

Then replace all 5 per-call lookups with cached references. **Saves ~240 lookups/sec**.

### Fix 2: Suppress BloodDecal per-decal logging (HIGH PRIORITY)

The `[BloodDecal] Blood puddle created at ...` message is logged for every decal. With 30 decals/hit × 60 hits/sec = 1,800 file writes/sec. Remove or gate this log:

```gdscript
# Before:
_log_info("Blood puddle created at %s (added to group)" % global_position)

# After: gate behind debug flag
if _debug_mode:
    _log_info("Blood puddle created at %s (added to group)" % global_position)
```

**Saves ~1,800 file I/O operations/sec**.

### Fix 3: Cache FileLogger in BloodDecal _ready() (MEDIUM PRIORITY)

The existing `get_node_or_null("/root/FileLogger")` in `blood_decal.gd:33` is called once in `_ready()` which is acceptable — but it fires for each of the 1,800 new nodes/sec. The real fix is Fix 2 (suppress logging), which eliminates the need for the FileLogger reference entirely at runtime.

### Fix 4: Cache _get_effective_detection_delay result (MEDIUM PRIORITY)

`_get_effective_detection_delay()` in `enemy.gd:4348` calls `get_node_or_null("/root/DifficultyManager")` on every detection tick. Since difficulty doesn't change mid-game, cache the result once in `_ready()`.

---

## External References

- [Godot 4 is 4x slower than 3.5 at instantiating scenes — godotengine/godot#71182](https://github.com/godotengine/godot/issues/71182)
- [Area nodes slow game to 4 FPS — Godot Forum](https://forum.godotengine.org/t/area-nodes-slows-game-to-4-fps/7447)
- [Performance drops instantiating thousands of objects — Godot Forum](https://forum.godotengine.org/t/performance-drops-when-instantiating-thousands-of-objects/105227)
- [GDQuest: Optimizing GDScript Code](https://www.gdquest.com/tutorial/godot/gdscript/optimization-code/)
- [Bloody Pool shader approach — godotshaders.com](https://godotshaders.com/shader/bloody-pool-smooth-blood-trail/)
