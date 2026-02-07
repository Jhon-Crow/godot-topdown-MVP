extends GutTest
## Unit tests for PenultimateHitEffectsManager autoload.
##
## Tests the penultimate hit effect logic including state transitions,
## color saturation calculations, fade-out progress, effect lifecycle,
## and reset behavior without Godot scene tree dependencies.


# ============================================================================
# Mock DifficultyManager for Hard Mode Tests
# ============================================================================


class MockDifficultyManager:
	## Whether hard mode is active.
	var _hard_mode: bool = false

	func is_hard_mode() -> bool:
		return _hard_mode

	func set_hard_mode(value: bool) -> void:
		_hard_mode = value


# ============================================================================
# Mock PenultimateHitEffectsManager
# ============================================================================


class MockPenultimateHitEffectsManager:
	## The slowed down time scale during penultimate hit effect.
	const PENULTIMATE_TIME_SCALE: float = 0.1

	## Screen saturation multiplier (3x = boost of 2.0, since multiplier = 1.0 + boost).
	const SCREEN_SATURATION_BOOST: float = 2.0

	## Screen contrast multiplier (2x = boost of 1.0, since multiplier = 1.0 + boost).
	const SCREEN_CONTRAST_BOOST: float = 1.0

	## Enemy saturation multiplier (4x).
	const ENEMY_SATURATION_MULTIPLIER: float = 4.0

	## Player saturation multiplier (same as enemies for consistency).
	const PLAYER_SATURATION_MULTIPLIER: float = 4.0

	## Duration of the effect in real seconds (independent of time_scale).
	const EFFECT_DURATION_REAL_SECONDS: float = 3.0

	## Duration of the fade-out animation in seconds.
	const FADE_OUT_DURATION_SECONDS: float = 0.4

	## Whether the penultimate hit effect is currently active.
	var _is_effect_active: bool = false

	## Whether the visual effects are currently fading out.
	var _is_fading_out: bool = false

	## Timer for tracking effect duration (uses real time).
	var _effect_start_time: float = 0.0

	## The time when the fade-out started.
	var _fade_out_start_time: float = 0.0

	## Whether we've successfully connected to player signals.
	var _connected_to_player: bool = false

	## Simulated Engine.time_scale.
	var _time_scale: float = 1.0

	## Simulated shader parameters.
	var _saturation_boost: float = 0.0
	var _contrast_boost: float = 0.0

	## Whether the saturation rect overlay is visible.
	var _saturation_rect_visible: bool = false

	## Simulated current time (for testing).
	var _current_time: float = 0.0

	## Optional mock difficulty manager.
	var _difficulty_manager: MockDifficultyManager = null

	## Whether _remove_visual_effects was called (for tracking).
	var _remove_visual_effects_called: bool = false

	## Whether the fade-out completed.
	var _fade_complete_called: bool = false

	## Cached player reference (simulated).
	var _player = null

	## Cached player original colors (simulated).
	var _player_original_colors: Dictionary = {}

	## Cached enemy original colors (simulated).
	var _enemy_original_colors: Dictionary = {}

	func _check_penultimate_state(current_health: float) -> void:
		if current_health <= 1.0 and current_health > 0.0:
			# On hard mode, skip the regular penultimate hit effect
			if _difficulty_manager != null and _difficulty_manager.is_hard_mode():
				return

			# Player has 1 HP or less but is still alive
			if not _is_effect_active:
				_start_penultimate_effect()
			else:
				# Effect already active, just reset the timer to extend duration
				_effect_start_time = _current_time

	func _start_penultimate_effect() -> void:
		if _is_effect_active:
			return

		_is_effect_active = true
		_effect_start_time = _current_time

		# Slow down time
		_time_scale = PENULTIMATE_TIME_SCALE

		# Apply screen saturation and contrast
		_saturation_rect_visible = true
		_saturation_boost = SCREEN_SATURATION_BOOST
		_contrast_boost = SCREEN_CONTRAST_BOOST

	func _end_penultimate_effect() -> void:
		if not _is_effect_active:
			return

		_is_effect_active = false

		# Restore normal time immediately
		_time_scale = 1.0

		# Start visual effects fade-out
		_start_fade_out()

	func _start_fade_out() -> void:
		_is_fading_out = true
		_fade_out_start_time = _current_time

	func update_fade_out() -> void:
		if not _is_fading_out:
			return

		var elapsed := _current_time - _fade_out_start_time
		var progress := clampf(elapsed / FADE_OUT_DURATION_SECONDS, 0.0, 1.0)

		# Interpolate shader parameters from effect values to neutral values
		_saturation_boost = lerpf(SCREEN_SATURATION_BOOST, 0.0, progress)
		_contrast_boost = lerpf(SCREEN_CONTRAST_BOOST, 0.0, progress)

		# Check if fade-out is complete
		if progress >= 1.0:
			_complete_fade_out()

	func get_fade_progress() -> float:
		if not _is_fading_out:
			return 0.0
		var elapsed := _current_time - _fade_out_start_time
		return clampf(elapsed / FADE_OUT_DURATION_SECONDS, 0.0, 1.0)

	func _complete_fade_out() -> void:
		_is_fading_out = false
		_fade_complete_called = true
		_remove_visual_effects()

	func _remove_visual_effects() -> void:
		_remove_visual_effects_called = true
		_saturation_rect_visible = false
		_saturation_boost = 0.0
		_contrast_boost = 0.0

	func reset_effects() -> void:
		if _is_effect_active:
			_is_effect_active = false
			_time_scale = 1.0

		# Reset fade-out state
		_is_fading_out = false
		_fade_out_start_time = 0.0

		# Always remove visual effects immediately on reset
		_remove_visual_effects()

		_player = null
		_connected_to_player = false
		_player_original_colors.clear()

	func check_effect_duration() -> void:
		if _is_effect_active:
			var elapsed_real_time := _current_time - _effect_start_time
			if elapsed_real_time >= EFFECT_DURATION_REAL_SECONDS:
				_end_penultimate_effect()

	## Increase saturation of a color by a multiplier.
	## Uses the same algorithm as the saturation shader.
	static func saturate_color(color: Color, multiplier: float) -> Color:
		# Calculate luminance using standard weights
		var luminance := color.r * 0.299 + color.g * 0.587 + color.b * 0.114

		# Increase saturation by moving away from grayscale
		var saturated_r: float = lerp(luminance, color.r, multiplier)
		var saturated_g: float = lerp(luminance, color.g, multiplier)
		var saturated_b: float = lerp(luminance, color.b, multiplier)

		# Clamp to valid color range
		return Color(
			clampf(saturated_r, 0.0, 1.0),
			clampf(saturated_g, 0.0, 1.0),
			clampf(saturated_b, 0.0, 1.0),
			color.a
		)

	func advance_time(seconds: float) -> void:
		_current_time += seconds


