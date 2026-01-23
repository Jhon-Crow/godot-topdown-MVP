class_name VisionComponent
extends Node
## Vision and line-of-sight detection component.
##
## Handles checking if targets are visible, calculating visibility ratios,
## and managing detection state.

## Detection range for spotting targets.
## Set to 0 or negative for unlimited range (line-of-sight only).
@export var detection_range: float = 0.0

## Delay before reacting to newly visible targets (seconds).
@export var detection_delay: float = 0.2

## Delay before enabling lead prediction on visible targets (seconds).
@export var lead_prediction_delay: float = 0.3

## Minimum visibility ratio required for lead prediction.
@export var lead_prediction_visibility_threshold: float = 0.6

## Reference to the RayCast2D for line-of-sight.
var _raycast: RayCast2D = null

## Parent node (the entity using this component).
var _parent: Node2D = null

## Currently tracked target.
var _target: Node2D = null

## Whether the target is currently visible.
var _can_see_target: bool = false

## Detection delay timer.
var _detection_timer: float = 0.0

## Whether detection delay has elapsed.
var _detection_delay_elapsed: bool = false

## Continuous visibility timer.
var _continuous_visibility_timer: float = 0.0

## Current visibility ratio of target (0.0 to 1.0).
var _target_visibility_ratio: float = 0.0

## Signal emitted when target visibility changes.
signal target_visibility_changed(is_visible: bool)

## Signal emitted when detection is confirmed (after delay).
signal target_detected


func _ready() -> void:
	_parent = get_parent() as Node2D
	_find_raycast()


## Set the raycast to use for line-of-sight checks.
func set_raycast(raycast: RayCast2D) -> void:
	_raycast = raycast


## Find raycast in parent.
func _find_raycast() -> void:
	if _parent:
		_raycast = _parent.get_node_or_null("RayCast2D")


## Set the target to track.
func set_target(target: Node2D) -> void:
	_target = target


## Check visibility of the current target.
func check_visibility() -> void:
	if not _parent or not _target or not _raycast:
		_can_see_target = false
		return

	var was_visible := _can_see_target

	# Check range (if range is set)
	if detection_range > 0.0:
		var distance := _parent.global_position.distance_to(_target.global_position)
		if distance > detection_range:
			_can_see_target = false
			if was_visible:
				target_visibility_changed.emit(false)
				_reset_detection_timers()
			return

	# Perform line-of-sight check
	_can_see_target = _check_line_of_sight(_target.global_position)

	if _can_see_target:
		_continuous_visibility_timer += get_physics_process_delta_time()
		_target_visibility_ratio = _calculate_visibility_ratio()

		if not was_visible:
			target_visibility_changed.emit(true)
	else:
		if was_visible:
			target_visibility_changed.emit(false)
		_reset_detection_timers()


## Check line-of-sight to a position.
func _check_line_of_sight(target_pos: Vector2) -> bool:
	if not _raycast or not _parent:
		return false

	_raycast.target_position = _raycast.to_local(target_pos)
	_raycast.force_raycast_update()

	if not _raycast.is_colliding():
		return true

	# Check if the collider is the target
	var collider := _raycast.get_collider()
	if collider == _target:
		return true

	# Check if collider is a child of the target
	if collider and _target:
		var parent: Node = collider.get_parent()
		while parent:
			if parent == _target:
				return true
			parent = parent.get_parent()

	return false


## Calculate visibility ratio using multiple check points.
func _calculate_visibility_ratio() -> float:
	if not _target:
		return 0.0

	var check_points := _get_target_check_points(_target.global_position)
	var visible_count := 0

	for point in check_points:
		if _is_point_visible(point):
			visible_count += 1

	return float(visible_count) / float(check_points.size())


## Get check points around the target center.
func _get_target_check_points(center: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var radius := 15.0  # Approximate target size

	points.append(center)
	points.append(center + Vector2(0, -radius))  # Top
	points.append(center + Vector2(0, radius))   # Bottom
	points.append(center + Vector2(-radius, 0))  # Left
	points.append(center + Vector2(radius, 0))   # Right

	return points


## Check if a specific point is visible.
func _is_point_visible(point: Vector2) -> bool:
	if not _raycast or not _parent:
		return false

	_raycast.target_position = _raycast.to_local(point)
	_raycast.force_raycast_update()

	return not _raycast.is_colliding()


## Update detection timer (call from _physics_process).
func update_detection(delta: float) -> void:
	if _can_see_target and not _detection_delay_elapsed:
		_detection_timer += delta
		if _detection_timer >= detection_delay:
			_detection_delay_elapsed = true
			target_detected.emit()


## Reset detection timers.
func _reset_detection_timers() -> void:
	_detection_timer = 0.0
	_detection_delay_elapsed = false
	_continuous_visibility_timer = 0.0
	_target_visibility_ratio = 0.0


## Check if target is currently visible.
func can_see_target() -> bool:
	return _can_see_target


## Check if detection delay has elapsed.
func is_detection_confirmed() -> bool:
	return _detection_delay_elapsed


## Check if lead prediction should be enabled.
func should_enable_lead_prediction() -> bool:
	return _continuous_visibility_timer >= lead_prediction_delay and \
		   _target_visibility_ratio >= lead_prediction_visibility_threshold


## Get the current visibility ratio.
func get_visibility_ratio() -> float:
	return _target_visibility_ratio


## Get the continuous visibility time.
func get_continuous_visibility_time() -> float:
	return _continuous_visibility_timer


## Check if a position is visible from the parent.
func is_position_visible(pos: Vector2) -> bool:
	if not _raycast or not _parent:
		return false

	_raycast.target_position = _raycast.to_local(pos)
	_raycast.force_raycast_update()

	return not _raycast.is_colliding()
