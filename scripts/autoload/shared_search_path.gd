extends Node
## SharedSearchPath - Centralized search path manager for all searching enemies (Issue #1458).
##
## Instead of each enemy generating its own spiral waypoints and computing individual
## NavigationServer2D paths, this autoload generates ONE shared set of waypoints from a
## center point. Enemies claim the nearest unclaimed waypoint, walk to it, then claim the next.
##
## Performance impact: reduces nav queries from 20/frame (one per enemy) to ~1-2/frame
## (only the enemy whose stagger slot fires), and eliminates redundant waypoint generation
## and navigability checks across all enemies.

## Zone snap size for visited-zone tracking (matches enemy.gd SEARCH_ZONE_SNAP_SIZE).
const ZONE_SNAP: float = 50.0
## Spacing between spiral waypoints.
const WAYPOINT_SPACING: float = 75.0
## Initial search radius.
const INITIAL_RADIUS: float = 100.0
## Radius expansion per ring.
const RADIUS_EXPANSION: float = 75.0
## Max search radius before relocating center.
const MAX_RADIUS: float = 2000.0
## How many waypoints to generate per expansion.
const WAYPOINTS_PER_RING: int = 20
## Nav update interval: each enemy only recalculates path every N physics frames.
const NAV_UPDATE_INTERVAL: int = 6  ## Issue #1458: increased from 3 to 6 since path is shared

## Current search center position.
var _center: Vector2 = Vector2.ZERO
## Current search radius.
var _radius: float = INITIAL_RADIUS
## All generated waypoints (shared pool).
var _waypoints: Array[Vector2] = []
## Waypoint claim map: waypoint index -> enemy instance_id (0 = unclaimed).
var _claims: Dictionary = {}
## Visited zones dictionary (zone_key -> true).
var _visited_zones: Dictionary = {}
## Spiral state for incremental generation.
var _spiral_direction: int = 0
var _spiral_leg_length: float = WAYPOINT_SPACING
var _spiral_legs_completed: int = 0
var _spiral_cursor: Vector2 = Vector2.ZERO
## Whether shared path is currently active.
var _active: bool = false
## Predefined path node (from SearchPathWaypoints group).
var _predefined_path_node: Node2D = null
## Whether using predefined path.
var _using_predefined: bool = false
## Registered searchers (enemy instance_id -> true).
var _searchers: Dictionary = {}
## Completed waypoints per enemy (instance_id -> Array[int] of completed wp indices).
var _completed: Dictionary = {}
## Nav stagger offset per enemy (instance_id -> frame offset).
var _nav_offsets: Dictionary = {}
## Frame counter for staggered nav updates.
var _frame_counter: int = 0


## Register an enemy as a searcher. Called when enemy enters SEARCHING state.
## center_position: where the search should be centered (typically last known player pos).
## Returns the first assigned waypoint index, or -1 if no waypoints available.
func register_searcher(enemy_id: int, center_position: Vector2) -> int:
	_searchers[enemy_id] = true
	_completed[enemy_id] = []
	_nav_offsets[enemy_id] = enemy_id % NAV_UPDATE_INTERVAL
	# If this is the first searcher or center changed significantly, regenerate
	if not _active or _center.distance_squared_to(center_position) > 10000.0:  # >100px
		_start_search(center_position)
	return claim_nearest(enemy_id)


## Unregister an enemy from searching. Called when enemy leaves SEARCHING state.
func unregister_searcher(enemy_id: int) -> void:
	_searchers.erase(enemy_id)
	_completed.erase(enemy_id)
	_nav_offsets.erase(enemy_id)
	# Release all claims by this enemy
	var to_release: Array[int] = []
	for wp_idx in _claims:
		if _claims[wp_idx] == enemy_id:
			to_release.append(wp_idx)
	for wp_idx in to_release:
		_claims.erase(wp_idx)
	# If no more searchers, deactivate
	if _searchers.is_empty():
		_active = false


