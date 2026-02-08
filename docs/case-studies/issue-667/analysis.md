# Case Study: Issue #667 - Wrong Weapon in Replay

## Problem Description

In the replay system, the wrong weapon was being displayed for both the player and enemies. The user reported "in the replay, the weapon is wrong for the player and enemies" (Russian: "в повторе не то оружие у игрока и врагов").

## Timeline of Events

1. **Initial fix attempt** (commit `c7960a84`): Added weapon recording to the GDScript `replay_system.gd` but the game uses the C# `ReplayManager.cs` at runtime.
2. **User feedback** (2026-02-08): User reported the issue persists, attached `game_log_20260209_022701.txt`.
3. **Root cause analysis**: Analyzed the game log and identified three distinct root causes in the C# ReplayManager.

## Root Cause Analysis

### Root Cause 1: Missing weapon types in DetectPlayerWeapon (Player)

**File**: `Scripts/Autoload/ReplayManager.cs`, method `DetectPlayerWeapon()`

The method only checked for 4 weapons by name:
- MiniUzi
- Shotgun
- SniperRifle
- SilencedPistol

It did NOT check for:
- **Revolver** - falls through to default (Assault Rifle)
- **MakarovPM** - falls through to default (Assault Rifle)
- AssaultRifle - explicit check was also missing (relied on default)

**Evidence from game log** (lines 1373-1378):
```
[ReplayManager] Detected player weapon: Assault Rifle (default)
[ReplayManager] Detected weapon texture: res://assets/sprites/weapons/m16_rifle_topdown.png
```
This occurs even when the player selected "revolver" (line 1276: `GameManager Weapon selected: revolver`).

### Root Cause 2: Detection method fragility (Player)

The detection used `player.GetNodeOrNull("WeaponName")` to find weapon child nodes. This can fail if called before the weapon has been added as a child (timing issue between Player._Ready() and level script _ready()).

**Fix**: Use `player.Get("CurrentWeapon")` property as the primary detection method, since `CurrentWeapon` is always set by `Player.ApplySelectedWeaponFromGameManager()` during Player._Ready().

### Root Cause 3: No enemy weapon recording in C# ReplayManager

The GDScript version (`replay_system.gd`) had proper enemy weapon recording via `_enemy_weapon_types`, but the C# `ReplayManager.cs` had NO equivalent:
- `CreateEnemyGhost()` always instantiated from `Enemy.tscn` which defaults to RIFLE sprite
- No weapon type was recorded during `StartRecording()`
- No weapon sprite was applied during ghost creation

Each enemy in the game has a `weapon_type` property (exported in enemy.gd):
- 0 = RIFLE (default)
- 1 = SHOTGUN
- 2 = UZI
- 3 = MACHETE

Enemies with non-RIFLE weapons would always appear with rifle sprite in replay.

### Root Cause 4: Missing "revolver" in GDScript weapon name dictionary

**File**: `scripts/levels/building_level.gd`, method `_setup_selected_weapon()`

The `weapon_names` dictionary used to check if C# Player already equipped a weapon was missing the "revolver" entry:
```gdscript
var weapon_names: Dictionary = {
    "shotgun": "Shotgun",
    "mini_uzi": "MiniUzi",
    "silenced_pistol": "SilencedPistol",
    "sniper": "SniperRifle",
    "m16": "AssaultRifle"
    # "revolver": "Revolver" was MISSING
}
```

## Solution

### Fix 1: Complete weapon detection for player

Rewrote `DetectPlayerWeapon()` to:
1. Use `CurrentWeapon` property name as primary detection (most reliable)
2. Fall back to child node name lookup
3. Handle ALL weapon types: MiniUzi, Shotgun, SniperRifle, SilencedPistol, **Revolver**, **MakarovPM**, AssaultRifle

### Fix 2: Enemy weapon recording and display

Added to `ReplayManager.cs`:
1. `_enemyWeaponTypes` list to store each enemy's weapon type at recording start
2. Reading `weapon_type` property from each enemy during `StartRecording()`
3. Passing weapon type to `CreateEnemyGhost(weaponType)`
4. `ApplyEnemyWeaponSprite()` method to set correct weapon texture on ghost enemies

### Fix 3: GDScript weapon name dictionary

Added `"revolver": "Revolver"` to the `weapon_names` dictionary in `building_level.gd`.

## Files Changed

- `Scripts/Autoload/ReplayManager.cs` - Player weapon detection + enemy weapon recording
- `scripts/levels/building_level.gd` - Added revolver to weapon names dictionary

## Weapon Sprite Mappings

| Weapon ID | Node Name | Texture Path | Sprite Offset |
|-----------|-----------|-------------|---------------|
| makarov_pm | MakarovPM | makarov_pm_topdown.png | (15, 0) |
| revolver | Revolver | revolver_topdown.png | (15, 0) |
| m16 | AssaultRifle | m16_rifle_topdown.png | (20, 0) |
| shotgun | Shotgun | shotgun_topdown.png | (20, 0) |
| mini_uzi | MiniUzi | mini_uzi_topdown.png | (15, 0) |
| silenced_pistol | SilencedPistol | silenced_pistol_topdown.png | (15, 0) |
| sniper | SniperRifle | asvk_topdown.png | (25, 0) |

## Enemy Weapon Types (from WeaponConfigComponent)

| Type | Name | Sprite Path |
|------|------|-------------|
| 0 | RIFLE | (default in Enemy.tscn) |
| 1 | SHOTGUN | shotgun_topdown.png |
| 2 | UZI | mini_uzi_topdown.png |
| 3 | MACHETE | machete_topdown.png |

## Verification

The fix can be verified by:
1. Selecting different weapons (especially Revolver) in the armory
2. Playing through a level with enemies that have different weapon types
3. Watching the replay and confirming weapons match what was used during gameplay
