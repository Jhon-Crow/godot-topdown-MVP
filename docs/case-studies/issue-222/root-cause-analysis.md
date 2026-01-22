# Issue 222: Root Cause Analysis - Reload Animation Not Visible

## Date: 2026-01-22

## Summary

The reload animation for the assault rifle was implemented but was not visible in the game. Investigation revealed that the animation code was added to the wrong script file.

## Problem Statement

User reported: "анимации не видно" (animation is not visible)

The reload animation was supposed to show:
1. Left hand grabs magazine from chest
2. Left hand inserts magazine into rifle
3. Pull the bolt/charging handle

## Investigation Process

### Step 1: Game Log Analysis

Downloaded and analyzed the game log file `game_log_20260122_105528.txt`.

**Key observation:** The log showed:
```
[10:55:29] [INFO] [Player] Ready! Grenades: 1/3
```

But the current code in `player.gd` should output:
```
[Player] Ready! Ammo: %d/%d, Grenades: %d/%d, Health: %d/%d
```

This format mismatch indicated the game was not using the file where the animation was implemented.

### Step 2: Code Review

Searched for the "Ready!" log message format and found:

1. **GDScript version** (`scripts/characters/player.gd` line 272):
   ```gdscript
   FileLogger.info("[Player] Ready! Ammo: %d/%d, Grenades: %d/%d, Health: %d/%d" % [...])
   ```

2. **C# version** (`Scripts/Characters/Player.cs` line 557):
   ```csharp
   LogToFile($"[Player] Ready! Grenades: {_currentGrenades}/{MaxGrenades}");
   ```

The game log matched the C# format, confirming the C# script was being used.

### Step 3: Scene Configuration Review

Found TWO Player scene files:

| Scene File | Script Used |
|------------|-------------|
| `scenes/characters/Player.tscn` | `scripts/characters/player.gd` (GDScript) |
| `scenes/characters/csharp/Player.tscn` | `Scripts/Characters/Player.cs` (C#) |

The game uses the **C# version** (`csharp/Player.tscn`), but the reload animation was only implemented in the **GDScript version** (`player.gd`).

## Root Cause

**The reload animation was implemented in the wrong file.**

- Animation code was added to: `scripts/characters/player.gd`
- Game actually uses: `Scripts/Characters/Player.cs`

The animation code in `player.gd` is never executed because the game loads the C# player scene which uses `Player.cs`.

## Evidence

### Game Log Evidence
- Log format `Ready! Grenades: 1/3` matches C# Player.cs (line 557)
- No `[Player.Reload.Anim]` log entries (which would appear if GDScript was used)
- No `Ready! Ammo:` prefix (which would appear if GDScript was used)

### File Evidence
- `Scripts/Characters/Player.cs` contains C# reload logic but NO animation code
- `scripts/characters/player.gd` contains full reload animation implementation
- `scenes/characters/csharp/Player.tscn` references `Player.cs`

## Solution

Implement the reload animation in `Scripts/Characters/Player.cs` following the same pattern:

1. Add `ReloadAnimPhase` enum
2. Add animation position/rotation constants
3. Add `_reloadAnimPhase`, `_reloadAnimTimer`, `_reloadAnimDuration` fields
4. Implement `StartReloadAnimPhase()` method
5. Implement `UpdateReloadAnimation()` method
6. Call animation methods from reload input handlers
7. Integrate with `_PhysicsProcess()`

## Timeline of Events

| Time | Event |
|------|-------|
| 2026-01-22 08:40 | Reload animation committed to `player.gd` |
| 2026-01-22 10:55 | User tested game using C# build |
| 2026-01-22 10:55:28 | Game log started (C# Player.cs used) |
| 2026-01-22 10:55:56 | Game log ended - no reload animation visible |
| 2026-01-22 07:56 | User reported issue in PR comment |

## Files Involved

### Currently Modified (Wrong File)
- `scripts/characters/player.gd` - Contains unused reload animation code

### Needs Modification (Correct File)
- `Scripts/Characters/Player.cs` - Needs reload animation implementation

### Reference
- `docs/case-studies/issue-222/logs/game_log_20260122_105528.txt` - User's game log showing initial issue
- `docs/case-studies/issue-222/logs/game_log_20260122_111454.txt` - User's game log after initial fix

---

# Second Round of Feedback (2026-01-22)

## User Feedback

After the initial C# implementation, user tested again and reported three issues:

1. **Z-index problem**: "сейчас анимированная рука над оружием, а должна быть под ним (не должна быть полностью видна)"
   - Translation: "Currently the animated hand is above the weapon, but it should be below it (should not be fully visible)"

2. **Step 2 position problem**: "анимация 2 шага должна заканчиваться примерно на середине длинны оружия (сейчас на конце)"
   - Translation: "Step 2 animation should end at approximately the middle of the weapon length (currently at the end)"

3. **Step 3 motion problem**: "анимация 3 шага должна быть движением по контуру винтовки справа на себя и от себя (туда сюда), затем рука должна возвратиться на позицию до анимации"
   - Translation: "Step 3 animation should be a movement along the rifle contour right towards and away from oneself (back and forth), then the hand should return to the position before the animation"

## Root Cause Analysis (Second Round)

### Issue 1: Z-index

**Root Cause**: Arms had z_index = 2 (set in _Ready()), weapon sprite has z_index = 1. This made arms appear ABOVE the weapon.

**Evidence in code**:
- `scenes/weapons/csharp/AssaultRifle.tscn` line 21: `z_index = 1`
- `Scripts/Characters/Player.cs` line 617-622: Arms set to z_index = 2

**Fix**: Added `SetReloadAnimZIndex()` method that sets arm z_index to 0 during reload animation, making them appear below the weapon.

### Issue 2: Step 2 Position

**Root Cause**: `ReloadArmLeftInsert = new Vector2(8, 2)` placed the left hand too far forward (toward muzzle) instead of at the magazine well (middle of weapon).

**Evidence**: Base left arm position is (24, 6), adding offset (8, 2) = (32, 8) which is beyond the rifle center.

**Fix**: Changed to `ReloadArmLeftInsert = new Vector2(-4, 2)` which places the hand at the middle of the weapon where the magazine well is located.

### Issue 3: Step 3 Motion

**Root Cause**: Original implementation had a single `ReloadArmRightBolt` position, moving the hand back only once. The real bolt cycling motion requires:
1. Hand reaches forward to charging handle
2. Hand pulls bolt back (toward player)
3. Hand releases bolt, returning forward

**Fix**: Added bolt pull sub-phases:
- `_boltPullSubPhase = 0`: Pull bolt back (ReloadArmRightBoltPull)
- `_boltPullSubPhase = 1`: Release bolt forward (ReloadArmRightBoltReturn)

## Timeline Update

| Time | Event |
|------|-------|
| 2026-01-22 08:05 | C# reload animation implemented and committed |
| 2026-01-22 11:14 | User tested game with C# implementation |
| 2026-01-22 11:15:02 | Reload animation visible (GrabMagazine phase logged) |
| 2026-01-22 11:18:46 | User reported three issues with animation |
| 2026-01-22 (later) | Fixes implemented for z-index, step 2 position, step 3 motion |
