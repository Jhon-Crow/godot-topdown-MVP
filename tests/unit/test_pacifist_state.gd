extends GutTest
## Unit tests for PacifistState class.
##
## Tests the pacifist enemy behavior including:
## - Cover finding fallback logic
## - Distance threshold for COVER_REACHED_DISTANCE
## - Cover check interval timing
## - Display name formatting
## - Enter/exit state management


# ============================================================================
# Mock Enemy for PacifistState Tests
# ============================================================================


class MockEnemy:
	extends Node2D

	var velocity: Vector2 = Vector2.ZERO
	var move_speed: float = 100.0
	var debug_logging: bool = false

	## Cover detection support flags.
	var has_find_nearest_cover_position: bool = false
	var has_get_nearest_cover_from_player: bool = false
	var has_find_cover_position: bool = false

	## Cover position to return from cover methods.
	var mock_cover_position: Variant = null

	func has_method(method_name: String) -> bool:
		match method_name:
			"_find_nearest_cover_position":
				return has_find_nearest_cover_position
			"_get_nearest_cover_from_player":
				return has_get_nearest_cover_from_player
			"_find_cover_position":
				return has_find_cover_position
			"_apply_wall_avoidance":
				return false
		return super.has_method(method_name)

	func _get_nearest_cover_from_player() -> Variant:
		return mock_cover_position

	func _find_cover_position() -> Variant:
		return mock_cover_position


# ============================================================================
# Setup / Teardown
# ============================================================================


var _enemy: MockEnemy = null
var _state: PacifistState = null


func before_each() -> void:
	_enemy = MockEnemy.new()
	_state = PacifistState.new(_enemy)


func after_each() -> void:
	_state = null
	if is_instance_valid(_enemy):
		_enemy.free()
	_enemy = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_state_name_is_pacifist() -> void:
	assert_eq(_state.state_name, "pacifist", "PacifistState state_name should be 'pacifist'")


func test_enemy_reference_stored() -> void:
	assert_eq(_state.enemy, _enemy, "PacifistState should store the enemy reference")


# ============================================================================
# Constants Tests
# ============================================================================


func test_cover_check_interval_constant() -> void:
	assert_eq(PacifistState.COVER_CHECK_INTERVAL, 2.0, "COVER_CHECK_INTERVAL should be 2.0 seconds")


func test_cover_reached_distance_constant() -> void:
	assert_eq(PacifistState.COVER_REACHED_DISTANCE, 20.0, "COVER_REACHED_DISTANCE should be 20.0 pixels")


# ============================================================================
# Enter State Tests
# ============================================================================


func test_enter_zeroes_velocity() -> void:
	_enemy.velocity = Vector2(100, 50)

	_state.enter()

	assert_eq(_enemy.velocity, Vector2.ZERO, "enter() should zero enemy velocity")


func test_enter_resets_in_cover_flag() -> void:
	_state.enter()

	assert_false(_state._in_cover, "_in_cover should be false after enter()")


func test_enter_resets_has_cover_target_when_no_cover_method() -> void:
	# Without _find_nearest_cover_position, the fallback sets cover to current pos
	_enemy.has_find_nearest_cover_position = false
	_enemy.global_position = Vector2(50, 50)

	_state.enter()

	# Fallback: no _find_nearest_cover_position means fallback triggers
	# which sets _has_cover_target = true and _in_cover = true
	assert_true(_state._has_cover_target, "Fallback should set _has_cover_target to true")


func test_enter_resets_cover_check_timer() -> void:
	_state.enter()

	assert_almost_eq(_state._cover_check_timer, 0.0, 0.001, "Cover check timer should be 0.0 after enter()")


# ============================================================================
# Exit State Tests
# ============================================================================


func test_exit_resets_in_cover() -> void:
	_state._in_cover = true

	_state.exit()

	assert_false(_state._in_cover, "exit() should set _in_cover to false")


func test_exit_resets_has_cover_target() -> void:
	_state._has_cover_target = true

	_state.exit()

	assert_false(_state._has_cover_target, "exit() should set _has_cover_target to false")


func test_enter_exit_cycle() -> void:
	_state.enter()
	_state.exit()

	assert_false(_state._in_cover, "_in_cover should be false after enter/exit cycle")
	assert_false(_state._has_cover_target, "_has_cover_target should be false after enter/exit cycle")


# ============================================================================
# Cover Finding Fallback Tests
# ============================================================================


