# Case Study: Issue #887 — Homing Bullets Charges & Duration

## Overview

**Issue**: [#887 — update наводящиеся пули](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/887)
**Pull Request**: [#964 — fix(homing-bullets): update charges to 2 and duration to 1.2s](https://github.com/Jhon-Crow/godot-topdown-MVP/pull/964)
**Status**: Fix implemented and verified correct in source code; CI passing. All user test reports show testing with a pre-fix executable.

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

### 2026-03-07 ~16:29 UTC — Fix implemented
- AI resumed work and implemented the fix (commit `00761de9`):
  - `HOMING_MAX_CHARGES`: `6` → `2` in `scripts/characters/player.gd` (line 208)
  - `_homing_charges`: initial value `6` → `2` in `scripts/characters/player.gd` (line 205)
  - `HOMING_DURATION`: `1.0` → `1.2` in `scripts/characters/player.gd` (line 211)
  - Updated unit test mock constants and assertions in `tests/unit/test_homing_bullets.gd`
- Additional CI fix commit `83a9b51a`: `fix(ci): replace wget with curl wrapper to fix 403 on GitHub release downloads`
- All CI checks passed (5 workflows + Windows build artifact produced)

### 2026-03-07 18:06 UTC — User reports "charges not changed" (Report #1)
- User (Jhon-Crow) tested the game and reported the number of charges didn't change
- Uploaded: `game_log_20260307_210527.txt`
- Log clearly shows stale executable at `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe`
- Log shows: `charges: 6/6`, `Duration: 1s` — confirms pre-fix binary was used

### 2026-03-07 18:23 UTC — User reports "still more than 2 charges" (Report #2)
- Uploaded: `game_log_20260307_212306.txt`
- **Identical executable path** as Report #1
- Log shows: `charges: 6/6`, `Duration: 1s` — same stale binary confirmed

### 2026-03-07 18:45 UTC — User reports "still more than 2 charges" (Report #3)
- Uploaded two logs:
  - `game_log_20260307_214436.txt` — Force Field selected (homing bullets NOT equipped; no homing log entries)
  - `game_log_20260307_214500.txt` — Homing bullets equipped, shows `6/6` charges, `Duration: 1s`
- **Both logs show identical executable path** — same stale binary, third consecutive test

### 2026-03-09 19:46 UTC — User reports "still much more than 2 charges" (Report #4)
- Uploaded: `game_log_20260309_194610.txt` (3,863 lines; date: 2 days after the fix)
- **Same executable path**: `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe`
- Log shows: `charges: 6/6`, `Duration: 1s` — **still the same pre-fix binary, two days later**
- User also requested a deep case study analysis in the PR comment

---

## Root Cause Analysis

### Primary Finding

**The fix IS correctly implemented in the source code.** All 5 user test sessions show the same pre-fix executable, not a fresh build from the fixed branch.

### Evidence Table — All 5 Game Logs

| Log File | Date/Time | Executable Path | Charges | Duration |
|----------|-----------|-----------------|---------|----------|
| `game_log_20260307_210527.txt` | 2026-03-07 21:05 | `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe` | 6/6 | 1s |
| `game_log_20260307_212306.txt` | 2026-03-07 21:23 | `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe` | 6/6 | 1s |
| `game_log_20260307_214436.txt` | 2026-03-07 21:44 | `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe` | N/A (Force Field) | N/A |
| `game_log_20260307_214500.txt` | 2026-03-07 21:45 | `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe` | 6/6 | 1s |
| `game_log_20260309_194610.txt` | 2026-03-09 19:46 | `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe` | 6/6 | 1s |

**All 5 logs show the exact same executable** — a pre-built binary from the folder `микро фиксы` ("micro fixes"), which predates the fix in commit `00761de9` (2026-03-07 ~16:32 UTC). This binary has never been replaced or updated by the user.

### Key Evidence Details

1. **Executable path is identical across all sessions** (5 out of 5 logs):
   ```
   I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe
   ```
   The folder name `микро фиксы` ("micro fixes") identifies this as a build from a prior release, not from branch `issue-887-b0735317c4f2`.

2. **Old values appear in all 4 active homing sessions** (logs 1, 2, 4, 5):
   ```
   [Player.Homing] Homing bullets equipped, charges: 6/6
   [Player.Homing] Homing activated! Duration: 1s, charges remaining: 5/6
   ```
   These match the **pre-fix constants** exactly: `HOMING_MAX_CHARGES = 6`, `HOMING_DURATION = 1.0`.

3. **Current source code** (commit `00761de9`, 2026-03-07):
   ```gdscript
   # scripts/characters/player.gd lines 205-211
   var _homing_charges: int = 2        # was 6
   const HOMING_MAX_CHARGES: int = 2   # was 6
   const HOMING_DURATION: float = 1.2  # was 1.0
   ```

4. **Unit tests** updated and passing (`tests/unit/test_homing_bullets.gd`):
   ```gdscript
   var homing_charges: int = 2   # was 6
   const MAX_CHARGES: int = 2    # was 6
   const DURATION: float = 1.2   # was 1.0
   ```

5. **All CI checks pass** on the latest branch commit:
   - Architecture Best Practices Check: ✅
   - Gameplay Critical Systems Validation: ✅
   - C# and GDScript Interoperability Check: ✅
   - Run GUT Tests: ✅
   - C# Build Validation: ✅
   - Build Windows Portable EXE: ✅

### Root Cause Conclusion

The root cause of continued user reports is a **stale executable problem**: the user consistently runs the same pre-built binary downloaded before the fix was made, rather than a build compiled from the fixed branch. The fix is correct and fully verified in source. To observe the fix, the user must run a build from this branch.

---

## Source Files Modified

| File | Lines Changed | Description |
|------|--------------|-------------|
| `scripts/characters/player.gd` | 205, 208, 211 | Updated `_homing_charges`, `HOMING_MAX_CHARGES`, `HOMING_DURATION` |
| `tests/unit/test_homing_bullets.gd` | 90, 93, 96 | Updated mock constants and test assertions |

---

## How to Verify the Fix

The correct way to verify this fix is to use a freshly compiled build from the fixed branch, **not** the pre-built binary at `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe`.

### Option 1: Download CI-built artifact (Recommended)

A Windows build is automatically compiled by CI from the fixed branch after each push:

1. Go to: https://github.com/konard/Jhon-Crow-godot-topdown-MVP/actions?query=branch%3Aissue-887-b0735317c4f2
2. Click the latest successful workflow run named **"Build Windows Portable EXE"**
3. Scroll down to the **"Artifacts"** section
4. Click `windows-build` to download the ZIP
5. Extract the ZIP and run the executable inside — **this is the fixed version**

> **Important**: Do NOT run `I:/Загрузки/godot exe/микро фиксы/Godot-Top-Down-Template.exe` — this is the pre-fix binary that always shows 6 charges / 1s duration regardless of any source code changes.

### Option 2: Build from source
1. Pull the latest code from branch `issue-887-b0735317c4f2`
2. Build using Godot 4.3
3. Test the homing bullets item — it should show 2/2 charges and each activation should last 1.2 seconds

### Expected Behavior After Fix

When running from the CI artifact or a fresh source build:
```
[Player.Homing] Homing bullets equipped, charges: 2/2
[Player.Homing] Homing activated! Duration: 1.2s, charges remaining: 1/2
[Player.Homing] Homing effect expired, charges remaining: 1/2
[Player.Homing] Homing activated! Duration: 1.2s, charges remaining: 0/2
[Player.Homing] Homing effect expired, charges remaining: 0/2
```

---

## Files in This Case Study

| File | Date | Notes |
|------|------|-------|
| `README.md` | — | This analysis document |
| `game_log_20260307_210527.txt` | 2026-03-07 21:05 | Report #1: stale exe, 6/6 charges, 1s duration |
| `game_log_20260307_212306.txt` | 2026-03-07 21:23 | Report #2: same stale exe, 6/6 charges, 1s duration |
| `game_log_20260307_214436.txt` | 2026-03-07 21:44 | Report #3a: same stale exe, Force Field equipped (no homing data) |
| `game_log_20260307_214500.txt` | 2026-03-07 21:45 | Report #3b: same stale exe, 6/6 charges, 1s duration |
| `game_log_20260309_194610.txt` | 2026-03-09 19:46 | Report #4: same stale exe 2 days later, 6/6 charges, 1s duration |

---

## Lessons Learned

1. **Verification requires a fresh build**: Editing source code does not update a pre-compiled `.exe`. Always use a build from the fixed branch.
2. **CI artifacts are the safest verification method**: The "Build Windows Portable EXE" workflow automatically produces a correct build downloadable from GitHub Actions.
3. **Log analysis is conclusive**: The executable path in the game log definitively identifies which binary version was running. All 5 logs point to the same pre-fix binary.
4. **Folder names matter**: The `микро фиксы` ("micro fixes") folder contains an old pre-release build — this name should not be confused with this fix.
