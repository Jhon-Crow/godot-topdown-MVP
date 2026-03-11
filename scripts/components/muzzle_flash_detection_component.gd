class_name MuzzleFlashDetectionComponent
extends RefCounted
## Component for detecting player weapon muzzle flashes when player is invisible (Issue #910).
##
## When the player fires while invisible, a brief muzzle flash is visible at the gun muzzle.
## Enemies within FOV and line-of-sight can detect this flash and fire toward the player's
## estimated position — even though the player's body is not visible.
##
## This detection is only active when the player IS invisible (is_invisible() == true).
## When the player is visible, enemies use normal targeting instead.
##
## Follows the same pattern as FlashlightDetectionComponent (Issue #574).

## Confidence when detecting via muzzle flash (Issue #910).
## Lower than flashlight (0.75) — flash is very brief (~0.3s).
## Higher than sound (0.5–0.7) — provides visual location.
const MUZZLE_FLASH_DETECTION_CONFIDENCE: float = 0.65

## Maximum detection range for muzzle flash (pixels).
## Flashes are bright but brief — detectable within FOV range.
const MUZZLE_FLASH_MAX_RANGE: float = 500.0

## Maximum age of a muzzle flash to still be detectable (seconds).
## Slightly longer than visual effect duration (0.3s) to account for reaction time.
const FLASH_MAX_AGE: float = 0.35

## Minimum interval between detection checks (seconds).
## Prevents per-frame overhead.
const CHECK_INTERVAL: float = 0.1

var _check_timer: float = 0.0

## Whether a muzzle flash is currently detected.
var detected: bool = false

## Estimated player position from the flash location.
var estimated_player_position: Vector2 = Vector2.ZERO

## Direction the weapon was pointing (from flash direction).
var flash_direction: Vector2 = Vector2.ZERO

## The actual flash position (for debug).
var flash_position: Vector2 = Vector2.ZERO

## Debug logging flag.
var debug_logging: bool = false

## Cached ImpactEffectsManager reference.
var _impact_manager: Node = null


## Check if the enemy can detect the player's muzzle flash (Issue #910).
## Only detects when player is invisible (is_invisible() == true).
##
## Parameters:
## - enemy_pos: Enemy global position
## - enemy_facing_angle: Enemy facing direction (radians)
## - enemy_fov_deg: Enemy FOV angle in degrees (full angle)
## - enemy_fov_enabled: Whether FOV mode is active
## - player: Reference to the player node
## - raycast: RayCast2D for line-of-sight checks
## - can_see_player: Whether the enemy can currently see the player directly
## - delta: Frame time for interval timing
##
## Returns true if a muzzle flash from an invisible player is detected.
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
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return detected
	_check_timer = 0.0

	# Reset state
	detected = false
	estimated_player_position = Vector2.ZERO
	flash_direction = Vector2.ZERO
	flash_position = Vector2.ZERO

	# Only detect muzzle flash when player is NOT directly visible
	if can_see_player:
		return false

	# Only detect when player is invisible (this component is for Issue #910 specifically)
	if player == null or not is_instance_valid(player):
		return false
	if not player.has_method("is_invisible") or not player.is_invisible():
		return false

	# Get ImpactEffectsManager
	if _impact_manager == null and player != null:
		_impact_manager = player.get_node_or_null("/root/ImpactEffectsManager")
	if _impact_manager == null or not _impact_manager.has_method("get_active_muzzle_flashes"):
		return false

	var active_flashes: Array = _impact_manager.get_active_muzzle_flashes()
	if active_flashes.is_empty():
		return false

	var enemy_facing_dir := Vector2.from_angle(enemy_facing_angle)
	var fov_half_angle_rad := deg_to_rad(enemy_fov_deg / 2.0) if enemy_fov_deg > 0.0 else PI

	for flash_data in active_flashes:
		var f_pos: Vector2 = flash_data.get("position", Vector2.ZERO)
		var f_dir: Vector2 = flash_data.get("direction", Vector2.ZERO)
		var f_age: float = flash_data.get("age", 999.0)

		if f_age > FLASH_MAX_AGE:
			continue

		var dist: float = enemy_pos.distance_to(f_pos)
		if dist > MUZZLE_FLASH_MAX_RANGE:
			continue

		# FOV check
		if enemy_fov_enabled and enemy_fov_deg > 0.0:
			var dir_to_flash := (f_pos - enemy_pos).normalized()
			if enemy_facing_dir.dot(dir_to_flash) < cos(fov_half_angle_rad):
				continue

		# LOS check: try direct LOS to barrel, then fall back to player body area
		# (ambient glow around cover when barrel is hidden behind wall)
		if raycast != null:
			var has_los := _check_los_to_position(enemy_pos, f_pos, raycast)
			if not has_los:
				var body_pos: Vector2 = f_pos - f_dir * 30.0
				if not _check_los_to_position(enemy_pos, body_pos, raycast):
					if debug_logging:
						print("[MuzzleFlashDetection#910] No LOS to flash %s or body %s" % [f_pos, body_pos])
					continue
				if debug_logging:
					print("[MuzzleFlashDetection#910] Barrel hidden, ambient glow visible at %s" % (f_pos - f_dir * 30.0))

		# Detection confirmed
		detected = true
		flash_position = f_pos
		flash_direction = f_dir
		# Player is slightly behind the muzzle, opposite to shoot direction
		estimated_player_position = f_pos - f_dir * 30.0
		if debug_logging:
			print("[MuzzleFlashDetection#910] DETECTED flash at %s -> est. player at %s" % [f_pos, estimated_player_position])
		return true

	return false


## Check LOS from enemy to a position (walls only, ignores player).
func _check_los_to_position(enemy_pos: Vector2, target_pos: Vector2, raycast: RayCast2D) -> bool:
	if raycast == null:
		return true
	var enemy_node := raycast.get_parent() as Node2D
	if enemy_node == null:
		return true
	var space_state := enemy_node.get_world_2d().direct_space_state
	if space_state == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(enemy_pos, target_pos)
	query.collision_mask = 4  # Layer 3: walls/obstacles only
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true
	var distance_to_target := enemy_pos.distance_to(target_pos)
	var distance_to_collision := enemy_pos.distance_to(result.position)
	return distance_to_collision >= distance_to_target - 10.0


## Reset detection state.
func reset() -> void:
	detected = false
	estimated_player_position = Vector2.ZERO
	flash_direction = Vector2.ZERO
	flash_position = Vector2.ZERO
	_check_timer = 0.0


func _to_string() -> String:
	if not detected:
		return "MuzzleFlashDetection#910(none)"
	return "MuzzleFlashDetection#910(flash=%s, est_player=%s)" % [flash_position, estimated_player_position]
