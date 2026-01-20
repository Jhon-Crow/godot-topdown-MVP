extends GutTest
## Integration tests for HitEffectsManager behavior.
##
## Tests timer-based hit feedback effects.


# Mock implementation that mimics HitEffectsManager's testable logic
class MockHitEffectsManager:
	const SLOW_TIME_SCALE: float = 0.8
	const SLOW_DURATION: float = 3.0
	const SATURATION_DURATION: float = 3.0
	const SATURATION_BOOST: float = 0.4

	var _slow_timer: float = 0.0
	var _saturation_timer: float = 0.0
	var _is_slow_active: bool = false
	var _is_saturation_active: bool = false

	# Track time_scale changes (simulating Engine.time_scale)
	var time_scale: float = 1.0

	func on_player_hit_enemy() -> void:
		_start_slow_effect()
		_start_saturation_effect()

	func _start_slow_effect() -> void:
		_slow_timer = SLOW_DURATION
		if not _is_slow_active:
			_is_slow_active = true
			time_scale = SLOW_TIME_SCALE

	func _end_slow_effect() -> void:
		_is_slow_active = false
		time_scale = 1.0

	func _start_saturation_effect() -> void:
		_saturation_timer = SATURATION_DURATION
		if not _is_saturation_active:
			_is_saturation_active = true

	func _end_saturation_effect() -> void:
		_is_saturation_active = false

	func process(delta: float) -> void:
		# Use unscaled delta for timers
		var unscaled_delta := delta / time_scale if time_scale > 0 else delta

		if _is_slow_active:
			_slow_timer -= unscaled_delta
			if _slow_timer <= 0.0:
				_end_slow_effect()

		if _is_saturation_active:
			_saturation_timer -= unscaled_delta
			if _saturation_timer <= 0.0:
				_end_saturation_effect()

	func reset_effects() -> void:
		_end_slow_effect()
		_end_saturation_effect()
		_slow_timer = 0.0
		_saturation_timer = 0.0


var manager: MockHitEffectsManager


func before_each() -> void:
	manager = MockHitEffectsManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Constant Value Tests
# ============================================================================


func test_slow_time_scale_constant() -> void:
	assert_eq(MockHitEffectsManager.SLOW_TIME_SCALE, 0.8, "Slow time scale should be 0.8")


func test_slow_duration_constant() -> void:
	assert_eq(MockHitEffectsManager.SLOW_DURATION, 3.0, "Slow duration should be 3 seconds")


func test_saturation_duration_constant() -> void:
	assert_eq(MockHitEffectsManager.SATURATION_DURATION, 3.0, "Saturation duration should be 3 seconds")


func test_saturation_boost_constant() -> void:
	assert_eq(MockHitEffectsManager.SATURATION_BOOST, 0.4, "Saturation boost should be 0.4")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_slow_inactive() -> void:
	assert_false(manager._is_slow_active, "Slow effect should be inactive initially")


func test_initial_saturation_inactive() -> void:
	assert_false(manager._is_saturation_active, "Saturation effect should be inactive initially")


func test_initial_time_scale_normal() -> void:
	assert_eq(manager.time_scale, 1.0, "Time scale should be 1.0 initially")


func test_initial_timers_zero() -> void:
	assert_eq(manager._slow_timer, 0.0, "Slow timer should be 0 initially")
	assert_eq(manager._saturation_timer, 0.0, "Saturation timer should be 0 initially")


# ============================================================================
# on_player_hit_enemy Tests
# ============================================================================


func test_hit_activates_slow_effect() -> void:
	manager.on_player_hit_enemy()

	assert_true(manager._is_slow_active, "Slow effect should be active after hit")


func test_hit_activates_saturation_effect() -> void:
	manager.on_player_hit_enemy()

	assert_true(manager._is_saturation_active, "Saturation effect should be active after hit")


func test_hit_changes_time_scale() -> void:
	manager.on_player_hit_enemy()

	assert_eq(manager.time_scale, 0.8, "Time scale should be 0.8 after hit")


func test_hit_sets_slow_timer() -> void:
	manager.on_player_hit_enemy()

	assert_eq(manager._slow_timer, 3.0, "Slow timer should be set to duration")


func test_hit_sets_saturation_timer() -> void:
	manager.on_player_hit_enemy()

	assert_eq(manager._saturation_timer, 3.0, "Saturation timer should be set to duration")


# ============================================================================
# Timer Countdown Tests
# ============================================================================


