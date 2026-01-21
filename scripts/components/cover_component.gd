class_name CoverComponent
extends Node
## Cover detection and evaluation component.
##
## Handles finding cover positions, evaluating cover quality,
## and tracking current cover state.

## Number of raycasts for cover detection.
@export var cover_check_count: int = 16

## Distance to check for cover.
@export var cover_check_distance: float = 300.0

## Minimum distance from current position for valid cover.
@export var min_cover_distance: float = 50.0

## Minimum distance progress required for pursuit cover (fraction).
@export var pursuit_min_progress_fraction: float = 0.10

## Penalty for cover on same obstacle.
@export var same_obstacle_penalty: float = 4.0

## Parent node (the entity using this component).
var _parent: Node2D = null

## Cover detection raycasts.
var _cover_raycasts: Array[RayCast2D] = []

## Current cover position.
var _cover_position: Vector2 = Vector2.ZERO

## Whether we have valid cover.
var _has_valid_cover: bool = false

## The obstacle of current cover (for penalty calculation).
var _current_cover_obstacle: Object = null

## Target (usually the player) to hide from.
var _threat_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_parent = get_parent() as Node2D
	call_deferred("_setup_cover_detection")


## Setup cover detection raycasts.
func _setup_cover_detection() -> void:
	for i in range(cover_check_count):
		var raycast := RayCast2D.new()
		raycast.enabled = true
		raycast.collision_mask = 4  # Obstacles layer
		raycast.exclude_parent = true
		add_child(raycast)
		_cover_raycasts.append(raycast)


## Set the threat position to hide from.
func set_threat_position(pos: Vector2) -> void:
	_threat_position = pos


## Find the best cover position.
func find_cover() -> void:
	if not _parent:
		return

	var best_cover: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var best_obstacle: Object = null

	# Cast rays in all directions
	var angle_step := TAU / float(cover_check_count)
	for i in range(cover_check_count):
		var angle := i * angle_step
		var direction := Vector2.from_angle(angle)
		var raycast := _cover_raycasts[i]

		raycast.target_position = direction * cover_check_distance
		raycast.force_raycast_update()

		if not raycast.is_colliding():
			continue

		var hit_point := raycast.get_collision_point()
		var obstacle := raycast.get_collider()

		# Calculate cover position (slightly away from wall)
		var normal := raycast.get_collision_normal()
		var cover_pos := hit_point + normal * 30.0

		# Evaluate cover quality
		var score := _evaluate_cover(cover_pos, obstacle)

		if score > best_score:
			best_score = score
			best_cover = cover_pos
			best_obstacle = obstacle

	if best_score > 0.0:
		_cover_position = best_cover
		_has_valid_cover = true
		_current_cover_obstacle = best_obstacle
	else:
		_has_valid_cover = false


## Find cover that moves closer to a target position.
func find_pursuit_cover(target_pos: Vector2) -> Vector2:
	if not _parent:
		return Vector2.ZERO

	var current_distance := _parent.global_position.distance_to(target_pos)
	var best_cover: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	var best_obstacle: Object = null

	var angle_step := TAU / float(cover_check_count)
	for i in range(cover_check_count):
		var angle := i * angle_step
		var direction := Vector2.from_angle(angle)
		var raycast := _cover_raycasts[i]

		raycast.target_position = direction * cover_check_distance
		raycast.force_raycast_update()

		if not raycast.is_colliding():
			continue

		var hit_point := raycast.get_collision_point()
		var obstacle := raycast.get_collider()
		var normal := raycast.get_collision_normal()
		var cover_pos := hit_point + normal * 30.0

		# Check distance progress
		var new_distance := cover_pos.distance_to(target_pos)
		var progress := current_distance - new_distance
		var progress_fraction := progress / current_distance

		if progress_fraction < pursuit_min_progress_fraction:
			continue

		# Evaluate cover
		var score := _evaluate_pursuit_cover(cover_pos, obstacle, target_pos)

		if score > best_score:
			best_score = score
			best_cover = cover_pos
			best_obstacle = obstacle

	if best_score > 0.0:
		_current_cover_obstacle = best_obstacle
		return best_cover

	return Vector2.ZERO


## Evaluate cover quality for defensive purposes.
func _evaluate_cover(cover_pos: Vector2, obstacle: Object) -> float:
	if not _parent:
		return -INF

	var score := 0.0

	# Distance from current position (prefer closer cover)
	var distance := _parent.global_position.distance_to(cover_pos)
	if distance < min_cover_distance:
		return -INF  # Too close

	score -= distance * 0.01  # Small penalty for distance

	# Check if cover blocks line of sight to threat
	if _is_protected_from_threat(cover_pos):
		score += 100.0  # Major bonus for actual cover

	# Penalty for same obstacle as current cover
	if obstacle == _current_cover_obstacle:
		score -= same_obstacle_penalty

	return score


## Evaluate cover for pursuit (moving toward target).
func _evaluate_pursuit_cover(cover_pos: Vector2, obstacle: Object, target_pos: Vector2) -> float:
	if not _parent:
		return -INF

	var score := 0.0

	# Distance to target (prefer cover closer to target)
	var distance_to_target := cover_pos.distance_to(target_pos)
	score -= distance_to_target * 0.1

	# Check if provides cover from threat
	if _is_protected_from_threat(cover_pos):
		score += 50.0

	# Penalty for same obstacle
	if obstacle == _current_cover_obstacle:
		score -= same_obstacle_penalty

	return score


## Check if position is protected from threat.
func _is_protected_from_threat(pos: Vector2) -> bool:
	if _cover_raycasts.is_empty():
		return false

	var raycast := _cover_raycasts[0]
	raycast.global_position = pos
	raycast.target_position = raycast.to_local(_threat_position)
	raycast.force_raycast_update()

	# If raycast hits something, we have cover
	var result := raycast.is_colliding()

	# Reset raycast position
	raycast.global_position = _parent.global_position if _parent else Vector2.ZERO

	return result


## Check if currently in valid cover.
func is_in_cover(tolerance: float = 30.0) -> bool:
	if not _has_valid_cover or not _parent:
		return false

	return _parent.global_position.distance_to(_cover_position) <= tolerance


## Get current cover position.
func get_cover_position() -> Vector2:
	return _cover_position


## Check if has valid cover.
func has_valid_cover() -> bool:
	return _has_valid_cover


## Clear current cover.
func clear_cover() -> void:
	_has_valid_cover = false
	_cover_position = Vector2.ZERO
	_current_cover_obstacle = null
