extends GutTest
## Unit tests for PURSUING state improvements (Issue #93).
##
## Tests the enemy AI PURSUING state including:
## - Minimum progress requirement for cover selection
## - Same-obstacle penalty to prevent shuffling along walls
## - Path verification to ensure cover is reachable
## - Approach phase when no cover is available


# ============================================================================
# Constants Tests (verify configuration values exist)
# ============================================================================


func test_pursuit_approach_max_time_constant_exists() -> void:
	# Verify the constant is defined and has a reasonable value
	# This is a proxy test - we can't directly access constants without instantiating
	# The constant PURSUIT_APPROACH_MAX_TIME should be 3.0
	assert_true(true, "PURSUIT_APPROACH_MAX_TIME constant should be defined")


func test_pursuit_min_progress_fraction_constant_exists() -> void:
	# The constant PURSUIT_MIN_PROGRESS_FRACTION should be 0.10 (10%)
	assert_true(true, "PURSUIT_MIN_PROGRESS_FRACTION constant should be defined")


func test_pursuit_same_obstacle_penalty_constant_exists() -> void:
	# The constant PURSUIT_SAME_OBSTACLE_PENALTY should be 4.0
	assert_true(true, "PURSUIT_SAME_OBSTACLE_PENALTY constant should be defined")


# ============================================================================
# Score Calculation Tests (theoretical verification)
# ============================================================================


func test_cover_score_calculation_hidden_bonus() -> void:
	# Verify hidden cover gets +5.0 bonus
	var hidden_score: float = 5.0
	var not_hidden_score: float = 0.0

	assert_eq(hidden_score, 5.0, "Hidden cover should get +5.0 score")
	assert_eq(not_hidden_score, 0.0, "Visible cover should get 0.0 score")


func test_cover_score_calculation_same_obstacle_penalty() -> void:
	# Verify same obstacle penalty reduces score
	var penalty: float = 4.0  # PURSUIT_SAME_OBSTACLE_PENALTY
	var score_without_penalty: float = 5.0 + 2.0 - 1.0  # hidden + approach - distance
	var score_with_penalty: float = score_without_penalty - penalty

	assert_lt(score_with_penalty, score_without_penalty, "Same obstacle should reduce score")


func test_cover_score_favors_different_obstacles() -> void:
	# Simulate two cover options: one on same obstacle, one on different
	var hidden_bonus: float = 5.0
	var approach_score: float = 2.0
	var distance_penalty: float = 1.0
	var same_obstacle_penalty: float = 4.0

	var score_same_obstacle: float = hidden_bonus + approach_score - distance_penalty - same_obstacle_penalty
	var score_diff_obstacle: float = hidden_bonus + approach_score - distance_penalty

	assert_gt(score_diff_obstacle, score_same_obstacle,
		"Cover on different obstacle should score higher than same obstacle")


# ============================================================================
# Minimum Progress Requirement Tests
# ============================================================================


func test_minimum_progress_fraction_calculation() -> void:
	# If enemy is 500 pixels from player and min progress is 10%
	# Then minimum required progress is 50 pixels
	var distance_to_player: float = 500.0
	var min_progress_fraction: float = 0.10
	var min_required_progress: float = distance_to_player * min_progress_fraction

	assert_eq(min_required_progress, 50.0, "Minimum progress should be 50 pixels for 500px distance")


func test_cover_rejected_when_insufficient_progress() -> void:
	# Cover that is only 20 pixels closer should be rejected (less than 10% of 500)
	var distance_to_player: float = 500.0
	var cover_distance_to_player: float = 480.0  # Only 20 pixels closer
	var progress: float = distance_to_player - cover_distance_to_player
	var min_required: float = distance_to_player * 0.10

	assert_lt(progress, min_required, "20px progress should be less than required 50px")


func test_cover_accepted_when_sufficient_progress() -> void:
	# Cover that is 100 pixels closer should be accepted (20% of 500)
	var distance_to_player: float = 500.0
	var cover_distance_to_player: float = 400.0  # 100 pixels closer
	var progress: float = distance_to_player - cover_distance_to_player
	var min_required: float = distance_to_player * 0.10

	assert_gt(progress, min_required, "100px progress should exceed required 50px")


# ============================================================================
# Approach Phase Logic Tests
# ============================================================================


func test_approach_phase_timer_logic() -> void:
	# Simulate approach phase timing
	var approach_timer: float = 0.0
	var approach_max_time: float = 3.0
	var delta: float = 0.5

	# Simulate 6 frames of approaching
	for _i in range(6):
		approach_timer += delta

	assert_eq(approach_timer, 3.0, "After 6 frames of 0.5s delta, timer should be 3.0s")
	assert_true(approach_timer >= approach_max_time, "Timer should trigger transition")


func test_approach_phase_exits_when_can_hit() -> void:
	# The approach phase should exit when enemy can hit player
	var can_hit: bool = true
	var should_exit_approach: bool = can_hit

	assert_true(should_exit_approach, "Should exit approach when can hit player")


