extends GutTest
## Unit tests for visual effect fade-out animation (Issue #442).
##
## Tests the fade-out behavior of LastChanceEffectsManager and
## PenultimateHitEffectsManager to ensure smooth transitions.


# ============================================================================
# Mock LastChanceEffectsManager for Testing
# ============================================================================


class MockLastChanceEffectsManager:
	## Duration of the fade-out animation in seconds.
	const FADE_OUT_DURATION_SECONDS: float = 0.4

	## Sepia intensity for the shader (0.0-1.0).
	const SEPIA_INTENSITY: float = 0.7

	## Brightness reduction (0.0-1.0, where 1.0 is normal).
	const BRIGHTNESS: float = 0.6

	## Ripple effect strength.
	const RIPPLE_STRENGTH: float = 0.008

	## Player saturation multiplier.
	const PLAYER_SATURATION_MULTIPLIER: float = 4.0

	## Whether the visual effects are currently fading out.
	var _is_fading_out: bool = false

	## The time when the fade-out started.
	var _fade_out_start_time: float = 0.0

	## Simulated shader parameters.
	var _sepia_intensity: float = 0.0
	var _brightness: float = 1.0
	var _ripple_strength: float = 0.0

	## Whether effect was completed.
	var _fade_complete_called: bool = false

	## Simulated current time (for testing).
	var _current_time: float = 0.0

	func start_fade_out() -> void:
		_is_fading_out = true
		_fade_out_start_time = _current_time
		# Set initial values (effect is active)
		_sepia_intensity = SEPIA_INTENSITY
		_brightness = BRIGHTNESS
		_ripple_strength = RIPPLE_STRENGTH

	func update_fade_out() -> void:
		if not _is_fading_out:
			return

		var elapsed := _current_time - _fade_out_start_time
		var progress := clampf(elapsed / FADE_OUT_DURATION_SECONDS, 0.0, 1.0)

		# Interpolate shader parameters
		_sepia_intensity = lerpf(SEPIA_INTENSITY, 0.0, progress)
		_brightness = lerpf(BRIGHTNESS, 1.0, progress)
		_ripple_strength = lerpf(RIPPLE_STRENGTH, 0.0, progress)

		if progress >= 1.0:
			_complete_fade_out()

	func _complete_fade_out() -> void:
		_is_fading_out = false
		_fade_complete_called = true

	func advance_time(seconds: float) -> void:
		_current_time += seconds


# ============================================================================
# Mock PenultimateHitEffectsManager for Testing
# ============================================================================


class MockPenultimateHitEffectsManager:
	## Duration of the fade-out animation in seconds.
	const FADE_OUT_DURATION_SECONDS: float = 0.4

	## Screen saturation boost.
	const SCREEN_SATURATION_BOOST: float = 2.0

	## Screen contrast boost.
	const SCREEN_CONTRAST_BOOST: float = 1.0

	## Enemy saturation multiplier.
	const ENEMY_SATURATION_MULTIPLIER: float = 4.0

	## Player saturation multiplier.
	const PLAYER_SATURATION_MULTIPLIER: float = 4.0

	## Whether the visual effects are currently fading out.
	var _is_fading_out: bool = false

	## The time when the fade-out started.
	var _fade_out_start_time: float = 0.0

	## Simulated shader parameters.
	var _saturation_boost: float = 0.0
	var _contrast_boost: float = 0.0

	## Whether effect was completed.
	var _fade_complete_called: bool = false

	## Simulated current time (for testing).
	var _current_time: float = 0.0

	func start_fade_out() -> void:
		_is_fading_out = true
		_fade_out_start_time = _current_time
		# Set initial values (effect is active)
		_saturation_boost = SCREEN_SATURATION_BOOST
		_contrast_boost = SCREEN_CONTRAST_BOOST

	func update_fade_out() -> void:
		if not _is_fading_out:
			return

		var elapsed := _current_time - _fade_out_start_time
		var progress := clampf(elapsed / FADE_OUT_DURATION_SECONDS, 0.0, 1.0)

		# Interpolate shader parameters
		_saturation_boost = lerpf(SCREEN_SATURATION_BOOST, 0.0, progress)
		_contrast_boost = lerpf(SCREEN_CONTRAST_BOOST, 0.0, progress)

		if progress >= 1.0:
			_complete_fade_out()

	func _complete_fade_out() -> void:
		_is_fading_out = false
		_fade_complete_called = true

	func advance_time(seconds: float) -> void:
		_current_time += seconds


