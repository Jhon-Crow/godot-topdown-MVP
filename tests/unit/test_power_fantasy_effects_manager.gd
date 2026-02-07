extends GutTest
## Unit tests for PowerFantasyEffectsManager autoload.
##
## Tests the power fantasy effects management functionality including
## effect activation, deactivation, duration tracking, timer resets,
## guard clauses, and constant values.


# ============================================================================
# Mock DifficultyManager for Testing
# ============================================================================


class MockDifficultyManager:
	var _is_power_fantasy: bool = false

	func set_power_fantasy(value: bool) -> void:
		_is_power_fantasy = value

	func is_power_fantasy_mode() -> bool:
		return _is_power_fantasy


# ============================================================================
# Mock LastChanceEffectsManager for Testing
# ============================================================================


class MockLastChanceEffectsManager:
	var _is_active: bool = false
	var grenade_last_chance_triggered: bool = false
	var grenade_last_chance_duration: float = 0.0

	func set_active(value: bool) -> void:
		_is_active = value

	func is_effect_active() -> bool:
		return _is_active

	func has_method(method_name: String) -> bool:
		return method_name in ["is_effect_active", "trigger_grenade_last_chance"]

	func trigger_grenade_last_chance(duration_seconds: float) -> void:
		grenade_last_chance_triggered = true
		grenade_last_chance_duration = duration_seconds


# ============================================================================
# Mock PowerFantasyEffectsManager for Logic Tests
# ============================================================================


class MockPowerFantasyEffectsManager:
	## Duration of the last chance effect when killing an enemy (300ms).
	const KILL_EFFECT_DURATION_MS: float = 300.0

	## Duration of the special last chance effect when grenade explodes (2000ms).
	const GRENADE_EFFECT_DURATION_MS: float = 2000.0

	## The slowed down time scale during effects.
	const EFFECT_TIME_SCALE: float = 0.1

	## Screen saturation multiplier during effect.
	const SCREEN_SATURATION_BOOST: float = 2.0

	## Screen contrast multiplier during effect.
	const SCREEN_CONTRAST_BOOST: float = 1.0

	## Whether the effect is currently active.
	var _is_effect_active: bool = false

	## Timer for tracking effect duration (uses real time, not game time).
	var _effect_start_time: float = 0.0

	## Current effect duration in milliseconds.
	var _current_effect_duration_ms: float = 0.0

	## Simulated time scale (mirrors Engine.time_scale).
	var time_scale: float = 1.0

	## Whether the saturation rect is visible.
	var saturation_rect_visible: bool = false

	## Current saturation boost value applied to shader.
	var current_saturation_boost: float = 0.0

	## Current contrast boost value applied to shader.
	var current_contrast_boost: float = 0.0

	## Simulated current ticks in milliseconds (for mocking Time.get_ticks_msec()).
	var _simulated_ticks_msec: float = 0.0

	## Log messages recorded during operations.
	var log_messages: Array = []

	## Reference to mock difficulty manager.
	var difficulty_manager: MockDifficultyManager = null

	## Reference to mock last chance effects manager.
	var last_chance_manager: MockLastChanceEffectsManager = null

	## Simulate getting ticks (replaces Time.get_ticks_msec()).
	func get_ticks_sec() -> float:
		return _simulated_ticks_msec / 1000.0

	## Set the simulated time in milliseconds.
	func set_simulated_ticks_msec(value: float) -> void:
		_simulated_ticks_msec = value

	## Log a message.
	func _log(message: String) -> void:
		log_messages.append("[PowerFantasy] " + message)

	## Returns whether the power fantasy effect is currently active.
	func is_effect_active() -> bool:
		return _is_effect_active

	## Starts the power fantasy effect with the specified duration.
	func _start_effect(duration_ms: float) -> void:
		# If effect is already active, reset the timer
		if _is_effect_active:
			_effect_start_time = get_ticks_sec()
			_current_effect_duration_ms = duration_ms
			_log("Effect timer reset to %.0fms" % duration_ms)
			return

		_is_effect_active = true
		_effect_start_time = get_ticks_sec()
		_current_effect_duration_ms = duration_ms

		_log("Starting power fantasy effect:")
		_log("  - Time scale: %.2f" % EFFECT_TIME_SCALE)
		_log("  - Duration: %.0fms" % duration_ms)

		# Slow down time
		time_scale = EFFECT_TIME_SCALE

		# Apply screen saturation and contrast
		saturation_rect_visible = true
		current_saturation_boost = SCREEN_SATURATION_BOOST
		current_contrast_boost = SCREEN_CONTRAST_BOOST

	## Ends the power fantasy effect.
	func _end_effect() -> void:
		if not _is_effect_active:
			return

		_is_effect_active = false
		_log("Ending power fantasy effect")

		# Restore normal time
		time_scale = 1.0

		# Remove screen saturation and contrast
		saturation_rect_visible = false
		current_saturation_boost = 0.0
		current_contrast_boost = 0.0

	## Resets all effects (useful when restarting the scene).
	func reset_effects() -> void:
		_log("Resetting all effects (scene change detected)")

		if _is_effect_active:
			_is_effect_active = false
			# Restore normal time immediately
			time_scale = 1.0

		# Remove screen saturation and contrast
		saturation_rect_visible = false
		current_saturation_boost = 0.0
		current_contrast_boost = 0.0

	## Simulates the _process check for effect expiration.
	func process_check() -> void:
		if _is_effect_active:
			var current_time := get_ticks_sec()
			var elapsed_real_time := (current_time - _effect_start_time) * 1000.0  # Convert to ms

			if elapsed_real_time >= _current_effect_duration_ms:
				_log("Effect duration expired after %.2f ms" % elapsed_real_time)
				_end_effect()

	## Called when an enemy is killed by the player in Power Fantasy mode.
	func on_enemy_killed() -> void:
		if difficulty_manager == null or not difficulty_manager.is_power_fantasy_mode():
			return

		# Skip kill effect if LastChanceEffectsManager is already providing a stronger
		# time-freeze (e.g., from grenade explosion).
		if last_chance_manager and last_chance_manager.has_method("is_effect_active"):
			if last_chance_manager.is_effect_active():
				_log("Enemy killed - skipping 300ms effect (LastChance time-freeze already active)")
				return

		_log("Enemy killed - triggering 300ms last chance effect")
		_start_effect(KILL_EFFECT_DURATION_MS)

	## Called when a grenade explodes in Power Fantasy mode.
	func on_grenade_exploded() -> void:
		if difficulty_manager == null or not difficulty_manager.is_power_fantasy_mode():
			return

		_log("Grenade exploded - triggering last chance time-freeze effect for %.0fms" % GRENADE_EFFECT_DURATION_MS)

		# Use LastChanceEffectsManager for the full time-freeze effect (like Hard mode)
		if last_chance_manager and last_chance_manager.has_method("trigger_grenade_last_chance"):
			last_chance_manager.trigger_grenade_last_chance(GRENADE_EFFECT_DURATION_MS / 1000.0)
		else:
			# Fallback: use simple time-scale effect if LastChanceEffectsManager not available
			_log("WARNING: LastChanceEffectsManager not available, using simple slowdown fallback")
			_start_effect(GRENADE_EFFECT_DURATION_MS)


