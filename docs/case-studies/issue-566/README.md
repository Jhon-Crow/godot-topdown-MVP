# Case Study: Issue #566 - ASVK Bolt Cycling on Empty Magazine

## Issue Summary

**Issue**: [#566](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/566)
**Title**: fix ASVK reload bolt chambering from empty magazine
**Reporter**: Jhon-Crow (repository owner)

**Original description (Russian)**:
> зарядка при пустом магазине не считается, когда будет заряжен новый магазин всё равно надо будет заново заряжать патрон, хотя при этом новая гильза не выбросится.

**Translation**:
> Bolt cycling with an empty magazine doesn't count; when a new magazine is loaded you still need to cycle the bolt again, although a new casing should not be ejected.

## Root Cause Analysis

### The Bug

The ASVK sniper rifle uses a manual 4-step bolt-action sequence: Left (unlock bolt) -> Down (extract/eject casing) -> Up (chamber round) -> Right (close bolt). The bolt cycling was completing successfully even when the magazine was empty (0 ammo), setting the bolt to "Ready" state despite no round being chambered.

### Scenario

1. Player fires all 5 rounds from ASVK magazine
2. After last shot, bolt is in `NeedsBoltCycle` state, `CurrentAmmo = 0`
3. Player cycles bolt (Left -> Down -> Up -> Right) on **empty** magazine
4. **Bug**: Bolt transitions to `Ready` state even though no round was chambered
5. Player reloads new magazine (R-F-R sequence)
6. **Bug**: Player can fire immediately because bolt is already "Ready"
7. **Expected**: Player should NOT be able to fire until bolt is cycled again with ammo available

### Additional Bug

When cycling the bolt on empty magazine, a shell casing was ejected at step 2 (extract casing). This is correct for the FIRST bolt cycle after firing (ejecting the spent casing), but if the bolt needs to be cycled again after reload, NO casing should be ejected since there's nothing in the chamber.

## Timeline of Events

### Initial Attempt (Incorrect Fix)

The first fix attempt misunderstood the issue. It added `InstantReload()` and `FinishReload()` overrides that called `ResetBolt()` after reload, which set the bolt to "Ready" state. This was the **opposite** of what was needed:
- The fix assumed: "After reload, bolt should automatically chamber a round"
- The actual issue: "Bolt cycling on empty magazine shouldn't count as chambering"

### Owner's Feedback

From PR #573 comment:
> не вижу изменений. всё ещё после зарядки из пустого магазина и вставления полного можно стрелять, а не должно

Translation: "I don't see changes. Still after charging from empty magazine and inserting a full one, you can fire, but you shouldn't be able to."

### Correct Fix

The fix addresses two behaviors:

1. **Bolt step 4 (close bolt)**: When bolt cycle completes, check if `CurrentAmmo > 0`. If no ammo, set bolt back to `NeedsBoltCycle` instead of `Ready` -- the bolt cycling doesn't count because no round was actually chambered.

2. **Bolt step 2 (extract casing)**: Track whether there's a spent casing to eject using `_hasCasingToEject` flag. Only eject a casing if there's one (after firing). When cycling bolt again after reload on a previously empty chamber, no casing is ejected.

## Game Logs Analysis

### Log 1 (`game_log_20260207_152509.txt`)
- Player selects ASVK sniper rifle
- Fires 5 shots (lines 446-465)
- Reload animation plays (lines 470-476): GrabMagazine -> InsertMagazine -> PullBolt -> ReturnIdle
- Fires again immediately after reload (line 479) -- demonstrates the bug

### Log 2 (`game_log_20260207_152616.txt`)
- Player tests with sniper rifle
- Fires 7 consecutive shots (lines 810-836) with no reload animation between them
- This confirms the bolt cycling was being bypassed after reload

## Files Changed

- `Scripts/Weapons/SniperRifle.cs`:
  - Added `_hasCasingToEject` flag to track spent casing state
  - Modified bolt step 2 to conditionally eject casing based on flag
  - Modified bolt step 4 to check `CurrentAmmo` before transitioning to Ready
  - Set `_hasCasingToEject = true` after firing
  - Removed incorrect `InstantReload()` / `FinishReload()` overrides
  - Removed incorrect `ResetBolt()` method

## Expected Behavior After Fix

### Scenario 1: Normal fire-reload-fire cycle (magazine NOT empty)
1. Fire shot -> bolt NeedsBoltCycle, ammo = 4
2. Cycle bolt (L-D-U-R) -> casing ejected at step 2, bolt Ready at step 4 (ammo > 0)
3. Fire again -> works normally

### Scenario 2: Fire all rounds, cycle bolt, reload (magazine empty)
1. Fire last shot -> bolt NeedsBoltCycle, ammo = 0
2. Cycle bolt (L-D-U-R) -> casing ejected at step 2, bolt stays NeedsBoltCycle at step 4 (ammo = 0)
3. Reload new magazine (R-F-R) -> ammo refilled, bolt still NeedsBoltCycle
4. Cycle bolt again (L-D-U-R) -> NO casing ejected at step 2, bolt Ready at step 4 (ammo > 0)
5. Fire -> works
