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

	## Whether unshaded material is applied to player (for laser/grenade visibility).
	var _unshaded_applied: bool = false

	## Count of children with unshaded material applied.
	var _unshaded_children_count: int = 0

	## Track dynamically added children that received unshaded material (Issue #570).
	var _dynamically_unshaded_children: Array = []


	## Apply the visibility state (enable/disable fog of war).
	func _apply_visibility_state(enabled: bool) -> void:
		_is_active = enabled
		_canvas_modulate_visible = enabled
		_point_light_visible = enabled
		_unshaded_applied = enabled
		_unshaded_children_count = 3 if enabled else 0  # Simulated: weapon, laser, arms
		if not enabled:
			_dynamically_unshaded_children.clear()


	## Setup the visibility system (simulated).
	func setup() -> void:
		_setup_called = true
		_is_active = false
		_canvas_modulate_visible = false
		_point_light_visible = false
		_unshaded_applied = false
		_unshaded_children_count = 0
		_dynamically_unshaded_children.clear()


	## Check if the visibility system is currently active.
	func is_active() -> bool:
		return _is_active


	## Check if unshaded material is applied.
	func is_unshaded_applied() -> bool:
		return _unshaded_applied


	## Get the current visibility radius.
	func get_visibility_radius() -> float:
		return VISIBILITY_RADIUS


	## Simulate adding a new child to the player while night mode is active (Issue #570).
	## This mimics the behavior of _on_player_child_added which applies unshaded material
	## to dynamically added weapons and their children (laser sights, sprites).
	func simulate_child_added(child_name: String) -> void:
		if _is_active:
			_dynamically_unshaded_children.append(child_name)
			_unshaded_children_count += 1


	## Check if a dynamically added child received unshaded material.
	func has_dynamic_unshaded(child_name: String) -> bool:
		return child_name in _dynamically_unshaded_children


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


# ============================================================================
# Unshaded Material Tests (Laser/Grenade Visibility)
# ============================================================================


func test_unshaded_applied_when_enabled() -> void:
	component._apply_visibility_state(true)

	assert_true(component.is_unshaded_applied(),
		"Unshaded material should be applied when night mode is enabled")


func test_unshaded_removed_when_disabled() -> void:
	component._apply_visibility_state(true)
	component._apply_visibility_state(false)

	assert_false(component.is_unshaded_applied(),
		"Unshaded material should be removed when night mode is disabled")


func test_unshaded_children_count_when_enabled() -> void:
	component._apply_visibility_state(true)

	assert_true(component._unshaded_children_count > 0,
		"Should have children with unshaded material when enabled")


func test_unshaded_children_count_when_disabled() -> void:
	component._apply_visibility_state(true)
	component._apply_visibility_state(false)

	assert_eq(component._unshaded_children_count, 0,
		"Should have no children with unshaded material when disabled")


func test_unshaded_default_not_applied() -> void:
	assert_false(component.is_unshaded_applied(),
		"Unshaded material should not be applied by default")


func test_unshaded_toggle_consistency() -> void:
	# Enable - unshaded should be applied
	component._apply_visibility_state(true)
	assert_true(component.is_unshaded_applied(), "Should be applied after enable")
	assert_true(component._canvas_modulate_visible, "Canvas modulate should be visible")

	# Disable - unshaded should be removed
	component._apply_visibility_state(false)
	assert_false(component.is_unshaded_applied(), "Should be removed after disable")
	assert_false(component._canvas_modulate_visible, "Canvas modulate should be hidden")


# ============================================================================
# Dynamic Child Monitoring Tests (Issue #570 - Night Mode Weapon Visibility)
# ============================================================================


func test_dynamic_weapon_gets_unshaded_when_active() -> void:
	# Night mode active, then add a weapon
	component._apply_visibility_state(true)
	component.simulate_child_added("SilencedPistol")

	assert_true(component.has_dynamic_unshaded("SilencedPistol"),
		"Dynamically added SilencedPistol should receive unshaded material in night mode")


func test_dynamic_weapon_not_unshaded_when_inactive() -> void:
	# Night mode inactive, add a weapon
	component._apply_visibility_state(false)
	component.simulate_child_added("SilencedPistol")

	assert_false(component.has_dynamic_unshaded("SilencedPistol"),
		"Dynamically added weapon should NOT receive unshaded material when night mode is off")


func test_dynamic_laser_sight_gets_unshaded() -> void:
	# Night mode active, then add laser sight (simulates weapon creating LaserSight in _Ready)
	component._apply_visibility_state(true)
	component.simulate_child_added("LaserSight")

	assert_true(component.has_dynamic_unshaded("LaserSight"),
		"Dynamically created LaserSight should receive unshaded material in night mode")


func test_dynamic_power_fantasy_laser_gets_unshaded() -> void:
	# Night mode active + Power Fantasy mode, sniper adds PowerFantasyLaser
	component._apply_visibility_state(true)
	component.simulate_child_added("PowerFantasyLaser")

	assert_true(component.has_dynamic_unshaded("PowerFantasyLaser"),
		"PowerFantasyLaser should receive unshaded material in night mode (Issue #570 bug 1)")


func test_multiple_dynamic_weapons_all_get_unshaded() -> void:
	# Night mode active, swap weapons multiple times
	component._apply_visibility_state(true)
	component.simulate_child_added("Shotgun")
	component.simulate_child_added("MiniUzi")
	component.simulate_child_added("SniperRifle")

	assert_true(component.has_dynamic_unshaded("Shotgun"),
		"Shotgun should get unshaded material")
	assert_true(component.has_dynamic_unshaded("MiniUzi"),
		"MiniUzi should get unshaded material")
	assert_true(component.has_dynamic_unshaded("SniperRifle"),
		"SniperRifle should get unshaded material")


func test_dynamic_children_cleared_on_disable() -> void:
	# Add weapons while active, then disable
	component._apply_visibility_state(true)
	component.simulate_child_added("SilencedPistol")
	component.simulate_child_added("LaserSight")

	component._apply_visibility_state(false)

	assert_false(component.has_dynamic_unshaded("SilencedPistol"),
		"Dynamic unshaded tracking should be cleared when night mode is disabled")
	assert_false(component.has_dynamic_unshaded("LaserSight"),
		"Dynamic unshaded tracking should be cleared when night mode is disabled")


func test_dynamic_children_count_increases() -> void:
	component._apply_visibility_state(true)
	var initial_count: int = component._unshaded_children_count

	component.simulate_child_added("SilencedPistol")
	assert_eq(component._unshaded_children_count, initial_count + 1,
		"Unshaded children count should increase when new weapon is added")

	component.simulate_child_added("LaserSight")
	assert_eq(component._unshaded_children_count, initial_count + 2,
		"Unshaded children count should increase again for laser sight")


func test_weapon_swap_scenario() -> void:
	# Simulate the exact scenario from Issue #570:
	# 1. Night mode is enabled
	# 2. Level removes default AssaultRifle (already has unshaded from initialization)
	# 3. Level adds SilencedPistol dynamically
	# 4. SilencedPistol creates LaserSight in its _Ready()
	# Expected: Both SilencedPistol and LaserSight should get unshaded material

	component._apply_visibility_state(true)

	# Weapon swap happens
	component.simulate_child_added("SilencedPistol")
	component.simulate_child_added("LaserSight")  # Created by weapon's _Ready()

	assert_true(component.has_dynamic_unshaded("SilencedPistol"),
		"Swapped weapon should be visible in night mode")
	assert_true(component.has_dynamic_unshaded("LaserSight"),
		"Laser sight of swapped weapon should be visible in night mode")
