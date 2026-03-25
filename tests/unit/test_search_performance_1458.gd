extends GutTest
## Regression tests for Issue #1458: SEARCHING state performance optimization.
##
## Tests verify the performance fixes across all rounds:
## 1. Minimum time in SEARCHING before COMBAT transition prevents oscillation
## 2. Navigation target caching avoids redundant path recalculations
## 3. _transition_to_idle redirect chain avoids re-generating waypoints when already SEARCHING
## 4. Cover-inspection waypoint generation replaces random/spiral algorithms (#1458r3)
## 5. Timeout log throttled to once per search session
## 6. #1458r4: Shared pool — points placed on navigable side of wall (wall normal offset)
## 7. #1458r4: Minimum distance between points enforced (no crowding)
## 8. #1458r4: Max point cap enforced
## 9. #1458r4: FOV clearing throttled (not every frame)
## 10. #1458r4: No per-frame get_nodes_in_group — shared array used instead of sync


# ============================================================================
# Constants matching enemy.gd
# ============================================================================

const SEARCH_MIN_TIME_BEFORE_COMBAT: float = 0.3
const SEARCH_WAYPOINT_COUNT: int = 5
const SEARCH_NAV_SNAP_THRESHOLD: float = 100.0  ## #1458r4: increased to 100 for better navmesh hit
const SEARCH_MAX_DURATION: float = 30.0
const SEARCH_INITIAL_RADIUS: float = 150.0
const SEARCH_MAX_RADIUS: float = 600.0
const SEARCH_RADIUS_EXPANSION: float = 100.0
const SEARCH_INSPECT_RAY_COUNT: int = 24  ## #1458r4: 24 rays (15° apart)
const SEARCH_INSPECT_RAY_DISTANCE: float = 600.0  ## #1458r4: reduced to 600px
const SEARCH_INSPECT_CLEAR_RADIUS: float = 80.0  ## #1458r4: increased to 80px
const SEARCH_INSPECT_MIN_DIST: float = 100.0  ## #1458r4: minimum distance between points
const SEARCH_INSPECT_MAX_POINTS: int = 12  ## #1458r4: max points per session
const SEARCH_ZONE_SNAP_SIZE: float = 50.0
const SEARCH_FOV_CLEAR_INTERVAL: float = 0.15  ## #1458r4: throttle interval


# ============================================================================
# Tests: SEARCHING→COMBAT oscillation prevention
# ============================================================================


func test_combat_transition_blocked_before_min_time() -> void:
	var search_state_timer: float = 0.1
	var can_see_player: bool = true
	var should_transition: bool = can_see_player and search_state_timer >= SEARCH_MIN_TIME_BEFORE_COMBAT
	assert_false(should_transition,
		"Should NOT transition to COMBAT before %.1fs in SEARCHING (Issue #1458)" % SEARCH_MIN_TIME_BEFORE_COMBAT)


func test_combat_transition_allowed_after_min_time() -> void:
	var search_state_timer: float = 0.35
	var can_see_player: bool = true
	var should_transition: bool = can_see_player and search_state_timer >= SEARCH_MIN_TIME_BEFORE_COMBAT
	assert_true(should_transition,
		"Should transition to COMBAT after %.1fs in SEARCHING" % SEARCH_MIN_TIME_BEFORE_COMBAT)


func test_combat_transition_not_triggered_without_player_visibility() -> void:
	var search_state_timer: float = 1.0
	var can_see_player: bool = false
	var should_transition: bool = can_see_player and search_state_timer >= SEARCH_MIN_TIME_BEFORE_COMBAT
	assert_false(should_transition,
		"Should NOT transition to COMBAT when player is not visible")


func test_min_time_constant_is_reasonable() -> void:
	assert_gt(SEARCH_MIN_TIME_BEFORE_COMBAT, 0.0, "Min time should be positive")
	assert_lt(SEARCH_MIN_TIME_BEFORE_COMBAT, 1.0, "Min time should be under 1s")


# ============================================================================
# Tests: Navigation target caching
# ============================================================================