## Claim the nearest unclaimed waypoint for this enemy. Returns index or -1.
func claim_nearest(enemy_id: int, from_pos: Vector2 = Vector2.ZERO) -> int:
	if _waypoints.is_empty():
		return -1
	# Use enemy's completed list to skip already-visited waypoints
	var completed_set: Array = _completed.get(enemy_id, [])
	var best_idx := -1
	var best_dist := INF
	for i in range(_waypoints.size()):
		if i in completed_set:
			continue
		# Skip if claimed by another enemy
		if _claims.has(i) and _claims[i] != enemy_id:
			continue
		var d: float = from_pos.distance_squared_to(_waypoints[i]) if from_pos != Vector2.ZERO else _waypoints[i].distance_squared_to(_center)
		if d < best_dist:
			best_dist = d
			best_idx = i
	if best_idx >= 0:
		_claims[best_idx] = enemy_id
	return best_idx


## Mark a waypoint as completed by this enemy and claim next nearest.
## Returns the next waypoint index, or -1 if all done (triggers expansion).
func complete_waypoint(enemy_id: int, wp_idx: int, enemy_pos: Vector2) -> int:
	# Mark zone visited
	if wp_idx >= 0 and wp_idx < _waypoints.size():
		_mark_zone_visited(_waypoints[wp_idx])
	# Release claim
	if _claims.has(wp_idx) and _claims[wp_idx] == enemy_id:
		_claims.erase(wp_idx)
	# Add to completed
	if not _completed.has(enemy_id):
		_completed[enemy_id] = []
	_completed[enemy_id].append(wp_idx)
	# Try to claim next
	var next := claim_nearest(enemy_id, enemy_pos)
	if next < 0:
		# All waypoints visited — try expanding
		next = _try_expand(enemy_id, enemy_pos)
	return next


## Get the waypoint position for a given index.
func get_waypoint(idx: int) -> Vector2:
	if idx >= 0 and idx < _waypoints.size():
		return _waypoints[idx]
	return Vector2.ZERO


## Check if this is a nav-update frame for this enemy (stagger).
func is_nav_update_frame(enemy_id: int) -> bool:
	var offset: int = _nav_offsets.get(enemy_id, 0)
	return (_frame_counter % NAV_UPDATE_INTERVAL) == offset


## Get all current waypoints (for visualization).
func get_all_waypoints() -> Array[Vector2]:
	return _waypoints.duplicate()


## Get claims map (for visualization: which enemy is heading to which waypoint).
func get_claims() -> Dictionary:
	return _claims.duplicate()


## Whether the shared search is active.
func is_active() -> bool:
	return _active


## Get center position.
func get_center() -> Vector2:
	return _center


func _physics_process(_delta: float) -> void:
	if _active:
		_frame_counter += 1


## Start a new shared search from center.
func _start_search(center: Vector2) -> void:
	_center = center
	_radius = INITIAL_RADIUS
	_waypoints.clear()
	_claims.clear()
	_visited_zones.clear()
	for eid in _completed:
		_completed[eid] = []
	_spiral_direction = 0
	_spiral_leg_length = WAYPOINT_SPACING
	_spiral_legs_completed = 0
	_spiral_cursor = center
	_frame_counter = 0
	_active = true
	# Try predefined path first
	_using_predefined = _load_predefined_path(center)
	if not _using_predefined:
		_generate_waypoints()
	FileLogger.log_info("[SharedSearchPath] Started search: center=%s, waypoints=%d, predefined=%s" % [center, _waypoints.size(), _using_predefined])


## Load predefined waypoints from SearchPathWaypoints node.
func _load_predefined_path(near_pos: Vector2) -> bool:
	_predefined_path_node = null
	var found := get_tree().get_nodes_in_group("search_path_waypoints")
	if found.size() > 0:
		_predefined_path_node = found[0]
	if _predefined_path_node == null:
		return false
	var wps: Array[Vector2] = []
	for c in _predefined_path_node.get_children():
		if c is Marker2D:
			wps.append(c.global_position)
	if wps.is_empty():
		return false
	# Sort by distance from near_pos for natural distribution
	var si := 0
	var md := INF
	for i in range(wps.size()):
		var d := near_pos.distance_to(wps[i])
		if d < md:
			md = d
			si = i
	_waypoints.clear()
	for i in range(wps.size()):
		_waypoints.append(wps[(si + i) % wps.size()])
	return true


