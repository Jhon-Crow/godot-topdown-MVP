extends Node
class_name GrenadeAvoidanceComponent
## Component that handles enemy grenade avoidance behavior (Issue #407).
## Enemies should flee from grenades (their own or others') to avoid self-damage.
##
## This component:
## - Detects grenades within danger range (effect_radius + safety_margin)
## - Calculates escape positions away from grenades
## - Updates GOAP world state for grenade danger
## - Provides evasion target for enemy movement

## Signal emitted when entering grenade danger zone.
signal entered_danger_zone(grenade: Node2D)

## Signal emitted when exiting grenade danger zone.
signal exited_danger_zone()

## Safety margin beyond grenade effect radius (pixels).
@export var safety_margin: float = 75.0

## Whether we're currently in a grenade danger zone.
var in_danger_zone: bool = false

## Target position to flee to when evading a grenade.
var evasion_target: Vector2 = Vector2.ZERO

## The most dangerous grenade (closest) affecting this enemy.
var most_dangerous_grenade: Node2D = null

## Issue #450: Predicted landing position of the most dangerous grenade.
## Enemies flee from this position instead of the grenade's current position.
var predicted_landing_position: Vector2 = Vector2.ZERO

## Issue #450: Whether we've locked onto a grenade target (prevents recalculation jitter).
## Once enemy starts fleeing from a grenade, they commit to that escape route.
var _locked_grenade: Node2D = null

## Issue #450: The locked predicted position we're fleeing from.
var _locked_position: Vector2 = Vector2.ZERO

## Tracked grenades in danger range.
var _grenades_in_range: Array = []

## Reference to parent enemy.
var _enemy: CharacterBody2D = null

## Reference to RayCast2D for line-of-sight checks (Issue #426).
## Enemies should only react to grenades they can see/hear (not through walls).
var _raycast: RayCast2D = null

## Reference to enemy model for getting facing direction (Issue #426).
## Enemies should only react to grenades within their field of view.
var _enemy_model: Node2D = null

## FOV angle in degrees (Issue #426). If 0 or negative, FOV check is disabled (360° vision).
var _fov_angle: float = 0.0

## Whether FOV checking is enabled for grenade detection (Issue #426).
var _fov_enabled: bool = false


func _ready() -> void:
	_enemy = get_parent() as CharacterBody2D


## Set the raycast to use for line-of-sight visibility checks (Issue #426).
## @param raycast: The RayCast2D node to use for visibility checks.
func set_raycast(raycast: RayCast2D) -> void:
	_raycast = raycast


## Set the enemy model for FOV direction checks (Issue #426).
## @param model: The enemy model Node2D whose rotation defines the facing direction.
## @param fov_angle_deg: The field of view angle in degrees (half-angle on each side).
## @param fov_enabled: Whether FOV checking is enabled for this enemy.
func set_fov_parameters(model: Node2D, fov_angle_deg: float, fov_enabled: bool) -> void:
	_enemy_model = model
	_fov_angle = fov_angle_deg
	_fov_enabled = fov_enabled


## Check if a position is within the enemy's field of view (Issue #426).
## @param pos: The position to check.
## @returns: True if position is within FOV, false if outside or behind enemy.
func _is_position_in_fov(pos: Vector2) -> bool:
	# If FOV is disabled or no model reference, assume 360° vision
	if not _fov_enabled or _fov_angle <= 0.0 or _enemy_model == null or _enemy == null:
		return true

	# Check global FOV setting from ExperimentalSettings
	var experimental_settings: Node = _enemy.get_node_or_null("/root/ExperimentalSettings")
	var global_fov_enabled: bool = experimental_settings != null and experimental_settings.has_method("is_fov_enabled") and experimental_settings.is_fov_enabled()
	if not global_fov_enabled:
		return true  # Global FOV disabled - 360 degree vision

	# Get enemy's facing direction from model rotation
	var facing_angle := _enemy_model.global_rotation
	var dir_to_pos := (pos - _enemy.global_position).normalized()

	# Calculate angle between facing direction and direction to position
	var facing_dir := Vector2.from_angle(facing_angle)
	var dot := facing_dir.dot(dir_to_pos)
	var angle_to_pos := rad_to_deg(acos(clampf(dot, -1.0, 1.0)))

	# Check if within FOV cone (half angle on each side)
	return angle_to_pos <= _fov_angle / 2.0


## Check if a position is visible from the enemy (no walls blocking).
## @param pos: The position to check visibility to.
## @returns: True if position is visible, false if blocked by walls.
func _can_see_position(pos: Vector2) -> bool:
	if _raycast == null or _enemy == null:
		return true  # Fallback: assume visible if no raycast available

	var orig := _raycast.target_position
	_raycast.target_position = pos - _enemy.global_position
	_raycast.force_raycast_update()
	var result := not _raycast.is_colliding()
	_raycast.target_position = orig
	return result