var last_chance: MockLastChanceEffectsManager
var penultimate: MockPenultimateHitEffectsManager


func before_each() -> void:
	last_chance = MockLastChanceEffectsManager.new()
	penultimate = MockPenultimateHitEffectsManager.new()


func after_each() -> void:
	last_chance = null
	penultimate = null


# ============================================================================
# LastChanceEffectsManager Fade-Out Tests (Issue #442)
# ============================================================================


func test_last_chance_fade_duration_constant() -> void:
	assert_eq(last_chance.FADE_OUT_DURATION_SECONDS, 0.4,
		"Fade-out duration should be 400ms (0.4 seconds)")


func test_last_chance_fade_out_starts() -> void:
	last_chance.start_fade_out()

	assert_true(last_chance._is_fading_out,
		"Fade-out should be active after start")


func test_last_chance_fade_out_initial_values() -> void:
	last_chance.start_fade_out()

	assert_eq(last_chance._sepia_intensity, 0.7,
		"Initial sepia intensity should be SEPIA_INTENSITY constant")
	assert_eq(last_chance._brightness, 0.6,
		"Initial brightness should be BRIGHTNESS constant")
	assert_eq(last_chance._ripple_strength, 0.008,
		"Initial ripple strength should be RIPPLE_STRENGTH constant")


func test_last_chance_fade_out_midpoint() -> void:
	last_chance.start_fade_out()
	last_chance.advance_time(0.2)  # 50% through fade
	last_chance.update_fade_out()

	# At 50% progress, values should be halfway between start and end
	assert_almost_eq(last_chance._sepia_intensity, 0.35, 0.01,
		"Sepia intensity should be at 50% (0.7 -> 0.0)")
	assert_almost_eq(last_chance._brightness, 0.8, 0.01,
		"Brightness should be at 50% (0.6 -> 1.0)")
	assert_almost_eq(last_chance._ripple_strength, 0.004, 0.001,
		"Ripple strength should be at 50% (0.008 -> 0.0)")


func test_last_chance_fade_out_completes() -> void:
	last_chance.start_fade_out()
	last_chance.advance_time(0.4)  # Full fade duration
	last_chance.update_fade_out()

	assert_false(last_chance._is_fading_out,
		"Fade-out should be complete after 400ms")
	assert_true(last_chance._fade_complete_called,
		"Fade complete callback should be called")


func test_last_chance_fade_out_final_values() -> void:
	last_chance.start_fade_out()
	last_chance.advance_time(0.4)
	last_chance.update_fade_out()

	assert_almost_eq(last_chance._sepia_intensity, 0.0, 0.01,
		"Final sepia intensity should be 0.0")
	assert_almost_eq(last_chance._brightness, 1.0, 0.01,
		"Final brightness should be 1.0")
	assert_almost_eq(last_chance._ripple_strength, 0.0, 0.001,
		"Final ripple strength should be 0.0")


func test_last_chance_fade_out_gradual_progression() -> void:
	last_chance.start_fade_out()

	var previous_sepia := last_chance._sepia_intensity
	var previous_brightness := last_chance._brightness

	# Simulate 4 frames (100ms each)
	for i in range(4):
		last_chance.advance_time(0.1)
		last_chance.update_fade_out()

		assert_true(last_chance._sepia_intensity <= previous_sepia,
			"Sepia should decrease or stay same over time")
		assert_true(last_chance._brightness >= previous_brightness,
			"Brightness should increase or stay same over time")

		previous_sepia = last_chance._sepia_intensity
		previous_brightness = last_chance._brightness


func test_last_chance_fade_does_not_complete_early() -> void:
	last_chance.start_fade_out()
	last_chance.advance_time(0.3)  # 75% through fade
	last_chance.update_fade_out()

	assert_true(last_chance._is_fading_out,
		"Fade-out should still be active before 400ms")
	assert_false(last_chance._fade_complete_called,
		"Fade complete should not be called before 400ms")


