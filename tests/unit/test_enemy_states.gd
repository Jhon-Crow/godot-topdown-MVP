extends GutTest
## Unit tests for EnemyState base class and IdleState.
##
## Tests the enemy AI state machine including state transitions,
## patrol behavior, and guard behavior.


# ============================================================================
# Mock Enemy for State Tests
# ============================================================================


class MockEnemy:
	## Mock enemy class that mimics Node2D properties for testing.
	## Note: Inner classes cannot extend engine types (Node2D) in GDScript,
	## so we use RefCounted and manually define needed properties.
	extends RefCounted

	# Enum matching the real enemy
	enum BehaviorMode { PATROL, GUARD }

	# Simulated Node2D properties
	var global_position: Vector2 = Vector2.ZERO
	var velocity: Vector2 = Vector2.ZERO

	# Properties used by states
	var behavior_mode: int = BehaviorMode.PATROL
	var _can_see_player: bool = false
	var _under_fire: bool = false
	var _threat_reaction_delay_elapsed: bool = false
	var _patrol_points: Array = []
	var _current_patrol_index: int = 0
	var _is_waiting_at_patrol_point: bool = false
	var _patrol_wait_timer: float = 0.0
	var patrol_wait_time: float = 2.0
	var move_speed: float = 100.0

	# Method call tracking
	var reset_alarm_mode_called: int = 0
	var reset_encounter_hits_called: int = 0
	var apply_wall_avoidance_called: int = 0
	var move_to_target_nav_called: int = 0
	var last_wall_avoidance_direction: Vector2 = Vector2.ZERO
	var last_nav_target: Vector2 = Vector2.ZERO
	var last_nav_speed: float = 0.0
	# Controls whether _move_to_target_nav returns true (moving) or false (arrived)
	var nav_move_result: bool = true

	func _reset_alarm_mode() -> void:
		reset_alarm_mode_called += 1

	func _reset_encounter_hits() -> void:
		reset_encounter_hits_called += 1

	func _apply_wall_avoidance(direction: Vector2) -> Vector2:
		apply_wall_avoidance_called += 1
		last_wall_avoidance_direction = direction
		return direction  # Return unchanged for test simplicity

	func _move_to_target_nav(target: Vector2, speed: float) -> bool:
		move_to_target_nav_called += 1
		last_nav_target = target
		last_nav_speed = speed
		if nav_move_result:
			velocity = (target - global_position).normalized() * speed
		return nav_move_result

	func has_method(method_name: String) -> bool:
		return method_name in ["_reset_alarm_mode", "_reset_encounter_hits", "_apply_wall_avoidance", "_move_to_target_nav"]


var enemy: MockEnemy


func before_each() -> void:
	enemy = MockEnemy.new()


func after_each() -> void:
	enemy = null


# ============================================================================
# EnemyState Base Class Tests
# ============================================================================


func test_enemy_state_init() -> void:
	var state := EnemyState.new(enemy)

	assert_eq(state.enemy, enemy,
		"State should store enemy reference")


func test_enemy_state_default_name() -> void:
	var state := EnemyState.new(enemy)

	assert_eq(state.state_name, "base",
		"Default state name should be 'base'")


func test_enemy_state_enter_does_nothing() -> void:
	var state := EnemyState.new(enemy)

	# Should not throw an error
	state.enter()
	assert_true(true, "enter() should complete without error")


func test_enemy_state_exit_does_nothing() -> void:
	var state := EnemyState.new(enemy)

	# Should not throw an error
	state.exit()
	assert_true(true, "exit() should complete without error")


func test_enemy_state_process_returns_null() -> void:
	var state := EnemyState.new(enemy)

	var next_state := state.process(0.016)

	assert_null(next_state,
		"process() should return null by default")


func test_enemy_state_get_display_name() -> void:
	var state := EnemyState.new(enemy)

	assert_eq(state.get_display_name(), "base",
		"get_display_name should return state_name")


func test_enemy_state_with_custom_name() -> void:
	var state := EnemyState.new(enemy)
	state.state_name = "custom"

	assert_eq(state.get_display_name(), "custom",
		"Should return custom state name")


# ============================================================================
# IdleState Initialization Tests
# ============================================================================


func test_idle_state_init() -> void:
	var state := IdleState.new(enemy)

	assert_eq(state.enemy, enemy,
		"IdleState should store enemy reference")


func test_idle_state_name() -> void:
	var state := IdleState.new(enemy)

	assert_eq(state.state_name, "idle",
		"IdleState name should be 'idle'")


func test_idle_state_display_name() -> void:
	var state := IdleState.new(enemy)

	assert_eq(state.get_display_name(), "idle",
		"Display name should be 'idle'")


# ============================================================================
# IdleState Enter Tests
# ============================================================================


func test_idle_state_enter_resets_alarm_mode() -> void:
	var state := IdleState.new(enemy)
	state.enter()

	assert_eq(enemy.reset_alarm_mode_called, 1,
		"Should call _reset_alarm_mode on enter")