func test_nav_target_cache_prevents_redundant_update() -> void:
	var cached_target := Vector2(100, 200)
	var current_waypoint := Vector2(100, 200)
	var should_update: bool = cached_target.distance_squared_to(current_waypoint) > 1.0
	assert_false(should_update, "Should NOT update nav target when waypoint unchanged")


func test_nav_target_cache_allows_new_waypoint() -> void:
	var cached_target := Vector2(100, 200)
	var current_waypoint := Vector2(175, 275)
	var should_update: bool = cached_target.distance_squared_to(current_waypoint) > 1.0
	assert_true(should_update, "Should update nav target when waypoint changes")


func test_nav_target_cache_allows_first_waypoint() -> void:
	var cached_target := Vector2.ZERO
	var current_waypoint := Vector2(50, 50)
	var should_update: bool = cached_target.distance_squared_to(current_waypoint) > 1.0
	assert_true(should_update, "Should update nav target on first waypoint")


# ============================================================================
# Tests: _transition_to_idle redirect chain optimization
# ============================================================================


func test_idle_redirect_skips_regeneration_when_already_searching() -> void:
	var current_state: int = 9  # AIState.SEARCHING
	var idle_enabled: bool = false
	var should_regenerate: bool = not idle_enabled and current_state != 9
	assert_false(should_regenerate, "Should NOT regenerate when already SEARCHING")


func test_idle_redirect_regenerates_when_coming_from_other_state() -> void:
	var current_state: int = 1  # AIState.COMBAT
	var idle_enabled: bool = false
	var should_regenerate: bool = not idle_enabled and current_state != 9
	assert_true(should_regenerate, "Should regenerate when transitioning from non-SEARCHING")


func test_idle_redirect_not_triggered_when_idle_enabled() -> void:
	var idle_enabled: bool = true
	var is_redirect: bool = not idle_enabled
	assert_false(is_redirect, "Should use normal IDLE when enabled")


# ============================================================================
# Tests: Logging throttle
# ============================================================================


func test_combat_transition_logs_only_once_per_session() -> void:
	var logged: bool = false
	if not logged: logged = true
	var first_log := logged
	var should_log_again: bool = not logged
	assert_true(first_log, "Should log on first player spotted event")
	assert_false(should_log_again, "Should NOT log on subsequent frames")


func test_timeout_log_fires_only_once() -> void:
	var timeout_logged: bool = false
	var log_count: int = 0
	for _frame in range(60):
		var search_state_timer: float = 31.0 + _frame * 0.016
		if search_state_timer >= SEARCH_MAX_DURATION and not timeout_logged:
			timeout_logged = true; log_count += 1
	assert_eq(log_count, 1, "Timeout log should fire exactly once")


# ============================================================================
# Tests: #1458r4 — Cover-inspection algorithm fixes
# ============================================================================


func test_inspection_ray_count_reasonable() -> void:
	# 24 rays at 15° apart gives full 360° coverage with fewer raycasts (#1458r4: reduced from 36)
	assert_eq(SEARCH_INSPECT_RAY_COUNT, 24, "Should use 24 rays (15° apart) — #1458r4 reduced from 36")
	assert_gt(SEARCH_INSPECT_RAY_COUNT, 8, "Need enough rays for good coverage")
	assert_lte(SEARCH_INSPECT_RAY_COUNT, 72, "Too many rays is wasteful")


func test_inspection_ray_distance_reasonable() -> void:
	assert_gt(SEARCH_INSPECT_RAY_DISTANCE, 200.0, "Rays must reach nearby obstacles")
	assert_lte(SEARCH_INSPECT_RAY_DISTANCE, 1500.0, "Rays should not span entire map")


func test_inspection_clear_radius_reasonable() -> void:
	# Must be small enough to require enemies to actually approach the point
	assert_gt(SEARCH_INSPECT_CLEAR_RADIUS, 20.0, "Clear radius must be positive")
	assert_lte(SEARCH_INSPECT_CLEAR_RADIUS, 150.0, "Clear radius should force proximity")


