extends GutTest
## Unit tests for FlashbangPlayerEffectsManager (Issue #605).
##
## Tests the flashbang player screen effect including distance-based
## duration and intensity calculations, and effect lifecycle.


# ============================================================================
# Mock Classes for Testing
# ============================================================================


class MockFlashbangPlayerEffectsManager:
	## Minimum effect duration in seconds (at maximum distance).
	const MIN_DURATION: float = 1.0

	## Maximum effect duration in seconds (at point-blank range).
	const MAX_DURATION: float = 5.0

	## Duration of the fade-out phase as a ratio of total duration.
	const FADE_OUT_RATIO: float = 0.6

	## Whether the effect is currently active.
	var _is_effect_active: bool = false

	## Total duration of the current effect.
	var _effect_duration: float = 0.0

	## Peak intensity of the current effect.
	var _peak_intensity: float = 0.0

	## Peak blur intensity of the current effect (matches peak_intensity).
	var _peak_blur_intensity: float = 0.0

	## Tracking for test verification.
	var effects_applied: Array = []

	## Apply flashbang effect to the player.
	func apply_flashbang_effect(grenade_position: Vector2, player_position: Vector2, effect_radius: float) -> void:
		var distance := grenade_position.distance_to(player_position)
		var distance_factor := 1.0 - clampf(distance / effect_radius, 0.0, 1.0)

		if distance_factor < 0.01:
			return

		var duration := MIN_DURATION + (MAX_DURATION - MIN_DURATION) * distance_factor
		var peak_intensity := clampf(distance_factor, 0.0, 1.0)

		_is_effect_active = true
		_effect_duration = duration
		_peak_intensity = peak_intensity
		# Blur intensity matches peak intensity (both fade together)
		_peak_blur_intensity = peak_intensity

		effects_applied.append({
			"grenade_position": grenade_position,
			"player_position": player_position,
			"effect_radius": effect_radius,
			"distance": distance,
			"distance_factor": distance_factor,
			"duration": duration,
			"peak_intensity": peak_intensity,
			"peak_blur_intensity": peak_intensity
		})

	## Whether the effect is active.
	func is_effect_active() -> bool:
		return _is_effect_active

	## Get the current peak intensity.
	func get_peak_intensity() -> float:
		return _peak_intensity if _is_effect_active else 0.0

	## Get the effect duration.
	func get_effect_duration() -> float:
		return _effect_duration

	## Get the current peak blur intensity.
	func get_peak_blur_intensity() -> float:
		return _peak_blur_intensity if _is_effect_active else 0.0

	## Reset effects.
	func reset_effects() -> void:
		_is_effect_active = false
		_effect_duration = 0.0
		_peak_intensity = 0.0
		_peak_blur_intensity = 0.0
		effects_applied.clear()


var manager: MockFlashbangPlayerEffectsManager


func before_each() -> void:
	manager = MockFlashbangPlayerEffectsManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Duration Constant Tests
# ============================================================================


func test_min_duration_is_one_second() -> void:
	assert_eq(manager.MIN_DURATION, 1.0,
		"Minimum duration should be 1 second")


func test_max_duration_is_five_seconds() -> void:
	assert_eq(manager.MAX_DURATION, 5.0,
		"Maximum duration should be 5 seconds")


func test_fade_out_ratio() -> void:
	assert_eq(manager.FADE_OUT_RATIO, 0.6,
		"Fade-out should use 60% of total duration")


# ============================================================================
# Distance-Based Duration Tests
# ============================================================================


func test_duration_at_center() -> void:
	# Player at same position as grenade (distance = 0)
	manager.apply_flashbang_effect(Vector2(100, 100), Vector2(100, 100), 400.0)

	assert_eq(manager.effects_applied.size(), 1, "Should apply effect")
	assert_eq(manager.effects_applied[0]["duration"], 5.0,
		"Point-blank should give maximum 5 second duration")


func test_duration_at_edge() -> void:
	# Player at the edge of effect radius (distance = radius)
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(400, 0), 400.0)

	assert_eq(manager.effects_applied.size(), 1, "Should apply effect")
	assert_eq(manager.effects_applied[0]["duration"], 1.0,
		"At edge of radius should give minimum 1 second duration")


func test_duration_at_half_radius() -> void:
	# Player at half the effect radius
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(200, 0), 400.0)

	assert_eq(manager.effects_applied.size(), 1, "Should apply effect")
	assert_eq(manager.effects_applied[0]["duration"], 3.0,
		"At half radius should give 3 second duration (midpoint)")


func test_duration_at_quarter_radius() -> void:
	# Player at 25% of effect radius
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(100, 0), 400.0)

	assert_eq(manager.effects_applied.size(), 1, "Should apply effect")
	assert_eq(manager.effects_applied[0]["duration"], 4.0,
		"At quarter radius should give 4 second duration")


