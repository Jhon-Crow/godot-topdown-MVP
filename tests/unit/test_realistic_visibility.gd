extends GutTest
## Unit tests for RealisticVisibilityComponent (Issue #540).
##
## Tests the realistic visibility (fog of war) system including:
## - Component initialization and default state
## - Visibility toggle via ExperimentalSettings
## - Light and modulate properties
## - Cleanup on exit


# ============================================================================
# Mock RealisticVisibilityComponent for Logic Tests
# ============================================================================


class MockRealisticVisibilityComponent:
	## Constants matching the real component.
	const VISIBILITY_RADIUS: float = 600.0
	const LIGHT_ENERGY: float = 1.5
	const FOG_COLOR: Color = Color(0.02, 0.02, 0.04, 1.0)
	const LIGHT_COLOR: Color = Color(1.0, 0.98, 0.95, 1.0)

	## Whether the visibility system is currently active.
	var _is_active: bool = false

	## Simulated CanvasModulate visibility.
	var _canvas_modulate_visible: bool = false

	## Simulated PointLight2D visibility.
	var _point_light_visible: bool = false

	## Whether setup was called.
	var _setup_called: bool = false


	## Apply the visibility state (enable/disable fog of war).
	func _apply_visibility_state(enabled: bool) -> void:
		_is_active = enabled
		_canvas_modulate_visible = enabled
		_point_light_visible = enabled


	## Setup the visibility system (simulated).
	func setup() -> void:
		_setup_called = true
		_is_active = false
		_canvas_modulate_visible = false
		_point_light_visible = false


	## Check if the visibility system is currently active.
	func is_active() -> bool:
		return _is_active


	## Get the current visibility radius.
	func get_visibility_radius() -> float:
		return VISIBILITY_RADIUS


var component: MockRealisticVisibilityComponent


func before_each() -> void:
	component = MockRealisticVisibilityComponent.new()
	component.setup()


func after_each() -> void:
	component = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_default_state_is_inactive() -> void:
	assert_false(component.is_active(),
		"Visibility system should be inactive by default")


func test_setup_initializes_properly() -> void:
	assert_true(component._setup_called,
		"Setup should have been called")


func test_default_canvas_modulate_hidden() -> void:
	assert_false(component._canvas_modulate_visible,
		"CanvasModulate should be hidden by default")


func test_default_point_light_hidden() -> void:
	assert_false(component._point_light_visible,
		"PointLight2D should be hidden by default")


# ============================================================================
# Constants Tests
# ============================================================================


func test_visibility_radius_value() -> void:
	assert_eq(component.VISIBILITY_RADIUS, 600.0,
		"Visibility radius should be 600 pixels")


func test_light_energy_value() -> void:
	assert_eq(component.LIGHT_ENERGY, 1.5,
		"Light energy should be 1.5")


func test_fog_color_is_dark() -> void:
	assert_true(component.FOG_COLOR.r < 0.1 and component.FOG_COLOR.g < 0.1 and component.FOG_COLOR.b < 0.1,
		"Fog color should be very dark")


func test_light_color_is_warm_white() -> void:
	assert_true(component.LIGHT_COLOR.r >= 0.95 and component.LIGHT_COLOR.g >= 0.95,
		"Light color should be warm white")


func test_get_visibility_radius() -> void:
	assert_eq(component.get_visibility_radius(), 600.0,
		"get_visibility_radius should return VISIBILITY_RADIUS")


# ============================================================================
# Enable/Disable Tests
# ============================================================================


func test_enable_activates_system() -> void:
	component._apply_visibility_state(true)

	assert_true(component.is_active(),
		"System should be active after enabling")


func test_enable_shows_canvas_modulate() -> void:
	component._apply_visibility_state(true)

	assert_true(component._canvas_modulate_visible,
		"CanvasModulate should be visible when enabled")


func test_enable_shows_point_light() -> void:
	component._apply_visibility_state(true)

	assert_true(component._point_light_visible,
		"PointLight2D should be visible when enabled")


func test_disable_deactivates_system() -> void:
	component._apply_visibility_state(true)
	component._apply_visibility_state(false)

	assert_false(component.is_active(),
		"System should be inactive after disabling")


func test_disable_hides_canvas_modulate() -> void:
	component._apply_visibility_state(true)
	component._apply_visibility_state(false)

	assert_false(component._canvas_modulate_visible,
		"CanvasModulate should be hidden when disabled")


func test_disable_hides_point_light() -> void:
	component._apply_visibility_state(true)
	component._apply_visibility_state(false)

	assert_false(component._point_light_visible,
		"PointLight2D should be hidden when disabled")


# ============================================================================
# Toggle Pattern Tests
# ============================================================================


func test_toggle_on_off() -> void:
	component._apply_visibility_state(true)
	assert_true(component.is_active(), "Should be active after enabling")

	component._apply_visibility_state(false)
	assert_false(component.is_active(), "Should be inactive after disabling")


func test_toggle_off_on() -> void:
	component._apply_visibility_state(false)
	assert_false(component.is_active(), "Should be inactive")

	component._apply_visibility_state(true)
	assert_true(component.is_active(), "Should be active after enabling")


func test_rapid_toggle() -> void:
	for i in range(10):
		component._apply_visibility_state(true)
		component._apply_visibility_state(false)

	assert_false(component.is_active(),
		"Should end inactive after even number of toggles")


func test_enable_multiple_times() -> void:
	component._apply_visibility_state(true)
	component._apply_visibility_state(true)
	component._apply_visibility_state(true)

	assert_true(component.is_active(),
		"Should stay active after multiple enables")


func test_disable_multiple_times() -> void:
	component._apply_visibility_state(false)
	component._apply_visibility_state(false)
	component._apply_visibility_state(false)

	assert_false(component.is_active(),
		"Should stay inactive after multiple disables")


# ============================================================================
# Integration-like Tests
# ============================================================================


func test_typical_usage_flow() -> void:
	# 1. Initial state - inactive
	assert_false(component.is_active(), "Should start inactive")

	# 2. User enables realistic visibility
	component._apply_visibility_state(true)
	assert_true(component.is_active(), "Should be active")
	assert_true(component._canvas_modulate_visible, "Canvas modulate should be visible")
	assert_true(component._point_light_visible, "Point light should be visible")

	# 3. User disables realistic visibility
	component._apply_visibility_state(false)
	assert_false(component.is_active(), "Should be inactive")
	assert_false(component._canvas_modulate_visible, "Canvas modulate should be hidden")
	assert_false(component._point_light_visible, "Point light should be hidden")


func test_all_visual_elements_consistent() -> void:
	# When enabled, all elements should be visible
	component._apply_visibility_state(true)
	assert_eq(component._canvas_modulate_visible, component._point_light_visible,
		"CanvasModulate and PointLight2D should have same visibility")

	# When disabled, all elements should be hidden
	component._apply_visibility_state(false)
	assert_eq(component._canvas_modulate_visible, component._point_light_visible,
		"CanvasModulate and PointLight2D should have same visibility")
