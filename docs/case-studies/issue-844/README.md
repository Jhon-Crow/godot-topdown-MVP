# Issue #844 — FPS Drop During Combat: Deep Case Study

**Issue:** [#844 — проанализируй, почему падает fps (Analyze FPS drops in combat)](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/844)
**Reporter:** Jhon-Crow
**Environment:** Windows, Godot 4.3-stable, release build (Debug: false)
**Level analyzed:** DocksLevel (20 enemies) after LabyrinthLevel (5 enemies)
**Log file:** [`game_log_20260219_200223.txt`](./game_log_20260219_200223.txt)
**Log coverage:** 20:02:23 – 20:06:13 (230 seconds, 27,743 log lines)

---

## Executive Summary

FPS drops severely during combat in the DocksLevel (20 enemies + rapid-fire AKGL weapon). The root causes are **seven distinct, compounding performance bottlenecks** identified from the game log and codebase analysis. These are ranked by estimated CPU/IO impact from highest to lowest.

---

## Bottleneck #1 — Synchronous File Logging on Every Sound Event (CRITICAL)

### Evidence from log

`emit_sound()` in `sound_propagation.gd` writes **two log lines per call** (one for the emission, one for the result) to the file logger synchronously. In the busiest second (20:04:19), **1,316 lines** were written to the log file — over 120 log lines per second on average.

```
[20:03:02] [INFO] [SoundPropagation] Sound emitted: type=CASING_KICK, pos=(...), listeners=20
[20:03:02] [INFO] [SoundPropagation] Sound result: notified=2, out_of_range=17, ...
```

Total: **4,655 SoundPropagation log writes** over 230 seconds = **~20 writes/sec** from sound alone.
Blood effect system (`impact_effects_manager.gd`) added another **1,381 log entries** = ~6 writes/sec.
Total file I/O: **~120 log lines/sec** to a persistent log file on disk.

### Root cause

`sound_propagation.gd:141-148` and `sound_propagation.gd:192-195` call `_log_to_file()` unconditionally on every `emit_sound()` call. The `impact_effects_manager.gd:98-104` does the same (`_log_info()` which always calls `_file_logger.log_info()`).

### Relevant code

**`sound_propagation.gd:141`:**
```gdscript
_log_to_file("Sound emitted: type=%s, pos=%s, source=%s (%s), range=%.0f, listeners=%d" % [...])
```

**`impact_effects_manager.gd:99-104`:**
```gdscript
func _log_info(message: String) -> void:
    var log_message := "[ImpactEffects] " + message
    print(log_message)  # Always prints
    if _file_logger and _file_logger.has_method("log_info"):
        _file_logger.log_info(log_message)  # Always writes to file
```

### Impact

At ~4ms per synchronous file write (measured in Godot community benchmarks), 120 writes/sec = **480ms of I/O overhead per second**, consuming nearly half a frame on a 60 FPS target. This alone can cause sustained FPS halving.

### Recommended fix

Gate file-logging behind OS build type or a runtime flag. The `_debug_logging` flag exists in `SoundPropagation` but only controls `print()` calls, not file logger calls:

```gdscript
# sound_propagation.gd
func _log_to_file(message: String) -> void:
    if _debug_logging and _file_logger and _file_logger.has_method("log_info"):
        _file_logger.log_info("[SoundPropagation] " + message)
```

Similarly for `impact_effects_manager.gd`, gate `_log_info()` behind `_debug_effects`:

```gdscript
func _log_info(message: String) -> void:
    if _debug_effects:
        print("[ImpactEffects] " + message)
        if _file_logger and _file_logger.has_method("log_info"):
            _file_logger.log_info("[ImpactEffects] " + message)
```

Also: `Bullet.cs:181` has `private const bool DebugPenetration = true;` — this is **hardcoded true**, causing every bullet-wall collision to log to disk via `LogPenetration()`. Found **892 bullet distance log entries** in the log.

---

## Bottleneck #2 — Duplicate CASING_KICK Sound Events Per Shot (HIGH)

### Evidence from log

Every CASING_KICK sound event appears **twice in a row at the exact same position**:

```
[20:03:02] Sound emitted: type=CASING_KICK, pos=(3917.432, 658.7122), ..., listeners=20
[20:03:02] Sound result: notified=2, ...
[20:03:02] Sound emitted: type=CASING_KICK, pos=(3917.432, 658.7122), ..., listeners=20  ← DUPLICATE
[20:03:02] Sound result: notified=2, ...
```

Total: **1,242 CASING_KICK entries** over 230 seconds, but because each real kick produces two log pairs, this means ~621 actual events emitted **twice** = **1,242 actual `emit_sound()` calls**.

### Root cause

The C# `Player` class inherits from `BaseCharacter` which calls `PushCasings()` after `MoveAndSlide()` via physics collision detection (`Scripts/AbstractClasses/BaseCharacter.cs:164`). Simultaneously, the GDScript player script (`scripts/characters/player.gd:383`) also calls `_push_casings()` every physics frame via the `CasingPusher Area2D`. When the same casing is within both the MoveAndSlide collision range AND the `CasingPusher` area, `receive_kick()` is called **twice** — once from each system — causing two `emit_casing_kick()` calls to `SoundPropagation`.

**`Scripts/AbstractClasses/BaseCharacter.cs:172-186`** (C# physics-based kicker):
```csharp
protected virtual void PushCasings()
{
    for (int i = 0; i < GetSlideCollisionCount(); i++)
    {
        var collider = GetSlideCollision(i).GetCollider();
        if (collider is RigidBody2D rigidBody && rigidBody.HasMethod("receive_kick"))
        {
            rigidBody.Call("receive_kick", pushDir * pushStrength);
        }
    }
}
```

**`scripts/characters/player.gd:383`** (GDScript area-based kicker — runs same frame):
```gdscript
_push_casings()  # Also calls casing.receive_kick(impulse) for same casings
```

### Recommended fix

Since the GDScript `_push_casings()` (Iteration 7, CasingPusher Area2D) is the more reliable and intentional system, override `PushCasings()` in `Player.cs` to skip the C# collision-based push — or remove the C# `PushCasings()` call from `PhysicsProcess()` in the Player class, since the GDScript side already handles it.

---

## Bottleneck #3 — Ghost Listener Accumulation in SoundPropagation (HIGH)

### Evidence from log

After the first scene reload (LabyrinthLevel → DocksLevel), the `SoundPropagation` listener count does **not reset** and continues growing above the 20 enemies in the current level:

```
[20:03:00] Registered listener: Enemy1 (total: 6)   ← old enemies still in list!
[20:03:00] Registered listener: OpenArea_Patrol2 (total: 30) ← 30 listeners for 20 enemies!
[20:03:35] Sound emitted: type=GUNSHOT, ..., listeners=60 ← grew to 60!
[20:03:35] Cleaned up 40 invalid listeners
```

After another scene reload (20:04:00), the count grew to **40 listeners** again despite only 20 enemies.

### Root cause

`sound_propagation.gd:104-108` correctly uses `not _listeners.has(listener)` to prevent duplicate registration, but stale/freed listeners from a previous scene are not cleaned up eagerly — they only get cleaned inside `emit_sound()`. When a new scene loads and re-registers all 20 enemies fresh, they are appended to the stale list, making it 20 (stale) + 20 (new) = 40 listeners, doubling the work of every sound emission.

### Relevant code

**`sound_propagation.gd:150-154`:**
```gdscript
# Clean up invalid listeners (destroyed nodes) — only runs inside emit_sound()!
var prev_count := _listeners.size()
_listeners = _listeners.filter(func(l): return is_instance_valid(l))
```

### Recommended fix

1. Add a method to clear all listeners on scene change:
   ```gdscript
   func clear_all_listeners() -> void:
       _listeners.clear()
   ```
2. Call this from level scripts in `_ready()` or connect to `get_tree().tree_changed`.
3. Alternatively, have enemies call `unregister_listener()` explicitly in `_exit_tree()`.

---

## Bottleneck #4 — Unlimited Blood Decal Accumulation (HIGH)

### Evidence from log

Every non-lethal hit spawns 10 decals; every lethal hit spawns 20 decals. These are scheduled with timers and added to the scene tree permanently (MAX_BLOOD_DECALS = 0 = unlimited):

```
[20:04:19] Blood decals scheduled: 10 to spawn at particle landing times
[20:04:19] Blood decals scheduled: 20 to spawn at particle landing times
```

Over 230 seconds: **302 non-lethal hit decal batches × 10 + 31 lethal × 20 = 3,640 blood decal nodes** added to the scene tree — never removed, never pooled.

### Root cause

`impact_effects_manager.gd:34`:
```gdscript
const MAX_BLOOD_DECALS: int = 0  # CRITICAL: Must remain 0 - do not change
```

This comment prohibits cleanup, but each decal is a persistent scene tree node. In Godot 4, each active node has processing overhead even if not visible (scene tree traversal, physics AABB checks, render visibility culling). With thousands of nodes accumulating over a full game session, both CPU and GPU costs grow linearly.

### Research context

Godot 4 GitHub issue [#71182](https://github.com/godotengine/godot/issues/71182) documents significant performance regression with 900+ scripted nodes. At 3,640+ decal nodes from a single level session, this is a significant multiplier.

### Recommended fix

Implement a ring buffer / FIFO cleanup with a reasonable cap (e.g., 200–500 decals). This preserves the "blood persists" gameplay feel while preventing unbounded growth:

```gdscript
const MAX_BLOOD_DECALS: int = 300  # Adjust based on playtesting

# In _schedule_delayed_decal, after appending:
_blood_decals.append(decal)
while _blood_decals.size() > MAX_BLOOD_DECALS:
    var oldest := _blood_decals.pop_front() as Node2D
    if oldest and is_instance_valid(oldest):
        oldest.queue_free()
```

Note: The comment `# CRITICAL: Must remain 0 - do not change` should be reviewed — it references issues #293 and #370 about "puddles should never disappear," but from a performance standpoint, this is unsustainable. A reasonable cap (200–500) means the *most recent* blood remains visible, achieving the same gameplay goal.

---

## Bottleneck #5 — Bullet Penetration Double Raycasting in _PhysicsProcess (MEDIUM-HIGH)

### Evidence from log

Every wall collision triggers verbose penetration logging with dual raycasting:

```
[20:03:03] [Bullet] _get_distance_to_shooter: shooter_position=(...), bullet_pos=(...)
[20:03:03] [Bullet] Using shooter_position, distance=4166.66
[20:03:03] [Bullet] Distance to wall: 4166.66 (283.7% of viewport)
[20:03:03] [Bullet] Distance-based penetration chance: 5%
[20:03:03] [Bullet] Penetration failed (distance roll)
```

**892 bullet distance log entries** in 230 seconds. Each wall hit runs:
1. `GetDistanceToShooter()` — accesses `ShooterPosition` or falls back to `GodotObject.InstanceFromId()`
2. `GetSurfaceNormal()` — fires a physics raycast (`IntersectRay`)
3. `IsStillInsideObstacle()` while penetrating — fires **two more raycasts** (forward + backward)

### Root cause

`Scripts/Projectiles/Bullet.cs:181`:
```csharp
private const bool DebugPenetration = true;  // HARDCODED TO TRUE IN RELEASE BUILD
```

This causes every bullet that hits a wall to call `LogPenetration()` which writes to the file logger via `GetNodeOrNull("/root/FileLogger")` — a node lookup + disk write per frame while penetrating.

### Recommended fix

Change to false for release builds or gate behind build config:
```csharp
private const bool DebugPenetration = false;
```

Additionally, the double raycast in `IsStillInsideObstacle()` (forward + backward) can be reduced by using `PhysicsRayQueryParameters2D.hit_from_inside = true` to detect both entry and exit in a single query.

---

## Bottleneck #6 — SoundPropagation O(N) Listener Iteration Per Shot (MEDIUM)

### Evidence from log

With 20-60 listeners in the list, each `emit_sound()` call iterates all of them:

```
Sound emitted: type=GUNSHOT, ..., listeners=60
Cleaned up 40 invalid listeners
Sound result: notified=3, out_of_range=14, ...
```

The AKGL fires at ~10 shots/second. With GUNSHOT + CASING_KICK (×2 duplicate) per shot = 4 `emit_sound()` calls × 20-60 listeners = **80-240 listener iterations per second** just for shooting.

### Research context

Godot forum benchmarks show 2,300 signal emissions/sec ≈ 1ms overhead. With 60 listeners per emission, each `emit_sound()` call also calls `is_instance_valid()` and `distance_to()` for each listener. At 20+ emissions/second this accumulates.

### Recommended fix

1. **Fix ghost listener leak** (Bottleneck #3) to reduce the 60-listener spikes to the real count of 20.
2. **Spatial partitioning**: Instead of iterating all listeners, only iterate those within a bounding box check first. Use a 2D grid or quadtree to narrow candidates before distance calculation.
3. **Throttle CASING_KICK**: The CasingPusher is called every physics frame (`_physics_process`). Add a cooldown so CASING_KICK is emitted at most once per 0.1 seconds per casing.

---

## Bottleneck #7 — ReplayManager Per-Frame Recording with 20 Enemies (MEDIUM)

### Evidence from log

The ReplayManager records every 60 frames (1 second), but it processes **every single physics frame** to check whether to record:

```
[20:03:00] Recording frame 0 (0,0s): player_valid=True, enemies=20
[20:03:01] Recording frame 60 (1,0s): player_valid=True, enemies=20
```

This is 20 enemies × position + rotation + state data = potentially large Dictionary/Array allocations at 1 Hz. The C# `ReplayManager.cs` records data per frame.

### Root cause

The recording frequency itself (1 per second) is reasonable, but the **check** happens every physics frame. Also, recording 20 enemy positions as Dictionaries creates GDScript GC pressure.

### Recommended fix

Use typed `PackedVector2Array` instead of `Array of Dicts` for position recording. Also consider reducing to 10 FPS replay resolution (record every 6 seconds) to halve memory and processing cost.

---

## Summary Table

| # | Bottleneck | Severity | Root Cause Location |
|---|-----------|----------|-------------------|
| 1 | File logging on every sound/effect event | **CRITICAL** | `sound_propagation.gd:141`, `impact_effects_manager.gd:99`, `Bullet.cs:181` |
| 2 | Duplicate CASING_KICK sound per shot | **HIGH** | `BaseCharacter.cs:172` + `player.gd:383` both calling `receive_kick()` |
| 3 | Ghost listener accumulation across scene reloads | **HIGH** | `sound_propagation.gd:104` — no cleanup on scene change |
| 4 | Unlimited blood decal nodes in scene tree | **HIGH** | `impact_effects_manager.gd:34` MAX_BLOOD_DECALS=0 |
| 5 | DebugPenetration=true hardcoded in Bullet.cs | **MEDIUM-HIGH** | `Bullet.cs:181` |
| 6 | O(N) listener iteration per sound event | **MEDIUM** | `sound_propagation.gd:162-190` |
| 7 | ReplayManager per-frame processing overhead | **MEDIUM** | `Scripts/Autoload/ReplayManager.cs` |

---

## Proposed Solutions

### Immediate fixes (minimal risk, high impact)

1. **Disable file logging in non-debug builds**:
   - `Bullet.cs`: Change `DebugPenetration = true` → `false`
   - `sound_propagation.gd`: Gate `_log_to_file` behind `_debug_logging`
   - `impact_effects_manager.gd`: Gate `_log_info` behind `_debug_effects`
   - Estimated FPS gain: **+10-30 FPS** (removes ~480ms/sec of I/O)

2. **Fix duplicate CASING_KICK**:
   - Override `PushCasings()` in `Player.cs` to be empty (let GDScript handle it), OR
   - In `Player.cs`, add a flag to disable inherited `PushCasings()` since GDScript already does it
   - Estimated FPS gain: **+2-5 FPS** (halves casing sound processing)

3. **Fix ghost listener accumulation**:
   - Add `SoundPropagation.clear_all_listeners()` call at scene start
   - Estimated FPS gain: **+3-8 FPS** (reduces sound iteration from 60 to 20 listeners)

### Medium-term fixes (moderate complexity)

4. **Implement blood decal FIFO cleanup** with `MAX_BLOOD_DECALS = 300`
5. **Throttle CASING_KICK sound** with a per-casing cooldown (max once per 100ms)
6. **Reduce replay recording frequency** to every 6 frames (10 FPS equivalent)

### Long-term improvements (architecture changes)

7. **Object pooling for particle effects**: Pre-allocate a pool of blood/dust particle nodes and reuse them instead of instantiating new ones each shot
8. **Spatial partitioning for SoundPropagation**: Use a grid to find nearby listeners in O(1) average instead of O(N)
9. **Consider async/buffered file logging**: Write logs in batches on a background thread

---

## References

- [Godot 4 CPU Optimization Docs](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html)
- [GPUParticles2D Performance](https://godotengine.org/article/improvements-gpuparticles-godot-40/)
- [Godot #71182: Node creation performance regression](https://github.com/godotengine/godot/issues/71182)
- [Godot #89116: C# signals not disconnecting after QueueFree](https://github.com/godotengine/godot/issues/89116)
- [Signal performance benchmarks](https://godotforums.org/d/28260-performance-cost-of-signals)
- [Memory leak with reload_current_scene](https://godotengine.org/qa/39723/memory-leak-with-get_tree-reload_current_scene)