func test_last_chance_fade_clamps_at_full_progress() -> void:
	last_chance.start_fade_out()
	last_chance.advance_time(1.0)  # Way past fade duration
	last_chance.update_fade_out()

	# Values should be clamped to final values, not overshoot
	assert_almost_eq(last_chance._sepia_intensity, 0.0, 0.01,
		"Sepia should clamp at 0.0")
	assert_almost_eq(last_chance._brightness, 1.0, 0.01,
		"Brightness should clamp at 1.0")


# ============================================================================
# PenultimateHitEffectsManager Fade-Out Tests (Issue #442)
# ============================================================================


func test_penultimate_fade_duration_constant() -> void:
	assert_eq(penultimate.FADE_OUT_DURATION_SECONDS, 0.4,
		"Fade-out duration should be 400ms (0.4 seconds)")


func test_penultimate_fade_out_starts() -> void:
	penultimate.start_fade_out()

	assert_true(penultimate._is_fading_out,
		"Fade-out should be active after start")


func test_penultimate_fade_out_initial_values() -> void:
	penultimate.start_fade_out()

	assert_eq(penultimate._saturation_boost, 2.0,
		"Initial saturation boost should be SCREEN_SATURATION_BOOST constant")
	assert_eq(penultimate._contrast_boost, 1.0,
		"Initial contrast boost should be SCREEN_CONTRAST_BOOST constant")


func test_penultimate_fade_out_midpoint() -> void:
	penultimate.start_fade_out()
	penultimate.advance_time(0.2)  # 50% through fade
	penultimate.update_fade_out()

	# At 50% progress, values should be halfway between start and end
	assert_almost_eq(penultimate._saturation_boost, 1.0, 0.01,
		"Saturation boost should be at 50% (2.0 -> 0.0)")
	assert_almost_eq(penultimate._contrast_boost, 0.5, 0.01,
		"Contrast boost should be at 50% (1.0 -> 0.0)")


func test_penultimate_fade_out_completes() -> void:
	penultimate.start_fade_out()
	penultimate.advance_time(0.4)  # Full fade duration
	penultimate.update_fade_out()

	assert_false(penultimate._is_fading_out,
		"Fade-out should be complete after 400ms")
	assert_true(penultimate._fade_complete_called,
		"Fade complete callback should be called")


func test_penultimate_fade_out_final_values() -> void:
	penultimate.start_fade_out()
	penultimate.advance_time(0.4)
	penultimate.update_fade_out()

	assert_almost_eq(penultimate._saturation_boost, 0.0, 0.01,
		"Final saturation boost should be 0.0")
	assert_almost_eq(penultimate._contrast_boost, 0.0, 0.01,
		"Final contrast boost should be 0.0")


func test_penultimate_fade_out_gradual_progression() -> void:
	penultimate.start_fade_out()

	var previous_saturation := penultimate._saturation_boost
	var previous_contrast := penultimate._contrast_boost

	# Simulate 4 frames (100ms each)
	for i in range(4):
		penultimate.advance_time(0.1)
		penultimate.update_fade_out()

		assert_true(penultimate._saturation_boost <= previous_saturation,
			"Saturation boost should decrease or stay same over time")
		assert_true(penultimate._contrast_boost <= previous_contrast,
			"Contrast boost should decrease or stay same over time")

		previous_saturation = penultimate._saturation_boost
		previous_contrast = penultimate._contrast_boost


# ============================================================================
# Both Effects Fade Consistency Tests
# ============================================================================


func test_both_effects_same_fade_duration() -> void:
	assert_eq(
		last_chance.FADE_OUT_DURATION_SECONDS,
		penultimate.FADE_OUT_DURATION_SECONDS,
		"Both effects should have the same fade-out duration (400ms)"
	)


