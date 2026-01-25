## SearchCoordinator - Coordinates search routes for multiple enemies (Issue #369).
## This autoload manages coordinated search operations so enemies don't overlap
## or revisit the same areas. Uses Voronoi-like partitioning to divide the search
## area among participating enemies.
##
## Reference: https://en.wikipedia.org/wiki/Voronoi_diagram
## Based on research into multi-agent coordinated search algorithms.
extends Node

## Signal emitted when a new search iteration begins.
signal search_iteration_started(iteration_id: int, center: Vector2, participating_enemies: Array)

## Signal emitted when search routes are assigned to enemies.
signal search_routes_assigned(iteration_id: int, routes: Dictionary)

## Configuration constants.
const SEARCH_GRID_SIZE: float = 50.0  ## Grid cell size for waypoint generation.
const SEARCH_WAYPOINT_SPACING: float = 100.0  ## Spacing between waypoints.
const MAX_WAYPOINTS_PER_ENEMY: int = 15  ## Max waypoints per enemy per iteration.
const SEARCH_EXPANSION_RATE: float = 100.0  ## How fast the search radius expands.
const SEARCH_INITIAL_RADIUS: float = 100.0  ## Initial search radius.
const SEARCH_MAX_RADIUS: float = 500.0  ## Maximum search radius.

## Current search state.
var _current_iteration_id: int = 0
var _search_active: bool = false
var _search_center: Vector2 = Vector2.ZERO
var _search_radius: float = SEARCH_INITIAL_RADIUS
var _participating_enemies: Array = []  ## Array of enemy node references.
var _enemy_routes: Dictionary = {}  ## enemy_id -> Array[Vector2] of waypoints
var _enemy_waypoint_indices: Dictionary = {}  ## enemy_id -> current waypoint index
var _globally_visited_zones: Dictionary = {}  ## zone_key -> true (shared visited zones)

## Debug logging.
var debug_logging: bool = true

func _ready() -> void:
	if debug_logging:
		print("[SearchCoordinator] Initialized")

## Start a new coordinated search from a given center position.
## Called when enemies lose sight of the player and begin searching.
## Returns the iteration ID for tracking.
func start_coordinated_search(center: Vector2, requesting_enemy: Node) -> int:
	# If search is already active and center is close, join existing search
	if _search_active and center.distance_to(_search_center) < SEARCH_MAX_RADIUS:
		_add_enemy_to_search(requesting_enemy)
		return _current_iteration_id

	# Start new search iteration
	_current_iteration_id += 1
	_search_active = true
	_search_center = center
	_search_radius = SEARCH_INITIAL_RADIUS
	_participating_enemies.clear()
	_enemy_routes.clear()
	_enemy_waypoint_indices.clear()
	_globally_visited_zones.clear()

	# Add the requesting enemy
	_add_enemy_to_search(requesting_enemy)

	# Find other enemies that should join the search
	_find_nearby_searching_enemies()

	# Generate and distribute routes
	_generate_coordinated_routes()

	_log("Started search iteration %d at %s with %d enemies" % [
		_current_iteration_id, center, _participating_enemies.size()
	])

	search_iteration_started.emit(_current_iteration_id, center, _participating_enemies.duplicate())

	return _current_iteration_id

