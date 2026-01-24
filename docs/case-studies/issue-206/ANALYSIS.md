# Issue #206: Fix Frag Grenade HE Damage

## Summary

The frag (offensive) grenade's HE (High Explosive) damage was not working correctly. Enemies within the blast zone were not being killed by the shockwave as expected.

## Timeline of Events

1. **PR #189**: Added offensive (frag) grenade with shrapnel mechanics
2. **Issue #206**: Reported that HE damage is not working - grenade should kill all living things in ~450x450 blast zone

## Root Cause Analysis

### Primary Root Cause

The `explosion_damage` value in `scenes/projectiles/FragGrenade.tscn` was incorrectly set to `2` instead of `99`:

```ini
# Before (incorrect):
explosion_damage = 2

# After (correct):
explosion_damage = 99
```

This value overrides the default `explosion_damage = 99` defined in the script `scripts/projectiles/frag_grenade.gd`.

### Evidence from Logs

From `game_log_20260122_072118.txt`:

```
[07:21:53] [ENEMY] [Enemy3] Hit taken, health: 2/3
[07:21:53] [ENEMY] [Enemy3] Hit taken, health: 1/3
[07:21:53] [INFO] [FragGrenade] Applied 2 HE damage to enemy at distance 226.7
```

The log shows only 2 damage was applied (reducing Enemy3's health from 3 to 1), when it should have been 99 damage (instantly killing the enemy).

### How the Damage System Works

The `_apply_explosion_damage` function in `frag_grenade.gd` calls `on_hit_with_info` in a loop:

```gdscript
for i in range(final_damage):
    enemy.on_hit_with_info(hit_direction, null)
```

With `explosion_damage = 2`, the loop only iterates twice, dealing 2 damage. With `explosion_damage = 99`, it iterates 99 times, which is sufficient to kill any enemy in the game (enemies have 2-4 health).

### Secondary Issue: Effect Radius

The effect radius was set to `250.0` but the user requested a ~450x450 zone. Updated to `225.0` (radius for 450 diameter circle).

## Fix Applied

### File: `scenes/projectiles/FragGrenade.tscn`

1. Changed `explosion_damage` from `2` to `99`
2. Changed `effect_radius` from `250.0` to `225.0`

### File: `scripts/projectiles/frag_grenade.gd`

1. Updated default `effect_radius` from `250.0` to `225.0` for consistency
2. Updated comment to reflect the user requirement

## Shockwave Physics Propagation

The code already correctly implements physics-based shockwave propagation:

1. The `_has_line_of_sight_to()` function performs a raycast from the grenade position to each enemy
2. Uses `collision_mask = 4` to check for obstacles (walls)
3. Only applies damage if there's clear line of sight (no walls blocking)

This means the shockwave will be blocked by walls as expected.

## Verification

After the fix:
- Enemies within 225 pixel radius of explosion receive 99 HE damage
- This is sufficient to instantly kill any enemy (max health is 4)
- Shockwave is blocked by walls (line-of-sight check)
- Shrapnel continues to work as before (4 pieces, ricochet, 1 damage each)

## Lessons Learned

1. **Scene files override script defaults**: When setting `@export var` values, the scene file's values take precedence over the script's default values
2. **Always verify exported values in scene files**: Bug was in the `.tscn` file, not the `.gd` script
3. **Log analysis is crucial**: The log clearly showed "Applied 2 HE damage" which directly pointed to the incorrect `explosion_damage` value