var manager: MockPowerFantasyEffectsManager
var difficulty_manager: MockDifficultyManager
var last_chance_manager: MockLastChanceEffectsManager


func before_each() -> void:
	manager = MockPowerFantasyEffectsManager.new()
	difficulty_manager = MockDifficultyManager.new()
	last_chance_manager = MockLastChanceEffectsManager.new()
	manager.difficulty_manager = difficulty_manager
	manager.last_chance_manager = last_chance_manager


func after_each() -> void:
	manager = null
	difficulty_manager = null
	last_chance_manager = null


# ============================================================================
# Constant Values Tests
# ============================================================================


func test_kill_effect_duration_ms_is_300() -> void:
	assert_eq(MockPowerFantasyEffectsManager.KILL_EFFECT_DURATION_MS, 300.0,
		"Kill effect duration should be 300ms")


func test_grenade_effect_duration_ms_is_2000() -> void:
	assert_eq(MockPowerFantasyEffectsManager.GRENADE_EFFECT_DURATION_MS, 2000.0,
		"Grenade effect duration should be 2000ms")


func test_effect_time_scale_is_0_1() -> void:
	assert_eq(MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE, 0.1,
		"Effect time scale should be 0.1 (10% speed)")


func test_screen_saturation_boost_is_2_0() -> void:
	assert_eq(MockPowerFantasyEffectsManager.SCREEN_SATURATION_BOOST, 2.0,
		"Screen saturation boost should be 2.0")


func test_screen_contrast_boost_is_1_0() -> void:
	assert_eq(MockPowerFantasyEffectsManager.SCREEN_CONTRAST_BOOST, 1.0,
		"Screen contrast boost should be 1.0")


func test_kill_effect_shorter_than_grenade_effect() -> void:
	assert_lt(MockPowerFantasyEffectsManager.KILL_EFFECT_DURATION_MS,
		MockPowerFantasyEffectsManager.GRENADE_EFFECT_DURATION_MS,
		"Kill effect should be shorter than grenade effect")