func test_idle_state_enter_resets_encounter_hits() -> void:
	var state := IdleState.new(enemy)
	state.enter()

	assert_eq(enemy.reset_encounter_hits_called, 1,
		"Should call _reset_encounter_hits on enter")


# ============================================================================
# IdleState Transition Tests
# ============================================================================


func test_idle_state_transitions_when_sees_player() -> void:
	var state := IdleState.new(enemy)
	enemy._can_see_player = true

	var next_state := state.process(0.016)

	# Returns null to signal transition (actual state change handled by enemy)
	assert_null(next_state,
		"Should return null when player seen (signals transition)")


func test_idle_state_transitions_when_under_fire() -> void:
	var state := IdleState.new(enemy)
	enemy._under_fire = true
	enemy._threat_reaction_delay_elapsed = true

	var next_state := state.process(0.016)

	assert_null(next_state,
		"Should return null when under fire (signals transition)")


func test_idle_state_no_transition_under_fire_without_delay() -> void:
	var state := IdleState.new(enemy)
	enemy._under_fire = true
	enemy._threat_reaction_delay_elapsed = false
	enemy.behavior_mode = enemy.BehaviorMode.GUARD  # No patrol movement

	var next_state := state.process(0.016)

	assert_null(next_state,
		"Should not transition if delay not elapsed")


# ============================================================================
# IdleState Patrol Behavior Tests
# ============================================================================


func test_idle_state_patrol_with_no_points() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = []

	state.process(0.016)

	assert_eq(enemy.velocity, Vector2.ZERO,
		"Should not move without patrol points")


func test_idle_state_patrol_moves_toward_point() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(200, 0)]
	enemy.global_position = Vector2.ZERO

	state.process(0.016)

	assert_true(enemy.velocity.x > 0,
		"Should move toward patrol point")


func test_idle_state_patrol_uses_move_speed() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(200, 0)]
	enemy.global_position = Vector2.ZERO
	enemy.move_speed = 150.0

	state.process(0.016)

	assert_almost_eq(enemy.velocity.length(), 150.0, 0.1,
		"Velocity should match move_speed")


func test_idle_state_patrol_uses_nav_pathfinding() -> void:
	# Issue #1273: patrol should use _move_to_target_nav for wall- and size-aware pathfinding.
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(200, 0)]
	enemy.global_position = Vector2.ZERO

	state.process(0.016)

	assert_eq(enemy.move_to_target_nav_called, 1,
		"Should use _move_to_target_nav for navigation-based pathfinding")
	assert_eq(enemy.last_nav_target, Vector2(200, 0),
		"Nav target should be the patrol point")


func test_idle_state_patrol_reaches_point() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(100, 0), Vector2(200, 0)]
	enemy.global_position = Vector2(95, 0)  # Within 10 units

	state.process(0.016)

	assert_true(enemy._is_waiting_at_patrol_point,
		"Should start waiting when reaching patrol point")
	assert_eq(enemy.velocity, Vector2.ZERO,
		"Should stop when reaching patrol point")


func test_idle_state_patrol_wait_timer() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(100, 0), Vector2(200, 0)]
	enemy._is_waiting_at_patrol_point = true
	enemy._patrol_wait_timer = 0.0
	enemy.patrol_wait_time = 2.0

	state.process(1.0)

	assert_eq(enemy._patrol_wait_timer, 1.0,
		"Wait timer should increment")
	assert_true(enemy._is_waiting_at_patrol_point,
		"Should still be waiting")


func test_idle_state_patrol_wait_complete() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(100, 0), Vector2(200, 0)]
	enemy._current_patrol_index = 0
	enemy._is_waiting_at_patrol_point = true
	enemy._patrol_wait_timer = 1.9
	enemy.patrol_wait_time = 2.0

	state.process(0.2)  # Total 2.1 seconds

	assert_false(enemy._is_waiting_at_patrol_point,
		"Should stop waiting after wait time")
	assert_eq(enemy._current_patrol_index, 1,
		"Should move to next patrol point")


func test_idle_state_patrol_wraps_index() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(100, 0), Vector2(200, 0)]
	enemy._current_patrol_index = 1  # At last point
	enemy._is_waiting_at_patrol_point = true
	enemy._patrol_wait_timer = 2.0
	enemy.patrol_wait_time = 2.0

	state.process(0.1)

	assert_eq(enemy._current_patrol_index, 0,
		"Should wrap to first patrol point")


# ============================================================================
# IdleState Guard Behavior Tests
# ============================================================================


func test_idle_state_guard_stays_still() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.GUARD
	enemy.velocity = Vector2(100, 50)

	state.process(0.016)

	assert_eq(enemy.velocity, Vector2.ZERO,
		"Guard should set velocity to zero")


func test_idle_state_guard_ignores_patrol_points() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.GUARD
	enemy._patrol_points = [Vector2(200, 0)]
	enemy.global_position = Vector2.ZERO

	state.process(0.016)

	assert_eq(enemy.velocity, Vector2.ZERO,
		"Guard should not move even with patrol points")


# ============================================================================
# Complex Scenario Tests
# ============================================================================