var manager: MockPenultimateHitEffectsManager


func before_each() -> void:
	manager = MockPenultimateHitEffectsManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_penultimate_time_scale_constant() -> void:
	assert_eq(manager.PENULTIMATE_TIME_SCALE, 0.1,
		"Penultimate time scale should be 0.1 (10x slowdown)")


func test_screen_saturation_boost_constant() -> void:
	assert_eq(manager.SCREEN_SATURATION_BOOST, 2.0,
		"Screen saturation boost should be 2.0 (3x total)")


func test_screen_contrast_boost_constant() -> void:
	assert_eq(manager.SCREEN_CONTRAST_BOOST, 1.0,
		"Screen contrast boost should be 1.0 (2x total)")


func test_enemy_saturation_multiplier_constant() -> void:
	assert_eq(manager.ENEMY_SATURATION_MULTIPLIER, 4.0,
		"Enemy saturation multiplier should be 4.0")


func test_player_saturation_multiplier_constant() -> void:
	assert_eq(manager.PLAYER_SATURATION_MULTIPLIER, 4.0,
		"Player saturation multiplier should be 4.0")


func test_effect_duration_real_seconds_constant() -> void:
	assert_eq(manager.EFFECT_DURATION_REAL_SECONDS, 3.0,
		"Effect duration should be 3.0 real seconds")


func test_fade_out_duration_seconds_constant() -> void:
	assert_eq(manager.FADE_OUT_DURATION_SECONDS, 0.4,
		"Fade-out duration should be 0.4 seconds (400ms)")


func test_player_and_enemy_saturation_multipliers_match() -> void:
	assert_eq(manager.PLAYER_SATURATION_MULTIPLIER, manager.ENEMY_SATURATION_MULTIPLIER,
		"Player and enemy saturation multipliers should be equal for consistency")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_is_effect_active_false() -> void:
	assert_false(manager._is_effect_active,
		"Effect should not be active initially")


func test_initial_is_fading_out_false() -> void:
	assert_false(manager._is_fading_out,
		"Fade-out should not be active initially")


func test_initial_effect_start_time_zero() -> void:
	assert_eq(manager._effect_start_time, 0.0,
		"Effect start time should be 0.0 initially")


func test_initial_fade_out_start_time_zero() -> void:
	assert_eq(manager._fade_out_start_time, 0.0,
		"Fade-out start time should be 0.0 initially")


func test_initial_connected_to_player_false() -> void:
	assert_false(manager._connected_to_player,
		"Should not be connected to player initially")


func test_initial_time_scale_normal() -> void:
	assert_eq(manager._time_scale, 1.0,
		"Time scale should be 1.0 (normal) initially")


func test_initial_saturation_boost_zero() -> void:
	assert_eq(manager._saturation_boost, 0.0,
		"Saturation boost should be 0.0 initially")


func test_initial_contrast_boost_zero() -> void:
	assert_eq(manager._contrast_boost, 0.0,
		"Contrast boost should be 0.0 initially")


func test_initial_saturation_rect_not_visible() -> void:
	assert_false(manager._saturation_rect_visible,
		"Saturation rect should not be visible initially")


# ============================================================================
# _check_penultimate_state Tests - Triggering Effect
# ============================================================================


func test_check_penultimate_state_triggers_at_health_1() -> void:
	manager._check_penultimate_state(1.0)

	assert_true(manager._is_effect_active,
		"Effect should be active when health is exactly 1.0")


func test_check_penultimate_state_triggers_at_health_0_5() -> void:
	manager._check_penultimate_state(0.5)

	assert_true(manager._is_effect_active,
		"Effect should be active when health is 0.5")


func test_check_penultimate_state_triggers_at_health_0_1() -> void:
	manager._check_penultimate_state(0.1)

	assert_true(manager._is_effect_active,
		"Effect should be active when health is 0.1")


func test_check_penultimate_state_does_not_trigger_at_health_0() -> void:
	manager._check_penultimate_state(0.0)

	assert_false(manager._is_effect_active,
		"Effect should NOT be active when health is 0 (dead)")


func test_check_penultimate_state_does_not_trigger_at_negative_health() -> void:
	manager._check_penultimate_state(-1.0)

	assert_false(manager._is_effect_active,
		"Effect should NOT be active when health is negative")


func test_check_penultimate_state_does_not_trigger_at_health_2() -> void:
	manager._check_penultimate_state(2.0)

	assert_false(manager._is_effect_active,
		"Effect should NOT be active when health is above 1.0")