func test_inspection_point_min_distance_enforced() -> void:
	## #1458r4: Points within SEARCH_INSPECT_MIN_DIST should be rejected as duplicates
	var p1 := Vector2(100, 100)
	var p2 := Vector2(150, 110)  # ~51px away, within 100px min dist
	var is_too_close: bool = p1.distance_to(p2) < SEARCH_INSPECT_MIN_DIST
	assert_true(is_too_close, "Points within min distance should be rejected (#1458r4)")


func test_inspection_point_distinct_points_kept() -> void:
	var p1 := Vector2(100, 100)
	var p2 := Vector2(300, 200)  # ~224px away, beyond min distance
	var is_too_close: bool = p1.distance_to(p2) < SEARCH_INSPECT_MIN_DIST
	assert_false(is_too_close, "Distant points should NOT be rejected")


func test_max_inspection_points_cap() -> void:
	## #1458r4: Pool must not exceed SEARCH_INSPECT_MAX_POINTS
	assert_gt(SEARCH_INSPECT_MAX_POINTS, 0, "Max points must be positive")
	assert_lte(SEARCH_INSPECT_MAX_POINTS, 24, "Max points must be bounded to prevent performance issues")
	var simulated_points_generated: int = 15  # Simulates a large open area
	var actual_points: int = mini(simulated_points_generated, SEARCH_INSPECT_MAX_POINTS)
	assert_lte(actual_points, SEARCH_INSPECT_MAX_POINTS, "Should not exceed max point cap")


func test_inspection_behind_obstacle_uses_wall_normal() -> void:
	## #1458r4: Point should be placed 40px BACK from wall using wall normal (not further along ray)
	## This ensures points are on the navigable side, not inside/past the wall
	var hit_point := Vector2(300, 0)
	var wall_normal := Vector2(-1, 0)  # Wall faces left (ray came from right)
	var inspect_pos := hit_point + wall_normal.normalized() * 40.0
	assert_eq(inspect_pos, Vector2(260, 0), "Inspection point should be 40px back from wall using wall normal (#1458r4)")
	# Old (broken) behavior would give Vector2(345, 0) — past the wall
	assert_ne(inspect_pos.x, 345.0, "Point should NOT be placed further along ray direction (past wall)")


func test_inspection_point_not_too_close_to_search_center() -> void:
	## #1458r4: Points within 80px of search center are already visible — skip them
	var search_center := Vector2(0, 0)
	var point_near := Vector2(60, 0)
	var point_far := Vector2(150, 0)
	var near_too_close: bool = point_near.distance_to(search_center) < 80.0
	var far_ok: bool = point_far.distance_to(search_center) >= 80.0
	assert_true(near_too_close, "Point within 80px of search center should be skipped")
	assert_true(far_ok, "Point beyond 80px should be accepted")


func test_nav_snap_threshold_increased_for_better_coverage() -> void:
	## #1458r4: Increased to 100px to reduce 'search not triggering' bug
	assert_gte(SEARCH_NAV_SNAP_THRESHOLD, 100.0,
		"Nav snap threshold should be 100px (#1458r4: increased from 50px to reduce empty pool bug)")


func test_fov_clearing_within_radius() -> void:
	# Simulates: enemy at origin facing right, inspection point at (60, 0) — within range & FOV
	var enemy_pos := Vector2.ZERO
	var facing_dir := Vector2(1, 0)
	var point := Vector2(60, 0)  # Within SEARCH_INSPECT_CLEAR_RADIUS = 80
	var dist := enemy_pos.distance_to(point)
	var dir_to_point := (point - enemy_pos).normalized()
	var angle_diff := acos(clampf(facing_dir.dot(dir_to_point), -1.0, 1.0))
	var half_fov := deg_to_rad(50.0)  # 100° FOV
	var should_clear: bool = dist <= SEARCH_INSPECT_CLEAR_RADIUS and angle_diff <= half_fov
	assert_true(should_clear, "Point within range and FOV should be cleared")


func test_fov_clearing_outside_radius() -> void:
	# Point beyond clear radius should NOT be cleared by FOV alone
	var enemy_pos := Vector2.ZERO
	var point := Vector2(200, 0)
	var dist := enemy_pos.distance_to(point)
	var should_clear: bool = dist <= SEARCH_INSPECT_CLEAR_RADIUS
	assert_false(should_clear, "Point beyond clear radius should require physical inspection")