func test_fallback_when_no_cover_methods_available() -> void:
	_enemy.has_find_nearest_cover_position = false
	_enemy.has_get_nearest_cover_from_player = false
	_enemy.has_find_cover_position = false
	_enemy.global_position = Vector2(100, 200)

	_state.enter()

	# Fallback: uses current position as cover
	assert_true(_state._has_cover_target, "Should have cover target via fallback")
	assert_true(_state._in_cover, "Should be marked as in cover via fallback")
	assert_eq(_state._target_cover, _enemy.global_position, "Fallback cover should be at current position")


func test_cover_found_via_get_nearest_cover_from_player() -> void:
	_enemy.has_find_nearest_cover_position = true
	_enemy.has_get_nearest_cover_from_player = true
	_enemy.mock_cover_position = Vector2(300, 400)
	_enemy.global_position = Vector2(0, 0)

	_state.enter()

	assert_true(_state._has_cover_target, "Should have cover target when cover position is found")
	assert_false(_state._in_cover, "Should not be in cover yet when cover is far away")
	assert_eq(_state._target_cover, Vector2(300, 400), "Target cover should be the returned position")


func test_cover_found_via_find_cover_position_fallback() -> void:
	_enemy.has_find_nearest_cover_position = true
	_enemy.has_get_nearest_cover_from_player = false
	_enemy.has_find_cover_position = true
	_enemy.mock_cover_position = Vector2(150, 250)
	_enemy.global_position = Vector2(0, 0)

	_state.enter()

	assert_true(_state._has_cover_target, "Should have cover target from _find_cover_position fallback")
	assert_eq(_state._target_cover, Vector2(150, 250), "Target cover should match _find_cover_position result")


func test_null_cover_result_uses_current_position() -> void:
	_enemy.has_find_nearest_cover_position = true
	_enemy.has_get_nearest_cover_from_player = true
	_enemy.mock_cover_position = null
	_enemy.global_position = Vector2(75, 80)

	_state.enter()

	assert_true(_state._has_cover_target, "Should have cover target even when null returned")
	assert_true(_state._in_cover, "Should be in cover when null returned (stay in place)")
	assert_eq(_state._target_cover, _enemy.global_position, "Should use current position when no cover found")


# ============================================================================
# Distance Threshold Tests (COVER_REACHED_DISTANCE = 20.0)
# ============================================================================


func test_reaches_cover_when_distance_below_threshold() -> void:
	_state._has_cover_target = true
	_state._in_cover = false
	_state._target_cover = Vector2(10, 0)
	_enemy.global_position = Vector2(0, 0)
	_enemy.move_speed = 100.0

	_state.process(0.016)

	# Distance is 10.0, which is < 20.0
	assert_true(_state._in_cover, "Should be in cover when distance < COVER_REACHED_DISTANCE (20.0)")
	assert_eq(_enemy.velocity, Vector2.ZERO, "Velocity should be zeroed when cover is reached")


func test_does_not_reach_cover_when_distance_above_threshold() -> void:
	_state._has_cover_target = true
	_state._in_cover = false
	_state._target_cover = Vector2(100, 0)
	_enemy.global_position = Vector2(0, 0)
	_enemy.move_speed = 100.0

	_state.process(0.016)

	# Distance is 100.0, which is >= 20.0
	assert_false(_state._in_cover, "Should not be in cover when distance >= COVER_REACHED_DISTANCE")


func test_boundary_distance_exactly_at_threshold() -> void:
	# At exactly 20.0, the condition is < 20.0, so should NOT trigger cover reached
	_state._has_cover_target = true
	_state._in_cover = false
	_state._target_cover = Vector2(20, 0)
	_enemy.global_position = Vector2(0, 0)

	_state.process(0.016)

	assert_false(_state._in_cover, "Should not be in cover when distance is exactly 20.0")


func test_just_below_threshold_reaches_cover() -> void:
	_state._has_cover_target = true
	_state._in_cover = false
	_state._target_cover = Vector2(19.9, 0)
	_enemy.global_position = Vector2(0, 0)

	_state.process(0.016)

	assert_true(_state._in_cover, "Should be in cover when distance is 19.9 (< 20.0)")


# ============================================================================
# Cover Check Interval Timing Tests
# ============================================================================


func test_cover_check_timer_increments() -> void:
	_state._has_cover_target = false
	_state._in_cover = false
	_state._cover_check_timer = 0.0

	_state.process(0.5)

	assert_almost_eq(_state._cover_check_timer, 0.5, 0.001, "Cover check timer should increment by delta")


func test_cover_check_does_not_trigger_before_interval() -> void:
	_enemy.has_find_nearest_cover_position = false
	_enemy.global_position = Vector2(50, 50)
	_state._has_cover_target = false
	_state._in_cover = false
	_state._cover_check_timer = 1.0

	_state.process(0.5)

	# Timer at 1.5, still below 2.0 interval
	assert_false(_state._has_cover_target, "Cover check should not trigger before COVER_CHECK_INTERVAL")


