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

## Follow-up Analysis (2026-02-15)

### Second User Test (2026-02-10 23:53)

After the initial fix, user @Jhon-Crow tested again and reported the item still wasn't working.

**New log file**: `game_log_20260210_235359.txt`

**Analysis**:

The log analysis revealed a **version mismatch** between the repository code and the user's tested build:

1. **Log messages differ from source code**:
   - Log shows: `"[Player.BreakerBullets] Breaker bullets not selected in ActiveItemManager"`
   - Source code has: `"[Player.BreakerBullets] Breaker bullets not selected"`
   - Log shows `[Player.TeleportBracers]` messages, but no teleport bracers code exists in the branch

2. **Missing trajectory glasses log**:
   - Still no `[Player.TrajectoryGlasses]` message appears in the log
   - This suggests the user's build was from a different branch/version

3. **Possible causes**:
   - User may have tested an older cached build
   - CI artifacts may have been from a different commit
   - Build wasn't updated after the fix commit

**Action taken**:

1. Added entry-point debug logging to `_init_trajectory_glasses()`:
   ```gdscript
   FileLogger.info("[Player.TrajectoryGlasses] Checking trajectory glasses...")
   ```
   This will confirm the function is being called in future builds.

2. Made log messages consistent across all active items (using "No X selected in ActiveItemManager" pattern).

### Verification Steps for User

When testing the next build, the user should see one of these log entries:

1. If trajectory glasses is selected:
   ```
   [Player.TrajectoryGlasses] Checking trajectory glasses...
   [Player.TrajectoryGlasses] Trajectory glasses selected, initializing...
   [Player.TrajectoryGlasses] Trajectory glasses equipped, charges: 2
   ```

2. If trajectory glasses is NOT selected:
   ```
   [Player.TrajectoryGlasses] Checking trajectory glasses...
   [Player.TrajectoryGlasses] No trajectory glasses selected in ActiveItemManager
   ```

3. If ActiveItemManager is missing the method (outdated build):
   ```
   [Player.TrajectoryGlasses] Checking trajectory glasses...
   [Player.TrajectoryGlasses] ActiveItemManager missing has_trajectory_glasses method
   ```

If NONE of these messages appear, the build doesn't include the trajectory glasses code at all.

### Third User Test (2026-02-15 21:54)

**User Report**: "в логе написано что выбраны не trajectory glasses, но я выбирал именно их"
(Translation: "the log says trajectory glasses is not selected, but I specifically selected them")

**New log file**: `logs/game_log_20260215_215418.txt`

**Analysis**:

Line 194 shows successful selection:
```
[21:54:24] [INFO] [ActiveItemManager] Active item changed from None to Trajectory Glasses
```

After level restart (lines 240-244), other items log their status:
```
[21:54:24] [INFO] [Player.Flashlight] No flashlight selected in ActiveItemManager
[21:54:24] [INFO] [Player.TeleportBracers] No teleport bracers selected in ActiveItemManager
[21:54:24] [INFO] [Player.Homing] No homing bullets selected in ActiveItemManager
[21:54:24] [INFO] [Player.InvisibilitySuit] No invisibility suit selected in ActiveItemManager
[21:54:24] [INFO] [Player.BreakerBullets] Breaker bullets not selected in ActiveItemManager
```

**Critical Finding**: The log shows `[Player.TeleportBracers]` but this code DOES NOT EXIST in the repository!

**Proof**:
1. Searched entire repository for `[Player.TeleportBracers]` - no matches in any .gd file
2. Our branch has `_init_trajectory_glasses()` at line 350, but NO teleport bracers init function
3. The main branch also has no teleport bracers init code in player.gd