func test_check_penultimate_state_does_not_trigger_at_health_100() -> void:
	manager._check_penultimate_state(100.0)

	assert_false(manager._is_effect_active,
		"Effect should NOT be active when health is full")


func test_check_penultimate_state_does_not_trigger_at_health_1_01() -> void:
	manager._check_penultimate_state(1.01)

	assert_false(manager._is_effect_active,
		"Effect should NOT be active when health is just above 1.0")


# ============================================================================
# _check_penultimate_state Tests - Hard Mode Skip
# ============================================================================


func test_check_penultimate_state_skips_on_hard_mode() -> void:
	var difficulty := MockDifficultyManager.new()
	difficulty.set_hard_mode(true)
	manager._difficulty_manager = difficulty

	manager._check_penultimate_state(1.0)

	assert_false(manager._is_effect_active,
		"Effect should NOT trigger on hard mode")


func test_check_penultimate_state_triggers_on_normal_mode() -> void:
	var difficulty := MockDifficultyManager.new()
	difficulty.set_hard_mode(false)
	manager._difficulty_manager = difficulty

	manager._check_penultimate_state(1.0)

	assert_true(manager._is_effect_active,
		"Effect should trigger on normal mode")


func test_check_penultimate_state_triggers_with_no_difficulty_manager() -> void:
	manager._difficulty_manager = null

	manager._check_penultimate_state(1.0)

	assert_true(manager._is_effect_active,
		"Effect should trigger when no difficulty manager exists")


func test_check_penultimate_state_hard_mode_skip_at_low_health() -> void:
	var difficulty := MockDifficultyManager.new()
	difficulty.set_hard_mode(true)
	manager._difficulty_manager = difficulty

	manager._check_penultimate_state(0.5)

	assert_false(manager._is_effect_active,
		"Effect should NOT trigger on hard mode even at 0.5 HP")


# ============================================================================
# _check_penultimate_state Tests - Duration Extension
# ============================================================================


func test_check_penultimate_state_extends_duration_when_already_active() -> void:
	manager.advance_time(10.0)
	manager._check_penultimate_state(1.0)

	var first_start_time := manager._effect_start_time
	assert_true(manager._is_effect_active,
		"Effect should be active after first trigger")

	# Advance time and hit again
	manager.advance_time(1.0)
	manager._check_penultimate_state(0.5)

	assert_true(manager._is_effect_active,
		"Effect should still be active")
	assert_gt(manager._effect_start_time, first_start_time,
		"Effect start time should be updated (duration extended)")


func test_check_penultimate_state_extension_does_not_restart_effect() -> void:
	manager._check_penultimate_state(1.0)

	# Effect is now active, set time scale
	assert_eq(manager._time_scale, manager.PENULTIMATE_TIME_SCALE,
		"Time scale should be slowed")

	# Manually reset time scale to verify it doesn't get set again
	manager._time_scale = 0.5

	manager.advance_time(1.0)
	manager._check_penultimate_state(0.5)

	# If it just extended, it should NOT call _start_penultimate_effect again
	# (since _is_effect_active is true, _start_penultimate_effect returns early)
	assert_eq(manager._time_scale, 0.5,
		"Time scale should not be reset during extension (start is not called again)")


# ============================================================================
# _start_penultimate_effect Tests
# ============================================================================


func test_start_effect_sets_active() -> void:
	manager._start_penultimate_effect()

	assert_true(manager._is_effect_active,
		"Effect should be active after starting")


func test_start_effect_records_start_time() -> void:
	manager.advance_time(5.0)
	manager._start_penultimate_effect()

	assert_eq(manager._effect_start_time, 5.0,
		"Effect start time should match current time")


func test_start_effect_slows_time() -> void:
	manager._start_penultimate_effect()

	assert_eq(manager._time_scale, MockPenultimateHitEffectsManager.PENULTIMATE_TIME_SCALE,
		"Time scale should be set to PENULTIMATE_TIME_SCALE (0.1)")


func test_start_effect_shows_saturation_rect() -> void:
	manager._start_penultimate_effect()

	assert_true(manager._saturation_rect_visible,
		"Saturation rect should be visible after starting effect")


func test_start_effect_applies_saturation_boost() -> void:
	manager._start_penultimate_effect()

	assert_eq(manager._saturation_boost, MockPenultimateHitEffectsManager.SCREEN_SATURATION_BOOST,
		"Saturation boost should be set to SCREEN_SATURATION_BOOST")


func test_start_effect_applies_contrast_boost() -> void:
	manager._start_penultimate_effect()

	assert_eq(manager._contrast_boost, MockPenultimateHitEffectsManager.SCREEN_CONTRAST_BOOST,
		"Contrast boost should be set to SCREEN_CONTRAST_BOOST")


func test_start_effect_does_nothing_if_already_active() -> void:
	manager._start_penultimate_effect()
	var original_start_time := manager._effect_start_time

	manager.advance_time(1.0)
	manager._start_penultimate_effect()

	assert_eq(manager._effect_start_time, original_start_time,
		"Start time should not change when calling start on already active effect")


# ============================================================================
# _end_penultimate_effect Tests
# ============================================================================


func test_end_effect_deactivates() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()

	assert_false(manager._is_effect_active,
		"Effect should not be active after ending")


func test_end_effect_restores_time_scale() -> void:
	manager._start_penultimate_effect()

	assert_eq(manager._time_scale, 0.1,
		"Time should be slowed during effect")

	manager._end_penultimate_effect()

	assert_eq(manager._time_scale, 1.0,
		"Time scale should be restored to 1.0 after ending effect")


func test_end_effect_starts_fade_out() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()

	assert_true(manager._is_fading_out,
		"Fade-out should be active after ending effect")


