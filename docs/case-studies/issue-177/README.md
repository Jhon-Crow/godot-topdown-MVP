# Case Study: Issue #177 - Flashbang Grenade Not Working

## Problem Summary
The flashbang grenade feature was implemented in GDScript but the player could not use grenades in the game. Users reported:
- Tutorial is present
- Grenade does not appear or work
- Multiple attempts of the control sequence produced no result

## Timeline of Events

### Initial Implementation (commits ad09b21 and 9acb5da)
1. Grenade system was added to `scripts/characters/player.gd` (GDScript)
2. `GrenadeBase.gd` and `FlashbangGrenade.gd` were created
3. Tutorial was added to `scripts/levels/tutorial_level.gd`
4. Input actions `grenade_prepare` (G key) and `grenade_throw` (RMB) were added to `project.godot`

### User Testing
User (Jhon-Crow) reported in PR #180 comments:
- Log files: `game_log_20260121_165728.txt` and `game_log_20260121_165904.txt`
- No grenade-related log entries appeared despite multiple attempts

## Root Cause Analysis

### Evidence from Logs
The user's game logs showed:
- Standard game startup messages
- GUNSHOT sounds from AssaultRifle
- **ZERO grenade-related log entries**

Expected log entries that were missing:
- `[Player] Ready! Grenades: 3/3`
- `[Player.Grenade] Step 1 started...`
- `[GrenadeBase] Timer activated!`

### Investigation

1. **Checked Player.tscn**: Found it uses `scripts/characters/player.gd`
2. **Checked Level Scenes**: Found they use a **different** player scene!

```bash
$ grep -h "Player" scenes/levels/*.tscn
[ext_resource type="PackedScene" path="res://scenes/characters/csharp/Player.tscn" id="2_player"]
```

### Root Cause Identified
**The level scenes (`BuildingLevel.tscn`, `TestTier.tscn`) use `scenes/characters/csharp/Player.tscn` which is attached to `Scripts/Characters/Player.cs` (C#), NOT `scripts/characters/player.gd` (GDScript).**

The grenade system was implemented in the GDScript player, but the actual game uses the C# player which had **no grenade functionality**.

## Architecture Issue
The project has two player implementations:
1. `scenes/characters/Player.tscn` + `scripts/characters/player.gd` (GDScript)
2. `scenes/characters/csharp/Player.tscn` + `Scripts/Characters/Player.cs` (C#)

The levels reference the C# version, but new features were added to the GDScript version.

## Solution
Added the complete 3-step grenade throwing mechanic to `Scripts/Characters/Player.cs`:

### Changes Made
1. Added grenade-related fields:
   - `GrenadeScene` (PackedScene export)
   - `MaxGrenades` (configurable, default 3)
   - `_currentGrenades` (current count)
   - `_grenadeState` (state machine)
   - `_activeGrenade` (reference to held grenade)

2. Added grenade state machine:
   - `GrenadeState.Idle` - waiting for input
   - `GrenadeState.TimerStarted` - pin pulled, timer running
   - `GrenadeState.Preparing` - LMB held
   - `GrenadeState.ReadyToAim` - LMB + RMB held
   - `GrenadeState.Aiming` - ready to throw

3. Implemented 3-step throwing mechanic:
   - Step 1: G + RMB drag right -> starts 4s timer
   - Step 2: LMB held -> RMB pressed -> LMB released -> prepare
   - Step 3: RMB held -> drag and release -> throw

4. Added signals:
   - `GrenadeChangedEventHandler(int current, int maximum)`
   - `GrenadeThrownEventHandler()`

5. Added logging via `LogToFile()` method for debugging

## Lessons Learned

1. **Dual Implementation Risk**: Having both GDScript and C# implementations of the same component creates maintenance burden and risk of features being added to the wrong version.

2. **Integration Testing**: Features should be tested in the actual game context, not just in isolation. The GDScript implementation may have worked in unit tests but never executed in the real game.

3. **Log Analysis is Critical**: The absence of expected log messages was the key indicator that the code wasn't running at all, pointing to a scene/script binding issue rather than a logic bug.

4. **Architecture Documentation**: Projects with mixed language implementations should clearly document which versions are used where.

## Files Changed
- `Scripts/Characters/Player.cs` - Added complete grenade system (~400 lines)

## Log Files
- `logs/game_log_20260121_165728.txt` - First test session
- `logs/game_log_20260121_165904.txt` - Second test session with multiple attempts
