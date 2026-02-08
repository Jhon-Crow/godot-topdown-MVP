class_name FlashlightDetectionComponent
extends RefCounted
## Component for detecting the player's flashlight beam and estimating player position (Issue #574).
##
## This component allows enemies to:
## 1. Detect when the player's flashlight beam is visible within their field of vision
## 2. Estimate the player's approximate position from the beam origin
## 3. Determine if a passage/path is illuminated by the flashlight
##
## Detection algorithm (v2 — beam-in-FOV):
## The enemy detects the flashlight when any part of the beam is within their FOV cone.
## This is checked by sampling points along the flashlight beam and testing if any
## sample point falls within the enemy's vision cone AND has line-of-sight.
##
## This replaces the v1 algorithm which only checked if the beam directly hit the enemy.
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

## Maximum distance from which the enemy can see a beam point on surfaces (pixels).
## Even if the beam point is in the enemy's FOV, they need to be close enough to notice it.
## This matches the FOV cone visualization range used in the debug display.
const BEAM_VISIBILITY_RANGE: float = 600.0

## Number of sample points along the beam center line for visibility testing.
const BEAM_SAMPLE_COUNT: int = 8

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


## Check if the enemy can detect the player's flashlight beam (Issue #574, v2).
##
## The enemy detects the beam when any part of it falls within their field of vision.
## This means the enemy can notice the flashlight even when not directly hit by the beam,
## as long as they can see the light cone from their position and FOV.
##
## Parameters:
## - enemy_pos: The enemy's global position
## - enemy_facing_angle: The enemy's facing direction in radians (from _enemy_model.global_rotation)
## - enemy_fov_deg: The enemy's FOV angle in degrees (full angle, e.g. 100°)
## - enemy_fov_enabled: Whether FOV is enabled (if false, enemy has 360° vision)
## - player: Reference to the player node (must have is_flashlight_on(), get_flashlight_direction(), get_flashlight_origin())
## - raycast: RayCast2D for line-of-sight checks
## - delta: Frame time for interval timing
##
## Returns true if the flashlight is detected this frame.
func check_flashlight(enemy_pos: Vector2, enemy_facing_angle: float, enemy_fov_deg: float, enemy_fov_enabled: bool, player: Node2D, raycast: RayCast2D, delta: float) -> bool:
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

	# Issue #640: When the flashlight is wall-clamped (player flush against wall),
	# the beam is physically blocked — enemies should not detect it through the wall.
	if player.has_method("is_flashlight_wall_clamped") and player.is_flashlight_wall_clamped():
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

	# Quick distance pre-check: if the enemy is too far from the beam's farthest point,
	# no sample point could be visible. Use sum of beam range + visibility range as max.
	var dist_to_origin := flashlight_origin.distance_to(enemy_pos)
	if dist_to_origin > FLASHLIGHT_MAX_RANGE + BEAM_VISIBILITY_RANGE:
		return false

	# Generate beam sample points: center line + edge rays
	var beam_points := _generate_beam_sample_points(flashlight_origin, flashlight_dir)

	# Check enemy's FOV parameters
	var enemy_facing_dir := Vector2.from_angle(enemy_facing_angle)
	var fov_half_angle_deg := enemy_fov_deg / 2.0

	# Test each beam sample point
	for point in beam_points:
		# Step 1: Is the beam point close enough for the enemy to see?
		var dist_to_point := enemy_pos.distance_to(point)
		if dist_to_point > BEAM_VISIBILITY_RANGE:
			continue

		# Step 2: Is the beam point within the enemy's FOV?
		if enemy_fov_enabled and enemy_fov_deg > 0.0:
			var dir_to_point := (point - enemy_pos).normalized()
			var dot := enemy_facing_dir.dot(dir_to_point)
			var angle_to_point := rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
			if angle_to_point > fov_half_angle_deg:
				continue  # Outside enemy's FOV

		# Step 3: Does the enemy have line-of-sight to this beam point?
		if raycast != null:
			var has_los := _check_enemy_los_to_point(enemy_pos, point, raycast)
			if not has_los:
				continue

		# Step 4: Verify the beam actually reaches this point (not blocked by walls)
		# The flashlight has shadow_enabled, so light doesn't pass through walls.
		# First check the geometric cone, then verify the beam isn't blocked by a wall
		# between the flashlight origin and this point (Issue #629).
		if not _is_point_in_beam_cone(point, flashlight_origin, flashlight_dir):
			continue
		if raycast != null and not _check_beam_reaches_point(flashlight_origin, point, raycast):
			continue

		# Detection confirmed — enemy can see a point on the flashlight beam
		detected = true
		estimated_player_position = flashlight_origin
		beam_direction = flashlight_dir
		return true

	return false


