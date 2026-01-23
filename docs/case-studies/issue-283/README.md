# Issue #283: Offensive Grenade Not Exploding on Enemy Hit

## Quick Summary

**Problem**: FragGrenade (offensive grenade) doesn't explode when hitting enemies.

**Root Cause**: Code in `scripts/projectiles/frag_grenade.gd:127` only checks for `StaticBody2D` and `TileMap` collisions, excluding `CharacterBody2D` (which enemies use).

**Fix**: Add `CharacterBody2D` to the collision type check.

## Files in This Case Study

1. **README.md** (this file) - Quick overview
2. **analysis.md** - Detailed root cause analysis, timeline reconstruction, and solution proposals
3. **logs/** - Original game logs provided in the issue report
   - `game_log_20260124_000025.txt`
   - `game_log_20260124_001256.txt`
   - `game_log_20260124_001617.txt`
4. **grenade-log-entries.txt** - Extracted grenade-related log entries
5. **grenade-collision-entries.txt** - Extracted collision-related log entries

## Evidence

The logs clearly show the grenade detecting enemy collisions but not exploding:

```
[00:21:57] [GrenadeBase] Collision detected with Enemy3 (type: CharacterBody2D)
[00:21:57] [FragGrenade] Non-wall collision (body: Enemy3, type: CharacterBody2D) - not triggering explosion
```

## Solution

Change line 127 in `scripts/projectiles/frag_grenade.gd`:

**Before:**
```gdscript
if body is StaticBody2D or body is TileMap:
```

**After:**
```gdscript
if body is StaticBody2D or body is TileMap or body is CharacterBody2D:
```

Also update the log message on line 128 from "Wall impact detected!" to "Impact detected!" to be more accurate.

## External Research

Impact detonation grenades in real-world military applications explode on any significant impact (walls, ground, vehicles, personnel) once armed. This supports the expected behavior that grenades should explode on enemy contact.

**Sources:**
- [Impact Grenades - How Grenades Work | HowStuffWorks](https://science.howstuffworks.com/grenade3.htm)
- [Military Service Member's Guide to Grenades | TacticalGear.com](https://tacticalgear.com/experts/military-service-members-guide-to-grenades)

## Testing

After the fix is implemented, verify:
1. ✅ Grenade explodes when hitting enemies
2. ✅ Grenade still explodes when hitting walls
3. ✅ Grenade still explodes when landing on ground
4. ✅ Damage is correctly applied on enemy impact
5. ✅ Shrapnel spawns correctly on all impact types

## Related Files

- `scripts/projectiles/frag_grenade.gd` - Main file requiring fix
- `scripts/objects/enemy.gd` - Enemy class definition (extends CharacterBody2D)
- `scripts/projectiles/grenade_base.gd` - Base grenade class
- `tests/unit/test_frag_grenade.gd` - Unit tests (may need updating)
