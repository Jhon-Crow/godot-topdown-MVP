extends Node
## Autoload singleton for coordinating tactical grenade throws between enemies.
##
## Issue #382: Implements tactical grenade coordination including:
## - Grenade throw announcements to allies
## - Ally evacuation from danger zones
## - Post-explosion assault coordination
##
## References:
## - Killzone AI: Safety checks for friendly units before throwing
## - F.E.A.R. GOAP: Squad coordination with grenade as tactical action
## - Days Gone: Frontline concept for spatial coordination

## Emitted when an enemy announces they're about to throw a grenade.
## Allies in the danger zone should evacuate.
signal grenade_announced(thrower: Node, target_position: Vector2, blast_radius: float)

## Emitted when a grenade explodes.
## Triggers coordinated assault from waiting enemies.
signal grenade_exploded(position: Vector2, thrower: Node)

## Emitted when coordinated assault should begin.
## All waiting allies rush through the throw passage.
signal assault_begin(passage_direction: Vector2, thrower: Node)

## Tactical grenade throw inaccuracy (max 5 degrees per issue #382).
const TACTICAL_THROW_INACCURACY_DEGREES: float = 5.0
const TACTICAL_THROW_INACCURACY_RADIANS: float = deg_to_rad(5.0)  # ~0.0873 radians

## Safety margin for ally evacuation (added to blast radius).
const EVACUATION_SAFETY_MARGIN: float = 75.0

## Time to wait after warning before allies are considered evacuated.
const EVACUATION_WAIT_TIME: float = 0.8

## Active grenade throw warnings.
## Each warning contains: thrower, target, blast_radius, time, passage_direction
var _active_warnings: Array[Dictionary] = []

## Enemies waiting for the coordinated assault.
var _assault_queue: Array[Node] = []

## The thrower who initiated the current tactical throw.
var _current_thrower: Node = null

## Direction of the assault (from thrower to target).
var _assault_direction: Vector2 = Vector2.ZERO

## Logger reference.
var _logger: Node = null

## Debug logging enabled.
var debug_logging: bool = false


func _ready() -> void:
	_logger = get_node_or_null("/root/FileLogger")
	_log("TacticalGrenadeCoordinator initialized")


## Announce an upcoming tactical grenade throw.
## Called by the thrower before throwing to warn allies.
##
## @param thrower: The enemy throwing the grenade.
## @param target: The intended target position.
## @param blast_radius: The grenade's blast radius.
## @return: True if allies in danger zone were warned.
func announce_tactical_throw(thrower: Node, target: Vector2, blast_radius: float) -> bool:
	if not is_instance_valid(thrower):
		return false

	var warning := {
		"thrower": thrower,
		"target": target,
		"blast_radius": blast_radius,
		"time": Time.get_ticks_msec() / 1000.0,
		"passage_direction": (target - thrower.global_position).normalized()
	}

	_active_warnings.append(warning)
	_current_thrower = thrower
	_assault_direction = warning.passage_direction

	_log("Tactical throw announced: thrower=%s, target=%s, blast_radius=%.0f" % [
		thrower.name, target, blast_radius
	])

	# Emit signal for all listeners (enemies will check if they're in danger zone)
	grenade_announced.emit(thrower, target, blast_radius)

	# Check if any allies are in the danger zone
	var allies_warned := _count_allies_in_danger_zone(thrower, target, blast_radius)
	_log("  %d allies warned in danger zone" % allies_warned)

	return allies_warned > 0


## Check if an enemy position is in any active danger zone.
##
## @param enemy_position: The position to check.
## @param exclude_thrower: Optional thrower to exclude from check.
## @return: True if position is in a danger zone.
func is_in_danger_zone(enemy_position: Vector2, exclude_thrower: Node = null) -> bool:
	for warning in _active_warnings:
		if warning.thrower == exclude_thrower:
			continue

		var distance := enemy_position.distance_to(warning.target)
		var danger_radius := warning.blast_radius + EVACUATION_SAFETY_MARGIN

		if distance < danger_radius:
			return true

	return false


## Get the nearest danger zone for evacuation calculation.
##
## @param enemy_position: The position to check from.
## @param exclude_thrower: Optional thrower to exclude.
## @return: Dictionary with warning info, or empty if none.
func get_nearest_danger_zone(enemy_position: Vector2, exclude_thrower: Node = null) -> Dictionary:
	var nearest := {}
	var min_dist := INF

	for warning in _active_warnings:
		if warning.thrower == exclude_thrower:
			continue

		var dist := enemy_position.distance_to(warning.target)
		if dist < min_dist:
			min_dist = dist
			nearest = warning

	return nearest


