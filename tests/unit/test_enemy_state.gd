extends GutTest
## Unit tests for EnemyState base class.
##
## Tests the enemy state lifecycle including:
## - Initialization with enemy reference
## - Enter/exit lifecycle methods
## - Default process behavior
## - Display name reporting


# ============================================================================
# Mock Enemy for State Tests
# ============================================================================


class MockEnemy:
	extends Node2D


# ============================================================================
# Setup / Teardown
# ============================================================================


var _enemy: MockEnemy = null
var _state: EnemyState = null


func before_each() -> void:
	_enemy = MockEnemy.new()
	_state = EnemyState.new(_enemy)


func after_each() -> void:
	_state = null
	if is_instance_valid(_enemy):
		_enemy.free()
	_enemy = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_init_stores_enemy_reference() -> void:
	assert_eq(_state.enemy, _enemy, "State should store the enemy reference passed to _init")


func test_init_sets_default_state_name() -> void:
	assert_eq(_state.state_name, "base", "Default state_name should be 'base'")


func test_init_with_null_enemy() -> void:
	var state := EnemyState.new(null)

	assert_eq(state.enemy, null, "State should accept null enemy reference")


# ============================================================================
# Enter / Exit Lifecycle Tests
# ============================================================================


func test_enter_does_not_crash() -> void:
	# enter() is a no-op on the base class; just verify it runs without error
	_state.enter()

	assert_true(true, "enter() should execute without error")


func test_exit_does_not_crash() -> void:
	# exit() is a no-op on the base class; just verify it runs without error
	_state.exit()

	assert_true(true, "exit() should execute without error")


func test_enter_exit_sequence() -> void:
	_state.enter()
	_state.exit()

	assert_true(true, "enter() followed by exit() should execute without error")


# ============================================================================
# Process Tests
# ============================================================================


func test_process_returns_null_by_default() -> void:
	var result: EnemyState = _state.process(0.016)

	assert_eq(result, null, "Base process() should return null (stay in current state)")


func test_process_returns_null_with_zero_delta() -> void:
	var result: EnemyState = _state.process(0.0)

	assert_eq(result, null, "process() with zero delta should return null")


func test_process_returns_null_with_large_delta() -> void:
	var result: EnemyState = _state.process(1.0)

	assert_eq(result, null, "process() with large delta should return null")


# ============================================================================
# Display Name Tests
# ============================================================================


func test_get_display_name_returns_state_name() -> void:
	var display_name: String = _state.get_display_name()

	assert_eq(display_name, "base", "get_display_name() should return the state_name value")


func test_get_display_name_reflects_custom_state_name() -> void:
	_state.state_name = "custom_state"

	var display_name: String = _state.get_display_name()

	assert_eq(display_name, "custom_state", "get_display_name() should reflect updated state_name")


func test_get_display_name_with_empty_state_name() -> void:
	_state.state_name = ""

	var display_name: String = _state.get_display_name()

	assert_eq(display_name, "", "get_display_name() should return empty string when state_name is empty")
