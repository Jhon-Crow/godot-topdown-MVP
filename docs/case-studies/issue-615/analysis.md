# Issue #615: Grenades Not Reaching Crosshair

## Summary

**Issue:** Grenades in simple throwing mode don't reach the crosshair target position. Grenades consistently land at only ~59% of the target distance.

**Root Cause:** **DOUBLE FRICTION** — both `grenade_base.gd` (_physics_process) and `GrenadeTimer.cs` (_PhysicsProcess) were applying friction simultaneously every physics frame, causing ~1.7x effective friction instead of the expected 1x.

**Solution:** Modified `grenade_base.gd` to detect the presence of the C# `GrenadeTimer` component and skip GDScript friction when C# handles it. Removed the 1.16x compensation factor from `Player.cs` since it was a partial workaround for the double friction, not for "hidden engine damping."

## Timeline

1. **Issue #398** (2026-02-03): Fixed double-damping (linear_damp), spawn offset, property reading
2. **Issue #428** (2026-02-03): Added `physicsCompensationFactor = 1.16f` — at the time, thought to compensate for "Godot's RigidBody2D hidden damping." Actually compensated partially for the double friction.
3. **Issue #432** (2026-02-03): Added `GrenadeTimer.cs` with its own friction handler because "GDScript _physics_process() does NOT run in exported builds." This was incorrect — GDScript physics DOES run.
4. **Issue #435** (2026-02-04): Introduced velocity-dependent friction in `grenade_base.gd` with `min_friction_multiplier = 0.5`. This made the double friction effect worse.
5. **Issue #615 v1** (2026-02-07): First fix attempt — tried to replace 1.16x with analytical two-phase model. Reverted because it made things worse.
6. **Issue #615 v2** (2026-02-07): Second fix attempt — synced 1.16x to `_Draw`. Still wrong because 1.16x doesn't fully compensate for double friction.
7. **Issue #615 v3** (2026-02-07): **Current fix** — identified double friction as root cause, fixed by preventing it.

## Root Cause Analysis

### The Double Friction Problem

Two friction systems run simultaneously on every physics frame:

**1. GDScript (`grenade_base.gd` line 186-208)** — Velocity-dependent friction:
```gdscript
# At high speed (>200): effective_friction = 0.5 × ground_friction
# At low speed (<200): smoothly ramps from 0.5 to 1.0 × ground_friction
var effective_friction := ground_friction * friction_multiplier
var friction_force := linear_velocity.normalized() * effective_friction * delta
linear_velocity -= friction_force
```

**2. C# (`GrenadeTimer.cs` line 263-283)** — Uniform friction:
```csharp
// Always applies full ground friction
Vector2 frictionForce = velocity.Normalized() * GroundFriction * delta;
_grenadeBody.LinearVelocity = velocity - frictionForce;
```

Combined effective friction at high speed: `0.5*F + 1.0*F = 1.5*F`
Combined effective friction at low speed: `1.0*F + 1.0*F = 2.0*F`

### Mathematical Proof

From user's game log (`game_log_20260207_221938.txt`), F-1 grenade throw:
- **Speed:** 613.2 px/s, **Friction:** 300.0, **Target distance:** 540.2 px
- **Expected with single friction:** d = 613.2² / (2 × 300) = 626.6 px
- **Actual landing:** spawn=(209.9, 139.2) → landing=(580.6, 156.5) → **371 px** (59% of expected)
- **With 1.5x friction:** d = 613.2² / (2 × 300 × 1.5) = 417.7 px
- **With ~1.7x friction** (weighted average): d ≈ 626.6 / 1.7 ≈ 368.6 px — **matches observed ~371 px**

### Why Was This Missed?

The original Issue #432 analysis concluded that "GDScript `_physics_process()` does NOT run in exported builds." This was incorrect. The evidence:

1. The game log from the exported build shows `"[GrenadeBase] CCD enabled"` and `"[GrenadeBase] Grenade created at..."` — proving GDScript `_ready()` runs in exports.
2. If `_ready()` runs, `_physics_process()` also runs — they use the same GDScript execution pipeline.
3. The 1.16x "compensation" factor was actually partially compensating for double friction (1/1.16 ≈ 0.86, vs actual ratio of ~0.59), not for engine damping.
4. After Issue #435 introduced variable friction (0.5x at high speed), the double friction effect changed from ~2.0x to ~1.5-1.7x, making the 1.16x factor even less adequate.

## Solution

### Files Modified

1. **`scripts/projectiles/grenade_base.gd`**:
   - Added `_csharp_handles_friction` flag (default `false`)
   - Added `_check_csharp_friction_handler()` called from `_ready()` via `call_deferred` to detect `GrenadeTimer` child
   - Added per-frame re-check in `_physics_process()` for late-attached `GrenadeTimer`
   - Modified friction condition: `if linear_velocity.length() > 0 and not _csharp_handles_friction`

2. **`Scripts/Characters/Player.cs`**:
   - **`ThrowSimpleGrenade()`**: Removed `physicsCompensationFactor = 1.16f`; formula is now `v = sqrt(2*F*d)`
   - **`_Draw()` simple aiming**: Removed `PhysicsCompensationFactor = 1.16f`; formula is now `v = sqrt(2*F*d)`
   - **`_Draw()` complex aiming**: Removed `ComplexPhysicsCompensation = 1.16f`
   - Landing distance is now `d = v²/(2*F)` (no compensation needed)

3. **`tests/unit/test_grenade_throw_speed.gd`**:
   - Removed all 1.16x compensation references
   - Updated formulas to `v = sqrt(2*F*d)` and `d = v²/(2*F)`
   - Added tests proving double friction causes undershoot
   - Added tests proving single friction works correctly

### Why This Works

With single friction (C# only), the physics is straightforward:
- Grenade decelerates at rate `F` (uniform friction)
- From `v² = u² - 2*F*s`, stopping distance `s = u²/(2*F)`
- Setting initial speed `u = sqrt(2*F*d)` gives stopping distance exactly `d`

No compensation factor is needed because there's no hidden extra damping — the "hidden damping" was actually the GDScript friction running alongside C#.

## Game Log Analysis

### Log 1: `game_log_20260207_212300.txt` (Two-phase fix — reverted)
- Speed: 424.4, Distance: 546.9, Friction: 300.0
- Grenade landed at ~177 px from spawn
- This build used the two-phase formula which gave incorrect (lower) speed

### Log 2: `game_log_20260207_221938.txt` (1.16x sync fix)
- F-1 grenade: Speed: 613.2, Target: 540.2, Friction: 300.0 → landed at ~371 px (59%)
- Frag grenade: Speed: 597.3, Target: 549.2, Friction: 280.0 → landed at ~375 px (59%)
- Frag grenade: Speed: 812.7, Target: 1016.7, Friction: 280.0 → hit wall at 475 px
- All throws consistently landed at ~59% of target, confirming double friction

## Lessons Learned

1. **Verify assumptions about runtime behavior**: The assumption "GDScript _physics_process doesn't run in exports" was wrong. Both GDScript and C# physics processes run.
2. **Look for double-processing before adding compensation factors**: When code doesn't behave as formulas predict, check for duplicate processing before assuming "hidden engine effects."
3. **Compensation factors are a code smell**: A magic number like 1.16x suggests the model is wrong, not that the engine is unpredictable.
4. **Game logs with position data enable precise diagnosis**: Comparing spawn position, landing position, and expected distance reveals the exact friction ratio.
5. **When adding a C# fallback for GDScript, disable the original**: If C# is added as a backup because "GDScript might not work," the GDScript path should be disabled when C# is active, not left running alongside it.
