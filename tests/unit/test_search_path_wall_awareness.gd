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
# Visited-zone marking tests (Issue #1275 owner feedback)
# Owner requirement: a zone is only counted as visited when the enemy physically
# touches (reaches) the waypoint — not when it skips due to being stuck or when
# the NavigationAgent reports navigation finished from afar.
# ============================================================================


class StubSearchStateProcessor:
	## Simulates the visited-zone marking logic from _process_searching_state().
	## Only marks a zone visited when the enemy has physically scanned it
	## (i.e. arrived within REACHED_DISTANCE and completed the scan timer).

	const REACHED_DISTANCE: float = 20.0
	const SCAN_DURATION: float = 1.0
	const STUCK_MAX_TIME: float = 2.0
	const PROGRESS_THRESHOLD: float = 10.0

	var visited: Dictionary = {}
	var waypoints: Array[Vector2] = []
	var current_index: int = 0
	var moving: bool = true
	var scan_timer: float = 0.0
	var stuck_timer: float = 0.0
	var last_progress_pos: Vector2 = Vector2.ZERO
	var enemy_pos: Vector2 = Vector2.ZERO

	## Simulate one "frame" of the searching state.
	## nav_finished: whether NavigationAgent.is_navigation_finished() would return true.
	## progress: distance the enemy "moved" this frame.
	## delta: frame time.
	func process_frame(delta: float, nav_finished: bool, progress: float) -> void:
		if current_index >= waypoints.size():
			return
		var wp := waypoints[current_index]
		var dist := enemy_pos.distance_to(wp)
		if moving:
			if dist <= REACHED_DISTANCE:
				# Physically arrived — start scanning
				moving = false; scan_timer = 0.0; stuck_timer = 0.0
			elif nav_finished:
				# Nav agent says done but enemy is not close — Issue #1275 fix:
				# do NOT mark visited, just skip to next waypoint.
				current_index += 1; moving = true; stuck_timer = 0.0
			else:
				# Moving toward waypoint
				if progress < PROGRESS_THRESHOLD:
					stuck_timer += delta
					if stuck_timer >= STUCK_MAX_TIME:
						# Stuck — Issue #1275 fix: do NOT mark visited, just skip.
						current_index += 1; moving = true; stuck_timer = 0.0
				else:
					stuck_timer = 0.0
		else:
			# Scanning at waypoint
			scan_timer += delta
			if scan_timer >= SCAN_DURATION:
				# Scan complete — enemy physically touched and scanned this zone.
				_mark_visited(wp); current_index += 1; moving = true

	func _mark_visited(pos: Vector2) -> void:
		var k := "%d,%d" % [int(pos.x / 50.0) * 50, int(pos.y / 50.0) * 50]
		visited[k] = true

	func is_visited(pos: Vector2) -> bool:
		var k := "%d,%d" % [int(pos.x / 50.0) * 50, int(pos.y / 50.0) * 50]
		return visited.has(k)


func _make_processor(wp: Vector2, enemy_at: Vector2) -> StubSearchStateProcessor:
	var p := StubSearchStateProcessor.new()
	p.waypoints = [wp]
	p.enemy_pos = enemy_at
	p.last_progress_pos = enemy_at
	return p


func test_stuck_waypoint_not_marked_visited() -> void:
	## When the enemy is stuck and skips a waypoint, the zone must NOT be marked visited
	## so future spiral rings can still include that position.
	var wp := Vector2(200, 0)
	var p := _make_processor(wp, Vector2(0, 0))
	# Enemy is far from waypoint and making no progress (stuck)
	p.enemy_pos = Vector2(0, 0)  # far from wp

	# Simulate stuck: no progress for STUCK_MAX_TIME + 1 extra frame
	var frames := int(StubSearchStateProcessor.STUCK_MAX_TIME / 0.1) + 1
	for _i in range(frames):
		p.process_frame(0.1, false, 0.0)  # progress=0 → stuck

	assert_false(p.is_visited(wp),
		"Stuck-skipped waypoint must NOT be marked visited (Issue #1275)")
	assert_eq(p.current_index, 1, "Index should advance past the stuck waypoint")


func test_nav_finished_early_not_marked_visited() -> void:
	## When NavigationAgent.is_navigation_finished() fires before the enemy is close,
	## the zone must NOT be marked visited.
	var wp := Vector2(300, 0)
	var p := _make_processor(wp, Vector2(0, 0))
	p.enemy_pos = Vector2(0, 0)  # far from wp

	# One frame where nav says finished but enemy is not close
	p.process_frame(0.1, true, 100.0)

	assert_false(p.is_visited(wp),
		"Nav-finished-early waypoint must NOT be marked visited (Issue #1275)")
	assert_eq(p.current_index, 1, "Index should advance past the waypoint")


func test_physically_reached_and_scanned_marked_visited() -> void:
	## When the enemy physically arrives (dist ≤ REACHED_DISTANCE) and completes
	## the scan timer, the zone IS marked visited.
	var wp := Vector2(10, 0)  # within REACHED_DISTANCE of origin
	var p := _make_processor(wp, Vector2(0, 0))
	p.enemy_pos = Vector2(5, 0)  # within 20px of wp → "touches" it

	# First frame: arrives (moving → scanning)
	p.process_frame(0.1, false, 0.0)
	assert_false(p.is_visited(wp), "Not yet visited — still scanning")

	# Scan frames until SCAN_DURATION is exceeded
	var scan_frames := int(StubSearchStateProcessor.SCAN_DURATION / 0.1) + 1
	for _i in range(scan_frames):
		p.process_frame(0.1, false, 0.0)

	assert_true(p.is_visited(wp),
		"Zone must be visited after enemy physically touches and scans it (Issue #1275)")


func test_stuck_then_reached_on_retry_marks_visited() -> void:
	## Validates the full intended flow: enemy skips a stuck wp without marking it
	## visited, so the zone remains available for future spiral regeneration.
	## Here we verify that if the enemy later physically reaches the same position,
	## it IS then marked visited.
	var wp_stuck := Vector2(200, 0)
	var wp_close := Vector2(10, 0)
	var p := StubSearchStateProcessor.new()
	p.waypoints = [wp_stuck, wp_close]
	p.enemy_pos = Vector2(0, 0)

	# Get stuck on first wp
	var stuck_frames := int(StubSearchStateProcessor.STUCK_MAX_TIME / 0.1) + 1
	for _i in range(stuck_frames):
		p.process_frame(0.1, false, 0.0)

	assert_false(p.is_visited(wp_stuck), "Stuck wp should not be marked visited")
	assert_eq(p.current_index, 1, "Should advance to second waypoint")

	# Now physically reach the close wp
	p.enemy_pos = Vector2(5, 0)  # within 20px of wp_close
	p.process_frame(0.1, false, 0.0)  # arrive at wp_close
	var scan_frames := int(StubSearchStateProcessor.SCAN_DURATION / 0.1) + 1
	for _i in range(scan_frames):
		p.process_frame(0.1, false, 0.0)

	assert_true(p.is_visited(wp_close), "Physically reached wp should be marked visited")
	assert_false(p.is_visited(wp_stuck), "First stuck wp still must NOT be marked visited")


# ============================================================================
# Constants validation
# ============================================================================


func test_spacing_constant_reasonable() -> void:
	assert_gt(StubWaypointGenerator.SEARCH_WAYPOINT_SPACING, 0.0,
		"Waypoint spacing should be positive")
	assert_lt(StubWaypointGenerator.SEARCH_WAYPOINT_SPACING, 500.0,
		"Waypoint spacing should be less than 500px")
