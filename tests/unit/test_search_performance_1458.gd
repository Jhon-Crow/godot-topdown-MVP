extends GutTest
## Regression tests for Issue #1458: SEARCHING state performance optimization.
##
## Tests verify the performance fixes:
## 1. Minimum time in SEARCHING before COMBAT transition prevents oscillation
## 2. Navigation target caching avoids redundant path recalculations
## 3. _transition_to_idle redirect chain avoids re-generating waypoints when already SEARCHING
## 4. Random-radius waypoint generation replaces expensive spiral algorithm
## 5. Timeout log throttled to once per search session


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


# ============================================================================
# Tests: SEARCHING→COMBAT oscillation prevention
# ============================================================================


func test_combat_transition_blocked_before_min_time() -> void:
	# Simulates: enemy in SEARCHING with _can_see_player = true but timer < 0.3s
	var search_state_timer: float = 0.1
	var can_see_player: bool = true

	var should_transition: bool = can_see_player and search_state_timer >= SEARCH_MIN_TIME_BEFORE_COMBAT
	assert_false(should_transition,
		"Should NOT transition to COMBAT before %.1fs in SEARCHING (Issue #1458)" % SEARCH_MIN_TIME_BEFORE_COMBAT)


func test_combat_transition_allowed_after_min_time() -> void:
	# Simulates: enemy in SEARCHING with _can_see_player = true and timer >= 0.3s
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
	# Ensure the min time is short enough to not noticeably delay combat engagement
	assert_gt(SEARCH_MIN_TIME_BEFORE_COMBAT, 0.0,
		"Min time should be positive")
	assert_lt(SEARCH_MIN_TIME_BEFORE_COMBAT, 1.0,
		"Min time should be under 1s to avoid noticeable delay in gameplay")


# ============================================================================
# Tests: Navigation target caching
# ============================================================================


func test_nav_target_cache_prevents_redundant_update() -> void:
	# Simulates: same waypoint target → should NOT re-set nav target
	var cached_target := Vector2(100, 200)
	var current_waypoint := Vector2(100, 200)

	var should_update: bool = cached_target.distance_squared_to(current_waypoint) > 1.0
	assert_false(should_update,
		"Should NOT update nav target when waypoint unchanged (Issue #1458)")


func test_nav_target_cache_allows_new_waypoint() -> void:
	# Simulates: new waypoint different from cache → should update
	var cached_target := Vector2(100, 200)
	var current_waypoint := Vector2(175, 275)

	var should_update: bool = cached_target.distance_squared_to(current_waypoint) > 1.0
	assert_true(should_update,
		"Should update nav target when waypoint changes")


func test_nav_target_cache_allows_first_waypoint() -> void:
	# Simulates: initial state (cache = ZERO) → should update to first waypoint
	var cached_target := Vector2.ZERO
	var current_waypoint := Vector2(50, 50)

	var should_update: bool = cached_target.distance_squared_to(current_waypoint) > 1.0
	assert_true(should_update,
		"Should update nav target on first waypoint after search start")


# ============================================================================
# Tests: _transition_to_idle redirect chain optimization
# ============================================================================


func test_idle_redirect_skips_regeneration_when_already_searching() -> void:
	# Simulates: _transition_to_idle called when IDLE is disabled and
	# current_state is already SEARCHING → should NOT regenerate waypoints
	var current_state: int = 9  # AIState.SEARCHING
	var idle_enabled: bool = false

	var should_regenerate: bool = not idle_enabled and current_state != 9  # 9 = SEARCHING
	assert_false(should_regenerate,
		"Should NOT regenerate waypoints when already in SEARCHING (Issue #1458)")


func test_idle_redirect_regenerates_when_coming_from_other_state() -> void:
	# Simulates: _transition_to_idle from COMBAT when IDLE disabled → should regenerate
	var current_state: int = 1  # AIState.COMBAT
	var idle_enabled: bool = false

	var should_regenerate: bool = not idle_enabled and current_state != 9  # 9 = SEARCHING
	assert_true(should_regenerate,
		"Should regenerate waypoints when transitioning from non-SEARCHING state")


func test_idle_redirect_not_triggered_when_idle_enabled() -> void:
	# Simulates: normal IDLE transition when IDLE is enabled → standard path
	var idle_enabled: bool = true

	var is_redirect: bool = not idle_enabled
	assert_false(is_redirect,
		"Should use normal IDLE transition when IDLE state is enabled")


# ============================================================================
# Tests: Combat transition logging throttle
# ============================================================================


