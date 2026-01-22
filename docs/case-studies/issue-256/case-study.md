# Case Study: Issue #256 - Grenade Throwing Physics Change Not Applied

## Summary
User reported that the velocity-based grenade throwing physics changes were not applied to the game build they tested. The root cause was identified as the C# Player.cs script still using the legacy drag-based throwing system, while only the GDScript player.gd was updated with velocity-based physics.

## Timeline of Events

### 2026-01-22 17:46:27 - Initial Implementation (Commit e39784b)
- Commit `e39784b` created: "Implement realistic velocity-based grenade throwing physics"
- Changes applied to **GDScript** files:
  - `scripts/characters/player.gd` (134 changes) - Velocity-based throwing
  - `scripts/projectiles/grenade_base.gd` (57 changes) - Added `throw_grenade_velocity_based()` method
  - `scenes/projectiles/FlashbangGrenade.tscn` (+3 lines)
  - `scenes/projectiles/FragGrenade.tscn` (+3 lines)
  - `tests/unit/test_grenade_base.gd` (143 changes)
- **MISSING**: `Scripts/Characters/Player.cs` was NOT updated

### 2026-01-22 19:59:17 - 19:59:59 (User Testing Session 1)
- User tested the game (Godot 4.3-stable)
- Log evidence shows OLD system was running (C# Player.cs code path)

### 2026-01-22 21:07:03 - 21:07:46 (User Testing Session 2)
- User confirmed build was updated with latest code
- Log evidence STILL shows OLD system running:

```
[21:07:12] [INFO] [GrenadeBase] LEGACY throw_grenade() called! Direction: (0.996999, 0.077419), Speed: 2484.6 (unfrozen)
[21:07:12] [INFO] [GrenadeBase] NOTE: Using DRAG-BASED system. If velocity-based is expected, ensure grenade has throw_grenade_velocity_based() method.
```

- Grenade traveled far even when mouse was stationary at release (user complaint)
- This confirms the **C# code path** was being executed, not the GDScript

## Root Cause Analysis

### Primary Finding: Dual Implementation (GDScript vs C#)

The project has TWO player implementations:
1. **`scripts/characters/player.gd`** - GDScript version (velocity-based updated)
2. **`Scripts/Characters/Player.cs`** - C# version (legacy drag-based, NOT updated)

**The game is using the C# implementation**, which explains why:
- Velocity-based changes in player.gd were not being executed
- Legacy `throw_grenade()` was being called instead of `throw_grenade_velocity_based()`
- Grenade flew far even when mouse was stopped (drag-based behavior)

### Evidence from Logs (game_log_20260122_210703.txt)

1. **Line 116-119**: Legacy system log messages
```
[21:07:12] [INFO] [Player.Grenade] Throwing! Direction: (0.9969986, 0.07741881), Drag: 138,03435 (adjusted: 1242,3091)
[21:07:12] [INFO] [GrenadeBase] LEGACY throw_grenade() called!
```

2. **Velocity-based log format (expected but not seen)**:
```
[Player.Grenade] Velocity-based throw! Mouse velocity: (X, Y) (Z px/s), Swing distance: N
```

### Technical Details

In `Player.cs:1927-1929` (before fix):
```csharp
if (_activeGrenade.HasMethod("throw_grenade"))
{
    _activeGrenade.Call("throw_grenade", throwDirection, adjustedDragDistance);
}
```

The C# code was calling the legacy `throw_grenade()` method with **drag distance**, NOT `throw_grenade_velocity_based()` with **mouse velocity**.

## Solution Applied (Commit TBD)

### Changes to Scripts/Characters/Player.cs:

1. **Added velocity tracking fields**:
   - `_mouseVelocityHistory` - List of last 5 velocity samples for smoothing
   - `_currentMouseVelocity` - Calculated mouse velocity (pixels/second)
   - `_totalSwingDistance` - Accumulated swing distance for momentum transfer
   - `_prevFrameTime` - For delta time calculation

2. **Updated `UpdateWindUpIntensity()`** to track:
   - Instantaneous mouse velocity each frame
   - Smoothed velocity using history
   - Total swing distance

3. **Updated `ThrowGrenade()`** to use velocity-based physics:
   - Determines throw direction from mouse velocity (not drag)
   - Calls `throw_grenade_velocity_based(releaseVelocity, swingDistance)`
   - Falls back to legacy only if velocity method unavailable

4. **Updated `ResetGrenadeState()`** to clear velocity tracking

5. **Updated debug trajectory visualization** to use velocity-based calculations

6. **Added startup log**: `[Player.Grenade] Throwing system: VELOCITY-BASED (v2.0)`

## Log Files in This Case Study

| File | Duration | Notes |
|------|----------|-------|
| `game_log_20260122_195917.txt` | 4 seconds | Game initialization only |
| `game_log_20260122_195927.txt` | 32 seconds | 4 throws, all using drag-based system |
| `game_log_20260122_210703.txt` | 43 seconds | 8+ throws, confirmed C# code path, legacy system |

## Key Learnings

1. **Dual implementations require sync**: When a project has both GDScript and C# implementations, both must be updated when changing behavior.

2. **Log messages are critical**: The debug logging in grenade_base.gd correctly identified that the legacy method was being called, helping diagnose the issue.

3. **Always verify the code path**: The logs clearly showed `LEGACY throw_grenade() called!` which pointed directly to the root cause.

## Verification Steps

After applying this fix:
1. Rebuild the Godot project (including C# rebuild)
2. Launch the game and check logs for:
   ```
   [Player.Grenade] Throwing system: VELOCITY-BASED (v2.0 - mouse velocity at release)
   ```
3. Test grenade throw with mouse stopped at release - grenade should drop at feet
4. Test grenade throw with fast mouse movement at release - grenade should fly far
5. Verify debug trajectory updates based on mouse velocity (not drag distance)
