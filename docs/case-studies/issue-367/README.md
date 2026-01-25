# Issue #367: Enemies Walk in Corner During FLANKING State

## Problem Statement

During the FLANKING state, enemies get stuck walking in a corner behind a wall where the player is hiding. They repeatedly trigger corner checks but never make progress toward their flank target, creating a FLANKING -> PURSUING -> FLANKING loop.

## Root Cause

When enemies attempt to flank the player who is behind a wall:
1. The flank target is calculated relative to player position without considering wall geometry
2. The flank target may be on the opposite side of a wall from the enemy
3. The enemy navigates toward the wall, gets deflected by wall avoidance
4. At wall corners, perpendicular openings are detected, causing repeated corner checks
5. The enemy oscillates at the corner until FLANKING timeout (5s), then re-enters FLANKING

## Key Evidence from Logs

All FLANKING timeouts occur at **x=887.9** (wall edge):
- Enemy3: pos=(887.9341, 754.4363)
- Enemy2: pos=(887.9336, 880.9666)
- Enemy4: pos=(887.9341, 754.4492)

Corner check angles oscillate (~-142°, ~-132°, ~-120° and ~132°), indicating corner stuck behavior.

## Key Files

- `scripts/objects/enemy.gd` - Main enemy AI script
  - `_calculate_flank_position()` - Line 3413
  - `_process_flanking_state()` - Line 1757
  - `_is_flank_target_reachable()` - Line 2637
  - `_transition_to_flanking()` - Line 2594

## Solution

1. **Add LOS validation to flank position** - Ensure the calculated flank position has line-of-sight to the player
2. **Add wall-stuck early exit** - Detect when movement is perpendicular to target direction and exit FLANKING early
3. **Try opposite flank side** - If one side is blocked, try the other before giving up

See [ANALYSIS.md](./ANALYSIS.md) for detailed analysis and implementation guidance.

## Log Files

- `game_log_20260125_073543.txt` - User-provided log demonstrating the stuck behavior
