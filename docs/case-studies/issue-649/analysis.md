# Case Study: Issue #649 - Manual Hammer Cocking for RSh-12 Revolver

## Issue Description

The user requested the ability to manually cock the revolver hammer with RMB immediately after a shot to skip the fire delay and increase the fire rate.

**Expected behavior:**
- After firing (LMB), player can immediately press RMB to cock the hammer
- RMB = instant hammer cock + cylinder rotation
- Then LMB = instant shot (no 0.15s cock delay)
- This allows skilled players to increase fire rate by manually cocking between shots

**Actual behavior (reported):**
- Hammer can only be cocked after the recoil/fire timer expires
- Cannot cock immediately after a shot

## Timeline

1. **Issue #661**: Added hammer cock delay (0.15s) before each shot - the hammer cocks and cylinder rotates, then the shot fires. This gives the revolver its mechanical feel.

2. **Issue #649 (initial implementation)**: Added `ManualCockHammer()` method with RMB input. However, the method checked `CanFire` which includes the fire timer check (`_fireTimer <= 0`).

3. **User feedback (2026-02-08)**: User tested the build and reported that the hammer can only be cocked after the recoil period, not immediately after a shot. This defeats the purpose of manual cocking.

## Root Cause Analysis

### The Fire Timer Blocking Chain

1. **`BaseWeapon.Fire()`** sets `_fireTimer = 1.0f / WeaponData.FireRate` after each shot
2. With `FireRate = 2.0`, this means `_fireTimer = 0.5 seconds`
3. **`CanFire`** property: `CurrentAmmo > 0 && !IsReloading && _fireTimer <= 0`
4. **`ManualCockHammer()`** checked `!CanFire` which returned `true` during the 0.5s cooldown
5. Result: Manual cocking was blocked for 0.5 seconds after each shot

### Code Path (Before Fix)

```
Player presses LMB → Revolver.Fire() → ExecuteShot() → base.Fire()
  → _fireTimer = 0.5s
  → CanFire = false for 0.5s

Player presses RMB (immediately after) → ManualCockHammer()
  → if (!CanFire) return false  ← BLOCKED HERE
  → Manual cock never happens
```

### The Contradiction

The entire purpose of manual cocking is to bypass the fire delay. But the manual cock check used `CanFire` which includes the fire delay check. This created a circular dependency: you can't cock to bypass the delay because the delay prevents cocking.

## Solution

### Fix Applied

1. **Removed `CanFire` check from `ManualCockHammer()`** - replaced with individual condition checks that only verify relevant state (ammo, reload state, weapon data), excluding the fire timer.

2. **Reset `_fireTimer` when manually cocking** - since the player is manually preparing the weapon, the fire rate timer should be reset so the follow-up LMB fires immediately.

3. **Also reset `_isHammerCocked` state** - if the auto-cock sequence from a previous LMB press is still pending, manual cock should override it.

### Code Path (After Fix)

```
Player presses LMB → Revolver.Fire() → ExecuteShot() → base.Fire()
  → _fireTimer = 0.5s

Player presses RMB (immediately after) → ManualCockHammer()
  → Checks: ammo > 0? yes. Reloading? no. Already cocked? no.
  → _fireTimer = 0 (reset timer)
  → _isManuallyHammerCocked = true
  → Plays cock + rotate sounds
  → Ready for instant fire

Player presses LMB → Revolver.Fire()
  → _isManuallyHammerCocked is true → fires instantly (no 0.15s delay)
```

## Data Sources

- `game_log_20260209_011812.txt` - Game log from user's test session showing revolver firing pattern
- `Scripts/Weapons/Revolver.cs` - Revolver weapon implementation
- `Scripts/AbstractClasses/BaseWeapon.cs` - Base weapon class with CanFire and _fireTimer
- `resources/weapons/RevolverData.tres` - Revolver configuration (FireRate = 2.0)