## Cooldown timer to prevent state thrashing when at danger zone edge.
## When enemy exits danger zone, they ignore grenades for this duration.
var _exit_cooldown: float = 0.0

## Cooldown duration in seconds after exiting danger zone.
const EXIT_COOLDOWN_DURATION: float = 1.0


## Update grenade danger detection. Call this each physics frame.
## Issue #450: Uses predicted landing position instead of current grenade position.
## Returns true if in danger zone.
func update() -> bool:
	if _enemy == null:
		return false

	# Decrement exit cooldown timer
	if _exit_cooldown > 0.0:
		_exit_cooldown -= get_physics_process_delta_time()
		# During cooldown, maintain "not in danger" state to prevent thrashing
		if _exit_cooldown > 0.0:
			return false

	# Issue #450: Check if we have a locked grenade that's still valid
	if _locked_grenade != null:
		if not is_instance_valid(_locked_grenade):
			# Grenade was destroyed (exploded) - clear lock
			_locked_grenade = null
			_locked_position = Vector2.ZERO
		elif _locked_grenade.has_method("has_exploded") and _locked_grenade.has_exploded():
			# Grenade exploded - clear lock
			_locked_grenade = null
			_locked_position = Vector2.ZERO
		else:
			# Still locked onto a valid grenade - check if we're still in danger from it
			var effect_radius: float = 225.0
			if _locked_grenade.has_method("_get_effect_radius"):
				effect_radius = _locked_grenade._get_effect_radius()
			var danger_radius: float = effect_radius + safety_margin

			# Use locked position for danger check (not current grenade position)
			var distance_to_danger := _enemy.global_position.distance_to(_locked_position)
			if distance_to_danger < danger_radius:
				# Still in danger from locked grenade - stay locked
				in_danger_zone = true
				most_dangerous_grenade = _locked_grenade
				predicted_landing_position = _locked_position
				_grenades_in_range = [_locked_grenade]
				return true
			else:
				# Escaped danger zone - clear lock
				_locked_grenade = null
				_locked_position = Vector2.ZERO

	# Clear previous tracking
	_grenades_in_range.clear()
	most_dangerous_grenade = null
	predicted_landing_position = Vector2.ZERO
	var was_in_danger := in_danger_zone
	in_danger_zone = false

	# Find all active grenades in the scene
	var grenades := get_tree().get_nodes_in_group("grenades")

	# PERFORMANCE FIX: Do NOT do recursive scene tree search - that's O(n) where n is all nodes!
	# If grenades aren't in the group, they aren't active grenades we need to worry about.
	# The grenade_base.gd adds grenades to this group when thrown.

	if grenades.is_empty():
		if was_in_danger:
			exited_danger_zone.emit()
			_exit_cooldown = EXIT_COOLDOWN_DURATION  # Start cooldown to prevent thrashing
		return false

	var closest_danger_distance: float = INF

	for grenade in grenades:
		if not is_instance_valid(grenade):
			continue

		# Skip grenades that haven't been thrown yet (still held by player/enemy)
		# Issue #426: Use is_thrown() instead of is_timer_active() because timer starts
		# when pin is pulled (before throw), but enemies should only react once thrown.
		if grenade.has_method("is_thrown"):
			if not grenade.is_thrown():
				continue
		elif grenade.has_method("is_timer_active"):
			# Fallback for grenades without is_thrown method
			if not grenade.is_timer_active():
				continue

		# Check if grenade has already exploded
		if grenade.has_method("has_exploded"):
			if grenade.has_exploded():
				continue

		# Issue #450: Get predicted landing position instead of current position
		var grenade_danger_pos: Vector2 = grenade.global_position
		if grenade.has_method("get_predicted_landing_position"):
			grenade_danger_pos = grenade.get_predicted_landing_position()

		# Get grenade effect radius
		var effect_radius: float = 225.0  # Default
		if grenade.has_method("_get_effect_radius"):
			effect_radius = grenade._get_effect_radius()

		var danger_radius: float = effect_radius + safety_margin

		# Issue #450: Calculate distance to PREDICTED landing position
		var distance := _enemy.global_position.distance_to(grenade_danger_pos)

		# Check if we're in danger zone of the predicted landing area
		if distance < danger_radius:
			# Issue #426: Check line-of-sight to grenade's CURRENT position
			# (enemies react to grenades they can see, but predict where it will land)
			if not _can_see_position(grenade.global_position):
				continue  # Skip grenades blocked by walls

			# Issue #426: Check field of view - enemies should only react to grenades
			# within their vision cone. They can't see grenades behind them.
			if not _is_position_in_fov(grenade.global_position):
				continue  # Skip grenades outside field of view

			_grenades_in_range.append(grenade)
			in_danger_zone = true

			# Track the most dangerous grenade (closest predicted landing)
			if distance < closest_danger_distance:
				closest_danger_distance = distance
				most_dangerous_grenade = grenade
				predicted_landing_position = grenade_danger_pos

	# Issue #450: Lock onto the most dangerous grenade to prevent jitter
	if in_danger_zone and most_dangerous_grenade != null:
		_locked_grenade = most_dangerous_grenade
		_locked_position = predicted_landing_position

	# Emit signals for state changes
	if in_danger_zone and not was_in_danger:
		entered_danger_zone.emit(most_dangerous_grenade)
	elif not in_danger_zone and was_in_danger:
		exited_danger_zone.emit()
		_exit_cooldown = EXIT_COOLDOWN_DURATION  # Start cooldown to prevent thrashing

	return in_danger_zone


