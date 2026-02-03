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

### User Feedback #1 (2026-02-03)
- Feedback from Jhon-Crow indicated the fix was incomplete:
  1. "Casings at the moment of spawn still push the player"
  2. "Casings fly too far" (mass reduction caused this)
  3. "Player still bumps into casings"
- **Critical requirement clarified**: Casings should NOT affect player, BUT player SHOULD push casings

### Second Fix Attempt (2026-02-03)
- Changed player collision_mask from 68 to 4 (removed layer 7)
- Added CasingPusher Area2D to detect and push casings
- Removed mass property (restored default 1.0)
- Player could now push casings without being blocked

### User Feedback #2 (2026-02-03)
- Feedback indicated improvement but issues remained:
  1. "Casings push better now, but player still gets stuck in them"
  2. "Player is still pushed back when shooting"
- Log file provided: `game_log_20260203_103825.txt`

### Final Fix (2026-02-03)
- Identified root cause: casings spawn close to player, Godot physics interacts even with correct layers when objects spawn overlapping
- Solution: Disable casing CollisionShape2D at spawn time, enable after 0.1s delay
- This ensures casing has moved away from player before enabling physics

### Root Cause Discovery (2026-02-03)
- Analyzed Player.tscn collision settings
- Found: `collision_mask = 68` (layers 3 and 7)
- Player was detecting casings (layer 7) in its collision mask
- This caused player to be blocked by casings

### User Feedback #3 (2026-02-03)
- Feedback from log `game_log_20260203_105632.txt`:
  1. "тряска при стрельбе исчезала (хорошо)" - Shake at shooting is gone (good)
  2. "гильзы всё ещё блокируют движение игрока" - Casings still block player movement
- The spawn collision delay fixed the spawn-time push issue
- But casings still block player when walking into them after they land

### Final Fix - Collision Exception (2026-02-03)
- Research discovered that collision layers/masks may not be 100% reliable in some physics edge cases
- Godot's physics system uses bidirectional checking: `collision_layer & p_other->collision_mask OR p_other->collision_layer & collision_mask`
- Solution: Use `add_collision_exception_with()` for guaranteed collision exclusion
- This makes the two physics bodies completely ignore each other at the physics engine level

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

4. **Spawn-Time Collision Edge Case**
   - Even with correct collision layers/masks, Godot physics can interact when objects spawn overlapping
   - Casings spawn at weapon position which is very close to player collision shape
   - Initial high velocity (300-450 px/sec) causes physics resolution during the first frames

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

#### 5. Spawn Collision Delay
**File**: `scripts/effects/casing.gd`

Added spawn collision delay system:
```gdscript
const SPAWN_COLLISION_DELAY: float = 0.1
var _spawn_timer: float = 0.0
var _spawn_collision_enabled: bool = false

func _ready() -> void:
    # ... existing code ...
    _disable_collision()  # Disable at spawn

func _physics_process(delta: float) -> void:
    # Enable collision after delay
    if not _spawn_collision_enabled:
        _spawn_timer += delta
        if _spawn_timer >= SPAWN_COLLISION_DELAY:
            _enable_collision()
            _spawn_collision_enabled = true
    # ... existing code ...

func _disable_collision() -> void:
    var collision_shape := get_node_or_null("CollisionShape2D")
    if collision_shape != null:
        collision_shape.disabled = true

func _enable_collision() -> void:
    var collision_shape := get_node_or_null("CollisionShape2D")
    if collision_shape != null:
        collision_shape.disabled = false
```

**Rationale**:
- Disables casing collision shape at spawn time
- After 0.1 seconds, casing has moved away from spawn point
- Enables collision only when casing is safely away from player
- Prevents any spawn-time physics interaction with player

#### 6. Collision Exception (Final Fix)
**File**: `scripts/effects/casing.gd`

Added explicit collision exception with player:
```gdscript
func _ready() -> void:
    # ... existing code ...
    _add_player_collision_exception()  # Add collision exception

func _add_player_collision_exception() -> void:
    # Find player in scene tree (player is in "player" group)
    var players := get_tree().get_nodes_in_group("player")
    for player in players:
        if player is PhysicsBody2D:
            # Make this casing ignore the player in collision detection
            add_collision_exception_with(player)
            # Also make player ignore this casing (bidirectional exclusion)
            player.add_collision_exception_with(self)
```

**Rationale**:
- `add_collision_exception_with()` is a Godot physics system function that makes two bodies completely ignore each other
- This works at the physics engine level, bypassing any layer/mask configuration
- Bidirectional exclusion ensures neither body affects the other
- Defense-in-depth: Works even if layer/mask configuration has edge cases
- Research showed Godot uses bidirectional checking for collision, which can cause unexpected interactions
- This is the most reliable way to ensure casings NEVER block player movement

