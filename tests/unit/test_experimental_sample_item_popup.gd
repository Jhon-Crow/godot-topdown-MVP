extends GutTest
## Unit tests for ExperimentalSampleItemPopup.
##
## Tests the floating item icon popup that shows above the player
## when Experimental Sample fires an effect. Covers constants,
## timer logic, fade-out calculations, and arc rendering math.


# ============================================================================
# Mock Popup for Logic Tests
# ============================================================================


class MockPopup:
	## Replicates the core logic of ExperimentalSampleItemPopup without scene tree.

	const DEFAULT_DURATION: float = 1.2
	const FADE_OUT_DURATION: float = 0.4
	const OFFSET_Y: float = -60.0
	const OFFSET_X: float = 16.0
	const ICON_SIZE: float = 36.0
	const BG_RADIUS: float = 22.0
	const ARC_RADIUS: float = 25.0
	const ARC_WIDTH: float = 4.0
	const ARC_SEGMENTS: int = 48
	const ARC_COLOR_FULL: Color = Color(0.3, 1.0, 0.4, 0.9)
	const ARC_COLOR_LOW: Color = Color(1.0, 0.2, 0.2, 0.9)
	const ARC_LOW_THRESHOLD: float = 0.3
	const BG_COLOR: Color = Color(0.05, 0.05, 0.05, 0.72)

	var _total_duration: float = DEFAULT_DURATION
	var _timer: float = 0.0
	var _active: bool = false
	var _texture_path: String = ""
	var modulate_a: float = 1.0

	func show_icon(icon_path: String, duration: float = DEFAULT_DURATION) -> void:
		if icon_path.is_empty():
			return
		_texture_path = icon_path
		_total_duration = maxf(duration, 0.0)
		_timer = _total_duration
		_active = true
		modulate_a = 1.0

	func process(delta: float) -> void:
		if not _active:
			return
		_timer -= delta
		if _timer <= 0.0:
			_active = false
			return
		# Fade out in last FADE_OUT_DURATION seconds
		if _timer < FADE_OUT_DURATION:
			modulate_a = clampf(_timer / FADE_OUT_DURATION, 0.0, 1.0)
		else:
			modulate_a = 1.0

	func is_active() -> bool:
		return _active

	func get_fraction() -> float:
		if _total_duration <= 0.0:
			return 0.0
		return clampf(_timer / _total_duration, 0.0, 1.0)


# ============================================================================
# Constants Tests
# ============================================================================


func test_default_duration_value() -> void:
	assert_eq(MockPopup.DEFAULT_DURATION, 1.2, "Default duration should be 1.2 seconds")


func test_fade_out_duration_value() -> void:
	assert_eq(MockPopup.FADE_OUT_DURATION, 0.4, "Fade out should be 0.4 seconds")


func test_offset_y_is_negative() -> void:
	assert_lt(MockPopup.OFFSET_Y, 0.0, "Offset Y should be negative (above player)")


func test_offset_x_is_positive() -> void:
	assert_gt(MockPopup.OFFSET_X, 0.0, "Offset X should be positive (right of center)")


func test_icon_size_value() -> void:
	assert_eq(MockPopup.ICON_SIZE, 36.0, "Icon size should be 36 pixels")


func test_bg_radius_smaller_than_arc() -> void:
	assert_lt(MockPopup.BG_RADIUS, MockPopup.ARC_RADIUS, "Background circle should be smaller than arc")


func test_arc_segments_sufficient() -> void:
	assert_gte(MockPopup.ARC_SEGMENTS, 16, "Arc segments should be at least 16 for smooth curve")


func test_arc_low_threshold_between_zero_and_one() -> void:
	assert_gt(MockPopup.ARC_LOW_THRESHOLD, 0.0, "Low threshold should be positive")
	assert_lt(MockPopup.ARC_LOW_THRESHOLD, 1.0, "Low threshold should be less than 1")


# ============================================================================
# Show Icon Tests
# ============================================================================


func test_show_icon_activates_popup() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg")
	assert_true(popup.is_active(), "Popup should be active after show_icon")


func test_show_icon_empty_path_does_nothing() -> void:
	var popup := MockPopup.new()
	popup.show_icon("")
	assert_false(popup.is_active(), "Popup should not activate with empty path")


func test_show_icon_custom_duration() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 5.0)
	assert_eq(popup._total_duration, 5.0, "Duration should be set to custom value")