## Generate spiral waypoints. Only generates navigable, unvisited positions.
func _generate_waypoints() -> void:
	var old_size := _waypoints.size()
	var generated := 0
	var iters := 0
	while generated < WAYPOINTS_PER_RING and _spiral_leg_length <= _radius * 2 and iters < 100:
		iters += 1
		var offset := Vector2.ZERO
		match _spiral_direction:
			0: offset = Vector2(0, -_spiral_leg_length)
			1: offset = Vector2(_spiral_leg_length, 0)
			2: offset = Vector2(0, _spiral_leg_length)
			3: offset = Vector2(-_spiral_leg_length, 0)
		var next_pos := _spiral_cursor + offset
		if _is_navigable(next_pos) and not _is_zone_visited(next_pos):
			_waypoints.append(next_pos)
			generated += 1
		_spiral_cursor = next_pos
		_spiral_legs_completed += 1
		_spiral_direction = (_spiral_direction + 1) % 4
		if _spiral_legs_completed % 2 == 0:
			_spiral_leg_length += WAYPOINT_SPACING
	if generated > 0:
		FileLogger.log_info("[SharedSearchPath] Generated %d waypoints (total=%d, radius=%.0f)" % [generated, _waypoints.size(), _radius])


## Try to expand the search radius and generate more waypoints.
func _try_expand(enemy_id: int, enemy_pos: Vector2) -> int:
	if _using_predefined:
		# Loop predefined path: clear completed for this enemy
		_completed[enemy_id] = []
		return claim_nearest(enemy_id, enemy_pos)
	if _radius < MAX_RADIUS:
		_radius += RADIUS_EXPANSION
		_generate_waypoints()
		if not _waypoints.is_empty():
			return claim_nearest(enemy_id, enemy_pos)
	else:
		# Max radius reached — relocate center to average position of active searchers
		var avg := Vector2.ZERO
		var count := 0
		var enemies := get_tree().get_nodes_in_group("enemies")
		for enemy in enemies:
			if is_instance_valid(enemy) and _searchers.has(enemy.get_instance_id()):
				avg += enemy.global_position
				count += 1
		if count > 0:
			avg /= count
		else:
			avg = enemy_pos
		_visited_zones.clear()
		for eid in _completed:
			_completed[eid] = []
		_center = avg
		_radius = INITIAL_RADIUS
		_spiral_cursor = avg
		_spiral_direction = 0
		_spiral_leg_length = WAYPOINT_SPACING
		_spiral_legs_completed = 0
		_waypoints.clear()
		_claims.clear()
		_generate_waypoints()
		FileLogger.log_info("[SharedSearchPath] Relocated center to %s, cleared zones" % avg)
		return claim_nearest(enemy_id, enemy_pos)
	return -1


## Check if position is navigable via NavigationServer2D.
func _is_navigable(pos: Vector2) -> bool:
	var nav_map := get_tree().root.get_world_2d().navigation_map
	var closest := NavigationServer2D.map_get_closest_point(nav_map, pos)
	return pos.distance_to(closest) < 50.0


## Zone key: integer hash (no string allocation). Matches enemy.gd formula.
func _get_zone_key(pos: Vector2) -> int:
	return int(pos.x / ZONE_SNAP) * 100003 + int(pos.y / ZONE_SNAP)


func _is_zone_visited(pos: Vector2) -> bool:
	return _visited_zones.has(_get_zone_key(pos))


func _mark_zone_visited(pos: Vector2) -> void:
	_visited_zones[_get_zone_key(pos)] = true