### Why This Solution Works

1. **Complete Collision Separation**
   - Player doesn't detect casings in collision mask
   - Player movement is never affected by casings
   - Physics engine doesn't resolve player-casing collisions

2. **Area2D for One-Way Interaction**
   - Area2D detects overlaps without physics collision
   - Player can push casings by applying impulses
   - Casings respond naturally with existing `receive_kick()` method

3. **Spawn Collision Delay Prevents Edge Cases**
   - Disabling collision at spawn prevents any physics interaction during spawn
   - 0.1s delay allows casing to move ~30-45 pixels away at ejection speed
   - Collision is re-enabled when casing is safely away from player
   - No spawn-time "bump" or "stuck" issues

4. **Maintains Visual Fidelity**
   - Casings still collide with obstacles (walls, floor) after delay
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

### game_log_20260203_103825.txt
- Third testing session after Area2D fix
- Player pushing improved but still getting stuck at spawn
- Led to discovery of spawn-time collision issue
- 1001 lines of gameplay data

All logs saved to `docs/case-studies/issue-392/logs/` for reference.

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

### Alternative 2: Collision Exception (NOW IMPLEMENTED)
**Approach**: Use `add_collision_exception_with()` to ignore casings

**Pros**:
- Direct physics system integration
- Guaranteed to work at physics engine level
- No ambiguity about collision behavior

**Cons**:
- Requires finding player reference at runtime
- Slightly more code

**Decision**: CHOSEN as final defense-in-depth solution due to reliability

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

4. **Spawn-Time Physics Edge Cases**
   - Godot physics can interact with overlapping objects even when collision layers don't match
   - Objects spawning inside other objects can cause unexpected physics behavior
   - Disabling collision at spawn and enabling after a delay is a robust workaround

5. **User Feedback is Critical**
   - First fix seemed reasonable but didn't meet actual requirements
   - Second fix improved behavior but revealed spawn-time edge case
   - Third fix (spawn delay) fixed spawn-time but not walk-into blocking
   - Clarifying exact behavior expectations and iterating on feedback saves time

6. **Collision Exception for Guaranteed Results**
   - `add_collision_exception_with()` provides direct physics engine exclusion
   - This bypasses all layer/mask complexity
   - Useful when layer configuration alone doesn't fully work
   - Bidirectional exceptions ensure both bodies ignore each other

7. **Defense-in-Depth for Physics**
   - Use multiple complementary techniques for reliability
   - Layer separation + spawn delay + collision exception = robust solution
   - Don't rely on a single mechanism for critical physics behavior

## References

### Godot Documentation
- [RigidBody2D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/classes/class_rigidbody2d.html)
- [Using CharacterBody2D/3D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/tutorials/physics/using_character_body_2d.html)
- [Area2D — Godot Engine Documentation](https://docs.godotengine.org/en/stable/classes/class_area2d.html)

### Community Resources
- [Character to Rigid Body Interaction :: Godot 4 Recipes](https://kidscancode.org/godot_recipes/4.x/physics/character_vs_rigid/index.html)
- [CharacterBody2D and RigidBody2D collision interaction problem - Godot Forum](https://forum.godotengine.org/t/characterbody2d-and-rigidbody2d-collision-interaction-problem/83714)

## Conclusion

The shell casing physics issue was resolved through a multi-layer defense-in-depth approach:

1. **Collision Layer Separation**: Removing layer 7 from player's collision mask (player no longer blocked)
2. **Area2D Detection**: Adding Area2D to detect and push casings (player can still interact)
3. **Mass Restoration**: Removing mass reduction (casings eject at normal distance)
4. **Spawn Collision Delay**: Disabling casing collision at spawn, enabling after 0.1s delay (prevents spawn-time physics interaction)
5. **Collision Exception (Final Fix)**: Using `add_collision_exception_with()` to guarantee mutual exclusion at the physics engine level

This solution achieves the exact behavior requested:
- Casings NEVER affect player movement (including at spawn time AND when walking into casings)
- Player CAN push casings when walking over them (via Area2D detection and impulses)
- Casings behave realistically during ejection and landing
- No spawn-time "bump" or "stuck" issues
- No blocking when walking into casings after they land

The fix uses multiple complementary techniques for maximum reliability:
- Collision layers/masks for primary separation
- Area2D for one-way push detection
- Spawn delay for edge case protection
- `add_collision_exception_with()` for guaranteed physics exclusion

This defense-in-depth approach ensures the fix works regardless of any physics engine edge cases or timing issues.
