# Issue #638: Frag Grenade (Offensive/Наступательная) Not Reaching Crosshair

## Summary

**Issue:** The frag grenade (наступательная граната) does not reach the crosshair target position after the fixes in PR #616.

**Root Cause:** `frag_grenade.gd` overrides `_physics_process()` with its own velocity-dependent friction code. PR #616 removed friction from `grenade_base.gd` but missed this override. This created **double friction** (GDScript + C# `GrenadeTimer.ApplyGroundFriction()`) exclusively for frag grenades, causing them to travel only ~64% of their target distance.

**Fix:** Removed the GDScript friction code from `frag_grenade.gd`'s `_physics_process()` override, consistent with the pattern established in PR #616. C# `GrenadeTimer` is now the sole friction source for all grenade types.

## Timeline

1. **Issue #615 / PR #616** (2026-02-07/08): Fixed double friction for flashbang and defensive grenades by removing friction from `grenade_base.gd`. Also set `linear_damp_mode = REPLACE` to eliminate Godot's hidden default damping.
2. **Issue #638** (2026-02-08): User reports that the frag grenade (наступательная граната) still doesn't reach the crosshair, even though flashbang and defensive grenades now work correctly.

## Root Cause Analysis

### The Double Friction Problem (Again)

PR #616 fixed double friction by removing all friction code from `grenade_base.gd`'s `_physics_process()`. However, `frag_grenade.gd` has its own **complete override** of `_physics_process()` that includes velocity-dependent friction:

```gdscript
# frag_grenade.gd (BEFORE fix)
func _physics_process(delta: float) -> void:
    # ... freeze detection ...

    # This friction code was NOT removed by PR #616:
    if linear_velocity.length() > 0:
        var friction_multiplier: float
        if current_speed >= friction_ramp_velocity:
            friction_multiplier = min_friction_multiplier  # 0.5 at high speed
        else:
            friction_multiplier = min_friction_multiplier + (1.0 - min_friction_multiplier) * (1.0 - t * t)
        var effective_friction := ground_friction * friction_multiplier
        var friction_force := linear_velocity.normalized() * effective_friction * delta
        linear_velocity -= friction_force
```

Meanwhile, `GrenadeTimer.cs` also applies uniform friction:
```csharp
// GrenadeTimer.cs (always runs)
private void ApplyGroundFriction(float delta)
{
    Vector2 frictionForce = velocity.Normalized() * GroundFriction * delta;
    _grenadeBody.LinearVelocity = velocity - frictionForce;
}
```

### Why Only Frag Grenades Were Affected

| Grenade Type | `_physics_process()` Source | Has GDScript Friction? | C# Friction? | Result |
|-------------|---------------------------|----------------------|-------------|--------|
| Flashbang | `grenade_base.gd` (no friction) | No | Yes | Single friction - OK |
| Defensive (F-1) | `grenade_base.gd` (no friction) | No | Yes | Single friction - OK |
| **Frag** | **`frag_grenade.gd` (HAS friction)** | **Yes** | **Yes** | **Double friction - BROKEN** |

### Mathematical Proof from Game Log

**Game log `game_log_20260208_150549.txt` analysis:**

**Flashbang** (Speed=571.9, Friction=300):
- Spawn: (210.0, 143.8), Landed: (746.1, 160.0)
- Travel distance: **536.1 px**
- Expected: d = v² / (2F) = 571.9² / (2 × 300) = **545.2 px**
- Ratio: 536.1 / 545.2 = **98.3%** (close match, small error from spawn offset angle)

**Frag Grenade** (Speed=549.5, Friction=280):
- Spawn: (209.8, 114.2), Landed: (555.1, 144.3)
- Travel distance: **345.3 px**
- Expected: d = v² / (2F) = 549.5² / (2 × 280) = **539.1 px**
- Ratio: 345.3 / 539.1 = **64.1%** (massive shortfall = double friction)

**Defensive (F-1)** (Speed=569.1, Friction=300):
- Spawn: (209.8, 108.9), Landed: (738.3, 156.8)
- Travel distance: **528.5 px**
- Expected: d = v² / (2F) = 569.1² / (2 × 300) = **539.9 px**
- Ratio: 528.5 / 539.9 = **97.9%** (close match)

The ~64% ratio for frag grenade is consistent with approximately double friction being applied.

## The Fix

**File modified:** `scripts/projectiles/frag_grenade.gd`

**Change:** Removed the velocity-dependent friction block (lines 99-126) from the `_physics_process()` override. Kept:
- Freeze detection (Issue #432 fallback)
- Landing detection (needed for impact-triggered explosion)
- Comment explaining why friction was removed

This aligns `frag_grenade.gd` with the pattern established in PR #616 where C# `GrenadeTimer.ApplyGroundFriction()` is the sole friction source for all grenade types.

## Lessons Learned

1. **Check all subclass overrides when modifying base class behavior.** PR #616 correctly removed friction from `grenade_base.gd` but didn't check that `frag_grenade.gd` had its own complete `_physics_process()` override with friction code.
2. **Test all grenade types, not just the ones initially reported.** The original issue #615 was reported for flashbang and defensive grenades. If frag grenades had been tested too, this issue would have been caught earlier.
3. **Method overrides can silently bypass base class fixes.** When a subclass completely overrides a method, changes to the base class version have no effect on the subclass.
