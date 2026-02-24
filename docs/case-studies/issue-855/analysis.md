# Case Study: Issue #855 — Incorrect Grenade Landing Sound Trigger During Player Movement

## Issue Summary

**Title (RU):** fix неправильное срабатывание звука гранаты
**Translation:** Fix incorrect grenade sound activation

**Reported Behavior:** If the player activates a grenade (pulls the pin) and then moves, the grenade landing sound fires even though the grenade hasn't actually landed yet. This sound should only play when the grenade reaches the end of its flight path and comes to rest.

**Attached Log:** `game_log_20260219_221717.txt`

---

## Data and Log Evidence

### Game Log: `game_log_20260219_221717.txt`

Key sequence of events from the log (first grenade incident):

```
[22:17:19] [INFO] [GrenadeBase] Grenade created at (0, 0) (frozen)
[22:17:19] [INFO] [GrenadeTimer] Initialized for Flashbang grenade, effect radius: 400
[22:17:19] [INFO] [GrenadeBase] Timer activated! 4.0 seconds until explosion
[22:17:19] [INFO] [GrenadeTimer] Timer activated! 4 seconds until explosion
[22:17:19] [INFO] [Player.Grenade] Timer started, grenade created at (150, 1000)
[22:17:19] [INFO] [Player.Grenade.Simple] RMB pressed after pin pull - starting trajectory aiming

... (player moves for ~3 seconds) ...

[22:17:22] [INFO] [SoundPropagation] Sound emitted: type=GRENADE_LANDING, pos=(150, 782.3333), ...
[22:17:22] [INFO] [GrenadeBase] Grenade landed at (150, 782.3333)

... (grenade explodes 1 second later at player position, was NEVER thrown) ...

[22:17:23] [INFO] [GrenadeBase] EXPLODED at (150, 972.4444)!
```

**Critical observation:** The grenade "landed" at `(150, 782)` approximately 3 seconds after pin pull, but the grenade was **never thrown** — it exploded at the player's position `(150, 972)`, confirming it was still following the player when the false landing sound fired.

The grenade's "landing position" `(150, 782)` corresponds exactly to where the player was at `22:17:22`, as confirmed by enemy AI rotation data showing the player near y=782-814 at that time.

This pattern repeats in the log:
- **Second incident:** `[22:17:26] Grenade landed at (150, 805.8334)` — again before throw
- **Third incident:** `[22:17:39] Grenade landed at (150, 789.3334)` — before throw
- **Fourth incident:** `[22:17:50] Grenade landed at (150, 1111.6)` — before throw

---

## Root Cause Analysis

### System Overview

The grenade system has two parallel landing detection mechanisms:

1. **GDScript** (`scripts/projectiles/grenade_base.gd`): Landing detection in `_physics_process()`
2. **C#** (`Scripts/Projectiles/GrenadeTimer.cs`): Landing detection in `_PhysicsProcess()`

### The Bug — GDScript Landing Detection (grenade_base.gd)

```gdscript
# Lines 192-199 in grenade_base.gd
func _physics_process(delta: float) -> void:
    ...
    # Check for landing (grenade comes to near-stop after being thrown)
    if not _has_landed and _timer_active:
        var current_speed := linear_velocity.length()
        var previous_speed := _previous_velocity.length()
        # Grenade has landed when it was moving fast and now nearly stopped
        if previous_speed > landing_velocity_threshold and current_speed < landing_velocity_threshold:
            _on_grenade_landed()
    _previous_velocity = linear_velocity
```

**The bug:** The condition `if not _has_landed and _timer_active:` is **missing a check that the grenade is in flight (not frozen)**. The check runs as soon as the timer is activated, which happens BEFORE the grenade is thrown.

### Why Does `linear_velocity` Become Non-Zero When Frozen?

The grenade uses `FREEZE_MODE_KINEMATIC` in Godot 4. In this mode:
- The RigidBody2D body can be moved via direct `global_position` assignment
- It **participates in collision detection** like a kinematic body
- The physics engine **computes an effective velocity** from position changes between frames

The player code (`Player.gd` line 429, `Player.cs` line ~1263) updates the grenade position each frame while it's held:
```gdscript
_active_grenade.global_position = global_position  # Player.gd
# or
_activeGrenade.GlobalPosition = GlobalPosition;  # Player.cs
```

When the player moves quickly, the grenade's `global_position` changes significantly between physics frames. In `FREEZE_MODE_KINEMATIC`, Godot uses these position changes to compute the body's effective velocity for collision purposes. The `linear_velocity` property of the frozen body then reflects this "movement velocity."

### The Trigger Sequence

