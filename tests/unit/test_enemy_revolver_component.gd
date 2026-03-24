extends GutTest
## Unit tests for EnemyRevolverComponent.
##
## Tests rounds fired tracking and reload state management
## for the enemy revolver reload system.


# ============================================================================
# Mock EnemyRevolverComponent for Logic Tests
# ============================================================================


class MockEnemyRevolverComponent:
	var _is_reloading_coroutine: bool = false
	var _rounds_fired: int = 0

	func is_reloading_coroutine() -> bool:
		return _is_reloading_coroutine

	func track_round_fired() -> void:
		_rounds_fired += 1

	func get_rounds_fired() -> int:
		return _rounds_fired

	func set_reloading(value: bool) -> void:
		_is_reloading_coroutine = value

	## Simulate the reload completion (resets rounds fired).
	func simulate_reload_complete() -> void:
		_rounds_fired = 0
		_is_reloading_coroutine = false


var comp: MockEnemyRevolverComponent


func before_each() -> void:
	comp = MockEnemyRevolverComponent.new()


func after_each() -> void:
	comp = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_rounds_fired_zero() -> void:
	assert_eq(comp.get_rounds_fired(), 0,
		"Rounds fired should start at 0")


func test_initial_not_reloading() -> void:
	assert_false(comp.is_reloading_coroutine(),
		"Should not be reloading initially")


# ============================================================================
# Rounds Fired Tracking Tests
# ============================================================================


func test_track_single_round() -> void:
	comp.track_round_fired()

	assert_eq(comp.get_rounds_fired(), 1,
		"Should track 1 round fired")


func test_track_multiple_rounds() -> void:
	comp.track_round_fired()
	comp.track_round_fired()
	comp.track_round_fired()

	assert_eq(comp.get_rounds_fired(), 3,
		"Should track 3 rounds fired")


func test_track_six_rounds_full_cylinder() -> void:
	for _i in range(6):
		comp.track_round_fired()

	assert_eq(comp.get_rounds_fired(), 6,
		"Should track full cylinder of 6 rounds")


func test_rounds_reset_after_reload() -> void:
	comp.track_round_fired()
	comp.track_round_fired()
	comp.track_round_fired()

	comp.simulate_reload_complete()

	assert_eq(comp.get_rounds_fired(), 0,
		"Rounds fired should reset to 0 after reload")


# ============================================================================
# Reload State Tests
# ============================================================================


func test_set_reloading_true() -> void:
	comp.set_reloading(true)

	assert_true(comp.is_reloading_coroutine(),
		"Should be reloading when set to true")


func test_set_reloading_false() -> void:
	comp.set_reloading(true)
	comp.set_reloading(false)

	assert_false(comp.is_reloading_coroutine(),
		"Should not be reloading when set to false")


func test_reload_complete_clears_reloading_state() -> void:
	comp.set_reloading(true)
	comp.simulate_reload_complete()

	assert_false(comp.is_reloading_coroutine(),
		"Reload complete should clear reloading state")


func test_reload_state_independent_of_rounds_fired() -> void:
	comp.track_round_fired()
	comp.track_round_fired()

	assert_false(comp.is_reloading_coroutine(),
		"Firing rounds should not automatically trigger reload")


func test_track_rounds_during_reload_allowed() -> void:
	comp.set_reloading(true)
	comp.track_round_fired()

	assert_eq(comp.get_rounds_fired(), 1,
		"Rounds can still be tracked during reload state")


# ============================================================================
# Edge Cases
# ============================================================================


func test_multiple_reload_cycles() -> void:
	# Cycle 1
	comp.track_round_fired()
	comp.track_round_fired()
	comp.simulate_reload_complete()
	assert_eq(comp.get_rounds_fired(), 0)

	# Cycle 2
	comp.track_round_fired()
	comp.track_round_fired()
	comp.track_round_fired()
	assert_eq(comp.get_rounds_fired(), 3)

	comp.simulate_reload_complete()
	assert_eq(comp.get_rounds_fired(), 0,
		"Second reload cycle should also reset rounds")


func test_reload_without_firing() -> void:
	comp.simulate_reload_complete()

	assert_eq(comp.get_rounds_fired(), 0,
		"Reload with no rounds fired should keep count at 0")
	assert_false(comp.is_reloading_coroutine())
