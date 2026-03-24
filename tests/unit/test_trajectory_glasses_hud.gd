extends GutTest
## Unit tests for TrajectoryGlassesHUD.
##
## Tests the charge pip HUD constants, charge tracking, and visibility logic
## using a mock class.


# ============================================================================
# Mock TrajectoryGlassesHUD for Testing
# ============================================================================


class MockTrajectoryGlassesHUD:
	## Vertical offset above the player center (negative = above).
	const OFFSET_Y: float = -40.0

	## Width of each charge pip in pixels.
	const PIP_WIDTH: float = 10.0

	## Height of each charge pip in pixels.
	const PIP_HEIGHT: float = 4.0

	## Gap between pips.
	const PIP_GAP: float = 3.0

	## Color for filled (available) charge pips.
	const PIP_FILLED_COLOR: Color = Color(0.0, 1.0, 0.5, 0.9)

	## Color for empty (used) charge pips.
	const PIP_EMPTY_COLOR: Color = Color(0.3, 0.3, 0.3, 0.5)

	## How long to show charge pips after activation.
	const ACTIVATION_SHOW_DURATION: float = 0.3

	## Current charges.
	var charges: int = 2

	## Maximum charges.
	var max_charges: int = 2

	## Whether the HUD is visible.
	var visible: bool = false

	## Auto-hide timer.
	var hide_timer: float = 0.0

	## Update charges display.
	func update_charges(current: int, maximum: int) -> void:
		charges = current
		max_charges = maximum

	## Show/hide the HUD based on effect state.
	func set_active(active: bool) -> void:
		if active:
			visible = true
			hide_timer = ACTIVATION_SHOW_DURATION
		else:
			visible = false
			hide_timer = 0.0

	## Calculate total pip width.
	func get_total_pip_width() -> float:
		return max_charges * PIP_WIDTH + (max_charges - 1) * PIP_GAP


var hud: MockTrajectoryGlassesHUD


func before_each() -> void:
	hud = MockTrajectoryGlassesHUD.new()


func after_each() -> void:
	hud = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_offset_y() -> void:
	assert_eq(hud.OFFSET_Y, -40.0,
		"OFFSET_Y should be -40 pixels (above player)")


func test_pip_width() -> void:
	assert_eq(hud.PIP_WIDTH, 10.0,
		"PIP_WIDTH should be 10 pixels")


func test_pip_height() -> void:
	assert_eq(hud.PIP_HEIGHT, 4.0,
		"PIP_HEIGHT should be 4 pixels")


func test_pip_gap() -> void:
	assert_eq(hud.PIP_GAP, 3.0,
		"PIP_GAP should be 3 pixels")


func test_pip_filled_color_is_greenish() -> void:
	assert_eq(hud.PIP_FILLED_COLOR, Color(0.0, 1.0, 0.5, 0.9),
		"PIP_FILLED_COLOR should be greenish with 0.9 alpha")
	assert_true(hud.PIP_FILLED_COLOR.g > hud.PIP_FILLED_COLOR.r,
		"Filled color should be more green than red")


func test_pip_empty_color() -> void:
	assert_eq(hud.PIP_EMPTY_COLOR, Color(0.3, 0.3, 0.3, 0.5),
		"PIP_EMPTY_COLOR should be gray with 0.5 alpha")


func test_activation_show_duration() -> void:
	assert_eq(hud.ACTIVATION_SHOW_DURATION, 0.3,
		"ACTIVATION_SHOW_DURATION should be 0.3 seconds")


# ============================================================================
# Charge Tracking Tests
# ============================================================================


func test_default_charges() -> void:
	assert_eq(hud.charges, 2, "Default charges should be 2")
	assert_eq(hud.max_charges, 2, "Default max charges should be 2")


func test_update_charges() -> void:
	hud.update_charges(1, 4)

	assert_eq(hud.charges, 1, "Charges should be updated to 1")
	assert_eq(hud.max_charges, 4, "Max charges should be updated to 4")


func test_update_charges_to_zero() -> void:
	hud.update_charges(0, 2)

	assert_eq(hud.charges, 0, "Charges should be updated to 0")


# ============================================================================
# Visibility and Timer Tests
# ============================================================================


func test_initially_hidden() -> void:
	assert_false(hud.visible,
		"HUD should be hidden initially")


func test_set_active_true_shows_hud() -> void:
	hud.set_active(true)

	assert_true(hud.visible,
		"Setting active should show the HUD")
	assert_eq(hud.hide_timer, hud.ACTIVATION_SHOW_DURATION,
		"Hide timer should be set to ACTIVATION_SHOW_DURATION")


func test_set_active_false_hides_hud() -> void:
	hud.set_active(true)
	hud.set_active(false)

	assert_false(hud.visible,
		"Setting inactive should hide the HUD")
	assert_eq(hud.hide_timer, 0.0,
		"Hide timer should be reset to 0")


# ============================================================================
# Pip Width Calculation Tests
# ============================================================================


func test_total_pip_width_with_2_charges() -> void:
	var expected := 2.0 * 10.0 + 1.0 * 3.0  # 23.0
	assert_eq(hud.get_total_pip_width(), expected,
		"Total pip width with 2 charges should be 23 pixels")


func test_total_pip_width_with_4_charges() -> void:
	hud.update_charges(4, 4)
	var expected := 4.0 * 10.0 + 3.0 * 3.0  # 49.0
	assert_eq(hud.get_total_pip_width(), expected,
		"Total pip width with 4 charges should be 49 pixels")
