# Case Study: Issue #1311 — Enemies Not Suppressed by Player Shots

## Problem Statement

Enemies are not being suppressed by player shots. The suppression mechanic (entering `SUPPRESSED` state when bullets fly near an enemy) only triggers from enemy crossfire, never from player bullets fired by C# weapons (AssaultRifle, Shotgun, etc.).

## Timeline Reconstruction (from game_log_20260322_064647.txt)

| Time | Event |
|------|-------|
| 06:46:47 | Game starts, player equipped with M16 (AssaultRifle, C# weapon) |
| 06:46:55 | Player fires M16 at BottomEnemy1 — enemy enters COMBAT, takes damage, dies at 06:46:56 |
| 06:46:56–06:47:07 | Player kills multiple enemies — none enter SUPPRESSED state despite rapid fire |
| 06:47:11 | Player switches to Shotgun (C# weapon) |
| 06:47:13 | Player fires near ReloadGuard3 — hits it (dmg=1) — ReloadGuard3 goes RETREATING→IN_COVER |
| 06:47:14 | BottomEnemy2 fires at player — ReloadGuard3 transitions IN_COVER→SUPPRESSED (enemy crossfire) |
| 06:47:14 | Player dies from enemy frag grenade |
| 06:48:16 | Enemy1 transitions IN_COVER→SUPPRESSED (again from enemy crossfire, not player) |

**Key observation**: All 3 SUPPRESSED transitions in the log were triggered by **enemy crossfire** (BottomEnemy2 shooting), never by player bullets despite the player firing extensively.

## Root Cause Analysis

Two root causes were identified in `scripts/objects/enemy.gd`, function `_on_threat_area_entered()`:

### Root Cause 1: Visibility Check Blocks Suppression Through Cover (Primary)

```gdscript
# OLD CODE (line 4094):
if not _is_position_visible_to_enemy(area.global_position): return
```

This line raycasts from the enemy to the bullet's position. When enemies are **in cover** (the primary scenario where suppression matters), there's a wall between them and the bullet's flight path. The raycast hits the wall and returns `false`, preventing suppression.

**Impact**: The very act of taking cover (which positions the enemy behind a wall) prevents the enemy from being suppressed — the exact opposite of intended behavior. In real combat and in game design, bullets impacting near your cover position should suppress you.

### Root Cause 2: Integer Overflow for C# Bullet ShooterId (Secondary)

```gdscript
# OLD CODE (line 4100):
var sid: int = int(raw_id); if sid <= 0: return
```

C# bullets use `ulong ShooterId` (unsigned 64-bit). When Godot marshals this to GDScript's signed `int64`, instance IDs with bit 63 set become negative. The `sid <= 0` check then incorrectly rejects valid player bullet IDs.

**Impact**: Player bullets fired by C# weapons (all standard weapons: AssaultRifle, Shotgun, MakarovPM, etc.) could fail the shooter identification check depending on the Player node's instance ID.

## Fix Applied

```gdscript
# NEW CODE:
func _on_threat_area_entered(area: Area2D) -> void:
    # Removed _is_position_visible_to_enemy check — suppression works through cover
    var raw_id = area.get("shooter_id")
    if raw_id == null: raw_id = area.get("ShooterId")
    if raw_id == null: return
    var sid: int = int(raw_id)
    if sid == 0 or sid == -1: return  # Only reject unset defaults
    var shooter: Object = instance_from_id(sid)
    if shooter == null: return
    if not (shooter as Node).is_in_group("player"): return
    _bullets_in_threat_sphere.append(area)
    _threat_memory_timer = THREAT_MEMORY_DURATION
```

Changes:
1. **Removed `_is_position_visible_to_enemy` check** — bullets within the threat sphere (100px radius) always trigger suppression, even through thin walls/cover
2. **Changed `sid <= 0` to `sid == 0 or sid == -1`** — only rejects actual unset defaults, accepts both positive and negative (overflow) instance IDs
3. **Added file-level logging** for suppression events to aid future debugging

## Files Changed

- `scripts/objects/enemy.gd` — `_on_threat_area_entered()` function

## Verification

The fix ensures:
- Player bullets from C# weapons (AssaultRifle, Shotgun, etc.) trigger suppression
- Suppression works when enemies are in cover (behind walls)
- Enemy-fired bullets still correctly do NOT trigger suppression (#1228 filter preserved)
- The threat sphere radius (100px, configurable via `threat_sphere_radius` export) defines the suppression zone
- The `threat_reaction_delay` (0.2s) and `THREAT_MEMORY_DURATION` (0.5s) timers work correctly with the fix
