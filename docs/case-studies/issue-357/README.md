# Issue #357: Enemies Navigate Corners Without Looking

## Problem Statement

Enemies navigate around corners without turning to look toward the corner where the player might be hiding. They literally walk with their backs to the player, which is tactically unrealistic and makes the game less immersive.

## Root Cause

The enemy model rotation priority system defaults to facing the movement velocity direction when the enemy cannot see the player. The existing corner check system looks **perpendicular** to movement direction (for peripheral vision detection), not **toward the suspected player position**.

## Key Files

- `scripts/objects/enemy.gd` - Main enemy AI script
  - `_update_enemy_model_rotation()` - Line 1002-1037
  - `_move_to_target_nav()` - Line 4928-4940
  - `_process_corner_check()` - Line 4103-4109
  - `_detect_perpendicular_opening()` - Line 4090-4101

## Recommended Solution

Implement a hybrid approach that combines:
1. **Target-aware corner checking** - Look toward suspected player position
2. **Navigation path look-ahead** - Anticipate turns in the navigation path
3. **Memory-based looking** - Use enemy memory system for context

See [ANALYSIS.md](./ANALYSIS.md) for detailed solutions and implementation guidance.

## Log Files

Four log files provided by the user demonstrating the bug:
- `game_log_20260125_035127.txt`
- `game_log_20260125_035837.txt`
- `game_log_20260125_035940.txt`
- `game_log_20260125_040455.txt`

## References

- [Steering Behaviors For Autonomous Characters - Craig Reynolds](https://www.red3d.com/cwr/steer/gdc99/)
- [The Predictable Problem: Why Stealth Game AI Needs an Overhaul - Wayline](https://www.wayline.io/blog/predictable-problem-stealth-game-ai-overhaul)
- [Understanding Steering Behaviors: Path Following - Envato Tuts+](https://gamedevelopment.tutsplus.com/tutorials/understanding-steering-behaviors-path-following--gamedev-8769)
