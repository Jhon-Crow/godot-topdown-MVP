# Issue #615: Grenades Not Reaching Crosshair

## Summary

**Issue:** Grenades in simple throwing mode don't reach the crosshair target position.

**Root Cause:** The trajectory visualization (`_Draw`) did not include the 1.16x physics compensation factor that `ThrowSimpleGrenade()` uses. This caused the landing indicator to show a different position than where the grenade actually lands. Additionally, the logging of actual distance was inaccurate.

**Solution:** Added the same 1.16x physics compensation factor to the `_Draw()` trajectory preview and landing distance logging, ensuring the landing indicator matches the actual throw behavior.

## Timeline

1. **Issue #398** (2026-02-03): Fixed double-damping, spawn offset, property reading
2. **Issue #428** (2026-02-03): Added `physicsCompensationFactor = 1.16f` to compensate for Godot's RigidBody2D hidden damping effects (~14% undershoot). This was calibrated empirically.
3. **Issue #435** (2026-02-04): Introduced **velocity-dependent friction** in grenade_base.gd — reduced friction at high speeds (`min_friction_multiplier = 0.5`). The speed calculation formula in Player.cs was NOT updated.
4. **Issue #615** (2026-02-07): User reports grenades not reaching crosshair

## Root Cause Analysis

### The Mismatch Between Throw and Visualization

**ThrowSimpleGrenade** (line 2577-2578):
```csharp
const float physicsCompensationFactor = 1.16f;
float requiredSpeed = Mathf.Sqrt(2.0f * groundFriction * throwDistance * physicsCompensationFactor);
```

**_Draw simple aiming** (line 3930, BEFORE fix):
```csharp
// Missing compensation factor!
float requiredSpeed = Mathf.Sqrt(2.0f * groundFriction * throwDistance);
```

The throw used 1.16x compensation to account for Godot's hidden physics damping, giving the grenade ~7.7% more speed. But the trajectory preview did NOT include this compensation, so the landing indicator showed a shorter distance than where the grenade actually landed.

### The Logging Issue

The `actualDistance` logged in ThrowSimpleGrenade used:
```csharp
float actualDistance = (throwSpeed * throwSpeed) / (2.0f * groundFriction);
```
This gave the theoretical distance without compensation, which was ~16% higher than the actual landing distance. After the fix, it correctly reports the compensated distance.

### Why the Two-Phase Formula Approach Failed (Previous Attempt)

The first fix attempt tried to replace the 1.16x compensation with an analytical two-phase friction model. This approach:
1. Correctly modeled the explicit friction code in `grenade_base.gd`
2. But **did not account for Godot's hidden RigidBody2D damping effects** (~14% reduction)
3. Produced **lower speeds** than the original formula (since it assumed lower effective friction)
4. Combined with the hidden damping, caused **severe undershoot** (~32% of target distance)

The 1.16x compensation factor was empirically calibrated to account for ALL physics effects in the Godot engine, including hidden damping that cannot be analytically predicted. Removing it broke the calibration.

## Solution

### Files Modified

1. **`Scripts/Characters/Player.cs`**:
   - **`_Draw()` simple aiming**: Added 1.16x compensation to speed calculation and landing distance, matching `ThrowSimpleGrenade()`
   - **`_Draw()` complex aiming**: Added 1.16x compensation to landing distance calculation
   - **`ThrowSimpleGrenade()` logging**: Updated `actualDistance` to use compensated formula for accurate logging

### Verification

The fix ensures:
- `ThrowSimpleGrenade()` speed: `v = sqrt(2 * F * d * 1.16)` (unchanged)
- `_Draw()` speed: `v = sqrt(2 * F * d * 1.16)` (was: `v = sqrt(2 * F * d)`, now matches)
- Landing distance: `d = v² / (2 * F * 1.16)` (was: `d = v² / (2 * F)`, now accounts for damping)

## Game Log Analysis

From the user's game log (`game_log_20260207_212300.txt`):
- Grenade thrown with speed 424.4 (from the two-phase formula, which was the previous fix attempt)
- Target distance: 546.9 px
- Actual landing: ~177 px from spawn
- The low speed from the two-phase formula combined with Godot's hidden damping caused severe undershoot

## Critical Discovery: C# vs GDScript Friction Models

A key finding during analysis: the friction is applied differently depending on the runtime:

| Runtime | File | Friction Model | Notes |
|---------|------|---------------|-------|
| **Exported builds** (Windows) | `GrenadeTimer.cs` line 263 | **Uniform** (`F * delta`) | C# applies simple `velocity.Normalized() * GroundFriction * delta` |
| **Editor** (development) | `grenade_base.gd` line 167 | **Two-phase** (variable multiplier) | GDScript uses `friction_ramp_velocity` and `min_friction_multiplier` |

The user plays the **exported Windows build**, where C# `GrenadeTimer.ApplyGroundFriction()` handles friction. This uses **uniform friction at 300.0** — which is exactly what the 1.16x compensation factor was calibrated for. The GDScript two-phase friction model from issue #435 only runs in the Godot editor, not in exports (because GDScript `_physics_process()` doesn't run for C#-owned nodes in exported builds).

This explains why:
1. The 1.16x factor works correctly in the user's game (uniform C# friction + hidden engine damping)
2. The two-phase model was wrong for the user's build (it modeled GDScript friction, not C# friction)

## Lessons Learned

1. **Empirical compensation factors should NOT be removed without in-game testing**: The 1.16x factor accounts for real Godot engine behavior that cannot be analytically modeled
2. **All code paths must use the same formula**: Throw and visualization formulas must match
3. **Analytical models need validation against actual engine behavior**: A theoretically correct model can be wrong in practice due to engine-specific effects
4. **Game log analysis is essential**: The game log from the user clearly showed the distance discrepancy
5. **C# vs GDScript runtime behavior differs in exports**: GDScript physics code may not run in exported builds when the node is owned by a C# script, leading to different friction behavior than expected