func test_effect_time_scale_is_between_zero_and_one() -> void:
	assert_gt(MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE, 0.0,
		"Effect time scale should be greater than zero")
	assert_lt(MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE, 1.0,
		"Effect time scale should be less than 1.0 (slower than normal)")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_effect_not_active() -> void:
	assert_false(manager.is_effect_active(),
		"Effect should not be active initially")


func test_initial_is_effect_active_field_false() -> void:
	assert_false(manager._is_effect_active,
		"_is_effect_active should be false initially")


func test_initial_effect_start_time_is_zero() -> void:
	assert_eq(manager._effect_start_time, 0.0,
		"Effect start time should be 0.0 initially")


func test_initial_current_effect_duration_is_zero() -> void:
	assert_eq(manager._current_effect_duration_ms, 0.0,
		"Current effect duration should be 0.0 initially")


func test_initial_time_scale_is_normal() -> void:
	assert_eq(manager.time_scale, 1.0,
		"Time scale should be 1.0 (normal) initially")


func test_initial_saturation_rect_not_visible() -> void:
	assert_false(manager.saturation_rect_visible,
		"Saturation rect should not be visible initially")


func test_initial_saturation_boost_is_zero() -> void:
	assert_eq(manager.current_saturation_boost, 0.0,
		"Saturation boost should be 0.0 initially")


func test_initial_contrast_boost_is_zero() -> void:
	assert_eq(manager.current_contrast_boost, 0.0,
		"Contrast boost should be 0.0 initially")


# ============================================================================
# _start_effect Tests
# ============================================================================


func test_start_effect_sets_active_flag() -> void:
	manager._start_effect(300.0)

	assert_true(manager._is_effect_active,
		"_is_effect_active should be true after starting effect")


func test_start_effect_sets_is_effect_active() -> void:
	manager._start_effect(300.0)

	assert_true(manager.is_effect_active(),
		"is_effect_active() should return true after starting effect")


func test_start_effect_sets_effect_start_time() -> void:
	manager.set_simulated_ticks_msec(5000.0)
	manager._start_effect(300.0)

	assert_eq(manager._effect_start_time, 5.0,
		"Effect start time should be set to current ticks in seconds")


func test_start_effect_sets_current_duration() -> void:
	manager._start_effect(300.0)

	assert_eq(manager._current_effect_duration_ms, 300.0,
		"Current effect duration should be set to provided duration")


func test_start_effect_sets_time_scale_to_effect_value() -> void:
	manager._start_effect(300.0)

	assert_eq(manager.time_scale, MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE,
		"Time scale should be set to EFFECT_TIME_SCALE")


func test_start_effect_makes_saturation_rect_visible() -> void:
	manager._start_effect(300.0)

	assert_true(manager.saturation_rect_visible,
		"Saturation rect should be visible during effect")


func test_start_effect_applies_saturation_boost() -> void:
	manager._start_effect(300.0)

	assert_eq(manager.current_saturation_boost, MockPowerFantasyEffectsManager.SCREEN_SATURATION_BOOST,
		"Saturation boost should be applied during effect")


func test_start_effect_applies_contrast_boost() -> void:
	manager._start_effect(300.0)

	assert_eq(manager.current_contrast_boost, MockPowerFantasyEffectsManager.SCREEN_CONTRAST_BOOST,
		"Contrast boost should be applied during effect")


func test_start_effect_with_kill_duration() -> void:
	manager._start_effect(MockPowerFantasyEffectsManager.KILL_EFFECT_DURATION_MS)

	assert_eq(manager._current_effect_duration_ms, 300.0,
		"Kill effect duration should be stored correctly")


func test_start_effect_with_grenade_duration() -> void:
	manager._start_effect(MockPowerFantasyEffectsManager.GRENADE_EFFECT_DURATION_MS)

	assert_eq(manager._current_effect_duration_ms, 2000.0,
		"Grenade effect duration should be stored correctly")


# ============================================================================
# _start_effect Timer Reset (Already Active) Tests
# ============================================================================


func test_start_effect_while_active_resets_timer() -> void:
	manager.set_simulated_ticks_msec(1000.0)
	manager._start_effect(300.0)

	manager.set_simulated_ticks_msec(1100.0)
	manager._start_effect(300.0)

	assert_eq(manager._effect_start_time, 1.1,
		"Effect start time should be updated when restarting while active")


func test_start_effect_while_active_updates_duration() -> void:
	manager._start_effect(300.0)
	manager._start_effect(2000.0)

	assert_eq(manager._current_effect_duration_ms, 2000.0,
		"Effect duration should be updated when restarting while active")