## Find all grenade nodes in the scene tree.
## NOTE: This function is kept for backwards compatibility but should NOT be used.
## PERFORMANCE WARNING: This is O(n) where n is total scene nodes - very expensive!
## Active grenades should be in the "grenades" group instead.
func _find_grenades_in_scene(_node: Node) -> Array:
	# PERFORMANCE FIX: Return empty array - do not recursively search scene tree.
	# Grenades should be in the "grenades" group. If they're not, the grenade
	# system needs to be fixed, not worked around with expensive searches.
	return []


## Calculate the best escape position from grenade danger.
## Issue #450: Uses predicted landing position instead of current grenade position.
## Moves directly away from the predicted landing spot, with fallback to alternative directions.
## @param nav_agent: The NavigationAgent2D to use for pathfinding
func calculate_evasion_target(nav_agent: NavigationAgent2D = null) -> void:
	if most_dangerous_grenade == null or _enemy == null:
		evasion_target = Vector2.ZERO
		return

	# Issue #450: Use predicted landing position (or locked position) instead of current position
	var grenade_pos: Vector2
	if _locked_position != Vector2.ZERO:
		grenade_pos = _locked_position
	elif predicted_landing_position != Vector2.ZERO:
		grenade_pos = predicted_landing_position
	else:
		# Fallback to current position if no prediction available
		grenade_pos = most_dangerous_grenade.global_position

	var effect_radius: float = 225.0
	if most_dangerous_grenade.has_method("_get_effect_radius"):
		effect_radius = most_dangerous_grenade._get_effect_radius()

	var safe_distance: float = effect_radius + safety_margin + 50.0  # Extra margin for safety

	# Calculate direction away from predicted landing position
	var escape_direction := (_enemy.global_position - grenade_pos).normalized()

	# If we're very close to the predicted landing spot, pick any direction
	if escape_direction.length() < 0.1:
		escape_direction = Vector2.RIGHT.rotated(randf() * TAU)

	# Calculate target position at safe distance from predicted landing
	var ideal_target := grenade_pos + escape_direction * safe_distance

	# Try to find a valid navigation position near the ideal target
	if nav_agent != null:
		nav_agent.target_position = ideal_target

		# If navigation can reach it, use it
		if not nav_agent.is_navigation_finished():
			evasion_target = ideal_target
			return

	# Fallback: try perpendicular directions
	var alt_direction1 := escape_direction.rotated(PI / 4)  # 45 degrees
	var alt_direction2 := escape_direction.rotated(-PI / 4)  # -45 degrees

	var alt_target1 := grenade_pos + alt_direction1 * safe_distance
	var alt_target2 := grenade_pos + alt_direction2 * safe_distance

	# Check which alternative is farther from current position
	var dist1 := _enemy.global_position.distance_to(alt_target1)
	var dist2 := _enemy.global_position.distance_to(alt_target2)

	evasion_target = alt_target1 if dist1 < dist2 else alt_target2


## Get the number of grenades in danger range.
func get_grenade_count() -> int:
	return _grenades_in_range.size()


## Check if a specific grenade is in our danger range.
func is_grenade_in_range(grenade: Node) -> bool:
	return grenade in _grenades_in_range


## Reset the component state.
func reset() -> void:
	in_danger_zone = false
	evasion_target = Vector2.ZERO
	most_dangerous_grenade = null
	# Issue #450: Clear predicted landing position and locked grenade
	predicted_landing_position = Vector2.ZERO
	_locked_grenade = null
	_locked_position = Vector2.ZERO
	_grenades_in_range.clear()
	_exit_cooldown = 0.0
	# Issue #426: Clear remembered grenade position
	_remembered_grenade_position = Vector2.ZERO
	_remembered_grenade_time = 0.0


# ============================================================================
# Issue #426: Grenade Sound Detection and Position Memory
# ============================================================================

## Issue #426: Remembered grenade position from sound detection.
## Enemies can hear grenades land nearby and remember their position to flee to safety.
var _remembered_grenade_position: Vector2 = Vector2.ZERO

