# Case Study: Issue #81 - Aggressive Enemy Behavior on Player Reload/Empty Ammo

## Summary

**Issue**: Enemies should attack aggressively when the player starts reloading or tries to shoot with empty ammo, but this behavior was not working in the exported game build.

**Root Cause**: The C# Player was missing the `ReloadStarted` signal, and the level scripts only connected reload signals for the GDScript player, not the C# player.

**Solution**: Added `ReloadStarted` and `AmmoDepleted` signals to the C# Player and fixed the level scripts to connect these signals for both player types.

## Timeline of Events

### Initial Implementation (Prior Session)

1. Issue #81 was created requesting aggressive enemy behavior when:
   - Player starts reloading near an enemy
   - Player tries to shoot with empty weapon near an enemy

2. Initial implementation added:
   - `reload_started` signal to GDScript `player.gd`
   - `AttackVulnerablePlayerAction` to GOAP action system in `enemy_actions.gd`
   - `player_reloading` and `player_ammo_empty` GOAP world states
   - Signal handlers in level scripts (`building_level.gd`, `test_tier.gd`)
   - Priority attack code in `enemy.gd` `_process_ai_state()`

### User Testing Report

User reported: "не работает ни с пустым ни при перезарядке" (doesn't work with empty or during reload)

Game log provided: `game_log_20260118_163005.txt`

### Log Analysis

Analysis of the game log revealed:
- No reload events logged anywhere in the log file
- No empty ammo events logged
- Enemies were functioning normally (state transitions, combat, etc.)
- Sound propagation was working correctly for gunshots

Key observation: The game log showed NO evidence of:
- `reload_started` signal being emitted
- `ammo_depleted` signal being emitted
- `set_player_reloading()` being called
- `set_player_ammo_empty()` being called

## Root Cause Analysis

### Finding 1: C# Player Missing Signals

The game uses the C# Player (from `scenes/characters/csharp/Player.tscn`) which is loaded in `BuildingLevel.tscn`:

```
[ext_resource type="PackedScene" path="res://scenes/characters/csharp/Player.tscn" id="2_player"]
```

The C# Player only had:
- `ReloadSequenceProgress` signal
- `ReloadCompleted` signal

**Missing**:
- `ReloadStarted` signal (never existed)
- `AmmoDepleted` signal (never existed)

### Finding 2: Level Script Signal Connection Logic Bug

In `building_level.gd`, the signal connections were structured as:

```gdscript
var weapon = _player.get_node_or_null("AssaultRifle")
if weapon != null:
    # C# Player with weapon - connect to WEAPON signals only
    # ...
else:
    # GDScript Player - connect to PLAYER signals
    # INCLUDING reload_started and ammo_depleted connections
```

This meant that for the C# Player (which has an AssaultRifle child), the reload signals were NEVER connected because the code entered the `if weapon != null` branch and the signal connections were in the `else` branch.

### Signal Flow Diagram

**Before Fix (Broken)**:
```
C# Player                     Level Script                  Enemy
     |                              |                          |
     | [ReloadStarted - NOT EXIST]  |                          |
     |                              |                          |
     | [R key pressed]              |                          |
     |-------------------->| X No signal connection!           |
     |                     |        |                          |
     |                     | [never receives event]            |
     |                     |        |                          |
     |                     |        |--X set_player_reloading |
     |                     |        |    NEVER CALLED          |
```

**After Fix (Working)**:
```
C# Player                     Level Script                  Enemy
     |                              |                          |
     | [ReloadStarted signal added] |                          |
     |<-------connect---------------|                          |
     |                              |                          |
     | [R key pressed]              |                          |
     |--- ReloadStarted ----------->|                          |
     |                              |---set_player_reloading-->|
     |                              |        (true)            |
     |                              |                          |
     |                              |      [enemy checks]      |
     |                              |      if vulnerable AND   |
     |                              |      close AND can_see   |
     |                              |           |              |
     |                              |      [ATTACK!]           |
```

## Fix Implementation

### Changes Made

1. **Scripts/Characters/Player.cs**:
   - Added `ReloadStarted` signal definition
   - Added `AmmoDepleted` signal definition
   - Emit `ReloadStarted` when reload sequence begins (R key pressed first time)
   - Emit `AmmoDepleted` when trying to shoot with empty weapon

2. **scripts/levels/building_level.gd**:
   - Moved reload/ammo signal connections OUTSIDE the if/else block
   - Added support for both PascalCase (C#) and snake_case (GDScript) signal names
   - Now connects `ReloadStarted` OR `reload_started`, `ReloadCompleted` OR `reload_completed`, `AmmoDepleted` OR `ammo_depleted`

3. **scripts/levels/test_tier.gd**:
   - Same changes as building_level.gd

4. **scripts/objects/enemy.gd**:
   - Added debug logging to `set_player_reloading()` and `set_player_ammo_empty()` to track state changes
   - Added debug logging to vulnerability check in `_process_ai_state()`

### Code Changes Summary

```
 Scripts/Characters/Player.cs     | 25 +++++++++++++++++++++++++
 scripts/levels/building_level.gd | 26 +++++++++++++++++++-------
 scripts/levels/test_tier.gd      | 26 +++++++++++++++++++-------
 scripts/objects/enemy.gd         | 21 ++++++++++++++++++---
 4 files changed, 81 insertions(+), 17 deletions(-)
```

## Lessons Learned

1. **Test with the actual game build**: The initial implementation was tested with unit tests and possibly the GDScript player, but not with the C# player that's actually used in the main game level.

2. **Signal naming conventions matter**: C# uses PascalCase (`ReloadStarted`) while GDScript uses snake_case (`reload_started`). Level scripts must handle both.

3. **Debug logging is essential**: The lack of logging in the signal handlers made it impossible to diagnose the issue from the game log alone.

4. **Check all code paths**: The level script's if/else structure meant the reload signal connections were skipped for C# players.

## Verification

After this fix, the game log should show:
- "Player reloading state changed: false -> true" when R is pressed
- "Player ammo empty state changed: false -> true" when shooting with empty weapon
- "Vulnerable check: reloading=true, ammo_empty=false, can_see=true, close=true" when conditions are met
- "Player reloading - priority attack triggered" when enemy attacks

## Files Included in Case Study

- `game_log_20260118_163005.txt` - Original game log showing the issue
- `analysis.md` - This analysis document

## Related Issues and PRs

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/81
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/128
