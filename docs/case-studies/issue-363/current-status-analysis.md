# Current Status Analysis - Issue #363

## Date: 2026-01-25

## Issue Summary
**User Feedback** (from PR #364 comment by @Jhon-Crow):
> "похоже в exe не работает новый функционал" (it seems the new functionality doesn't work in exe)
> "проверь C#" (check C#)

## Root Cause Analysis

### What Was Expected
The user expected **working enemy grenade throwing functionality** in the executable game.

### What Actually Exists

**This PR (#364) contains documentation only:**
- `README.md` - Case study analysis
- `trigger-conditions.md` - Trigger condition specifications
- `goap-actions.md` - Proposed GOAP action classes
- `difficulty-configuration.md` - Map/difficulty configuration proposals
- `research-sources.md` - External references

**No implementation code was added.** The existing grenade system only supports **player** grenade throwing:

```
[05:16:57] [INFO] [Player.Grenade] Grenade scene loaded from GrenadeManager: Flashbang
[05:16:57] [INFO] [Player.Grenade] Normal level - starting with 1 grenade
[05:16:57] [INFO] [Player.Grenade] Throwing system: VELOCITY-BASED (v2.0 - mouse velocity at release)
```

### C# Analysis

The C# codebase includes:
- `Scripts/Objects/Enemy.cs` - Simple visual target with health component (not the AI enemy)
- `Scripts/Characters/Player.cs` - Player character

**Important distinction:**
- **GDScript `scripts/objects/enemy.gd`** - Main AI enemy with GOAP system (4999 lines)
- **C# `Scripts/Objects/Enemy.cs`** - Simple target dummy (336 lines)

The C# Enemy.cs is NOT the main game enemy - it's a simplified target practice object. The actual enemy AI is in GDScript (`enemy.gd`).

### Game Log Analysis

From the uploaded log file `game_log_20260125_051657.txt`:

1. **No errors or exceptions** - The game runs without crashes
2. **C# components work** - Signal connections successful:
   ```
   [05:16:57] [INFO] [PenultimateHit] Connected to player Damaged signal (C#)
   [05:16:57] [INFO] [PenultimateHit] Connected to player Died signal (C#)
   ```
3. **Grenade system initializes** - But only for player:
   ```
   [05:16:57] [INFO] [GrenadeManager] Loaded grenade scene: res://scenes/projectiles/FlashbangGrenade.tscn
   [05:16:57] [INFO] [GrenadeManager] Loaded grenade scene: res://scenes/projectiles/FragGrenade.tscn
   ```
4. **No enemy grenade activity** - No log entries for enemy grenades

### Why "New Functionality Doesn't Work"

**The functionality was never implemented.** This PR provides:
- Analysis and documentation
- Proposed solutions
- Research references

But does **NOT** include:
- New GOAP actions for enemy grenades
- Trigger condition code
- Grenade inventory for enemies
- AI throwing mechanics

## Current GOAP Actions (None for Grenades)

From `scripts/ai/enemy_actions.gd`, the existing 16 actions are:
1. SeekCoverAction
2. EngagePlayerAction
3. FlankPlayerAction
4. PatrolAction
5. StaySuppressedAction
6. ReturnFireAction
7. FindCoverAction
8. RetreatAction
9. RetreatWithFireAction
10. PursuePlayerAction
11. AssaultPlayerAction (DISABLED)
12. AttackDistractedPlayerAction
13. AttackVulnerablePlayerAction
14. PursueVulnerablePlayerAction
15. InvestigateHighConfidenceAction
16. InvestigateMediumConfidenceAction
17. SearchLowConfidenceAction

**No grenade-related actions exist.**

## Conclusion

The PR #364 is a **design document/case study**, not an implementation. To have working enemy grenade throwing, the following must be implemented:

1. **GrenadeInventoryComponent** - Track grenades per enemy
2. **Trigger condition detection** - 6 conditions from issue #363
3. **New GOAP actions** - PrepareGrenadeAction, ThrowGrenadeAction, etc.
4. **AI throwing mechanics** - Trajectory calculation, animation
5. **Difficulty integration** - Per-map grenade assignment

## Recommendation

The case study analysis is thorough and provides a solid foundation. The next step is **actual code implementation** following the proposed architecture in the documentation.

The issue with "C#" specifically is a misunderstanding - the main enemy AI is in GDScript, not C#. The C# Enemy.cs is a different, simpler component.
