# Implementation Guide for Issue #754

## Step 1: Create MuzzleFlashDetectionComponent

Create file: `scripts/components/muzzle_flash_detection_component.gd`

```gdscript
class_name MuzzleFlashDetectionComponent
extends RefCounted
## Component for detecting player weapon muzzle flashes (Issue #754).
##
## When the enemy cannot see the player but can see their muzzle flash,
## they estimate the player's position from the flash location.
## This enables suppressive fire behavior - shooting at the last known
## flash position when the player is behind cover.
##
## Activation conditions:
## 1. player_visible == false (enemy cannot see player directly)
## 2. Player is NOT preparing/throwing a grenade
##
## The grenade condition prevents enemies from shooting at flashes
## when the player is exposed and throwing a grenade (they should
## engage the player directly in that case).

## Confidence level when detecting player via muzzle flash.
## Lower than flashlight (0.75) because flash is very brief (~0.3s).
## Higher than general sound (0.5-0.7) because it provides visual location.
const MUZZLE_FLASH_DETECTION_CONFIDENCE: float = 0.65

## Maximum detection range for muzzle flash (in pixels).
## Muzzle flashes are bright but brief - detectable within FOV range.
const MUZZLE_FLASH_MAX_RANGE: float = 500.0

## Maximum age of a muzzle flash to still be detectable (seconds).
## Slightly longer than visual effect to account for reaction time.
const FLASH_MAX_AGE: float = 0.35

## Minimum interval between detection checks (seconds).
## Prevents per-frame overhead.
const CHECK_INTERVAL: float = 0.1

## Timer for detection check interval.
var _check_timer: float = 0.0

## Whether the enemy currently detects a muzzle flash.
var detected: bool = false

## The estimated player position based on the muzzle flash.
## Calculated by offsetting from flash position opposite to flash direction.
var estimated_player_position: Vector2 = Vector2.ZERO

## The direction the weapon was pointing (from flash direction).
var flash_direction: Vector2 = Vector2.ZERO

## The actual flash position (for debug/visualization).
var flash_position: Vector2 = Vector2.ZERO

## Debug logging flag.
var debug_logging: bool = false

## Cached reference to ImpactEffectsManager.
var _impact_manager: Node = null


## Check if the enemy can detect any muzzle flashes from the player's weapon.
##
## Parameters:
## - enemy_pos: The enemy's global position
## - enemy_facing_angle: The enemy's facing direction in radians
## - enemy_fov_deg: The enemy's FOV angle in degrees (full angle)
## - enemy_fov_enabled: Whether FOV is enabled (false = 360° vision)
## - player: Reference to the player node
## - raycast: RayCast2D for line-of-sight checks
## - can_see_player: Whether the enemy can currently see the player
## - delta: Frame time for interval timing
##
## Returns true if a muzzle flash is detected this check.
func check_muzzle_flash(
    enemy_pos: Vector2,
    enemy_facing_angle: float,
    enemy_fov_deg: float,
    enemy_fov_enabled: bool,
    player: Node2D,
    raycast: RayCast2D,
    can_see_player: bool,
    delta: float
) -> bool:
    # Interval-based checking to reduce overhead
    _check_timer += delta
    if _check_timer < CHECK_INTERVAL:
        return detected
    _check_timer = 0.0

    # Reset detection state
    detected = false
    estimated_player_position = Vector2.ZERO
    flash_direction = Vector2.ZERO
    flash_position = Vector2.ZERO

    # Condition 1: Only detect if player is NOT visible
    # If we can see the player directly, shoot at them instead
    if can_see_player:
        if debug_logging:
            print("[MuzzleFlashDetection] Skipping - player is visible")
        return false

    # Condition 2: Only detect if player is NOT preparing/throwing grenade
    # When throwing a grenade, the player is exposed and should be targeted directly
    if player != null and is_instance_valid(player):
        if player.has_method("is_preparing_grenade"):
            if player.is_preparing_grenade():
                if debug_logging:
                    print("[MuzzleFlashDetection] Skipping - player preparing grenade")
                return false

    # Get ImpactEffectsManager reference
    if _impact_manager == null:
        _impact_manager = Engine.get_singleton("ImpactEffectsManager") if Engine.has_singleton("ImpactEffectsManager") else null
        if _impact_manager == null and player != null:
            _impact_manager = player.get_node_or_null("/root/ImpactEffectsManager")
    if _impact_manager == null:
        return false

    # Check for active muzzle flashes
    if not _impact_manager.has_method("get_active_muzzle_flashes"):
        if debug_logging:
            print("[MuzzleFlashDetection] ImpactEffectsManager missing get_active_muzzle_flashes()")
        return false

    var active_flashes: Array = _impact_manager.get_active_muzzle_flashes()
    if active_flashes.is_empty():
        return false

    # Check each flash for visibility
    var enemy_facing_dir := Vector2.from_angle(enemy_facing_angle)
    var fov_half_angle_rad := deg_to_rad(enemy_fov_deg / 2.0) if enemy_fov_deg > 0.0 else PI

    for flash_data in active_flashes:
        var f_pos: Vector2 = flash_data.get("position", Vector2.ZERO)
        var f_dir: Vector2 = flash_data.get("direction", Vector2.ZERO)
        var f_age: float = flash_data.get("age", 999.0)

        # Skip old flashes
        if f_age > FLASH_MAX_AGE:
            continue

        # Check distance
        var dist: float = enemy_pos.distance_to(f_pos)
        if dist > MUZZLE_FLASH_MAX_RANGE:
            continue

        # Check FOV (if enabled)
        if enemy_fov_enabled and enemy_fov_deg > 0.0:
            var dir_to_flash := (f_pos - enemy_pos).normalized()
            var dot := enemy_facing_dir.dot(dir_to_flash)
            if dot < cos(fov_half_angle_rad):
                if debug_logging:
                    print("[MuzzleFlashDetection] Flash outside FOV")
                continue  # Outside FOV

        # Check line-of-sight to flash position
        if raycast != null:
            var has_los := _check_los_to_position(enemy_pos, f_pos, raycast)
            if not has_los:
                if debug_logging:
                    print("[MuzzleFlashDetection] No LOS to flash at ", f_pos)
                continue

        # Detection confirmed!
        detected = true
        flash_position = f_pos
        flash_direction = f_dir

        # Estimate player position:
        # The player is behind the muzzle flash, opposite to the shooting direction
        # Use typical bullet spawn offset to estimate player body position
        var estimated_offset: float = 30.0  # ~bullet_spawn_offset
        estimated_player_position = f_pos - f_dir * estimated_offset

        if debug_logging:
            print("[MuzzleFlashDetection] DETECTED flash at ", f_pos, " -> estimated player at ", estimated_player_position)

        return true

    return false


## Check line-of-sight from enemy to a position.
func _check_los_to_position(enemy_pos: Vector2, target_pos: Vector2, raycast: RayCast2D) -> bool:
    if raycast == null:
        return true  # Assume LOS if no raycast available

    # Save original raycast state
    var original_target := raycast.target_position
    var original_enabled := raycast.enabled

    # Configure raycast toward target
    var direction := target_pos - enemy_pos
    raycast.target_position = direction
    raycast.enabled = true
    raycast.force_raycast_update()

    var has_los := true

    if raycast.is_colliding():
        var collision_point := raycast.get_collision_point()
        var enemy_parent := raycast.get_parent() as Node2D
        if enemy_parent:
            var distance_to_target := enemy_parent.global_position.distance_to(target_pos)
            var distance_to_collision := enemy_parent.global_position.distance_to(collision_point)
            # Wall is before the target - LOS blocked
            has_los = distance_to_collision >= distance_to_target - 10.0

    # Restore raycast state
    raycast.target_position = original_target
    raycast.enabled = original_enabled

    return has_los


## Reset detection state.
func reset() -> void:
    detected = false
    estimated_player_position = Vector2.ZERO
    flash_direction = Vector2.ZERO
    flash_position = Vector2.ZERO
    _check_timer = 0.0


## Create string representation for debugging.
func _to_string() -> String:
    if not detected:
        return "MuzzleFlashDetection(none)"
    return "MuzzleFlashDetection(flash=%s, estimated_player=%s)" % [
        flash_position, estimated_player_position
    ]
```

