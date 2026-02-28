# Issue #886 Case Study: HIGH — Grenade Blast Radius Instantiates Scene Every Call

## Issue Description

**Title**: fix HIGH: Grenade Blast Radius Instantiates Scene Every Call

**Summary**: `_get_blast_radius()` in `scripts/components/enemy_grenade_component.gd` creates a temporary grenade scene instance on every call just to read the `effect_radius` property. This function was called 10,621 times during a session when throw conditions were met but blocked (e.g., unsafe distance). The fix is to cache the result after first access.

**File**: `scripts/components/enemy_grenade_component.gd:296`

**Reported by**: Jhon-Crow

**Fixed in**: PR #916

---

## Timeline / Sequence of Events

### 1. Background: Issue #375 Introduces `_get_blast_radius()`

Issue #375 added a safe-throw distance check to prevent enemies from killing themselves with their own grenades. The developer needed to know the grenade's blast radius at throw-check time. The simplest implementation was to instantiate the scene temporarily and read the exported property:

```gdscript
func _get_blast_radius() -> float:
    if grenade_scene == null:
        return 225.0

    var temp_grenade = grenade_scene.instantiate()
    if temp_grenade == null:
        return 225.0

    var radius := 225.0
    if temp_grenade.get("effect_radius") != null:
        radius = temp_grenade.effect_radius
    temp_grenade.queue_free()
    return radius
```

This is functionally correct and safe, but carries hidden performance cost.

### 2. `try_throw()` Calls `_get_blast_radius()` on Every Attempt

`try_throw()` is called every frame (or near-every-frame) for each enemy that is in grenade-throwing range:

```gdscript
func try_throw(target: Vector2, is_alive: bool, is_stunned: bool, is_blinded: bool) -> bool:
    ...
    var blast_radius := _get_blast_radius()   # ← called unconditionally
    var min_safe_distance := blast_radius + safety_margin

    if dist < min_safe_distance:
        _log("Unsafe throw distance ...")
        return false
    ...
```

Even when the player is too close (unsafe distance), the function returns `false` — but only **after** instantiating and freeing a scene. The safety check is a common early-exit path.

### 3. 10,621 Instantiations Observed

The issue reports 10,621 calls in a single session. This arises from:
- Multiple enemies, each with a `EnemyGrenadeComponent`.
- Game running at 60 FPS.
- Typical game session of several minutes with enemies attempting (but failing) to throw grenades.
- Each enemy component independently instantiates the grenade scene on each attempt.

At 60 FPS with 3 enemies over a 60-second period: `60 × 3 × 60 = 10,800` — consistent with the reported 10,621.

### 4. Root Cause

The root cause is the absence of caching in `_get_blast_radius()`. The `effect_radius` property of a grenade is a static `@export var` that does not change at runtime:

```gdscript
# scripts/projectiles/frag_grenade.gd
@export var effect_radius: float = 225.0
```

Since the value is constant for a given `grenade_scene` and does not change after loading, caching is both safe and correct.

---

## Root Cause Analysis

### Primary Cause: No Memoization of Static Data

The `effect_radius` property is an exported constant that is set at scene design time and never mutated during gameplay. Reading it requires instantiating the packed scene, which involves:

1. Allocating memory for the node tree.
2. Calling `_init()` and `_ready()` on each node in the scene (including physics bodies, collision shapes, etc.).
3. Reading the property.
4. Calling `queue_free()` to schedule deallocation.

All of this work is wasted when the result is always the same value.

### Contributing Factor: Early-Exit Path Is the Hot Path

In normal gameplay, enemies frequently want to throw grenades but are blocked by the safe-distance check. This means the **most common code path** is:

1. Call `_get_blast_radius()` → instantiate scene → read property → free instance.
2. Check: `dist < min_safe_distance` → `true` → return `false`.

The expensive operation occurs on the path that does the least actual work.

### Why This Is Classified as HIGH (Not CRITICAL)

- The instantiation is fast (microseconds per call), so 10,621 calls may add tens of milliseconds of overhead — noticeable but not catastrophic.
- Memory usage is transient: each instance is freed immediately.
- The game remains playable, but CPU/GC pressure increases.
- At higher enemy counts or longer sessions, this could degrade to CRITICAL.

---

## Performance Impact Analysis

### Godot Scene Instantiation Cost

Godot's `PackedScene.instantiate()` is not free. For a `FragGrenade` scene (a `RigidBody2D` with collision shape, sprite, timer, and script), each instantiation involves:

