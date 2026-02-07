# Case Study: Issue #584 - Flashlight Enemy Blinding

## Issue Summary

**Issue**: When the player shines the flashlight directly at an enemy, the enemy should be blinded for 200ms (the first time for each enemy per flashlight activation).

**Reporter**: @Jhon-Crow
**PR**: #600
**Branch**: `issue-584-358f1bf6655d`

## Timeline of Events

1. **Initial implementation** (commit `986b5db`): Added beam detection logic to `flashlight_effect.gd` with cone geometry check, range check, line-of-sight check, and per-activation tracking.
2. **User testing**: @Jhon-Crow reported "не понимаю, вроде не работает" (I don't understand, it seems like it doesn't work) and provided two game logs.
3. **Investigation**: Analysis of game logs revealed the blinding mechanism IS working correctly, but the user couldn't tell.

## Root Cause Analysis

### Finding 1: The blinding mechanism works correctly

Evidence from `game_log_20260207_185021.txt` (first session, ~4 minutes):
- 30+ instances of `[ENEMY] [EnemyX] Status: BLINDED applied`
- Each followed by `Status: BLINDED removed` within ~200ms
- Multiple enemies affected: Enemy1, Enemy2, Enemy3, Enemy4, Enemy5, Enemy6, Enemy7, Enemy8

Evidence from `game_log_20260207_185352.txt` (second session, ~3 minutes):
- 40+ instances of `BLINDED applied` / `BLINDED removed`
- All enemy types affected: Enemy1 through Enemy9

### Finding 2: Visual tint was not applying to enemies (BUG)

**Root cause**: `StatusEffectsManager._apply_blindness_visual()` called `entity.get_node_or_null("Sprite2D")` but enemies do NOT have a direct `Sprite2D` child. The enemy scene structure is:

```
Enemy (CharacterBody2D)
  EnemyModel (Node2D)
    Body (Sprite2D)       <-- actual body sprite
    Head (Sprite2D)
    LeftArm (Sprite2D)
    RightArm (Sprite2D)
    WeaponMount (Node2D)
      WeaponSprite (Sprite2D)
```

The yellow tint (`Color(1.0, 1.0, 0.5, 1.0)`) was supposed to indicate blindness visually, but the sprite lookup returned `null` and silently failed. This meant the user saw NO visual change when enemies were blinded.

**Fix**: Added `_find_sprite()` helper that checks `Sprite2D` first (generic entities), then falls back to `EnemyModel/Body` (enemy structure).

### Finding 3: Debug label did not show status effects

The enemy debug label (toggled with F7) showed:
- AI state: IDLE, COMBAT, IN_COVER, PURSUING, FLANKING, etc.
- Sub-state info: timers, directions, approach status
- Memory confidence and behavior mode
- Prediction debug text

But it did NOT show BLINDED or STUNNED status, making it impossible for the user to verify the effect was working even with debug mode enabled.

**Fix**: Added status effect display to `_update_debug_label()`: when `_is_blinded` or `_is_stunned` is true, appends `{BLINDED}`, `{STUNNED}`, or `{BLINDED + STUNNED}` to the debug label.

### Finding 4: No flashlight beam logging

The flashlight beam detection ran every physics frame but produced no log output when it successfully detected and blinded an enemy. Only the enemy's `set_blinded()` produced a log entry via the enemy's own logging.

**Fix**: Added `FileLogger.info()` call in `_blind_enemy()` to log beam hits with enemy name, distance, and blindness duration.

## Summary of Fixes

| Fix | File | Description |
|-----|------|-------------|
| Visual tint sprite lookup | `status_effects_manager.gd` | Use `_find_sprite()` to find `EnemyModel/Body` instead of nonexistent `Sprite2D` |
| Debug label status | `enemy.gd` | Show `{BLINDED}` / `{STUNNED}` in F7 debug label |
| Beam hit logging | `flashlight_effect.gd` | Log enemy name, distance, duration when beam blinds an enemy |

## Data Files

- `logs/game_log_20260207_185021.txt` - First test session (4 min, ~6000 lines)
- `logs/game_log_20260207_185352.txt` - Second test session (3 min, ~17000 lines)

## Key Takeaway

The core blinding logic (cone geometry, range check, line-of-sight, per-activation tracking) was correct from the start. The problem was purely in the feedback layer: the user couldn't see the effect because (a) the visual tint failed silently due to wrong sprite path, and (b) there was no debug indicator. This highlights the importance of always verifying visual feedback works in the actual game scene structure, not just in unit tests with mock nodes.
