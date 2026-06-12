extends Node
## Component that handles enemy movement, navigation, and wall avoidance (Issue #336).
## Extracted from enemy.gd to reduce file size below 2500 lines.
class_name EnemyMovementController

## Signal emitted when destination is reached.
signal destination_reached

# Configuration
var move_speed: float = 220.0
var combat_move_speed: float = 320.0
var patrol_wait_time: float = 1.5

# Wall avoidance constants
const WALL_CHECK_DISTANCE: float = 60.0
const WALL_CHECK_COUNT: int = 8
const WALL_AVOIDANCE_MIN_WEIGHT: float = 0.7
const WALL_AVOIDANCE_MAX_WEIGHT: float = 0.3
const WALL_SLIDE_DISTANCE: float = 30.0

# Corner check constants
const CORNER_CHECK_DURATION: float = 0.3
const CORNER_CHECK_DISTANCE: float = 150.0

# State
var _enemy: CharacterBody2D = null
var _nav_agent: NavigationAgent2D = null
var _wall_raycasts: Array[RayCast2D] = []

# Patrol state
var _patrol_points: Array[Vector2] = []
var _current_patrol_index: int = 0
var _is_waiting_at_patrol_point: bool = false
var _patrol_wait_timer: float = 0.0
var _initial_position: Vector2 = Vector2.ZERO

# Corner check state
var _corner_check_angle: float = 0.0
var _corner_check_timer: float = 0.0


func _ready() -> void:
	_enemy = get_parent() as CharacterBody2D


## Initialize with required references.
func initialize(nav_agent: NavigationAgent2D, initial_pos: Vector2) -> void:
	_nav_agent = nav_agent
	_initial_position = initial_pos
	_setup_wall_detection()


## Setup wall detection raycasts.
func _setup_wall_detection() -> void:
	if _enemy == null:
		return

	_wall_raycasts.clear()

	for i in range(WALL_CHECK_COUNT):
		var raycast := RayCast2D.new()
		raycast.enabled = false
		raycast.collision_mask = 2  # Walls
		var angle := (float(i) / float(WALL_CHECK_COUNT)) * TAU
		raycast.target_position = Vector2.RIGHT.rotated(angle) * WALL_CHECK_DISTANCE
		_enemy.add_child(raycast)
		_wall_raycasts.append(raycast)


## Setup patrol points from offsets relative to initial position.
func setup_patrol_points(offsets: Array[Vector2]) -> void:
	_patrol_points.clear()
	_patrol_points.append(_initial_position)

	for offset in offsets:
		_patrol_points.append(_initial_position + offset)


## Update movement logic each frame.
func update(_delta: float) -> void:
	pass  # Placeholder - movement is driven by move_to_target


## Move toward a target position using navigation.
## Returns true if still moving, false if reached destination.
func move_to_target(target_pos: Vector2, speed: float, apply_wall_avoidance: bool = true) -> bool:
	if _enemy == null or _nav_agent == null:
		return false

	_nav_agent.target_position = target_pos

	if _nav_agent.is_navigation_finished():
		_enemy.velocity = Vector2.ZERO
		destination_reached.emit()
		return false

	var next_pos := _nav_agent.get_next_path_position()
	var direction := (next_pos - _enemy.global_position).normalized()

	# Apply wall avoidance if enabled
	if apply_wall_avoidance:
		var wall_avoidance := _get_wall_avoidance_vector()
		if wall_avoidance.length_squared() > 0.01:
			var weight := _get_wall_avoidance_weight()
			direction = (direction * (1.0 - weight) + wall_avoidance.normalized() * weight).normalized()

	_enemy.velocity = direction * speed
	_enemy.move_and_slide()

	return true


## Get direction to target using navigation.
func get_nav_direction_to(target_pos: Vector2) -> Vector2:
	if _enemy == null or _nav_agent == null:
		return Vector2.ZERO

	_nav_agent.target_position = target_pos
	var next_pos := _nav_agent.get_next_path_position()
	return (next_pos - _enemy.global_position).normalized()


## Check if there's a navigable path to a position.
func has_nav_path_to(target_pos: Vector2) -> bool:
	if _nav_agent == null:
		return false

	_nav_agent.target_position = target_pos
	return not _nav_agent.get_current_navigation_path().is_empty()


## Get the navigation path distance to a target.
func get_nav_path_distance(target_pos: Vector2) -> float:
	if _nav_agent == null or _enemy == null:
		return INF

	_nav_agent.target_position = target_pos
	var path := _nav_agent.get_current_navigation_path()

	if path.is_empty():
		return INF

	var distance := 0.0
	var prev := _enemy.global_position
	for point in path:
		distance += prev.distance_to(point)
		prev = point

	return distance