## Calculate the best evacuation direction for an enemy.
## Moves perpendicular to throw trajectory or directly away from blast.
##
## @param enemy: The enemy to evacuate.
## @param enemy_position: The enemy's current position.
## @return: Normalized direction vector, or Vector2.ZERO if not in danger.
func calculate_evacuation_direction(enemy: Node, enemy_position: Vector2) -> Vector2:
	var danger := get_nearest_danger_zone(enemy_position, enemy)
	if danger.is_empty():
		return Vector2.ZERO

	var target: Vector2 = danger.target
	var thrower_pos: Vector2 = danger.thrower.global_position if is_instance_valid(danger.thrower) else enemy_position

	# Primary direction: away from blast center
	var away_from_blast := (enemy_position - target).normalized()

	# Check if enemy is on the throw trajectory
	var throw_dir: Vector2 = danger.passage_direction
	var to_enemy := (enemy_position - thrower_pos)
	var projection := to_enemy.dot(throw_dir)

	if projection > 0:
		# Enemy is ahead of thrower on the throw path
		# Calculate perpendicular escape direction
		var perp_left := throw_dir.rotated(PI / 2)
		var perp_right := throw_dir.rotated(-PI / 2)

		# Choose direction that's more away from blast center
		var left_test := enemy_position + perp_left * 50.0
		var right_test := enemy_position + perp_right * 50.0

		if left_test.distance_to(target) > right_test.distance_to(target):
			return perp_left
		else:
			return perp_right

	# Not on trajectory - just move away from blast
	return away_from_blast


## Calculate safe evacuation position for an enemy.
##
## @param enemy_position: Current enemy position.
## @param evacuation_direction: Direction to evacuate.
## @param blast_radius: The grenade's blast radius.
## @return: Target position outside the danger zone.
func calculate_evacuation_position(enemy_position: Vector2, evacuation_direction: Vector2, blast_radius: float) -> Vector2:
	var safe_distance := blast_radius + EVACUATION_SAFETY_MARGIN + 50.0
	return enemy_position + evacuation_direction * safe_distance


## Register an enemy as waiting for the coordinated assault.
##
## @param enemy: The enemy to register.
func register_for_assault(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return

	if enemy not in _assault_queue:
		_assault_queue.append(enemy)
		_log("Enemy registered for assault: %s (queue size: %d)" % [enemy.name, _assault_queue.size()])


## Unregister an enemy from the assault queue.
##
## @param enemy: The enemy to remove.
func unregister_from_assault(enemy: Node) -> void:
	var idx := _assault_queue.find(enemy)
	if idx >= 0:
		_assault_queue.remove_at(idx)
		_log("Enemy unregistered from assault: %s" % enemy.name)


## Called when a grenade explodes to trigger coordinated assault.
##
## @param position: Explosion position.
## @param thrower: The enemy who threw the grenade (optional).
func on_grenade_exploded(position: Vector2, thrower: Node = null) -> void:
	_log("Grenade exploded at %s, thrower=%s" % [position, thrower.name if thrower else "unknown"])

	# Remove related warning(s)
	for i in range(_active_warnings.size() - 1, -1, -1):
		var warning: Dictionary = _active_warnings[i]
		if warning.target.distance_to(position) < 100.0:
			_active_warnings.remove_at(i)

	# Emit explosion signal
	grenade_exploded.emit(position, thrower)

	# Trigger coordinated assault if we have enemies waiting
	if _assault_queue.size() > 0:
		_log("Triggering coordinated assault with %d enemies" % _assault_queue.size())
		assault_begin.emit(_assault_direction, _current_thrower)

		# Clear the queue - enemies will connect to this signal
		_assault_queue.clear()

	# Reset current thrower
	_current_thrower = null


## Get the number of active warnings.
func get_warning_count() -> int:
	return _active_warnings.size()


## Check if there's an active tactical throw in progress.
func is_tactical_throw_active() -> bool:
	return _active_warnings.size() > 0


## Get the current assault direction (for post-throw behavior).
func get_assault_direction() -> Vector2:
	return _assault_direction


## Get the current thrower.
func get_current_thrower() -> Node:
	return _current_thrower


## Clear all warnings and reset state (e.g., on level restart).
func clear() -> void:
	_active_warnings.clear()
	_assault_queue.clear()
	_current_thrower = null
	_assault_direction = Vector2.ZERO
	_log("TacticalGrenadeCoordinator cleared")


## Count allies in the danger zone (excluding thrower).
func _count_allies_in_danger_zone(thrower: Node, target: Vector2, blast_radius: float) -> int:
	var count := 0
	var danger_radius := blast_radius + EVACUATION_SAFETY_MARGIN

	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy == thrower:
			continue
		if not enemy is Node2D:
			continue

		var distance: float = enemy.global_position.distance_to(target)
		if distance < danger_radius:
			count += 1

	return count


## Log a message if debug logging is enabled.
func _log(msg: String) -> void:
	if debug_logging:
		print("[TacticalGrenadeCoordinator] %s" % msg)
	if _logger and _logger.has_method("log_info"):
		_logger.log_info("[TacticalGrenadeCoordinator] %s" % msg)
