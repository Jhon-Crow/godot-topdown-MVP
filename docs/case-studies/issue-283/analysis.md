# Case Study: Issue #283 - Offensive Grenade Not Exploding on Enemy Hit

## Issue Summary

**Title:** fix наступательную гранату (fix offensive grenade)

**Problem:** The offensive grenade (FragGrenade) does not explode when it hits an enemy. Currently, it only explodes when hitting walls or landing on the ground.

**Reported Date:** 2026-01-24

## Evidence

### Log Files Analysis

Three game log files were provided that demonstrate the issue:

1. `game_log_20260124_000025.txt` (18,733 lines)
2. `game_log_20260124_001256.txt` (3,292 lines)
3. `game_log_20260124_001617.txt` (20,316 lines)

### Key Log Entries

The most critical log entries that demonstrate the bug:

```
[00:21:57] [GrenadeBase] Collision detected with Enemy3 (type: CharacterBody2D)
[00:21:57] [FragGrenade] Non-wall collision (body: Enemy3, type: CharacterBody2D) - not triggering explosion
```

```
[00:22:13] [GrenadeBase] Collision detected with Enemy3 (type: CharacterBody2D)
[00:22:13] [FragGrenade] Non-wall collision (body: Enemy3, type: CharacterBody2D) - not triggering explosion
```

### Timeline of Events

1. **T+0s**: Player throws FragGrenade
2. **T+Xs**: Grenade flies through the air (velocity-based throw system)
3. **T+Ys**: Grenade collides with Enemy3 (CharacterBody2D)
4. **T+Ys**: Collision is detected and logged
5. **T+Ys**: Code checks if body is StaticBody2D or TileMap
6. **T+Ys**: Check fails (Enemy3 is CharacterBody2D)
7. **T+Ys**: Explosion is NOT triggered
8. **T+Ys**: Log message: "Non-wall collision - not triggering explosion"
9. **T+Zs**: Grenade continues flying until hitting a wall or landing
10. **T+Zs**: Eventually explodes on wall/ground impact

### Successful Explosion Cases

For comparison, here are examples of successful explosions:

```
[00:21:55] [GrenadeBase] Collision detected with Room2_WallLeft (type: StaticBody2D)
[00:21:55] [FragGrenade] Wall impact detected! Body: Room2_WallLeft, triggering explosion
```

```
[00:22:07] [GrenadeBase] Collision detected with Table1 (type: StaticBody2D)
[00:22:07] [FragGrenade] Wall impact detected! Body: Table1, triggering explosion
```

## Root Cause Analysis

### Code Location

File: `scripts/projectiles/frag_grenade.gd`
Method: `_on_body_entered(body: Node)`
Lines: 120-132

### Current Implementation

```gdscript
func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)

	# Only explode on impact if we've been thrown and haven't exploded yet
	if _is_thrown and not _has_impacted and not _has_exploded:
		# Trigger impact explosion on wall/obstacle hit
		if body is StaticBody2D or body is TileMap:
			FileLogger.info("[FragGrenade] Wall impact detected! Body: %s, triggering explosion" % body.name)
			_trigger_impact_explosion()
		else:
			FileLogger.info("[FragGrenade] Non-wall collision (body: %s, type: %s) - not triggering explosion" % [body.name, body.get_class()])
```

### Root Cause

The collision detection logic **only triggers explosion for StaticBody2D and TileMap nodes**. It explicitly excludes CharacterBody2D nodes, which are used for:
- Enemies (`scripts/objects/enemy.gd`: `extends CharacterBody2D`)
- Player (`scripts/characters/player.gd`: `extends CharacterBody2D`)

This is the direct cause of the bug - when the grenade hits an enemy (CharacterBody2D), it falls into the `else` branch and logs "Non-wall collision - not triggering explosion".

### Design Intent vs. Actual Behavior

Looking at the code comments in the file header (lines 3-13):