func test_start_effect_while_active_keeps_active_flag() -> void:
	manager._start_effect(300.0)
	manager._start_effect(2000.0)

	assert_true(manager._is_effect_active,
		"Effect should remain active when restarting")


func test_start_effect_while_active_does_not_change_time_scale() -> void:
	manager._start_effect(300.0)
	# Time scale was set to EFFECT_TIME_SCALE
	assert_eq(manager.time_scale, MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE)

	# Restarting while active should return early (not re-apply time scale)
	manager._start_effect(2000.0)
	assert_eq(manager.time_scale, MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE,
		"Time scale should remain at EFFECT_TIME_SCALE after timer reset")


func test_start_effect_while_active_keeps_saturation_visible() -> void:
	manager._start_effect(300.0)
	manager._start_effect(2000.0)

	assert_true(manager.saturation_rect_visible,
		"Saturation rect should remain visible after timer reset")


func test_start_effect_while_active_logs_timer_reset() -> void:
	manager._start_effect(300.0)
	manager.log_messages.clear()
	manager._start_effect(2000.0)

	var found_reset_log := false
	for msg in manager.log_messages:
		if "timer reset" in msg.to_lower():
			found_reset_log = true
			break

	assert_true(found_reset_log,
		"Should log a timer reset message when restarting while active")


# ============================================================================
# _end_effect Tests
# ============================================================================


func test_end_effect_clears_active_flag() -> void:
	manager._start_effect(300.0)
	manager._end_effect()

	assert_false(manager._is_effect_active,
		"_is_effect_active should be false after ending effect")


func test_end_effect_returns_is_effect_active_false() -> void:
	manager._start_effect(300.0)
	manager._end_effect()

	assert_false(manager.is_effect_active(),
		"is_effect_active() should return false after ending effect")


func test_end_effect_restores_time_scale() -> void:
	manager._start_effect(300.0)
	manager._end_effect()

	assert_eq(manager.time_scale, 1.0,
		"Time scale should be restored to 1.0 after ending effect")


func test_end_effect_hides_saturation_rect() -> void:
	manager._start_effect(300.0)
	manager._end_effect()

	assert_false(manager.saturation_rect_visible,
		"Saturation rect should be hidden after ending effect")


func test_end_effect_clears_saturation_boost() -> void:
	manager._start_effect(300.0)
	manager._end_effect()

	assert_eq(manager.current_saturation_boost, 0.0,
		"Saturation boost should be 0.0 after ending effect")


func test_end_effect_clears_contrast_boost() -> void:
	manager._start_effect(300.0)
	manager._end_effect()

	assert_eq(manager.current_contrast_boost, 0.0,
		"Contrast boost should be 0.0 after ending effect")


func test_end_effect_when_not_active_does_nothing() -> void:
	# Ensure nothing is active
	assert_false(manager._is_effect_active)

	# Ending an inactive effect should not change anything
	manager._end_effect()

	assert_false(manager._is_effect_active,
		"Ending inactive effect should keep it inactive")
	assert_eq(manager.time_scale, 1.0,
		"Time scale should remain 1.0 when ending inactive effect")
	assert_false(manager.saturation_rect_visible,
		"Saturation rect should remain hidden when ending inactive effect")


func test_end_effect_when_not_active_does_not_log() -> void:
	manager.log_messages.clear()
	manager._end_effect()

	var found_ending_log := false
	for msg in manager.log_messages:
		if "ending" in msg.to_lower():
			found_ending_log = true
			break

	assert_false(found_ending_log,
		"Should not log ending message when effect is not active")


# ============================================================================
# reset_effects Tests
# ============================================================================


func test_reset_effects_clears_active_flag() -> void:
	manager._start_effect(300.0)
	manager.reset_effects()

	assert_false(manager._is_effect_active,
		"_is_effect_active should be false after reset")


func test_reset_effects_restores_time_scale() -> void:
	manager._start_effect(300.0)
	manager.reset_effects()

	assert_eq(manager.time_scale, 1.0,
		"Time scale should be restored to 1.0 after reset")


func test_reset_effects_hides_saturation_rect() -> void:
	manager._start_effect(300.0)
	manager.reset_effects()

	assert_false(manager.saturation_rect_visible,
		"Saturation rect should be hidden after reset")


func test_reset_effects_clears_saturation_boost() -> void:
	manager._start_effect(300.0)
	manager.reset_effects()

	assert_eq(manager.current_saturation_boost, 0.0,
		"Saturation boost should be 0.0 after reset")