1. Player activates grenade (pin pulled) → `_timer_active = true`
2. Grenade is frozen (`freeze = true`, `FREEZE_MODE_KINEMATIC`)
3. Player moves fast → grenade position updates rapidly → `linear_velocity` reflects high speed
4. Player suddenly stops or changes direction → `linear_velocity` drops below `landing_velocity_threshold` (50 px/s)
5. Landing detection fires: `previous_speed > 50` ✓ and `current_speed < 50` ✓
6. `_on_grenade_landed()` is called → landing sound plays → FALSE POSITIVE

### The C# Landing Detection (GrenadeTimer.cs)

```csharp
// Lines 252-278 in GrenadeTimer.cs
if (IsThrown && !_hasLanded)
{
    // ... landing detection ...
}
```

**The C# code is CORRECT**: it checks `IsThrown` before doing landing detection. `IsThrown` is only set to `true` when `MarkAsThrown()` is called (right before the grenade is unfrozen and thrown). So the C# component **does not have this bug**.

---

## Timeline of Events

```
T+0s  [22:17:19]: Player presses G + RMB, grenade created (frozen at player pos)
T+0s  [22:17:19]: Timer activated (4-second fuse)
T+0s  [22:17:19]: Player starts trajectory aiming (RMB held)

T+1s  [22:17:20]: Player begins moving (position changes ~(150, 1000))
T+2s  [22:17:21]: Player continues moving, grenade follows via position copy
T+3s  [22:17:22]: Player pauses/slows briefly near (150, 782)
                  → linear_velocity drops below 50 px/s threshold
                  → FALSE landing detection fires!
                  → Landing sound plays at (150, 782)

T+4s  [22:17:23]: Timer expires, grenade explodes at (150, 972)
                  (Grenade was NEVER thrown - exploded at player position)
```

---

## Proposed Solutions

### Solution 1: Add `freeze` Check to Landing Detection (Recommended)

The simplest and most targeted fix: check that the grenade is NOT frozen before doing landing detection.

```gdscript
# In grenade_base.gd _physics_process()
# Check for landing (grenade comes to near-stop after being thrown)
if not _has_landed and _timer_active and not freeze:  # ADD: "and not freeze"
    var current_speed := linear_velocity.length()
    var previous_speed := _previous_velocity.length()
    if previous_speed > landing_velocity_threshold and current_speed < landing_velocity_threshold:
        _on_grenade_landed()
```

This mirrors the approach already used correctly in the C# `GrenadeTimer.cs` which checks `IsThrown` (equivalent to "not frozen").

### Solution 2: Add `is_thrown()` Check

Use the existing `is_thrown()` method which already checks `not freeze`:

```gdscript
# In grenade_base.gd
if not _has_landed and _timer_active and is_thrown():
    # ... landing detection ...
```

`is_thrown()` returns `not freeze` (line 476 of grenade_base.gd), which is semantically clearer.

### Solution 3: Track Thrown State Explicitly in GDScript

Add a separate `_is_thrown` flag in GDScript (similar to C# `IsThrown`):

```gdscript
var _is_thrown: bool = false

func throw_grenade_simple(direction, speed):
    _is_thrown = true
    freeze = false
    ...

func _physics_process(delta):
    if not _has_landed and _timer_active and _is_thrown:
        # ... landing detection ...
```

---

## Recommended Fix

**Solution 2** (using `is_thrown()`) is the most readable and semantically clear, as it expresses the intent directly: "has the grenade been thrown?"

The fix should be applied to `scripts/projectiles/grenade_base.gd` at lines 192-199.

The C# `GrenadeTimer.cs` does NOT need changes — it already correctly guards landing detection with `IsThrown`.

---

## Additional Notes

### Why Does This Not Affect the C# Component?

The C# `GrenadeTimer.cs` was written more carefully with the explicit `IsThrown` guard. It was introduced as a fix for Issue #432 (GDScript failing in exported builds). The GDScript base class `grenade_base.gd` predates the awareness of this issue and was not updated to match the C# guard.

### Impact

- All grenade types (Flashbang, Frag, AggressionGas) are affected since they all inherit from `GrenadeBase`
- The bug only manifests when:
  1. Player activates grenade (pulls pin)
  2. Player moves fast enough to exceed `landing_velocity_threshold` (50 px/s)
  3. Player then pauses or slows below the threshold
- In the log, this triggered 4 times across different grenade activations

### Severity

**Medium** — The bug causes:
- Incorrect audio (landing sound at wrong time/place)
- Potential AI confusion (enemies may react to landing sound at wrong location)
- Does NOT prevent grenade from functioning correctly
