extends GutTest
## Unit tests for LoudspeakerConeEffect.
##
## Tests the expanding sound wave cone effect used by the
## loudspeaker active item.


# ============================================================================
# Mock LoudspeakerConeEffect for Logic Tests
# ============================================================================


class MockConeEffect:
	const CONE_HALF_ANGLE_DEG: float = 50.0
	const MAX_RADIUS: float = 400.0
	const MIN_RADIUS: float = 30.0
	const WAVE_THICKNESS: float = 28.0
	const EXPAND_DURATION: float = 0.55
	const WAVE_COLOR: Color = Color(0.3, 0.9, 1.0, 0.75)
	const ARC_SEGMENTS: int = 32

	var _is_playing: bool = false
	var _progress: float = 0.0
	var _direction: Vector2 = Vector2.ZERO

	func play(direction: Vector2) -> void:
		_direction = direction
		_progress = 0.0
		_is_playing = true

	func stop() -> void:
		_is_playing = false
		_progress = 0.0

	func is_playing() -> bool:
		return _is_playing

	func process(delta: float) -> void:
		if not _is_playing:
			return
		_progress += delta / EXPAND_DURATION
		if _progress >= 1.0:
			_is_playing = false

	func get_current_radius() -> float:
		return MIN_RADIUS + (MAX_RADIUS - MIN_RADIUS) * _progress


# ============================================================================
# Constants Tests
# ============================================================================


func test_cone_half_angle() -> void:
	assert_eq(MockConeEffect.CONE_HALF_ANGLE_DEG, 50.0, "Cone half angle should be 50 degrees")


func test_max_radius() -> void:
	assert_eq(MockConeEffect.MAX_RADIUS, 400.0, "Max radius should be 400 pixels")


func test_min_radius() -> void:
	assert_eq(MockConeEffect.MIN_RADIUS, 30.0, "Min radius should be 30 pixels")


func test_wave_thickness() -> void:
	assert_eq(MockConeEffect.WAVE_THICKNESS, 28.0, "Wave thickness should be 28 pixels")


func test_expand_duration() -> void:
	assert_eq(MockConeEffect.EXPAND_DURATION, 0.55, "Expand duration should be 0.55 seconds")


func test_arc_segments() -> void:
	assert_eq(MockConeEffect.ARC_SEGMENTS, 32, "Arc segments should be 32")


func test_wave_color_is_cyan() -> void:
	var c := MockConeEffect.WAVE_COLOR
	assert_almost_eq(c.r, 0.3, 0.001, "Wave red should be 0.3")
	assert_almost_eq(c.g, 0.9, 0.001, "Wave green should be 0.9")
	assert_almost_eq(c.b, 1.0, 0.001, "Wave blue should be 1.0")
	assert_almost_eq(c.a, 0.75, 0.001, "Wave alpha should be 0.75")


# ============================================================================
# State Tests
# ============================================================================


func test_not_playing_by_default() -> void:
	var effect := MockConeEffect.new()
	assert_false(effect.is_playing(), "Should not be playing by default")


func test_play_activates_effect() -> void:
	var effect := MockConeEffect.new()
	effect.play(Vector2.RIGHT)
	assert_true(effect.is_playing(), "Should be playing after play()")


func test_stop_deactivates_effect() -> void:
	var effect := MockConeEffect.new()
	effect.play(Vector2.RIGHT)
	effect.stop()
	assert_false(effect.is_playing(), "Should stop after stop()")


func test_play_sets_direction() -> void:
	var effect := MockConeEffect.new()
	effect.play(Vector2(1.0, 0.5))
	assert_eq(effect._direction, Vector2(1.0, 0.5), "Direction should be set")


func test_play_resets_progress() -> void:
	var effect := MockConeEffect.new()
	effect.play(Vector2.RIGHT)
	effect.process(0.3)
	effect.play(Vector2.LEFT)
	assert_almost_eq(effect._progress, 0.0, 0.001, "Progress should reset on new play")


# ============================================================================
# Progress Tests
# ============================================================================


func test_progress_advances() -> void:
	var effect := MockConeEffect.new()
	effect.play(Vector2.RIGHT)
	effect.process(0.1)
	assert_gt(effect._progress, 0.0, "Progress should advance")


func test_effect_stops_at_full_progress() -> void:
	var effect := MockConeEffect.new()
	effect.play(Vector2.RIGHT)
	effect.process(0.55)
	assert_false(effect.is_playing(), "Should stop at full progress")


func test_progress_calculation() -> void:
	var effect := MockConeEffect.new()
	effect.play(Vector2.RIGHT)
	effect.process(0.275)
	assert_almost_eq(effect._progress, 0.5, 0.01, "Progress should be 0.5 at half duration")


func test_process_inactive_does_nothing() -> void:
	var effect := MockConeEffect.new()
	effect.process(1.0)
	assert_false(effect.is_playing(), "Processing inactive effect should do nothing")


# ============================================================================
# Radius Tests
# ============================================================================


func test_radius_at_start() -> void:
	var effect := MockConeEffect.new()
	effect.play(Vector2.RIGHT)
	assert_almost_eq(effect.get_current_radius(), 30.0, 0.1, "Radius should start at MIN_RADIUS")


func test_radius_at_end() -> void:
	var effect := MockConeEffect.new()
	effect.play(Vector2.RIGHT)
	effect._progress = 1.0
	assert_almost_eq(effect.get_current_radius(), 400.0, 0.1, "Radius should reach MAX_RADIUS")


func test_radius_at_midpoint() -> void:
	var effect := MockConeEffect.new()
	effect.play(Vector2.RIGHT)
	effect._progress = 0.5
	var expected := 30.0 + (400.0 - 30.0) * 0.5
	assert_almost_eq(effect.get_current_radius(), expected, 0.1, "Radius should interpolate linearly")


func test_min_radius_less_than_max() -> void:
	assert_lt(MockConeEffect.MIN_RADIUS, MockConeEffect.MAX_RADIUS, "Min radius must be less than max")