```gdscript
## Offensive (frag) grenade that explodes on impact and releases shrapnel.
##
## Key characteristics:
## - Explodes ONLY on landing or hitting a wall (NO timer - impact-triggered only)
## - Smaller explosion radius than flashbang
## - Releases 4 shrapnel pieces in all directions (with random deviation)
## - Shrapnel ricochets off walls and deals 1 damage each
## - Slightly lighter than flashbang (throws a bit farther/easier)
##
## Per issue requirement: "взрывается при приземлении/ударе об стену (без таймера)"
## Translation: "explodes on landing/hitting a wall (without timer)"
```

The design specification says "explodes on landing or hitting a wall" - it does NOT mention hitting enemies. However, this appears to be an oversight or incomplete specification, as:

1. Real-world offensive grenades with impact detonation would explode on ANY significant impact
2. Game balance suggests the grenade should explode on enemy hit (otherwise enemies can "catch" grenades)
3. The user reported this as a bug, expecting explosion on enemy hit

## Real-World Research

Impact-detonation grenades in the real world:

- **Arming System**: Impact grenades arm 1-2 seconds after throw, then detonate on any impact
- **Backup Timer**: Have a 3-7 second backup timer in case impact fuse fails
- **Safety**: Must travel minimum distance (usually 20+ meters) before arming
- **Detonation**: Will explode on contact with ANY solid surface once armed (ground, walls, vehicles, etc.)

Sources:
- [Impact Grenades - How Grenades Work | HowStuffWorks](https://science.howstuffworks.com/grenade3.htm)
- [Military Service Member's Guide to Grenades | TacticalGear.com](https://tacticalgear.com/experts/military-service-members-guide-to-grenades)

**Conclusion**: Real-world impact grenades would explode on hitting a person, not pass through them.

## Proposed Solutions

### Solution 1: Add CharacterBody2D to Impact Detection (Recommended)

**Change**: Add `CharacterBody2D` to the type check in `_on_body_entered`.

**Pros**:
- Minimal code change
- Explicit and clear
- Maintains existing logic structure
- Easy to understand and maintain

**Cons**:
- Hardcoded type checking
- Need to update if new body types added

**Implementation**:
```gdscript
if body is StaticBody2D or body is TileMap or body is CharacterBody2D:
	FileLogger.info("[FragGrenade] Impact detected! Body: %s, triggering explosion" % body.name)
	_trigger_impact_explosion()
```

### Solution 2: Explode on Any Body Impact

**Change**: Remove type checking, explode on any body collision.

**Pros**:
- Most flexible
- Matches real-world behavior (explodes on any impact)
- Future-proof for new body types

**Cons**:
- Might cause unexpected explosions on non-solid objects
- Less control over what triggers explosion

**Implementation**:
```gdscript
# Explode on any body impact after being thrown
FileLogger.info("[FragGrenade] Impact detected! Body: %s (type: %s), triggering explosion" % [body.name, body.get_class()])
_trigger_impact_explosion()
```

### Solution 3: Use Collision Layers/Masks

**Change**: Use physics collision layers to determine if impact should explode.

**Pros**:
- Most configurable via editor
- Best practice for Godot physics
- Can fine-tune what triggers explosion

**Cons**:
- Requires collision layer setup
- More complex implementation
- May need changes to existing scenes

### Recommendation

**Use Solution 1** - Add `CharacterBody2D` to the type check. This is:
- The safest change with minimal risk
- Explicit about what triggers explosion
- Easy to review and understand
- Solves the reported bug directly
- Maintains backward compatibility

## Testing Plan

After implementing the fix, the following tests should be performed:

1. **Manual Testing**:
   - Throw grenade at enemy - should explode on contact
   - Throw grenade at wall - should explode on contact
   - Throw grenade at ground - should explode on landing
   - Throw grenade at player - should explode on contact

2. **Unit Testing**:
   - Update `tests/unit/test_frag_grenade.gd` to verify explosion on enemy hit
   - Test that grenade doesn't explode before being thrown

3. **Integration Testing**:
   - Run game and verify grenades work in all scenarios
   - Check that damage is properly applied on enemy impact
   - Verify shrapnel spawns correctly

## Implementation Notes

- Update log message to be more generic: "Impact detected!" instead of "Wall impact detected!"
- Consider adding a comment explaining why these specific types trigger explosion
- Ensure grenade still doesn't explode during initial spawn/setup (before `_is_thrown` is true)