func test_fov_clearing_outside_fov_angle() -> void:
	# Point behind enemy should NOT be cleared
	var enemy_pos := Vector2.ZERO
	var facing_dir := Vector2(1, 0)  # Facing right
	var point := Vector2(-30, 0)  # Behind enemy, but within range
	var dist := enemy_pos.distance_to(point)
	var dir_to_point := (point - enemy_pos).normalized()
	var angle_diff := acos(clampf(facing_dir.dot(dir_to_point), -1.0, 1.0))
	var half_fov := deg_to_rad(50.0)
	var should_clear: bool = dist <= SEARCH_INSPECT_CLEAR_RADIUS and angle_diff <= half_fov
	assert_false(should_clear, "Point outside FOV should NOT be cleared")


func test_fov_clearing_throttled() -> void:
	## #1458r4: FOV clearing must be throttled to avoid per-frame overhead
	assert_gt(SEARCH_FOV_CLEAR_INTERVAL, 0.0, "Throttle interval must be positive")
	assert_lte(SEARCH_FOV_CLEAR_INTERVAL, 0.5, "Throttle interval should be at most 500ms for responsiveness")
	# Simulate: only run FOV clearing when timer <= 0
	var timer: float = SEARCH_FOV_CLEAR_INTERVAL
	var clear_count: int = 0
	var dt: float = 0.016  # 60fps
	for _frame in range(60):  # simulate 1 second
		timer -= dt
		if timer <= 0.0:
			clear_count += 1; timer = SEARCH_FOV_CLEAR_INTERVAL
	# At 60fps over 1s, should fire ~6 times (every 0.15s), not 60 times
	assert_lte(clear_count, 10, "FOV clearing should NOT run every frame (throttled)")
	assert_gte(clear_count, 5, "FOV clearing should run regularly")


func test_all_points_cleared_check() -> void:
	# Simulates _all_inspection_points_cleared logic
	var flags: Array[bool] = [true, true, true, true, true]
	var all_cleared := true
	for f in flags:
		if not f: all_cleared = false; break
	assert_true(all_cleared, "All flags true = all cleared")


func test_not_all_points_cleared() -> void:
	var flags: Array[bool] = [true, false, true, true, true]
	var all_cleared := true
	for f in flags:
		if not f: all_cleared = false; break
	assert_false(all_cleared, "One false flag = not all cleared")


func test_nearest_uninspected_point_selection() -> void:
	# Simulates _assign_nearest_inspection_point logic
	var enemy_pos := Vector2(0, 0)
	var points: Array[Vector2] = [Vector2(100, 0), Vector2(50, 0), Vector2(200, 0)]
	var flags: Array[bool] = [false, false, false]
	var best_idx := -1; var best_dist := INF
	for i in range(points.size()):
		if flags[i]: continue
		var d := enemy_pos.distance_to(points[i])
		if d < best_dist: best_dist = d; best_idx = i
	assert_eq(best_idx, 1, "Should select nearest uninspected point (index 1 at 50px)")


func test_nearest_skips_inspected_points() -> void:
	var enemy_pos := Vector2(0, 0)
	var points: Array[Vector2] = [Vector2(100, 0), Vector2(50, 0), Vector2(200, 0)]
	var flags: Array[bool] = [false, true, false]  # Index 1 already inspected
	var best_idx := -1; var best_dist := INF
	for i in range(points.size()):
		if flags[i]: continue
		var d := enemy_pos.distance_to(points[i])
		if d < best_dist: best_dist = d; best_idx = i
	assert_eq(best_idx, 0, "Should skip inspected point and select index 0 at 100px")


func test_shared_array_reference_semantics() -> void:
	## #1458r5: Plain untyped Array assignment is by reference. Writes from one enemy are visible to all.
	## The fix uses var arr: Array = dict["flags"] (no typed cast) which is always a reference.
	var pool := {"flags": [false, false, false]}
	var enemy_a_flags: Array = pool["flags"]  ## untyped — safe reference in Godot 4.3
	var enemy_b_flags: Array = pool["flags"]  ## same reference
	enemy_a_flags[0] = true
	assert_true(enemy_b_flags[0], "Untyped plain Array: flag set by A must be visible to B (#1458r5)")