---

## Step 2: Modify ImpactEffectsManager

Add flash tracking to: `scripts/autoload/impact_effects_manager.gd`

Add these members near the top of the file:

```gdscript
## Active muzzle flash data for enemy detection (Issue #754).
## Each entry contains position, direction, and timestamp.
var _active_muzzle_flashes: Array = []

## Maximum number of tracked flashes to prevent memory growth.
const MAX_TRACKED_FLASHES: int = 10

## Maximum age before flash is removed from tracking (seconds).
const FLASH_TRACKING_MAX_AGE: float = 0.5
```

Modify the `spawn_muzzle_flash` function to track flashes:

```gdscript
func spawn_muzzle_flash(position: Vector2, direction: Vector2, caliber_data: Resource = null, scale_override: float = 0.0) -> void:
    # ... existing code to create the visual effect ...

    # Track flash for enemy detection (Issue #754)
    _track_muzzle_flash(position, direction)


## Track a muzzle flash for enemy detection (Issue #754).
func _track_muzzle_flash(position: Vector2, direction: Vector2) -> void:
    var flash_data := {
        "position": position,
        "direction": direction.normalized(),
        "timestamp": Time.get_ticks_msec() / 1000.0
    }
    _active_muzzle_flashes.append(flash_data)

    # Limit tracked flashes
    while _active_muzzle_flashes.size() > MAX_TRACKED_FLASHES:
        _active_muzzle_flashes.pop_front()


## Get active muzzle flashes for enemy detection (Issue #754).
## Returns array of dictionaries with: position, direction, age.
func get_active_muzzle_flashes() -> Array:
    var current_time := Time.get_ticks_msec() / 1000.0

    # Clean up old flashes
    _active_muzzle_flashes = _active_muzzle_flashes.filter(
        func(f): return current_time - f.timestamp < FLASH_TRACKING_MAX_AGE
    )

    # Return with age calculated
    var result: Array = []
    for flash in _active_muzzle_flashes:
        result.append({
            "position": flash.position,
            "direction": flash.direction,
            "age": current_time - flash.timestamp
        })
    return result
```