func test_end_effect_does_nothing_if_not_active() -> void:
	manager._end_penultimate_effect()

	assert_false(manager._is_fading_out,
		"Fade-out should not start if effect was not active")
	assert_eq(manager._time_scale, 1.0,
		"Time scale should remain normal if effect was not active")


func test_end_effect_records_fade_out_start_time() -> void:
	manager.advance_time(5.0)
	manager._start_penultimate_effect()
	manager.advance_time(2.0)
	manager._end_penultimate_effect()

	assert_eq(manager._fade_out_start_time, 7.0,
		"Fade-out start time should match current time when effect ended")


# ============================================================================
# Effect Duration Tests
# ============================================================================


func test_effect_expires_after_duration() -> void:
	manager._start_penultimate_effect()
	manager.advance_time(MockPenultimateHitEffectsManager.EFFECT_DURATION_REAL_SECONDS)
	manager.check_effect_duration()

	assert_false(manager._is_effect_active,
		"Effect should end after EFFECT_DURATION_REAL_SECONDS")


func test_effect_does_not_expire_before_duration() -> void:
	manager._start_penultimate_effect()
	manager.advance_time(2.9)
	manager.check_effect_duration()

	assert_true(manager._is_effect_active,
		"Effect should still be active before duration expires")


func test_effect_expires_at_exact_duration() -> void:
	manager._start_penultimate_effect()
	manager.advance_time(3.0)
	manager.check_effect_duration()

	assert_false(manager._is_effect_active,
		"Effect should end at exactly EFFECT_DURATION_REAL_SECONDS")


func test_effect_starts_fadeout_after_expiring() -> void:
	manager._start_penultimate_effect()
	manager.advance_time(3.0)
	manager.check_effect_duration()

	assert_true(manager._is_fading_out,
		"Fade-out should start after effect duration expires")


func test_effect_duration_uses_real_time() -> void:
	manager._start_penultimate_effect()

	# Simulate time passing in small increments (like real frames)
	for i in range(30):
		manager.advance_time(0.1)

	manager.check_effect_duration()

	assert_false(manager._is_effect_active,
		"Effect should end after 3.0 seconds of accumulated real time")


func test_effect_duration_extended_resets_timer() -> void:
	manager._check_penultimate_state(1.0)

	# Advance 2 seconds
	manager.advance_time(2.0)
	manager.check_effect_duration()
	assert_true(manager._is_effect_active,
		"Effect should still be active at 2s")

	# Extend duration by getting hit again
	manager._check_penultimate_state(0.5)

	# Advance 2 more seconds (total 4s from start, but only 2s from extension)
	manager.advance_time(2.0)
	manager.check_effect_duration()

	assert_true(manager._is_effect_active,
		"Effect should still be active because duration was extended")

	# Advance 1 more second (3s from extension)
	manager.advance_time(1.0)
	manager.check_effect_duration()

	assert_false(manager._is_effect_active,
		"Effect should end 3s after the extension")


# ============================================================================
# Fade-Out Progress Tests
# ============================================================================


func test_fade_out_progress_at_start() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()

	var progress := manager.get_fade_progress()

	assert_almost_eq(progress, 0.0, 0.001,
		"Fade progress should be 0.0 at the start")


func test_fade_out_progress_at_quarter() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(0.1)

	var progress := manager.get_fade_progress()

	assert_almost_eq(progress, 0.25, 0.001,
		"Fade progress should be 0.25 at 100ms (25% of 400ms)")


func test_fade_out_progress_at_midpoint() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(0.2)

	var progress := manager.get_fade_progress()

	assert_almost_eq(progress, 0.5, 0.001,
		"Fade progress should be 0.5 at 200ms (50% of 400ms)")


func test_fade_out_progress_at_three_quarters() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(0.3)

	var progress := manager.get_fade_progress()

	assert_almost_eq(progress, 0.75, 0.001,
		"Fade progress should be 0.75 at 300ms (75% of 400ms)")


func test_fade_out_progress_clamped_at_1() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(1.0)

	var progress := manager.get_fade_progress()

	assert_almost_eq(progress, 1.0, 0.001,
		"Fade progress should be clamped at 1.0 even past duration")


func test_fade_out_progress_zero_when_not_fading() -> void:
	var progress := manager.get_fade_progress()

	assert_eq(progress, 0.0,
		"Fade progress should be 0.0 when not fading")


# ============================================================================
# Fade-Out Shader Parameter Interpolation Tests
# ============================================================================


func test_fade_out_saturation_at_start() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.update_fade_out()

	assert_almost_eq(manager._saturation_boost, 2.0, 0.01,
		"Saturation boost should be at full value at fade-out start")


func test_fade_out_saturation_at_midpoint() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(0.2)
	manager.update_fade_out()

	assert_almost_eq(manager._saturation_boost, 1.0, 0.01,
		"Saturation boost should be at 50% (2.0 -> 0.0) at midpoint")


func test_fade_out_saturation_at_end() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(0.4)
	manager.update_fade_out()

	assert_almost_eq(manager._saturation_boost, 0.0, 0.01,
		"Saturation boost should be 0.0 at fade-out end")


func test_fade_out_contrast_at_start() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.update_fade_out()

	assert_almost_eq(manager._contrast_boost, 1.0, 0.01,
		"Contrast boost should be at full value at fade-out start")


func test_fade_out_contrast_at_midpoint() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(0.2)
	manager.update_fade_out()

	assert_almost_eq(manager._contrast_boost, 0.5, 0.01,
		"Contrast boost should be at 50% (1.0 -> 0.0) at midpoint")