## Add an enemy to the current search operation.
func _add_enemy_to_search(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return

	var enemy_id := enemy.get_instance_id()
	if enemy_id in _enemy_routes:
		return  # Already participating

	if enemy not in _participating_enemies:
		_participating_enemies.append(enemy)
		_enemy_routes[enemy_id] = []
		_enemy_waypoint_indices[enemy_id] = 0
		_log("Enemy %s joined search iteration %d" % [enemy.name, _current_iteration_id])

## Find nearby enemies that should join the coordinated search.
func _find_nearby_searching_enemies() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		# Check if enemy has the expected properties (is an actual enemy AI)
		if not enemy.has_method("get_instance_id"):
			continue
		# Check if enemy is in SEARCHING state or can be recruited
		if enemy.has_method("is_searching") and enemy.is_searching():
			if enemy.global_position.distance_to(_search_center) < SEARCH_MAX_RADIUS * 2:
				_add_enemy_to_search(enemy)
		# Also check for enemies that just lost sight of player
		elif enemy.has_method("should_join_search") and enemy.should_join_search():
			if enemy.global_position.distance_to(_search_center) < SEARCH_MAX_RADIUS * 2:
				_add_enemy_to_search(enemy)

## Generate coordinated search routes using Voronoi-like partitioning.
## Each enemy gets a unique sector of the search area to minimize overlap.
func _generate_coordinated_routes() -> void:
	if _participating_enemies.is_empty():
		return

	var enemy_count := _participating_enemies.size()

	# Calculate sector angles for each enemy (Voronoi-like partitioning)
	var sector_angle := TAU / float(enemy_count)

	# Get navigation map for checking waypoint validity
	var nav_map := get_tree().root.get_world_2d().navigation_map if get_tree().root else RID()

	for i in range(enemy_count):
		var enemy: Node = _participating_enemies[i]
		if enemy == null or not is_instance_valid(enemy):
			continue

		var enemy_id := enemy.get_instance_id()
		var enemy_pos: Vector2 = enemy.global_position

		# Calculate this enemy's sector
		var sector_start: float = i * sector_angle
		var sector_end: float = (i + 1) * sector_angle

		# Generate waypoints in this sector
		var waypoints: Array[Vector2] = _generate_sector_waypoints(
			enemy_pos, _search_center, _search_radius,
			sector_start, sector_end, nav_map
		)

		_enemy_routes[enemy_id] = waypoints
		_enemy_waypoint_indices[enemy_id] = 0

		_log("Enemy %s assigned %d waypoints in sector %.1f-%.1f deg" % [
			enemy.name, waypoints.size(),
			rad_to_deg(sector_start), rad_to_deg(sector_end)
		])

	search_routes_assigned.emit(_current_iteration_id, _enemy_routes.duplicate())

## Generate waypoints within a specific sector.
## Uses a spiral pattern from enemy position toward sector center, then outward.
func _generate_sector_waypoints(
	enemy_pos: Vector2, search_center: Vector2, radius: float,
	sector_start: float, sector_end: float, nav_map: RID
) -> Array[Vector2]:
	var waypoints: Array[Vector2] = []

	# First waypoint: move toward center along sector midpoint
	var sector_mid: float = (sector_start + sector_end) / 2.0
	var to_center: Vector2 = (search_center - enemy_pos)
	var to_center_dist: float = to_center.length()

	# If we're outside the search area, first waypoint is toward the center
	if to_center_dist > radius * 0.5:
		var entry_point: Vector2 = search_center + Vector2.from_angle(sector_mid) * radius * 0.3
		if _is_waypoint_valid(entry_point, nav_map):
			waypoints.append(entry_point)

	# Generate spiral waypoints within the sector
	var rings: int = int(radius / SEARCH_WAYPOINT_SPACING) + 1
	for ring in range(1, rings + 1):
		var ring_radius: float = ring * SEARCH_WAYPOINT_SPACING
		if ring_radius > radius:
			break

		# Number of points in this ring for this sector
		var arc_length: float = ring_radius * (sector_end - sector_start)
		var points_in_arc: int = maxi(1, int(arc_length / SEARCH_WAYPOINT_SPACING))

		for j in range(points_in_arc):
			var angle: float = sector_start + (sector_end - sector_start) * (float(j) + 0.5) / float(points_in_arc)
			var point: Vector2 = search_center + Vector2.from_angle(angle) * ring_radius

			# Check if this zone was already visited
			var zone_key: String = _get_zone_key(point)
			if zone_key in _globally_visited_zones:
				continue

			if _is_waypoint_valid(point, nav_map):
				waypoints.append(point)
				if waypoints.size() >= MAX_WAYPOINTS_PER_ENEMY:
					break

		if waypoints.size() >= MAX_WAYPOINTS_PER_ENEMY:
			break

	# Sort waypoints by distance from enemy for efficient traversal
	waypoints.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return enemy_pos.distance_to(a) < enemy_pos.distance_to(b)
	)

	return waypoints

## Check if a waypoint position is valid (navigable).
func _is_waypoint_valid(pos: Vector2, nav_map: RID) -> bool:
	if not nav_map.is_valid():
		return true  # Can't verify, assume valid

	var closest := NavigationServer2D.map_get_closest_point(nav_map, pos)
	return pos.distance_to(closest) < 50.0

## Get zone key for tracking visited areas (grid-based).
func _get_zone_key(pos: Vector2) -> String:
	var x := int(pos.x / SEARCH_GRID_SIZE) * int(SEARCH_GRID_SIZE)
	var y := int(pos.y / SEARCH_GRID_SIZE) * int(SEARCH_GRID_SIZE)
	return "%d,%d" % [x, y]

