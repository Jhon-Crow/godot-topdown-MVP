extends GutTest
## Unit tests for IdleState class.
##
## Tests the idle enemy behavior including:
## - State name initialization
## - Patrol point cycling with modulo wraparound
## - Patrol wait timer logic
## - Distance threshold for reaching patrol points
## - Guard mode behavior
## - Transition conditions (can_see_player, under_fire)


# ============================================================================
# Mock Enemy for IdleState Tests
# ============================================================================


class MockEnemy:
	extends Node2D

	## Behavior modes matching enemy.gd enum.
	enum BehaviorMode { PATROL, GUARD }

	var behavior_mode: int = BehaviorMode.PATROL
	var velocity: Vector2 = Vector2.ZERO
	var move_speed: float = 100.0

	## Patrol variables.
	var _patrol_points: Array = []
	var _current_patrol_index: int = 0
	var _is_waiting_at_patrol_point: bool = false
	var _patrol_wait_timer: float = 0.0
	var patrol_wait_time: float = 3.0

	## Detection variables.
	var _can_see_player: bool = false
	var _under_fire: bool = false
	var _threat_reaction_delay_elapsed: bool = false

	## Tracking calls to reset methods.
	var reset_alarm_called: bool = false
	var reset_encounter_hits_called: bool = false

	func _reset_alarm_mode() -> void:
		reset_alarm_called = true

	func _reset_encounter_hits() -> void:
		reset_encounter_hits_called = true


# ============================================================================
# Setup / Teardown
# ============================================================================


var _enemy: MockEnemy = null
var _state: IdleState = null


func before_each() -> void:
	_enemy = MockEnemy.new()
	_state = IdleState.new(_enemy)


func after_each() -> void:
	_state = null
	if is_instance_valid(_enemy):
		_enemy.free()
	_enemy = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_state_name_is_idle() -> void:
	assert_eq(_state.state_name, "idle", "IdleState state_name should be 'idle'")


func test_enemy_reference_stored() -> void:
	assert_eq(_state.enemy, _enemy, "IdleState should store the enemy reference")


# ============================================================================
# Enter Tests
# ============================================================================


func test_enter_resets_alarm_mode() -> void:
	_state.enter()

	assert_true(_enemy.reset_alarm_called, "enter() should call _reset_alarm_mode on the enemy")


func test_enter_resets_encounter_hits() -> void:
	_state.enter()

	assert_true(_enemy.reset_encounter_hits_called, "enter() should call _reset_encounter_hits on the enemy")


# ============================================================================
# Patrol Point Cycling Tests
# ============================================================================


func test_patrol_index_wraps_around_with_modulo() -> void:
	_enemy._patrol_points = [Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)]
	_enemy._current_patrol_index = 2
	_enemy._is_waiting_at_patrol_point = true
	_enemy._patrol_wait_timer = 0.0
	_enemy.patrol_wait_time = 1.0

	# Simulate enough delta to exceed wait time
	_state.process(1.1)

	assert_eq(_enemy._current_patrol_index, 0, "Patrol index should wrap to 0 after last point")


func test_patrol_index_advances_sequentially() -> void:
	_enemy._patrol_points = [Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)]
	_enemy._current_patrol_index = 0
	_enemy._is_waiting_at_patrol_point = true
	_enemy._patrol_wait_timer = 0.0
	_enemy.patrol_wait_time = 1.0

	_state.process(1.1)

	assert_eq(_enemy._current_patrol_index, 1, "Patrol index should advance from 0 to 1")


func test_patrol_index_wraps_with_two_points() -> void:
	_enemy._patrol_points = [Vector2(0, 0), Vector2(100, 0)]
	_enemy._current_patrol_index = 1
	_enemy._is_waiting_at_patrol_point = true
	_enemy._patrol_wait_timer = 0.0
	_enemy.patrol_wait_time = 0.5

	_state.process(0.6)

	assert_eq(_enemy._current_patrol_index, 0, "Patrol index should wrap from 1 to 0 with two points")


# ============================================================================
# Patrol Wait Timer Tests
# ============================================================================


func test_patrol_wait_timer_increments() -> void:
	_enemy._patrol_points = [Vector2(0, 0), Vector2(100, 0)]
	_enemy._is_waiting_at_patrol_point = true
	_enemy._patrol_wait_timer = 0.0
	_enemy.patrol_wait_time = 5.0

	_state.process(0.5)

	assert_almost_eq(_enemy._patrol_wait_timer, 0.5, 0.001, "Patrol wait timer should increment by delta")


func test_patrol_wait_timer_does_not_transition_early() -> void:
	_enemy._patrol_points = [Vector2(0, 0), Vector2(100, 0)]
	_enemy._current_patrol_index = 0
	_enemy._is_waiting_at_patrol_point = true
	_enemy._patrol_wait_timer = 0.0
	_enemy.patrol_wait_time = 3.0

	_state.process(2.0)

	assert_true(_enemy._is_waiting_at_patrol_point, "Should still be waiting when timer < patrol_wait_time")
	assert_eq(_enemy._current_patrol_index, 0, "Patrol index should not change before wait completes")


func test_patrol_wait_timer_resets_after_transition() -> void:
	_enemy._patrol_points = [Vector2(0, 0), Vector2(100, 0)]
	_enemy._current_patrol_index = 0
	_enemy._is_waiting_at_patrol_point = true
	_enemy._patrol_wait_timer = 0.0
	_enemy.patrol_wait_time = 1.0

	_state.process(1.5)

	assert_almost_eq(_enemy._patrol_wait_timer, 0.0, 0.001, "Wait timer should reset after transitioning to next point")
	assert_false(_enemy._is_waiting_at_patrol_point, "Should no longer be waiting after timer exceeds wait time")


