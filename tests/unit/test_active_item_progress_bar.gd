extends GutTest
## Unit tests for ActiveItemProgressBar component (Issue #700).
##
## Tests the progress bar display modes, value management,
## color selection, and visibility logic.


# ============================================================================
# Mock Progress Bar for Logic Tests (without scene tree)
# ============================================================================


class MockProgressBar:
	## Display mode for the progress bar.
	enum DisplayMode {
		SEGMENTED,
		CONTINUOUS
	}

	## Current display mode.
	var display_mode: int = DisplayMode.SEGMENTED

	## Current value (charges remaining or time remaining).
	var current_value: float = 0.0

	## Maximum value (max charges or max time).
	var max_value: float = 1.0

	## Whether the progress bar is currently visible.
	var is_visible: bool = false

	## Tracking for redraw calls.
	var redraw_count: int = 0

	## Show the progress bar with the given parameters.
	func show_bar(mode: int, current: float, maximum: float) -> void:
		display_mode = mode
		current_value = current
		max_value = maxf(maximum, 0.001)
		is_visible = true
		redraw_count += 1

	## Hide the progress bar.
	func hide_bar() -> void:
		is_visible = false
		redraw_count += 1

	## Update the current value without changing mode or max.
	func update_value(current: float) -> void:
		current_value = current
		if is_visible:
			redraw_count += 1

	## Get the fill color based on the current percentage.
	func get_fill_color() -> String:
		if max_value <= 0.0:
			return "red"
		var percent: float = current_value / max_value
		if percent > 0.5:
			return "green"
		elif percent > 0.25:
			return "yellow"
		else:
			return "red"

	## Get the fill percentage (0.0 to 1.0).
	func get_fill_percent() -> float:
		if max_value <= 0.0:
			return 0.0
		return clampf(current_value / max_value, 0.0, 1.0)


var bar: MockProgressBar


func before_each() -> void:
	bar = MockProgressBar.new()


func after_each() -> void:
	bar = null


# ============================================================================
# Default State Tests
# ============================================================================


func test_default_not_visible() -> void:
	assert_false(bar.is_visible,
		"Progress bar should not be visible by default")


func test_default_display_mode_is_segmented() -> void:
	assert_eq(bar.display_mode, MockProgressBar.DisplayMode.SEGMENTED,
		"Default display mode should be SEGMENTED")


func test_default_current_value_is_zero() -> void:
	assert_eq(bar.current_value, 0.0,
		"Default current value should be 0.0")


func test_default_max_value_is_one() -> void:
	assert_eq(bar.max_value, 1.0,
		"Default max value should be 1.0")


# ============================================================================
# Segmented Mode Tests (Charge-Based Items)
# ============================================================================


func test_show_segmented_bar_with_full_charges() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 6.0, 6.0)
	assert_true(bar.is_visible, "Bar should be visible after show_bar")
	assert_eq(bar.display_mode, MockProgressBar.DisplayMode.SEGMENTED,
		"Display mode should be SEGMENTED")
	assert_eq(bar.current_value, 6.0, "Current value should be 6.0")
	assert_eq(bar.max_value, 6.0, "Max value should be 6.0")


func test_show_segmented_bar_with_partial_charges() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 3.0, 6.0)
	assert_eq(bar.current_value, 3.0, "Current value should be 3.0")
	assert_eq(bar.max_value, 6.0, "Max value should be 6.0")


func test_show_segmented_bar_with_zero_charges() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 0.0, 6.0)
	assert_eq(bar.current_value, 0.0, "Current value should be 0.0")
	assert_true(bar.is_visible, "Bar should remain visible with zero charges")


func test_segmented_bar_fill_percent_full() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 6.0, 6.0)
	assert_almost_eq(bar.get_fill_percent(), 1.0, 0.001,
		"Fill percent should be 1.0 at full charges")


func test_segmented_bar_fill_percent_half() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 3.0, 6.0)
	assert_almost_eq(bar.get_fill_percent(), 0.5, 0.001,
		"Fill percent should be 0.5 at half charges")


