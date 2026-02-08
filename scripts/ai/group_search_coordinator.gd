class_name GroupSearchCoordinator
extends RefCounted
## Coordinates group search behavior for multiple enemies (Issue #650).
##
## When multiple enemies enter SEARCHING state near the same center,
## this coordinator divides the search area into angular sectors so
## each enemy covers a unique zone without duplication.
##
## Uses angle-sector division: for N enemies searching around a center,
## the 360-degree area is split into N equal sectors. Each enemy's
## spiral search is constrained to their assigned sector.
##
## Also provides realistic scan target generation so enemies look
## around naturally rather than mechanically rotating.
##
## Usage:
##   # Called from enemy when entering SEARCHING state
##   var coordinator = GroupSearchCoordinator.get_or_create(search_center)
##   var sector = coordinator.register_enemy(enemy_instance)
##   var waypoints = coordinator.generate_sector_waypoints(sector, radius)
##
##   # Called each scan stop for realistic look angles
##   var scan_angles = coordinator.generate_scan_targets(sector, enemy_rotation)

## Active coordinators keyed by snapped center position.
static var _active_coordinators: Dictionary = {}

## Snap size for grouping nearby search centers (px).
const CENTER_SNAP_SIZE: float = 150.0

## Maximum distance between search centers to consider them the same group.
const GROUP_DISTANCE_THRESHOLD: float = 200.0

## Minimum number of enemies to activate coordination (1 enemy = no coordination needed).
const MIN_ENEMIES_FOR_COORDINATION: int = 2

## Waypoint spacing within sector (px).
const SECTOR_WAYPOINT_SPACING: float = 75.0

## Number of scan targets to generate per waypoint stop.
const SCAN_TARGETS_PER_STOP: int = 3

## Chance (0-1) that enemy looks away from expected direction during scan.
const LOOK_AWAY_CHANCE: float = 0.25

## Maximum angle offset for "look away" behavior (radians, ~60 degrees).
const LOOK_AWAY_MAX_ANGLE: float = PI / 3.0

## Scan pause variation range (seconds) - adds realism.
const SCAN_PAUSE_MIN: float = 0.3
const SCAN_PAUSE_MAX: float = 0.8

## Enable debug logging.
var debug_logging: bool = false

## Center position of the coordinated search.
var center: Vector2 = Vector2.ZERO

## Registered enemies and their assigned sector indices.
## Key: enemy instance ID, Value: sector index (0-based).
var _enemy_sectors: Dictionary = {}

## Ordered list of enemy instance IDs for sector assignment.
var _enemy_order: Array[int] = []

## Shared visited zones across all coordinated enemies.
var _shared_visited_zones: Dictionary = {}

## Zone snap size for visited tracking.
const ZONE_SNAP_SIZE: float = 50.0


func _init(center_pos: Vector2 = Vector2.ZERO) -> void:
	center = center_pos


## Get or create a coordinator for a search center position.
## Groups nearby centers within GROUP_DISTANCE_THRESHOLD.
static func get_or_create(search_center: Vector2) -> GroupSearchCoordinator:
	# Issue #650: Clean up stale coordinators (enemies from previous scene loads)
	var stale_keys: Array = []
	for key in _active_coordinators.keys():
		var coord: GroupSearchCoordinator = _active_coordinators[key]
		if coord == null:
			stale_keys.append(key)
			continue
		# Check if any registered enemies are still valid
		var has_valid_enemy := false
		for enemy_id in coord._enemy_order:
			if instance_from_id(enemy_id) != null:
				has_valid_enemy = true
				break
		if not has_valid_enemy and not coord._enemy_order.is_empty():
			stale_keys.append(key)
			continue
		if coord.center.distance_to(search_center) < GROUP_DISTANCE_THRESHOLD:
			return coord
	for key in stale_keys:
		_active_coordinators.erase(key)
	# Create new coordinator
	var coordinator := GroupSearchCoordinator.new(search_center)
	var key := _snap_center(search_center)
	_active_coordinators[key] = coordinator
	return coordinator