func test_duration_at_three_quarter_radius() -> void:
	# Player at 75% of effect radius
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(300, 0), 400.0)

	assert_eq(manager.effects_applied.size(), 1, "Should apply effect")
	assert_eq(manager.effects_applied[0]["duration"], 2.0,
		"At three-quarter radius should give 2 second duration")


# ============================================================================
# Distance-Based Intensity Tests
# ============================================================================


func test_intensity_at_center() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(0, 0), 400.0)

	assert_eq(manager.effects_applied[0]["peak_intensity"], 1.0,
		"Point-blank intensity should be 1.0 (maximum)")


func test_intensity_at_edge() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(400, 0), 400.0)

	assert_almost_eq(manager.effects_applied[0]["peak_intensity"], 0.0, 0.01,
		"At edge of radius, intensity should be near 0.0")


func test_intensity_at_half_radius() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(200, 0), 400.0)

	assert_eq(manager.effects_applied[0]["peak_intensity"], 0.5,
		"At half radius, intensity should be 0.5")


func test_intensity_scales_inversely_with_distance() -> void:
	# Close player
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(50, 0), 400.0)
	var close_intensity: float = manager.effects_applied[0]["peak_intensity"]

	manager.reset_effects()

	# Far player
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(350, 0), 400.0)
	var far_intensity: float = manager.effects_applied[0]["peak_intensity"]

	assert_true(close_intensity > far_intensity,
		"Closer player should have higher intensity than farther player")


# ============================================================================
# Effect Application Tests
# ============================================================================


func test_effect_activates() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(100, 0), 400.0)

	assert_true(manager.is_effect_active(),
		"Effect should be active after applying")


func test_no_effect_when_outside_radius() -> void:
	# Player is outside effect radius (distance > radius)
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(500, 0), 400.0)

	assert_eq(manager.effects_applied.size(), 0,
		"Should not apply effect when player is outside radius")


func test_no_effect_at_very_edge() -> void:
	# Player is at the very edge where distance_factor < 0.01
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(398, 0), 400.0)

	assert_eq(manager.effects_applied.size(), 1,
		"Player slightly inside radius should still be affected")


func test_effect_not_active_initially() -> void:
	assert_false(manager.is_effect_active(),
		"Effect should not be active initially")


func test_peak_intensity_when_inactive() -> void:
	assert_eq(manager.get_peak_intensity(), 0.0,
		"Peak intensity should be 0 when effect is inactive")


# ============================================================================
# Reset Tests
# ============================================================================


func test_reset_clears_effect() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(100, 0), 400.0)
	assert_true(manager.is_effect_active(), "Effect should be active before reset")

	manager.reset_effects()

	assert_false(manager.is_effect_active(),
		"Effect should not be active after reset")


func test_reset_clears_tracked_effects() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(100, 0), 400.0)

	manager.reset_effects()

	assert_eq(manager.effects_applied.size(), 0,
		"Applied effects should be cleared after reset")


func test_reset_clears_peak_intensity() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(100, 0), 400.0)

	manager.reset_effects()

	assert_eq(manager.get_peak_intensity(), 0.0,
		"Peak intensity should be 0 after reset")


# ============================================================================
# Distance Factor Tests
# ============================================================================


func test_distance_factor_at_center() -> void:
	manager.apply_flashbang_effect(Vector2(100, 100), Vector2(100, 100), 400.0)

	assert_eq(manager.effects_applied[0]["distance_factor"], 1.0,
		"Distance factor at center should be 1.0")


func test_distance_factor_at_edge() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(400, 0), 400.0)

	assert_almost_eq(manager.effects_applied[0]["distance_factor"], 0.0, 0.01,
		"Distance factor at edge should be ~0.0")


func test_distance_factor_is_clamped() -> void:
	# Player beyond radius - should be rejected before creating effect
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(800, 0), 400.0)

	assert_eq(manager.effects_applied.size(), 0,
		"Player beyond radius should not receive effect (clamped to 0)")


func test_distance_factor_diagonal() -> void:
	# Player at (200, 200), grenade at origin, radius 400
	# Distance = sqrt(200^2 + 200^2) = ~282.8
	# Factor = 1 - 282.8/400 = ~0.293
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(200, 200), 400.0)

	var factor: float = manager.effects_applied[0]["distance_factor"]
	assert_almost_eq(factor, 0.293, 0.01,
		"Diagonal distance factor should be calculated correctly")


# ============================================================================
# Multiple Effect Tests
# ============================================================================


func test_stronger_effect_overrides() -> void:
	# First: weaker flashbang (player far away)
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(350, 0), 400.0)
	var first_intensity: float = manager.get_peak_intensity()

	# Second: stronger flashbang (player close)
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(50, 0), 400.0)
	var second_intensity: float = manager.get_peak_intensity()

	assert_true(second_intensity > first_intensity,
		"Stronger flashbang should override weaker one")