## Generate sample points along the flashlight beam for visibility testing.
## Samples along the center line and two edge rays of the beam cone.
func _generate_beam_sample_points(origin: Vector2, direction: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var beam_half_angle_rad := deg_to_rad(BEAM_HALF_ANGLE_DEG)

	# Sample along center line
	for i in range(1, BEAM_SAMPLE_COUNT + 1):
		var t := float(i) / float(BEAM_SAMPLE_COUNT)
		var dist := t * FLASHLIGHT_MAX_RANGE
		points.append(origin + direction * dist)

	# Sample along left edge of beam cone
	var left_dir := direction.rotated(-beam_half_angle_rad)
	for i in range(1, BEAM_SAMPLE_COUNT + 1):
		var t := float(i) / float(BEAM_SAMPLE_COUNT)
		var dist := t * FLASHLIGHT_MAX_RANGE
		points.append(origin + left_dir * dist)

	# Sample along right edge of beam cone
	var right_dir := direction.rotated(beam_half_angle_rad)
	for i in range(1, BEAM_SAMPLE_COUNT + 1):
		var t := float(i) / float(BEAM_SAMPLE_COUNT)
		var dist := t * FLASHLIGHT_MAX_RANGE
		points.append(origin + right_dir * dist)

	return points


## Check if a point is within the flashlight beam cone (no wall check, just geometry).
func _is_point_in_beam_cone(point: Vector2, origin: Vector2, direction: Vector2) -> bool:
	var dist := origin.distance_to(point)
	if dist > FLASHLIGHT_MAX_RANGE or dist < 0.01:
		return true  # Origin point is always in the beam

	var dir_to_point := (point - origin).normalized()
	var dot := direction.dot(dir_to_point)
	var cos_half_angle := cos(deg_to_rad(BEAM_HALF_ANGLE_DEG))
	return dot >= cos_half_angle


## Check line of sight from the enemy to a beam point (Issue #574).
## Verifies the enemy can actually see the illuminated surface.
func _check_enemy_los_to_point(enemy_pos: Vector2, point: Vector2, raycast: RayCast2D) -> bool:
	if raycast == null:
		return true  # Assume LOS if no raycast available

	# Save original raycast state
	var original_target := raycast.target_position
	var original_enabled := raycast.enabled

	# Cast ray from enemy toward the beam point
	var direction := point - enemy_pos
	raycast.target_position = direction
	raycast.enabled = true
	raycast.force_raycast_update()

	var has_los := true

	if raycast.is_colliding():
		var collision_point := raycast.get_collision_point()
		var enemy_parent := raycast.get_parent() as Node2D
		if enemy_parent:
			var distance_to_point := enemy_parent.global_position.distance_to(point)
			var distance_to_collision := enemy_parent.global_position.distance_to(collision_point)
			# Wall is before the beam point — LOS blocked
			has_los = distance_to_collision >= distance_to_point - 10.0

	# Restore raycast state
	raycast.target_position = original_target
	raycast.enabled = original_enabled

	return has_los


## Check if the flashlight beam reaches a point without being blocked by walls (Issue #629).
## Uses the enemy's world physics to cast a ray from the flashlight origin to the target point.
## This prevents enemies from detecting beam points that are behind walls from the flashlight.
func _check_beam_reaches_point(beam_origin: Vector2, target_point: Vector2, raycast: RayCast2D) -> bool:
	if raycast == null:
		return true  # Assume beam reaches if no raycast available

	var enemy_node := raycast.get_parent() as Node2D
	if enemy_node == null:
		return true

	var space_state := enemy_node.get_world_2d().direct_space_state
	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(beam_origin, target_point)
	query.collision_mask = 4  # Layer 3: obstacles/walls
	var result := space_state.intersect_ray(query)
	return result.is_empty()


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


## Check if a specific position is illuminated by the flashlight beam (Issue #574).
## Used for passage avoidance — enemies check if a doorway/corridor is lit.
##
## Parameters:
## - position: The position to check (e.g., a doorway or navigation waypoint)
## - player: Reference to the player node
## - raycast: Optional RayCast2D for wall occlusion checks (Issue #629).
##   When provided, verifies the beam isn't blocked by a wall between the
##   flashlight origin and the position. Without a raycast, only the geometric
##   cone is checked (which can give false positives through walls).
##
## Returns true if the position is within the flashlight beam cone and the beam
## is not blocked by a wall.
func is_position_lit(position: Vector2, player: Node2D, raycast: RayCast2D = null) -> bool:
	if player == null or not is_instance_valid(player):
		return false

	if not player.has_method("is_flashlight_on") or not player.is_flashlight_on():
		return false

	# Issue #640: Wall-clamped beam cannot illuminate positions through walls.
	if player.has_method("is_flashlight_wall_clamped") and player.is_flashlight_wall_clamped():
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

	if dot < cos(beam_half_angle_rad):
		return false

	# Wall occlusion check (Issue #629): verify the beam actually reaches
	# this position and isn't blocked by a wall.
	if raycast != null and not _check_beam_reaches_point(flashlight_origin, position, raycast):
		return false

	return true


## Check if the next navigation waypoint is illuminated by the flashlight (Issue #574).
## Used by the GOAP planner to decide whether to avoid a lit passage.
##
## Parameters:
## - nav_agent: The enemy's NavigationAgent2D
## - player: Reference to the player node
## - raycast: Optional RayCast2D for wall occlusion checks (Issue #629)
##
## Returns true if the next waypoint in the navigation path is lit by the flashlight.
func is_next_waypoint_lit(nav_agent: NavigationAgent2D, player: Node2D, raycast: RayCast2D = null) -> bool:
	if nav_agent == null or nav_agent.is_navigation_finished():
		return false

	var next_pos := nav_agent.get_next_path_position()
	return is_position_lit(next_pos, player, raycast)


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