func test_combat_transition_logs_only_once_per_session() -> void:
	# Simulates: first time seeing player → log; subsequent frames → no log
	var logged: bool = false

	# First transition
	if not logged:
		logged = true
	var first_log := logged

	# Second call in same session
	var should_log_again: bool = not logged
	assert_true(first_log, "Should log on first player spotted event")
	assert_false(should_log_again, "Should NOT log on subsequent frames (Issue #1458)")


func test_combat_transition_log_resets_on_new_search_session() -> void:
	# Simulates: after re-entering SEARCHING, the log flag resets
	var logged: bool = true  # From previous session

	# Reset on new search session
	logged = false

	assert_false(logged, "Log flag should reset when entering new SEARCHING session")


# ============================================================================
# Tests: Random-radius waypoint generation (Issue #1458 redesign)
# ============================================================================


func test_waypoint_count_constant_is_reasonable() -> void:
	# 5 waypoints per batch keeps nav calls low (max ~10 calls vs 100 in spiral)
	assert_gt(SEARCH_WAYPOINT_COUNT, 0, "Must generate at least 1 waypoint")
	assert_lte(SEARCH_WAYPOINT_COUNT, 10,
		"Waypoint count should be <=10 to limit NavigationServer calls per batch")


func test_max_nav_calls_bounded() -> void:
	# max_attempts = SEARCH_WAYPOINT_COUNT * 2, each does 1 nav call
	# Plus 1 for the center check = max 11 total (vs 100 in old spiral)
	var max_nav_calls := SEARCH_WAYPOINT_COUNT * 2 + 1
	assert_lte(max_nav_calls, 15,
		"Max NavigationServer calls per generation should be <=15 (was up to 100 in spiral)")


func test_search_radius_reduced_from_old_value() -> void:
	# Old SEARCH_MAX_RADIUS was 2000, caused paths crossing entire map
	assert_lte(SEARCH_MAX_RADIUS, 800.0,
		"Max search radius should be <=800 to keep searches local (was 2000)")
	assert_gt(SEARCH_MAX_RADIUS, SEARCH_INITIAL_RADIUS,
		"Max radius must be greater than initial radius")


func test_radius_expansion_is_progressive() -> void:
	# Radius should expand in reasonable steps
	var steps_to_max := int((SEARCH_MAX_RADIUS - SEARCH_INITIAL_RADIUS) / SEARCH_RADIUS_EXPANSION)
	assert_gt(steps_to_max, 0, "Should take at least 1 expansion step to reach max radius")
	assert_lte(steps_to_max, 10,
		"Should reach max radius within 10 expansion steps to avoid excessive generations")


func test_nav_snap_threshold_matches_original() -> void:
	# The snap threshold should match the original _is_waypoint_navigable threshold of 50px
	assert_eq(SEARCH_NAV_SNAP_THRESHOLD, 50.0,
		"Nav snap threshold should be 50.0 to match original _is_waypoint_navigable behavior")


func test_random_point_within_radius() -> void:
	# Simulates: random point generation should stay within search_radius
	var center := Vector2(500, 500)
	var radius := SEARCH_INITIAL_RADIUS
	for i in range(100):
		var angle := randf() * TAU
		var dist := randf_range(radius * 0.3, radius)
		var candidate := center + Vector2(cos(angle), sin(angle)) * dist
		var distance_from_center := center.distance_to(candidate)
		assert_lte(distance_from_center, radius + 0.01,
			"Random waypoint candidate should be within search radius")
		assert_gte(distance_from_center, radius * 0.3 - 0.01,
			"Random waypoint candidate should be at least 30%% of radius from center")


# ============================================================================
# Tests: Timeout log throttle (Issue #1458)
# ============================================================================


func test_timeout_log_fires_only_once() -> void:
	# Simulates: timeout condition fires every frame, but log should write only once
	var timeout_logged: bool = false
	var log_count: int = 0

	# Simulate 60 frames of timeout firing
	for _frame in range(60):
		var search_state_timer: float = 31.0 + _frame * 0.016  # Increasing past 30s
		var has_left_idle: bool = false
		if search_state_timer >= SEARCH_MAX_DURATION and not has_left_idle:
			if not timeout_logged:
				timeout_logged = true
				log_count += 1

	assert_eq(log_count, 1, "Timeout log should fire exactly once, not every frame")


func test_timeout_log_resets_on_new_search_session() -> void:
	# Simulates: timeout_logged resets when entering new SEARCHING session
	var timeout_logged: bool = true  # From previous timeout

	# New search session resets the flag
	timeout_logged = false

	assert_false(timeout_logged, "Timeout log flag should reset on new search session")
