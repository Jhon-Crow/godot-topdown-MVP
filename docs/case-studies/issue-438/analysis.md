# Issue #438: Enemies Get Stuck in Shell Casings

## Problem Summary

**Issue:** Enemies get stuck in shell casings while the player doesn't.
**Reported behavior:** Player can walk through areas with shell casings without issue, but enemies get stuck/blocked when they encounter casings on the ground.

## Timeline of Events

1. Player fires weapon, ejecting shell casings
2. Casings land on the ground (RigidBody2D objects on collision layer 64)
3. Enemy attempts to move through area with casings
4. Enemy gets stuck/blocked by the casings

## Root Cause Analysis

### The Core Issue: Different Collision Handling Strategies

The player and enemies use **fundamentally different approaches** to handle casing interactions:

#### Player Implementation (Working)

```
Player.tscn:
  collision_mask = 4    (Only walls/obstacles - Layer 3)

  CasingPusher (Area2D child):
    collision_mask = 64  (Casings only - Layer 7)
```

- Player's `CharacterBody2D` does NOT include casings in its `collision_mask`
- Separate `CasingPusher` Area2D detects casings via signals (`body_entered`/`body_exited`)
- Player tracks overlapping casings in `_overlapping_casings` array
- During `_physics_process()`, player calls `_push_casings()` which kicks casings away
- **Result:** Player never physically collides with casings, just pushes them away

#### Enemy Implementation (Broken)

```
Enemy.tscn:
  collision_mask = 68   (Walls + Casings - Layers 3 + 7)

  No CasingPusher Area2D
```

- Enemy's `CharacterBody2D` INCLUDES casings in its `collision_mask` (64 = layer 7)
- Enemy has `_push_casings()` method that uses `get_slide_collision()` after `move_and_slide()`
- **Problem:** When `move_and_slide()` encounters a RigidBody2D (casing), it treats it as a blocking collision
- The enemy gets stuck because `move_and_slide()` stops movement when hitting casings
- Even though `_push_casings()` kicks the casing, the enemy has already been blocked for that frame

### Casing Configuration

```
Casing.tscn (RigidBody2D):
  collision_layer = 64  (Layer 7 - casings)
  collision_mask = 4    (Layer 3 - walls only)
```

Casings only collide with walls, not with characters. This is correct design - the casing shouldn't push back against characters.

### Why `get_slide_collision()` Doesn't Work Well Here

The enemy's approach relies on `get_slide_collision()` which only returns collisions that occurred **during** `move_and_slide()`. However:

1. `move_and_slide()` treats the collision as blocking
2. Enemy velocity is reduced/stopped by the collision
3. Only then does `_push_casings()` attempt to kick the casing
4. By this point, the enemy has already lost momentum for this frame

The player's approach is better because:
1. Player never collides with casings (they're not in collision_mask)
2. Area2D continuously tracks overlapping casings
3. Push happens without any blocking collision

## Solution

Apply the same pattern used for the player to enemies:

### Step 1: Remove casing layer from enemy collision_mask

Change `Enemy.tscn`:
```
collision_mask = 68  ->  collision_mask = 4
```

This removes layer 7 (casings) from enemy collision detection.

### Step 2: Add CasingPusher Area2D to Enemy

Add to `Enemy.tscn`:
```
[node name="CasingPusher" type="Area2D" parent="."]
collision_layer = 0
collision_mask = 64
monitorable = false

[node name="CasingPusherShape" type="CollisionShape2D" parent="CasingPusher"]
shape = SubResource("CircleShape2D_casing_pusher")
```

### Step 3: Update enemy.gd to use Area2D-based casing detection

Add:
- `@onready var _casing_pusher: Area2D = $CasingPusher`
- `var _overlapping_casings: Array[RigidBody2D] = []`
- Signal connections for `body_entered`/`body_exited`
- Update `_push_casings()` to use `_overlapping_casings` instead of `get_slide_collision()`

## Files Changed

1. `scenes/objects/Enemy.tscn` - Add CasingPusher Area2D, fix collision_mask
2. `scripts/objects/enemy.gd` - Add Area2D-based casing detection logic

## References

- Issue #392: Original casing collision fix for player
- Issue #341: First implementation of casing pushing
- Issue #424: Casing push direction improvements
- `scripts/characters/player.gd:2616-2694` - Reference implementation for player
- `scripts/effects/casing.gd:196-216` - `receive_kick()` method
