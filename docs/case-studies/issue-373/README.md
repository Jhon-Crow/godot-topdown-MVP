# Issue #373: Enemies Turn Away When Seeing Player

## Summary

Enemies would sharply turn away when the player entered their field of view, instead of engaging in combat. This resulted in rapid `IDLE -> COMBAT -> PURSUING` transitions within 1 second.

## Root Cause

A race condition in the visibility checking system caused by the order of operations in `_physics_process()`:

1. `_check_player_visibility()` uses the enemy model's current rotation for FOV checking
2. `_update_enemy_model_rotation()` updates rotation based on visibility result
3. When enemy is moving, velocity-based rotation could override player-facing rotation
4. This caused the model to rotate away, making the player exit the FOV

## Solution

Modified `_check_player_visibility()` to skip FOV checks when in combat-related states. The rationale:
- FOV should restrict **initial detection** only
- Once in combat, enemies maintain situational awareness of the player
- Line-of-sight (raycast) is still required - walls still block vision

## Files Changed

- `scripts/objects/enemy.gd` - Modified `_check_player_visibility()` to skip FOV check in combat states

## Log Files

- `game_log_20260125_090013.txt` - Shows repeated IDLE->COMBAT->PURSUING transitions
- `game_log_20260125_090150.txt` - Additional reproduction of the issue

## Related Issues

- Issue #347: Smooth rotation for visual polish
- Issue #332: Corner checking during movement
- Issue #367: FLANKING/PURSUING wall-stuck detection