# ============================================================================
# Distance Threshold Tests
# ============================================================================


func test_reaches_patrol_point_when_distance_below_threshold() -> void:
	_enemy._patrol_points = [Vector2(5, 0)]
	_enemy._current_patrol_index = 0
	_enemy._is_waiting_at_patrol_point = false
	_enemy.global_position = Vector2(0, 0)

	_state.process(0.016)

	assert_true(_enemy._is_waiting_at_patrol_point, "Should start waiting when distance to patrol point < 10.0")
	assert_eq(_enemy.velocity, Vector2.ZERO, "Velocity should be zeroed when reaching patrol point")


func test_does_not_reach_patrol_point_when_distance_above_threshold() -> void:
	_enemy._patrol_points = [Vector2(100, 0)]
	_enemy._current_patrol_index = 0
	_enemy._is_waiting_at_patrol_point = false
	_enemy.global_position = Vector2(0, 0)

	_state.process(0.016)

	assert_false(_enemy._is_waiting_at_patrol_point, "Should not wait when distance to patrol point >= 10.0")


func test_boundary_distance_exactly_at_threshold() -> void:
	# At exactly 10.0, the condition is < 10.0, so should NOT trigger waiting
	_enemy._patrol_points = [Vector2(10, 0)]
	_enemy._current_patrol_index = 0
	_enemy._is_waiting_at_patrol_point = false
	_enemy.global_position = Vector2(0, 0)

	_state.process(0.016)

	assert_false(_enemy._is_waiting_at_patrol_point, "Should not wait when distance is exactly 10.0 (threshold is strictly < 10.0)")


func test_just_below_threshold_triggers_waiting() -> void:
	_enemy._patrol_points = [Vector2(9.9, 0)]
	_enemy._current_patrol_index = 0
	_enemy._is_waiting_at_patrol_point = false
	_enemy.global_position = Vector2(0, 0)

	_state.process(0.016)

	assert_true(_enemy._is_waiting_at_patrol_point, "Should wait when distance is 9.9 (< 10.0)")


# ============================================================================
# Guard Mode Tests
# ============================================================================


func test_guard_mode_zeroes_velocity() -> void:
	_enemy.behavior_mode = MockEnemy.BehaviorMode.GUARD
	_enemy.velocity = Vector2(50, 50)

	_state.process(0.016)

	assert_eq(_enemy.velocity, Vector2.ZERO, "Guard mode should set velocity to Vector2.ZERO")


func test_guard_mode_keeps_velocity_zero_over_multiple_frames() -> void:
	_enemy.behavior_mode = MockEnemy.BehaviorMode.GUARD

	_state.process(0.016)
	_state.process(0.016)
	_state.process(0.016)

	assert_eq(_enemy.velocity, Vector2.ZERO, "Guard mode should keep velocity at zero across frames")


# ============================================================================
# Empty Patrol Points Tests
# ============================================================================


func test_patrol_with_empty_points_does_not_crash() -> void:
	_enemy._patrol_points = []
	_enemy.behavior_mode = MockEnemy.BehaviorMode.PATROL

	_state.process(0.016)

	assert_true(true, "Patrol with empty points should not crash")


# ============================================================================
# Transition Condition Tests
# ============================================================================


func test_process_returns_null_when_can_see_player() -> void:
	_enemy._can_see_player = true

	var result: EnemyState = _state.process(0.016)

	assert_eq(result, null, "process() should return null when player is visible (transition signal)")


func test_process_returns_null_when_under_fire_and_delay_elapsed() -> void:
	_enemy._under_fire = true
	_enemy._threat_reaction_delay_elapsed = true

	var result: EnemyState = _state.process(0.016)

	assert_eq(result, null, "process() should return null when under fire with delay elapsed")


func test_process_returns_null_when_under_fire_but_delay_not_elapsed() -> void:
	_enemy._under_fire = true
	_enemy._threat_reaction_delay_elapsed = false
	_enemy.behavior_mode = MockEnemy.BehaviorMode.GUARD

	var result: EnemyState = _state.process(0.016)

	assert_eq(result, null, "process() should return null even when delay not elapsed (idle stays idle)")


func test_process_returns_null_in_normal_patrol() -> void:
	_enemy._can_see_player = false
	_enemy._under_fire = false
	_enemy._patrol_points = [Vector2(500, 0)]
	_enemy.global_position = Vector2(0, 0)

	var result: EnemyState = _state.process(0.016)

	assert_eq(result, null, "process() should return null during normal patrol")


# ============================================================================
# Patrol Movement Tests
# ============================================================================


func test_patrol_sets_velocity_toward_target() -> void:
	_enemy._patrol_points = [Vector2(200, 0)]
	_enemy._current_patrol_index = 0
	_enemy._is_waiting_at_patrol_point = false
	_enemy.global_position = Vector2(0, 0)
	_enemy.move_speed = 100.0

	_state.process(0.016)

	assert_gt(_enemy.velocity.x, 0.0, "Velocity x should be positive when moving toward point at (200, 0)")
	assert_almost_eq(_enemy.velocity.length(), 100.0, 0.1, "Velocity magnitude should equal move_speed")
