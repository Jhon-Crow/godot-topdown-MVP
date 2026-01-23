# Case Study: Issue #256 - Velocity-Based Grenade Throwing System

## Executive Summary

This case study documents the development and debugging of a realistic velocity-based grenade throwing system for a Godot 4 top-down shooter game. The issue (#256) requested changing the grenade throwing mechanics from a drag-distance-based system to a velocity-based system where the throw distance is determined by mouse velocity at the moment of release, similar to real-world physics.

**Key Finding:** The implementation revealed multiple layers of complexity due to the game's dual-language architecture (C# and GDScript) and exposed a common pattern of incomplete cross-language method overriding.

---

## 1. Original Issue Description

**Issue #256:** "изменить систему бросков гранат" (Change the grenade throwing system)

### Original Requirements (Russian with English translation)

> изначально я ставил задачу сделать реалистичный расчёт дальности броска в зависимости от замаха. но сейчас она не реалистичная.
>
> *Translation: Originally I set the task to make realistic throw distance calculation based on swing. But now it's not realistic.*

> сейчас если далеко протянуть мышкой - будет сильный бросок, даже если рука полностью остановится. должно быть - как при реальном броске - дальность определяется скоростью, которую движение руки (мышики) сообщает гранате.
>
> *Translation: Currently if you drag the mouse far - it will be a strong throw, even if the hand completely stops. It should be - like in a real throw - the distance is determined by the speed that the hand (mouse) movement gives to the grenade.*

### Physics Formula Referenced
The user referenced the kinetic energy formula:
```
E_k = ½mv²
```

### Key Requirements
1. **Mouse velocity at release** determines throw distance (not drag distance)
2. **Zero velocity at release = grenade drops at player's feet**
3. **Grenade mass affects** the swing distance needed for full velocity transfer
4. **Realistic physics** following kinetic energy principles

---

## 2. Timeline of Events

### Phase 1: Initial Analysis and GDScript Implementation
| Timestamp (UTC) | Event |
|----------------|-------|
| 2026-01-22 16:07 | Issue #256 created |
| 2026-01-22 16:48 | AI work session #1 started |
| 2026-01-22 16:48 | First solution draft completed |

**Actions taken:**
- Added `throw_grenade_velocity_based()` method to `grenade_base.gd`
- Added new properties: `grenade_mass`, `mouse_velocity_to_throw_multiplier`, `min_swing_distance`
- Updated `player.gd` with mouse velocity tracking

### Phase 2: C# Code Path Discovery
| Timestamp (UTC) | Event |
|----------------|-------|
| 2026-01-22 17:01 | User feedback: "изменения не добавились наверное как всегда дело в C#" (Changes weren't added, probably as always the matter is in C#) |
| 2026-01-22 17:51 | AI work session #2 started |
| 2026-01-22 17:54 | Root cause identified: C# Player.cs was still using legacy system |

**Evidence from game log (game_log_3_210703.txt):**
```
[21:07:12] [INFO] [GrenadeBase] LEGACY throw_grenade() called! Direction: (0.996999, 0.077419), Speed: 2484.6 (unfrozen)
[21:07:12] [INFO] [GrenadeBase] NOTE: Using DRAG-BASED system. If velocity-based is expected, ensure grenade has throw_grenade_velocity_based() method.
```

### Phase 3: C# Implementation
| Timestamp (UTC) | Event |
|----------------|-------|
| 2026-01-22 18:08 | User feedback: Grenade still flying far even when mouse is stopped |
| 2026-01-22 20:14 | AI work session #3 started |
| 2026-01-22 20:21 | C# implementation completed with velocity-based tracking |

**Actions taken:**
- Added mouse velocity tracking to `Player.cs`:
  - `_mouseVelocityHistory` - List for velocity smoothing
  - `_currentMouseVelocity` - Calculated velocity in pixels/second
  - `_totalSwingDistance` - Accumulated swing distance
- Updated `ThrowGrenade()` to call `throw_grenade_velocity_based()`

### Phase 4: Regression Discovered
| Timestamp (UTC) | Event |
|----------------|-------|
| 2026-01-22 20:33 | User feedback: Frag grenade stopped exploding, throw sensitivity too high |
| 2026-01-22 21:17 | AI work session #4 started (interrupted by usage limit) |

**Evidence from game log (game_log_4_232541.txt):**
```
[23:25:41] [INFO] [Player.Grenade] Throwing system: VELOCITY-BASED (v2.0 - mouse velocity at release)
...
[23:27:06] [INFO] [FragGrenade] Pin pulled - waiting for impact (no timer, impact-triggered only)
[23:27:10] [INFO] [FragGrenade] Pin pulled - waiting for impact (no timer, impact-triggered only)
...
# Note: NO "[FragGrenade] Impact detected - exploding immediately!" or "[GrenadeBase] EXPLODED" messages
```

### Phase 5: Multiple Retry Sessions
| Timestamp (UTC) | Event |
|----------------|-------|
| 2026-01-23 16:23 | AI work session #5 (short) |
| 2026-01-23 18:01 | AI work session #6 (short) |
| 2026-01-23 18:29 | AI work session #7 (short) |
| 2026-01-23 19:03 | User requested case study analysis |

---

## 3. Root Cause Analysis

### Root Cause #1: Dual-Language Architecture Gap

**Problem:** The game uses both C# (`Player.cs`) and GDScript (`player.gd`, `grenade_base.gd`) for the same functionality. The AI initially only modified the GDScript files, not realizing the C# code was the active code path for the player character.

**Evidence:**
- Game logs showed "LEGACY throw_grenade()" being called
- User correctly suspected: "наверное как всегда дело в C#" (probably as always the matter is in C#)

**Solution Applied:** Added velocity tracking and velocity-based throwing to `Player.cs`

### Root Cause #2: Incomplete Method Override in Subclass

**Problem:** When `throw_grenade_velocity_based()` was added to `grenade_base.gd`, the subclass `frag_grenade.gd` only overrode `throw_grenade()` (the legacy method), not the new velocity-based method.

**Code Analysis:**

In `frag_grenade.gd`:
```gdscript
## Override throw to mark grenade as thrown.
func throw_grenade(direction: Vector2, drag_distance: float) -> void:
    super.throw_grenade(direction, drag_distance)
    _is_thrown = true  # <-- CRITICAL: Sets flag for impact detection
    FileLogger.info("[FragGrenade] Grenade thrown - impact detection enabled")
```

The impact detection requires `_is_thrown = true`:
```gdscript
## Override body_entered to detect wall impacts.
func _on_body_entered(body: Node) -> void:
    super._on_body_entered(body)
    if _is_thrown and not _has_impacted and not _has_exploded:  # <-- NEVER TRUE!
        if body is StaticBody2D or body is TileMap:
            _trigger_impact_explosion()
```

**Why frag grenades stopped exploding:**
1. C# `Player.cs` calls `throw_grenade_velocity_based()` via `.Call()`
2. `frag_grenade.gd` doesn't override `throw_grenade_velocity_based()`
3. Base class `grenade_base.gd` handles the call but doesn't set `_is_thrown = true`
4. Impact detection checks `_is_thrown` - always false
5. Grenade never explodes

### Root Cause #3: Mouse Velocity Sensitivity Configuration

**Problem:** Maximum throw distance was achieved with medium mouse speed instead of very high speed, making it difficult to control throw strength.

**User Feedback:**
> сейчас максимальная дальность броска включается при средней скорости движения мышью, а должна при очень высокой (должно быть легче выбрать силу броска)
>
> *Translation: Currently maximum throw distance is triggered at medium mouse speed, but it should be at very high speed (it should be easier to choose throw strength)*

**Technical Analysis:**
The current configuration in `grenade_base.gd`:
```gdscript
@export var mouse_velocity_to_throw_multiplier: float = 3.0
@export var max_throw_speed: float = 2500.0
```

With a multiplier of 3.0, reaching max speed (2500) requires mouse velocity of ~833 px/s, which is easily achievable with medium-speed mouse movement.

---

## 4. Technical Deep Dive

### 4.1 Mouse Velocity Tracking in Godot 4

**Industry Context:** According to [Godot Engine issue #3796](https://github.com/godotengine/godot-proposals/issues/3796), the built-in `InputEventMouseMotion.velocity` property in Godot 4 has known issues:
- Updated only every 0.1 seconds
- Deliberately smoothed
- Inaccurate for precise throwing mechanics

**Solution in Player.cs:**
```csharp
// Calculate instantaneous mouse velocity (pixels per second)
Vector2 instantaneousVelocity = mouseDelta / (float)deltaTime;

// Add to velocity history for smoothing
_mouseVelocityHistory.Add(instantaneousVelocity);
if (_mouseVelocityHistory.Count > MouseVelocityHistorySize)
{
    _mouseVelocityHistory.RemoveAt(0);
}

// Calculate average velocity from history (smoothed velocity)
Vector2 velocitySum = Vector2.Zero;
foreach (Vector2 vel in _mouseVelocityHistory)
{
    velocitySum += vel;
}
_currentMouseVelocity = velocitySum / Math.Max(_mouseVelocityHistory.Count, 1);
```

### 4.2 C# to GDScript Interoperability

**Industry Context:** According to [Godot documentation on cross-language scripting](https://docs.godotengine.org/en/stable/tutorials/scripting/cross_language_scripting.html), when calling GDScript methods from C#:
- Use snake_case method names
- Parameter type mismatches silently fail (no error)
- Missing methods also fail silently

**Implementation Pattern:**
```csharp
if (_activeGrenade.HasMethod("throw_grenade_velocity_based"))
{
    _activeGrenade.Call("throw_grenade_velocity_based", releaseVelocity, _totalSwingDistance);
}
else if (_activeGrenade.HasMethod("throw_grenade"))
{
    // Legacy fallback
    float legacyDistance = velocityMagnitude * 0.5f;
    _activeGrenade.Call("throw_grenade", throwDirection, legacyDistance);
}
```

### 4.3 Physics Formula Implementation

**Kinetic Energy Principle:**
```
E_k = ½mv²
```

**Implementation in grenade_base.gd:**
```gdscript
func throw_grenade_velocity_based(mouse_velocity: Vector2, swing_distance: float) -> void:
    # Mass-adjusted minimum swing distance
    var mass_ratio := grenade_mass / 0.4  # Normalized to "standard" 0.4kg grenade
    var required_swing := min_swing_distance * mass_ratio

    # Velocity transfer efficiency (0.0 to 1.0)
    var transfer_efficiency := clampf(swing_distance / required_swing, 0.0, 1.0)

    # Convert mouse velocity to throw velocity
    var base_throw_velocity := mouse_velocity * mouse_velocity_to_throw_multiplier * transfer_efficiency
    var mass_adjusted_velocity := base_throw_velocity / sqrt(mass_ratio)  # sqrt for more natural feel

    var throw_speed := clampf(mass_adjusted_velocity.length(), 0.0, max_throw_speed)
```

---

## 5. Proposed Solutions

### Solution 1: Fix FragGrenade Method Override (Critical)

Add `throw_grenade_velocity_based()` override to `frag_grenade.gd`:

```gdscript
## Override velocity-based throw to mark grenade as thrown.
func throw_grenade_velocity_based(mouse_velocity: Vector2, swing_distance: float) -> void:
    super.throw_grenade_velocity_based(mouse_velocity, swing_distance)
    _is_thrown = true
    FileLogger.info("[FragGrenade] Grenade thrown (velocity-based) - impact detection enabled")
```

### Solution 2: Adjust Velocity-to-Throw Sensitivity

Reduce the multiplier to require higher mouse speed for maximum throw:

**Current:**
```gdscript
@export var mouse_velocity_to_throw_multiplier: float = 3.0
```

**Proposed:**
```gdscript
@export var mouse_velocity_to_throw_multiplier: float = 1.5
```

This would require mouse velocity of ~1667 px/s for maximum throw, making it easier to control throw strength at lower speeds.

### Solution 3: Architecture Documentation

Create documentation for future development:

1. **Dual-Language Guidelines:** When adding methods to GDScript base classes, check for:
   - All subclasses that override related methods
   - C# code that calls these methods

2. **Testing Checklist:**
   - Test flashbang (timer-based) throwing
   - Test frag grenade (impact-based) throwing
   - Test with various mouse speeds
   - Verify startup logs show correct throwing system

### Solution 4: Add Debug Logging for Method Dispatch

Add logging to help identify future method dispatch issues:

```gdscript
# In grenade_base.gd
func throw_grenade_velocity_based(mouse_velocity: Vector2, swing_distance: float) -> void:
    FileLogger.info("[%s] throw_grenade_velocity_based() called" % get_class())
    # ... rest of implementation
```

---

## 6. Lessons Learned

### 6.1 Dual-Language Architecture Challenges

1. **Always identify the active code path** before implementing changes
2. **Check both C# and GDScript** when modifying game mechanics
3. **User domain knowledge is valuable** - The user correctly identified C# as the likely issue

### 6.2 Inheritance and Method Overriding

1. **New base class methods require subclass review** - Any method added to a base class that affects behavior should be checked against all subclasses
2. **Flag-setting methods need special attention** - Methods that set state flags (like `_is_thrown`) must be overridden in subclasses that depend on those flags

### 6.3 Cross-Language Interop

1. **Silent failures are dangerous** - Godot's C#-to-GDScript call mechanism fails silently on type mismatches
2. **Use HasMethod() checks** - Always verify method existence before calling
3. **Document expected method signatures** - Clear documentation prevents signature mismatches

### 6.4 Physics Tuning

1. **Player feedback is essential** - The specific feedback about sensitivity was actionable
2. **Provide configuration options** - Using `@export` variables allows easy tuning
3. **Log key values** - Velocity, swing distance, and transfer efficiency help debugging

---

## 7. Files Affected

### Modified Files
| File | Changes |
|------|---------|
| `Scripts/Characters/Player.cs` | Added velocity tracking, velocity-based throwing |
| `scripts/projectiles/grenade_base.gd` | Added `throw_grenade_velocity_based()` method |
| `scripts/players/player.gd` | Updated throwing to use velocity-based system |

### Files Requiring Additional Changes
| File | Required Change |
|------|-----------------|
| `scripts/projectiles/frag_grenade.gd` | Override `throw_grenade_velocity_based()` |

### Configuration Files
| File | Parameters |
|------|------------|
| `scenes/projectiles/FlashbangGrenade.tscn` | `grenade_mass=0.36kg`, `ground_friction=300` |
| `scenes/projectiles/FragGrenade.tscn` | `grenade_mass=0.45kg` |

---

## 8. Data Files in This Case Study

### Logs Directory (`logs/`)
- `solution-draft-log-1.txt` - First AI work session (1.3 MB)
- `solution-draft-log-2.txt` - Second AI work session (423 KB)
- `solution-draft-log-3.txt` - Third AI work session (1.4 MB)
- `game_log_1_195917.txt` - Initial game startup
- `game_log_2_195927.txt` - Initial testing
- `game_log_3_210703.txt` - Testing after GDScript changes (shows LEGACY system)
- `game_log_4_232541.txt` - Testing after C# changes (shows VELOCITY-BASED system)
- `game_log_5_232816.txt` - Additional testing
- `game_log_6_232926.txt` - Final testing

### Data Directory (`data/`)
- `issue-256.json` - Original issue data
- `pr-260.json` - Pull request data
- `pr-260-comments.json` - PR conversation comments
- `pr-260-review-comments.json` - PR review comments
- `pr-260-commits.json` - Commit history
- `pr-260-diff.txt` - Complete PR diff
- `timeline.txt` - Extracted timeline from comments

---

## 9. References

### Online Resources
- [Godot Engine Issue #3796 - MouseMotion Velocity Issues](https://github.com/godotengine/godot-proposals/issues/3796)
- [Godot Forum - Object Velocity with Mouse Movement](https://forum.godotengine.org/t/object-velocity-with-mouse-movement/53162)
- [Godot Documentation - Cross-Language Scripting](https://docs.godotengine.org/en/stable/tutorials/scripting/cross_language_scripting.html)
- [Godot Issue #83765 - GDScript Function Not Called from C#](https://github.com/godotengine/godot/issues/83765)

### Internal References
- Issue #256: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/256
- PR #260: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/260

---

## 10. Conclusion

This case study illustrates the challenges of implementing physics-based game mechanics in a dual-language (C#/GDScript) Godot project. The key insights are:

1. **Root cause identification is crucial** - The user's intuition about C# being the issue was correct and saved significant debugging time

2. **Inheritance hierarchies require complete updates** - Adding a new method to a base class without updating subclasses that depend on related behavior leads to subtle bugs

3. **Cross-language interoperability has pitfalls** - Silent failures in C#-to-GDScript calls make debugging challenging

4. **Iterative feedback is valuable** - Each round of user testing revealed new issues that wouldn't have been caught by code review alone

The immediate fix requires overriding `throw_grenade_velocity_based()` in `frag_grenade.gd` to set the `_is_thrown` flag. Additionally, reducing the velocity-to-throw multiplier from 3.0 to ~1.5 would improve throw control as requested by the user.

---

*Case study compiled: 2026-01-23*
*Author: AI Issue Solver*