func test_reset_effects_clears_contrast_boost() -> void:
	manager._start_effect(300.0)
	manager.reset_effects()

	assert_eq(manager.current_contrast_boost, 0.0,
		"Contrast boost should be 0.0 after reset")


func test_reset_effects_when_not_active_still_clears_visuals() -> void:
	# Manually set visual state without activating the effect
	manager.saturation_rect_visible = true
	manager.current_saturation_boost = 1.5
	manager.current_contrast_boost = 0.5

	manager.reset_effects()

	assert_false(manager.saturation_rect_visible,
		"Saturation rect should be hidden after reset even if effect was not active")
	assert_eq(manager.current_saturation_boost, 0.0,
		"Saturation boost should be cleared after reset even if effect was not active")
	assert_eq(manager.current_contrast_boost, 0.0,
		"Contrast boost should be cleared after reset even if effect was not active")


func test_reset_effects_when_not_active_does_not_touch_time_scale() -> void:
	# Set time_scale to something non-standard without an active effect
	manager.time_scale = 0.5

	manager.reset_effects()

	# Since _is_effect_active is false, reset_effects should not change time_scale
	assert_eq(manager.time_scale, 0.5,
		"Time scale should not be changed by reset when effect is not active")


func test_reset_effects_logs_message() -> void:
	manager.log_messages.clear()
	manager.reset_effects()

	var found_reset_log := false
	for msg in manager.log_messages:
		if "resetting" in msg.to_lower():
			found_reset_log = true
			break

	assert_true(found_reset_log,
		"Should log a reset message")


# ============================================================================
# Process / Effect Expiration Tests
# ============================================================================


func test_process_check_ends_effect_after_duration_expires() -> void:
	manager.set_simulated_ticks_msec(1000.0)
	manager._start_effect(300.0)

	# Advance time past the effect duration
	manager.set_simulated_ticks_msec(1400.0)
	manager.process_check()

	assert_false(manager.is_effect_active(),
		"Effect should end after duration expires")


func test_process_check_keeps_effect_before_duration_expires() -> void:
	manager.set_simulated_ticks_msec(1000.0)
	manager._start_effect(300.0)

	# Advance time but not past the effect duration
	manager.set_simulated_ticks_msec(1200.0)
	manager.process_check()

	assert_true(manager.is_effect_active(),
		"Effect should remain active before duration expires")


func test_process_check_ends_effect_at_exact_duration() -> void:
	manager.set_simulated_ticks_msec(1000.0)
	manager._start_effect(300.0)

	# Advance time exactly to the duration
	manager.set_simulated_ticks_msec(1300.0)
	manager.process_check()

	assert_false(manager.is_effect_active(),
		"Effect should end at exactly the duration boundary")


func test_process_check_restores_time_scale_on_expiry() -> void:
	manager.set_simulated_ticks_msec(1000.0)
	manager._start_effect(300.0)
	assert_eq(manager.time_scale, MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE)

	manager.set_simulated_ticks_msec(1400.0)
	manager.process_check()

	assert_eq(manager.time_scale, 1.0,
		"Time scale should be restored to 1.0 after effect expires via process")


func test_process_check_hides_saturation_rect_on_expiry() -> void:
	manager.set_simulated_ticks_msec(1000.0)
	manager._start_effect(300.0)

	manager.set_simulated_ticks_msec(1400.0)
	manager.process_check()

	assert_false(manager.saturation_rect_visible,
		"Saturation rect should be hidden after effect expires via process")


func test_process_check_does_nothing_when_not_active() -> void:
	manager.set_simulated_ticks_msec(5000.0)
	manager.log_messages.clear()
	manager.process_check()

	assert_false(manager.is_effect_active(),
		"Effect should remain inactive when process check runs with no active effect")
	assert_eq(manager.time_scale, 1.0,
		"Time scale should remain 1.0")


func test_process_check_grenade_effect_lasts_longer() -> void:
	manager.set_simulated_ticks_msec(1000.0)
	manager._start_effect(MockPowerFantasyEffectsManager.GRENADE_EFFECT_DURATION_MS)

	# After 300ms (kill effect would have ended), grenade should still be active
	manager.set_simulated_ticks_msec(1300.0)
	manager.process_check()

	assert_true(manager.is_effect_active(),
		"Grenade effect should still be active after 300ms")

	# After 2000ms, grenade effect should end
	manager.set_simulated_ticks_msec(3000.0)
	manager.process_check()

	assert_false(manager.is_effect_active(),
		"Grenade effect should end after 2000ms")