func test_slow_timer_decrements() -> void:
	manager.on_player_hit_enemy()
	manager.process(1.0)

	# Timer decrements by unscaled time
	# unscaled_delta = 1.0 / 0.8 = 1.25
	assert_almost_eq(manager._slow_timer, 1.75, 0.01, "Slow timer should decrement")


func test_saturation_timer_decrements() -> void:
	manager.on_player_hit_enemy()
	manager.process(1.0)

	# unscaled_delta = 1.0 / 0.8 = 1.25
	assert_almost_eq(manager._saturation_timer, 1.75, 0.01, "Saturation timer should decrement")


func test_effects_end_after_duration() -> void:
	manager.on_player_hit_enemy()

	# Process enough time for effects to end
	# Need ~2.4 real seconds (3.0 * 0.8) for 3 seconds of real time at 0.8 scale
	manager.process(2.5)

	assert_false(manager._is_slow_active, "Slow effect should end")
	assert_false(manager._is_saturation_active, "Saturation effect should end")


func test_time_scale_restores_after_slow_ends() -> void:
	manager.on_player_hit_enemy()
	manager.process(2.5)

	assert_eq(manager.time_scale, 1.0, "Time scale should restore to 1.0")


# ============================================================================
# Multiple Hits Tests
# ============================================================================


func test_multiple_hits_reset_timers() -> void:
	manager.on_player_hit_enemy()
	manager.process(1.0)

	# Hit again
	manager.on_player_hit_enemy()

	assert_eq(manager._slow_timer, 3.0, "Timer should reset on new hit")
	assert_eq(manager._saturation_timer, 3.0, "Saturation timer should reset")


func test_multiple_hits_keep_effects_active() -> void:
	manager.on_player_hit_enemy()
	manager.process(2.0)

	# Hit again before effects end
	manager.on_player_hit_enemy()

	assert_true(manager._is_slow_active, "Slow should still be active")
	assert_true(manager._is_saturation_active, "Saturation should still be active")


func test_rapid_hits() -> void:
	for i in range(5):
		manager.on_player_hit_enemy()
		manager.process(0.1)

	assert_true(manager._is_slow_active, "Effects should remain active")
	assert_almost_eq(manager._slow_timer, 3.0 - (0.1 / 0.8), 0.1, "Timer should be near full")


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_deactivates_slow() -> void:
	manager.on_player_hit_enemy()
	manager.reset_effects()

	assert_false(manager._is_slow_active, "Slow should be deactivated")


func test_reset_deactivates_saturation() -> void:
	manager.on_player_hit_enemy()
	manager.reset_effects()

	assert_false(manager._is_saturation_active, "Saturation should be deactivated")


func test_reset_restores_time_scale() -> void:
	manager.on_player_hit_enemy()
	manager.reset_effects()

	assert_eq(manager.time_scale, 1.0, "Time scale should be restored")


func test_reset_clears_timers() -> void:
	manager.on_player_hit_enemy()
	manager.reset_effects()

	assert_eq(manager._slow_timer, 0.0, "Slow timer should be cleared")
	assert_eq(manager._saturation_timer, 0.0, "Saturation timer should be cleared")


func test_reset_on_inactive_manager() -> void:
	# Should not crash when resetting inactive manager
	manager.reset_effects()

	assert_false(manager._is_slow_active, "Should remain inactive")
	assert_eq(manager.time_scale, 1.0, "Time scale should be 1.0")


# ============================================================================
# Edge Cases
# ============================================================================


func test_process_without_active_effects() -> void:
	manager.process(1.0)

	# Should not crash, and nothing should change
	assert_false(manager._is_slow_active, "Should remain inactive")
	assert_eq(manager.time_scale, 1.0, "Time scale should remain 1.0")


func test_zero_delta_process() -> void:
	manager.on_player_hit_enemy()
	var initial_timer := manager._slow_timer

	manager.process(0.0)

	assert_eq(manager._slow_timer, initial_timer, "Timer should not change with zero delta")


func test_very_large_delta() -> void:
	manager.on_player_hit_enemy()

	manager.process(100.0)

	assert_false(manager._is_slow_active, "Effects should end with large delta")
	assert_false(manager._is_saturation_active, "Saturation should end")
	assert_eq(manager.time_scale, 1.0, "Time scale should be restored")


func test_effect_ends_at_duration_boundary() -> void:
	manager.on_player_hit_enemy()

	# Process just enough time to cross the boundary
	# At 0.8 time scale, need > 2.4 real seconds to exceed 3.0 game seconds
	# Using 2.41 to avoid floating-point precision issues with exact boundary
	manager.process(2.41)

	assert_false(manager._is_slow_active, "Effects should end at duration boundary")
