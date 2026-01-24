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

---

# Third Round of Feedback (2026-01-22)

## User Feedback

After the second fix, user tested again and reported:

- **"не вижу изменений (возможно ошибка экспорта или конфликт языков)"**
  - Translation: "I don't see changes (possibly export error or language conflict)"

## Investigation

### Log Analysis

Downloaded and analyzed two new game logs:
- `game_log_20260122_112717.txt`
- `game_log_20260122_112810.txt`

### Key Findings

**1. C# code IS running** - The log shows new format:
```
[11:27:17] [INFO] [Player] Ready! Ammo: 30/30, Grenades: 1/3, Health: 2/4
```
This format with "Ammo: X/X" is from the updated C# code, confirming the C# Player.cs is being used.

**2. Animation phases ARE being triggered** - The log shows:
```
[11:27:28] [INFO] [Player.Reload.Anim] Phase changed to: GrabMagazine (duration: 0,25s)
[11:27:30] [INFO] [Player.Reload.Anim] Phase changed to: InsertMagazine (duration: 0,30s)
[11:27:31] [INFO] [Player.Reload.Anim] Phase changed to: PullBolt (duration: 0,15s)
[11:27:31] [INFO] [Player.Reload.Anim] Phase changed to: ReturnIdle (duration: 0,20s)
[11:27:31] [INFO] [Player.Reload.Anim] Animation complete, returning to normal
```

This confirms the animation state machine is working correctly.

## Root Cause Analysis (Third Round)

### Hypothesis

Since the animation phases are being triggered correctly but the user doesn't see visual changes, the most likely causes are:

1. **Animation offsets are too subtle** - The position changes may be too small to be noticeable
2. **Arms might not be moving due to missing sprite references** - Though this is unlikely since the code doesn't error
3. **Lerp speed might be too slow** - Animation might not complete before returning to idle

### Investigation Steps

Added diagnostic logging to:
1. Verify arm sprites are found during initialization
2. Log actual arm positions during animation
3. Compare target positions with base positions

### Fix Applied

1. **Significantly increased animation offsets** to make movements more dramatic:
   - `ReloadArmLeftGrab`: Changed from `(-18, -2)` to `(-40, -8)`
   - `ReloadArmLeftInsert`: Changed from `(-4, 2)` to `(-20, 0)`
   - `ReloadArmRightBoltPull`: Changed from `(-8, -2)` to `(-20, -8)`

2. **Significantly increased rotation angles** for more visible movement:
   - `ReloadArmRotLeftGrab`: Changed from `-50°` to `-70°`
   - `ReloadArmRotRightBoltPull`: Changed from `-25°` to `-45°`

3. **Added diagnostic logging** to track:
   - Whether arm sprites are found during initialization
   - Arm positions during animation every ~1 second

## Files Updated

- `Scripts/Characters/Player.cs` - Increased animation offsets and added diagnostic logging
- `docs/case-studies/issue-222/logs/game_log_20260122_112717.txt` - Third test log
- `docs/case-studies/issue-222/logs/game_log_20260122_112810.txt` - Third test log

## Timeline Update

| Time | Event |
|------|-------|
| 2026-01-22 08:23:59 | Second fix committed (z-index, position, bolt motion) |
| 2026-01-22 11:27:17 | User started new test session |
| 2026-01-22 11:27:28 | First reload animation triggered (GrabMagazine) |
| 2026-01-22 11:28:52 | User reported "not seeing changes" |
| 2026-01-22 08:33:32 | Third fix: increased animation offsets, added diagnostic logging |

---

# Fourth Round of Feedback (2026-01-22)

## User Feedback

After the third fix with increased offsets, user tested and reported:

1. **"теперь первый сломался (раньше рука тянулась куда надо, теперь за спину)"**
   - Translation: "Now the first [step] is broken (before the hand was reaching where needed, now it goes behind the back)"

2. **"третий этап анимации (движение туда-сюда вдоль оружия) - не появился"**
   - Translation: "Third step animation (back-and-forth movement along the weapon) - didn't appear"

## Investigation

### Log Analysis

Downloaded and analyzed new game logs:
- `game_log_20260122_114303.txt`
- `game_log_20260122_114411.txt`

### Key Findings

**1. Left arm positions show the problem:**
```
[11:43:10] [INFO] [Player.Reload.Anim] LeftArm: pos=(-15.999999, -1.9999998), target=(-16, -2), base=(24, 6)
```

The left arm base is at `(24, 6)` but target is `(-16, -2)` - a negative X coordinate means the arm went **behind the player**, not toward the chest.

**2. Step 3 sub-phases not visible:**
The log shows:
```
[11:43:11] [INFO] [Player.Reload.Anim] Phase changed to: PullBolt (duration: 0,15s)
[11:43:11] [INFO] [Player.Reload.Anim] Phase changed to: ReturnIdle (duration: 0,20s)
```

Both phases happen within the same second (0.15s duration is too short), and the sub-phase transition log `"Bolt pull sub-phase: returning forward"` never appears.

## Root Cause Analysis (Fourth Round)

### Issue 1: Step 1 Goes Behind Back

**Root Cause**: The offset `(-40, -8)` was too large.
- Base left arm position: `(24, 6)`
- Offset applied: `(-40, -8)`
- Resulting target: `(24 + (-40), 6 + (-8)) = (-16, -2)` ← **This is behind the player!**

The coordinate system:
- Positive X = forward (toward weapon/mouse direction)
- Negative X = backward (behind player)
- Player body center is around `(0, 0)`

For the arm to reach the chest/vest mag pouch, it should move from `(24, 6)` to around `(4, 2)` - still positive X, not negative!

**Fix**: Changed offset from `(-40, -8)` to `(-20, -4)`:
- New target: `(24 + (-20), 6 + (-4)) = (4, 2)` ← At body center/chest area

### Issue 2: Step 3 Back-and-Forth Not Visible

**Root Cause**: The bolt pull duration is too short (0.15s) for the back-and-forth to be visible.

Additionally, looking at the animation code, when entering `PullBolt` phase:
1. Timer set to 0.15s
2. Arm lerps toward pull position
3. When timer expires, sub-phase changes to 1, timer reset to 0.1s
4. Arm lerps toward return position
5. Total time: 0.25s - barely visible

**Fix**:
1. Increased `ReloadAnimBoltPullDuration` from 0.15s to 0.35s
2. Increased `ReloadAnimBoltReturnDuration` from 0.1s to 0.25s
3. Total visible bolt motion: 0.6s

## Files Updated

- `Scripts/Characters/Player.cs`:
  - Fixed Step 1 offset: `(-40, -8)` → `(-20, -4)`
  - Fixed Step 2 offset: `(-20, 0)` → `(-12, 0)`
  - Increased bolt pull duration: 0.15s → 0.35s
  - Increased bolt return duration: 0.1s → 0.25s
  - Added detailed bolt sub-phase logging

## Timeline Update

| Time | Event |
|------|-------|
| 2026-01-22 08:33:32 | Third fix committed |
| 2026-01-22 11:43:03 | User started new test session |
| 2026-01-22 11:43:09 | Reload animation triggered - arm goes behind back |
| 2026-01-22 11:45:19 | User reported step 1 broken, step 3 not visible |
| 2026-01-22 (current) | Fourth fix: corrected offsets, increased durations |