func test_fade_out_contrast_at_end() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(0.4)
	manager.update_fade_out()

	assert_almost_eq(manager._contrast_boost, 0.0, 0.01,
		"Contrast boost should be 0.0 at fade-out end")


func test_fade_out_completes_after_duration() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(0.4)
	manager.update_fade_out()

	assert_false(manager._is_fading_out,
		"Fade-out should be complete after FADE_OUT_DURATION_SECONDS")
	assert_true(manager._fade_complete_called,
		"Fade complete callback should be called")


func test_fade_out_does_not_complete_early() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(0.3)
	manager.update_fade_out()

	assert_true(manager._is_fading_out,
		"Fade-out should still be active at 300ms")
	assert_false(manager._fade_complete_called,
		"Fade complete should not be called before duration ends")


func test_fade_out_gradual_saturation_decrease() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()

	var previous_saturation := manager._saturation_boost

	# Simulate 4 frames (100ms each)
	for i in range(4):
		manager.advance_time(0.1)
		manager.update_fade_out()

		assert_true(manager._saturation_boost <= previous_saturation,
			"Saturation boost should decrease or stay same over time (frame %d)" % i)
		previous_saturation = manager._saturation_boost


func test_fade_out_gradual_contrast_decrease() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()

	var previous_contrast := manager._contrast_boost

	# Simulate 4 frames (100ms each)
	for i in range(4):
		manager.advance_time(0.1)
		manager.update_fade_out()

		assert_true(manager._contrast_boost <= previous_contrast,
			"Contrast boost should decrease or stay same over time (frame %d)" % i)
		previous_contrast = manager._contrast_boost


func test_fade_out_removes_visual_effects_on_complete() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(0.4)
	manager.update_fade_out()

	assert_true(manager._remove_visual_effects_called,
		"Visual effects should be removed after fade-out completes")
	assert_false(manager._saturation_rect_visible,
		"Saturation rect should be hidden after fade-out completes")


func test_fade_out_clamps_values_past_duration() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.advance_time(2.0)  # Way past fade duration
	manager.update_fade_out()

	assert_almost_eq(manager._saturation_boost, 0.0, 0.01,
		"Saturation should clamp at 0.0 past duration")
	assert_almost_eq(manager._contrast_boost, 0.0, 0.01,
		"Contrast should clamp at 0.0 past duration")


func test_fade_out_does_nothing_when_not_fading() -> void:
	manager._saturation_boost = 1.5
	manager._contrast_boost = 0.8
	manager.update_fade_out()

	assert_eq(manager._saturation_boost, 1.5,
		"Saturation should not change when not fading")
	assert_eq(manager._contrast_boost, 0.8,
		"Contrast should not change when not fading")


# ============================================================================
# _saturate_color Tests
# ============================================================================


func test_saturate_color_pure_red() -> void:
	var color := Color(1.0, 0.0, 0.0, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 4.0)

	# Luminance of pure red: 1.0 * 0.299 + 0.0 * 0.587 + 0.0 * 0.114 = 0.299
	# saturated_r = lerp(0.299, 1.0, 4.0) = 0.299 + 4.0 * (1.0 - 0.299) = 0.299 + 2.804 = 3.103 -> clamped to 1.0
	# saturated_g = lerp(0.299, 0.0, 4.0) = 0.299 + 4.0 * (0.0 - 0.299) = 0.299 - 1.196 = -0.897 -> clamped to 0.0
	# saturated_b = lerp(0.299, 0.0, 4.0) = same as g -> clamped to 0.0
	assert_almost_eq(result.r, 1.0, 0.001,
		"Saturated pure red R channel should clamp to 1.0")
	assert_almost_eq(result.g, 0.0, 0.001,
		"Saturated pure red G channel should clamp to 0.0")
	assert_almost_eq(result.b, 0.0, 0.001,
		"Saturated pure red B channel should clamp to 0.0")


func test_saturate_color_pure_green() -> void:
	var color := Color(0.0, 1.0, 0.0, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 4.0)

	# Luminance: 0.0 * 0.299 + 1.0 * 0.587 + 0.0 * 0.114 = 0.587
	# saturated_r = lerp(0.587, 0.0, 4.0) = 0.587 + 4.0 * (0.0 - 0.587) = -1.761 -> clamped to 0.0
	# saturated_g = lerp(0.587, 1.0, 4.0) = 0.587 + 4.0 * (1.0 - 0.587) = 0.587 + 1.652 = 2.239 -> clamped to 1.0
	# saturated_b = lerp(0.587, 0.0, 4.0) = same as r -> clamped to 0.0
	assert_almost_eq(result.r, 0.0, 0.001,
		"Saturated pure green R channel should clamp to 0.0")
	assert_almost_eq(result.g, 1.0, 0.001,
		"Saturated pure green G channel should clamp to 1.0")
	assert_almost_eq(result.b, 0.0, 0.001,
		"Saturated pure green B channel should clamp to 0.0")


func test_saturate_color_pure_blue() -> void:
	var color := Color(0.0, 0.0, 1.0, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 4.0)

	# Luminance: 0.0 * 0.299 + 0.0 * 0.587 + 1.0 * 0.114 = 0.114
	# saturated_r = lerp(0.114, 0.0, 4.0) = 0.114 + 4.0 * (0.0 - 0.114) = -0.342 -> clamped to 0.0
	# saturated_g = lerp(0.114, 0.0, 4.0) = same as r -> clamped to 0.0
	# saturated_b = lerp(0.114, 1.0, 4.0) = 0.114 + 4.0 * (1.0 - 0.114) = 0.114 + 3.544 = 3.658 -> clamped to 1.0
	assert_almost_eq(result.r, 0.0, 0.001,
		"Saturated pure blue R channel should clamp to 0.0")
	assert_almost_eq(result.g, 0.0, 0.001,
		"Saturated pure blue G channel should clamp to 0.0")
	assert_almost_eq(result.b, 1.0, 0.001,
		"Saturated pure blue B channel should clamp to 1.0")