func test_process_check_timer_reset_extends_duration() -> void:
	manager.set_simulated_ticks_msec(1000.0)
	manager._start_effect(300.0)

	# At 200ms, restart the effect (timer reset)
	manager.set_simulated_ticks_msec(1200.0)
	manager._start_effect(300.0)

	# At original 300ms mark (1300ms), effect should still be active due to reset
	manager.set_simulated_ticks_msec(1300.0)
	manager.process_check()

	assert_true(manager.is_effect_active(),
		"Effect should still be active because timer was reset at 200ms")

	# At 500ms from the reset point (1700ms), effect should have expired
	manager.set_simulated_ticks_msec(1600.0)
	manager.process_check()

	assert_false(manager.is_effect_active(),
		"Effect should expire 300ms after the timer reset")


# ============================================================================
# on_enemy_killed Guard Clause Tests
# ============================================================================


func test_on_enemy_killed_does_nothing_when_not_power_fantasy() -> void:
	difficulty_manager.set_power_fantasy(false)

	manager.on_enemy_killed()

	assert_false(manager.is_effect_active(),
		"Effect should not activate when not in power fantasy mode")


func test_on_enemy_killed_does_nothing_when_difficulty_manager_null() -> void:
	manager.difficulty_manager = null

	manager.on_enemy_killed()

	assert_false(manager.is_effect_active(),
		"Effect should not activate when difficulty manager is null")


func test_on_enemy_killed_activates_in_power_fantasy_mode() -> void:
	difficulty_manager.set_power_fantasy(true)
	last_chance_manager.set_active(false)

	manager.on_enemy_killed()

	assert_true(manager.is_effect_active(),
		"Effect should activate when in power fantasy mode")


func test_on_enemy_killed_uses_kill_duration() -> void:
	difficulty_manager.set_power_fantasy(true)
	last_chance_manager.set_active(false)

	manager.on_enemy_killed()

	assert_eq(manager._current_effect_duration_ms,
		MockPowerFantasyEffectsManager.KILL_EFFECT_DURATION_MS,
		"Kill effect should use KILL_EFFECT_DURATION_MS")


func test_on_enemy_killed_skipped_when_last_chance_active() -> void:
	difficulty_manager.set_power_fantasy(true)
	last_chance_manager.set_active(true)

	manager.on_enemy_killed()

	assert_false(manager.is_effect_active(),
		"Kill effect should be skipped when LastChance effect is already active")


func test_on_enemy_killed_logs_skip_when_last_chance_active() -> void:
	difficulty_manager.set_power_fantasy(true)
	last_chance_manager.set_active(true)
	manager.log_messages.clear()

	manager.on_enemy_killed()

	var found_skip_log := false
	for msg in manager.log_messages:
		if "skipping" in msg.to_lower():
			found_skip_log = true
			break

	assert_true(found_skip_log,
		"Should log a skipping message when LastChance effect prevents kill effect")


func test_on_enemy_killed_works_when_last_chance_manager_null() -> void:
	difficulty_manager.set_power_fantasy(true)
	manager.last_chance_manager = null

	manager.on_enemy_killed()

	assert_true(manager.is_effect_active(),
		"Kill effect should activate when last_chance_manager is null (no conflict)")


func test_on_enemy_killed_sets_time_scale() -> void:
	difficulty_manager.set_power_fantasy(true)
	last_chance_manager.set_active(false)

	manager.on_enemy_killed()

	assert_eq(manager.time_scale, MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE,
		"Time scale should be set to EFFECT_TIME_SCALE on enemy kill")


# ============================================================================
# on_grenade_exploded Guard Clause Tests
# ============================================================================


func test_on_grenade_exploded_does_nothing_when_not_power_fantasy() -> void:
	difficulty_manager.set_power_fantasy(false)

	manager.on_grenade_exploded()

	assert_false(last_chance_manager.grenade_last_chance_triggered,
		"Grenade effect should not trigger when not in power fantasy mode")
	assert_false(manager.is_effect_active(),
		"Manager effect should not activate when not in power fantasy mode")


func test_on_grenade_exploded_does_nothing_when_difficulty_manager_null() -> void:
	manager.difficulty_manager = null

	manager.on_grenade_exploded()

	assert_false(last_chance_manager.grenade_last_chance_triggered,
		"Grenade effect should not trigger when difficulty manager is null")


func test_on_grenade_exploded_delegates_to_last_chance_manager() -> void:
	difficulty_manager.set_power_fantasy(true)

	manager.on_grenade_exploded()

	assert_true(last_chance_manager.grenade_last_chance_triggered,
		"Should delegate to LastChanceEffectsManager.trigger_grenade_last_chance")


