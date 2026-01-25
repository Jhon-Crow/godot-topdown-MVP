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

## Evolution of Solutions

### Iteration 1: Alignment-Based Wall-Stuck Detection
Initial fix added alignment-based detection: if enemy movement direction doesn't align with target direction (dot product < 0.3), they're considered "sliding on wall". This caught some stuck scenarios but was insufficient.

### Iteration 2: Global Position-Based Stuck Detection (Final Solution)
User testing revealed the alignment-based approach was still failing - enemies would cycle between FLANKING -> PURSUING in a loop, all stuck at the same wall position (~770, 975).

**Final solution**: Global position-based timeout. If enemy stays within 30 units of the same position for 4+ seconds without direct player contact (can't see AND hit player), force transition to SEARCHING state.

This approach is more robust because:
- Catches ALL stuck scenarios regardless of movement alignment
- Only triggers when enemy has no valid engagement (not in player contact)
- Uses same pattern as SEARCHING state stuck detection

## Key Evidence from Logs

### Original Issue (game_log_20260125_073543.txt)
All FLANKING timeouts occur at **x=887.9** (wall edge):
- Enemy3: pos=(887.9341, 754.4363)
- Enemy2: pos=(887.9336, 880.9666)
- Enemy4: pos=(887.9341, 754.4492)

### After First Fix (game_log_20260125_082704.txt)
Enemies cycle between states at same position:
- Enemy1, Enemy2, Enemy4 all stuck at pos=(770.68, 975.93)
- FLANKING stuck (2.0s) -> PURSUING -> FLANKING (repeat)

## Key Files

- `scripts/objects/enemy.gd` - Main enemy AI script
  - `_physics_process()` - Global stuck detection (lines ~953-980)
  - `_calculate_flank_position()` - Line ~3413
  - `_process_flanking_state()` - Line ~1790
  - `_transition_to_flanking()` - Line ~2592

## Solution Implementation

1. **Global position-based stuck detection** - In `_physics_process()`, track position over time during PURSUING/FLANKING
2. **4-second timeout** - If enemy hasn't moved 30+ units in 4 seconds without player contact, force SEARCHING
3. **LOS validation for flank positions** - Ensure flank position has line-of-sight to player before attempting
4. **Reduced distance fallback** - Try 50% distance flank positions if full distance fails

## Log Files

- `game_log_20260125_073543.txt` - Original user-provided log showing wall-corner stuck behavior
- `game_log_20260125_082704.txt` - User testing log showing FLANKING/PURSUING loop (fixed in iteration 2)
