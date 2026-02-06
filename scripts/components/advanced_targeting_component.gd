class_name AdvancedTargetingComponent
extends Node
## Advanced targeting component for enemy AI.
##
## Provides ricochet and wallbang (penetration) targeting capabilities.
## Enemies can use this to hit players behind cover by:
## 1. Shooting through thin walls (wallbang)
## 2. Bouncing bullets off walls (ricochet)
##
## Issue #349: Enemy mechanics understanding

## Wallbang opportunity data structure
class WallbangInfo:
	var valid: bool = false
	var aim_point: Vector2 = Vector2.ZERO
	var wall_thickness: float = 0.0
	var damage_multiplier: float = 1.0
	var last_check_time: float = 0.0

## Ricochet path data structure
class RicochetPath:
	var valid: bool = false
	var aim_point: Vector2 = Vector2.ZERO      # Where to aim (wall point)
	var bounce_point: Vector2 = Vector2.ZERO   # Where bullet bounces (same as aim_point for single bounce)
	var second_bounce: Vector2 = Vector2.ZERO  # Second bounce point (for double ricochet)
	var final_target: Vector2 = Vector2.ZERO   # Player position
	var probability: float = 0.0               # Ricochet success probability
	var bounce_count: int = 0                  # Number of bounces (1 or 2)
	var last_check_time: float = 0.0

# Export settings

## Enable/disable wallbang shots
@export var enable_wallbang_shots: bool = true

## Enable/disable ricochet shots
@export var enable_ricochet_shots: bool = true

## Enable/disable double ricochet shots (computationally expensive)
@export var enable_double_ricochet: bool = true

## Wallbang check interval (seconds)
@export var wallbang_check_interval: float = 0.5

## Ricochet check interval (seconds)
@export var ricochet_check_interval: float = 0.3

## Double ricochet check interval (seconds) - slower due to O(n^2) complexity
@export var double_ricochet_check_interval: float = 1.0

## Minimum damage multiplier to attempt wallbang (filter out weak shots)
@export var wallbang_min_damage_threshold: float = 0.3

## Minimum ricochet probability to attempt (filter out unlikely shots)
@export var ricochet_min_probability_threshold: float = 0.5

## Minimum combined probability for double ricochet
@export var double_ricochet_min_probability_threshold: float = 0.25

## Maximum distance to search for ricochet walls
@export var ricochet_search_radius: float = 500.0

## Maximum total ricochet path distance (enemy -> wall -> player)
@export var ricochet_max_total_distance: float = 800.0

## Maximum penetration distance for wallbang (from caliber data)
@export var max_penetration_distance: float = 48.0

## Damage multiplier after penetration (from caliber data)
@export var post_penetration_damage_multiplier: float = 0.9

## Enable debug logging
@export var debug_logging: bool = false

# Internal state

## Parent node (the enemy using this component)
var _parent: Node2D = null

## Cached wallbang opportunity
var _wallbang_info: WallbangInfo = WallbangInfo.new()

## Cached ricochet path
var _ricochet_path: RicochetPath = RicochetPath.new()

## Reference to player (set by parent)
var _player: Node2D = null

## Callback for getting predicted player position (set by parent)
var _get_predicted_position_callback: Callable = Callable()

## Callback for checking if player is visible (set by parent)
var _can_see_player_callback: Callable = Callable()

## Suspected target position from enemy memory (snap-shooting, Issue #349)
var _suspected_target_pos: Vector2 = Vector2.ZERO

## Confidence level for suspected target (0.0-1.0)
var _suspected_confidence: float = 0.0

## Whether we're targeting a suspected position vs confirmed player position
var _using_suspected_target: bool = false

## Wall collision mask (layer 3 = bit 4)
const WALL_LAYER_MASK: int = 4


func _ready() -> void:
	_parent = get_parent() as Node2D
	# Initialize with empty info
	_wallbang_info = WallbangInfo.new()
	_ricochet_path = RicochetPath.new()