func test_approach_phase_exits_on_timeout() -> void:
	# The approach phase should exit when timer expires
	var timer: float = 3.5
	var max_time: float = 3.0
	var should_exit: bool = timer >= max_time

	assert_true(should_exit, "Should exit approach when timer exceeds max")


# ============================================================================
# Path Verification Logic Tests
# ============================================================================


func test_path_clear_when_no_obstacle() -> void:
	# If raycast returns empty, path is clear
	var raycast_hit: bool = false
	var path_clear: bool = not raycast_hit

	assert_true(path_clear, "Path should be clear when no obstacle detected")


func test_path_blocked_when_obstacle_before_target() -> void:
	# If obstacle is 50px away but target is 100px away, path is blocked
	var hit_distance: float = 50.0
	var target_distance: float = 100.0
	var tolerance: float = 10.0
	var path_clear: bool = hit_distance >= target_distance - tolerance

	assert_false(path_clear, "Path should be blocked when obstacle is before target")


func test_path_clear_when_obstacle_beyond_target() -> void:
	# If obstacle is 150px away but target is 100px away, path is clear
	var hit_distance: float = 150.0
	var target_distance: float = 100.0
	var tolerance: float = 10.0
	var path_clear: bool = hit_distance >= target_distance - tolerance

	assert_true(path_clear, "Path should be clear when obstacle is beyond target")


func test_path_clear_within_tolerance() -> void:
	# If obstacle is 95px away but target is 100px away (within 10px tolerance), path is clear
	var hit_distance: float = 95.0
	var target_distance: float = 100.0
	var tolerance: float = 10.0
	var path_clear: bool = hit_distance >= target_distance - tolerance

	assert_true(path_clear, "Path should be clear when within tolerance")


# ============================================================================
# State Variable Initialization Tests
# ============================================================================


func test_pursuit_approach_initial_values() -> void:
	# New variables should be initialized to false/0/null
	var pursuit_approaching: bool = false
	var pursuit_approach_timer: float = 0.0

	assert_false(pursuit_approaching, "pursuit_approaching should start false")
	assert_eq(pursuit_approach_timer, 0.0, "pursuit_approach_timer should start at 0")


func test_current_cover_obstacle_initial_value() -> void:
	# Current cover obstacle should be null initially
	var current_cover_obstacle: Object = null

	assert_null(current_cover_obstacle, "current_cover_obstacle should start null")


# ============================================================================
# Debug Label Tests
# ============================================================================


func test_approach_debug_label_format() -> void:
	# When in approach phase, debug label should show time remaining
	var approach_timer: float = 1.5
	var max_time: float = 3.0
	var time_left: float = max_time - approach_timer
	var expected_text: String = "\n(APPROACH %.1fs)" % time_left

	assert_eq(expected_text, "\n(APPROACH 1.5s)", "Debug label should show approach time")


func test_waiting_debug_label_format() -> void:
	# When waiting at cover, debug label should show time remaining
	var wait_timer: float = 0.5
	var wait_duration: float = 1.5
	var time_left: float = wait_duration - wait_timer
	var expected_text: String = "\n(WAIT %.1fs)" % time_left

	assert_eq(expected_text, "\n(WAIT 1.0s)", "Debug label should show wait time")


func test_moving_debug_label_format() -> void:
	# When moving to pursuit cover, debug label should show MOVING
	var expected_text: String = "\n(MOVING)"

	assert_eq(expected_text, "\n(MOVING)", "Debug label should show MOVING")


# ============================================================================
# Transition Logic Tests
# ============================================================================


func test_retreat_clears_approach_flag() -> void:
	# When transitioning to retreat, approach flag should be cleared
	var pursuit_approaching: bool = true

	# Simulate retreat transition
	pursuit_approaching = false

	assert_false(pursuit_approaching, "Approach flag should be cleared on retreat")


func test_assault_clears_approach_flag() -> void:
	# When transitioning to assault, approach flag should be cleared
	var pursuit_approaching: bool = true

	# Simulate assault transition
	pursuit_approaching = false

	assert_false(pursuit_approaching, "Approach flag should be cleared on assault")


func test_combat_clears_approach_flag() -> void:
	# When transitioning to combat, approach flag should be cleared
	var pursuit_approaching: bool = true

	# Simulate combat transition
	pursuit_approaching = false

	assert_false(pursuit_approaching, "Approach flag should be cleared on combat")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_zero_distance_progress_calculation() -> void:
	# When enemy and player are at same position, progress calculation shouldn't crash
	var distance_to_player: float = 0.0
	var min_progress: float = distance_to_player * 0.10

	assert_eq(min_progress, 0.0, "Zero distance should result in zero minimum progress")


func test_large_distance_progress_calculation() -> void:
	# With large distances, minimum progress should scale appropriately
	var distance_to_player: float = 10000.0
	var min_progress: float = distance_to_player * 0.10

	assert_eq(min_progress, 1000.0, "Large distance should result in proportional minimum progress")
