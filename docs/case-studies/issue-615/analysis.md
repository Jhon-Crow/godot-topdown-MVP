# Issue #615: Grenades Not Reaching Crosshair (Redux)

## Summary

**Issue:** Grenades in simple throwing mode don't reach the crosshair target position.

**Root Cause:** The throw speed calculation formula in `Player.cs` assumed constant friction, but the actual grenade physics (introduced in Issue #435) uses velocity-dependent friction with reduced friction at high speeds. The old compensation factor of 1.16x was calibrated for the pre-#435 constant friction model and became incorrect after the friction model changed.

**Solution:** Replaced the old formula `v = sqrt(2 * F * d * 1.16)` with a proper two-phase friction model that calculates speed based on:
- Phase 1 (high speed): friction = groundFriction * minFrictionMultiplier (150 px/s²)
- Phase 2 (low speed): friction ramps from 150 to 300 px/s² via quadratic curve

## Timeline

1. **Issue #398** (2026-02-03): Fixed double-damping, spawn offset, property reading
2. **Issue #428** (2026-02-03): Added `physicsCompensationFactor = 1.16f` to compensate for Godot physics damping (calibrated with **constant friction** model)
3. **Issue #435** (2026-02-04): Introduced **velocity-dependent friction** in grenade_base.gd - reduced friction at high speeds (`min_friction_multiplier = 0.5`). This changed the physics model but **did not update** the speed calculation formula in Player.cs.
4. **Issue #615** (2026-02-07): User reports grenades not reaching crosshair again

## Root Cause Analysis

### The Formula Mismatch

**Player.cs speed calculation (pre-fix):**
```csharp
// Assumes constant friction = groundFriction (300 px/s²)
float requiredSpeed = Mathf.Sqrt(2.0f * groundFriction * throwDistance * 1.16f);
```

**Actual grenade physics (grenade_base.gd):**
```gdscript
# At high speeds (>= 200 px/s): friction = 300 * 0.5 = 150 px/s²
# At low speeds (< 200 px/s): friction ramps from 150 to 300 via quadratic curve
if current_speed >= friction_ramp_velocity:
    friction_multiplier = min_friction_multiplier  # 0.5
else:
    var t := current_speed / friction_ramp_velocity
    friction_multiplier = min_friction_multiplier + (1.0 - min_friction_multiplier) * (1.0 - t * t)
```

### The Physics

The grenade's flight has two distinct phases:

**Phase 1 (High Speed → Ramp Velocity):**
- Constant friction: `F * M = 300 * 0.5 = 150 px/s²`
- Distance: `d₁ = (v₀² - V_ramp²) / (2 * F * M)`

**Phase 2 (Ramp Velocity → Stop):**
- Variable friction (quadratic ramp from 150 to 300 px/s²)
- Average effective friction ≈ `F * (M + 2(1-M)/3)` ≈ 216 px/s²
- Distance: `d₂ ≈ V_ramp² / (2 * avg_friction)` ≈ 92 px (fixed constant)

**Total: `d = d₁ + d₂`**

### Why the Old Formula Was Wrong

The old formula treated the grenade as having constant friction of 300 px/s² throughout its entire flight. In reality, for most of the flight (at high speeds), friction is only 150 px/s² (50% of nominal). This means:

- The old formula **overestimated** the friction, requiring **too much speed**
- With the 1.16x compensation factor on top, the calculated speed was even higher
- The grenade received excessive velocity, overshooting the target

### The Trajectory Visualization Mismatch

An additional bug was found: the trajectory preview (`_Draw()` method) did NOT include the 1.16x compensation factor, while the actual throw did. This meant the landing indicator showed one position, but the grenade actually flew differently.

## Solution

### New Formula

```csharp
// Phase 1: constant reduced friction (above ramp velocity)
float phase1Friction = groundFriction * minFrictionMultiplier;

// Phase 2: average friction for the variable zone
float avgPhase2Multiplier = minFrictionMultiplier
    + 2.0f * (1.0f - minFrictionMultiplier) / 3.0f;
float avgPhase2Friction = groundFriction * avgPhase2Multiplier;

// Phase 2 distance (constant)
float phase2Distance = frictionRampVelocity² / (2 * avgPhase2Friction);

if (throwDistance <= phase2Distance)
    requiredSpeed = sqrt(2 * avgPhase2Friction * throwDistance);
else
    requiredSpeed = sqrt(V_ramp² + 2 * phase1Friction * (throwDistance - phase2Distance));
```

### Files Modified

1. **`Scripts/Characters/Player.cs`**:
   - Added `CalculateGrenadeThrowSpeed()` helper method
   - Added `CalculateGrenadeLandingDistance()` helper method (inverse)
   - Updated `ThrowSimpleGrenade()` to use new formula
   - Updated `_Draw()` trajectory visualization to use new formula
   - Both throw and visualization now read `friction_ramp_velocity` and `min_friction_multiplier` from the grenade

2. **`tests/unit/test_grenade_throw_speed.gd`**: 20 unit tests verifying formula accuracy

### Verification

The formula was verified against a physics simulation (experiments/simulate_grenade_physics.py) that replicates the exact friction model from grenade_base.gd:

| Target (px) | Formula Speed | Simulated Distance | Error |
|-------------|--------------|-------------------|-------|
| 200 | 269.3 | 199.4 | 0.3% |
| 400 | 364.0 | 398.6 | 0.4% |
| 600 | 438.8 | 598.0 | 0.3% |
| 800 | 502.5 | 797.5 | 0.3% |
| 1000 | 559.0 | 997.0 | 0.3% |

The small error (<1%) is from the Phase 2 average friction approximation and discrete time integration effects.

## Lessons Learned

1. **Formula must match physics model**: When the physics model changes (constant → velocity-dependent friction), the speed calculation must be updated simultaneously
2. **Empirical compensation factors are fragile**: The 1.16x factor was correct for one physics model but became incorrect when the model changed
3. **Trajectory preview should use the same formula as the throw**: Having two different formulas (with/without compensation) causes visual mismatch
4. **Two-phase analysis simplifies variable friction**: By splitting into a high-speed constant-friction phase and a low-speed variable-friction phase, we can derive a closed-form formula