## Initialize the component with required callbacks.
## @param player: Reference to the player node.
## @param get_predicted_pos: Callable that returns Vector2 (predicted player position).
## @param can_see_player: Callable that returns bool (whether player is visible).
func initialize(player: Node2D, get_predicted_pos: Callable, can_see_player: Callable) -> void:
	_player = player
	_get_predicted_position_callback = get_predicted_pos
	_can_see_player_callback = can_see_player


## Set a suspected target position for snap-shooting (Issue #349).
## Enemies will attempt ricochet/wallbang toward this position with minimal suspicion.
## @param position: Suspected player position (from memory/sound).
## @param confidence: Confidence level 0.0-1.0 (affects shot probability).
func set_suspected_target(position: Vector2, confidence: float) -> void:
	_suspected_target_pos = position
	_suspected_confidence = clampf(confidence, 0.0, 1.0)

## Clear suspected target (e.g., when player is found or memory decays).
func clear_suspected_target() -> void:
	_suspected_target_pos = Vector2.ZERO
	_suspected_confidence = 0.0
	_using_suspected_target = false

## Update targeting calculations. Call this from the parent's _physics_process.
## Supports both confirmed player positions and suspected positions (snap-shooting).
func update_targeting() -> void:
	if not _parent:
		return

	# Can target if we have a player OR a suspected position
	if _player == null and _suspected_confidence <= 0.0:
		return

	_check_wallbang_opportunity()
	_find_ricochet_path()


## Get the current best targeting opportunity.
## Returns a Dictionary with targeting info:
## - type: "direct", "ricochet", "wallbang", or "none"
## - aim_point: Vector2 - where to aim
## - probability: float - success probability (1.0 for direct/wallbang)
## - bounce_count: int - number of bounces (0 for direct/wallbang)
## - suspected: bool - true if targeting a suspected (not confirmed) position
func get_best_targeting() -> Dictionary:
	# Check if we can see the player directly
	if _can_see_player_callback.is_valid() and _can_see_player_callback.call():
		var target_pos := _get_predicted_player_position()
		return {
			"type": "direct",
			"aim_point": target_pos,
			"probability": 1.0,
			"bounce_count": 0,
			"suspected": false
		}

	# Check ricochet path (prefer ricochet over wallbang for tactical variety)
	if enable_ricochet_shots and _ricochet_path.valid:
		# Scale probability by confidence when using suspected position
		var prob: float = _ricochet_path.probability
		if _using_suspected_target:
			prob *= _suspected_confidence
		return {
			"type": "ricochet",
			"aim_point": _ricochet_path.aim_point,
			"probability": prob,
			"bounce_count": _ricochet_path.bounce_count,
			"suspected": _using_suspected_target
		}

	# Check wallbang opportunity
	if enable_wallbang_shots and _wallbang_info.valid:
		var prob: float = 1.0
		if _using_suspected_target:
			prob = _suspected_confidence
		return {
			"type": "wallbang",
			"aim_point": _wallbang_info.aim_point,
			"probability": prob,
			"bounce_count": 0,
			"suspected": _using_suspected_target
		}

	return {
		"type": "none",
		"aim_point": Vector2.ZERO,
		"probability": 0.0,
		"bounce_count": 0,
		"suspected": false
	}


## Check if we have any valid targeting opportunity (ricochet or wallbang).
func has_indirect_targeting() -> bool:
	return _ricochet_path.valid or _wallbang_info.valid


## Get the ricochet path info.
func get_ricochet_path() -> RicochetPath:
	return _ricochet_path


## Get the wallbang info.
func get_wallbang_info() -> WallbangInfo:
	return _wallbang_info


## Clear all cached targeting data.
func clear_targeting() -> void:
	_wallbang_info = WallbangInfo.new()
	_ricochet_path = RicochetPath.new()


# ============================================================================
# Wallbang (Penetration) Targeting
# ============================================================================