func test_both_effects_fade_completes_at_same_time() -> void:
	last_chance.start_fade_out()
	penultimate.start_fade_out()

	# Advance to just before completion
	last_chance.advance_time(0.39)
	penultimate.advance_time(0.39)
	last_chance.update_fade_out()
	penultimate.update_fade_out()

	assert_true(last_chance._is_fading_out,
		"Last chance should still be fading at 390ms")
	assert_true(penultimate._is_fading_out,
		"Penultimate should still be fading at 390ms")

	# Advance to completion
	last_chance.advance_time(0.02)
	penultimate.advance_time(0.02)
	last_chance.update_fade_out()
	penultimate.update_fade_out()

	assert_false(last_chance._is_fading_out,
		"Last chance should be complete at 410ms")
	assert_false(penultimate._is_fading_out,
		"Penultimate should be complete at 410ms")


# ============================================================================
# Scene Change Reset Tests (Issue #452)
# ============================================================================


## Mock extended for testing reset behavior
class MockLastChanceEffectsManagerWithReset:
	## Duration of the fade-out animation in seconds.
	const FADE_OUT_DURATION_SECONDS: float = 0.4

	## Sepia intensity for the shader (0.0-1.0).
	const SEPIA_INTENSITY: float = 0.7

	## Brightness reduction (0.0-1.0, where 1.0 is normal).
	const BRIGHTNESS: float = 0.6

	## Ripple effect strength.
	const RIPPLE_STRENGTH: float = 0.008

	## Player saturation multiplier.
	const PLAYER_SATURATION_MULTIPLIER: float = 4.0

	## Whether effect is currently active (time freeze).
	var _is_effect_active: bool = false

	## Whether the visual effects are currently fading out.
	var _is_fading_out: bool = false

	## The time when the fade-out started.
	var _fade_out_start_time: float = 0.0

	## Simulated shader parameters.
	var _sepia_intensity: float = 0.0
	var _brightness: float = 1.0
	var _ripple_strength: float = 0.0

	## Whether effect overlay is visible.
	var _effect_rect_visible: bool = false

	## Simulated current time (for testing).
	var _current_time: float = 0.0

	func start_effect() -> void:
		_is_effect_active = true
		_effect_rect_visible = true
		_sepia_intensity = SEPIA_INTENSITY
		_brightness = BRIGHTNESS
		_ripple_strength = RIPPLE_STRENGTH

	func start_fade_out() -> void:
		_is_fading_out = true
		_fade_out_start_time = _current_time

	func _remove_visual_effects() -> void:
		_effect_rect_visible = false
		_sepia_intensity = 0.0
		_brightness = 1.0
		_ripple_strength = 0.0

	## This simulates the FIXED reset_effects() function (Issue #452).
	## It now calls _remove_visual_effects() directly during scene change.
	func reset_effects() -> void:
		if _is_effect_active:
			_is_effect_active = false
			# Would call _unfreeze_time() here in real code

		# Reset fade-out state
		_is_fading_out = false
		_fade_out_start_time = 0.0

		# CRITICAL FIX (Issue #452): Always remove visual effects immediately
		_remove_visual_effects()

	func advance_time(seconds: float) -> void:
		_current_time += seconds


var reset_mock: MockLastChanceEffectsManagerWithReset


func test_reset_during_active_effect_clears_visuals() -> void:
	reset_mock = MockLastChanceEffectsManagerWithReset.new()

	# Start the effect
	reset_mock.start_effect()

	assert_true(reset_mock._effect_rect_visible,
		"Effect overlay should be visible when effect is active")
	assert_eq(reset_mock._sepia_intensity, 0.7,
		"Sepia should be set when effect is active")

	# Simulate scene change (reset)
	reset_mock.reset_effects()

	assert_false(reset_mock._effect_rect_visible,
		"Effect overlay should be hidden after reset (Issue #452)")
	assert_eq(reset_mock._sepia_intensity, 0.0,
		"Sepia should be cleared after reset")
	assert_eq(reset_mock._brightness, 1.0,
		"Brightness should be reset to normal after reset")
	assert_eq(reset_mock._ripple_strength, 0.0,
		"Ripple should be cleared after reset")


