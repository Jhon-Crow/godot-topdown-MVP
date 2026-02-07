class_name FlashlightDetectionComponent
extends RefCounted
## Component for detecting the player's flashlight beam and estimating player position (Issue #574).
##
## This component allows enemies to:
## 1. Detect when the player's flashlight beam is shining in their direction
## 2. Estimate the player's approximate position from the beam origin
## 3. Determine if a passage/path is illuminated by the flashlight
##
## Detection uses the dot product cone test:
## - Calculate the direction from flashlight origin to enemy position
## - Check if the angle between beam direction and direction-to-enemy is within beam half-angle
## - Verify line of sight (no walls blocking the beam)
##
## The flashlight has shadow_enabled=true, so light doesn't pass through walls.
## The beam is an 18-degree cone (9 degrees half-angle) with texture_scale=6.0.

## Confidence level when detecting player via flashlight beam (Issue #574).
## Higher than gunshot (0.7) because the flashlight reveals exact direction,
## but lower than direct visual (1.0) since the player could turn the light off.
const FLASHLIGHT_DETECTION_CONFIDENCE: float = 0.75

## Maximum detection range for the flashlight beam (in pixels).
## Matches the visual beam range: LIGHT_TEXTURE_SCALE (6.0) * base_range (100px) = 600px.
const FLASHLIGHT_MAX_RANGE: float = 600.0

## Flashlight beam half-angle in degrees for detection.
## The actual texture uses an 18-degree cone, so half-angle is 9 degrees.
## We use a slightly wider detection angle (12°) to account for the glow/halo
## around the beam that enemies would realistically notice.
const BEAM_HALF_ANGLE_DEG: float = 12.0

## Minimum interval between flashlight detection checks (seconds).
## Prevents per-frame overhead when the flashlight is continuously on.
const CHECK_INTERVAL: float = 0.15

## Timer for detection check interval.
var _check_timer: float = 0.0

## Whether the enemy currently detects a flashlight beam.
var detected: bool = false

## The estimated player position based on the flashlight beam origin.
## Only valid when detected == true.
var estimated_player_position: Vector2 = Vector2.ZERO

## The direction the flashlight beam is pointing (normalized).
## Only valid when detected == true.
var beam_direction: Vector2 = Vector2.ZERO

## Whether debug logging is enabled.
var debug_logging: bool = false


## Check if the enemy can detect the player's flashlight beam.
##
## Parameters:
## - enemy_pos: The enemy's global position
## - player: Reference to the player node (must have is_flashlight_on(), get_flashlight_direction(), get_flashlight_origin())
## - raycast: RayCast2D for line-of-sight checks (to verify no walls block the beam)
## - delta: Frame time for interval timing
##
## Returns true if the flashlight is detected this frame.
func check_flashlight(enemy_pos: Vector2, player: Node2D, raycast: RayCast2D, delta: float) -> bool:
	_check_timer += delta
	if _check_timer < CHECK_INTERVAL:
		return detected

	_check_timer = 0.0

	# Reset detection state
	detected = false
	estimated_player_position = Vector2.ZERO
	beam_direction = Vector2.ZERO

	if player == null or not is_instance_valid(player):
		return false

	# Check if player has flashlight methods and if it's on
	if not player.has_method("is_flashlight_on") or not player.is_flashlight_on():
		return false

	# Get flashlight beam properties from player
	var flashlight_dir: Vector2 = Vector2.ZERO
	if player.has_method("get_flashlight_direction"):
		flashlight_dir = player.get_flashlight_direction()
	if flashlight_dir.length_squared() < 0.01:
		return false

	var flashlight_origin: Vector2 = player.global_position
	if player.has_method("get_flashlight_origin"):
		flashlight_origin = player.get_flashlight_origin()

	# Step 1: Distance check — is the enemy within beam range?
	var distance_to_enemy := flashlight_origin.distance_to(enemy_pos)
	if distance_to_enemy > FLASHLIGHT_MAX_RANGE:
		return false

	# Step 2: Cone intersection test — is the enemy within the beam cone?
	var direction_to_enemy := (enemy_pos - flashlight_origin).normalized()
	var dot := flashlight_dir.dot(direction_to_enemy)
	var beam_half_angle_rad := deg_to_rad(BEAM_HALF_ANGLE_DEG)
	var cos_half_angle := cos(beam_half_angle_rad)

	if dot < cos_half_angle:
		# Enemy is outside the beam cone
		return false

	# Step 3: Line-of-sight check — verify no walls block the beam to the enemy
	if raycast != null:
		var has_los := _check_beam_los(flashlight_origin, enemy_pos, raycast)
		if not has_los:
			return false

	# Detection confirmed — enemy can see the flashlight beam
	detected = true
	estimated_player_position = flashlight_origin
	beam_direction = flashlight_dir

	return true