func test_show_icon_zero_duration() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 0.0)
	assert_eq(popup._total_duration, 0.0, "Duration of 0 should be accepted")


func test_show_icon_negative_duration_clamped() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", -5.0)
	assert_eq(popup._total_duration, 0.0, "Negative duration should be clamped to 0")


func test_show_icon_resets_modulate() -> void:
	var popup := MockPopup.new()
	popup.modulate_a = 0.5
	popup.show_icon("res://icon.svg")
	assert_eq(popup.modulate_a, 1.0, "Modulate alpha should reset to 1.0")


func test_show_icon_sets_timer_to_duration() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 3.0)
	assert_eq(popup._timer, 3.0, "Timer should equal total duration")


# ============================================================================
# Process Timer Tests
# ============================================================================


func test_process_decrements_timer() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 2.0)
	popup.process(0.5)
	assert_almost_eq(popup._timer, 1.5, 0.001, "Timer should decrease by delta")


func test_process_deactivates_at_zero() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 1.0)
	popup.process(1.0)
	assert_false(popup.is_active(), "Popup should deactivate when timer reaches 0")


func test_process_deactivates_past_zero() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 0.5)
	popup.process(1.0)
	assert_false(popup.is_active(), "Popup should deactivate when timer goes past 0")


func test_process_inactive_does_nothing() -> void:
	var popup := MockPopup.new()
	popup.process(1.0)
	assert_false(popup.is_active(), "Processing inactive popup should do nothing")


# ============================================================================
# Fade Out Tests
# ============================================================================


func test_no_fade_before_threshold() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 2.0)
	popup.process(0.5)  # timer = 1.5, well above FADE_OUT_DURATION
	assert_eq(popup.modulate_a, 1.0, "Alpha should be 1.0 before fade threshold")


func test_fade_starts_at_fade_out_duration() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 2.0)
	popup.process(1.6)  # timer = 0.4 = FADE_OUT_DURATION
	assert_eq(popup.modulate_a, 1.0, "Alpha should be 1.0 at fade threshold boundary")


func test_fade_progresses_below_threshold() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 2.0)
	popup.process(1.8)  # timer = 0.2, which is < FADE_OUT_DURATION (0.4)
	assert_almost_eq(popup.modulate_a, 0.5, 0.01, "Alpha should be 0.5 at halfway through fade")


func test_fade_near_zero() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 2.0)
	popup.process(1.96)  # timer = 0.04
	assert_almost_eq(popup.modulate_a, 0.1, 0.01, "Alpha should be near 0 at end of fade")


# ============================================================================
# Fraction (Arc Progress) Tests
# ============================================================================


func test_fraction_full_at_start() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 2.0)
	assert_almost_eq(popup.get_fraction(), 1.0, 0.001, "Fraction should be 1.0 at start")


func test_fraction_half_at_midpoint() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 2.0)
	popup.process(1.0)
	assert_almost_eq(popup.get_fraction(), 0.5, 0.001, "Fraction should be 0.5 at midpoint")


func test_fraction_zero_at_end() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 2.0)
	popup.process(2.0)
	# After deactivation, timer is <= 0
	assert_almost_eq(popup.get_fraction(), 0.0, 0.001, "Fraction should be 0.0 at end")


func test_fraction_with_zero_duration() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 0.0)
	assert_eq(popup.get_fraction(), 0.0, "Fraction should be 0.0 with zero duration")


# ============================================================================
# Override Behavior Tests
# ============================================================================


func test_show_icon_overrides_active_popup() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon1.svg", 5.0)
	popup.process(2.0)  # timer = 3.0
	popup.show_icon("res://icon2.svg", 4.0)
	assert_eq(popup._total_duration, 4.0, "New show_icon should override duration")
	assert_eq(popup._timer, 4.0, "New show_icon should reset timer")
	assert_true(popup.is_active(), "Popup should remain active")


func test_show_icon_resets_alpha_on_override() -> void:
	var popup := MockPopup.new()
	popup.show_icon("res://icon.svg", 1.0)
	popup.process(0.8)  # trigger fade
	assert_lt(popup.modulate_a, 1.0, "Alpha should have faded")
	popup.show_icon("res://icon2.svg", 2.0)
	assert_eq(popup.modulate_a, 1.0, "Alpha should reset on override")
