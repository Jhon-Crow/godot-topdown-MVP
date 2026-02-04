extends Node
## Component that handles enemy vision and player visibility detection (Issue #336).
## Extracted from enemy.gd to reduce file size below 2500 lines.
class_name EnemyVisionSystem

## Signal emitted when visibility state changes.
signal visibility_changed(can_see: bool)

# Configuration
var detection_range: float = 0.0  ## 0 = unlimited
var fov_angle: float = 100.0  ## Field of view in degrees
var fov_enabled: bool = true

# State
var _enemy: CharacterBody2D = null
var _player: Node2D = null
var _raycast: RayCast2D = null
var _can_see_player: bool = false
var _continuous_visibility_timer: float = 0.0
var _player_visibility_ratio: float = 0.0

# Check points for multi-point visibility (head, torso, legs)
const CHECK_POINT_HEAD_OFFSET := Vector2(0, -20)
const CHECK_POINT_TORSO_OFFSET := Vector2(0, 0)
const CHECK_POINT_LEGS_OFFSET := Vector2(0, 20)


func _ready() -> void:
	_enemy = get_parent() as CharacterBody2D


## Initialize with required references.
func initialize(raycast: RayCast2D, player: Node2D) -> void:
	_raycast = raycast
	_player = player


## Set the player reference.
func set_player(player: Node2D) -> void:
	_player = player


## Update visibility check each frame.
func update(delta: float, is_blinded: bool = false, memory_confusion_active: bool = false) -> void:
	if _player == null or _enemy == null:
		_can_see_player = false
		return

	var previous_visibility := _can_see_player

	# Can't see if blinded or confused from memory reset
	if is_blinded or memory_confusion_active:
		_can_see_player = false
		_continuous_visibility_timer = 0.0
		_player_visibility_ratio = 0.0
		if previous_visibility != _can_see_player:
			visibility_changed.emit(_can_see_player)
		return

	_can_see_player = _check_player_visibility()

	if _can_see_player:
		_continuous_visibility_timer += delta
		_player_visibility_ratio = _calculate_player_visibility_ratio()
	else:
		_continuous_visibility_timer = 0.0
		_player_visibility_ratio = 0.0

	if previous_visibility != _can_see_player:
		visibility_changed.emit(_can_see_player)


## Check if the enemy can see the player.
func _check_player_visibility() -> bool:
	if _player == null or _enemy == null or _raycast == null:
		return false

	# Check range first (if limited)
	if detection_range > 0.0:
		var distance := _enemy.global_position.distance_to(_player.global_position)
		if distance > detection_range:
			return false

	# Check FOV
	if not _is_position_in_fov(_player.global_position):
		return false

	# Raycast check - use multi-point visibility
	var check_points := _get_player_check_points(_player.global_position)
	for point in check_points:
		if _is_player_point_visible_to_enemy(point):
			return true

	return false


## Check if a position is within the enemy's field of view.
func _is_position_in_fov(target_pos: Vector2) -> bool:
	if _enemy == null:
		return false

	# Check if FOV is enabled globally
	var exp_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	var global_fov_enabled: bool = exp_settings == null or (exp_settings.has_method("is_fov_enabled") and exp_settings.is_fov_enabled())

	if not fov_enabled or not global_fov_enabled:
		return true  # 360° vision

	if fov_angle <= 0.0:
		return true  # 360° vision

	var to_target := (target_pos - _enemy.global_position).normalized()
	var facing := Vector2.RIGHT.rotated(_enemy.rotation)
	var angle := abs(facing.angle_to(to_target))

	return angle <= deg_to_rad(fov_angle / 2.0)


## Get check points around the player center for multi-point visibility.
func _get_player_check_points(center: Vector2) -> Array[Vector2]:
	return [
		center + CHECK_POINT_HEAD_OFFSET,
		center + CHECK_POINT_TORSO_OFFSET,
		center + CHECK_POINT_LEGS_OFFSET
	]


## Get check points around the enemy center.
func _get_enemy_check_points(center: Vector2) -> Array[Vector2]:
	return [
		center + CHECK_POINT_HEAD_OFFSET,
		center + CHECK_POINT_TORSO_OFFSET,
		center + CHECK_POINT_LEGS_OFFSET
	]


## Check if a specific point on the player is visible to the enemy.
func _is_player_point_visible_to_enemy(point: Vector2) -> bool:
	if _enemy == null or _raycast == null:
		return false

	_raycast.target_position = _raycast.to_local(point)
	_raycast.force_raycast_update()

	if not _raycast.is_colliding():
		return true

	var collider := _raycast.get_collider()
	if collider == null:
		return true

	# Check if we hit the player
	if collider == _player:
		return true

	# Check if we hit something the player is part of
	if collider.get_parent() == _player:
		return true

	return false


## Calculate what fraction of the player is visible (0.0-1.0).
func _calculate_player_visibility_ratio() -> float:
	if _player == null:
		return 0.0

	var check_points := _get_player_check_points(_player.global_position)
	var visible_count := 0

	for point in check_points:
		if _is_player_point_visible_to_enemy(point):
			visible_count += 1

	return float(visible_count) / float(check_points.size())


## Check if the enemy is visible from the player's perspective.
func is_visible_from_player() -> bool:
	if _player == null or _enemy == null:
		return false

	var check_points := _get_enemy_check_points(_enemy.global_position)
	for point in check_points:
		if _is_point_visible_from_player(point):
			return true

	return false


## Check if a specific point is visible from the player's perspective.
func _is_point_visible_from_player(point: Vector2) -> bool:
	if _player == null:
		return false

	var space_state := _player.get_world_2d().direct_space_state
	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(
		_player.global_position,
		point,
		2  # Wall collision layer
	)
	query.exclude = [_player]

	var result := space_state.intersect_ray(query)
	return result.is_empty()


## Check if a position is visible from the player.
func is_position_visible_from_player(pos: Vector2) -> bool:
	if _player == null:
		return false

	var space_state := _player.get_world_2d().direct_space_state
	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(
		_player.global_position,
		pos,
		2  # Wall collision layer
	)
	query.exclude = [_player]

	var result := space_state.intersect_ray(query)
	return result.is_empty()


## Check if a position is visible to the enemy.
func is_position_visible_to_enemy(target_pos: Vector2) -> bool:
	if _enemy == null:
		return false

	# Check FOV
	if not _is_position_in_fov(target_pos):
		return false

	var space_state := _enemy.get_world_2d().direct_space_state
	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(
		_enemy.global_position,
		target_pos,
		2  # Wall collision layer
	)
	query.exclude = [_enemy]

	var result := space_state.intersect_ray(query)
	return result.is_empty()


# --- Accessors ---

func can_see_player() -> bool:
	return _can_see_player


func get_visibility_timer() -> float:
	return _continuous_visibility_timer


func get_visibility_ratio() -> float:
	return _player_visibility_ratio