func test_reset_during_fadeout_clears_visuals_immediately() -> void:
	reset_mock = MockLastChanceEffectsManagerWithReset.new()

	# Start the effect and begin fade-out
	reset_mock.start_effect()
	reset_mock.start_fade_out()

	# Advance time partially through fade-out
	reset_mock.advance_time(0.1)

	assert_true(reset_mock._is_fading_out,
		"Fade-out should be active")
	assert_true(reset_mock._effect_rect_visible,
		"Effect should still be visible during fade-out")

	# Simulate scene change (reset) during fade-out
	reset_mock.reset_effects()

	assert_false(reset_mock._is_fading_out,
		"Fade-out should be cancelled after reset")
	assert_false(reset_mock._effect_rect_visible,
		"Effect overlay should be hidden immediately after reset during fade-out (Issue #452)")
	assert_eq(reset_mock._sepia_intensity, 0.0,
		"Sepia should be cleared after reset during fade-out")


func test_reset_clears_effect_active_state() -> void:
	reset_mock = MockLastChanceEffectsManagerWithReset.new()

	reset_mock.start_effect()
	assert_true(reset_mock._is_effect_active,
		"Effect should be active")

	reset_mock.reset_effects()
	assert_false(reset_mock._is_effect_active,
		"Effect should be deactivated after reset")


func test_reset_when_no_effect_active_still_clears_visuals() -> void:
	reset_mock = MockLastChanceEffectsManagerWithReset.new()

	# Manually set some visual state without going through start_effect
	reset_mock._effect_rect_visible = true
	reset_mock._sepia_intensity = 0.5
	reset_mock._brightness = 0.8
	reset_mock._ripple_strength = 0.005

	# Reset should still clear visuals even if effect wasn't "active"
	reset_mock.reset_effects()

	assert_false(reset_mock._effect_rect_visible,
		"Effect overlay should be hidden after reset (Issue #452)")
	assert_eq(reset_mock._sepia_intensity, 0.0,
		"Sepia should be cleared after reset")
	assert_eq(reset_mock._brightness, 1.0,
		"Brightness should be reset")
	assert_eq(reset_mock._ripple_strength, 0.0,
		"Ripple should be cleared")


# ============================================================================
# PenultimateHitEffectsManager Scene Change Reset Tests (Issue #452)
# ============================================================================


## Mock extended for testing PenultimateHit reset behavior
class MockPenultimateHitEffectsManagerWithReset:
	## Duration of the fade-out animation in seconds.
	const FADE_OUT_DURATION_SECONDS: float = 0.4

	## Screen saturation boost.
	const SCREEN_SATURATION_BOOST: float = 2.0

	## Screen contrast boost.
	const SCREEN_CONTRAST_BOOST: float = 1.0

	## Whether effect is currently active (slow-mo).
	var _is_effect_active: bool = false

	## Whether the visual effects are currently fading out.
	var _is_fading_out: bool = false

	## The time when the fade-out started.
	var _fade_out_start_time: float = 0.0

	## Simulated shader parameters.
	var _saturation_boost: float = 0.0
	var _contrast_boost: float = 0.0

	## Whether effect overlay is visible.
	var _saturation_rect_visible: bool = false

	## Simulated time scale (normal = 1.0).
	var _time_scale: float = 1.0

	## Simulated current time (for testing).
	var _current_time: float = 0.0

	func start_effect() -> void:
		_is_effect_active = true
		_saturation_rect_visible = true
		_saturation_boost = SCREEN_SATURATION_BOOST
		_contrast_boost = SCREEN_CONTRAST_BOOST
		_time_scale = 0.1  # Slow-mo

	func start_fade_out() -> void:
		_is_fading_out = true
		_fade_out_start_time = _current_time
		_time_scale = 1.0  # Restore normal time

	func _remove_visual_effects() -> void:
		_saturation_rect_visible = false
		_saturation_boost = 0.0
		_contrast_boost = 0.0

	## This simulates the FIXED reset_effects() function (Issue #452).
	## It now calls _remove_visual_effects() directly during scene change.
	func reset_effects() -> void:
		if _is_effect_active:
			_is_effect_active = false
			_time_scale = 1.0

		# Reset fade-out state
		_is_fading_out = false
		_fade_out_start_time = 0.0

		# CRITICAL FIX (Issue #452): Always remove visual effects immediately
		_remove_visual_effects()

	func advance_time(seconds: float) -> void:
		_current_time += seconds


var penultimate_reset_mock: MockPenultimateHitEffectsManagerWithReset


