extends GutTest
## Unit tests for armory progress bar shine animation behavior (Issue #1621).
##
## Verifies that:
## 1. When the progress bar reaches full (target_progress >= 1.0), the progress
##    bar overlay layer is hidden so only the availability (condition_met) shine
##    on the slot itself remains visible — avoiding duplicate animations.
## 2. The progress bar's shine shader colors are dimmer than the condition-met
##    slot shine, so the two are visually distinct when progress is partial.


# ============================================================================
# Mock: simulates the shine overlay visibility logic from armory_menu.gd
# ============================================================================


class MockProgressBarShineLogic:
	## Mirrors the logic added in _animate_unlock_progress_bar (Issue #1621):
	## after the fill animation completes, if target_progress >= 1.0 the
	## overlay_layer that contains the progress bar (and its shine) is hidden.

	## Whether the overlay layer is currently visible.
	var overlay_layer_visible: bool = true

	## Whether the condition_met slot shine is active.
	var condition_met_shine_active: bool = false

	## Simulate completing the fill animation for a given target_progress.
	## Mirrors: if target_progress >= 1.0: overlay_layer.hide()
	func finish_fill_animation(target_progress: float, condition_met: bool) -> void:
		condition_met_shine_active = condition_met
		if target_progress >= 1.0:
			overlay_layer_visible = false

	## Returns true if both progress bar shine AND condition_met shine are visible
	## at the same time (the duplication the issue describes).
	func has_duplicate_shine() -> bool:
		return overlay_layer_visible and condition_met_shine_active


# ============================================================================
# Mock: simulates progress bar shader color assignment (Issue #1621)
# ============================================================================


class MockProgressBarShaderColors:
	## Shader colors used for the condition_met slot shine (full brightness).
	const CONDITION_MET_SWEEP_COLOR := Color(1.0, 0.85, 0.2, 1.0)
	const CONDITION_MET_BURST_COLOR := Color(1.0, 0.75, 0.1, 1.0)

	## Shader colors used for the progress bar shine (dimmed, Issue #1621).
	const PROGRESS_BAR_SWEEP_COLOR := Color(0.5, 0.42, 0.1, 1.0)
	const PROGRESS_BAR_BURST_COLOR := Color(0.5, 0.37, 0.05, 1.0)

	## Returns the average RGB luminance of a color (ignores alpha).
	func luminance(color: Color) -> float:
		return (color.r + color.g + color.b) / 3.0


# ============================================================================
# Test Setup
# ============================================================================


var _logic: MockProgressBarShineLogic
var _colors: MockProgressBarShaderColors


func before_each() -> void:
	_logic = MockProgressBarShineLogic.new()
	_colors = MockProgressBarShaderColors.new()


# ============================================================================
# Tests: progress bar overlay visibility at completion (Issue #1621 fix 1)
# ============================================================================


func test_partial_progress_keeps_overlay_visible() -> void:
	# At 50% progress the bar is still filling — keep overlay visible.
	_logic.finish_fill_animation(0.5, false)
	assert_true(_logic.overlay_layer_visible, "Overlay should remain visible for partial progress")


func test_zero_progress_keeps_overlay_visible() -> void:
	# At 0% progress the bar is present but empty — keep overlay visible.
	_logic.finish_fill_animation(0.0, false)
	assert_true(_logic.overlay_layer_visible, "Overlay should remain visible at zero progress")


func test_full_progress_hides_overlay() -> void:
	# At 100% progress the progress bar shine should disappear.
	_logic.finish_fill_animation(1.0, true)
	assert_false(_logic.overlay_layer_visible, "Overlay should be hidden when progress is full (1.0)")


func test_full_progress_no_duplicate_shine() -> void:
	# At 100% progress with condition_met shine active, there should be no duplication.
	_logic.finish_fill_animation(1.0, true)
	assert_false(_logic.has_duplicate_shine(),
		"Progress bar shine and condition_met shine must not both be visible at full progress")


func test_partial_progress_condition_not_met_no_duplicate() -> void:
	# At partial progress with no condition_met shine, there is no duplication.
	_logic.finish_fill_animation(0.75, false)
	assert_false(_logic.has_duplicate_shine(),
		"No duplication when condition_met shine is not active")


func test_partial_progress_condition_met_causes_no_duplicate_since_bar_visible_not_condition_met() -> void:
	# At partial progress, the progress bar IS visible. If condition is not yet met
	# (shine not active), there is no duplication.
	_logic.finish_fill_animation(0.75, false)
	assert_false(_logic.has_duplicate_shine(),
		"No duplication at partial progress without condition_met shine")


func test_near_full_progress_does_not_hide_overlay() -> void:
	# At 99.9% the bar should still be visible — only >= 1.0 triggers hide.
	_logic.finish_fill_animation(0.999, false)
	assert_true(_logic.overlay_layer_visible, "Overlay should still be visible at 99.9% progress")


func test_over_max_progress_hides_overlay() -> void:
	# Clamped-but-overflowed progress (e.g. 1.5) should also hide the overlay.
	_logic.finish_fill_animation(1.5, true)
	assert_false(_logic.overlay_layer_visible, "Overlay should be hidden for progress > 1.0")


# ============================================================================
# Tests: progress bar shine is dimmer than condition_met shine (Issue #1621 fix 2)
# ============================================================================


func test_progress_bar_sweep_color_is_dimmer_than_condition_met_sweep() -> void:
	var progress_lum: float = _colors.luminance(_colors.PROGRESS_BAR_SWEEP_COLOR)
	var condition_lum: float = _colors.luminance(_colors.CONDITION_MET_SWEEP_COLOR)
	assert_true(progress_lum < condition_lum,
		"Progress bar sweep color should be dimmer (lower luminance) than condition_met sweep color")


func test_progress_bar_burst_color_is_dimmer_than_condition_met_burst() -> void:
	var progress_lum: float = _colors.luminance(_colors.PROGRESS_BAR_BURST_COLOR)
	var condition_lum: float = _colors.luminance(_colors.CONDITION_MET_BURST_COLOR)
	assert_true(progress_lum < condition_lum,
		"Progress bar burst color should be dimmer (lower luminance) than condition_met burst color")


func test_progress_bar_sweep_color_is_noticeably_dimmer() -> void:
	# Progress bar shine should be meaningfully dimmer, not just marginally.
	# We expect at least 30% less luminance.
	var progress_lum: float = _colors.luminance(_colors.PROGRESS_BAR_SWEEP_COLOR)
	var condition_lum: float = _colors.luminance(_colors.CONDITION_MET_SWEEP_COLOR)
	var ratio: float = progress_lum / condition_lum
	assert_true(ratio <= 0.7,
		"Progress bar sweep should be at most 70%% as bright as condition_met sweep (ratio: %.2f)" % ratio)


func test_progress_bar_burst_color_is_noticeably_dimmer() -> void:
	var progress_lum: float = _colors.luminance(_colors.PROGRESS_BAR_BURST_COLOR)
	var condition_lum: float = _colors.luminance(_colors.CONDITION_MET_BURST_COLOR)
	var ratio: float = progress_lum / condition_lum
	assert_true(ratio <= 0.7,
		"Progress bar burst should be at most 70%% as bright as condition_met burst (ratio: %.2f)" % ratio)
