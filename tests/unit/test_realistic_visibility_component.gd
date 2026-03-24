extends GutTest
## Unit tests for RealisticVisibilityComponent.
##
## Tests VISIBILITY_RADIUS, LIGHT_ENERGY, fog color values,
## and active state tracking for the fog of war system.


# ============================================================================
# Mock RealisticVisibilityComponent for Logic Tests
# ============================================================================


class MockRealisticVisibilityComponent:
	const VISIBILITY_RADIUS: float = 600.0
	const LIGHT_ENERGY: float = 1.5
	const FOG_COLOR: Color = Color(0.02, 0.02, 0.04, 1.0)
	const LIGHT_COLOR: Color = Color(1.0, 0.98, 0.95, 1.0)

	var _is_active: bool = false
	var _light_color: Color = LIGHT_COLOR
	var _light_energy: float = LIGHT_ENERGY

	func is_active() -> bool:
		return _is_active

	func get_visibility_radius() -> float:
		return VISIBILITY_RADIUS

	func set_active(enabled: bool) -> void:
		_is_active = enabled

	func set_light_color(color: Color) -> void:
		_light_color = color

	func set_light_energy(energy: float) -> void:
		_light_energy = energy


var comp: MockRealisticVisibilityComponent


func before_each() -> void:
	comp = MockRealisticVisibilityComponent.new()


func after_each() -> void:
	comp = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_visibility_radius() -> void:
	assert_eq(MockRealisticVisibilityComponent.VISIBILITY_RADIUS, 600.0,
		"VISIBILITY_RADIUS should be 600.0 pixels")


func test_light_energy() -> void:
	assert_eq(MockRealisticVisibilityComponent.LIGHT_ENERGY, 1.5,
		"LIGHT_ENERGY should be 1.5")


func test_fog_color_red() -> void:
	assert_almost_eq(MockRealisticVisibilityComponent.FOG_COLOR.r, 0.02, 0.001,
		"FOG_COLOR red channel should be 0.02")


func test_fog_color_green() -> void:
	assert_almost_eq(MockRealisticVisibilityComponent.FOG_COLOR.g, 0.02, 0.001,
		"FOG_COLOR green channel should be 0.02")


func test_fog_color_blue() -> void:
	assert_almost_eq(MockRealisticVisibilityComponent.FOG_COLOR.b, 0.04, 0.001,
		"FOG_COLOR blue channel should be 0.04")


func test_fog_color_alpha() -> void:
	assert_eq(MockRealisticVisibilityComponent.FOG_COLOR.a, 1.0,
		"FOG_COLOR alpha should be 1.0")


func test_light_color_red() -> void:
	assert_eq(MockRealisticVisibilityComponent.LIGHT_COLOR.r, 1.0,
		"LIGHT_COLOR red channel should be 1.0")


func test_light_color_green() -> void:
	assert_almost_eq(MockRealisticVisibilityComponent.LIGHT_COLOR.g, 0.98, 0.001,
		"LIGHT_COLOR green channel should be 0.98")


func test_light_color_blue() -> void:
	assert_almost_eq(MockRealisticVisibilityComponent.LIGHT_COLOR.b, 0.95, 0.001,
		"LIGHT_COLOR blue channel should be 0.95")


func test_light_color_alpha() -> void:
	assert_eq(MockRealisticVisibilityComponent.LIGHT_COLOR.a, 1.0,
		"LIGHT_COLOR alpha should be 1.0")


# ============================================================================
# Active State Tracking Tests
# ============================================================================


func test_not_active_by_default() -> void:
	assert_false(comp.is_active(),
		"Should not be active by default")


func test_set_active_enables() -> void:
	comp.set_active(true)

	assert_true(comp.is_active(),
		"Should be active after enabling")


func test_set_active_disables() -> void:
	comp.set_active(true)
	comp.set_active(false)

	assert_false(comp.is_active(),
		"Should be inactive after disabling")


func test_toggle_active_state() -> void:
	comp.set_active(true)
	assert_true(comp.is_active())

	comp.set_active(false)
	assert_false(comp.is_active())

	comp.set_active(true)
	assert_true(comp.is_active(),
		"Should support toggling active state")


# ============================================================================
# Visibility Radius Tests
# ============================================================================


func test_get_visibility_radius() -> void:
	assert_eq(comp.get_visibility_radius(), 600.0,
		"get_visibility_radius should return VISIBILITY_RADIUS")


# ============================================================================
# Light Customization Tests
# ============================================================================


func test_set_light_color() -> void:
	var cold_blue := Color(0.45, 0.65, 1.0)
	comp.set_light_color(cold_blue)

	assert_eq(comp._light_color, cold_blue,
		"Should update light color")


func test_set_light_energy() -> void:
	comp.set_light_energy(0.8)

	assert_eq(comp._light_energy, 0.8,
		"Should update light energy")


func test_default_light_color() -> void:
	assert_eq(comp._light_color, MockRealisticVisibilityComponent.LIGHT_COLOR,
		"Default light color should match LIGHT_COLOR constant")


func test_default_light_energy() -> void:
	assert_eq(comp._light_energy, 1.5,
		"Default light energy should match LIGHT_ENERGY constant")


# ============================================================================
# Fog Color Semantics Tests
# ============================================================================


func test_fog_color_is_near_black() -> void:
	var fog := MockRealisticVisibilityComponent.FOG_COLOR
	var brightness := (fog.r + fog.g + fog.b) / 3.0

	assert_true(brightness < 0.05,
		"Fog color should be near black (very dark)")


func test_fog_color_has_slight_blue_tint() -> void:
	var fog := MockRealisticVisibilityComponent.FOG_COLOR

	assert_true(fog.b > fog.r,
		"Fog should have slight blue tint (blue > red)")
	assert_true(fog.b > fog.g,
		"Fog should have slight blue tint (blue > green)")


func test_light_color_is_warm_white() -> void:
	var light := MockRealisticVisibilityComponent.LIGHT_COLOR

	assert_true(light.r >= light.g,
		"Light color should be warm (red >= green)")
	assert_true(light.g >= light.b,
		"Light color should be warm (green >= blue)")
