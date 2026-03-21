extends GutTest
## Unit tests for wall-aware search path generation (Issue #1275).
##
## Tests that the spiral waypoint generator correctly rejects candidates that are
## unreachable from the enemy's position (i.e., behind walls), and that the spiral
## tracking position only advances when the step lands on the navigation mesh.


# ============================================================================
# Stub classes for logic testing without Godot scene / NavigationServer2D
# ============================================================================


class StubWaypointGenerator:
	## Simulates the waypoint generation logic from _generate_search_waypoints() (Issue #322/#1275).
	## Uses injected callbacks for navigability and path checks so tests can control them.

	const SEARCH_WAYPOINT_SPACING: float = 75.0
	const SEARCH_ZONE_SNAP_SIZE: float = 50.0

	var enemy_pos: Vector2 = Vector2.ZERO
	var search_center: Vector2 = Vector2.ZERO
	var search_radius: float = 300.0

	## Injected: returns true when pos is on the navigation mesh.
	var is_navigable_fn: Callable = func(_pos: Vector2) -> bool: return true
	## Injected: returns true when a navigable path exists from->to.
	var is_path_navigable_fn: Callable = func(_f: Vector2, _t: Vector2) -> bool: return true

	var _visited: Dictionary = {}

	func generate() -> Array[Vector2]:
		var waypoints: Array[Vector2] = []
		var current_pos := search_center
		var direction := 0
		var leg_length := SEARCH_WAYPOINT_SPACING
		var legs_completed := 0
		var waypoints_generated := 0
		var iters := 0

		if not _is_zone_visited(search_center):
			waypoints.append(search_center)
			waypoints_generated += 1

		while waypoints_generated < 20 and leg_length <= search_radius * 2 and iters < 100:
			iters += 1
			var offset := Vector2.ZERO
			match direction:
				0: offset = Vector2(0, -leg_length)
				1: offset = Vector2(leg_length, 0)
				2: offset = Vector2(0, leg_length)
				3: offset = Vector2(-leg_length, 0)
			var next_pos := current_pos + offset
			# Issue #1275 fix: require navigable point AND a wall-free path from enemy.
			if is_navigable_fn.call(next_pos) and not _is_zone_visited(next_pos) \
					and is_path_navigable_fn.call(enemy_pos, next_pos):
				waypoints.append(next_pos)
				waypoints_generated += 1
			# Only advance tracking pos when step is on nav mesh (Issue #1275).
			if is_navigable_fn.call(next_pos):
				current_pos = next_pos
			legs_completed += 1
			direction = (direction + 1) % 4
			if legs_completed % 2 == 0:
				leg_length += SEARCH_WAYPOINT_SPACING
		return waypoints

	func _is_zone_visited(pos: Vector2) -> bool:
		return _visited.has(_zone_key(pos))

	func _zone_key(pos: Vector2) -> String:
		return "%d,%d" % [int(pos.x / SEARCH_ZONE_SNAP_SIZE) * int(SEARCH_ZONE_SNAP_SIZE),
			int(pos.y / SEARCH_ZONE_SNAP_SIZE) * int(SEARCH_ZONE_SNAP_SIZE)]


# ============================================================================
# Helper
# ============================================================================


## Returns a StubWaypointGenerator with the enemy at origin and all positions
## reachable by default.
func _make_generator(enemy_pos: Vector2 = Vector2.ZERO) -> StubWaypointGenerator:
	var gen := StubWaypointGenerator.new()
	gen.enemy_pos = enemy_pos
	gen.search_center = enemy_pos
	return gen


# ============================================================================
# Basic sanity tests
# ============================================================================


func test_all_reachable_generates_waypoints() -> void:
	var gen := _make_generator()
	var wps := gen.generate()
	assert_gt(wps.size(), 0, "Should generate at least one waypoint when all positions are reachable")


func test_first_waypoint_is_search_center() -> void:
	var gen := _make_generator(Vector2(100, 200))
	var wps := gen.generate()
	assert_gt(wps.size(), 0, "Should have at least one waypoint")
	assert_eq(wps[0], Vector2(100, 200), "First waypoint should be the search center")


# ============================================================================
# Wall filtering tests (Issue #1275 core requirement)
# ============================================================================


func test_waypoints_behind_wall_are_excluded() -> void:
	## Wall at y < -50 blocks positions north of it.
	var gen := _make_generator(Vector2(0, 0))
	# All points are on the nav mesh, but paths to points with y < -50 are blocked.
	gen.is_path_navigable_fn = func(from: Vector2, to: Vector2) -> bool:
		return to.y >= -50.0

	var wps := gen.generate()
	for wp in wps:
		assert_true(wp.y >= -50.0,
			"No waypoint should have y < -50 (behind wall). Got: %s" % wp)