## Register an enemy for coordinated search. Returns sector index.
func register_enemy(enemy: Node) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return 0
	var id := enemy.get_instance_id()
	if _enemy_sectors.has(id):
		return _enemy_sectors[id]
	var sector_index := _enemy_order.size()
	_enemy_order.append(id)
	_enemy_sectors[id] = sector_index
	# Reassign all sectors when a new enemy joins
	_reassign_sectors()
	_log("Registered enemy %d, assigned sector %d/%d" % [id, sector_index, _enemy_order.size()])
	return sector_index


## Unregister an enemy when they leave SEARCHING state.
func unregister_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	var id := enemy.get_instance_id()
	if not _enemy_sectors.has(id):
		return
	_enemy_sectors.erase(id)
	_enemy_order.erase(id)
	_reassign_sectors()
	_log("Unregistered enemy %d, %d enemies remain" % [id, _enemy_order.size()])
	# Clean up coordinator if no enemies remain
	if _enemy_order.is_empty():
		_remove_self()


## Get the number of coordinating enemies.
func get_enemy_count() -> int:
	return _enemy_order.size()


## Check if coordination is active (enough enemies).
func is_coordinated() -> bool:
	return _enemy_order.size() >= MIN_ENEMIES_FOR_COORDINATION


## Get the angular sector for an enemy (start_angle, end_angle in radians).
func get_sector_angles(enemy: Node) -> Dictionary:
	var id := enemy.get_instance_id()
	if not _enemy_sectors.has(id):
		return {"start": 0.0, "end": TAU}
	var sector_index: int = _enemy_sectors[id]
	var total := _enemy_order.size()
	if total <= 0:
		return {"start": 0.0, "end": TAU}
	var sector_size := TAU / float(total)
	return {
		"start": sector_index * sector_size,
		"end": (sector_index + 1) * sector_size
	}


## Generate search waypoints constrained to enemy's assigned sector.
## Returns waypoints in an expanding pattern within the angular sector.
func generate_sector_waypoints(enemy: Node, radius: float, nav_check_callback: Callable = Callable()) -> Array[Vector2]:
	var waypoints: Array[Vector2] = []
	var sector := get_sector_angles(enemy)
	var start_angle: float = sector["start"]
	var end_angle: float = sector["end"]
	var sector_mid := (start_angle + end_angle) / 2.0

	# Generate waypoints in expanding arcs within the sector
	var current_radius := SECTOR_WAYPOINT_SPACING
	while current_radius <= radius and waypoints.size() < 20:
		# Number of points per ring scales with radius
		var points_per_ring := maxi(2, int(current_radius * (end_angle - start_angle) / SECTOR_WAYPOINT_SPACING))
		points_per_ring = mini(points_per_ring, 6)  # Cap per ring
		var angle_step := (end_angle - start_angle) / float(points_per_ring)
		for i in range(points_per_ring):
			if waypoints.size() >= 20:
				break
			var angle := start_angle + angle_step * (float(i) + 0.5)
			var pos := center + Vector2(cos(angle), sin(angle)) * current_radius
			var zone_key := _get_zone_key(pos)
			if _shared_visited_zones.has(zone_key):
				continue
			if nav_check_callback.is_valid() and not nav_check_callback.call(pos):
				continue
			waypoints.append(pos)
		current_radius += SECTOR_WAYPOINT_SPACING

	# If sector has no navigable waypoints, include center
	if waypoints.is_empty() and not _shared_visited_zones.has(_get_zone_key(center)):
		waypoints.append(center)
	_log("Generated %d sector waypoints (sector=%d, radius=%.0f)" % [waypoints.size(), _enemy_sectors.get(enemy.get_instance_id(), -1), radius])
	return waypoints


## Mark a zone as visited (shared across all coordinated enemies).
func mark_zone_visited(pos: Vector2) -> void:
	var key := _get_zone_key(pos)
	if not _shared_visited_zones.has(key):
		_shared_visited_zones[key] = true


## Check if a zone has been visited by any coordinated enemy.
func is_zone_visited(pos: Vector2) -> bool:
	return _shared_visited_zones.has(_get_zone_key(pos))


