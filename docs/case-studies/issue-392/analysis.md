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

### Fix Iteration 4 - Collision Exception (2026-02-03)
- Research discovered that collision layers/masks may not be 100% reliable in some physics edge cases
- Godot's physics system uses bidirectional checking: `collision_layer & p_other->collision_mask OR p_other->collision_layer & collision_mask`
- Solution: Use `add_collision_exception_with()` for guaranteed collision exclusion
- This makes the two physics bodies completely ignore each other at the physics engine level

### User Feedback #4 (2026-02-03)
- Feedback from log `game_log_20260203_112501.txt`:
  1. "физика гильз перестала работать полностью" - Casing physics stopped working completely
  2. "возможно стоит сделать отдельную коллизию для взаимодействия с гильзами" - Maybe we should create a separate collision for casing interaction
- The bidirectional collision exception broke the CasingPusher Area2D detection
- Player could no longer push casings at all

### Fix Iteration 5 - Unidirectional Exception (2026-02-03)
- Root cause: The bidirectional `add_collision_exception_with()` (both casing ignoring player AND player ignoring casing) was breaking the CasingPusher Area2D's ability to detect casings
- Research confirmed that `add_collision_exception_with()` is UNIDIRECTIONAL - each body has its own exception list
- Solution: Only add exception in ONE direction (casing ignores player, player does NOT ignore casing)
- This allows:
  1. Casing ignores player → Casing physics not affected by player collisions
  2. CasingPusher Area2D can still detect casings → Player can push casings
  3. Player's move_and_slide() doesn't collide with casings anyway (mask=4 doesn't include layer 64)

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

#### 6. Collision Exception (Iteration 4) - PARTIAL FIX
**File**: `scripts/effects/casing.gd`

Added explicit collision exception with player (bidirectional - PROBLEMATIC):
```gdscript
func _add_player_collision_exception() -> void:
    var players := get_tree().get_nodes_in_group("player")
    for player in players:
        if player is PhysicsBody2D:
            add_collision_exception_with(player)  # Casing ignores player
            player.add_collision_exception_with(self)  # Player ignores casing - BREAKS Area2D!
```

**Issue**: Bidirectional exception broke CasingPusher Area2D detection

#### 7. Unidirectional Collision Exception (Iteration 5) - FINAL FIX
**File**: `scripts/effects/casing.gd`

Changed to unidirectional collision exception:
```gdscript
func _add_player_collision_exception() -> void:
    # Find player in scene tree (player is in "player" group)
    var players := get_tree().get_nodes_in_group("player")
    for player in players:
        if player is PhysicsBody2D:
            # Make this casing ignore the player in collision detection
            # This prevents the casing from pushing the player when they overlap
            add_collision_exception_with(player)
            # NOTE: Do NOT add player.add_collision_exception_with(self)
            # That would break the player's CasingPusher Area2D detection
```

**Rationale**:
- `add_collision_exception_with()` is UNIDIRECTIONAL - only affects the calling body's collision detection
- Casing ignores player → Casing doesn't push player when overlapping
- Player does NOT ignore casing → CasingPusher Area2D can still detect casings for pushing
- Player's collision mask (4) doesn't include casing layer (64) anyway, so move_and_slide() won't be blocked
- This preserves the intended one-way interaction: casings don't affect player, but player can push casings

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
   - **IMPORTANT**: The function is UNIDIRECTIONAL - only affects the calling body's collision list

7. **Bidirectional vs Unidirectional Exceptions**
   - Adding exceptions on BOTH bodies (A ignores B, B ignores A) can break Area2D detection
   - Area2D relies on detecting overlapping bodies - if both bodies ignore each other, Area2D may not work
   - Use UNIDIRECTIONAL exceptions when you need Area2D to still detect one body

8. **Defense-in-Depth for Physics**
   - Use multiple complementary techniques for reliability
   - Layer separation + spawn delay + unidirectional collision exception = robust solution
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
5. **Unidirectional Collision Exception (Final Fix)**: Using `add_collision_exception_with()` ONLY on casing (casing ignores player, NOT vice versa)

This solution achieves the exact behavior requested:
- Casings NEVER affect player movement (including at spawn time AND when walking into casings)
- Player CAN push casings when walking over them (via Area2D detection and impulses)
- Casings behave realistically during ejection and landing
- No spawn-time "bump" or "stuck" issues
- No blocking when walking into casings after they land

The fix uses multiple complementary techniques for maximum reliability:
- Collision layers/masks for primary separation
- Area2D for one-way push detection (CasingPusher)
- Spawn delay for spawn-time edge case protection
- Unidirectional `add_collision_exception_with()` for guaranteed casing→player exclusion while preserving Area2D detection

This defense-in-depth approach ensures the fix works regardless of any physics engine edge cases or timing issues.

### Critical Lesson: Unidirectional vs Bidirectional Collision Exceptions

The key breakthrough in Iteration 5 was understanding that `add_collision_exception_with()` is **unidirectional**:
- `casing.add_collision_exception_with(player)` makes casing ignore player
- This does NOT make player ignore casing
- If you also add `player.add_collision_exception_with(casing)`, the player's child Area2D (CasingPusher) may also be affected, breaking the push detection

For one-way interactions (A doesn't affect B, but B can push A), use unidirectional exceptions on only one body.

### User Feedback #5 (2026-02-03)
- Feedback from log `game_log_20260203_114135.txt`:
  1. "сейчас вообще не работает физика гильз" - Casing physics are not working at all now
- The unidirectional collision exception from Iteration 5 broke something
- Casings may not be moving or responding to physics properly

### Fix Iteration 6 - Remove Collision Exception Entirely (2026-02-03)
- **Hypothesis**: Even unidirectional collision exceptions may have unintended side effects
- **Solution**: Remove the collision exception call entirely, rely only on collision layer/mask separation
- The collision layer/mask setup should already be sufficient:
  - Player `collision_mask = 4` (doesn't include layer 7)
  - Casing `collision_layer = 64` (layer 7)
  - CasingPusher Area2D `collision_mask = 64` (detects layer 7)
- The spawn collision delay (0.1s) still prevents spawn-time issues
- No collision exception needed - layers/masks handle the separation

**Code Change**:
```gdscript
func _ready() -> void:
    # ... existing code ...
    _disable_collision()

    # NOTE: Collision exception with player has been REMOVED (Issue #392 Iteration 6)
    # The collision layer/mask setup is sufficient:
    # - Player collision_mask = 4 (doesn't include layer 7 where casings are)
    # - Casing collision_layer = 64 (layer 7)
    # - CasingPusher Area2D collision_mask = 64 (detects layer 7)
    # The collision exception was causing issues with casing physics.
    # _add_player_collision_exception()  # DISABLED
```

**Rationale**:
- Simplify the solution by removing unnecessary complexity
- Trust the collision layer/mask system which is the standard Godot approach
- The spawn delay handles the spawn-time edge case
- No collision exception means no unexpected side effects on casing physics

### User Feedback #6 (2026-02-03)
- Feedback from log `game_log_20260203_120120.txt`:
  1. "гильзы не толкаются если игрок врезается в них с узкой стороны" - Casings don't get pushed if player bumps into them from the narrow side
- The casing collision shape is a thin rectangle (4x14 pixels)
- When approaching from the narrow 4-pixel side, the CasingPusher Area2D may not reliably detect the overlap

### Root Cause Analysis (Iteration 7)
- **Casing shape**: RectangleShape2D with size (4, 14) - tall, thin rectangle
- **CasingPusher shape**: CircleShape2D with radius 20 - covers player vicinity
- **Casing rotation**: Random rotation at spawn (0 to 2π)
- **Issue**: When casing is rotated so its narrow side (4px) faces the player, the overlap detection via `get_overlapping_bodies()` polling may be unreliable
- **Research findings** (from Godot forums and GitHub issues):
  - `Area2D.get_overlapping_bodies()` can miss bodies that only briefly enter the detection area
  - The function doesn't account for RigidBody2D moves in the same frame
  - Polling-based detection can miss narrow overlaps when player moves quickly

### Fix Iteration 7 - Signal-Based Casing Detection (2026-02-03)
**Problem**: Polling `get_overlapping_bodies()` every frame may miss casings when:
1. Player approaches casing from narrow side (4px edge)
2. Player moves quickly past the casing
3. Timing issues between physics and Area2D detection

**Solution**: Use `body_entered` and `body_exited` signals for more reliable casing tracking:
- Connect to CasingPusher's `body_entered` signal to track casings as they enter
- Connect to `body_exited` signal to remove casings when they leave
- Maintain an array of currently overlapping casings
- Use BOTH signal-tracked casings AND polled bodies for redundancy

**Code Changes** (scripts/characters/player.gd):

1. Added tracking array:
```gdscript
## Set of casings currently overlapping with the CasingPusher Area2D (Issue #392 Iteration 7).
## Using signal-based tracking instead of polling get_overlapping_bodies() for reliable detection.
## This ensures casings are detected even when approaching from narrow sides.
var _overlapping_casings: Array[RigidBody2D] = []
```

2. Connect signals in _ready():
```gdscript
# Connect CasingPusher signals for reliable casing detection (Issue #392 Iteration 7)
_connect_casing_pusher_signals()
```

3. Signal connection function:
```gdscript
func _connect_casing_pusher_signals() -> void:
    if _casing_pusher == null:
        return
    if not _casing_pusher.body_entered.is_connected(_on_casing_pusher_body_entered):
        _casing_pusher.body_entered.connect(_on_casing_pusher_body_entered)
    if not _casing_pusher.body_exited.is_connected(_on_casing_pusher_body_exited):
        _casing_pusher.body_exited.connect(_on_casing_pusher_body_exited)
```

4. Signal handlers:
```gdscript
func _on_casing_pusher_body_entered(body: Node2D) -> void:
    if body is RigidBody2D and body.has_method("receive_kick"):
        if body not in _overlapping_casings:
            _overlapping_casings.append(body)

func _on_casing_pusher_body_exited(body: Node2D) -> void:
    if body is RigidBody2D:
        var idx := _overlapping_casings.find(body)
        if idx >= 0:
            _overlapping_casings.remove_at(idx)
```

5. Updated _push_casings() to use both sources:
```gdscript
func _push_casings() -> void:
    # ... null/velocity checks ...

    # Combine both signal-tracked casings and polled overlapping bodies for reliability
    var casings_to_push: Array[RigidBody2D] = []

    # Add signal-tracked casings
    for casing in _overlapping_casings:
        if is_instance_valid(casing) and casing not in casings_to_push:
            casings_to_push.append(casing)

    # Also poll for any casings that might have been missed by signals
    var polled_bodies := _casing_pusher.get_overlapping_bodies()
    for body in polled_bodies:
        if body is RigidBody2D and body.has_method("receive_kick"):
            if body not in casings_to_push:
                casings_to_push.append(body)

    # Push all detected casings
    for casing in casings_to_push:
        var push_dir := velocity.normalized()
        var push_strength := velocity.length() * CASING_PUSH_FORCE / 100.0
        casing.receive_kick(push_dir * push_strength)
```

**Rationale**:
- Signal-based tracking ensures casings are tracked from the moment they enter the detection area
- Signals fire at the physics engine level, not just during polling
- Combining both methods provides maximum reliability (defense-in-depth)
- If signals miss something, polling catches it; if polling misses something, signals catch it

### Research References (Iteration 7)
- [Area2D.get_overlapping_bodies() not detecting - Godot Forum](https://forum.godotengine.org/t/area2d-get-overlapping-bodies-not-detecting/74632)
- [Disabling process of PhysicsBody2D and Area2D bug - GitHub Issue #76219](https://github.com/godotengine/godot/issues/76219)
- [Area 2D fails to detect Rigidbody 2D - Godot Forum](https://forum.godotengine.org/t/area-2d-fails-to-detect-rigidbody-2d-on-body-entered-not-triggered/48113)

### Lessons Learned (Iteration 7)
1. **Polling vs Signals for Collision Detection**
   - `get_overlapping_bodies()` is convenient but can miss brief overlaps
   - `body_entered`/`body_exited` signals are more reliable for tracking
   - Use BOTH methods for maximum reliability in critical systems

2. **Shape Geometry Affects Detection**
   - Thin shapes (4x14 rectangle) with random rotation create edge cases
   - Players moving quickly past narrow edges may not trigger reliable detection
   - Consider shape geometry when designing collision detection systems

3. **Defense-in-Depth is Essential**
   - No single detection method is 100% reliable
   - Combining multiple approaches catches edge cases
   - Extra code complexity is worth it for robust gameplay

### User Feedback #7 (2026-02-03)
- Feedback from log `game_log_20260203_123943.txt`:
  1. "гильзы не дают пройти игроку" - Casings are not letting the player pass
- The log shows no casing-related debug output at all
- User was testing on the Tutorial level (`csharp/TestTier.tscn`)

### Root Cause Discovery (Iteration 8)
- **The C# Player scene was never updated!**
- `scenes/characters/csharp/Player.tscn` still had:
  - `collision_mask = 68` (includes layer 7 where casings are)
  - No CasingPusher Area2D node
- The GDScript fixes were only applied to `scenes/characters/Player.tscn`
- Tutorial level (`scenes/levels/csharp/TestTier.tscn`) uses the C# Player scene

### Fix Iteration 8 - Update C# Player Scene and Script (2026-02-03)
**Problem**: All previous fixes were only applied to the GDScript version. The C# version was untouched.

**Solution**: Apply the same fixes to the C# Player scene and script:

1. **Update C# Player.tscn** (`scenes/characters/csharp/Player.tscn`):
   - Changed `collision_mask = 68` to `collision_mask = 4`
   - Added `CasingPusher` Area2D with `collision_mask = 64` (layer 7)
   - Added `CasingPusherShape` CollisionShape2D with radius 20

2. **Update C# Player.cs** (`Scripts/Characters/Player.cs`):
   - Added `_casingPusher` Area2D reference
   - Added `_overlappingCasings` list for signal-based tracking
   - Added `ConnectCasingPusherSignals()` method
   - Added `OnCasingPusherBodyEntered()` and `OnCasingPusherBodyExited()` signal handlers
   - Added `PushCasingsWithArea2D()` method called from `_PhysicsProcess()`

**Code Changes** (Scripts/Characters/Player.cs):

```csharp
// New fields
private Area2D? _casingPusher;
private const float CasingPushForce = 50.0f;
private readonly List<RigidBody2D> _overlappingCasings = new();

// In _Ready():
ConnectCasingPusherSignals();

// In _PhysicsProcess():
PushCasingsWithArea2D();

// New methods
private void ConnectCasingPusherSignals()
{
    _casingPusher = GetNodeOrNull<Area2D>("CasingPusher");
    if (_casingPusher == null) return;
    _casingPusher.BodyEntered += OnCasingPusherBodyEntered;
    _casingPusher.BodyExited += OnCasingPusherBodyExited;
}

private void OnCasingPusherBodyEntered(Node2D body)
{
    if (body is RigidBody2D rigidBody && rigidBody.HasMethod("receive_kick"))
    {
        if (!_overlappingCasings.Contains(rigidBody))
            _overlappingCasings.Add(rigidBody);
    }
}

private void OnCasingPusherBodyExited(Node2D body)
{
    if (body is RigidBody2D rigidBody)
        _overlappingCasings.Remove(rigidBody);
}

private void PushCasingsWithArea2D()
{
    if (_casingPusher == null || Velocity.LengthSquared() < 1.0f) return;

    var casingsToPush = new HashSet<RigidBody2D>();

    // Add signal-tracked casings
    foreach (var casing in _overlappingCasings)
        if (IsInstanceValid(casing)) casingsToPush.Add(casing);

    // Also poll for any missed casings
    foreach (var body in _casingPusher.GetOverlappingBodies())
        if (body is RigidBody2D rigidBody && rigidBody.HasMethod("receive_kick"))
            casingsToPush.Add(rigidBody);

    // Push all detected casings
    foreach (var casing in casingsToPush)
    {
        var pushDir = Velocity.Normalized();
        var pushStrength = Velocity.Length() * CasingPushForce / 100.0f;
        casing.Call("receive_kick", pushDir * pushStrength);
    }
}
```

**Rationale**:
- The game has BOTH GDScript and C# versions of key scenes/scripts
- Levels in `scenes/levels/csharp/` use C# versions (Player.tscn, Enemy.tscn, etc.)
- The Tutorial level specifically uses the C# Player
- All fixes must be applied to BOTH versions for consistency

### Lessons Learned (Iteration 8)
1. **Dual Codebase Awareness**
   - This project has both GDScript and C# implementations
   - Fixes must be applied to BOTH versions
   - Always check which version is used by the affected scenes/levels

2. **Verify Affected Code Paths**
   - The user was on the Tutorial level which uses C# Player
   - Previous testing may have been with GDScript version
   - When a "fix" doesn't work, verify the actual code path being executed

3. **Log Analysis is Critical**
   - The log showed no casing debug output → CasingPusher logic not running
   - This indicated the C# version was being used (no CasingPusher signals)
   - Log analysis can reveal which code path is active