## Check if there's a wall directly ahead in the movement direction.
func check_wall_ahead(direction: Vector2) -> bool:
	if _enemy == null:
		return false

	for raycast in _wall_raycasts:
		raycast.force_raycast_update()

		if not raycast.is_colliding():
			continue

		var ray_dir := raycast.target_position.normalized()
		if ray_dir.dot(direction) > 0.7:
			var dist := raycast.get_collision_point().distance_to(_enemy.global_position)
			if dist < WALL_SLIDE_DISTANCE:
				return true

	return false


## Get wall avoidance vector based on nearby walls.
func _get_wall_avoidance_vector() -> Vector2:
	var avoidance := Vector2.ZERO

	for raycast in _wall_raycasts:
		raycast.force_raycast_update()

		if not raycast.is_colliding():
			continue

		var collision_point := raycast.get_collision_point()
		var dist := collision_point.distance_to(_enemy.global_position)
		var away_dir := (_enemy.global_position - collision_point).normalized()

		# Stronger avoidance when closer
		var strength := 1.0 - (dist / WALL_CHECK_DISTANCE)
		avoidance += away_dir * strength

	return avoidance


## Get wall avoidance weight based on closest wall.
func _get_wall_avoidance_weight() -> float:
	var closest_dist := WALL_CHECK_DISTANCE

	for raycast in _wall_raycasts:
		raycast.force_raycast_update()

		if not raycast.is_colliding():
			continue

		var dist := raycast.get_collision_point().distance_to(_enemy.global_position)
		if dist < closest_dist:
			closest_dist = dist

	var t := closest_dist / WALL_CHECK_DISTANCE
	return lerpf(WALL_AVOIDANCE_MIN_WEIGHT, WALL_AVOIDANCE_MAX_WEIGHT, t)


## Process patrol behavior.
## Returns the patrol target position, or Vector2.ZERO if waiting.
func process_patrol(delta: float) -> Vector2:
	if _patrol_points.is_empty():
		return Vector2.ZERO

	if _is_waiting_at_patrol_point:
		_patrol_wait_timer += delta
		if _patrol_wait_timer >= patrol_wait_time:
			_is_waiting_at_patrol_point = false
			_patrol_wait_timer = 0.0
			_current_patrol_index = (_current_patrol_index + 1) % _patrol_points.size()
		return Vector2.ZERO

	var target := _patrol_points[_current_patrol_index]
	if _enemy.global_position.distance_to(target) < 10.0:
		_is_waiting_at_patrol_point = true
		return Vector2.ZERO

	return target


## Process corner check behavior.
## Returns the angle to look at, or 0 if not checking.
func process_corner_check(delta: float, movement_dir: Vector2, state_name: String = "") -> float:
	if _corner_check_timer > 0.0:
		_corner_check_timer -= delta
		return _corner_check_angle

	# Check for perpendicular openings
	var opening := _detect_perpendicular_opening(movement_dir)
	if opening != 0.0:
		_corner_check_angle = opening
		_corner_check_timer = CORNER_CHECK_DURATION
		return _corner_check_angle

	return 0.0


## Detect perpendicular openings (corners) while moving.
func _detect_perpendicular_opening(movement_dir: Vector2) -> float:
	if _enemy == null:
		return 0.0

	var space_state := _enemy.get_world_2d().direct_space_state
	if space_state == null:
		return 0.0

	# Check left perpendicular
	var left_dir := movement_dir.rotated(-PI / 2)
	var left_result := _check_opening_direction(space_state, left_dir)

	# Check right perpendicular
	var right_dir := movement_dir.rotated(PI / 2)
	var right_result := _check_opening_direction(space_state, right_dir)

	# Return the direction with an opening
	if left_result:
		return left_dir.angle()
	elif right_result:
		return right_dir.angle()

	return 0.0


## Check if there's an opening in a specific direction.
func _check_opening_direction(space_state: PhysicsDirectSpaceState2D, direction: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(
		_enemy.global_position,
		_enemy.global_position + direction * CORNER_CHECK_DISTANCE,
		2  # Wall collision layer
	)
	query.exclude = [_enemy]

	var result := space_state.intersect_ray(query)
	return result.is_empty()


## Stop all movement.
func stop() -> void:
	if _enemy:
		_enemy.velocity = Vector2.ZERO


## Get current patrol point index.
func get_patrol_index() -> int:
	return _current_patrol_index


## Check if waiting at patrol point.
func is_waiting_at_patrol_point() -> bool:
	return _is_waiting_at_patrol_point


## Get the initial position.
func get_initial_position() -> Vector2:
	return _initial_position