func test_saturate_color_gray_stays_gray() -> void:
	var color := Color(0.5, 0.5, 0.5, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 4.0)

	# Luminance of gray: 0.5 * 0.299 + 0.5 * 0.587 + 0.5 * 0.114 = 0.5
	# Each channel: lerp(0.5, 0.5, 4.0) = 0.5 (no change since color equals luminance)
	assert_almost_eq(result.r, 0.5, 0.001,
		"Gray should remain unchanged when saturated (R)")
	assert_almost_eq(result.g, 0.5, 0.001,
		"Gray should remain unchanged when saturated (G)")
	assert_almost_eq(result.b, 0.5, 0.001,
		"Gray should remain unchanged when saturated (B)")


func test_saturate_color_white_stays_white() -> void:
	var color := Color(1.0, 1.0, 1.0, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 4.0)

	# Luminance: 1.0 * 0.299 + 1.0 * 0.587 + 1.0 * 0.114 = 1.0
	# Each channel: lerp(1.0, 1.0, 4.0) = 1.0
	assert_almost_eq(result.r, 1.0, 0.001,
		"White should remain white when saturated (R)")
	assert_almost_eq(result.g, 1.0, 0.001,
		"White should remain white when saturated (G)")
	assert_almost_eq(result.b, 1.0, 0.001,
		"White should remain white when saturated (B)")


func test_saturate_color_black_stays_black() -> void:
	var color := Color(0.0, 0.0, 0.0, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 4.0)

	# Luminance: 0.0
	# Each channel: lerp(0.0, 0.0, 4.0) = 0.0
	assert_almost_eq(result.r, 0.0, 0.001,
		"Black should remain black when saturated (R)")
	assert_almost_eq(result.g, 0.0, 0.001,
		"Black should remain black when saturated (G)")
	assert_almost_eq(result.b, 0.0, 0.001,
		"Black should remain black when saturated (B)")


func test_saturate_color_preserves_alpha() -> void:
	var color := Color(1.0, 0.0, 0.0, 0.5)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 4.0)

	assert_almost_eq(result.a, 0.5, 0.001,
		"Alpha channel should be preserved during saturation")


func test_saturate_color_multiplier_1_no_change() -> void:
	var color := Color(0.8, 0.3, 0.5, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 1.0)

	# With multiplier 1.0, lerp(luminance, channel, 1.0) = channel
	assert_almost_eq(result.r, 0.8, 0.001,
		"Multiplier 1.0 should not change R channel")
	assert_almost_eq(result.g, 0.3, 0.001,
		"Multiplier 1.0 should not change G channel")
	assert_almost_eq(result.b, 0.5, 0.001,
		"Multiplier 1.0 should not change B channel")


func test_saturate_color_multiplier_0_desaturates_to_grayscale() -> void:
	var color := Color(1.0, 0.0, 0.0, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 0.0)

	# Luminance of pure red: 0.299
	# With multiplier 0.0, lerp(0.299, channel, 0.0) = 0.299 for all channels
	var expected_luminance := 1.0 * 0.299 + 0.0 * 0.587 + 0.0 * 0.114
	assert_almost_eq(result.r, expected_luminance, 0.001,
		"Multiplier 0.0 should desaturate R to luminance")
	assert_almost_eq(result.g, expected_luminance, 0.001,
		"Multiplier 0.0 should desaturate G to luminance")
	assert_almost_eq(result.b, expected_luminance, 0.001,
		"Multiplier 0.0 should desaturate B to luminance")


func test_saturate_color_luminance_calculation() -> void:
	# Test with known color to verify luminance weights
	var color := Color(0.5, 0.5, 0.5, 1.0)

	# Luminance = 0.5 * 0.299 + 0.5 * 0.587 + 0.5 * 0.114 = 0.5 * 1.0 = 0.5
	# The standard weights should sum to 1.0
	var weight_sum := 0.299 + 0.587 + 0.114
	assert_almost_eq(weight_sum, 1.0, 0.001,
		"Luminance weights (0.299 + 0.587 + 0.114) should sum to 1.0")


func test_saturate_color_channels_clamped_to_valid_range() -> void:
	# A very saturated color with high multiplier should clamp
	var color := Color(1.0, 0.0, 0.0, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 10.0)

	assert_gte(result.r, 0.0, "R channel should be >= 0.0")
	assert_lte(result.r, 1.0, "R channel should be <= 1.0")
	assert_gte(result.g, 0.0, "G channel should be >= 0.0")
	assert_lte(result.g, 1.0, "G channel should be <= 1.0")
	assert_gte(result.b, 0.0, "B channel should be >= 0.0")
	assert_lte(result.b, 1.0, "B channel should be <= 1.0")


func test_saturate_color_mixed_color() -> void:
	# Test with a brownish color (0.6, 0.3, 0.1)
	var color := Color(0.6, 0.3, 0.1, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 2.0)

	# Luminance = 0.6 * 0.299 + 0.3 * 0.587 + 0.1 * 0.114 = 0.1794 + 0.1761 + 0.0114 = 0.3669
	var luminance := 0.6 * 0.299 + 0.3 * 0.587 + 0.1 * 0.114
	var expected_r := clampf(lerp(luminance, 0.6, 2.0), 0.0, 1.0)
	var expected_g := clampf(lerp(luminance, 0.3, 2.0), 0.0, 1.0)
	var expected_b := clampf(lerp(luminance, 0.1, 2.0), 0.0, 1.0)

	assert_almost_eq(result.r, expected_r, 0.001,
		"Mixed color saturated R should match expected")
	assert_almost_eq(result.g, expected_g, 0.001,
		"Mixed color saturated G should match expected")
	assert_almost_eq(result.b, expected_b, 0.001,
		"Mixed color saturated B should match expected")