func test_waypoints_in_other_room_are_excluded() -> void:
	## Simulate a wall at x = 200 that prevents entering a room to the east.
	var gen := _make_generator(Vector2(0, 0))
	gen.is_path_navigable_fn = func(_from: Vector2, to: Vector2) -> bool:
		return to.x <= 200.0

	var wps := gen.generate()
	for wp in wps:
		assert_true(wp.x <= 200.0 + 0.001,
			"No waypoint should be east of x=200 (other room). Got: %s" % wp)


func test_all_directions_blocked_yields_only_center() -> void:
	## Only the search center itself is reachable — all paths to other positions are blocked.
	var gen := _make_generator(Vector2(50, 50))
	gen.is_path_navigable_fn = func(_from: Vector2, to: Vector2) -> bool:
		return to.is_equal_approx(Vector2(50, 50))

	var wps := gen.generate()
	assert_eq(wps.size(), 1, "Only the center should be included when all paths are blocked")
	assert_eq(wps[0], Vector2(50, 50))


func test_partial_wall_allows_some_waypoints() -> void:
	## East and south are reachable; north and west are blocked.
	var gen := _make_generator(Vector2(0, 0))
	gen.is_path_navigable_fn = func(_from: Vector2, to: Vector2) -> bool:
		return to.x >= 0.0 and to.y >= 0.0  # Only quadrant IV (east/south)

	var wps := gen.generate()
	for wp in wps:
		assert_true(wp.x >= -0.001 and wp.y >= -0.001,
			"All waypoints should be in the east/south quadrant. Got: %s" % wp)


# ============================================================================
# Spiral tracking position tests (Issue #1275 secondary fix)
# ============================================================================


func test_tracking_position_does_not_advance_into_off_mesh_point() -> void:
	## If a step lands on a position that is NOT on the nav mesh, the tracking
	## position must stay at the previous valid position.
	## Consequence: the next spiral step originates from the last valid position,
	## not from inside a wall.
	##
	## We verify this indirectly: when one direction is entirely off-mesh, the
	## spiral still generates valid waypoints in other directions.

	var gen := _make_generator(Vector2(0, 0))
	# North positions (y < 0) are off the nav mesh entirely.
	gen.is_navigable_fn = func(pos: Vector2) -> bool:
		return pos.y >= 0.0 or pos.is_equal_approx(Vector2.ZERO)
	gen.is_path_navigable_fn = func(_f: Vector2, to: Vector2) -> bool:
		return to.y >= 0.0 or to.is_equal_approx(Vector2.ZERO)

	var wps := gen.generate()
	# Should still find at least center + some south/east waypoints.
	assert_gt(wps.size(), 1,
		"Should generate waypoints in non-blocked directions even when one direction is off mesh")
	for wp in wps:
		assert_true(wp.y >= -0.001,
			"No waypoint should be north of origin (off mesh). Got: %s" % wp)


# ============================================================================
# Regression: pre-fix behaviour would have included cross-wall waypoints
# ============================================================================


func test_pre_fix_behaviour_would_have_included_cross_wall_waypoint() -> void:
	## This test documents that the OLD code (without _is_path_navigable check)
	## WOULD have included a blocked waypoint, while the new code rejects it.
	##
	## We simulate the old generator (no path check) and confirm it returns a
	## waypoint that the new generator would reject.

	var old_gen := StubWaypointGenerator.new()
	old_gen.enemy_pos = Vector2(0, 0)
	old_gen.search_center = Vector2(0, 0)
	# Old code: no path-navigability filter — any point on the mesh is included.
	old_gen.is_navigable_fn = func(_pos: Vector2) -> bool: return true
	old_gen.is_path_navigable_fn = func(_f: Vector2, _t: Vector2) -> bool: return true
	var old_wps := old_gen.generate()

	var new_gen := StubWaypointGenerator.new()
	new_gen.enemy_pos = Vector2(0, 0)
	new_gen.search_center = Vector2(0, 0)
	new_gen.is_navigable_fn = func(_pos: Vector2) -> bool: return true
	# New code: path to positions with x > 150 is blocked by a wall.
	new_gen.is_path_navigable_fn = func(_f: Vector2, to: Vector2) -> bool:
		return to.x <= 150.0

	var new_wps := new_gen.generate()

	# Old generator (no path check) would include positions with x > 150.
	var old_has_cross_wall := false
	for wp in old_wps:
		if wp.x > 150.0:
			old_has_cross_wall = true
			break
	assert_true(old_has_cross_wall,
		"Without path check, the old generator would include cross-wall waypoints")

	# New generator must not include any position with x > 150.
	for wp in new_wps:
		assert_true(wp.x <= 150.0 + 0.001,
			"New generator must reject cross-wall waypoints. Got: %s" % wp)


# ============================================================================
# Constants validation
# ============================================================================


func test_spacing_constant_reasonable() -> void:
	assert_gt(StubWaypointGenerator.SEARCH_WAYPOINT_SPACING, 0.0,
		"Waypoint spacing should be positive")
	assert_lt(StubWaypointGenerator.SEARCH_WAYPOINT_SPACING, 500.0,
		"Waypoint spacing should be less than 500px")