---

## Step 3: Add GOAP Action

Add to: `scripts/ai/enemy_actions.gd`

```gdscript
## Action to shoot suppressive fire at detected muzzle flash position (Issue #754).
## When an enemy cannot see the player directly but can see their muzzle flash,
## this action fires suppressive rounds at the estimated player position.
##
## Activation conditions:
## - player_visible == false (can't see player)
## - muzzle_flash_detected == true (can see muzzle flash)
## - player_preparing_grenade == false (player not throwing grenade)
##
## This behavior adds tactical depth: players can't simply fire from cover
## without consequence. Enemies will suppress the position.
class ShootAtMuzzleFlashAction extends GOAPAction:
    func _init() -> void:
        super._init("shoot_at_muzzle_flash", 1.8)
        preconditions = {
            "player_visible": false,
            "muzzle_flash_detected": true,
            "player_preparing_grenade": false
        }
        effects = {
            "suppressive_fire_delivered": true,
            "player_engaged": true  # Partial engagement via suppression
        }

    func get_cost(_agent: Node, world_state: Dictionary) -> float:
        # Action should have medium priority:
        # - Higher than patrol (patrol cost: 1.0)
        # - Lower than direct engagement when player visible
        # - Similar to investigation actions
        if world_state.get("muzzle_flash_detected", false):
            # Recently detected - higher priority
            return 1.5
        return 100.0  # Should not happen due to preconditions
```

Also add to `create_all_actions()`:

```gdscript
static func create_all_actions() -> Array[GOAPAction]:
    var actions: Array[GOAPAction] = []
    # ... existing actions ...

    # Muzzle flash shooting action (Issue #754)
    actions.append(ShootAtMuzzleFlashAction.new())

    return actions
```

---

## Step 4: Integrate into Enemy

Modify: `scripts/objects/enemy.gd`

Add member variable:

```gdscript
## Muzzle flash detection component (Issue #754).
var _muzzle_flash_detection: MuzzleFlashDetectionComponent = null
```

Add to `_ready()`:

```gdscript
func _ready() -> void:
    # ... existing setup ...
    _setup_muzzle_flash_detection()
```