## Check for wallbang opportunity to hit player through thin walls.
func _check_wallbang_opportunity() -> void:
	if not enable_wallbang_shots:
		return

	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _wallbang_info.last_check_time < wallbang_check_interval:
		return

	_wallbang_info.last_check_time = current_time
	_wallbang_info.valid = false

	if not _parent:
		return

	# Check if we can see the player directly (no wallbang needed)
	if _can_see_player_callback.is_valid() and _can_see_player_callback.call():
		return

	var target_pos := _get_predicted_player_position()
	if target_pos == Vector2.ZERO:
		return
	var enemy_pos := _parent.global_position

	# Cast ray to find walls between enemy and player
	var space_state := _parent.get_world_2d().direct_space_state
	var direction := (target_pos - enemy_pos).normalized()
	var query := PhysicsRayQueryParameters2D.create(enemy_pos, target_pos)
	query.collision_mask = WALL_LAYER_MASK
	query.exclude = [_parent]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return  # No wall in the way (shouldn't happen if player not visible)

	# Estimate wall thickness
	var entry_point: Vector2 = result.position
	var wall_body = result.collider
	var thickness := _estimate_wall_thickness(entry_point, wall_body, direction)

	# Check if we can penetrate
	if thickness <= max_penetration_distance:
		# Calculate damage multiplier based on penetration distance
		# Each 24 pixels of penetration applies the damage multiplier
		var penetration_steps := ceil(thickness / 24.0)
		var damage_mult := pow(post_penetration_damage_multiplier, penetration_steps)

		if damage_mult >= wallbang_min_damage_threshold:
			_wallbang_info.valid = true
			_wallbang_info.aim_point = target_pos
			_wallbang_info.wall_thickness = thickness
			_wallbang_info.damage_multiplier = damage_mult

			_log_debug("Wallbang opportunity found: thickness=%.1f, damage=%.1f%%" % [
				thickness, damage_mult * 100
			])


## Estimate the thickness of a wall by stepping through it.
## @param entry_point: Where the bullet enters the wall.
## @param wall_body: The wall collider.
## @param direction: Direction of travel (normalized).
## @return: Estimated wall thickness in pixels.
func _estimate_wall_thickness(entry_point: Vector2, wall_body: Object, direction: Vector2) -> float:
	var space_state := _parent.get_world_2d().direct_space_state
	var step_size := 5.0
	var max_thickness := 100.0
	var current_pos := entry_point + direction * step_size

	for i in range(int(max_thickness / step_size)):
		# Check if we're still inside the wall
		var check_start := current_pos - direction * 2.0
		var check_end := current_pos + direction * 2.0
		var query := PhysicsRayQueryParameters2D.create(check_start, check_end)
		query.collision_mask = WALL_LAYER_MASK
		query.exclude = [_parent]

		var result := space_state.intersect_ray(query)
		if result.is_empty() or result.collider != wall_body:
			# Exited the wall
			return current_pos.distance_to(entry_point)

		current_pos += direction * step_size

	return max_thickness  # Wall is too thick


# ============================================================================
# Ricochet Targeting
# ============================================================================


## Find a ricochet path to hit the player via wall bounce.
func _find_ricochet_path() -> void:
	if not enable_ricochet_shots:
		return

	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _ricochet_path.last_check_time < ricochet_check_interval:
		return

	_ricochet_path.last_check_time = current_time
	_ricochet_path.valid = false

	if not _parent:
		return

	# Skip if we have direct line of sight (prefer direct shots)
	if _can_see_player_callback.is_valid() and _can_see_player_callback.call():
		return

	var player_pos := _get_predicted_player_position()
	if player_pos == Vector2.ZERO:
		return
	var enemy_pos := _parent.global_position

	# Get nearby wall segments by raycasting
	var walls := _get_nearby_wall_segments()

	var best_path: RicochetPath = null
	var best_probability := 0.0

	# Try single ricochet paths
	for wall in walls:
		var path := _calculate_ricochet_for_wall(wall, player_pos)
		if path.valid and path.probability > best_probability:
			best_path = path
			best_probability = path.probability

	# Try double ricochet if enabled and no good single ricochet found
	if enable_double_ricochet and best_probability < 0.7:
		var double_interval_check := current_time - _ricochet_path.last_check_time
		# Only check double ricochet periodically due to O(n^2) complexity
		if double_interval_check < double_ricochet_check_interval:
			for wall1 in walls:
				for wall2 in walls:
					if wall1 == wall2:
						continue
					var path := _calculate_double_ricochet(wall1, wall2, player_pos)
					if path.valid and path.probability > best_probability:
						best_path = path
						best_probability = path.probability

	if best_path != null:
		_ricochet_path = best_path
		_log_debug("Ricochet path found: aim=%v, probability=%.1f%%, bounces=%d" % [
			_ricochet_path.aim_point, _ricochet_path.probability * 100, _ricochet_path.bounce_count
		])


