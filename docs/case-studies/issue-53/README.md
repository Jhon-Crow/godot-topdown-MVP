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

### Log 1: game_log_20260118_153026.txt
- **Game Start**: 15:30:26
- **First Kill**: 15:30:34 (Enemy3)
- **Last Kill**: 15:31:13 (Enemy8)
- **Total Enemies**: 10 (all died)
- **Game End**: 15:31:49 (36 seconds after last kill)

### Log 2: game_log_20260118_161311.txt (After code update)
- **Game Start**: 16:13:11
- **First Kill**: 16:13:18 (Enemy3)
- **Last Kill**: 16:14:01 (Enemy9)
- **Total Enemies**: 10 (all died)
- **Duration**: ~50 seconds of gameplay

#### Critical Finding from Log 2
**NO output from building_level.gd script at all** - not even the `_ready()` print statements:
```gdscript
func _ready() -> void:
    print("BuildingLevel loaded - Hotline Miami Style")  # NOT IN LOG
    print("Building size: ~2400x2000 pixels")           # NOT IN LOG
```

This confirms the root cause: **The user is running an old exported build that doesn't contain the updated scripts.**

Evidence:
1. Log shows `Debug build: false` - running from export, not editor
2. Executable path: `I:/Загрузки/godot exe/Godot-Top-Down-Template.exe`
3. No `[BuildingLevel]` log entries at all
4. No print statements from `_ready()` function
5. All enemy deaths logged correctly by enemy.gd (which hasn't changed significantly)

### Evidence from Log 1
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

## Root Cause Conclusion

### Primary Issue: Stale Export Build
The user is testing with an exported executable that was built BEFORE the code updates were made. The export needs to be regenerated to include:
1. Updated building_level.gd with enemy tracking fixes
2. Updated game_manager.gd with score UI visibility
3. New settings menu files

### Verification Steps for User
1. Re-export the project using Godot's Export feature
2. Run the new export and check for `[BuildingLevel]` log entries
3. Verify that settings menu appears in pause menu (ESC)

## Additional Fixes Applied

### User Request: Score UI Hidden by Default
Changed `score_ui_visible` default from `true` to `false` in GameManager:
```gdscript
var score_ui_visible: bool = false  # Was: true
```

This means:
- Timer, combo counter, and running score are hidden by default
- User can enable them via Settings menu in pause screen
- Final score breakdown still shows on level completion

## Recommendations

1. **Re-export the game** to include all code updates
2. **Testing Required**: Run from the new export to verify enemy tracking works
3. **Signal Debugging**: If issues persist after re-export, consider adding `CONNECT_DEFERRED` flag
4. **Initialization Order**: Verify level script `_ready()` completes before any enemy can die
5. **Ammo Investigation**: Add logging to weapon signal connections to verify they work

## Update 2026-01-21: Ricochet and Wall Penetration Scoring

### User Request
User comment (translated from Russian): "also reward using ricochets and wall penetrations only in combination with aggressive play. Add scoring for the new functionality."

The request specifically requires that these bonuses should ONLY be awarded when playing aggressively (fast-paced), aligning with Hotline Miami's philosophy of rewarding skilled, aggressive play.

### New Features Implemented

#### Ricochet Kill Bonus
- **Base Bonus**: +300 points per ricochet kill
- **Requirement**: Player must maintain aggressive play (≥15 kills/minute)
- **How it works**: When a bullet ricochets off a wall and kills an enemy, the kill is tracked as a ricochet kill

#### Wall Penetration Kill Bonus
- **Base Bonus**: +250 points per penetration kill
- **Requirement**: Player must maintain aggressive play (≥15 kills/minute)
- **How it works**: When a bullet penetrates through a wall and kills an enemy, the kill is tracked as a penetration kill

### Technical Implementation

#### Data Flow
1. **bullet.gd** tracks `_has_ricocheted` and `_has_penetrated` flags
2. When bullet hits an enemy via **hit_area.gd**, it calls `on_hit_extended()` with these flags
3. **enemy.gd** stores `_last_hit_was_ricochet` and `_last_hit_was_penetration`
4. On death, **enemy.gd** emits `died(is_ricochet_kill, is_penetration_kill)` signal
5. **building_level.gd** receives signal and calls `score_manager.register_kill_extended()`
6. **score_manager.gd** calculates aggressiveness and awards bonuses if threshold met

#### New Constants in score_manager.gd
```gdscript
const RICOCHET_KILL_BASE_BONUS: int = 300
const RICOCHET_MIN_AGGRESSIVENESS: float = 15.0  # kills per minute

const PENETRATION_KILL_BASE_BONUS: int = 250
const PENETRATION_MIN_AGGRESSIVENESS: float = 15.0  # kills per minute
```

#### Aggressiveness Gate
The aggressiveness check ensures bonuses reward skilled play:
```gdscript
var current_aggressiveness := 0.0
if elapsed_time > 0.0:
    current_aggressiveness = (float(_total_kills_for_aggressiveness) / elapsed_time) * 60.0

if is_ricochet_kill and current_aggressiveness >= RICOCHET_MIN_AGGRESSIVENESS:
    # Award ricochet bonus
```

### Files Modified
1. **scripts/projectiles/bullet.gd** - Pass ricochet/penetration flags via `on_hit_extended()`
2. **scripts/objects/hit_area.gd** - Forward extended hit info to parent enemy
3. **scripts/objects/enemy.gd** - Track last hit type, emit via updated `died` signal
4. **scripts/autoload/score_manager.gd** - Calculate and track ricochet/penetration bonuses
5. **scripts/levels/building_level.gd** - Display bonuses in victory screen

### Victory Screen Display
The victory screen now shows:
```
KILLS: X
COMBO BONUS: X (Max: Xx)
TIME BONUS: X (MM:SS.ms)
ACCURACY BONUS: X (X.X%)
AGGRESSIVENESS: X (X.X/min)
RICOCHET BONUS: X (X kills)
PENETRATION BONUS: X (X kills)
DAMAGE PENALTY: -X (X hits)
---
TOTAL SCORE: X
```

### Design Rationale

The aggressiveness requirement (15 kills/minute) serves several purposes:
1. **Prevents camping**: Players can't slowly line up ricochet shots for easy points
2. **Rewards skill**: Performing ricochets while maintaining fast pace requires high skill
3. **Matches Hotline Miami style**: Fast, aggressive play is the intended way to earn high scores
4. **Balances gameplay**: Regular play still viable, but skilled aggressive play earns more

## Update 2026-01-21: Counter Issues Investigation

### User Report
User reported (translated from Russian): "Ammo counter and enemy counter is broken"

### Log Analysis (2026-01-21)

Two new log files were provided:
- `game_log_20260121_133914.txt`
- `game_log_20260121_134045.txt`

#### Critical Observation
**No `[BuildingLevel]` log entries appear in either file.**

The logs show:
1. **Enemy deaths logged correctly**: `[ENEMY] [Enemy3] Enemy died (ricochet=false, penetration=false)`
2. **Sound propagation working**: `[INFO] [SoundPropagation] Unregistered listener: Enemy3 (remaining: 9)`
3. **Autoloads initializing**: `[GameManager]`, `[SoundPropagation]`, `[PenultimateHit]`, `[LastChance]`

But NO:
- `[BuildingLevel] BuildingLevel _ready() started`
- `[BuildingLevel] Setup tracking for X enemies`
- `[BuildingLevel] Enemy died signal received`

### Root Cause Hypothesis

The `building_level.gd` script's `_ready()` function uses `print()` statements which:
1. Go to stdout (console)
2. Do NOT appear in FileLogger output
3. Are invisible in exported Windows builds

Therefore, the existing logs cannot tell us whether `building_level.gd` is executing at all.

### Diagnostic Additions (Commit 89a33df)

Added comprehensive `_log_to_file()` tracing:

```gdscript
func _ready() -> void:
    _log_to_file("BuildingLevel _ready() started")
    # ... existing code ...
    _log_to_file("Enemy count label found: %s" % str(_enemy_count_label != null))
    # ... existing code ...
    _log_to_file("BuildingLevel _ready() completed")

func _setup_enemy_tracking() -> void:
    _log_to_file("_setup_enemy_tracking() started")
    # ...
    _log_to_file("Found Environment/Enemies node with %d children" % enemies_node.get_child_count())
    # ...
    _log_to_file("Setup tracking for %d enemies (connected died signal to %d)" % [_initial_enemy_count, connected_count])

func _setup_player_tracking() -> void:
    _log_to_file("_setup_player_tracking() started")
    _log_to_file("Found player: %s" % _player.name)
    _log_to_file("Ammo label found: %s" % str(_ammo_label != null))
    _log_to_file("Found weapon: AssaultRifle (C# player)")
    _log_to_file("Initial ammo: %d / %d" % [weapon.CurrentAmmo, weapon.ReserveAmmo])
    _log_to_file("Weapon AmmoChanged signal connected: %s" % ammo_connected)
```

### Expected Log Output After Re-Export

When the user re-exports and runs the game, the log should show:
```
[BuildingLevel] BuildingLevel _ready() started
[BuildingLevel] _setup_enemy_tracking() started
[BuildingLevel] Found Environment/Enemies node with 10 children
[BuildingLevel] Setup tracking for 10 enemies (connected died signal to 10)
[BuildingLevel] Enemy count label found: true
[BuildingLevel] _setup_player_tracking() started
[BuildingLevel] Found player: Player
[BuildingLevel] Ammo label found: true
[BuildingLevel] Found weapon: AssaultRifle (C# player)
[BuildingLevel] Initial ammo: 30 / 90
[BuildingLevel] Weapon AmmoChanged signal connected: true
[BuildingLevel] BuildingLevel _ready() completed
```

If these entries are missing, the script isn't running at all.
If some are present but not others, we'll know exactly where it fails.

### Possible Root Causes

1. **Stale export**: User's exported build doesn't contain latest code
2. **Script attachment error**: building_level.gd not properly attached to scene in export
3. **C# compilation issue**: GDScript/C# interop problem in exported build
4. **Signal signature mismatch**: The `died` signal changed from `signal died` to `signal died(is_ricochet_kill: bool, is_penetration_kill: bool)` - callback has default parameters but connection might fail

### Next Steps

1. User needs to re-export the game
2. Run exported game and share new log
3. Analyze `[BuildingLevel]` entries to pinpoint failure

## Update 2026-01-21 (13:55): Third Log Analysis

### New Log File
User provided `game_log_20260121_135511.txt` after being asked to re-export.

### Critical Finding
**STILL NO `[BuildingLevel]` LOG ENTRIES** despite:
1. The enemy scripts ARE updated (they show `ricochet=false, penetration=false` in died signal)
2. All 10 enemies died and were logged correctly
3. FileLogger is working (INFO entries appear)
4. Export is from after the FileLogger tracing commit (11:47 AM), log is from 1:55 PM

### Evidence from Log

Timestamps comparison:
- **Tracing commit**: `Wed Jan 21 11:47:51 2026` (89a33df)
- **Log timestamp**: `2026-01-21T13:55:11` (nearly 2 hours later)

Log shows updated enemy script behavior:
```
[13:55:15] [ENEMY] [Enemy3] Enemy died (ricochet=false, penetration=false)
...
[13:56:03] [ENEMY] [Enemy10] Enemy died (ricochet=false, penetration=false)
[13:56:03] [INFO] [SoundPropagation] Unregistered listener: Enemy10 (remaining: 0)
```

All 10 enemies died, game continued until 13:56:12 without showing victory.

### Root Cause Analysis

The `building_level.gd` script is NOT EXECUTING AT ALL. Evidence:
1. No `print()` output from `_ready()` (even basic prints)
2. No `_log_to_file()` output (FileLogger not being called)
3. No `push_warning()` output (would appear regardless)
4. Victory not triggered despite all enemies dead

### Possible Causes

1. **Script not being compiled/loaded** - GDScript parser error at export time
2. **Scene/Script mismatch** - Scene might reference a different script path
3. **Export issue** - Script files not being included in .pck
4. **C# interop issue** - C# project not properly built alongside GDScript

### Enhanced Debugging (Commit pending)

Added multiple logging methods to `_ready()`:
```gdscript
func _ready() -> void:
    # Method 1: Direct print
    print("=== BUILDING_LEVEL _READY() CALLED ===")

    # Method 2: FileLogger via multiple paths
    var file_logger = Engine.get_singleton("FileLogger") if Engine.has_singleton("FileLogger") else null
    if file_logger == null:
        file_logger = get_tree().root.get_node_or_null("FileLogger")
    if file_logger and file_logger.has_method("log_info"):
        file_logger.log_info("[BuildingLevel] === _READY() STARTED ===")

    # Method 3: Original _log_to_file
    _log_to_file("BuildingLevel _ready() started")

    # Method 4: Push warning (always visible)
    push_warning("[BuildingLevel] _ready() function is executing")
```

Also added version constant:
```gdscript
const SCRIPT_LOADED_VERSION: String = "2026-01-21-v2-debug"
```

### Next Steps for User

1. **Verify branch**: Pull specifically from `issue-53-990810d3363f` branch
2. **Clean rebuild**: Delete any `.godot/` cache folder before opening project
3. **Re-export**: Create fresh export from Godot Editor
4. **Check output**: Look for "=== BUILDING_LEVEL _READY() CALLED ===" in log

If NONE of the debug messages appear, the script is not being loaded at all, which points to:
- Export preset issue
- Script path mismatch
- GDScript parse error only visible in editor

## Related Resources
- [Hotline Miami Scoring Analysis](https://steamcommunity.com/app/219150/discussions/) (reference)
- Godot Signal Documentation
- GDScript/C# Interop Best Practices
