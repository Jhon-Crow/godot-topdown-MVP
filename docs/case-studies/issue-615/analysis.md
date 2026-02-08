# Issue #615: Grenades Not Reaching Crosshair

## Summary

**Issue:** Grenades in simple throwing mode don't reach the crosshair target position.

**Root Causes (TWO):**
1. **DOUBLE FRICTION** — both `grenade_base.gd` (_physics_process) and `GrenadeTimer.cs` (_PhysicsProcess) were applying friction simultaneously. The v3 fix (flag-based skipping) partially worked but was unreliable across grenade types.
2. **GODOT DEFAULT LINEAR_DAMP** — Godot 4.x project default `physics/2d/default_linear_damp` is 0.1. With `linear_damp = 0.0` in COMBINE mode (Godot default), the effective damping was `0.0 + 0.1 = 0.1`, causing grenades to travel ~13% shorter than the physics formula predicts — even with single friction.

**Solution (v4):**
1. Removed GDScript friction entirely — C# `GrenadeTimer` handles all friction exclusively
2. Set `linear_damp_mode = REPLACE` so `linear_damp = 0.0` means exactly zero damping

## Timeline

1. **Issue #398** (2026-02-03): Fixed double-damping (linear_damp), spawn offset, property reading
2. **Issue #428** (2026-02-03): Added `physicsCompensationFactor = 1.16f` — thought to compensate for "Godot hidden damping." Actually compensated partially for double friction + Godot default damp.
3. **Issue #432** (2026-02-03): Added `GrenadeTimer.cs` with its own friction handler because "GDScript _physics_process() does NOT run in exported builds." This created the double friction problem.
4. **Issue #435** (2026-02-04): Introduced velocity-dependent friction in `grenade_base.gd`. Made double friction effect worse.
5. **Issue #615 v1** (2026-02-07): Tried two-phase analytical model. Reverted (made things worse).
6. **Issue #615 v2** (2026-02-07): Synced 1.16x to `_Draw`. Still insufficient.
7. **Issue #615 v3** (2026-02-07): Added `_csharp_handles_friction` flag. Partially worked (flashbang=87% of target, frag=59%).
8. **Issue #615 v4** (2026-02-08): **Current fix** — removed GDScript friction entirely + set damp_mode=REPLACE.

## Root Cause Analysis

### Root Cause 1: Double Friction

Two friction systems were running simultaneously:

**GDScript** (`grenade_base.gd`): Velocity-dependent friction (0.5x-1.0x multiplier)
**C#** (`GrenadeTimer.cs`): Uniform friction (always 1.0x)

The v3 fix attempted to skip GDScript friction when C# `GrenadeTimer` was detected via `has_node("GrenadeTimer")`. This worked for flashbang grenades but NOT reliably for frag grenades, possibly due to timing of node detection.

**v4 solution:** Remove the GDScript friction code entirely. C# `GrenadeTimer.ApplyGroundFriction()` is the single source of friction for all grenades.

### Root Cause 2: Godot Default Linear Damping

Godot 4.x applies project-level physics damping to all RigidBody2D nodes:

- **Project default:** `physics/2d/default_linear_damp = 0.1` (Godot 4.3 default)
- **Grenade setting:** `linear_damp = 0.0` in scene files and `_ready()`
- **Default damp_mode:** `COMBINE` (adds node value to project default)
- **Effective damping:** `0.0 + 0.1 = 0.1` per frame

With `damp = 0.1`, Godot applies `velocity *= (1 - 0.1 * delta)` each physics step BEFORE user code runs. This reduces grenade travel distance by ~13%.

**v4 solution:** Set `linear_damp_mode = REPLACE` so that `linear_damp = 0.0` means exactly zero damping, overriding the project default.

### Mathematical Proof

**Game log `game_log_20260208_085031.txt` analysis:**

**Flashbang** (speed=568.7, friction=300, `_csharp_handles_friction` = true):
- Simulation with C# friction + Godot damp=0.1: **474.2 px**
- Actual from log: **471.0 px** — **MATCH** (ratio 0.993)

**Frag grenade** (speed=554.9, friction=280, `_csharp_handles_friction` = false):
- Simulation with double friction + Godot damp=0.1: **326.4 px**
- Actual from log: **324.7 px** — **MATCH** (ratio 0.995)

Both distances match the model of "C# friction + GDScript friction (for frag) + Godot default damp=0.1" with >99% accuracy.

## Solution (v4)

### Files Modified

1. **`scripts/projectiles/grenade_base.gd`**:
   - Added `linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE` in `_ready()` — eliminates Godot default damping
   - **Removed** all GDScript friction code from `_physics_process()` — eliminates double friction
   - **Removed** `_csharp_handles_friction` flag and detection logic — no longer needed
   - Kept landing detection and timer logic (unrelated to friction)

2. **`Scripts/Projectiles/GrenadeTimer.cs`**:
   - Added `_grenadeBody.LinearDampMode = REPLACE` and `LinearDamp = 0.0f` in `_Ready()` — belt-and-suspenders for exports where GDScript may not set it

3. **`tests/unit/test_grenade_throw_speed.gd`**:
   - Updated header comments to reflect both root causes

### Why This Works

With v4, the grenade physics has a single, predictable friction model:
- **Friction:** C# `GrenadeTimer.ApplyGroundFriction()` — uniform deceleration: `F = ground_friction * delta`
- **Damping:** None (linear_damp=0 in REPLACE mode)
- **Formula:** `v = sqrt(2*F*d)` → grenade travels exactly distance `d`

No compensation factor needed. No flag detection needed. No interaction between two friction systems.

## Game Log Analysis

### Log 1: `game_log_20260207_212300.txt` (v1 — two-phase fix, reverted)
- Speed: 424.4, Distance: 546.9, Friction: 300.0
- Grenade landed at ~177 px from spawn (two-phase formula gave wrong speed)

### Log 2: `game_log_20260207_221938.txt` (v2 — 1.16x sync fix)
- F-1: Speed: 613.2, Target: 540.2 → landed at ~371 px (59% = double friction + damp)
- Frag: Speed: 597.3, Target: 549.2 → landed at ~375 px (59%)

### Log 3: `game_log_20260208_085031.txt` (v3 — flag-based friction skip)
- Flashbang: Speed: 568.7, Target: 538.7 → landed at ~471 px (87% = C# only + damp)
- Frag: Speed: 554.9, Target: 549.8 → landed at ~325 px (59% = STILL double friction + damp)
- **Key finding:** Flag worked for flashbang but not for frag, proving unreliable detection

## Lessons Learned

1. **Check Godot project defaults:** `linear_damp = 0.0` doesn't mean zero damping in COMBINE mode. Always set `damp_mode = REPLACE` when you want exact control.
2. **Eliminate duplicate code paths, don't try to coordinate them:** The v3 flag-based approach was fragile. Removing GDScript friction entirely is simpler and more reliable.
3. **Verify assumptions about runtime behavior:** GDScript `_physics_process()` DOES run in Godot 4.3 exported builds.
4. **Compensation factors are a code smell:** The 1.16x factor masked the actual problem.
5. **Game logs with position data enable precise diagnosis:** Comparing spawn/landing positions against multiple friction models (at >99% accuracy) identified both root causes.