- Node allocation and tree construction.
- Script `_init()` execution.
- Property default assignment.
- Registration with the scene tree (via `queue_free()`, not immediately, but still tracked by the GC).

Benchmarks on typical Godot 4 scenes suggest 10–100 µs per instantiation depending on scene complexity. At 10,621 calls:
- **Low estimate (10 µs/call)**: ~106 ms total overhead per session.
- **High estimate (100 µs/call)**: ~1,062 ms (~1 second) total overhead per session.

Additionally, `queue_free()` defers deallocation, which means the GC accumulates work that must be processed at end-of-frame, adding frame-time spikes.

### References

- [Godot 4 PackedScene.instantiate() documentation](https://docs.godotengine.org/en/stable/classes/class_packedscene.html#class-packedscene-method-instantiate)
- [Godot performance best practices — avoid instantiation in hot loops](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
- [GDScript performance tips](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html)

---

## Solution

### Approach 1: Hard-code the Radius (Rejected)

Replace `_get_blast_radius()` with a constant `225.0`.

- **Pros**: Zero overhead.
- **Cons**: If `grenade_scene` is ever changed to a different grenade type (e.g., a flashbang with a different radius), the hard-coded value will be wrong. Removes the dynamic capability introduced by Issue #375.

### Approach 2: Read from Scene Resource Directly (Not Feasible)

Access `effect_radius` directly from the `PackedScene` resource without instantiation.

- **Pros**: Would avoid instantiation.
- **Cons**: GDScript's `PackedScene` does not expose exported property values without instantiation. Packed scene state is stored in binary resource format; there is no public API to read export var values without creating an instance.

### Approach 3: Cache After First Instantiation (Chosen)

Add a `_blast_radius_cache: float = -1.0` member variable. On first call, instantiate, read, cache, and free. On subsequent calls, return the cached value immediately.

- **Pros**:
  - Reduces 10,621 instantiations to exactly 1.
  - No behavior change: the correct value is still read from the actual scene.
  - Safe: `effect_radius` is a static export var that does not change at runtime.
  - Minimal code change, easy to review and verify.
- **Cons**:
  - If `grenade_scene` is changed after initialization (hypothetically), the cache would return a stale value. However, `grenade_scene` is set once in `initialize()` and never changed, so this is not a real concern in practice.

### Chosen Implementation

**Added to State section (line 47–48):**
```gdscript
## Cache for blast radius to avoid repeated scene instantiation (Issue #886)
var _blast_radius_cache: float = -1.0
```

**Updated `_get_blast_radius()` function:**
```gdscript
## Get grenade blast radius (Issue #375).
## Result is cached after first access to avoid repeated scene instantiation (Issue #886).
func _get_blast_radius() -> float:
    if _blast_radius_cache >= 0.0:
        return _blast_radius_cache

    if grenade_scene == null:
        _blast_radius_cache = 225.0  # Default frag grenade radius
        return _blast_radius_cache

    # Instantiate grenade once to read effect_radius, then cache the result
    var temp_grenade = grenade_scene.instantiate()
    if temp_grenade == null:
        _blast_radius_cache = 225.0  # Fallback
        return _blast_radius_cache

    # Check if grenade has effect_radius property
    if temp_grenade.get("effect_radius") != null:
        _blast_radius_cache = temp_grenade.effect_radius
    else:
        _blast_radius_cache = 225.0  # Default

    # Clean up temporary instance
    temp_grenade.queue_free()

    return _blast_radius_cache
```

The sentinel value `-1.0` is used because a valid blast radius cannot be negative. The check `_blast_radius_cache >= 0.0` will be `false` only on the very first call, after which the cached value (always `>= 0`) is returned immediately.

---

## Verification

### Before Fix
- `_get_blast_radius()` called `grenade_scene.instantiate()` on every invocation.
- 10,621 calls → 10,621 scene instantiations per session.

### After Fix
- `_get_blast_radius()` calls `grenade_scene.instantiate()` exactly **once** per `EnemyGrenadeComponent` instance (on first call).
- 10,621 calls → **1** scene instantiation per component instance.
- Subsequent calls return `_blast_radius_cache` immediately (single float comparison).

### Impact Reduction
- **CPU overhead**: Reduced by ~99.99% (from 10,621 instantiations to 1).
- **GC pressure**: Eliminated. No longer accumulates `queue_free()` deferred work on every frame.
- **Behavior**: Unchanged. The blast radius value is identical to what was computed before.

---

## Follow-Up Bug Report (Log: game_log_20260301_013204.txt)

After the initial fix was deployed, the owner submitted a session log (`game_log_20260301_013204.txt`, 48,438 lines) with two new symptom reports:

1. **"При взрыве всё равно пролаг"** — "There is still a lag at the moment of explosion"
2. **"При взрыве наступательной гранаты не об врага в режиме Power Fantasy не останавливается время"** — "When an offensive grenade explodes NOT hitting an enemy in Power Fantasy mode, time does not stop"

### Log Analysis: Session Overview

The log covers a ~7-minute session on BuildingLevel with the player in Power Fantasy mode. The session contains:
- Multiple scene reloads (player deaths → restart at BuildingLevel)
- Mix of Power Fantasy sessions (player health 10/10) and Normal mode sessions (health 2-4/4)
- Grenades thrown: Frag (impact-triggered), VOGGrenade (impact-triggered via AKGL underbarrel), Flashbang/F-1 (timer-triggered)
- Both player-thrown and enemy-thrown grenades observed

### Root Cause Analysis: Bug 1 — Lag at Explosion

**Finding**: For impact-triggered grenades (Frag, VOGGrenade), **both GDScript and C# explosion paths fire simultaneously**, causing double work.

**Timeline for typical Frag wall hit (lines 10618–10651):**
```
[01:34:03] [GrenadeBase] Collision detected with Room2_WallBottom (type: StaticBody2D)
[01:34:03] [FragGrenade] Impact detected! Body: Room2_WallBottom (type: StaticBody2D), triggering explosion
[01:34:03] [FragGrenade] Impact detected - exploding immediately!
[01:34:03] [GrenadeBase] EXPLODED at (711.8705, 1032.413)!   ← GDScript fires first
[01:34:03] [FragGrenade] Spawned shrapnel #1..4              ← GDScript spawns 4 shrapnel
[01:34:03] [GrenadeTimer] Impact detected with Room2_WallBottom - EXPLODING! ← C# fires next
[01:34:03] [GrenadeTimer] Frag grenade activated at (711.8705, 1032.4133)!
[01:34:03] [GrenadeTimer] Applying frag explosion damage...
[01:34:03] [GrenadeTimer] Spawned 4 shrapnel pieces ...      ← C# spawns 4 MORE shrapnel
[01:34:03] [GrenadeTimer] Spawned PointLight2D frag explosion flash
```

**Result**: 8 shrapnel instead of 4, double damage calculation, two explosion sound/visual effects, two `QueueFree()` calls on the same grenade. This causes measurable CPU and GPU spikes.

**Why both paths fire**:
- `GrenadeBase._ready()` connects GDScript `_on_body_entered()` to `body_entered` signal
- `GrenadeTimer._Ready()` (C#) ALSO connects C# `OnBodyEntered()` to `body_entered` signal
- For Frag/VOG grenades, GDScript `_on_body_entered()` → `frag_grenade.gd::_trigger_impact_explosion()` → `_explode()` → sets `_has_exploded = true`
- C# `OnBodyEntered()` fires shortly after (same physics frame, different connection order) → checks own `HasExploded` (separate bool from GDScript!) → triggers `Explode()` independently

**Dual guard state issue**: GDScript has `_has_exploded: bool` and C# has `HasExploded: bool`. They are **independent variables** that do NOT share state. When GDScript sets `_has_exploded = true`, C# still sees `HasExploded = false` and proceeds with its own explosion logic.

**The fix**: Make `GrenadeTimer.Explode()` check whether GDScript has already handled the explosion. This can be done by reading the GDScript property via GDScript interop: `_grenadeBody.Get("_has_exploded")`. If `true`, skip the C# explosion.

### Root Cause Analysis: Bug 2 — Power Fantasy Time-Stop for Non-Enemy Hits

**Finding**: The Power Fantasy time-stop effect (`LastChanceEffectsManager.trigger_grenade_last_chance()`) is only triggered from `GrenadeBase._explode()` via `PowerFantasyEffectsManager.on_grenade_exploded()`. The C# `GrenadeTimer.Explode()` path does **not** call `on_grenade_exploded()`.

**Evidence from log (working case — Defensive grenade timer-based, lines 17554–17555):**
```
[01:34:55] [GrenadeBase] EXPLODED at (656.2443, 660.1168)!
[01:34:55] [PowerFantasy] Grenade exploded - triggering last chance time-freeze effect for 2000ms
```

**Evidence from log (working case — VOGGrenade wall hit in PF mode, lines 41322–41323):**
```
[01:38:09] [GrenadeBase] EXPLODED at (570.0801, 1376.776)!
[01:38:09] [PowerFantasy] Grenade exploded - triggering last chance time-freeze effect for 2000ms
... (681 lines of game activity) ...
[01:38:09] [GrenadeTimer] Impact detected with LobbyDivider_Right - EXPLODING!
[01:38:09] [GrenadeTimer] Frag grenade activated at (570.0801, 1376.7755)!
```

**Evidence from log (failing case — Frag wall hit in Normal mode, lines 10621–10632):**
```
[01:34:03] [GrenadeBase] EXPLODED at (711.8705, 1032.413)!
(no PowerFantasy log)
[01:34:03] [GrenadeTimer] Impact detected with Room2_WallBottom - EXPLODING!
[01:34:03] [GrenadeTimer] Frag grenade activated at (711.8705, 1032.4133)!
```

**Session mode correlation:**
| Log area | Health (PF mode?) | GrenadeBase.EXPLODED | PowerFantasy triggered |
|----------|-------------------|----------------------|------------------------|
| Line 10621 | 4/4 (Normal) | Yes (wall hit) | **NO** |
| Line 10940 | 4/4 (Normal) | Yes (wall hit) | **NO** |
| Line 17554 | 10/10 (PF) | Yes (F-1 timer) | **YES** |
| Line 26291 | 4/4 (Normal) | Yes (VOG wall hit) | **NO** |
| Line 39470 | 10/10 (PF) | Yes (Frag enemy hit) | **YES** |
| Line 41322 | 10/10 (PF) | Yes (VOG wall hit) | **YES** |
| Line 44823 | 10/10 (PF) | Yes (Frag enemy hit) | **YES** |

**Conclusion**: In Power Fantasy mode, ALL grenade explosions trigger the time-stop effect correctly — including wall hits (line 41322). The "no time-stop for wall hit" symptom occurs ONLY in Normal mode sessions, where `is_power_fantasy_mode()` returns `false`.

**Likely explanation**: The owner observed the symptom during a Normal mode session (health 4/4), possibly after the game reloaded the difficulty settings from `user://difficulty_settings.cfg`. The DifficultyManager does not log difficulty changes or the loaded value, making this impossible to diagnose from logs alone.

**The fix**:
1. Add logging to `DifficultyManager._load_settings()` so future logs show which difficulty was loaded on startup.
2. Add `on_grenade_exploded()` call to C# `GrenadeTimer.Explode()` as a safety net — if GDScript `_explode()` runs first (normal case), the second call will check `is_power_fantasy_mode()` again (no harm). If C# runs first (race condition), the PF effect will still trigger.

### Sequence Diagram: Impact-Triggered Grenade (Frag/VOG) Hitting Wall

```
physics frame:
  body_entered signal fires
    │
    ├─► GDScript handler (connected first in _ready())
    │     frag_grenade._on_body_entered(wall)
    │     → _trigger_impact_explosion()
    │     → GrenadeBase._explode()
    │         sets _has_exploded = true
    │         calls PowerFantasyEffectsManager.on_grenade_exploded()  ← PF triggers here
    │         calls _on_explode() → FragGrenade._on_explode()
    │             spawns 4 shrapnel  ← FIRST 4 shrapnel
    │         emits exploded signal
    │         await 0.1s → queue_free()
    │
    └─► C# handler (connected in GrenadeTimer._Ready())
          GrenadeTimer.OnBodyEntered(wall)
          HasExploded = false  ← independent bool!
          → GrenadeTimer.Explode()
              sets HasExploded = true
              calls ApplyFragExplosion()  ← damage applied AGAIN
              spawns 4 more shrapnel  ← SECOND 4 shrapnel
              calls QueueFree()  ← freed again (safe, Godot handles this)
              does NOT call on_grenade_exploded()  ← PF not triggered from here
```

### Files Involved

| File | Role | Issue |
|------|------|-------|
| `scripts/projectiles/grenade_base.gd` | GDScript base explosion → calls on_grenade_exploded() | Works correctly |
| `scripts/projectiles/frag_grenade.gd` | Impact detection → calls _explode() | Works correctly |
| `scripts/projectiles/vog_grenade.gd` | Impact detection → calls _explode() | Works correctly |
| `Scripts/Projectiles/GrenadeTimer.cs` | C# explosion handler, independent HasExploded state | **Bug: no PF call, no GDScript guard check** |
| `scripts/autoload/power_fantasy_effects_manager.gd` | on_grenade_exploded() checks is_power_fantasy_mode() | Works correctly |
| `scripts/autoload/difficulty_manager.gd` | is_power_fantasy_mode() | **Bug: no logging of loaded/current difficulty** |

### Proposed Fixes

#### Fix 1: Stop double explosion in GrenadeTimer.Explode()

In `GrenadeTimer.cs`, before running explosion logic, check if GDScript already handled it using the public `has_exploded()` method (not `Get("_has_exploded")` — non-@export GDScript properties are not reliably accessible via `Get()` in release exports):

```csharp
public void Explode()
{
    if (HasExploded)
        return;

    // FIX for Issue #886: Check if GDScript _explode() already ran.
    // GDScript sets _has_exploded = true before C# OnBodyEntered fires.
    // If GDScript already handled the explosion, C# should skip to avoid
    // double shrapnel, double damage, and the lag spike at explosion moment.
    // Use Call("has_exploded") instead of Get("_has_exploded") — method calls
    // are always accessible in exported builds, unlike non-@export GDScript vars.
    if (_grenadeBody != null && Type == GrenadeType.Frag)
    {
        if (_grenadeBody.HasMethod("has_exploded") && _grenadeBody.Call("has_exploded").AsBool())
        {
            LogToFile($"[GrenadeTimer] GDScript already handled Frag explosion - skipping C# duplicate");
            HasExploded = true; // Mark C# state to prevent future triggers
            return;
        }
    }

    HasExploded = true;
    // ... rest of explosion logic
```

#### Fix 2: Add on_grenade_exploded() call to C# explosion path

In `GrenadeTimer.Explode()`, after the HasExploded check, call `on_grenade_exploded()`:

```csharp
// Trigger Power Fantasy time-freeze effect
var pfManager = GetNodeOrNull("/root/PowerFantasyEffectsManager");
if (pfManager != null && pfManager.HasMethod("on_grenade_exploded"))
{
    pfManager.Call("on_grenade_exploded");
}
```

This ensures PF time-stop triggers even if C# runs before GDScript (race condition).

#### Fix 3: Add DifficultyManager startup logging

In `difficulty_manager.gd::_load_settings()`:

```gdscript
func _load_settings() -> void:
    var config := ConfigFile.new()
    var error := config.load(SETTINGS_PATH)
    if error == OK:
        var saved_difficulty = config.get_value("difficulty", "level", Difficulty.NORMAL)
        if saved_difficulty is int and saved_difficulty >= 0 and saved_difficulty <= Difficulty.POWER_FANTASY:
            current_difficulty = saved_difficulty as Difficulty
        else:
            current_difficulty = Difficulty.NORMAL
    else:
        current_difficulty = Difficulty.NORMAL
    # FIX for Issue #886: Log current difficulty so it's traceable in logs
    FileLogger.info("[DifficultyManager] Loaded difficulty: %s (value: %d)" % [
        get_difficulty_name(), current_difficulty
    ])
```

### Bug 2 Resolution: Not a Bug in Power Fantasy Mode

Further analysis of the session log revealed that the "no time-stop for wall hits" symptom occurs **only in Normal mode sessions** (player health 4/4), not in Power Fantasy mode (health 10/10). In PF mode, ALL grenade explosions — including wall hits — correctly trigger the time-stop effect. The PowerFantasy path (via GDScript `GrenadeBase._explode()`) was already working correctly.

The confusion arose because the session contained both Normal mode and Power Fantasy mode play (the user died and restarted multiple times, each time DifficultyManager loaded the saved difficulty from `user://difficulty_settings.cfg`). Without difficulty logging, it was impossible to tell which mode was active at each explosion. Fix 3 (DifficultyManager startup logging) resolves this observability gap.

**For the C# path (Fix 2)**: Even though Bug 2 is not present in PF mode via the GDScript path, the `on_grenade_exploded()` call was added to `GrenadeTimer.Explode()` as a safety net. This ensures the PF time-stop triggers correctly even when:
- GDScript `_explode()` is unavailable (extreme export edge case)
- C# runs before GDScript due to a race condition (theoretical)