func test_on_grenade_exploded_passes_correct_duration_in_seconds() -> void:
	difficulty_manager.set_power_fantasy(true)

	manager.on_grenade_exploded()

	var expected_seconds := MockPowerFantasyEffectsManager.GRENADE_EFFECT_DURATION_MS / 1000.0
	assert_eq(last_chance_manager.grenade_last_chance_duration, expected_seconds,
		"Should pass duration converted from ms to seconds (2000ms = 2.0s)")


func test_on_grenade_exploded_falls_back_to_start_effect_without_last_chance_manager() -> void:
	difficulty_manager.set_power_fantasy(true)
	manager.last_chance_manager = null

	manager.on_grenade_exploded()

	assert_true(manager.is_effect_active(),
		"Should fall back to _start_effect when LastChanceEffectsManager is not available")
	assert_eq(manager._current_effect_duration_ms,
		MockPowerFantasyEffectsManager.GRENADE_EFFECT_DURATION_MS,
		"Fallback should use GRENADE_EFFECT_DURATION_MS")


func test_on_grenade_exploded_fallback_logs_warning() -> void:
	difficulty_manager.set_power_fantasy(true)
	manager.last_chance_manager = null
	manager.log_messages.clear()

	manager.on_grenade_exploded()

	var found_warning_log := false
	for msg in manager.log_messages:
		if "warning" in msg.to_lower() and "not available" in msg.to_lower():
			found_warning_log = true
			break

	assert_true(found_warning_log,
		"Should log a warning when falling back to simple slowdown")


func test_on_grenade_exploded_does_not_activate_local_effect_when_delegating() -> void:
	difficulty_manager.set_power_fantasy(true)
	# last_chance_manager is available

	manager.on_grenade_exploded()

	assert_false(manager.is_effect_active(),
		"Local effect should not be activated when delegating to LastChanceEffectsManager")


# ============================================================================
# Full Effect Lifecycle Tests
# ============================================================================


func test_full_lifecycle_start_to_end() -> void:
	# Step 1: Start the effect
	manager.set_simulated_ticks_msec(1000.0)
	manager._start_effect(300.0)

	assert_true(manager.is_effect_active(), "Step 1: Effect should be active")
	assert_eq(manager.time_scale, MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE,
		"Step 1: Time should be slowed")
	assert_true(manager.saturation_rect_visible, "Step 1: Saturation should be visible")

	# Step 2: Process before expiry
	manager.set_simulated_ticks_msec(1200.0)
	manager.process_check()

	assert_true(manager.is_effect_active(), "Step 2: Effect should still be active")

	# Step 3: Process after expiry
	manager.set_simulated_ticks_msec(1400.0)
	manager.process_check()

	assert_false(manager.is_effect_active(), "Step 3: Effect should have ended")
	assert_eq(manager.time_scale, 1.0, "Step 3: Time should be normal")
	assert_false(manager.saturation_rect_visible, "Step 3: Saturation should be hidden")


func test_full_lifecycle_enemy_kill_in_power_fantasy() -> void:
	difficulty_manager.set_power_fantasy(true)
	last_chance_manager.set_active(false)

	# Kill enemy
	manager.set_simulated_ticks_msec(1000.0)
	manager.on_enemy_killed()

	assert_true(manager.is_effect_active(), "Effect should activate on enemy kill")
	assert_eq(manager._current_effect_duration_ms, 300.0, "Duration should be 300ms")

	# Let effect expire
	manager.set_simulated_ticks_msec(1400.0)
	manager.process_check()

	assert_false(manager.is_effect_active(), "Effect should have expired")
	assert_eq(manager.time_scale, 1.0, "Time scale should be restored")


func test_full_lifecycle_multiple_kills_reset_timer() -> void:
	difficulty_manager.set_power_fantasy(true)
	last_chance_manager.set_active(false)

	# First kill
	manager.set_simulated_ticks_msec(1000.0)
	manager.on_enemy_killed()
	assert_true(manager.is_effect_active())

	# Second kill at 200ms (before first expires)
	manager.set_simulated_ticks_msec(1200.0)
	manager.on_enemy_killed()

	# At 300ms from start (first effect would have ended without reset)
	manager.set_simulated_ticks_msec(1300.0)
	manager.process_check()
	assert_true(manager.is_effect_active(),
		"Effect should still be active due to timer reset from second kill")

	# At 500ms from second kill start, effect should have expired
	manager.set_simulated_ticks_msec(1600.0)
	manager.process_check()
	assert_false(manager.is_effect_active(),
		"Effect should expire after full duration from reset point")


func test_full_lifecycle_reset_during_active_effect() -> void:
	manager._start_effect(300.0)
	assert_true(manager.is_effect_active())
	assert_eq(manager.time_scale, MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE)

	manager.reset_effects()

	assert_false(manager.is_effect_active(), "Effect should be cleared after reset")
	assert_eq(manager.time_scale, 1.0, "Time scale should be restored after reset")
	assert_false(manager.saturation_rect_visible, "Saturation should be hidden after reset")


