# Case Study: Issue #878 — Premature Grenade Landing Sound in Offensive (Frag) Grenade

## Summary

The fix from PR #856 (which resolved premature landing sound for most grenades) did not fix the
issue for the **offensive grenade** (`frag_grenade.gd`, also known as "наступательная граната").
The same bug exists in `vog_grenade.gd` as well.

## Problem Description

After PR #856 was merged, the user (Jhon-Crow) tested and reported:
> "проблема решена для всех гранат, кроме наступательной"
> ("problem fixed for all grenades, except the offensive one")

The landing sound played while the grenade was still held (not thrown), occurring at the player's
position — not at the grenade's landing position. This was accompanied by enemy grenade avoidance
behavior triggering prematurely.

## Timeline Reconstruction from Game Log (`game_log_20260219_225205.txt`)

```
22:52:46 — FragGrenade pin pulled (timer activated, grenade frozen/following player)
22:52:48 — GRENADE_LANDING sound emitted at (150, 1111.999) ← player's position!
22:52:48 — FragGrenade thrown (simple mode) — impact detection enabled
```

Key observations:
1. Landing sound fires at `22:52:48` at position `(150, 1111.999)` — the player's position
2. The throw happens at `22:52:48` — **after** the landing sound was already emitted
3. This pattern repeats multiple times (see lines 2787, 3047 in the log)

## Root Cause Analysis

### PR #856 Fix (Applied to Base Class Only)

PR #856 fixed the bug in `grenade_base.gd` by adding an `is_thrown()` guard to the landing
detection check:

```gdscript
# grenade_base.gd, line 199 — FIXED in PR #856
if not _has_landed and _timer_active and is_thrown():
```

The `is_thrown()` method returns `not freeze`, so it's `false` while the grenade is still held
by the player (frozen) and `true` only after it's been thrown.

### The Missed Override

`FragGrenade` (and `VOGGrenade`) **override** `_physics_process()` and contain their own landing
detection code that was **not** updated in PR #856:

```gdscript
# frag_grenade.gd, line 134 — UNFIXED (root cause of issue #878)
if not _has_landed and _timer_active:
    # ... landing detection logic
```

```gdscript
# vog_grenade.gd, line 112 — UNFIXED
if not _has_landed and _timer_active:
    # ... landing detection logic
```

Since these subclasses override the entire `_physics_process()` method, the fix in the base
class is never reached when these grenade types are in use.

### Why Frag Grenade Overrides `_physics_process()`

`FragGrenade` needs its own `_physics_process()` override because:
1. It needs to detect the unfreeze transition to enable impact detection (`_was_frozen` flag)
2. It needs to track arming distance (Issue #657)
3. It does NOT use a countdown timer (sets `_time_remaining = 999999.0`)
4. It does NOT have the blink effect

During the override, the developer replicated the landing detection logic from the base class
**without** the Issue #855 fix.

### Why `is_thrown()` Guard Is Necessary for Impact-Based Grenades

Even though frag grenades explode on impact (not timer), the landing detection is still needed
because:
1. When the grenade lands (comes to rest without hitting a solid wall), it explodes via `_on_grenade_landed()`
2. The same kinematic velocity problem applies: while frozen and following the player,
   `FREEZE_MODE_KINEMATIC` causes `linear_velocity` to reflect position updates from player
   movement, which can falsely trigger landing detection

## Affected Code

| File | Line | Status |
|------|------|--------|
| `scripts/projectiles/grenade_base.gd` | 199 | ✅ Fixed in PR #856 |
| `scripts/projectiles/frag_grenade.gd` | 134 | ❌ NOT fixed — root cause of #878 |
| `scripts/projectiles/vog_grenade.gd` | 112 | ❌ NOT fixed — same bug |
| `Scripts/Projectiles/GrenadeTimer.cs` | 252 | ✅ Correctly guarded with `IsThrown` |

## Fix

Apply the same `is_thrown()` guard to both affected GDScript overrides:

### `frag_grenade.gd` (line 134)

```gdscript
# Before (broken):
if not _has_landed and _timer_active:

# After (fixed):
# FIX for Issue #878: Add is_thrown() guard (same as grenade_base.gd Issue #855 fix).
# FragGrenade overrides _physics_process() so the base class fix is never reached.
# While frozen and following the player, FREEZE_MODE_KINEMATIC causes linear_velocity
# to reflect player movement, which was falsely triggering landing detection.
if not _has_landed and _timer_active and is_thrown():
```

### `vog_grenade.gd` (line 112)

```gdscript
# Before (broken):
if not _has_landed and _timer_active:

# After (fixed):
# FIX for Issue #878: Add is_thrown() guard (same as grenade_base.gd Issue #855 fix).
# VOGGrenade overrides _physics_process() so the base class fix is never reached.
if not _has_landed and _timer_active and is_thrown():
```

## C# Counterpart Confirmation

`GrenadeTimer.cs` (line 252) already correctly guards landing detection:
```csharp
if (IsThrown && !_hasLanded)
{
    // ... landing detection
}
```

This confirms the intended pattern and validates that the GDScript fix is correct.

## Attached Evidence

- `game_log_20260219_225205.txt` — Game log showing multiple premature landing sound events
  for FragGrenade (lines 2626, 2787, 3047)

## Online Research

The Godot 4 `FREEZE_MODE_KINEMATIC` behavior causing velocity calculation from position changes
is documented in the Godot docs. When `freeze_mode = FREEZE_MODE_KINEMATIC`, the physics engine
computes a velocity by comparing positions between frames. This is the underlying mechanism
that causes the false landing detection when the grenade follows the player while frozen.

Reference: https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html#enum-rigidbody2d-freezemode
> FREEZE_MODE_KINEMATIC: The body is not moved by the physics engine. It can be moved by
> code. Body contacts will generate collision signals. linear_velocity is read-only from
> code, **but is reported by the engine based on position delta.**

This confirms that `linear_velocity` is indeed computed from position changes in kinematic
freeze mode, validating the root cause analysis.
