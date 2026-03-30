# Case Study: Issue #1512 — Enemies Not Appearing in Winter Forest Level

## Summary

After the Winter Forest level was updated (PR #1513), players reported that enemies were not appearing on the level and the enemy counter showed 0. This document reconstructs the timeline of events, identifies the root cause, and describes the fix applied.

---

## Artifact

- **Log file**: `game_log_20260326_070441.txt` (provided by Jhon-Crow, 2026-03-26 07:04:41)
- **Game version**: Godot 4.3-stable (release build, Windows)
- **Branch**: `issue-1512-e6033fb5f788`

---

## Timeline / Sequence of Events

| Time | Event |
|------|-------|
| 07:04:41 | Game starts, loads `LabyrinthLevel` first (as the current level) |
| 07:04:42 | LabyrinthLevel: finds 5 enemies, all with `has_died_signal=true`, 5 registered |
| 07:04:51 | Player completes LabyrinthLevel, game transitions to `WinterForestLevel` |
| 07:04:52 | WinterForestLevel scene loaded successfully |
| 07:04:52 | **[ANOMALY]** `BloodyFeet:PauseMenu` initializes — PauseMenu is being treated as an enemy character |
| 07:04:52 | **[ANOMALY]** `[ENEMY] [PauseMenu] Spawned at (0, 0), hp: 4, behavior: GUARD` |
| 07:04:52 | WinterForestLevel: finds 5 children in `Environment/Enemies` node |
| 07:04:52 | **[BUG]** All 5 enemy children have `has_died_signal=false` |
| 07:04:52 | **[BUG]** "Enemy tracking complete: 0 enemies registered" |
| 07:04:52 | `ScoreManager` starts with 0 enemies — enemy counter shows 0 |

---

## Root Cause Analysis

### Finding 1: Wrong UIDs in WinterForestLevel.tscn

The `.tscn` format in Godot 4 uses UIDs (unique identifiers) for external resources. When a UID is present, **Godot uses the UID to locate the file, not the path**. The path is only a human-readable hint.

In the original (buggy) `WinterForestLevel.tscn`, the UID assignments for `PauseMenu.tscn` and `Enemy.tscn` were **swapped**:

```
# BUGGY (wrong UIDs)
[ext_resource type="PackedScene" uid="uid://cx5m8np6u3bwd" path="res://scenes/ui/PauseMenu.tscn" id="3_pause_menu"]
[ext_resource type="PackedScene" uid="uid://dxqmk8f3nw5pe" path="res://scenes/objects/Enemy.tscn" id="4_enemy"]
```

Actual UID-to-file mapping (from the scene files themselves):
- `uid://cx5m8np6u3bwd` → `scenes/objects/Enemy.tscn` (confirmed by Enemy.tscn header)
- `uid://dxqmk8f3nw5pe` → `scenes/ui/PauseMenu.tscn` (confirmed by PauseMenu.tscn header)

So when Godot loaded `id="4_enemy"` using `uid://dxqmk8f3nw5pe`, it actually loaded **PauseMenu.tscn** — and when it loaded `id="3_pause_menu"` using `uid://cx5m8np6u3bwd`, it actually loaded **Enemy.tscn**.

This means:
- Every enemy node (5 total) was instantiated from `PauseMenu.tscn`, not `Enemy.tscn`
- PauseMenu does not have the `died` signal → `has_signal("died")` returns `false` for all 5
- None were added to `_enemies` array → enemy count = 0
- The actual PauseMenu slot in the scene was loaded from `Enemy.tscn` → spawned as a "PauseMenu" named enemy at position (0,0)

### Finding 2: Comparison with Working Level

The `LabyrinthLevel.tscn` has the correct UID assignments:
```
# CORRECT
[ext_resource type="PackedScene" uid="uid://dxqmk8f3nw5pe" path="res://scenes/ui/PauseMenu.tscn" id="3_pause_menu"]
[ext_resource type="PackedScene" uid="uid://cx5m8np6u3bwd" path="res://scenes/objects/Enemy.tscn" id="4_enemy"]
```

This explains why LabyrinthLevel worked correctly (5/5 enemies registered) while WinterForestLevel failed (0/5 enemies registered).

### How the Bug Was Introduced

The bug was introduced when the WinterForestLevel.tscn was created/edited as part of PR #1513. The ext_resource declarations for PauseMenu and Enemy were written with the UIDs mistakenly swapped — the paths were correct but the UIDs were exchanged between the two resources.

---

## Fix

Swap the UIDs to match the actual scene files:

```
# FIXED
[ext_resource type="PackedScene" uid="uid://dxqmk8f3nw5pe" path="res://scenes/ui/PauseMenu.tscn" id="3_pause_menu"]
[ext_resource type="PackedScene" uid="uid://cx5m8np6u3bwd" path="res://scenes/objects/Enemy.tscn" id="4_enemy"]
```

This ensures Godot loads the correct scenes for each resource ID, so:
- Enemies are instantiated from `Enemy.tscn` → have `died` signal → registered and counted
- PauseMenu is instantiated from `PauseMenu.tscn` → works as UI overlay

---

## Evidence from Log

Key log lines confirming the diagnosis:

```
# PauseMenu being treated as an enemy
[07:04:52] [BloodyFeet:PauseMenu] Found EnemyModel for facing direction
[07:04:52] [ENEMY] [PauseMenu] Death animation component initialized
[07:04:52] [ENEMY] [PauseMenu] Spawned at (0, 0), hp: 4, behavior: GUARD

# All enemies missing the died signal
[07:04:52] [WinterForestLevel] Child 'Clearing_DroneOperator1': script=true, has_died_signal=false
[07:04:52] [WinterForestLevel] Child 'Clearing_DroneOperator2': script=true, has_died_signal=false
[07:04:52] [WinterForestLevel] Child 'Clearing_Sniper1': script=true, has_died_signal=false
[07:04:52] [WinterForestLevel] Child 'Clearing_Sniper2': script=true, has_died_signal=false
[07:04:52] [WinterForestLevel] Child 'BottomRight_MachineGunner': script=true, has_died_signal=false

# Result: 0 enemies registered
[07:04:52] [WinterForestLevel] Enemy tracking complete: 0 enemies registered
[07:04:52] [ScoreManager] Level started with 0 enemies
```

---

## Lessons Learned

1. **UIDs in Godot 4 take precedence over file paths**. When editing `.tscn` files manually or with automated tools, the UID must match the actual scene file's declared UID, not just have the correct path.

2. **Automated scene generation** must validate that UIDs in `ext_resource` declarations match the UIDs declared in the header of the referenced scene files.

3. **The `has_died_signal=false` log output** is a reliable early diagnostic indicator for this class of bug. If an enemy node lacks the `died` signal, it was likely loaded from the wrong scene.