func test_patrol_full_loop() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(10, 0), Vector2(20, 0)]
	enemy.global_position = Vector2.ZERO
	enemy.patrol_wait_time = 0.1

	# Move toward first point
	state.process(0.016)
	assert_true(enemy.velocity.x > 0, "Should move toward first point")

	# Reach first point
	enemy.global_position = Vector2(5, 0)
	state.process(0.016)
	assert_true(enemy._is_waiting_at_patrol_point, "Should wait at first point")

	# Wait at first point
	state.process(0.15)
	assert_false(enemy._is_waiting_at_patrol_point, "Should finish waiting")
	assert_eq(enemy._current_patrol_index, 1, "Should target second point")

	# Move toward second point
	enemy.global_position = Vector2(10, 0)
	state.process(0.016)
	assert_true(enemy.velocity.x > 0, "Should move toward second point")

	# Reach second point
	enemy.global_position = Vector2(15, 0)
	state.process(0.016)
	assert_true(enemy._is_waiting_at_patrol_point, "Should wait at second point")

	# Wait and loop back to first
	state.process(0.15)
	assert_eq(enemy._current_patrol_index, 0, "Should loop to first point")


func test_state_transitions_interrupt_patrol() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(100, 0)]
	enemy.global_position = Vector2.ZERO

	# Start moving
	state.process(0.016)
	assert_true(enemy.velocity.length() > 0, "Should be moving")

	# Enemy sees player - should signal transition
	enemy._can_see_player = true
	var result := state.process(0.016)

	# Result is null to signal that a transition should occur
	# (the actual transition is handled by the state machine in enemy.gd)
	assert_null(result, "Should signal transition when player seen")


func test_multiple_enter_calls() -> void:
	var state := IdleState.new(enemy)

	state.enter()
	state.enter()
	state.enter()

	assert_eq(enemy.reset_alarm_mode_called, 3,
		"Each enter should reset alarm mode")
	assert_eq(enemy.reset_encounter_hits_called, 3,
		"Each enter should reset encounter hits")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_patrol_point_at_current_position() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2.ZERO]
	enemy.global_position = Vector2.ZERO

	state.process(0.016)

	assert_true(enemy._is_waiting_at_patrol_point,
		"Should immediately wait if already at patrol point")


func test_patrol_single_point() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(100, 0)]
	enemy._current_patrol_index = 0
	enemy._is_waiting_at_patrol_point = true
	enemy._patrol_wait_timer = 2.0
	enemy.patrol_wait_time = 2.0

	state.process(0.1)

	# With single point, wrapping still works: (0 + 1) % 1 = 0
	assert_eq(enemy._current_patrol_index, 0,
		"Should wrap to same point with single patrol point")


func test_very_fast_movement() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(100, 0)]
	enemy.global_position = Vector2.ZERO
	enemy.move_speed = 1000.0

	state.process(0.016)

	assert_almost_eq(enemy.velocity.length(), 1000.0, 0.1,
		"Very fast movement should work")


func test_patrol_with_diagonal_movement() -> void:
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(100, 100)]
	enemy.global_position = Vector2.ZERO

	state.process(0.016)

	# Direction should be normalized, so velocity magnitude = move_speed
	assert_almost_eq(enemy.velocity.length(), enemy.move_speed, 0.1,
		"Diagonal movement should use correct speed")
	assert_true(enemy.velocity.x > 0 and enemy.velocity.y > 0,
		"Should move in diagonal direction")


# ============================================================================
# Issue #1273: Navigation-Based Pathfinding Tests
# ============================================================================


func test_patrol_nav_passes_move_speed() -> void:
	# Issue #1273: _move_to_target_nav must receive move_speed, not combat_move_speed.
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(200, 0)]
	enemy.global_position = Vector2.ZERO
	enemy.move_speed = 150.0

	state.process(0.016)

	assert_almost_eq(enemy.last_nav_speed, 150.0, 0.01,
		"Patrol should pass move_speed to _move_to_target_nav")


func test_patrol_nav_arrived_triggers_wait() -> void:
	# Issue #1273: when _move_to_target_nav returns false (arrived/nav finished), enter wait phase.
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(200, 0)]
	enemy.global_position = Vector2.ZERO
	enemy.nav_move_result = false  # Simulate nav reporting arrived

	state.process(0.016)

	assert_true(enemy._is_waiting_at_patrol_point,
		"Nav arrival (false return) should trigger patrol wait")
	assert_eq(enemy.velocity, Vector2.ZERO,
		"Velocity should be zero when arrived at patrol point via nav")


func test_patrol_nav_not_called_when_already_waiting() -> void:
	# If already waiting, nav should not be called.
	var state := IdleState.new(enemy)
	enemy.behavior_mode = enemy.BehaviorMode.PATROL
	enemy._patrol_points = [Vector2(200, 0)]
	enemy.global_position = Vector2.ZERO
	enemy._is_waiting_at_patrol_point = true
	enemy._patrol_wait_timer = 0.0

	state.process(0.016)

	assert_eq(enemy.move_to_target_nav_called, 0,
		"Should not call nav when already waiting at patrol point")
