# Deep Case Study: BFF Pendant (Issue #674)

## Summary

**Issue**: Add active item — BFF pendant ("кулон BFF"). When Space is pressed, spawn a friendly NPC companion with M16, 2-4 HP. One charge per battle.

**Status**: Multiple failed attempts spanning 2026-02-08 to 2026-02-25. Root cause identified and fixed in PR #698.

---

## Timeline of Events

### 2026-02-08: Initial Implementation

- **Commit ec60829d**: First attempt — created `BffCompanion.tscn` + `bff_companion.gd` with custom companion AI.
- **User feedback (2026-02-09)**: "item doesn't work" + "enemy model appears (should be player model, different color). companion AI doesn't work"

**Root cause at this stage**: Custom companion AI (`bff_companion.gd`) was a new, untested script without working aggression logic.

### 2026-02-10: Debug Logging Added

- **Commit 666f0f92**: Added detailed logging to companion system.
- **User provided log**: `logs/game_log_20260210_224424.txt`
- **Log finding**:
  ```
  [Player.BffPendant] BFF pendant is selected, ready to summon companion
  [Player.BffPendant] Companion scene not found: res://scenes/objects/BffCompanion.tscn
  ```
- **Root cause at this stage**: `BffCompanion.tscn` existed in the GDScript branch but was NOT included in the C# `Player.cs` implementation's path check. Additionally, the scene was deleted in a later cleanup commit but the path reference was never updated.

### 2026-02-10: User AI Requirements Clarified

- **User feedback**: "1. companion has no AI (should be like enemy in aggressive mode from gas grenade, but following player instead of searching). 2. should not spawn in or behind walls"
- **User feedback**: "doesn't work. Can you just copy the enemy AI but make it aggressive and not treat the player as an enemy?"

### 2026-02-15: New Approach — Actual Enemy as Companion

- **Code change**: Deleted `BffCompanion.tscn` and `bff_companion.gd`. Instead, spawn actual `Enemy.tscn` in permanent aggressive state using `AggressionComponent`.
- **player.gd updated**: `BFF_ENEMY_SCENE_PATH = "res://scenes/objects/Enemy.tscn"`
- **User feedback**: "still adds player model with no AI (just stationary). Just add enemy in permanent aggressive state, model doesn't matter now"
- **User feedback**: "now nothing happens on activation"