func test_full_lifecycle_grenade_delegates_to_last_chance() -> void:
	difficulty_manager.set_power_fantasy(true)

	manager.on_grenade_exploded()

	assert_true(last_chance_manager.grenade_last_chance_triggered,
		"Grenade should delegate to LastChanceEffectsManager")
	assert_eq(last_chance_manager.grenade_last_chance_duration, 2.0,
		"Should pass 2.0 seconds (2000ms) to LastChanceEffectsManager")
	assert_false(manager.is_effect_active(),
		"Local effect should not be active when delegating")


# ============================================================================
# Edge Cases Tests
# ============================================================================


func test_double_end_effect_is_safe() -> void:
	manager._start_effect(300.0)
	manager._end_effect()
	manager._end_effect()

	assert_false(manager.is_effect_active(),
		"Double end should not cause issues")
	assert_eq(manager.time_scale, 1.0,
		"Time scale should be 1.0 after double end")


func test_end_effect_without_start_is_safe() -> void:
	manager._end_effect()

	assert_false(manager.is_effect_active(),
		"Ending without starting should not cause issues")
	assert_eq(manager.time_scale, 1.0,
		"Time scale should remain 1.0")


func test_reset_without_active_effect_is_safe() -> void:
	manager.reset_effects()

	assert_false(manager.is_effect_active(),
		"Reset without active effect should not cause issues")


func test_start_effect_with_zero_duration() -> void:
	manager.set_simulated_ticks_msec(1000.0)
	manager._start_effect(0.0)

	assert_true(manager.is_effect_active(),
		"Effect should be active immediately after start with zero duration")

	# Process should immediately end it
	manager.process_check()

	assert_false(manager.is_effect_active(),
		"Zero duration effect should end immediately on process")


func test_start_effect_with_very_large_duration() -> void:
	manager._start_effect(999999.0)

	assert_true(manager.is_effect_active(),
		"Effect should be active with very large duration")
	assert_eq(manager._current_effect_duration_ms, 999999.0,
		"Very large duration should be stored correctly")


func test_multiple_rapid_kills_keep_effect_alive() -> void:
	difficulty_manager.set_power_fantasy(true)
	last_chance_manager.set_active(false)

	# Simulate rapid kills at 100ms intervals
	manager.set_simulated_ticks_msec(1000.0)
	manager.on_enemy_killed()

	manager.set_simulated_ticks_msec(1100.0)
	manager.on_enemy_killed()

	manager.set_simulated_ticks_msec(1200.0)
	manager.on_enemy_killed()

	manager.set_simulated_ticks_msec(1300.0)
	manager.on_enemy_killed()

	# At 1300ms, last reset was at 1300ms so effect should be active for another 300ms
	manager.set_simulated_ticks_msec(1400.0)
	manager.process_check()

	assert_true(manager.is_effect_active(),
		"Rapid kills should keep the effect alive by resetting timer each time")

	# Effect should expire 300ms after last kill
	manager.set_simulated_ticks_msec(1700.0)
	manager.process_check()

	assert_false(manager.is_effect_active(),
		"Effect should expire after final kill's duration ends")


func test_on_enemy_killed_after_previous_effect_ended() -> void:
	difficulty_manager.set_power_fantasy(true)
	last_chance_manager.set_active(false)

	# First kill
	manager.set_simulated_ticks_msec(1000.0)
	manager.on_enemy_killed()

	# Let it expire
	manager.set_simulated_ticks_msec(1400.0)
	manager.process_check()
	assert_false(manager.is_effect_active())

	# Second kill after effect ended
	manager.set_simulated_ticks_msec(2000.0)
	manager.on_enemy_killed()

	assert_true(manager.is_effect_active(),
		"New kill after expired effect should start a new effect")
	assert_eq(manager.time_scale, MockPowerFantasyEffectsManager.EFFECT_TIME_SCALE,
		"Time scale should be slowed again for new effect")


func test_is_effect_active_reflects_internal_state() -> void:
	assert_eq(manager.is_effect_active(), manager._is_effect_active,
		"is_effect_active() should match _is_effect_active when false")

	manager._start_effect(300.0)
	assert_eq(manager.is_effect_active(), manager._is_effect_active,
		"is_effect_active() should match _is_effect_active when true")

	manager._end_effect()
	assert_eq(manager.is_effect_active(), manager._is_effect_active,
		"is_effect_active() should match _is_effect_active after ending")