## Mark a zone as globally visited (by any enemy).
func mark_zone_visited(pos: Vector2) -> void:
	var key := _get_zone_key(pos)
	if key not in _globally_visited_zones:
		_globally_visited_zones[key] = true
		_log("Zone %s marked as visited (total: %d)" % [key, _globally_visited_zones.size()])

## Check if a zone has been visited by any enemy.
func is_zone_visited(pos: Vector2) -> bool:
	return _get_zone_key(pos) in _globally_visited_zones

## Get the next waypoint for an enemy.
## Returns Vector2.ZERO if no more waypoints or enemy not participating.
func get_next_waypoint(enemy: Node) -> Vector2:
	if enemy == null or not is_instance_valid(enemy):
		return Vector2.ZERO

	var enemy_id := enemy.get_instance_id()
	if enemy_id not in _enemy_routes:
		return Vector2.ZERO

	var waypoints: Array = _enemy_routes[enemy_id]
	var index: int = _enemy_waypoint_indices.get(enemy_id, 0)

	if index >= waypoints.size():
		return Vector2.ZERO

	return waypoints[index]

## Advance to the next waypoint for an enemy.
## Returns true if there are more waypoints, false if search iteration complete.
func advance_waypoint(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false

	var enemy_id := enemy.get_instance_id()
	if enemy_id not in _enemy_routes:
		return false

	# Mark current waypoint's zone as visited
	var current_wp := get_next_waypoint(enemy)
	if current_wp != Vector2.ZERO:
		mark_zone_visited(current_wp)

	# Advance index
	var new_index: int = _enemy_waypoint_indices.get(enemy_id, 0) + 1
	_enemy_waypoint_indices[enemy_id] = new_index

	var waypoints: Array = _enemy_routes[enemy_id]
	return new_index < waypoints.size()

## Check if an enemy has completed their assigned route.
func is_route_complete(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return true

	var enemy_id := enemy.get_instance_id()
	if enemy_id not in _enemy_routes:
		return true

	var waypoints: Array = _enemy_routes[enemy_id]
	var index: int = _enemy_waypoint_indices.get(enemy_id, 0)

	return index >= waypoints.size()

## Expand the search radius and regenerate routes for the next iteration.
## Called when all enemies have completed their current routes.
func expand_search() -> bool:
	if _search_radius >= SEARCH_MAX_RADIUS:
		_log("Search reached max radius %.0f, cannot expand further" % SEARCH_MAX_RADIUS)
		return false

	_search_radius = minf(_search_radius + SEARCH_EXPANSION_RATE, SEARCH_MAX_RADIUS)

	# Regenerate routes with expanded radius
	_generate_coordinated_routes()

	_log("Search expanded to radius %.0f" % _search_radius)
	return true

## End the current coordinated search.
func end_search() -> void:
	_search_active = false
	_participating_enemies.clear()
	_enemy_routes.clear()
	_enemy_waypoint_indices.clear()
	# Keep globally visited zones for potential future searches

	_log("Search iteration %d ended" % _current_iteration_id)

## Remove an enemy from the search (e.g., if they spotted the player).
func remove_enemy_from_search(enemy: Node) -> void:
	if enemy == null:
		return

	var enemy_id := enemy.get_instance_id()
	_enemy_routes.erase(enemy_id)
	_enemy_waypoint_indices.erase(enemy_id)

	var idx := _participating_enemies.find(enemy)
	if idx >= 0:
		_participating_enemies.remove_at(idx)
		_log("Enemy %s removed from search (remaining: %d)" % [
			enemy.name if is_instance_valid(enemy) else "unknown",
			_participating_enemies.size()
		])

## Check if coordinated search is currently active.
func is_search_active() -> bool:
	return _search_active

## Get current search center.
func get_search_center() -> Vector2:
	return _search_center

## Get current search radius.
func get_search_radius() -> float:
	return _search_radius

## Get the current iteration ID.
func get_iteration_id() -> int:
	return _current_iteration_id

## Get number of participating enemies.
func get_enemy_count() -> int:
	return _participating_enemies.size()

## Debug logging helper.
func _log(message: String) -> void:
	if debug_logging:
		print("[SearchCoordinator] %s" % message)

	# Also log to FileLogger if available
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_action"):
		file_logger.log_action("SearchCoordinator", "COORD", message)