func test_penultimate_reset_during_active_effect_clears_visuals() -> void:
	penultimate_reset_mock = MockPenultimateHitEffectsManagerWithReset.new()

	# Start the effect
	penultimate_reset_mock.start_effect()

	assert_true(penultimate_reset_mock._saturation_rect_visible,
		"Effect overlay should be visible when effect is active")
	assert_eq(penultimate_reset_mock._saturation_boost, 2.0,
		"Saturation should be set when effect is active")
	assert_eq(penultimate_reset_mock._time_scale, 0.1,
		"Time scale should be slowed during effect")

	# Simulate scene change (reset)
	penultimate_reset_mock.reset_effects()

	assert_false(penultimate_reset_mock._saturation_rect_visible,
		"Effect overlay should be hidden after reset (Issue #452)")
	assert_eq(penultimate_reset_mock._saturation_boost, 0.0,
		"Saturation should be cleared after reset")
	assert_eq(penultimate_reset_mock._contrast_boost, 0.0,
		"Contrast should be cleared after reset")
	assert_eq(penultimate_reset_mock._time_scale, 1.0,
		"Time scale should be restored to normal after reset")


func test_penultimate_reset_during_fadeout_clears_visuals_immediately() -> void:
	penultimate_reset_mock = MockPenultimateHitEffectsManagerWithReset.new()

	# Start the effect and begin fade-out
	penultimate_reset_mock.start_effect()
	penultimate_reset_mock.start_fade_out()

	# Advance time partially through fade-out
	penultimate_reset_mock.advance_time(0.1)

	assert_true(penultimate_reset_mock._is_fading_out,
		"Fade-out should be active")
	assert_true(penultimate_reset_mock._saturation_rect_visible,
		"Effect should still be visible during fade-out")

	# Simulate scene change (reset) during fade-out
	penultimate_reset_mock.reset_effects()

	assert_false(penultimate_reset_mock._is_fading_out,
		"Fade-out should be cancelled after reset")
	assert_false(penultimate_reset_mock._saturation_rect_visible,
		"Effect overlay should be hidden immediately after reset during fade-out (Issue #452)")
	assert_eq(penultimate_reset_mock._saturation_boost, 0.0,
		"Saturation should be cleared after reset during fade-out")


func test_penultimate_reset_clears_effect_active_state() -> void:
	penultimate_reset_mock = MockPenultimateHitEffectsManagerWithReset.new()

	penultimate_reset_mock.start_effect()
	assert_true(penultimate_reset_mock._is_effect_active,
		"Effect should be active")

	penultimate_reset_mock.reset_effects()
	assert_false(penultimate_reset_mock._is_effect_active,
		"Effect should be deactivated after reset")


func test_penultimate_reset_when_no_effect_active_still_clears_visuals() -> void:
	penultimate_reset_mock = MockPenultimateHitEffectsManagerWithReset.new()

	# Manually set some visual state without going through start_effect
	penultimate_reset_mock._saturation_rect_visible = true
	penultimate_reset_mock._saturation_boost = 1.5
	penultimate_reset_mock._contrast_boost = 0.8

	# Reset should still clear visuals even if effect wasn't "active"
	penultimate_reset_mock.reset_effects()

	assert_false(penultimate_reset_mock._saturation_rect_visible,
		"Effect overlay should be hidden after reset (Issue #452)")
	assert_eq(penultimate_reset_mock._saturation_boost, 0.0,
		"Saturation should be cleared after reset")
	assert_eq(penultimate_reset_mock._contrast_boost, 0.0,
		"Contrast should be cleared after reset")


func test_penultimate_reset_restores_time_scale() -> void:
	penultimate_reset_mock = MockPenultimateHitEffectsManagerWithReset.new()

	# Start effect (slows time)
	penultimate_reset_mock.start_effect()
	assert_eq(penultimate_reset_mock._time_scale, 0.1,
		"Time should be slowed during effect")

	# Reset without going through normal end_effect flow
	penultimate_reset_mock.reset_effects()

	assert_eq(penultimate_reset_mock._time_scale, 1.0,
		"Time scale should be restored to normal after reset (Issue #452)")
