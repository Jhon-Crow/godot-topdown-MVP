extends GutTest
## Unit tests for JammerHUD.
##
## Tests the prohibition sign HUD constants and visibility logic
## using a mock class.


# ============================================================================
# Mock JammerHUD for Testing
# ============================================================================


class MockJammerHUD:
	## Vertical offset above the player center (negative = above).
	const OFFSET_Y: float = -56.0

	## Radius of the prohibition circle in pixels.
	const CIRCLE_RADIUS: float = 10.0

	## Color of the prohibition sign (red, slightly transparent).
	const SIGN_COLOR: Color = Color(0.9, 0.1, 0.05, 0.95)

	## Line width for both the circle and diagonal bar.
	const LINE_WIDTH: float = 3.0

	## Whether the icon is visible.
	var visible: bool = false

	## Show or hide the icon.
	func set_jammed_visible(show: bool) -> void:
		visible = show


var hud: MockJammerHUD


func before_each() -> void:
	hud = MockJammerHUD.new()


func after_each() -> void:
	hud = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_offset_y() -> void:
	assert_eq(hud.OFFSET_Y, -56.0,
		"OFFSET_Y should be -56 pixels (above player)")


func test_circle_radius() -> void:
	assert_eq(hud.CIRCLE_RADIUS, 10.0,
		"CIRCLE_RADIUS should be 10 pixels")


func test_sign_color() -> void:
	assert_eq(hud.SIGN_COLOR, Color(0.9, 0.1, 0.05, 0.95),
		"SIGN_COLOR should be red with 0.95 alpha")


func test_sign_color_is_red() -> void:
	assert_true(hud.SIGN_COLOR.r > 0.8,
		"Sign color should have high red channel")
	assert_true(hud.SIGN_COLOR.g < 0.2,
		"Sign color should have low green channel")
	assert_true(hud.SIGN_COLOR.b < 0.2,
		"Sign color should have low blue channel")


func test_line_width() -> void:
	assert_eq(hud.LINE_WIDTH, 3.0,
		"LINE_WIDTH should be 3 pixels")


# ============================================================================
# Visibility Tests
# ============================================================================


func test_initially_hidden() -> void:
	assert_false(hud.visible,
		"Jammer icon should be hidden initially")


func test_set_jammed_visible_true() -> void:
	hud.set_jammed_visible(true)

	assert_true(hud.visible,
		"Setting jammed visible should show the icon")


func test_set_jammed_visible_false() -> void:
	hud.set_jammed_visible(true)
	hud.set_jammed_visible(false)

	assert_false(hud.visible,
		"Setting jammed hidden should hide the icon")


func test_toggle_visibility() -> void:
	hud.set_jammed_visible(true)
	assert_true(hud.visible, "Should be visible after show")

	hud.set_jammed_visible(false)
	assert_false(hud.visible, "Should be hidden after hide")

	hud.set_jammed_visible(true)
	assert_true(hud.visible, "Should be visible again after re-show")