func test_segmented_bar_fill_percent_empty() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 0.0, 6.0)
	assert_almost_eq(bar.get_fill_percent(), 0.0, 0.001,
		"Fill percent should be 0.0 at zero charges")


# ============================================================================
# Continuous Mode Tests (Time-Based Items)
# ============================================================================


func test_show_continuous_bar_with_full_time() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.CONTINUOUS, 10.0, 10.0)
	assert_true(bar.is_visible, "Bar should be visible")
	assert_eq(bar.display_mode, MockProgressBar.DisplayMode.CONTINUOUS,
		"Display mode should be CONTINUOUS")
	assert_eq(bar.current_value, 10.0, "Current value should be 10.0")


func test_show_continuous_bar_with_partial_time() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.CONTINUOUS, 5.0, 10.0)
	assert_almost_eq(bar.get_fill_percent(), 0.5, 0.001,
		"Fill percent should be 0.5 at half time")


func test_continuous_bar_decreasing_time() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.CONTINUOUS, 10.0, 10.0)
	bar.update_value(7.0)
	assert_eq(bar.current_value, 7.0, "Current value should update to 7.0")
	bar.update_value(3.0)
	assert_eq(bar.current_value, 3.0, "Current value should update to 3.0")
	bar.update_value(0.0)
	assert_eq(bar.current_value, 0.0, "Current value should update to 0.0")


# ============================================================================
# Color Selection Tests
# ============================================================================


func test_color_green_when_above_50_percent() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 4.0, 6.0)
	assert_eq(bar.get_fill_color(), "green",
		"Color should be green when above 50%% (4/6 = 67%%)")


func test_color_green_at_exactly_51_percent() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.CONTINUOUS, 5.1, 10.0)
	assert_eq(bar.get_fill_color(), "green",
		"Color should be green at 51%%")


func test_color_yellow_when_between_25_and_50_percent() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 2.0, 6.0)
	assert_eq(bar.get_fill_color(), "yellow",
		"Color should be yellow when between 25%% and 50%% (2/6 = 33%%)")


func test_color_red_when_below_25_percent() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 1.0, 6.0)
	assert_eq(bar.get_fill_color(), "red",
		"Color should be red when below 25%% (1/6 = 17%%)")


func test_color_red_when_zero() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 0.0, 6.0)
	assert_eq(bar.get_fill_color(), "red",
		"Color should be red at zero charges")


func test_color_green_at_full() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 6.0, 6.0)
	assert_eq(bar.get_fill_color(), "green",
		"Color should be green at full charges")


# ============================================================================
# Visibility Tests
# ============================================================================


func test_hide_bar() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 6.0, 6.0)
	assert_true(bar.is_visible, "Bar should be visible")
	bar.hide_bar()
	assert_false(bar.is_visible, "Bar should be hidden after hide_bar()")


func test_show_after_hide() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 6.0, 6.0)
	bar.hide_bar()
	bar.show_bar(MockProgressBar.DisplayMode.CONTINUOUS, 5.0, 10.0)
	assert_true(bar.is_visible, "Bar should be visible again after show")
	assert_eq(bar.display_mode, MockProgressBar.DisplayMode.CONTINUOUS,
		"Display mode should change to CONTINUOUS")


func test_update_value_triggers_redraw_when_visible() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 6.0, 6.0)
	var initial_redraws := bar.redraw_count
	bar.update_value(5.0)
	assert_eq(bar.redraw_count, initial_redraws + 1,
		"Redraw should be triggered when updating visible bar")


func test_update_value_no_redraw_when_hidden() -> void:
	bar.update_value(5.0)
	assert_eq(bar.redraw_count, 0,
		"Redraw should not be triggered when bar is hidden")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_max_value_cannot_be_zero() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 0.0, 0.0)
	assert_true(bar.max_value > 0.0,
		"Max value should be clamped above zero to prevent division by zero")


func test_negative_current_value_clamps_to_zero_percent() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.CONTINUOUS, -1.0, 10.0)
	assert_almost_eq(bar.get_fill_percent(), 0.0, 0.001,
		"Negative current value should clamp to 0%% fill")