## Generate realistic scan targets for a waypoint stop (Issue #650).
## Returns an array of {angle: float, pause: float} dictionaries.
## Enemies will look at these angles with variable pauses, making
## the search appear more natural and realistic.
func generate_scan_targets(enemy: Node, current_rotation: float) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var sector := get_sector_angles(enemy)
	var sector_mid := (sector["start"] + sector["end"]) / 2.0

	for i in range(SCAN_TARGETS_PER_STOP):
		var angle: float
		var pause: float
		if randf() < LOOK_AWAY_CHANCE:
			# Look away from expected direction (adds realism)
			var away_offset := randf_range(PI / 2.0, PI + LOOK_AWAY_MAX_ANGLE)
			if randf() > 0.5:
				away_offset = -away_offset
			angle = current_rotation + away_offset
			pause = randf_range(SCAN_PAUSE_MIN, SCAN_PAUSE_MIN + 0.2)  # Shorter pause for wrong dir
		else:
			# Look toward search sector with some randomness
			var base_angle: float
			if i == 0:
				base_angle = sector_mid  # First look: toward sector center
			else:
				base_angle = randf_range(sector["start"], sector["end"])
			angle = base_angle + randf_range(-0.4, 0.4)  # ~23 degree variation
			pause = randf_range(SCAN_PAUSE_MIN, SCAN_PAUSE_MAX)

		targets.append({"angle": wrapf(angle, -PI, PI), "pause": pause})

	return targets


## Generate realistic scan targets without coordination (single enemy).
## Used when there's no group coordination active.
static func generate_solo_scan_targets(current_rotation: float, search_direction: Vector2) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var base_angle := search_direction.angle() if search_direction.length_squared() > 0.01 else current_rotation
	for i in range(3):
		var angle: float
		var pause: float
		if randf() < LOOK_AWAY_CHANCE:
			# Sometimes look the wrong way
			var away := randf_range(PI / 2.0, PI + LOOK_AWAY_MAX_ANGLE)
			if randf() > 0.5:
				away = -away
			angle = current_rotation + away
			pause = randf_range(SCAN_PAUSE_MIN, SCAN_PAUSE_MIN + 0.2)
		else:
			# Look toward search area with variation
			angle = base_angle + randf_range(-PI / 3.0, PI / 3.0)
			pause = randf_range(SCAN_PAUSE_MIN, SCAN_PAUSE_MAX)
		targets.append({"angle": wrapf(angle, -PI, PI), "pause": pause})
	return targets


## Clear all shared visited zones.
func clear_visited_zones() -> void:
	_shared_visited_zones.clear()


## Remove all coordinators (for level cleanup).
static func clear_all() -> void:
	_active_coordinators.clear()


# ============================================================================
# Private Methods
# ============================================================================


## Reassign sector indices after registration/unregistration changes.
func _reassign_sectors() -> void:
	_enemy_sectors.clear()
	for i in range(_enemy_order.size()):
		_enemy_sectors[_enemy_order[i]] = i


## Remove this coordinator from the active set.
func _remove_self() -> void:
	for key in _active_coordinators.keys():
		if _active_coordinators[key] == self:
			_active_coordinators.erase(key)
			break


## Snap center position for dictionary key.
static func _snap_center(pos: Vector2) -> String:
	return "%d,%d" % [int(pos.x / CENTER_SNAP_SIZE) * int(CENTER_SNAP_SIZE), int(pos.y / CENTER_SNAP_SIZE) * int(CENTER_SNAP_SIZE)]


## Get zone key for visited tracking.
func _get_zone_key(pos: Vector2) -> String:
	return "%d,%d" % [int(pos.x / ZONE_SNAP_SIZE) * int(ZONE_SNAP_SIZE), int(pos.y / ZONE_SNAP_SIZE) * int(ZONE_SNAP_SIZE)]


## Debug log helper.
func _log(msg: String) -> void:
	if debug_logging:
		print("[GroupSearch] %s" % msg)