## Calculate ricochet path for a specific wall using mirror-point technique.
## @param wall: Dictionary with start, end, normal vectors.
## @param player_pos: Target player position.
## @return: RicochetPath with path info.
func _calculate_ricochet_for_wall(wall: Dictionary, player_pos: Vector2) -> RicochetPath:
	var path := RicochetPath.new()
	var enemy_pos := _parent.global_position

	# Get wall geometry
	var wall_start: Vector2 = wall.start
	var wall_end: Vector2 = wall.end
	var wall_dir := (wall_end - wall_start).normalized()
	var wall_normal: Vector2 = wall.normal

	# Calculate mirror point of player across wall
	var to_player := player_pos - wall_start
	var dist_to_wall := to_player.dot(wall_normal)

	# Player and enemy must be on opposite sides of the wall for ricochet to work
	var to_enemy := enemy_pos - wall_start
	var enemy_side := to_enemy.dot(wall_normal)
	if dist_to_wall * enemy_side > 0:
		# Same side of wall - no ricochet possible
		return path

	var mirror_player := player_pos - 2.0 * dist_to_wall * wall_normal

	# Find intersection of enemy -> mirror_player line with wall segment
	var intersection := _line_segment_intersection(
		enemy_pos, mirror_player,
		wall_start, wall_end
	)

	if not intersection.valid:
		return path

	var aim_point: Vector2 = intersection.point

	# Check LOS from enemy to aim point
	if not _has_clear_shot_to(aim_point):
		return path

	# Calculate impact angle and probability
	var incoming_dir := (aim_point - enemy_pos).normalized()
	var impact_angle := _calculate_bullet_impact_angle(incoming_dir, wall_normal)
	var probability := _calculate_ricochet_probability_for_angle(impact_angle)

	if probability < ricochet_min_probability_threshold:
		return path

	# Verify reflected path reaches player
	var reflected_dir := incoming_dir - 2.0 * incoming_dir.dot(wall_normal) * wall_normal
	reflected_dir = reflected_dir.normalized()
	if not _reflected_path_reaches_target(aim_point, reflected_dir, player_pos):
		return path

	# Check total distance
	var total_dist := enemy_pos.distance_to(aim_point) + aim_point.distance_to(player_pos)
	if total_dist > ricochet_max_total_distance:
		return path

	path.valid = true
	path.aim_point = aim_point
	path.bounce_point = aim_point
	path.final_target = player_pos
	path.probability = probability
	path.bounce_count = 1

	return path


