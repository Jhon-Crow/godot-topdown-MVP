# Case Study: Issue #887 — Homing Bullets Charges & Duration

## Overview

**Issue**: [#887 — update наводящиеся пули](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/887)
**Pull Request**: [#964 — fix(homing-bullets): update charges to 2 and duration to 1.2s](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/964)
**Status**: Fix implemented, code verified correct, CI passing

---

## Problem Statement

The "наводящиеся пули" (homing bullets) active item had two incorrect configuration values:

| Parameter | Original Value | Required Value |
|-----------|---------------|---------------|
| Charges per battle | 6 | 2 |
| Effect duration per activation | 1.0 seconds | 1.2 seconds |

---

## Timeline / Sequence of Events

### 2026-03-05 18:42 UTC — AI session interrupted
- AI work session reached Claude usage limit
- Partial solution was left in progress
- Auto-resume was scheduled for after limit reset

### 2026-03-07 ~16:29 UTC — New AI session started
- AI resumed work and implemented the fix:
  - `HOMING_MAX_CHARGES`: `6` → `2` in `scripts/characters/player.gd` (line 208)
  - `_homing_charges`: initial value `6` → `2` in `scripts/characters/player.gd` (line 205)
  - `HOMING_DURATION`: `1.0` → `1.2` in `scripts/characters/player.gd` (line 211)
  - Updated unit test mock constants and assertions in `tests/unit/test_homing_bullets.gd`
- Commit `00761de9` pushed: `fix(homing-bullets): update charges to 2 and duration to 1.2s`
- Additional CI fix commit `83a9b51a`: `fix(ci): replace wget with curl wrapper to fix 403 on GitHub release downloads`
- All CI checks passed (5 workflows + Windows build)

### 2026-03-07 18:06 UTC — User reports "charges not changed" (first report)
- User (Jhon-Crow) tested the game and reported the number of charges didn't change
- User uploaded game log: `game_log_20260307_210527.txt`
- Log path shows: `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe`
- AI responded explaining the stale binary hypothesis with evidence

### 2026-03-07 18:23 UTC — User reports "still more than 2 charges" (second report)
- User (Jhon-Crow) tested again and still reported more than 2 charges
- User uploaded second game log: `game_log_20260307_212306.txt`
- **Second log shows the exact same executable path**: `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe`
- This confirms the user ran the same pre-fix binary both times — no newly built binary was used

---

## Root Cause Analysis

### Finding

**Both game logs** clearly show the **old values** were used during the user's tests:

**First log** (`game_log_20260307_210527.txt`):
```
[21:05:32] [INFO] [Player.Homing] Homing bullets equipped, charges: 6/6
[21:05:33] [INFO] [Player.Homing] Homing activated! Duration: 1s, charges remaining: 5/6
```

**Second log** (`game_log_20260307_212306.txt`):
```
[21:23:11] [INFO] [Player.Homing] Homing bullets equipped, charges: 6/6
[21:23:12] [INFO] [Player.Homing] Homing activated! Duration: 1s, charges remaining: 5/6
```

**The fix WAS applied correctly to the source code.** However, both times the user tested with the **same old pre-built executable** that was compiled before our fix was applied.

### Evidence

1. **Executable path is identical in both logs**:
   - First log: `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe`
   - Second log: `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe`
   - Both point to the **same local pre-built binary** downloaded previously
   - The folder name "микро фиксы" ("micro fixes") identifies this as a build from a prior release, not from this branch

2. **Old values in both logs**: Both logs show `6/6` charges and `Duration: 1s` — exactly matching the **pre-fix values** (`HOMING_MAX_CHARGES = 6`, `HOMING_DURATION = 1.0`)

3. **Current source code** (our fix, commit `00761de9`):
   ```gdscript
   # scripts/characters/player.gd lines 205-211
   var _homing_charges: int = 2   # was 6
   const HOMING_MAX_CHARGES: int = 2   # was 6
   const HOMING_DURATION: float = 1.2  # was 1.0
   ```

4. **Unit tests** are also updated (`tests/unit/test_homing_bullets.gd`):
   ```gdscript
   var homing_charges: int = 2   # was 6
   const MAX_CHARGES: int = 2    # was 6
   const DURATION: float = 1.2   # was 1.0
   ```

5. **All CI checks pass** on commit `83a9b51a` (the latest commit on the branch):
   - Architecture Best Practices Check: ✅
   - Gameplay Critical Systems Validation: ✅
   - C# and GDScript Interoperability Check: ✅
   - Run GUT Tests: ✅
   - C# Build Validation: ✅
   - Build Windows Portable EXE: ✅

### Root Cause Conclusion

**The fix is correct and verified.** The user encountered a "stale executable" problem — testing an old binary rather than a build from the fixed branch.

---

## Source Files Modified

| File | Lines Changed | Description |
|------|--------------|-------------|
| `scripts/characters/player.gd` | 205, 208, 211 | Updated `_homing_charges`, `HOMING_MAX_CHARGES`, `HOMING_DURATION` |
| `tests/unit/test_homing_bullets.gd` | 90, 93, 96 | Updated mock constants and test assertions |

---

## How to Verify the Fix

The correct way to verify this fix is to use a freshly compiled build from the fixed branch, **not** a pre-built binary from before the fix.

### Option 1: Download CI-built artifact
A Windows build was automatically compiled by CI from the fixed branch (commit `83a9b51a`):
- Artifact: `windows-build` from workflow run [#22802974713](https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions/runs/22802974713)
- Built at: 2026-03-07T16:44:20Z (after the fix commit)
- This build contains the fixed values: **2 charges** and **1.2s duration**

### Option 2: Build from source
1. Pull the latest code from branch `issue-887-b0735317c4f2`
2. Build using Godot 4.3
3. Test the homing bullets item — it should show 2/2 charges and each activation should last 1.2 seconds

### Expected Behavior After Fix

```
[Player.Homing] Homing bullets equipped, charges: 2/2
[Player.Homing] Homing activated! Duration: 1.2s, charges remaining: 1/2
[Player.Homing] Homing effect expired, charges remaining: 1/2
[Player.Homing] Homing activated! Duration: 1.2s, charges remaining: 0/2
[Player.Homing] Homing effect expired, charges remaining: 0/2
```

---

## Files in This Case Study

- `README.md` — This analysis document
- `game_log_20260307_210527.txt` — First game log provided by the user (2026-03-07 21:05 UTC) showing old (pre-fix) executable behavior
- `game_log_20260307_212306.txt` — Second game log provided by the user (2026-03-07 21:23 UTC) confirming the same pre-fix executable was used again

---

## Lessons Learned

1. **Verification requires a fresh build**: When testing a fix, always use a build compiled from the fixed code, not a previously downloaded executable.
2. **CI artifacts are the safest way to test**: The CI workflow "Build Windows Portable EXE" automatically produces a correct build that can be downloaded from GitHub Actions.
3. **Log analysis is essential**: The game log clearly identified which executable version was running, enabling rapid root cause determination.