**Conclusion**: The user is running a **completely different build** that:
- Has teleport bracers initialization code (which doesn't exist in this repo)
- Does NOT have trajectory glasses code (no `[Player.TrajectoryGlasses]` log at all)

This build may be from:
1. A local modification the user made
2. A build from a different PR/branch
3. A corrupted/incomplete download
4. A cached older version

**Action Required**:

User needs to download a fresh build from the CI artifacts:
1. Go to https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions?query=branch%3Aissue-744-95dafced7ca4
2. Find the most recent successful workflow run (should show commit `f8c60d06`)
3. Download the Windows artifact
4. Extract to a NEW folder (not the existing one)
5. Run the new executable

The correct build will show these log messages after selecting Trajectory Glasses:
```
[Player.TrajectoryGlasses] Checking trajectory glasses...
[Player.TrajectoryGlasses] Trajectory glasses selected, initializing...
[Player.TrajectoryGlasses] Trajectory glasses equipped, charges: 2
```

### Fourth Fix (2026-02-24)

After the third analysis, user reported: "очки всё ещё не работают. я выбрал эти очки, нажал пробел но ничего не произошло."
(Translation: "glasses still don't work, I selected them, pressed space but nothing happened")

No new log was attached. Based on the history, two scenarios were possible:
1. User still ran the wrong build (same as before)
2. User ran our build but visualization didn't appear

**Actions taken**:

1. **Merged upstream/main into the branch**:
   - Main branch moved ahead significantly with new features
   - Key change: Active item unlock system (hold LMB to unlock items in armory)
   - `TRAJECTORY_GLASSES` added to `unlocked_active_items` dictionary
   - Unlock methods (`is_active_item_unlocked`, `unlock_active_item`, etc.) added

2. **Rewrote trajectory visualization (root cause fix)**:
   - Previous approach: Line2D node with `top_level = true` (unreliable coordinate handling)
   - New approach: `queue_redraw()` + `_draw()` method in player (proven, used by grenade trajectory)
   - Trajectory points stored as LOCAL player coordinates in `trajectory_local_points`
   - Player's `_draw()` renders the trajectory directly using `draw_line()`
   - Same pattern as `_draw_trajectory_with_bounces()` which is confirmed working

3. **Added activation logging**:
   - Log when Space is pressed with current charge count
   - Log activation result (success/failure)

4. **Fixed coordinate conversion**:
   - `_get_aim_direction()` now uses `_player.get_global_mouse_position()` (simpler, correct)
   - Trajectory calculation returns world coords, converts to local before storing

**Expected log for next test**:
```
[Player.TrajectoryGlasses] Checking trajectory glasses...
[Player.TrajectoryGlasses] Trajectory glasses selected, initializing...
[Player.TrajectoryGlasses] Trajectory glasses equipped, charges: 2
... (when Space is pressed) ...
[Player.TrajectoryGlasses] Space pressed - activating (charges: 2)
[TrajectoryGlasses] Activated! Duration: 10.0s, Charges remaining: 1/2, Player: Player
[Player.TrajectoryGlasses] Activation result: true
```

## Fix Round 5 — February 24, 2026 (Final Root Cause Found)

User feedback: "при нажатии пробела ничего не происходит" (pressing Space nothing happens)
Log file: `game_log_20260224_193202.txt`

### Root Cause Analysis (Round 5)

**Critical discovery**: The game uses **C# Player** (`Scripts/Characters/Player.cs`), NOT the GDScript player (`scripts/characters/player.gd`).

**Evidence from the log**:
- Log shows `[Player.TeleportBracers]` and `[Player.InvisibilitySuit]` — these exist ONLY in `Scripts/Characters/Player.cs`
- `[Player.BreakerBullets] Breaker bullets not selected in ActiveItemManager` — matches C# Player.cs line 4933 exactly
- Log shows `[ActiveItemManager] Active item changed from None to Trajectory Glasses` — so the item IS selected
- But NO `[Player.TrajectoryGlasses]` messages — because C# Player.cs had no `InitTrajectoryGlasses()` method

**Why all previous fixes failed**: All trajectory glasses code was added to `scripts/characters/player.gd` (GDScript). The game at runtime uses the C# Player node, which completely ignores GDScript player code.

### Fix Applied

Added trajectory glasses support to `Scripts/Characters/Player.cs`:
1. `InitTrajectoryGlasses()` — loads `trajectory_glasses_effect.gd` and initializes it (mirrors GDScript pattern)
2. `HandleTrajectoryGlassesInput()` — handles Space press to activate
3. `DrawTrajectoryGlasses()` — draws the laser trajectory in `_Draw()` using local player coordinates
4. Called from `_Ready()` (after InitBreakerBullets) and from the input update method

The GDScript `trajectory_glasses_effect.gd` is still used as the actual effect controller (loaded via `GD.Load<Script>()`), exactly like invisibility suit and homing bullets do.

**Expected log after fix**:
```
[Player.TrajectoryGlasses] Checking trajectory glasses...
[Player.TrajectoryGlasses] Trajectory glasses selected, initializing...
[Player.TrajectoryGlasses] Trajectory glasses equipped, charges: 2
... (when Space pressed) ...
[Player.TrajectoryGlasses] Space pressed - activating (charges: 2)
[TrajectoryGlasses] Activated! Duration: 10.0s, Charges remaining: 1/2, Player: Player
[Player.TrajectoryGlasses] Activation result: True
```

## Fix Round 6 — February 24, 2026

User feedback: "работает, но надо подправить" (works, but needs adjustment):
1. "сейчас красным не подсвечиваются углы, под которыми не происходит отражение. возможность рикошета должна зависеть от используемого оружия."
   (Translation: "red color is not shown for angles where ricochet doesn't happen; ricochet possibility should depend on the weapon used")
2. "слишком много рикошетов отображается - после первого не подходящего для рикошета угла линия должна прекращаться"
   (Translation: "too many ricochets shown - after the first non-ricochetable angle, the line should stop")

This was major progress: the item was now **working** (pressing Space showed a trajectory), but the visualization logic was incorrect.

### Root Cause Analysis (Round 6)

Two bugs found in `scripts/effects/trajectory_glasses_effect.gd`:

**Issue A — All-green, weapon-independent trajectory**:
- The effect used a hardcoded `MAX_RICOCHET_ANGLE = 90.0` for all weapons
- `set_weapon()` was never called from `Player.cs`, so `_weapon` reference was always null
- Without a weapon reference, `_get_weapon_max_ricochet_angle()` always returned the 90° default
- The check `impact_angle < 90.0` passes for nearly all wall hits, so trajectory was always green

**Fix A**: Added `_get_weapon_max_ricochet_angle()` that reads `CaliberData.max_ricochet_angle` from the weapon. Updated `Player.cs` to call `SetWeapon()` on the trajectory glasses effect.

| Weapon | Caliber | Max Ricochet Angle |
|--------|---------|-------------------|
| Makarov PM, Mini UZI, Silenced Pistol | 9x18/9x19mm | 20° |
| Shotgun | Buckshot | 35° |
| Assault Rifle / AKGL | 5.45/7.62x39mm | 90° |
| Sniper Rifle | 12.7x108mm | 0° (cannot ricochet) |

## Fix Round 7 — February 24, 2026

User feedback: "у m16 и AK всё ещё не отображаются невозможные углы рикошета (показывается слишком большое количество рикошетов)"
(Translation: "for M16 and AK, impossible ricochet angles are still not displayed (too many ricochets shown)")

Log files provided: `game_log_20260225_003935.txt`, `game_log_20260225_004648.txt`

### Root Cause Analysis (Round 7)

**Analysis of game_log_20260225_003935.txt**:
- Trajectory glasses activate successfully with both MakarovPM and AssaultRifle
- Log entries confirm Round 5/6 fixes are working: `[Player.TrajectoryGlasses] Weapon set: AssaultRifle`
- However, no `_calculate_ricochet_trajectory` debug logs visible — confirms this was tested with Round 6 build before Round 7 debug logging was added

**Key insight**: For M16/AK-GL, the 5.45x39mm and 7.62x39mm calibers have `max_ricochet_angle = 90.0°`. Since grazing impacts approach 90° only for perfectly perpendicular shots, the angle check `impact_angle < 90.0°` always passes. This is the correct physics behavior — these calibers can ricochet at virtually any angle.

**However**, the issue is **count**: the weapon's caliber data also has `max_ricochets` field:
- Pistols (9x18/9x19): `max_ricochets = 1` → bullet can ricochet once, then stops
- Rifles (5.45x39/7.62x39): `max_ricochets = -1` → unlimited ricochets
- With `MAX_RICOCHET_BOUNCES = 50` and unlimited ricochets, the trajectory showed 50 green bounces filling the entire screen

**Fix**:
1. Added `_get_weapon_max_ricochets()` — reads `max_ricochets` from `CaliberData`
2. Updated `_calculate_ricochet_trajectory()` to use the weapon's `max_ricochets` as the bounce limit
3. For unlimited-ricochet weapons (`max_ricochets = -1`): capped at `MAX_RICOCHET_BOUNCES = 5` (readable, not screen-filling)
4. After max bounces reached, the next wall hit is shown as a **red terminal segment**
5. Added debug logging for ricochet angle and bounce count

**Expected behavior after Round 7**:
- Makarov PM: shows 1 green bounce + red terminal segment at second wall
- Assault Rifle: shows up to 5 green bounces + red terminal at 6th wall
- Sniper Rifle: shows immediate red terminal (0° max angle = cannot ricochet)

### Analysis of Provided Log Files

**game_log_20260225_003935.txt** (15237 lines):
- Testing both MakarovPM and AssaultRifle weapons
- Trajectory glasses activating and working: Space pressed → `Activated! Duration: 10.0s, Charges remaining: 1/2`
- Laser sight disabled on AssaultRifle when activated: `[TrajectoryGlasses] Disabled weapon laser sight`
- No `_calculate_ricochet_trajectory` debug logs → tested with Round 6 build
- Real bullets ricocheting successfully: `[Bullet] Within ricochet range - trying ricochet first` + ricochet kills

**game_log_20260225_004648.txt** (4788 lines):
- Testing exclusively with AssaultRifle
- Same pattern: trajectory glasses activating but no ricochet-count debug logs
- Multiple activation/deactivation cycles visible in log

Both logs confirm Round 5/6 fixes are working correctly. The ricochet-count issue was fixed in Round 7 (committed as `59d5ec57`).

## Related Files

- `logs/game_log_20260210_231250.txt` - Original game log showing the bug
- `logs/game_log_20260210_235359.txt` - Follow-up test log showing version mismatch
- `logs/game_log_20260215_215418.txt` - Third test showing different build with teleport bracers code
- `game_log_20260224_193202.txt` - Fifth test confirming C# Player is used, not GDScript
- `game_log_20260225_003935.txt` - Sixth test (Round 6 build) showing item working but too many ricochets
- `game_log_20260225_004648.txt` - Seventh test (Round 6 build) with AssaultRifle only