## Calculate double ricochet path using two walls.
## @param wall1: First wall to bounce off.
## @param wall2: Second wall to bounce off.
## @param player_pos: Target player position.
## @return: RicochetPath with double bounce info.
func _calculate_double_ricochet(wall1: Dictionary, wall2: Dictionary, player_pos: Vector2) -> RicochetPath:
	var path := RicochetPath.new()
	var enemy_pos := _parent.global_position

	# Get wall geometry
	var wall1_start: Vector2 = wall1.start
	var wall1_end: Vector2 = wall1.end
	var wall1_normal: Vector2 = wall1.normal

	var wall2_start: Vector2 = wall2.start
	var wall2_end: Vector2 = wall2.end
	var wall2_normal: Vector2 = wall2.normal

	# Mirror player across wall2 to get intermediate target
	var to_player := player_pos - wall2_start
	var dist_to_wall2 := to_player.dot(wall2_normal)
	var mirror1 := player_pos - 2.0 * dist_to_wall2 * wall2_normal

	# Mirror that across wall1 to get aim target
	var to_mirror1 := mirror1 - wall1_start
	var dist_to_wall1 := to_mirror1.dot(wall1_normal)
	var mirror2 := mirror1 - 2.0 * dist_to_wall1 * wall1_normal

	# Find where enemy -> mirror2 hits wall1
	var intersection1 := _line_segment_intersection(
		enemy_pos, mirror2,
		wall1_start, wall1_end
	)

	if not intersection1.valid:
		return path

	var bounce1: Vector2 = intersection1.point

	# Check LOS from enemy to first bounce
	if not _has_clear_shot_to(bounce1):
		return path

	# Find where bounce1 -> mirror1 hits wall2
	var intersection2 := _line_segment_intersection(
		bounce1, mirror1,
		wall2_start, wall2_end
	)

	if not intersection2.valid:
		return path

	var bounce2: Vector2 = intersection2.point

	# Check LOS from bounce1 to bounce2
	if not _has_clear_line(bounce1, bounce2):
		return path

	# Calculate impact angles and combined probability
	var incoming1 := (bounce1 - enemy_pos).normalized()
	var angle1 := _calculate_bullet_impact_angle(incoming1, wall1_normal)
	var prob1 := _calculate_ricochet_probability_for_angle(angle1)

	var incoming2 := (bounce2 - bounce1).normalized()
	var angle2 := _calculate_bullet_impact_angle(incoming2, wall2_normal)
	var prob2 := _calculate_ricochet_probability_for_angle(angle2)

	var combined_prob := prob1 * prob2

	if combined_prob < double_ricochet_min_probability_threshold:
		return path

	# Verify final path reaches player
	var reflected2 := incoming2 - 2.0 * incoming2.dot(wall2_normal) * wall2_normal
	reflected2 = reflected2.normalized()
	if not _reflected_path_reaches_target(bounce2, reflected2, player_pos):
		return path

	# Check total distance
	var total_dist := enemy_pos.distance_to(bounce1) + bounce1.distance_to(bounce2) + bounce2.distance_to(player_pos)
	if total_dist > ricochet_max_total_distance * 1.5:  # Allow longer for double bounce
		return path

	path.valid = true
	path.aim_point = bounce1
	path.bounce_point = bounce1
	path.second_bounce = bounce2
	path.final_target = player_pos
	path.probability = combined_prob
	path.bounce_count = 2

	return path


## Get nearby wall segments by raycasting in multiple directions.
## @return: Array of wall dictionaries with start, end, normal.
func _get_nearby_wall_segments() -> Array:
	var walls: Array = []
	var space_state := _parent.get_world_2d().direct_space_state
	var enemy_pos := _parent.global_position

	# Sample walls by casting rays in multiple directions
	for angle_deg in range(0, 360, 15):  # Every 15 degrees
		var direction := Vector2.from_angle(deg_to_rad(angle_deg))
		var query := PhysicsRayQueryParameters2D.create(
			enemy_pos,
			enemy_pos + direction * ricochet_search_radius
		)
		query.collision_mask = WALL_LAYER_MASK
		query.exclude = [_parent]

		var result := space_state.intersect_ray(query)
		if not result.is_empty():
			# Estimate wall segment from hit point and normal
			var hit_point: Vector2 = result.position
			var normal: Vector2 = result.normal
			var wall_dir := Vector2(-normal.y, normal.x)

			# Create approximate wall segment (200 pixels long centered on hit)
			var wall := {
				"start": hit_point - wall_dir * 100.0,
				"end": hit_point + wall_dir * 100.0,
				"normal": normal,
				"hit_point": hit_point
			}

			# Avoid duplicates (walls very close to existing ones)
			var is_duplicate := false
			for existing in walls:
				if hit_point.distance_to(existing.hit_point) < 50.0:
					is_duplicate = true
					break

			if not is_duplicate:
				walls.append(wall)

	return walls


# ============================================================================
# Geometry Helpers
# ============================================================================


