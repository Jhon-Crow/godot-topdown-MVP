# Case Study: Issue #744 - Trajectory Glasses Active Item

## Issue Summary

**Request**: Add a new active item "Trajectory Glasses" (очки траекторий) that shows ricochet trajectories when activated.

**Specifications**:
- 2 charges per battle
- 10 seconds activation time per charge
- Shows unlimited ricochet bounces as laser sight
- Green laser = valid ricochet angle
- Red laser = impossible ricochet (angle too steep)
- Replaces built-in weapon lasers when active
- Uses existing ricochet calculation code from bullet.gd

## Timeline of Events

### Initial Implementation (PR #746)

1. Created `TRAJECTORY_GLASSES` enum in ActiveItemManager
2. Implemented `trajectory_glasses_effect.gd` with:
   - Charge management (2 charges)
   - Duration timer (10 seconds)
   - Line2D trajectory visualization
   - Ricochet calculation using physics raycasting
   - Weapon laser hiding/restoration
3. Implemented `trajectory_glasses_hud.gd` for charge/timer display
4. Added player initialization and input handling in `player.gd`
5. Created unit tests in `test_trajectory_glasses.gd`
6. Created placeholder icon (copied from homing bullets - **BUG**)

### User Testing (2026-02-10 23:12)

User @Jhon-Crow tested the build and reported two issues:

**Bug #1: Wrong Icon**
- Trajectory glasses icon was identical to homing bullets icon
- Expected: Glasses with green lenses and crosshair on one lens

**Bug #2: Item Not Working**
- User selected Trajectory Glasses in armory
- Pressed Space key to activate
- No effect visible (no laser, no trajectory visualization)

## Root Cause Analysis

### Bug #1: Wrong Icon

**Cause**: During initial implementation, a placeholder icon was created by copying `homing_bullets_icon.png` to `trajectory_glasses_icon.png`. This was intended as temporary but was committed as-is.

**Evidence**: Both files had identical MD5 checksums:
```
e2007988e26a84296d8e70028fb38849  trajectory_glasses_icon.png
e2007988e26a84296d8e70028fb38849  homing_bullets_icon.png
```

**Fix**: Created a new proper icon showing glasses with green lenses and red crosshair on one lens using Python PIL.

### Bug #2: Item Not Working

**Cause**: Merge conflict with upstream/main (Issue #700 - Active Item Progress Bar) broke the initialization code.

**Analysis of game log** (`game_log_20260210_231250.txt`):

Line 558 shows the item was selected:
```
[23:13:00] [INFO] [ActiveItemManager] Active item changed from None to Trajectory Glasses
```

After level restart (lines 606-610), other active items log their initialization status:
```
[23:13:00] [INFO] [Player.Flashlight] No flashlight selected in ActiveItemManager
[23:13:00] [INFO] [Player.TeleportBracers] No teleport bracers selected in ActiveItemManager
[23:13:00] [INFO] [Player.Homing] No homing bullets selected in ActiveItemManager
[23:13:00] [INFO] [Player.InvisibilitySuit] No invisibility suit selected in ActiveItemManager
[23:13:00] [INFO] [Player.BreakerBullets] Breaker bullets not selected in ActiveItemManager
```

**Missing log entry**: There is NO `[Player.TrajectoryGlasses]` log entry at all!

This confirms the `_init_trajectory_glasses()` function was never called, which means the effect node was never created, so pressing Space did nothing.

**Root cause**: The merge conflict in `player.gd`:

```gdscript
<<<<<<< HEAD
	# Initialize trajectory glasses if active item manager has trajectory glasses selected (Issue #744)
	_init_trajectory_glasses()
=======
	# Initialize active item progress bar (Issue #700)
	_init_active_item_progress_bar()
>>>>>>> upstream/main
```

The user tested a build where this conflict was either:
1. Unresolved (syntax error preventing load), or
2. Resolved incorrectly (choosing one side, losing the other)

The same conflict pattern appeared at the end of the file where both the trajectory glasses code section AND the active item progress bar code section conflicted.

**Fix**: Resolved the merge conflict by keeping BOTH code sections:
- Both initialization calls in `_ready()`
- Both feature implementations at end of file

## Files Modified

| File | Change |
|------|--------|
| `scripts/characters/player.gd` | Resolved merge conflict - kept both trajectory glasses AND progress bar code |
| `assets/sprites/weapons/trajectory_glasses_icon.png` | Replaced with proper glasses icon |
| `experiments/create_trajectory_glasses_icon.py` | Added script to generate icon |

## Lessons Learned

1. **Test after merge**: Always test functionality after merging with upstream, especially when conflicts are resolved.

2. **Placeholder assets are dangerous**: If creating placeholder assets, mark them clearly (e.g., `trajectory_glasses_icon_PLACEHOLDER.png`) or add TODO comments.

3. **Log analysis is powerful**: The absence of expected log messages (`[Player.TrajectoryGlasses]`) quickly identified that initialization code wasn't running.

4. **Merge conflicts need careful resolution**: When resolving merge conflicts, consider whether BOTH sides of the conflict should be kept (additive changes) vs choosing one side.

## Testing Verification

After fixes:
- C# build: SUCCESS
- Merge conflicts: RESOLVED (0 conflict markers)
- Icon: Updated to proper glasses design
- Code path: `_init_trajectory_glasses()` now called alongside `_init_active_item_progress_bar()`

## Related Files

- `game_log_20260210_231250.txt` - Original game log showing the bug
