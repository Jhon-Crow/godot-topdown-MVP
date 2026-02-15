class_name MuzzleFlashDetectionComponent
extends RefCounted
## Component for detecting player weapon muzzle flashes (Issue #754).
##
## This component allows enemies to:
## 1. Detect when the player fires their weapon (muzzle flash visible within FOV)
## 2. Estimate the player's approximate position from the flash location
## 3. Enable suppressive fire behavior toward the flash position
##
## Activation conditions:
## 1. player_visible == false (enemy cannot see player directly)
## 2. Player is NOT preparing/throwing a grenade
##
## The grenade condition prevents enemies from shooting at flashes
## when the player is exposed and throwing a grenade (they should
## engage the player directly in that case).
##
## This follows the same detection pattern as FlashlightDetectionComponent.

## Confidence level when detecting player via muzzle flash (Issue #754).
## Lower than flashlight (0.75) because flash is very brief (~0.3s).
## Higher than general sound (0.5-0.7) because it provides visual location.
const MUZZLE_FLASH_DETECTION_CONFIDENCE: float = 0.65

## Maximum detection range for muzzle flash (in pixels).
## Muzzle flashes are bright but brief - detectable within FOV range.
const MUZZLE_FLASH_MAX_RANGE: float = 500.0

## Maximum age of a muzzle flash to still be detectable (seconds).
## Slightly longer than visual effect duration (0.3s) to account for reaction time.
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
## - enemy_fov_enabled: Whether FOV is enabled (false = 360 vision)
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
