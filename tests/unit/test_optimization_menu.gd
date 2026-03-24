extends GutTest
## Unit tests for OptimizationMenu.
##
## Tests ROW_HOVER_BG color and wall hit particles toggle logic
## using a mock class.


# ============================================================================
# Mock OptimizationMenu for Testing
# ============================================================================


class MockOptimizationMenu:
	## Semi-transparent background colour drawn over a settings row on hover.
	const ROW_HOVER_BG: Color = Color(1.0, 1.0, 1.0, 0.08)

	## Wall hit particles setting.
	var wall_hit_particles_enabled: bool = true

	## Signal tracking.
	var back_pressed_count: int = 0

	## Toggle wall hit particles.
	func set_wall_hit_particles(enabled: bool) -> void:
		wall_hit_particles_enabled = enabled

	## Check if wall hit particles are enabled.
	func is_wall_hit_particles_enabled() -> bool:
		return wall_hit_particles_enabled

	## Press back.
	func press_back() -> void:
		back_pressed_count += 1


var menu: MockOptimizationMenu


func before_each() -> void:
	menu = MockOptimizationMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# ROW_HOVER_BG Tests
# ============================================================================


func test_row_hover_bg_value() -> void:
	assert_eq(menu.ROW_HOVER_BG, Color(1.0, 1.0, 1.0, 0.08),
		"ROW_HOVER_BG should be Color(1.0, 1.0, 1.0, 0.08)")


func test_row_hover_bg_alpha() -> void:
	assert_almost_eq(menu.ROW_HOVER_BG.a, 0.08, 0.001,
		"ROW_HOVER_BG alpha should be approximately 0.08")


# ============================================================================
# Wall Hit Particles Toggle Tests
# ============================================================================


func test_wall_hit_particles_default_enabled() -> void:
	assert_true(menu.is_wall_hit_particles_enabled(),
		"Wall hit particles should be enabled by default")


func test_disable_wall_hit_particles() -> void:
	menu.set_wall_hit_particles(false)

	assert_false(menu.is_wall_hit_particles_enabled(),
		"Should be able to disable wall hit particles")


func test_reenable_wall_hit_particles() -> void:
	menu.set_wall_hit_particles(false)
	menu.set_wall_hit_particles(true)

	assert_true(menu.is_wall_hit_particles_enabled(),
		"Should be able to re-enable wall hit particles")


# ============================================================================
# Back Button Tests
# ============================================================================


func test_back_button() -> void:
	menu.press_back()

	assert_eq(menu.back_pressed_count, 1,
		"Should track back press")