## Check if a specific position is illuminated by the flashlight beam (Issue #574).
## Used for passage avoidance — enemies check if a doorway/corridor is lit.
##
## Parameters:
## - position: The position to check (e.g., a doorway or navigation waypoint)
## - player: Reference to the player node
##
## Returns true if the position is within the flashlight beam cone.
func is_position_lit(position: Vector2, player: Node2D) -> bool:
	if player == null or not is_instance_valid(player):
		return false

	if not player.has_method("is_flashlight_on") or not player.is_flashlight_on():
		return false

	var flashlight_dir: Vector2 = Vector2.ZERO
	if player.has_method("get_flashlight_direction"):
		flashlight_dir = player.get_flashlight_direction()
	if flashlight_dir.length_squared() < 0.01:
		return false

	var flashlight_origin: Vector2 = player.global_position
	if player.has_method("get_flashlight_origin"):
		flashlight_origin = player.get_flashlight_origin()

	# Distance check
	var distance := flashlight_origin.distance_to(position)
	if distance > FLASHLIGHT_MAX_RANGE:
		return false

	# Cone test
	var direction_to_pos := (position - flashlight_origin).normalized()
	var dot := flashlight_dir.dot(direction_to_pos)
	var beam_half_angle_rad := deg_to_rad(BEAM_HALF_ANGLE_DEG)

	return dot >= cos(beam_half_angle_rad)


## Check if the next navigation waypoint is illuminated by the flashlight (Issue #574).
## Used by the GOAP planner to decide whether to avoid a lit passage.
##
## Parameters:
## - nav_agent: The enemy's NavigationAgent2D
## - player: Reference to the player node
##
## Returns true if the next waypoint in the navigation path is lit by the flashlight.
func is_next_waypoint_lit(nav_agent: NavigationAgent2D, player: Node2D) -> bool:
	if nav_agent == null or nav_agent.is_navigation_finished():
		return false

	var next_pos := nav_agent.get_next_path_position()
	return is_position_lit(next_pos, player)


## Check line of sight from flashlight to a position, respecting walls (Issue #574).
## Uses the enemy's raycast to verify the beam isn't blocked.
func _check_beam_los(from_pos: Vector2, to_pos: Vector2, raycast: RayCast2D) -> bool:
	if raycast == null:
		return true  # Assume LOS if no raycast available

	# Save original raycast state
	var original_target := raycast.target_position
	var original_enabled := raycast.enabled

	# Configure raycast for LOS check from flashlight to enemy
	# We check from the enemy toward the flashlight origin to use the enemy's raycast
	var direction := from_pos - to_pos  # From enemy pos toward flashlight
	raycast.target_position = direction
	raycast.enabled = true
	raycast.force_raycast_update()

	# Check if anything blocks the path
	var has_los := not raycast.is_colliding()

	# If something is in the way, check if the collision is beyond the flashlight
	if raycast.is_colliding():
		var collision_point := raycast.get_collision_point()
		var enemy_parent := raycast.get_parent() as Node2D
		if enemy_parent:
			var distance_to_flashlight := enemy_parent.global_position.distance_to(from_pos)
			var distance_to_collision := enemy_parent.global_position.distance_to(collision_point)
			has_los = distance_to_collision >= distance_to_flashlight - 10.0

	# Restore raycast state
	raycast.target_position = original_target
	raycast.enabled = original_enabled

	return has_los


## Reset detection state.
func reset() -> void:
	detected = false
	estimated_player_position = Vector2.ZERO
	beam_direction = Vector2.ZERO
	_check_timer = 0.0


## Create string representation for debugging.
func _to_string() -> String:
	if not detected:
		return "FlashlightDetection(none)"
	return "FlashlightDetection(pos=%s, dir=%s)" % [
		estimated_player_position, beam_direction
	]
