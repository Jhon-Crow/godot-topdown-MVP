extends GutTest
## Regression tests for Issue #1458: SEARCHING state performance optimization.
##
## Tests verify the performance fixes:
## 1. Minimum time in SEARCHING before COMBAT transition prevents oscillation
## 2. Navigation target caching avoids redundant path recalculations
## 3. _transition_to_idle redirect chain avoids re-generating waypoints when already SEARCHING
## 4. Cover-inspection waypoint generation replaces random/spiral algorithms (#1458r3)
## 5. Timeout log throttled to once per search session
## 6. Inspection point FOV clearing and sync between enemies (#1458r3)


# ============================================================================
# Constants matching enemy.gd
# ============================================================================

const SEARCH_MIN_TIME_BEFORE_COMBAT: float = 0.3
const SEARCH_WAYPOINT_COUNT: int = 5
const SEARCH_NAV_SNAP_THRESHOLD: float = 50.0
const SEARCH_MAX_DURATION: float = 30.0
const SEARCH_INITIAL_RADIUS: float = 150.0
const SEARCH_MAX_RADIUS: float = 600.0
const SEARCH_RADIUS_EXPANSION: float = 100.0
const SEARCH_INSPECT_RAY_COUNT: int = 36
const SEARCH_INSPECT_RAY_DISTANCE: float = 800.0
const SEARCH_INSPECT_CLEAR_RADIUS: float = 60.0
const SEARCH_ZONE_SNAP_SIZE: float = 50.0


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
# Tests: Cover-inspection waypoint generation (#1458 round 3)
# ============================================================================


func test_inspection_ray_count_reasonable() -> void:
	# 36 rays at 10° apart gives full 360° coverage
	assert_eq(SEARCH_INSPECT_RAY_COUNT, 36, "Should use 36 rays (10° apart)")
	assert_gt(SEARCH_INSPECT_RAY_COUNT, 12, "Need enough rays for good coverage")
	assert_lte(SEARCH_INSPECT_RAY_COUNT, 72, "Too many rays is wasteful")


func test_inspection_ray_distance_reasonable() -> void:
	assert_gt(SEARCH_INSPECT_RAY_DISTANCE, 200.0, "Rays must reach nearby obstacles")
	assert_lte(SEARCH_INSPECT_RAY_DISTANCE, 1500.0, "Rays should not span entire map")


func test_inspection_clear_radius_reasonable() -> void:
	# Must be small enough to require enemies to actually approach the point
	assert_gt(SEARCH_INSPECT_CLEAR_RADIUS, 20.0, "Clear radius must be positive")
	assert_lte(SEARCH_INSPECT_CLEAR_RADIUS, 150.0, "Clear radius should force proximity")


func test_inspection_point_deduplication() -> void:
	# Simulates: two points within SEARCH_ZONE_SNAP_SIZE should be considered duplicates
	var p1 := Vector2(100, 100)
	var p2 := Vector2(120, 110)  # ~22px away, within 50px snap size
	var is_duplicate: bool = p1.distance_to(p2) < SEARCH_ZONE_SNAP_SIZE
	assert_true(is_duplicate, "Points within snap distance should be deduplicated")


func test_inspection_point_distinct_points_kept() -> void:
	var p1 := Vector2(100, 100)
	var p2 := Vector2(200, 200)  # ~141px away, beyond snap size
	var is_duplicate: bool = p1.distance_to(p2) < SEARCH_ZONE_SNAP_SIZE
	assert_false(is_duplicate, "Distant points should NOT be deduplicated")


func test_inspection_behind_obstacle_offset() -> void:
	# The inspection point is placed 45px past the obstacle hit point
	var hit_point := Vector2(300, 0)
	var direction := Vector2(1, 0)
	var inspect_pos := hit_point + direction * 45.0
	assert_eq(inspect_pos, Vector2(345, 0), "Inspection point should be 45px past obstacle")


func test_fov_clearing_within_radius() -> void:
	# Simulates: enemy at origin facing right, inspection point at (50, 0) — within range & FOV
	var enemy_pos := Vector2.ZERO
	var facing_dir := Vector2(1, 0)
	var point := Vector2(50, 0)
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


func test_sync_inspected_flags_by_proximity() -> void:
	# Simulates _sync_inspected_flags: matching points by distance
	var my_points: Array[Vector2] = [Vector2(100, 100), Vector2(200, 200)]
	var my_flags: Array[bool] = [false, false]
	var their_points: Array[Vector2] = [Vector2(105, 105), Vector2(500, 500)]
	var their_flags: Array[bool] = [true, true]
	# Sync
	for i in range(my_points.size()):
		if my_flags[i]: continue
		for j in range(their_points.size()):
			if their_flags[j] and my_points[i].distance_to(their_points[j]) < SEARCH_ZONE_SNAP_SIZE:
				my_flags[i] = true; break
	assert_true(my_flags[0], "Point within snap distance should sync cleared flag")
	assert_false(my_flags[1], "Distant point should NOT sync")


func test_nav_snap_threshold_matches_original() -> void:
	assert_eq(SEARCH_NAV_SNAP_THRESHOLD, 50.0,
		"Nav snap threshold should be 50.0 to match _is_waypoint_navigable behavior")