func test_saturate_color_with_enemy_multiplier() -> void:
	var color := Color(0.8, 0.2, 0.2, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(
		color, MockPenultimateHitEffectsManager.ENEMY_SATURATION_MULTIPLIER)

	# Should produce a more vivid version of the reddish color
	assert_gt(result.r, result.g,
		"Red channel should be dominant after enemy saturation of reddish color")
	assert_gt(result.r, result.b,
		"Red channel should be dominant after enemy saturation of reddish color")


# ============================================================================
# reset_effects Tests
# ============================================================================


func test_reset_deactivates_effect() -> void:
	manager._start_penultimate_effect()

	assert_true(manager._is_effect_active,
		"Effect should be active before reset")

	manager.reset_effects()

	assert_false(manager._is_effect_active,
		"Effect should not be active after reset")


func test_reset_restores_time_scale() -> void:
	manager._start_penultimate_effect()

	assert_eq(manager._time_scale, 0.1,
		"Time should be slowed during effect")

	manager.reset_effects()

	assert_eq(manager._time_scale, 1.0,
		"Time scale should be restored to 1.0 after reset")


func test_reset_stops_fade_out() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()

	assert_true(manager._is_fading_out,
		"Fade-out should be active")

	manager.reset_effects()

	assert_false(manager._is_fading_out,
		"Fade-out should be stopped after reset")


func test_reset_clears_fade_out_start_time() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()
	manager.reset_effects()

	assert_eq(manager._fade_out_start_time, 0.0,
		"Fade-out start time should be reset to 0.0")


func test_reset_removes_visual_effects() -> void:
	manager._start_penultimate_effect()
	manager.reset_effects()

	assert_true(manager._remove_visual_effects_called,
		"Visual effects should be removed on reset")
	assert_false(manager._saturation_rect_visible,
		"Saturation rect should be hidden after reset")
	assert_eq(manager._saturation_boost, 0.0,
		"Saturation boost should be 0.0 after reset")
	assert_eq(manager._contrast_boost, 0.0,
		"Contrast boost should be 0.0 after reset")


func test_reset_clears_player_reference() -> void:
	manager._player = "some_player"
	manager._connected_to_player = true
	manager.reset_effects()

	assert_null(manager._player,
		"Player reference should be null after reset")
	assert_false(manager._connected_to_player,
		"Connected to player should be false after reset")


func test_reset_clears_player_original_colors() -> void:
	manager._player_original_colors["sprite1"] = Color.RED
	manager._player_original_colors["sprite2"] = Color.BLUE
	manager.reset_effects()

	assert_eq(manager._player_original_colors.size(), 0,
		"Player original colors should be cleared after reset")


func test_reset_when_no_effect_active_still_works() -> void:
	# Even without an active effect, reset should clear any stale state
	manager._saturation_rect_visible = true
	manager._saturation_boost = 1.5
	manager.reset_effects()

	assert_false(manager._saturation_rect_visible,
		"Saturation rect should be hidden after reset even if effect was not active")
	assert_eq(manager._saturation_boost, 0.0,
		"Saturation boost should be cleared after reset even if effect was not active")


func test_reset_during_fade_out_clears_visuals_immediately() -> void:
	manager._start_penultimate_effect()
	manager._end_penultimate_effect()

	# Advance partially through fade
	manager.advance_time(0.2)
	manager.update_fade_out()

	# Visual effects are still partially visible during fade
	assert_true(manager._is_fading_out,
		"Fade-out should be in progress")

	# Reset should clear everything immediately
	manager.reset_effects()

	assert_false(manager._is_fading_out,
		"Fade-out should be cancelled after reset")
	assert_false(manager._saturation_rect_visible,
		"Visual effects should be removed immediately on reset during fade-out")
	assert_eq(manager._saturation_boost, 0.0,
		"Saturation should be cleared immediately on reset during fade-out")
	assert_eq(manager._contrast_boost, 0.0,
		"Contrast should be cleared immediately on reset during fade-out")


# ============================================================================
# Full Effect Lifecycle Tests
# ============================================================================


func test_full_lifecycle_trigger_to_fade_complete() -> void:
	# 1. Player gets hit, health drops to 1
	manager._check_penultimate_state(1.0)
	assert_true(manager._is_effect_active, "Step 1: Effect should be active")
	assert_eq(manager._time_scale, 0.1, "Step 1: Time should be slowed")
	assert_true(manager._saturation_rect_visible, "Step 1: Overlay should be visible")

	# 2. Effect duration expires
	manager.advance_time(3.0)
	manager.check_effect_duration()
	assert_false(manager._is_effect_active, "Step 2: Effect should have ended")
	assert_eq(manager._time_scale, 1.0, "Step 2: Time should be normal")
	assert_true(manager._is_fading_out, "Step 2: Fade-out should have started")

	# 3. Fade-out progresses
	manager.advance_time(0.2)
	manager.update_fade_out()
	assert_true(manager._is_fading_out, "Step 3: Fade-out should still be in progress")
	assert_almost_eq(manager._saturation_boost, 1.0, 0.01,
		"Step 3: Saturation should be at 50%")

	# 4. Fade-out completes
	manager.advance_time(0.2)
	manager.update_fade_out()
	assert_false(manager._is_fading_out, "Step 4: Fade-out should be complete")
	assert_false(manager._saturation_rect_visible, "Step 4: Overlay should be hidden")
	assert_almost_eq(manager._saturation_boost, 0.0, 0.01,
		"Step 4: Saturation should be 0.0")
	assert_almost_eq(manager._contrast_boost, 0.0, 0.01,
		"Step 4: Contrast should be 0.0")


func test_lifecycle_trigger_extend_expire_fade() -> void:
	# 1. First hit at 1 HP
	manager._check_penultimate_state(1.0)
	assert_true(manager._is_effect_active, "Step 1: Effect should be active")

	# 2. Second hit extends duration at 2s
	manager.advance_time(2.0)
	manager._check_penultimate_state(0.5)
	assert_true(manager._is_effect_active, "Step 2: Effect should still be active (extended)")

	# 3. Check at 4s from start (2s from extension) - should still be active
	manager.advance_time(2.0)
	manager.check_effect_duration()
	assert_true(manager._is_effect_active, "Step 3: Effect should still be active")

	# 4. Check at 5.1s from start (3.1s from extension) - should expire
	manager.advance_time(1.1)
	manager.check_effect_duration()
	assert_false(manager._is_effect_active, "Step 4: Effect should have expired")
	assert_true(manager._is_fading_out, "Step 4: Fade-out should have started")

	# 5. Fade completes
	manager.advance_time(0.4)
	manager.update_fade_out()
	assert_false(manager._is_fading_out, "Step 5: Fade-out should be complete")


func test_lifecycle_trigger_then_scene_change() -> void:
	# 1. Effect triggers
	manager._check_penultimate_state(1.0)
	assert_true(manager._is_effect_active, "Step 1: Effect should be active")
	assert_eq(manager._time_scale, 0.1, "Step 1: Time should be slowed")

	# 2. Scene changes mid-effect (e.g., player dies and restarts)
	manager.reset_effects()
	assert_false(manager._is_effect_active, "Step 2: Effect should be deactivated")
	assert_eq(manager._time_scale, 1.0, "Step 2: Time should be normal")
	assert_false(manager._saturation_rect_visible, "Step 2: Overlay should be hidden")
	assert_false(manager._is_fading_out, "Step 2: No fade-out should be running")


func test_lifecycle_multiple_triggers_without_high_health() -> void:
	# Effect ends based on duration, not health recovery
	manager._check_penultimate_state(1.0)
	assert_true(manager._is_effect_active, "Effect should be active at 1 HP")

	# Health goes to 2 - effect should NOT end (duration-based only)
	manager._check_penultimate_state(2.0)
	assert_true(manager._is_effect_active,
		"Effect should remain active even when health goes above 1 (duration-based)")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_health_exactly_at_boundary_0() -> void:
	manager._check_penultimate_state(0.0)

	assert_false(manager._is_effect_active,
		"Health of exactly 0.0 should NOT trigger effect (player is dead)")


func test_health_very_small_positive() -> void:
	manager._check_penultimate_state(0.001)

	assert_true(manager._is_effect_active,
		"Very small positive health should trigger effect")


func test_health_exactly_1_triggers() -> void:
	manager._check_penultimate_state(1.0)

	assert_true(manager._is_effect_active,
		"Health of exactly 1.0 should trigger effect (boundary inclusive)")


func test_health_1_point_0_triggers_but_1_point_01_does_not() -> void:
	manager._check_penultimate_state(1.0)
	assert_true(manager._is_effect_active,
		"1.0 should trigger")

	# Reset
	manager = MockPenultimateHitEffectsManager.new()
	manager._check_penultimate_state(1.01)
	assert_false(manager._is_effect_active,
		"1.01 should NOT trigger")


func test_start_effect_idempotent() -> void:
	manager._start_penultimate_effect()
	var first_start := manager._effect_start_time

	manager.advance_time(1.0)
	manager._start_penultimate_effect()

	assert_eq(manager._effect_start_time, first_start,
		"Calling start twice should not change start time (guard clause)")


func test_end_effect_idempotent() -> void:
	manager._end_penultimate_effect()

	assert_false(manager._is_fading_out,
		"Calling end when not active should have no effect")

	assert_eq(manager._time_scale, 1.0,
		"Time scale should remain normal when ending an inactive effect")


func test_multiple_resets_are_safe() -> void:
	manager._start_penultimate_effect()
	manager.reset_effects()
	manager.reset_effects()
	manager.reset_effects()

	assert_false(manager._is_effect_active,
		"Multiple resets should be safe")
	assert_eq(manager._time_scale, 1.0,
		"Time scale should still be normal after multiple resets")


func test_saturate_color_alpha_zero_preserved() -> void:
	var color := Color(1.0, 0.0, 0.0, 0.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 4.0)

	assert_almost_eq(result.a, 0.0, 0.001,
		"Zero alpha should be preserved during saturation")


func test_saturate_color_high_multiplier_clamps() -> void:
	var color := Color(0.9, 0.1, 0.1, 1.0)
	var result := MockPenultimateHitEffectsManager.saturate_color(color, 100.0)

	assert_gte(result.r, 0.0, "R channel should be >= 0.0 with extreme multiplier")
	assert_lte(result.r, 1.0, "R channel should be <= 1.0 with extreme multiplier")
	assert_gte(result.g, 0.0, "G channel should be >= 0.0 with extreme multiplier")
	assert_lte(result.g, 1.0, "G channel should be <= 1.0 with extreme multiplier")
	assert_gte(result.b, 0.0, "B channel should be >= 0.0 with extreme multiplier")
	assert_lte(result.b, 1.0, "B channel should be <= 1.0 with extreme multiplier")