## Issue #426: Timestamp when grenade position was remembered (for expiration).
var _remembered_grenade_time: float = 0.0

## Issue #426: How long to remember a grenade position (seconds). After this time, the memory expires.
const GRENADE_MEMORY_DURATION: float = 5.0

## Issue #426: Extra buffer distance for guaranteed safe escape (on top of effect_radius + safety_margin).
const SAFE_DISTANCE_BUFFER: float = 100.0


## Issue #426: Get remembered grenade position (if still valid).
## @returns: Remembered position, or Vector2.ZERO if expired/not set.
func get_remembered_grenade_position() -> Vector2:
	if _remembered_grenade_position == Vector2.ZERO:
		return Vector2.ZERO
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _remembered_grenade_time >= GRENADE_MEMORY_DURATION:
		# Memory expired
		_remembered_grenade_position = Vector2.ZERO
		return Vector2.ZERO
	return _remembered_grenade_position


## Issue #426: Store grenade position from heard sound.
## @param position: Position where grenade landed.
func remember_grenade_position(position: Vector2) -> void:
	_remembered_grenade_position = position
	_remembered_grenade_time = Time.get_ticks_msec() / 1000.0


## Issue #426: Clear remembered grenade position.
func clear_remembered_position() -> void:
	_remembered_grenade_position = Vector2.ZERO
	_remembered_grenade_time = 0.0


## Issue #426: Calculate guaranteed safe distance from a grenade position.
## @param grenade_position: Position of the grenade.
## @param grenade_node: Optional grenade node to get effect radius from.
## @returns: Safe distance in pixels.
func get_safe_distance(grenade_node: Node2D = null) -> float:
	var effect_radius: float = 225.0  # Default grenade effect radius
	if grenade_node and grenade_node.has_method("_get_effect_radius"):
		effect_radius = grenade_node._get_effect_radius()
	return effect_radius + safety_margin + SAFE_DISTANCE_BUFFER


## Issue #426, #450: Check if enemy is at guaranteed safe distance from grenade danger.
## Issue #450: Uses predicted landing position / locked position instead of current grenade position.
## @returns: True if at safe distance, false otherwise.
func is_at_safe_distance() -> bool:
	if _enemy == null:
		return true

	# Issue #450: Priority order for danger position:
	# 1. Locked position (committed escape route)
	# 2. Predicted landing position (moving grenade)
	# 3. Remembered position (heard grenade land)
	# 4. Current grenade position (fallback)
	var grenade_pos: Vector2 = Vector2.ZERO

	if _locked_position != Vector2.ZERO:
		grenade_pos = _locked_position
	elif predicted_landing_position != Vector2.ZERO:
		grenade_pos = predicted_landing_position
	else:
		grenade_pos = get_remembered_grenade_position()
		if grenade_pos == Vector2.ZERO:
			# No remembered position - check most dangerous grenade
			if most_dangerous_grenade and is_instance_valid(most_dangerous_grenade):
				# Issue #450: Try to get predicted position from grenade
				if most_dangerous_grenade.has_method("get_predicted_landing_position"):
					grenade_pos = most_dangerous_grenade.get_predicted_landing_position()
				else:
					grenade_pos = most_dangerous_grenade.global_position
			else:
				return true  # No grenade to flee from

	var distance := _enemy.global_position.distance_to(grenade_pos)
	var safe_dist := get_safe_distance(most_dangerous_grenade)
	return distance >= safe_dist


## Issue #426: Trigger evasion from heard sound (bypasses visual detection).
## @param grenade_position: Position where grenade was heard landing.
## @param grenade_node: Optional grenade node.
## @returns: True if evasion was triggered, false if outside danger zone.
func trigger_evasion_from_sound(grenade_position: Vector2, grenade_node: Node2D = null) -> bool:
	if _enemy == null:
		return false

	# Store the position for memory-based evasion
	remember_grenade_position(grenade_position)

	# Calculate if we're within the grenade's danger zone
	var effect_radius: float = 225.0
	if grenade_node and grenade_node.has_method("_get_effect_radius"):
		effect_radius = grenade_node._get_effect_radius()
	var danger_radius: float = effect_radius + safety_margin
	var distance_to_grenade := _enemy.global_position.distance_to(grenade_position)

	# Only trigger evasion if we're within the danger zone
	if distance_to_grenade >= danger_radius:
		return false

	# Calculate escape direction (away from grenade)
	var escape_direction := (_enemy.global_position - grenade_position).normalized()
	if escape_direction.length() < 0.1:
		escape_direction = Vector2.RIGHT.rotated(randf() * TAU)

	# Calculate safe distance for evasion target
	var safe_distance := get_safe_distance(grenade_node)

	# Set evasion target at safe distance from grenade
	evasion_target = grenade_position + escape_direction * safe_distance
	in_danger_zone = true

	return true
