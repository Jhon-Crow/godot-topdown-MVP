# Game Log Analysis: game_log_20260317_032746.txt

**Date**: 2026-03-17
**Issue**: #583 — RPG enemy type
**Symptom reported**: "RPG enemies still don't fire a projectile"

## Timeline Reconstruction

The log covers multiple play sessions within the same game run. The player spawned at (264, 1544) in TestTier (Полигон).

- `03:27:58` — First session starts. RpgEnemy1 spawns at (3700, 1400), RpgEnemy2 at (2000, 2200).
- `03:28:32` — Second respawn session. RpgEnemy2 briefly enters COMBAT (saw player at 2490,1451), then immediately transitions to PURSUING. No rocket fired.
- `03:28:45` — Third session. RpgEnemy1 enters COMBAT (saw player at ~362,1336 — distance 3338 units), then immediately transitions to PURSUING. No rocket fired.
- `03:28:46` — RpgEnemy2 enters COMBAT, then PURSUING. No rocket fired.

Throughout the entire log, **zero RPG rocket shots were fired**. Only player weapon shots appear (`AKGL grenade launcher fired!` at 03:31:52).

## Root Cause Analysis

### Primary Cause: `shoot_cooldown = 2.0s` + `_shoot_timer` starts at 0 on COMBAT entry

When `_transition_to_combat()` is called, it resets `_detection_timer = 0.0` and `_detection_delay_elapsed = false`, but it does **NOT** reset `_shoot_timer`.

However, `_shoot_timer` starts at 0.0 at game start and is incremented every frame (line 819). The RPG weapon config has `shoot_cooldown = 2.0`.

The RPG fire condition (line 1504 in the original code):
```gdscript
if _is_rpg_weapon and not _rpg_fired and has_clear_shot and _detection_delay_elapsed:
    _aim_at_player()
    if _shoot_timer >= shoot_cooldown: ...fire...
    return
```

For the **first encounter** (e.g., 34s after game start), `_shoot_timer` ≈ 34s >> 2.0s, so timer IS ready.

But the condition also required `_detection_delay_elapsed = true`, which requires 0.2s in COMBAT. This part is fine.

**The real blocking issue was the `has_clear_shot` condition.** The RPG enemies at (3700,1400) and (2000,2200) were spotting the player at long range (2000–3300 units), but:

1. The player moved rapidly and LOS was lost within the 0.5s `COMBAT_MIN_DURATION_BEFORE_PURSUE` window
2. OR `_is_bullet_spawn_clear` returned false due to the enemy's muzzle position being near a wall

Looking at the log, the pattern is consistent: enemies enter COMBAT showing `P1:visible` (LOS exists for 1 frame), then immediately rotate to `P2:combat_state` and transition to PURSUING within the same logged second.

### Secondary Cause: Detection delay requirement (removed in fix)

The original code required `_detection_delay_elapsed` for the RPG to fire. This added another 0.2s window where the RPG couldn't fire, giving the player more time to break LOS.

## Fix Applied (2026-03-17)

Two changes to `scripts/objects/enemy.gd`:

### Change 1: Pre-initialize shoot_timer in `_transition_to_combat()`

```gdscript
# Added to _transition_to_combat():
if _is_rpg_weapon and not _rpg_fired: _shoot_timer = shoot_cooldown  # Issue #583: RPG fires immediately on first sight
```

This ensures that when the RPG enemy enters COMBAT, the `_shoot_timer` is already at `shoot_cooldown`, so the fire check succeeds on the very first frame (after aiming).

### Change 2: Remove detection delay requirement for RPG

```gdscript
# Before:
if _is_rpg_weapon and not _rpg_fired and has_clear_shot and _detection_delay_elapsed:
# After:
if _is_rpg_weapon and not _rpg_fired and has_clear_shot:  # Issue #583: RPG fires immediately at max range
```

The detection delay is a "reaction time" mechanic for normal enemies. For RPG enemies whose whole design is to fire a single rocket immediately on first sight, this delay was counterproductive and prevented the shot in brief LOS windows.

## Expected Behavior After Fix

1. RPG enemy enters COMBAT state → `_shoot_timer` immediately set to `shoot_cooldown` (ready to fire)
2. On the same frame: `has_clear_shot` is checked (muzzle not inside wall)
3. `_aim_at_player()` is called to orient toward player
4. Next frame: if aim is within 30° tolerance (`AIM_TOLERANCE_DOT = cos(30°)`), rocket fires
5. `_rpg_fired = true` → switches to PM pistol via `_switch_to_secondary_weapon()`

The RPG enemy will now fire a rocket on the very first frame it enters COMBAT with a clear shot, even if the player is at maximum detection distance.
