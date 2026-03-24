# Case Study: Issue #1305 — Disabling AI states does not prevent all enemies from attacking

## Summary

When the user disables the COMBAT AI state via Performance Settings, some enemies
(notably snipers) continue to attack the player. The log file shows that the sniper
`ContainerYardA_Sniper` fires via the "Player distracted - priority attack triggered"
path even after COMBAT was explicitly disabled at 06:01:10.

## Timeline of Events (from game_log_20260322_060057.txt)

| Time     | Event |
|----------|-------|
| 06:00:57 | Game started, PerformanceSettings initialized (all AI states enabled) |
| 06:01:10 | User disables AI state COMBAT |
| 06:01:11 | User disables SEEKING_COVER, IN_COVER |
| 06:01:12 | User disables FLANKING, SUPPRESSED |
| 06:01:13 | User disables RETREATING, PURSUING |
| 06:01:14 | User disables ASSAULT, SEARCHING |
| 06:01:19 | Level loads with ContainerYardA_Sniper spawning |
| 06:01:34 | **BUG**: Sniper fires via "Player distracted - priority attack triggered" |
| 06:01:34 | Sniper hits player for 50 damage via hitscan |

## Root Cause Analysis

The Performance Settings system (Issue #1186) correctly guards **state transitions**
via `_transition_to_combat()`, `_transition_to_pursuing()`, etc. When COMBAT is
disabled, `_transition_to_combat()` redirects to IDLE.

However, `_process_ai_state()` in `enemy.gd` has **priority attack paths** that
execute **before** the state machine match block. These paths shoot directly
without checking whether combat-related states are enabled:

### Bypass Path 1: Player Distracted Attack (line ~1230)
- Condition: Player aim > 23 degrees off enemy, Hard difficulty
- Action: Immediate shot, bypassing state machine entirely
- **No PerformanceSettings check**

### Bypass Path 2: Player Vulnerable Attack (line ~1271)
- Condition: Player reloading or out of ammo, close range, line of sight
- Action: Immediate shot
- **No PerformanceSettings check**

### Bypass Path 3: Player Vulnerable Pursuit (line ~1291)
- Condition: Player vulnerable, visible but not close
- Action: Transitions to PURSUING (which has its own check, partially guarded)

### Bypass Path 4: Hit-Triggered Suppressive Fire (line ~4177)
- Condition: Enemy hit while in IDLE/SEARCHING/etc.
- Action: `_transition_to_combat()` correctly redirects to IDLE, but
  `_suppressive_fire.shoot()` on the next line fires regardless

### Bypass Path 5: Grenade Throwing (line ~1315)
- Condition: Ready to throw grenade
- Action: Throws grenade without checking combat state

## Fix Applied

1. Added a single `_combat_allowed` check at the top of `_process_ai_state()` that
   queries `PerformanceSettings.is_ai_state_combat_enabled()`.
2. Gated all 4 priority attack paths with `_combat_allowed`.
3. For hit-triggered suppressive fire, added a check that `_current_state == AIState.COMBAT`
   after `_transition_to_combat()` (which will be IDLE if combat is disabled).

## Files Modified

- `scripts/objects/enemy.gd` — 5 locations patched

## Verification

The fix ensures that when COMBAT state is disabled in PerformanceSettings:
- No "Player distracted" priority attacks fire
- No "Player vulnerable" priority attacks fire
- No vulnerability-pursuit transitions occur
- No grenade throws occur
- No suppressive fire on hit occurs
- Normal state transitions (already guarded by Issue #1186) continue to work