func test_cover_check_triggers_at_interval() -> void:
	_enemy.has_find_nearest_cover_position = false
	_enemy.global_position = Vector2(50, 50)
	_state._has_cover_target = false
	_state._in_cover = false
	_state._cover_check_timer = 1.5

	_state.process(0.6)

	# Timer at 2.1, exceeds 2.0 — cover check should have fired
	assert_true(_state._has_cover_target, "Cover check should trigger when timer >= COVER_CHECK_INTERVAL")


func test_cover_check_timer_resets_after_check() -> void:
	_enemy.has_find_nearest_cover_position = false
	_enemy.global_position = Vector2(50, 50)
	_state._has_cover_target = false
	_state._in_cover = false
	_state._cover_check_timer = 1.9

	_state.process(0.2)

	# Timer crossed 2.0, should reset to 0.0
	assert_almost_eq(_state._cover_check_timer, 0.0, 0.001, "Cover check timer should reset after triggering")


# ============================================================================
# In Cover Behavior Tests
# ============================================================================


func test_in_cover_zeroes_velocity() -> void:
	_state._has_cover_target = true
	_state._in_cover = true
	_enemy.velocity = Vector2(50, 50)

	_state.process(0.016)

	assert_eq(_enemy.velocity, Vector2.ZERO, "In cover should keep velocity at zero")


func test_no_cover_target_zeroes_velocity() -> void:
	_state._has_cover_target = false
	_state._in_cover = false
	_state._cover_check_timer = 0.0
	_enemy.velocity = Vector2(50, 50)

	_state.process(0.016)

	assert_eq(_enemy.velocity, Vector2.ZERO, "No cover target should zero velocity (stay in place)")


# ============================================================================
# Process Return Value Tests
# ============================================================================


func test_process_always_returns_null() -> void:
	_state._has_cover_target = true
	_state._in_cover = false
	_state._target_cover = Vector2(500, 0)
	_enemy.global_position = Vector2(0, 0)

	var result: EnemyState = _state.process(0.016)

	assert_eq(result, null, "PacifistState process() should always return null (stays in pacifist)")


func test_process_returns_null_when_in_cover() -> void:
	_state._has_cover_target = true
	_state._in_cover = true

	var result: EnemyState = _state.process(0.016)

	assert_eq(result, null, "process() should return null when in cover")


# ============================================================================
# is_in_cover Tests
# ============================================================================


func test_is_in_cover_returns_false_initially() -> void:
	var state := PacifistState.new(_enemy)

	assert_false(state.is_in_cover(), "is_in_cover() should return false before entering state")


func test_is_in_cover_returns_true_when_in_cover() -> void:
	_state._in_cover = true

	assert_true(_state.is_in_cover(), "is_in_cover() should return true when _in_cover is true")


func test_is_in_cover_returns_false_when_not_in_cover() -> void:
	_state._in_cover = false

	assert_false(_state.is_in_cover(), "is_in_cover() should return false when _in_cover is false")


# ============================================================================
# Display Name Formatting Tests
# ============================================================================


func test_display_name_default() -> void:
	_state._in_cover = false
	_state._has_cover_target = false

	var name: String = _state.get_display_name()

	assert_eq(name, "pacifist", "Display name should be 'pacifist' with no cover target")


func test_display_name_in_cover() -> void:
	_state._in_cover = true
	_state._has_cover_target = true

	var name: String = _state.get_display_name()

	assert_eq(name, "pacifist (in cover)", "Display name should be 'pacifist (in cover)' when in cover")


func test_display_name_seeking_cover() -> void:
	_state._in_cover = false
	_state._has_cover_target = true

	var name: String = _state.get_display_name()

	assert_eq(name, "pacifist (seeking cover)", "Display name should be 'pacifist (seeking cover)' when seeking")


# ============================================================================
# Movement Toward Cover Tests
# ============================================================================


func test_moves_toward_cover_when_not_reached() -> void:
	_state._has_cover_target = true
	_state._in_cover = false
	_state._target_cover = Vector2(200, 0)
	_enemy.global_position = Vector2(0, 0)
	_enemy.move_speed = 100.0

	_state.process(0.016)

	assert_gt(_enemy.velocity.x, 0.0, "Should move toward cover in the positive x direction")
	assert_almost_eq(_enemy.velocity.length(), 100.0, 0.1, "Velocity magnitude should equal move_speed")