## Calculate line segment intersection.
## @return: Dictionary with valid: bool and point: Vector2.
func _line_segment_intersection(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> Dictionary:
	var d1 := p2 - p1
	var d2 := p4 - p3
	var d3 := p1 - p3

	var cross := d1.x * d2.y - d1.y * d2.x

	if abs(cross) < 0.0001:
		return {"valid": false}  # Lines are parallel

	var t := (d3.x * d2.y - d3.y * d2.x) / cross
	var u := (d3.x * d1.y - d3.y * d1.x) / cross

	# Check if intersection is within both segments
	if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
		return {
			"valid": true,
			"point": p1 + t * d1
		}

	return {"valid": false}


## Calculate the bullet impact angle (grazing angle).
## @return: Angle in radians (0 = grazing, PI/2 = perpendicular).
func _calculate_bullet_impact_angle(direction: Vector2, surface_normal: Vector2) -> float:
	var dot := absf(direction.normalized().dot(surface_normal.normalized()))
	dot = clampf(dot, 0.0, 1.0)
	return asin(dot)  # Returns grazing angle in radians


## Calculate ricochet probability based on impact angle.
## Uses the same curve as bullet.gd for consistency.
func _calculate_ricochet_probability_for_angle(impact_angle_rad: float) -> float:
	var impact_angle_deg := rad_to_deg(impact_angle_rad)
	var max_angle := 90.0

	if impact_angle_deg > max_angle:
		return 0.0

	# Match bullet.gd probability curve:
	# probability = base * (0.9 * (1 - (angle/90)^2.17) + 0.1)
	var normalized_angle := impact_angle_deg / 90.0
	var power_factor := pow(normalized_angle, 2.17)
	var angle_factor := (1.0 - power_factor) * 0.9 + 0.1

	return angle_factor


## Check if there's a clear shot from enemy to target (no walls in between).
func _has_clear_shot_to(target: Vector2) -> bool:
	var space_state := _parent.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(_parent.global_position, target)
	query.collision_mask = WALL_LAYER_MASK
	query.exclude = [_parent]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true

	# Allow if very close to target (rounding errors)
	return result.position.distance_to(target) < 5.0


## Check if there's a clear line between two points.
func _has_clear_line(from: Vector2, to: Vector2) -> bool:
	var space_state := _parent.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = WALL_LAYER_MASK
	query.exclude = [_parent]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true

	# Allow if hit is very close to destination
	return result.position.distance_to(to) < 5.0


## Check if a reflected ray passes near the target position.
func _reflected_path_reaches_target(start: Vector2, direction: Vector2, target: Vector2) -> bool:
	# Calculate perpendicular distance from target to the ray line
	var to_target := target - start
	var projected := to_target.project(direction)

	# Target must be in the direction of reflection (not behind)
	if projected.dot(direction) < 0:
		return false

	# Check perpendicular distance to target
	var perp_dist := (to_target - projected).length()

	# Allow some tolerance for player hitbox size (~50px wide)
	return perp_dist < 50.0


## Get target position for targeting calculations.
## Uses predicted player position when visible, suspected position otherwise.
func _get_predicted_player_position() -> Vector2:
	# If player is visible, use predicted position (most accurate)
	var player_visible := _can_see_player_callback.is_valid() and _can_see_player_callback.call()
	if player_visible:
		_using_suspected_target = false
		if _get_predicted_position_callback.is_valid():
			return _get_predicted_position_callback.call()
		elif _player:
			return _player.global_position

	# If player is not visible but we have a suspected position, use it (snap-shooting)
	if _suspected_confidence > 0.0 and _suspected_target_pos != Vector2.ZERO:
		_using_suspected_target = true
		return _suspected_target_pos

	# Fallback to player's actual position (if we have reference)
	_using_suspected_target = false
	if _get_predicted_position_callback.is_valid():
		return _get_predicted_position_callback.call()
	elif _player:
		return _player.global_position
	return Vector2.ZERO


## Log debug message if debug logging is enabled.
func _log_debug(message: String) -> void:
	if debug_logging:
		var prefix := "[AdvancedTargeting] "
		if _parent and _parent.has_method("_log_debug"):
			_parent._log_debug(prefix + message)
		else:
			print(prefix + message)