**Root cause at this stage**: `Player.cs` (C# version) was NOT updated to match `player.gd`. The C# version still had `BffCompanionScenePath = "res://scenes/objects/BffCompanion.tscn"` which no longer existed. The game uses C# for the player logic, so the pendant never activated.

### 2026-02-24 (User Report with Latest Log)

- **User feedback (Russian)**: "не работает вообще (даже моделька не появляется)" (doesn't work at all, even the model doesn't appear)
- **Attached log**: `game_log_20260225_012900.txt`
- **Log evidence** (repeated 6 times during session):
  ```
  [Player.BffPendant] BFF pendant is selected, ready to summon companion
  [Player.BffPendant] WARNING: Companion scene not found: res://scenes/objects/BffCompanion.tscn
  ```

**Root cause confirmed**: The `Player.cs` file still referenced the DELETED `BffCompanion.tscn`. Every time the pendant was activated, the C# code checked for this scene, found it missing, and returned without spawning anything. `_bffPendantEquipped` was never set to `true`.

---

## Root Cause Analysis

### Primary Root Cause: Mismatch Between GDScript and C# Implementation

The project uses both GDScript (`player.gd`) and C# (`Player.cs`) for the player character. Both files implement the BFF pendant logic independently.

When `player.gd` was updated to use `Enemy.tscn` instead of `BffCompanion.tscn`, the same change was **NOT applied to `Player.cs`**. The C# version continued to reference the now-deleted `BffCompanion.tscn`.

```csharp
// Player.cs (BUGGY - old code)
private const string BffCompanionScenePath = "res://scenes/objects/BffCompanion.tscn";
// Scene was DELETED, this path no longer exists
// InitBffPendant() returns early without setting _bffPendantEquipped = true
// HandleBffPendantInput() checks _bffPendantEquipped which is always false
// RESULT: Nothing happens when Space is pressed
```

```gdscript
# player.gd (CORRECT - updated code)
const BFF_ENEMY_SCENE_PATH: String = "res://scenes/objects/Enemy.tscn"
# Scene EXISTS and works correctly
```

### Secondary Issue: Logic Guard in InitBffPendant

The `InitBffPendant` method checked if the scene exists and returned early if not. This meant `_bffPendantEquipped` stayed `false` forever, so `HandleBffPendantInput` was a no-op.

```csharp
// The scene check was meant as a safety guard, but it
// prevented the pendant from EVER working after the scene was deleted
if (!ResourceLoader.Exists(BffCompanionScenePath))
{
    LogToFile($"WARNING: Companion scene not found: {BffCompanionScenePath}");
    return;  // <-- Returns here! _bffPendantEquipped stays false
}
_bffPendantEquipped = true;  // Never reached!
```

---

## Solution Applied (PR #698)

### Fix: Update Player.cs to Use Enemy.tscn

```csharp
// FIXED: Use Enemy.tscn instead of deleted BffCompanion.tscn
private const string BffEnemyScenePath = "res://scenes/objects/Enemy.tscn";
```

### Fix: Replicate Full GDScript Logic in C#

The `SummonBffCompanion()` method was completely rewritten to match the `player.gd` implementation:

1. **Load `Enemy.tscn`** (the proven, working enemy scene)
2. **Set health 2-4 HP** before adding to scene tree
3. **Add to scene** as independent node
4. **Remove from "enemies" group** so other enemies don't target it
5. **Add to "bff_companions" group** for identification
6. **Set aggressive state** via `companion.Call("set_aggressive", true)`
7. **Apply green-cyan tint** to visually distinguish from enemies
8. **Find valid wall-free spawn position** using raycasting
9. **Connect "died" signal** (not "companion_died" which doesn't exist on Enemy)

---

## Game Log Evidence

### Log: game_log_20260225_012900.txt (Latest — 2026-02-25)

The user tested a build that still had the old `Player.cs`. Evidence:

```
[01:29:12] [INFO] [Player.BffPendant] BFF pendant is selected, ready to summon companion
[01:29:12] [INFO] [Player.BffPendant] WARNING: Companion scene not found: res://scenes/objects/BffCompanion.tscn
```

This warning appears **6 times** during the session (the game reloads the scene multiple times via the armory menu). Every time, the companion fails to spawn.

**Build evidence**: The log shows `Debug build: false` on `Executable: I:/Загрузки/godot exe/BFF/Godot-Top-Down-Template.exe` — this is a Windows exported build that the user downloaded. The user never received the updated code because PR #698 was never merged.

### Log: game_log_20260216_003912.txt (Earlier — 2026-02-16)

Same issue, same cause. C# code checking for deleted `BffCompanion.tscn`.

---

## Sequence of Events Reconstruction

```
2026-02-08: BffCompanion.tscn + bff_companion.gd created
     ↓ user tests: "enemy model appears but no AI"
2026-02-10: Debug logging added, CI export fails (unrelated Godot bug)
     ↓ user tests: still same scene path issue
2026-02-15: player.gd updated to use Enemy.tscn
            BffCompanion.tscn DELETED
            *** Player.cs NOT updated ***
     ↓ user tests: "nothing happens on activation"
     ↓ ROOT CAUSE: Player.cs still checks for deleted BffCompanion.tscn
2026-02-24: user tests again: "even the model doesn't appear"
     ↓ log confirms: "Companion scene not found: BffCompanion.tscn"
2026-02-28: Player.cs fixed to use Enemy.tscn
            Full spawning logic implemented to match player.gd
```

---

## Key Lessons

1. **Dual implementation risk**: When the same feature is implemented in both GDScript and C#, changes to one must always be replicated in the other. A checklist or code review step should verify this.

2. **Early returns that silently disable features**: The pattern `if (!file_exists) { return; }` in init methods can hide the root cause for a long time. Adding `_bffPendantEquipped = false` and logging "pendant disabled due to missing scene" would have made diagnosis faster.

3. **Test with exported builds**: The user was testing with a Windows export, not the editor. The export was from BEFORE the code was merged, so the fix was never in the build they tested.

4. **User feedback "even the model doesn't appear"**: This specific phrasing is a strong signal that initialization failed (not just the visual tint or AI behavior), since if spawning worked but behavior was broken, the model WOULD appear.

---

## Log Files in This Folder

| File | Date | Key Finding |
|------|------|-------------|
| `game_log_20260209_103259.txt` | 2026-02-09 | First user test; no BFF pendant issues logged |
| `game_log_20260216_001841.txt` | 2026-02-16 | Long session; pendant activated multiple times, fails each time |
| `game_log_20260216_003912.txt` | 2026-02-16 | Short test session; confirms `BffCompanion.tscn` not found |
| `logs/game_log_20260210_224424.txt` | 2026-02-10 | First log with debug; "Companion scene not found" first appears |
| `logs/game_log_20260210_224511.txt` | 2026-02-10 | Second test on same day |
| `game_log_20260225_012900.txt` | 2026-02-25 | **Latest test** — confirms C# still uses old BffCompanion.tscn path |

---

## References

- Issue: https://github.com/Jhon-Crow/godot-topdown-MVP/issues/674
- PR: https://github.com/Jhon-Crow/godot-topdown-MVP/pull/698
- AggressionComponent: `scripts/components/aggression_component.gd`
- Player GDScript: `scripts/characters/player.gd` (lines 3220-3430)
- Player C# (fixed): `Scripts/Characters/Player.cs`
