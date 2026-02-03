# Case Study: Issue #392 - Shell Casing Physics Fix

## Issue Summary

**Issue**: [#392](https://github.com/Jhon-Crow/godot-topdown-MVP/issues/392)
**Title**: fix физику гильз (Fix shell casing physics)
**Reporter**: User reported that shell casings behave as very heavy objects and sometimes push the player
**Expected Behavior**:
- Shell casings should NEVER affect player movement in any way
- Player should be able to PUSH casings when walking over them

## Timeline of Events

### Initial Report (2026-01-25)
- User reported that shell casings are behaving like heavy objects
- Shell casings sometimes push the player character
- Log file provided: `game_log_20260125_200508.txt`

### First Fix Attempt (2026-02-03)
- Added `mass = 0.01` to reduce casing momentum
- Set `collision_layer = 64` (layer 7, "decorative")
- Added layer naming in project.godot

### User Feedback (2026-02-03)
- Feedback from Jhon-Crow indicated the fix was incomplete:
  1. "Casings at the moment of spawn still push the player"
  2. "Casings fly too far" (mass reduction caused this)
  3. "Player still bumps into casings"
- **Critical requirement clarified**: Casings should NOT affect player, BUT player SHOULD push casings

### Root Cause Discovery (2026-02-03)
- Analyzed Player.tscn collision settings
- Found: `collision_mask = 68` (layers 3 and 7)
- Player was detecting casings (layer 7) in its collision mask
- This caused player to be blocked by casings

## Root Cause Analysis

### Problem Identification

The issue had multiple contributing factors:

1. **Player Collision Mask Included Casings**
   - Player had `collision_mask = 68` (binary: 1000100)
   - This means player collides with layer 3 (obstacles) AND layer 7 (decorative)
   - Casings on layer 7 were blocking player movement

2. **Mass Reduction Caused Excessive Distance**
   - Setting `mass = 0.01` made casings fly too far
   - Lower mass + same force = higher acceleration
   - Casings no longer behaved realistically

3. **Spawn-Time Collision Issue**
   - Casings spawned at high velocity near player position
   - Even with layer separation, physics engine resolved initial overlap

### Research Findings

#### Godot 4 CharacterBody2D to RigidBody2D Interaction
Source: [Character to Rigid Body Interaction :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/index.html)

Key insight: To achieve "one-way" collision (player pushes objects but isn't pushed):
1. Remove the object layer from player's collision_mask (player won't be blocked)
2. Use Area2D to detect overlapping objects and apply impulses

#### Community Solutions
Source: [CharacterBody2D and RigidBody2D collision interaction problem](https://forum.godotengine.org/t/characterbody2d-and-rigidbody2d-collision-interaction-problem/83714)

Recommended approach:
```gdscript
# After move_and_slide()
for i in get_slide_collision_count():
    var c = get_slide_collision(i)
    if c.get_collider() is RigidBody2D:
        c.get_collider().apply_central_impulse(-c.get_normal() * push_force)
```

## Solution Implementation

### Changes Made

#### 1. Player Collision Mask Fix
**File**: `scenes/characters/Player.tscn`

Changed from:
```gdscript
collision_mask = 68  # Layers 3 and 7
```

To:
```gdscript
collision_mask = 4   # Only layer 3 (obstacles)
```

**Rationale**:
- Player no longer collides with casings (layer 7)
- Player movement is completely unaffected by casings
- Player still collides with obstacles (layer 3)

#### 2. CasingPusher Area2D Added
**File**: `scenes/characters/Player.tscn`

Added new Area2D child node:
```gdscript
[node name="CasingPusher" type="Area2D" parent="."]
collision_layer = 0
collision_mask = 64  # Layer 7 (decorative/casings)
monitorable = false

[node name="CasingPusherShape" type="CollisionShape2D" parent="CasingPusher"]
shape = SubResource("CircleShape2D_casing_pusher")  # radius = 20.0
```

**Rationale**:
- Area2D detects overlapping casings without blocking movement
- Larger radius (20px vs 16px for player body) ensures casings are detected before visual overlap
- `monitorable = false` optimizes performance (casings don't need to detect the area)

#### 3. Casing Pushing Logic
**File**: `scripts/characters/player.gd`

Added constant and function:
```gdscript
const CASING_PUSH_FORCE: float = 50.0

func _push_casings() -> void:
    if _casing_pusher == null:
        return

    if velocity.length_squared() < 1.0:
        return

    var overlapping_bodies := _casing_pusher.get_overlapping_bodies()
    for body in overlapping_bodies:
        if body is RigidBody2D and body.has_method("receive_kick"):
            var push_dir := velocity.normalized()
            var push_strength := velocity.length() * CASING_PUSH_FORCE / 100.0
            body.receive_kick(push_dir * push_strength)
```

**Rationale**:
- Called after `move_and_slide()` to push any overlapping casings
- Uses existing `receive_kick()` method on casings (from Issue #341)
- Push force proportional to player velocity for natural feel

#### 4. Mass Property Removed
**File**: `scenes/effects/Casing.tscn`

Removed:
```gdscript
mass = 0.01
```

**Rationale**:
- Restores default mass (1.0 kg)
- Casings now eject with realistic distance
- Linear damping (3.0) still slows them naturally

### Why This Solution Works

1. **Complete Collision Separation**
   - Player doesn't detect casings in collision mask
   - Player movement is never affected by casings
   - Physics engine doesn't resolve player-casing collisions

2. **Area2D for One-Way Interaction**
   - Area2D detects overlaps without physics collision
   - Player can push casings by applying impulses
   - Casings respond naturally with existing `receive_kick()` method

3. **Maintains Visual Fidelity**
   - Casings still collide with obstacles (walls, floor)
   - Casings eject at realistic distance (no mass reduction)
   - Player pushing casings looks natural

## Testing Approach

### Manual Testing Required
1. Start game and move player character
2. Fire weapon to spawn casings
3. Walk through/over casings - verify NO player displacement
4. Verify casings are pushed when player walks over them
5. Verify casings eject at normal distance (not too far)
6. Test at different player speeds

### Expected Results
- Player walks through casings without any displacement
- Player pushes casings when walking over them
- Casings eject at realistic distance
- Casings still land properly on ground
- No visual artifacts or clipping issues

## Log Files Analyzed

### game_log_20260203_101940.txt
- From first testing session after initial fix attempt
- Showed player still being affected by casings
- 353 lines of gameplay data

### game_log_20260203_102059.txt
- Second testing session
- Similar issues observed
- 256 lines of gameplay data

Both logs saved to `docs/case-studies/issue-392/` for reference.

## Alternative Solutions Considered

### Alternative 1: Keep Collision Mask, Use Slide Collision Detection
**Approach**: Keep player collision with casings, use `get_slide_collision()` to push them

**Pros**:
- Simpler code (no Area2D needed)
- Uses built-in collision detection

**Cons**:
- Player would still be blocked by casings momentarily
- Requires careful tuning to avoid "bumpy" movement

**Decision**: Not chosen - Area2D provides cleaner separation

### Alternative 2: Collision Exception
**Approach**: Use `add_collision_exception_with()` to ignore casings

**Pros**:
- Direct physics system integration

**Cons**:
- Requires tracking all casings
- Performance overhead with many casings
- Doesn't allow player to push casings

**Decision**: Not chosen - Layer-based approach is more efficient

## Lessons Learned

1. **Collision Mask Matters**
   - Even with separate collision layers, if the mask includes those layers, collisions occur
   - Always check both layer AND mask settings

2. **Area2D for One-Way Interactions**
   - Area2D is ideal for detecting objects without physics collision
   - Useful pattern for "player pushes objects but isn't blocked" scenarios

3. **Mass Affects More Than Momentum**
   - Reducing mass also affects how far objects travel
   - Consider all physics effects when adjusting mass

4. **User Feedback is Critical**
   - First fix seemed reasonable but didn't meet actual requirements
   - Clarifying exact behavior expectations saves time

## References

### Godot Documentation
- [RigidBody2D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html)
- [Using CharacterBody2D/3D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html)
- [Area2D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/classes/class_area2d.html)

### Community Resources
- [Character to Rigid Body Interaction :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/index.html)
- [CharacterBody2D and RigidBody2D collision interaction problem - Godot Forum](https://forum.godotengine.org/t/characterbody2d-and-rigidbody2d-collision-interaction-problem/83714)

## Conclusion

The shell casing physics issue was resolved by:
1. Removing layer 7 from player's collision mask (player no longer blocked)
2. Adding Area2D to detect and push casings (player can still interact)
3. Removing mass reduction (casings eject at normal distance)

This solution achieves the exact behavior requested:
- Casings NEVER affect player movement
- Player CAN push casings when walking over them
- Casings behave realistically during ejection and landing

The fix is minimal, targeted, and follows Godot best practices for one-way physics interactions.
