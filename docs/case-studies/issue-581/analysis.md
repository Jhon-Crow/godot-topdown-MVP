# Case Study: Issue #581 — Sniper Enemy Round 8 Bug Analysis

## Source Data
- **Game log**: `game_log_20260208_164625.txt` (5021 lines, ~2 min play session on City map)
- **Reported by**: Jhon-Crow (2026-02-08)
- **Reported bugs**: 3 issues with sniper enemy behavior

## Bug 1: Enemy in IN_COVER despite direct line of sight to player

### Symptoms
- SniperEnemy stays in `IN_COVER` state while player can see it directly
- Log shows `IN_COVER -> SEEKING_COVER -> IN_COVER` oscillation every ~3 seconds

### Timeline from log
1. `16:47:42` — SniperEnemy1 retreats: `SNIPER: retreating, player very close (730)`
2. `16:47:42` — `COMBAT -> SEEKING_COVER -> IN_COVER` (no actual cover found, settles at current position)
3. `16:47:45` — `IN_COVER -> SEEKING_COVER -> IN_COVER` (3s cooldown expired, re-seeks)
4. Pattern repeats every 3 seconds until end of session

### Root Cause
`_process_sniper_in_cover_state()` (enemy.gd:3996-4015) never transitions back to COMBAT state when the sniper has direct line of sight to the player. The function only:
- Re-seeks cover when player is close (every 3s due to cooldown)
- Shoots from cover if `_can_see_player` is true

Compare with non-sniper IN_COVER logic (enemy.gd:1615-1698) which properly checks `_can_see_player` and transitions to COMBAT.

### Fix
Added check: if sniper can see the player directly from IN_COVER, transition to COMBAT state immediately. This allows the sniper to properly aim and shoot through the normal combat state flow.

## Bug 2: Enemy shoots but no smoke trail and no damage

### Symptoms
- Muzzle flash visible when sniper fires
- No smoke tracer line visible
- No damage dealt to player

### Timeline from log
1. `16:47:31` — First sniper shot: `Player distracted - priority attack triggered` followed by empty log line and SoundPropagation event
2. `16:47:35` — Second shot: `SNIPER: shooting through 0 walls` followed by empty log line
3. No `SNIPER FIRED:` log entries found (0 occurrences) despite ~30 shots fired
4. `_can_shoot()=false (bolt=true, reloading=true, ammo=0)` appears at `16:47:47` — only 16 seconds after first shot

### Root Cause Analysis

**Sub-issue A: "Player distracted" snap-aim bypass**
The "Player distracted" priority attack path (enemy.gd:1165-1188) fires BEFORE the sniper-specific state processing. This path:
- Snap-rotates the sniper instantly (`rotation = direction_to_player.angle()`)
- Bypasses the sniper's slow rotation mechanic (designed to be ~25x slower)
- Called every 3s when player aims away, consuming ammo rapidly through the normal `_shoot()` pipeline

**Sub-issue B: Empty log lines**
The `SNIPER FIRED:` log at enemy.gd:3871 was formatted with `%s` for Vector2 values which may produce locale-dependent output. Fixed to use explicit `%.0f` / `%.2f` formatting.

**Sub-issue C: Tracer visibility**
The smoke tracer was being created with:
- Width 5.0 pixels (thin)
- Very pale gray colors (Color(0.9, 0.9, 0.85, 0.8)) that blend with light backgrounds
- No unshaded material (invisible in dark/lit scenes)

**Sub-issue D: Damage**
The hitscan damage chain actually works: `perform_hitscan()` → `on_hit_with_info()` → player takes damage. However, no diagnostic logging existed in `perform_hitscan` to confirm hits, making it impossible to verify from logs.

### Fixes
1. Excluded snipers from "Player distracted" snap-aim path — they engage through normal slow-rotation combat
2. Excluded snipers from "Player vulnerable" snap-aim path
3. Fixed log format to use numeric formatting instead of `%s` for Vector2
4. Improved tracer: width 5→8px, brighter colors, added unshaded material
5. Added hit logging to `perform_hitscan()`: `HITSCAN HIT: <target> at <pos> (dmg=<value>)`

## Bug 3: No laser visible

### Symptoms
- Red laser sight not visible at any point during gameplay
- No laser-related log entries

### Root Cause
`SniperComponent.update_laser()` (sniper_component.gd:207-226) used raycast mask `4` (walls only). The laser raycast:
- Only collided with walls (layer 4)
- Did NOT collide with the player (layer 1) or enemies (layer 2)
- Did NOT collide with areas (HitArea)
- Did NOT exclude self from raycast

Compare with `perform_hitscan()` which correctly uses mask `4+2+1=7` and `collide_with_areas=true`.

Result: the laser extended to full 5000px range (or stopped at walls) but never terminated at the player, making it hard to see the tactical information. The laser line was mechanically present but didn't interact with game entities.

### Fix
Updated `update_laser()` raycast:
- Changed mask from `4` to `4+2+1=7` (walls + enemies + player)
- Set `collide_with_areas = true` to detect HitArea nodes
- Added `enemy.get_rid()` to exclude list to prevent self-intersection

## Summary of Changes

| File | Change |
|------|--------|
| `scripts/objects/enemy.gd` | IN_COVER→COMBAT transition on direct LOS |
| `scripts/objects/enemy.gd` | Skip snap-aim for snipers in distracted/vulnerable paths |
| `scripts/objects/enemy.gd` | Fixed SNIPER FIRED log format |
| `scripts/components/sniper_component.gd` | Laser mask 4→7, areas=true, self-exclude |
| `scripts/components/sniper_component.gd` | Hitscan hit diagnostic logging |
| `scripts/components/sniper_component.gd` | Tracer: wider, brighter, unshaded material |
| `scripts/components/sniper_component.gd` | Null-check for scene_tree.current_scene in tracer |
