# Case Study: Issue #53 - Hotline Miami-Style Scoring System

## Issue Summary
**Issue**: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/53
**Title**: Add score calculation after level clear (Russian: "добавить подсчёт очков после зачистки уровня")
**Original Request**: Score should depend on combo, completion time, damage taken, ammo accuracy, and aggressiveness. Reference: Hotline Miami 1 and 2 scoring system.

## Timeline of Events

### Initial Implementation (Commit f9958df)
The scoring system was initially implemented with:
- Combo system (2.5s window, quadratic scaling)
- Time bonus (up to 9000 points, decaying over 300s)
- Accuracy bonus (100 points per percentage)
- Aggressiveness bonus (based on kills per minute)
- Damage penalty (-500 points per hit)
- Grade system (A+/A/B/C/D/F)

### User Feedback (PR #127 Comment)
User reported several issues:
1. Need S rank (higher than A+)
2. Accuracy should be worth more, time bonus worth less (keep same total)
3. Enemy count tracking broken - game doesn't end after killing all enemies
4. Ammo counter broken
5. Need option to hide score-related UI in settings (ESC menu)
6. Combo UI not working

## Root Cause Analysis

### Issue 1: Missing S Rank
**Root Cause**: Initial implementation only had A+ as highest rank (90%+ threshold)
**Fix**: Added S rank with 95%+ threshold, adjusted other thresholds (A+ to 88%, A to 78%)

### Issue 2: Scoring Balance
**Root Cause**: Time bonus was weighted too heavily (9000 max) compared to accuracy (10000 max at 100%)
**Fix**: Reduced TIME_BONUS_MAX from 9000 to 5000, increased ACCURACY_POINTS_PER_PERCENT from 100 to 150

### Issue 3: Enemy Count Not Working
**Investigation**:
- Game log shows all 10 enemies died and `died` signal was emitted
- SoundPropagation correctly unregistered all listeners
- No error messages in log
- Level script's `_on_enemy_died` handler may not be receiving signals

**Potential Causes**:
1. Signal connection timing issue
2. Path to enemies node incorrect
3. `destroy_on_death` interaction

**Diagnostic Additions**:
- Added logging to `_setup_enemy_tracking()` and `_on_enemy_died()`
- Added warning when `Environment/Enemies` node not found
- Added duplicate connection check to prevent issues

### Issue 4: Ammo Counter
**Investigation**:
- Code connects to C# weapon's `AmmoChanged` signal
- Initial display fetches `CurrentAmmo` and `ReserveAmmo` properties
- Signal should update on each fire

**Potential Causes**:
1. Weapon signals not being emitted
2. Signal parameters mismatch
3. Initial state not being set correctly

### Issue 5: Missing Score UI Toggle
**Root Cause**: No settings menu existed to control UI visibility
**Fix**:
- Created SettingsMenu.tscn and settings_menu.gd
- Added `score_ui_visible` variable and `score_ui_visibility_changed` signal to GameManager
- Added Settings button to PauseMenu
- Level scripts now connect to visibility signal and respect setting

### Issue 6: Combo UI Not Working
**Investigation**:
- `combo_changed` signal is emitted from ScoreManager
- Level script connects to signal in `_setup_score_tracking()`
- `_is_tracking` must be true for kills to register

**Code Flow**:
1. `_setup_score_tracking()` calls `score_manager.reset_for_new_level()`
2. This sets `_is_tracking = true`
3. When enemy dies, level script calls `score_manager.register_kill()`
4. This emits `combo_changed` signal
5. Level script's `_on_combo_changed()` updates UI

## Technical Details

### Files Modified
1. `scripts/autoload/score_manager.gd` - S rank threshold, scoring balance
2. `scripts/autoload/game_manager.gd` - Score UI visibility toggle
3. `scripts/levels/building_level.gd` - Logging, visibility support, S rank color
4. `scripts/levels/test_tier.gd` - Same changes as building_level.gd
5. `scripts/ui/pause_menu.gd` - Settings button integration
6. `scenes/ui/PauseMenu.tscn` - Added Settings button

### Files Added
1. `scripts/ui/settings_menu.gd` - Settings menu controller
2. `scenes/ui/SettingsMenu.tscn` - Settings menu scene

### Scoring Constants (After Rebalancing)
```gdscript
const BASE_KILL_POINTS: int = 100        # Unchanged
const COMBO_MULTIPLIER_BASE: int = 50    # Unchanged
const TIME_BONUS_MAX: int = 5000         # Changed from 9000
const ACCURACY_POINTS_PER_PERCENT: int = 150  # Changed from 100
const AGGRESSIVENESS_BONUS_MAX: int = 5000    # Unchanged
const DAMAGE_PENALTY_PER_HIT: int = 500       # Unchanged

const GRADE_THRESHOLDS: Dictionary = {
    "S": 0.95,    # NEW - 95%+ (perfect play)
    "A+": 0.88,   # Changed from 0.90
    "A": 0.78,    # Changed from 0.80
    "B": 0.65,    # Unchanged
    "C": 0.50,    # Unchanged
    "D": 0.35,    # Unchanged
}
```

## User Log Analysis

### Key Observations from game_log_20260118_153026.txt
- **Game Start**: 15:30:26
- **First Kill**: 15:30:34 (Enemy3)
- **Last Kill**: 15:31:13 (Enemy8)
- **Total Enemies**: 10 (all died)
- **Game End**: 15:31:49 (36 seconds after last kill)

### Evidence from Log
```
[15:30:34] [ENEMY] [Enemy3] Enemy died
...
[15:31:13] [ENEMY] [Enemy8] Enemy died
[15:31:13] [INFO] [SoundPropagation] Unregistered listener: Enemy8 (remaining: 0)
```

The log confirms:
1. All enemies died
2. `died` signal was emitted for each
3. SoundPropagation correctly tracked deaths
4. No victory message appeared in log

## Recommendations

1. **Testing Required**: The added logging will help identify the exact failure point in enemy tracking
2. **Signal Debugging**: Consider adding `CONNECT_DEFERRED` flag to signal connections
3. **Initialization Order**: Verify level script `_ready()` completes before any enemy can die
4. **Ammo Investigation**: Add logging to weapon signal connections to verify they work

## Related Resources
- [Hotline Miami Scoring Analysis](https://steamcommunity.com/app/219150/discussions/) (reference)
- Godot Signal Documentation
- GDScript/C# Interop Best Practices
