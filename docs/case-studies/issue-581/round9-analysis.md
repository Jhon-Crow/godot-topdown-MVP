# Round 9 Root Cause Analysis — Sniper Bugs

## User-Reported Symptoms (2026-02-08)
1. Snipers don't deal damage to the player
2. No smoke trail (tracer) visible when snipers fire
3. Snipers don't hide in cover from the player
4. Snipers have no laser sight

## Game Log Analysis

**File**: `game_log_20260208_174909.txt` (4061 lines, ~2 minutes of gameplay on City map)

### Key observations:
- Snipers DO fire (GUNSHOT sound events at ~3s intervals = bolt-action cycling works)
- **ZERO "HITSCAN HIT" log entries** — hitscan raycast never detects the player
- **Empty SNIPER FIRED log lines** — format string produces empty output on certain locales
- **Rapid state thrashing**: `COMBAT → SEEKING_COVER → IN_COVER → COMBAT` in single frames
- **Snipers pursuing player**: "Player vulnerable (reloading) - pursuing to attack" messages

### Timeline reconstruction (selected events):

| Time | Event |
|------|-------|
| 17:49:15 | CityLevel loaded, SniperEnemy1 at (5600,400), SniperEnemy2 at (5600,4700) |
| 17:49:32 | SniperEnemy1 detects player, IDLE → COMBAT |
| 17:49:33 | First shot blocked: aim_dot=-0.678 (132.7° off) — still rotating |
| 17:49:39 | First GUNSHOT fires. Empty SNIPER FIRED log. No HITSCAN HIT. |
| 17:49:42 | Second GUNSHOT. Still no HITSCAN HIT. |
| 17:49:55 | SniperEnemy1 runs out of ammo (5 rounds in magazine) |
| 17:49:59 | SniperEnemy2 enters "pursuing to attack" on player reload |
| 17:50:13 | State thrashing begins: COMBAT→SEEKING_COVER→IN_COVER→COMBAT in 1 frame |
| 17:50:17 | SniperEnemy2 runs out of ammo |
| 17:51:31 | State thrashing continues for SniperEnemy1 |

## Root Causes Found

### RC-1: Hitscan self-collision (HitArea not excluded)

**Location**: `sniper_component.gd:93-97`, `sniper_component.gd:228-231`

The `perform_hitscan()` function excluded the enemy's CharacterBody2D RID from the raycast:
```gdscript
var exclude_rids: Array[RID] = [enemy.get_rid()]  # Only excludes CharacterBody2D
```

But each enemy also has an `HitArea` (Area2D) child on `collision_layer = 2`. With `collide_with_areas = true` and mask 7 (includes layer 2), the hitscan raycast **hit the sniper's own HitArea** at ~0 distance. This:
- Caused the sniper to take self-damage
- Made the hitscan continue from the HitArea's position (still near the sniper) but with the same problem on subsequent iterations
- Prevented the raycast from ever reaching the player

**Same bug in `update_laser()`**: The laser raycast also only excluded the CharacterBody2D, not the HitArea. The laser terminated at the HitArea position (~0 pixels from start), making it invisible (a single point Line2D).

### RC-2: Damage not delivered through correct method

**Location**: `sniper_component.gd:144-157`

Even if hitscan hit the player, `on_hit_with_info(-direction, null)` was called, which passes default `damage = 1.0`. The configured `hitscan_damage = 50.0` was only passed to `take_damage(damage)` which was never reached because `on_hit_with_info` method exists and takes priority.

### RC-3: Muzzle position / shot direction mismatch

**Location**: `enemy.gd:3846-3853`

Bullet spawn position used `_get_bullet_spawn_position(weapon_forward)` where `weapon_forward = _get_weapon_forward_direction()` (weapon sprite direction, pointing at player). But the shot direction used `Vector2.from_angle(rotation)` (body rotation). At long range, even a small angular difference between weapon sprite and body rotation caused the hitscan to miss entirely.

### RC-4: Cover state thrashing (IN_COVER → COMBAT immediate transition)

**Location**: `enemy.gd:4001-4002`

`_process_sniper_in_cover_state()` checked `_can_see_player` and immediately transitioned to COMBAT:
```gdscript
if _can_see_player and _player:
    _transition_to_combat(); return
```

Since the sniper typically has LOS to the player even from its "cover" position (especially when no actual cover exists on the map), this created an infinite loop:
1. COMBAT: player too close → SEEKING_COVER
2. SEEKING_COVER: no cover found → settle at current position → IN_COVER
3. IN_COVER: can see player → COMBAT (immediate, same frame)
4. Back to step 1

### RC-5: Snipers pursuing on player vulnerability

**Location**: `enemy.gd:1250`

The "Player vulnerable - pursuing" priority action path lacked a `not _is_sniper` guard:
```gdscript
if player_is_vulnerable and _can_see_player and _player and not player_close:
```

This caused snipers to transition to PURSUING state when the player reloaded, contradicting their GUARD behavior.

## Fixes Applied

1. **HitArea exclusion**: Added `extra_exclude_rids` parameter to `perform_hitscan()` and `update_laser()`. Enemy passes `_hit_area.get_rid()` to exclude its own HitArea from raycast.

2. **Correct damage delivery**: Added `on_hit_with_bullet_info` as the first-priority damage method, passing actual hitscan damage (50.0).

3. **Consistent muzzle/direction**: Snipers now use body rotation (`aim_check_dir`) for both spawn position calculation and shot direction.

4. **Snipers stay in cover**: Replaced immediate IN_COVER → COMBAT transition with in-cover shooting logic. Snipers now aim and shoot from cover when they see the player.

5. **Snipers don't pursue**: Added `not _is_sniper` guard to the "Player vulnerable - pursuing" path.
