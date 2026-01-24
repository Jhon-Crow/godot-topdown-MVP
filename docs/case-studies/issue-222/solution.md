# Issue 222: Solution Implementation

## Date: 2026-01-22

## Initial Implementation (GDScript)

Originally implemented reload animation in `scripts/characters/player.gd` following the grenade animation pattern.

## Root Cause of Animation Not Visible

**The animation was implemented in the wrong script file.**

The game uses the C# version (`Scripts/Characters/Player.cs`) loaded by `scenes/characters/csharp/Player.tscn`,
but the animation was only added to the GDScript version (`scripts/characters/player.gd`).

**Evidence:** Game log showed `[Player] Ready! Grenades: 1/3` format (C# code)
instead of `[Player] Ready! Ammo: X/Y, Grenades: X/Y, Health: X/Y` format (GDScript code).

See [root-cause-analysis.md](./root-cause-analysis.md) for detailed investigation.

## Solution: Implemented in C# Player.cs

Added the reload animation system to `Scripts/Characters/Player.cs` following the same pattern
as the existing grenade animation system.

### Changes Made to Player.cs

#### 1. Added ReloadAnimPhase Enum
```csharp
private enum ReloadAnimPhase
{
    None,           // Normal arm positions (weapon held)
    GrabMagazine,   // Step 1: Left hand moves to chest to grab new magazine
    InsertMagazine, // Step 2: Left hand brings magazine to weapon, inserts it
    PullBolt,       // Step 3: Character pulls the charging handle
    ReturnIdle      // Arms return to normal weapon-holding position
}
```

#### 2. Animation Position Constants (Updated after feedback)
- `ReloadArmLeftGrab = (-18, -2)` - Left hand at chest/vest magazine pouch
- `ReloadArmLeftInsert = (-4, 2)` - Left hand at weapon magwell (**middle of weapon, not end**)
- `ReloadArmLeftSupport = (-2, 0)` - Left hand holds near magwell during bolt pull
- `ReloadArmRightBoltPull = (-8, -2)` - Right hand pulls charging handle back
- `ReloadArmRightBoltReturn = (4, 2)` - Right hand releases bolt forward

#### 3. Animation Rotation Constants
- `ReloadArmRotLeftGrab = -50°` - Arm rotation when grabbing from chest
- `ReloadArmRotLeftInsert = -10°` - Left arm rotation when inserting
- `ReloadArmRotRightBoltPull = -25°` - Right arm rotation when pulling bolt back
- `ReloadArmRotRightBoltReturn = -5°` - Right arm rotation when releasing bolt

#### 4. Duration Constants
- `ReloadAnimGrabDuration = 0.25s`
- `ReloadAnimInsertDuration = 0.30s`
- `ReloadAnimBoltPullDuration = 0.15s` - Time to pull bolt back
- `ReloadAnimBoltReturnDuration = 0.10s` - Time for bolt to return forward
- `ReloadAnimReturnDuration = 0.20s`

#### 5. New Methods
- `StartReloadAnimPhase(phase, duration)` - Starts a reload animation phase
- `UpdateReloadAnimation(delta)` - Updates animation each frame with smooth interpolation
- `SetReloadAnimZIndex()` - Sets arms z-index below weapon during reload
- `_boltPullSubPhase` field - Tracks back-and-forth bolt motion (0=pull, 1=return)

#### 6. Integration Points
- Modified `_PhysicsProcess()` to call `UpdateReloadAnimation(delta)`
- Modified `_PhysicsProcess()` to skip walk animation during reload animation
- Modified `HandleReloadSequenceInput()` to trigger animation phases:
  - Step 0→1 (R press): Triggers `GrabMagazine`
  - Step 1→2 (F press): Triggers `InsertMagazine`
  - Step 2→complete (R press): Triggers `PullBolt`
- Modified `ResetReloadSequence()` to reset animation to `ReturnIdle`

## Animation Behavior

### Sequence Reload Mode (R-F-R)
Each key press triggers the corresponding animation phase, synchronized with sounds:
1. **R press** → Left arm moves to chest to grab magazine (with mag_out sound)
2. **F press** → Left arm moves to weapon, inserts magazine (with mag_in sound)
3. **R press** → Both arms involved in pulling bolt (with m16_bolt sound)

## Files Modified

| File | Change |
|------|--------|
| `Scripts/Characters/Player.cs` | Added reload animation system (~120 lines) |
| `docs/case-studies/issue-222/root-cause-analysis.md` | Root cause investigation |
| `docs/case-studies/issue-222/logs/game_log_20260122_105528.txt` | User's game log |

## Testing

To test the reload animation:
1. Build the game from the issue branch (uses C# Player.tscn)
2. Start the game and deplete some ammunition
3. Press R to initiate reload (observe left arm moving to chest)
4. Press F to insert magazine (observe left arm moving to weapon)
5. Press R to pull bolt (observe right arm pulling back)
6. Arms should return to normal position after reload completes

## Lessons Learned

1. **Verify which script is being used** - This project has dual implementations (GDScript + C#).
   Check the scene file to confirm which script is loaded.

2. **Use logging to debug** - The game log format mismatch revealed which script was active.

3. **Follow existing patterns** - The grenade animation system provided a template for the
   reload animation, ensuring consistency.

---

## Second Iteration Fixes (Based on User Feedback)

After initial C# implementation, user tested and reported three issues:

### Issue 1: Arms Visible Above Weapon

**User feedback**: "animated hand should be below weapon, not above it"

**Fix**: Added `SetReloadAnimZIndex()` method that sets arm `z_index = 0` during reload animation.
Weapon has `z_index = 1`, so arms now appear behind/below the weapon.

### Issue 2: Magazine Insert Position

**User feedback**: "step 2 animation should end at middle of weapon length, not at the end"

**Fix**: Changed `ReloadArmLeftInsert` from `(8, 2)` to `(-4, 2)`.
The new position places the left hand at the middle of the weapon where the magazine well is located.

### Issue 3: Bolt Pull Motion

**User feedback**: "step 3 should be a movement along the rifle contour, back and forth"

**Fix**: Implemented two-phase bolt pull animation:
- **Sub-phase 0**: Right hand pulls bolt back toward player (`ReloadArmRightBoltPull`)
- **Sub-phase 1**: Right hand releases bolt forward (`ReloadArmRightBoltReturn`)

This creates the realistic back-and-forth motion of operating a rifle charging handle.

## Files Modified (Second Iteration)

| File | Change |
|------|--------|
| `Scripts/Characters/Player.cs` | Z-index fix, position adjustments, bolt pull sub-phases |
| `docs/case-studies/issue-222/root-cause-analysis.md` | Added second round of feedback analysis |
| `docs/case-studies/issue-222/logs/game_log_20260122_111454.txt` | User's second test log |