Add setup function:

```gdscript
## Setup muzzle flash detection component (Issue #754).
func _setup_muzzle_flash_detection() -> void:
    _muzzle_flash_detection = MuzzleFlashDetectionComponent.new()
    _muzzle_flash_detection.debug_logging = debug_logging
```

Modify `_check_player_visibility()` to check for muzzle flashes:

```gdscript
func _check_player_visibility() -> void:
    # ... existing visibility code ...

    # After setting _can_see_player, check for muzzle flash (Issue #754)
    _check_muzzle_flash_detection(delta)
```

Add muzzle flash detection function:

```gdscript
## Check for muzzle flash detection when player is not visible (Issue #754).
func _check_muzzle_flash_detection(delta: float) -> void:
    if _muzzle_flash_detection == null or _player == null:
        _goap_world_state["muzzle_flash_detected"] = false
        return

    # Only check when player is NOT visible
    if _can_see_player:
        _goap_world_state["muzzle_flash_detected"] = false
        return

    # Check for muzzle flashes
    var flash_detected := _muzzle_flash_detection.check_muzzle_flash(
        global_position,
        _enemy_model.global_rotation if _enemy_model else rotation,
        fov_angle,
        fov_enabled and _is_fov_globally_enabled(),
        _player,
        _raycast,
        _can_see_player,
        delta
    )

    _goap_world_state["muzzle_flash_detected"] = flash_detected

    # Update GOAP state for grenade check
    var preparing_grenade := false
    if _player and _player.has_method("is_preparing_grenade"):
        preparing_grenade = _player.is_preparing_grenade()
    _goap_world_state["player_preparing_grenade"] = preparing_grenade

    # Update memory with estimated position if flash detected
    if flash_detected and _memory:
        var success := _memory.update_position(
            _muzzle_flash_detection.estimated_player_position,
            MuzzleFlashDetectionComponent.MUZZLE_FLASH_DETECTION_CONFIDENCE
        )
        if success:
            _log_to_file("Updated memory from muzzle flash: pos=%s, conf=%.2f" % [
                _muzzle_flash_detection.estimated_player_position,
                MuzzleFlashDetectionComponent.MUZZLE_FLASH_DETECTION_CONFIDENCE
            ])
```

Add suppressive fire behavior to shooting logic (in combat state handling):

```gdscript
## Execute suppressive fire at muzzle flash position (Issue #754).
func _execute_suppressive_fire() -> void:
    if not _muzzle_flash_detection or not _muzzle_flash_detection.detected:
        return

    if _current_ammo <= 0:
        return

    var target := _muzzle_flash_detection.estimated_player_position
    var direction := (target - global_position).normalized()

    # Add spread for suppressive fire (less accurate than aimed shots)
    var spread := randf_range(-0.2, 0.2)  # ~±11 degrees
    direction = direction.rotated(spread)

    # Fire suppressive burst (2-3 rounds)
    _shoot_at_direction(direction)

    _log_debug("Suppressive fire at muzzle flash position: %s" % target)
```

---

## Step 5: Testing

### Manual Test Procedure

1. Load a level with enemies and cover
2. Position player behind cover where enemy cannot see
3. Fire weapon while behind cover
4. Observe:
   - Enemy should turn toward muzzle flash
   - Enemy should fire suppressive rounds at cover position
   - Enemy should update memory with estimated position

### Test with Grenade

1. Start preparing grenade (hold G)
2. Fire weapon while holding grenade
3. Enemy should NOT shoot at muzzle flash (grenade takes priority)

### Test FOV

1. Position player behind cover
2. Fire weapon outside enemy's FOV
3. Enemy should NOT detect flash (outside vision)
4. Fire weapon within enemy's FOV
5. Enemy should detect and respond

---

## Summary

This implementation adds realistic suppressive fire behavior where enemies can:
- Detect muzzle flashes from player weapons
- Estimate player position from the flash
- Fire suppressive rounds at the estimated position
- Integrate this behavior with existing GOAP planning

The solution follows established patterns in the codebase (similar to FlashlightDetectionComponent) and integrates cleanly with existing systems (enemy memory, GOAP actions).