func test_current_above_max_clamps_to_100_percent() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.CONTINUOUS, 15.0, 10.0)
	assert_almost_eq(bar.get_fill_percent(), 1.0, 0.001,
		"Current above max should clamp to 100%% fill")


func test_single_charge_item() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 1.0, 1.0)
	assert_almost_eq(bar.get_fill_percent(), 1.0, 0.001,
		"Single charge at max should be 100%%")
	bar.update_value(0.0)
	assert_almost_eq(bar.get_fill_percent(), 0.0, 0.001,
		"Single charge used should be 0%%")


func test_mode_switch_segmented_to_continuous() -> void:
	bar.show_bar(MockProgressBar.DisplayMode.SEGMENTED, 3.0, 6.0)
	bar.show_bar(MockProgressBar.DisplayMode.CONTINUOUS, 5.0, 10.0)
	assert_eq(bar.display_mode, MockProgressBar.DisplayMode.CONTINUOUS,
		"Should switch to continuous mode")
	assert_eq(bar.current_value, 5.0, "Value should update to new value")
	assert_eq(bar.max_value, 10.0, "Max should update to new max")


# ============================================================================
# Teleport Bracers Integration Tests (Simulated)
# ============================================================================


class MockTeleportBracersWithBar:
	## Simulates teleport bracers charge tracking with progress bar updates.
	const MAX_CHARGES: int = 6
	var charges: int = MAX_CHARGES
	var bar_visible: bool = true
	var bar_current: float = 6.0
	var bar_max: float = 6.0
	var bar_mode: int = 0  # 0 = SEGMENTED

	func use_charge() -> bool:
		if charges <= 0:
			return false
		charges -= 1
		bar_current = float(charges)
		return true

	func get_bar_color() -> String:
		var percent: float = bar_current / bar_max
		if percent > 0.5:
			return "green"
		elif percent > 0.25:
			return "yellow"
		else:
			return "red"


func test_teleport_bracers_bar_starts_full() -> void:
	var bracers := MockTeleportBracersWithBar.new()
	assert_eq(bracers.bar_current, 6.0, "Bar should start at 6 charges")
	assert_eq(bracers.bar_max, 6.0, "Bar max should be 6")
	assert_true(bracers.bar_visible, "Bar should be visible")


func test_teleport_bracers_bar_decrements_on_use() -> void:
	var bracers := MockTeleportBracersWithBar.new()
	bracers.use_charge()
	assert_eq(bracers.bar_current, 5.0, "Bar should show 5 charges after use")
	bracers.use_charge()
	assert_eq(bracers.bar_current, 4.0, "Bar should show 4 charges after 2 uses")


func test_teleport_bracers_bar_color_changes() -> void:
	var bracers := MockTeleportBracersWithBar.new()
	# 6/6 = 100% -> green
	assert_eq(bracers.get_bar_color(), "green", "6/6 should be green")

	# Use 3 charges -> 3/6 = 50% -> yellow (boundary: > 0.25 and <= 0.5)
	for i in range(3):
		bracers.use_charge()
	assert_eq(bracers.get_bar_color(), "yellow", "3/6 should be yellow")

	# Use 2 more -> 1/6 = 17% -> red
	bracers.use_charge()
	bracers.use_charge()
	assert_eq(bracers.get_bar_color(), "red", "1/6 should be red")


func test_teleport_bracers_bar_all_charges_used() -> void:
	var bracers := MockTeleportBracersWithBar.new()
	for i in range(6):
		bracers.use_charge()
	assert_eq(bracers.bar_current, 0.0, "Bar should show 0 after all charges used")
	assert_eq(bracers.get_bar_color(), "red", "0/6 should be red")


func test_teleport_bracers_cannot_go_negative() -> void:
	var bracers := MockTeleportBracersWithBar.new()
	for i in range(6):
		bracers.use_charge()
	var result := bracers.use_charge()
	assert_false(result, "Should not use charge when empty")
	assert_eq(bracers.bar_current, 0.0, "Bar should remain at 0")