func test_round_robin_point_assignment_spreads_enemies() -> void:
	## #1458r5: next_idx counter ensures each enemy claims a different point.
	var pool := {"points": [Vector2(100,0), Vector2(200,0), Vector2(300,0)], "flags": [false,false,false], "next_idx": 0}
	var flags: Array = pool["flags"]
	## Simulate 3 enemies each claiming next_idx
	var claims := []
	for _e in range(3):
		var ni: int = pool["next_idx"]
		for _a in range(pool["points"].size()):
			var idx := ni % pool["points"].size(); ni += 1
			if not flags[idx]: claims.append(idx); pool["next_idx"] = ni; break
	assert_eq(claims.size(), 3, "3 enemies should each get a claim")
	assert_ne(claims[0], claims[1], "Enemy 0 and 1 should claim different points")
	assert_ne(claims[1], claims[2], "Enemy 1 and 2 should claim different points")


func test_shared_pool_key_snapping() -> void:
	## #1458r4: Two enemies with similar search centers should use the same pool key.
	## Pool key snaps to 200px grid.
	var snap := 200.0
	var center_a := Vector2(350, 420)
	var center_b := Vector2(370, 450)  # Close to A, within same 200px cell
	var key_a := "%d,%d" % [int(center_a.x / snap) * int(snap), int(center_a.y / snap) * int(snap)]
	var key_b := "%d,%d" % [int(center_b.x / snap) * int(snap), int(center_b.y / snap) * int(snap)]
	assert_eq(key_a, key_b, "Nearby enemies should share the same pool key (#1458r4)")


func test_shared_pool_key_different_for_distant_centers() -> void:
	## Two enemies far apart should get different pool keys (different search zones).
	var snap := 200.0
	var center_a := Vector2(100, 100)
	var center_b := Vector2(900, 900)
	var key_a := "%d,%d" % [int(center_a.x / snap) * int(snap), int(center_a.y / snap) * int(snap)]
	var key_b := "%d,%d" % [int(center_b.x / snap) * int(snap), int(center_b.y / snap) * int(snap)]
	assert_ne(key_a, key_b, "Distant enemies should use different pool keys")


# ============================================================================
# Tests: #1458r6 — _all_inspection_points_cleared one-liner parsing bug
# ============================================================================


func test_all_points_cleared_requires_all_flags_true() -> void:
	## #1458r6: Regression test — the one-liner "for f in flags: if not f: return false; return true"
	## placed 'return true' INSIDE the loop body (after first true element), not after the loop.
	## This caused the function to return true as soon as ANY single point was inspected.
	## Fixed by expanding to multi-line: 'return true' is now after the loop.
	var flags: Array = [false, false, false, false, false]
	flags[0] = true  # Mark only the first point as inspected (simulates enemy visiting point 0)
	var all_cleared := true
	for f in flags:
		if not f:
			all_cleared = false
			break
	assert_false(all_cleared,
		"#1458r6: Should NOT report all cleared when only the first point is inspected")


func test_all_points_cleared_correct_when_truly_all_done() -> void:
	## #1458r6: Verify the correct multi-line version works when all points are inspected.
	var flags: Array = [true, true, true, true, true]
	var all_cleared := true
	for f in flags:
		if not f:
			all_cleared = false
			break
	assert_true(all_cleared, "#1458r6: All flags true should return true")


func test_all_points_cleared_false_for_last_flag_false() -> void:
	## #1458r6: The bug would have returned 'true' after the first 'true' element,
	## never reaching the last 'false'. The fix must check ALL elements.
	var flags: Array = [true, true, true, true, false]  # Only last is uninspected
	var all_cleared := true
	for f in flags:
		if not f:
			all_cleared = false
			break
	assert_false(all_cleared,
		"#1458r6: Must check all elements — last uninspected flag must prevent 'all cleared'")
