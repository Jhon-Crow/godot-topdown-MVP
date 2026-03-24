extends GutTest
## Unit tests for InvisibilityHUD.
##
## Tests the charge pip HUD constants and charge tracking logic
## using a mock class.


# ============================================================================
# Mock InvisibilityHUD for Testing
# ============================================================================


class MockInvisibilityHUD:
	## Vertical offset above the player center (negative = above).
	const OFFSET_Y: float = -32.0

	## Width of each charge pip in pixels.
	const PIP_WIDTH: float = 10.0

	## Height of each charge pip in pixels.
	const PIP_HEIGHT: float = 4.0

	## Gap between pips.
	const PIP_GAP: float = 3.0

	## How long the bar stays visible after activation (seconds).
	const SHOW_DURATION: float = 0.3

	## Color for filled (available) charge pips.
	const PIP_FILLED_COLOR: Color = Color(0.4, 0.85, 1.0, 0.9)

	## Color for empty (used) charge pips.
	const PIP_EMPTY_COLOR: Color = Color(0.3, 0.3, 0.3, 0.5)

	## Current charges.
	var charges: int = 2

	## Maximum charges.
	var max_charges: int = 2

	## Whether the bar is currently visible.
	var bar_visible: bool = false

	## Show timer.
	var show_timer: float = 0.0

	## Update charges display.
	func update_charges(current: int, maximum: int) -> void:
		charges = current
		max_charges = maximum

	## Show the bar (called on activation).
	func set_active(active: bool) -> void:
		if active:
			show_timer = SHOW_DURATION
			bar_visible = true

	## Calculate total bar width.
	func get_total_width() -> float:
		return max_charges * PIP_WIDTH + (max_charges - 1) * PIP_GAP


var hud: MockInvisibilityHUD


func before_each() -> void:
	hud = MockInvisibilityHUD.new()


func after_each() -> void:
	hud = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_offset_y() -> void:
	assert_eq(hud.OFFSET_Y, -32.0,
		"OFFSET_Y should be -32 pixels (above player)")


func test_pip_width() -> void:
	assert_eq(hud.PIP_WIDTH, 10.0,
		"PIP_WIDTH should be 10 pixels")


func test_pip_height() -> void:
	assert_eq(hud.PIP_HEIGHT, 4.0,
		"PIP_HEIGHT should be 4 pixels")


func test_pip_gap() -> void:
	assert_eq(hud.PIP_GAP, 3.0,
		"PIP_GAP should be 3 pixels")


func test_show_duration() -> void:
	assert_eq(hud.SHOW_DURATION, 0.3,
		"SHOW_DURATION should be 0.3 seconds")


func test_pip_filled_color() -> void:
	assert_eq(hud.PIP_FILLED_COLOR, Color(0.4, 0.85, 1.0, 0.9),
		"PIP_FILLED_COLOR should be light blue with 0.9 alpha")


func test_pip_empty_color() -> void:
	assert_eq(hud.PIP_EMPTY_COLOR, Color(0.3, 0.3, 0.3, 0.5),
		"PIP_EMPTY_COLOR should be gray with 0.5 alpha")


# ============================================================================
# Charge Tracking Tests
# ============================================================================


func test_default_charges() -> void:
	assert_eq(hud.charges, 2, "Default charges should be 2")
	assert_eq(hud.max_charges, 2, "Default max charges should be 2")


func test_update_charges() -> void:
	hud.update_charges(1, 3)

	assert_eq(hud.charges, 1, "Charges should be updated to 1")
	assert_eq(hud.max_charges, 3, "Max charges should be updated to 3")


func test_update_charges_to_zero() -> void:
	hud.update_charges(0, 2)

	assert_eq(hud.charges, 0, "Charges should be updated to 0")


# ============================================================================
# Visibility Tests
# ============================================================================


func test_initially_hidden() -> void:
	assert_false(hud.bar_visible,
		"Bar should be hidden initially")


func test_set_active_shows_bar() -> void:
	hud.set_active(true)

	assert_true(hud.bar_visible,
		"Setting active should show the bar")
	assert_eq(hud.show_timer, hud.SHOW_DURATION,
		"Show timer should be set to SHOW_DURATION")


func test_set_active_false_does_nothing() -> void:
	hud.set_active(false)

	assert_false(hud.bar_visible,
		"Setting active false should not show bar")


# ============================================================================
# Bar Width Calculation Tests
# ============================================================================


func test_total_width_with_2_charges() -> void:
	var expected := 2.0 * 10.0 + 1.0 * 3.0  # 23.0
	assert_eq(hud.get_total_width(), expected,
		"Total width with 2 charges should be 23 pixels")


func test_total_width_with_3_charges() -> void:
	hud.update_charges(3, 3)
	var expected := 3.0 * 10.0 + 2.0 * 3.0  # 36.0
	assert_eq(hud.get_total_width(), expected,
		"Total width with 3 charges should be 36 pixels")