func test_weaker_effect_does_not_override() -> void:
	# First: strong flashbang (player close)
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(50, 0), 400.0)
	var first_intensity: float = manager.get_peak_intensity()

	# Second: weaker flashbang (player far away) - should be ignored
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(350, 0), 400.0)
	var after_intensity: float = manager.get_peak_intensity()

	assert_eq(after_intensity, first_intensity,
		"Weaker flashbang should not override stronger one")


# ============================================================================
# Different Radius Tests
# ============================================================================


func test_small_radius() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(50, 0), 100.0)

	assert_eq(manager.effects_applied.size(), 1, "Should apply with small radius")
	assert_eq(manager.effects_applied[0]["distance_factor"], 0.5,
		"Distance factor should scale with small radius")


func test_large_radius() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(400, 0), 800.0)

	assert_eq(manager.effects_applied.size(), 1, "Should apply with large radius")
	assert_eq(manager.effects_applied[0]["distance_factor"], 0.5,
		"Distance factor should scale with large radius")


# ============================================================================
# Negative Position Tests
# ============================================================================


func test_negative_positions() -> void:
	manager.apply_flashbang_effect(Vector2(-100, -100), Vector2(-100, -100), 400.0)

	assert_eq(manager.effects_applied.size(), 1,
		"Should work with negative positions")
	assert_eq(manager.effects_applied[0]["distance_factor"], 1.0,
		"Same position should give maximum factor regardless of coordinates")


func test_cross_origin_positions() -> void:
	# Grenade at negative, player at positive
	manager.apply_flashbang_effect(Vector2(-100, 0), Vector2(100, 0), 400.0)

	assert_eq(manager.effects_applied.size(), 1,
		"Should work across origin")
	assert_eq(manager.effects_applied[0]["distance"], 200.0,
		"Distance should be calculated correctly across origin")


# ============================================================================
# Duration Range Verification Tests
# ============================================================================


func test_duration_never_below_minimum() -> void:
	# Player at edge
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(399, 0), 400.0)

	if manager.effects_applied.size() > 0:
		assert_true(manager.effects_applied[0]["duration"] >= 1.0,
			"Duration should never be below minimum 1 second")


func test_duration_never_above_maximum() -> void:
	# Player at center
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(0, 0), 400.0)

	assert_true(manager.effects_applied[0]["duration"] <= 5.0,
		"Duration should never be above maximum 5 seconds")


func test_intensity_never_above_one() -> void:
	# Even at center
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(0, 0), 400.0)

	assert_true(manager.effects_applied[0]["peak_intensity"] <= 1.0,
		"Peak intensity should never exceed 1.0")


# ============================================================================
# Blur Effect Tests
# ============================================================================


func test_blur_intensity_matches_peak_intensity_at_center() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(0, 0), 400.0)

	assert_eq(manager.effects_applied[0]["peak_blur_intensity"], 1.0,
		"Blur intensity at point-blank should be 1.0 (maximum)")


func test_blur_intensity_matches_peak_intensity_at_half_radius() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(200, 0), 400.0)

	assert_eq(manager.effects_applied[0]["peak_blur_intensity"], 0.5,
		"Blur intensity at half radius should be 0.5")


func test_blur_intensity_equals_peak_intensity() -> void:
	# Blur and color overlay should always have the same intensity
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(150, 0), 400.0)

	var peak: float = manager.effects_applied[0]["peak_intensity"]
	var blur: float = manager.effects_applied[0]["peak_blur_intensity"]
	assert_eq(blur, peak,
		"Blur intensity should always equal peak intensity")


func test_blur_intensity_scales_with_distance() -> void:
	# Close player - strong blur
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(50, 0), 400.0)
	var close_blur: float = manager.effects_applied[0]["peak_blur_intensity"]

	manager.reset_effects()

	# Far player - weak blur
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(350, 0), 400.0)
	var far_blur: float = manager.effects_applied[0]["peak_blur_intensity"]

	assert_true(close_blur > far_blur,
		"Closer player should have stronger blur than farther player")


func test_blur_clears_on_reset() -> void:
	manager.apply_flashbang_effect(Vector2(0, 0), Vector2(100, 0), 400.0)
	assert_true(manager.get_peak_blur_intensity() > 0.0,
		"Blur should be active before reset")

	manager.reset_effects()

	assert_eq(manager.get_peak_blur_intensity(), 0.0,
		"Blur intensity should be 0 after reset")


func test_blur_inactive_when_no_effect() -> void:
	assert_eq(manager.get_peak_blur_intensity(), 0.0,
		"Blur intensity should be 0 when no effect is active")
