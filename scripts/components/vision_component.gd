class_name VisionComponent
extends Node
## Vision and line-of-sight detection component.
##
## Handles checking if targets are visible, calculating visibility ratios,
## and managing detection state. Supports field of view (FOV) angle limiting.

## Detection range for spotting targets.
## Set to 0 or negative for unlimited range (line-of-sight only).
@export var detection_range: float = 0.0

## Field of view angle in degrees.
## Set to 0 or negative to disable FOV check (360 degree vision).
## Default is 100 degrees as requested in issue #66.
@export var fov_angle: float = 100.0

## Whether FOV checking is enabled.
## When true, targets must be within the FOV cone to be visible.
@export var fov_enabled: bool = true

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

## Current facing direction in radians (where the entity is looking/aiming).
## This is used for FOV calculations. Updated by the parent entity.
var _facing_direction: float = 0.0

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


## Set the facing direction in radians.
## This should be called by the parent entity to update where it's looking.
func set_facing_direction(direction_radians: float) -> void:
	_facing_direction = direction_radians


## Get the current facing direction in radians.
func get_facing_direction() -> float:
	return _facing_direction


## Get the FOV angle in radians (half-angle for cone calculation).
func get_fov_half_angle_radians() -> float:
	return deg_to_rad(fov_angle / 2.0)


## Check if a target position is within the field of view cone.
## The FOV is centered on the facing direction.
func _is_target_in_fov(target_pos: Vector2) -> bool:
	if not _parent:
		return false

	# Calculate direction to target
	var direction_to_target := (target_pos - _parent.global_position).normalized()

	# Calculate facing direction as vector
	var facing_vector := Vector2.from_angle(_facing_direction)

	# Calculate angle between facing direction and direction to target
	# Using dot product: cos(angle) = a · b for normalized vectors
	var dot := facing_vector.dot(direction_to_target)

	# Clamp to handle floating point errors
	dot = clampf(dot, -1.0, 1.0)

	var angle_to_target := acos(dot)

	# Check if angle is within half the FOV angle
	var half_fov := deg_to_rad(fov_angle / 2.0)
	return angle_to_target <= half_fov


## Check if a position is within the field of view cone (public method).
## Can be used by external code to check if arbitrary positions are in FOV.
func is_position_in_fov(pos: Vector2) -> bool:
	if not fov_enabled or fov_angle <= 0.0:
		return true  # No FOV restriction
	return _is_target_in_fov(pos)


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

	# Check FOV angle (if FOV is enabled)
	if fov_enabled and fov_angle > 0.0:
		if not _is_target_in_fov(_target.global_position):
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
		var parent := collider.get_parent()
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
## This only checks line-of-sight, not FOV. Use is_position_visible_with_fov
## if you need both checks.
func is_position_visible(pos: Vector2) -> bool:
	if not _raycast or not _parent:
		return false

	_raycast.target_position = _raycast.to_local(pos)
	_raycast.force_raycast_update()

	return not _raycast.is_colliding()


## Check if a position is visible from the parent, including FOV check.
## Returns true only if position is within FOV cone AND has line-of-sight.
func is_position_visible_with_fov(pos: Vector2) -> bool:
	if not _raycast or not _parent:
		return false

	# Check FOV first (cheaper than raycast)
	if fov_enabled and fov_angle > 0.0:
		if not _is_target_in_fov(pos):
			return false

	# Then check line-of-sight
	return is_position_visible(pos)
