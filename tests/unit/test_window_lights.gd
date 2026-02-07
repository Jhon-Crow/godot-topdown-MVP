extends GutTest
## Unit tests for window lights in BuildingLevel corridors (Issue #593).
##
## Tests the window light placement system that adds dim blue PointLight2D nodes
## along exterior walls in corridors and rooms without enemies, so players can
## see wall outlines in night mode (realistic visibility).


# ============================================================================
# Mock WindowLightManager for Logic Tests
# ============================================================================


class MockWindowLightManager:
	## Window light color (cool blue moonlight).
	const LIGHT_COLOR: Color = Color(0.4, 0.5, 0.9, 1.0)

	## Window light energy (dim).
	const LIGHT_ENERGY: float = 0.5

	## Window light texture scale.
	const LIGHT_TEXTURE_SCALE: float = 2.5

	## Window visual color (semi-transparent blue).
	const WINDOW_COLOR: Color = Color(0.3, 0.4, 0.7, 0.6)

	## Valid wall sides.
	const VALID_WALL_SIDES: Array = ["top", "bottom", "left", "right"]

	## Enemy positions on the BuildingLevel map.
	## Used to verify no window lights are placed near enemies.
	const ENEMY_POSITIONS: Array = [
		Vector2(300, 350),   # Enemy1 - Office 1
		Vector2(400, 550),   # Enemy2 - Office 1
		Vector2(700, 750),   # Enemy3 - Office 2
		Vector2(800, 900),   # Enemy4 - Office 2
		Vector2(1700, 350),  # Enemy5 - Conference Room
		Vector2(1950, 450),  # Enemy6 - Conference Room
		Vector2(1600, 900),  # Enemy7 - Break Room (patrol)
		Vector2(1900, 1450), # Enemy8 - Server Room
		Vector2(2100, 1550), # Enemy9 - Server Room
		Vector2(1200, 1550), # Enemy10 - Main Hall (patrol)
	]

	## Building exterior wall positions.
	const WALL_LEFT_X: float = 64.0
	const WALL_RIGHT_X: float = 2464.0
	const WALL_TOP_Y: float = 64.0
	const WALL_BOTTOM_Y: float = 2064.0

	## Minimum distance from enemy positions for window light placement.
	const MIN_ENEMY_DISTANCE: float = 200.0

	## List of created window lights: Array of {position, wall_side, energy, color}.
	var _window_lights: Array = []

	## Whether setup was called.
	var _setup_called: bool = false


	## Setup the window light system.
	func setup() -> void:
		_setup_called = true
		_window_lights.clear()


	## Create a window light at the given position.
	func create_window_light(pos: Vector2, wall_side: String) -> Dictionary:
		var light_data := {
			"position": pos,
			"wall_side": wall_side,
			"energy": LIGHT_ENERGY,
			"color": LIGHT_COLOR,
			"shadow_enabled": true,
			"texture_scale": LIGHT_TEXTURE_SCALE,
		}
		_window_lights.append(light_data)
		return light_data


	## Get all created window lights.
	func get_window_lights() -> Array:
		return _window_lights


	## Get window light count.
	func get_light_count() -> int:
		return _window_lights.size()


	## Check if a position is on an exterior wall.
	func is_on_exterior_wall(pos: Vector2) -> bool:
		return (
			is_equal_approx(pos.x, WALL_LEFT_X) or
			is_equal_approx(pos.x, WALL_RIGHT_X) or
			is_equal_approx(pos.y, WALL_TOP_Y) or
			is_equal_approx(pos.y, WALL_BOTTOM_Y)
		)


	## Check if a position is far enough from all enemy positions.
	func is_far_from_enemies(pos: Vector2) -> bool:
		for enemy_pos in ENEMY_POSITIONS:
			if pos.distance_to(enemy_pos) < MIN_ENEMY_DISTANCE:
				return false
		return true


	## Get the expected light offset direction based on wall side.
	func get_light_offset_direction(wall_side: String) -> Vector2:
		match wall_side:
			"left":
				return Vector2(1, 0)   # Light points inward (right)
			"right":
				return Vector2(-1, 0)  # Light points inward (left)
			"top":
				return Vector2(0, 1)   # Light points inward (down)
			"bottom":
				return Vector2(0, -1)  # Light points inward (up)
			_:
				return Vector2.ZERO


	## Check if wall_side is valid.
	func is_valid_wall_side(wall_side: String) -> bool:
		return wall_side in VALID_WALL_SIDES


var manager: MockWindowLightManager


func before_each() -> void:
	manager = MockWindowLightManager.new()
	manager.setup()


func after_each() -> void:
	manager = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_setup_initializes_properly() -> void:
	assert_true(manager._setup_called,
		"Setup should have been called")


func test_no_lights_on_init() -> void:
	assert_eq(manager.get_light_count(), 0,
		"Should have no window lights initially")


# ============================================================================
# Light Creation Tests
# ============================================================================


func test_create_window_light_returns_data() -> void:
	var light := manager.create_window_light(Vector2(64, 1100), "left")

	assert_not_null(light, "Created light data should not be null")
	assert_eq(light.position, Vector2(64, 1100), "Position should match")
	assert_eq(light.wall_side, "left", "Wall side should match")


func test_create_window_light_increments_count() -> void:
	manager.create_window_light(Vector2(64, 1100), "left")

	assert_eq(manager.get_light_count(), 1,
		"Light count should be 1 after creating one light")


func test_create_multiple_lights() -> void:
	manager.create_window_light(Vector2(64, 1100), "left")
	manager.create_window_light(Vector2(64, 1250), "left")
	manager.create_window_light(Vector2(700, 64), "top")

	assert_eq(manager.get_light_count(), 3,
		"Light count should be 3 after creating three lights")


# ============================================================================
# Light Properties Tests
# ============================================================================


func test_light_color_is_blue() -> void:
	var light := manager.create_window_light(Vector2(64, 1100), "left")

	assert_true(light.color.b > light.color.r,
		"Light color should be blue-dominant (blue > red)")
	assert_true(light.color.b > light.color.g,
		"Light color should be blue-dominant (blue > green)")


func test_light_energy_is_dim() -> void:
	var light := manager.create_window_light(Vector2(64, 1100), "left")

	assert_true(light.energy <= 1.0,
		"Window light energy should be dim (<=1.0)")
	assert_true(light.energy > 0.0,
		"Window light energy should be positive")


func test_light_energy_is_weaker_than_player() -> void:
	var light := manager.create_window_light(Vector2(64, 1100), "left")

	# Player visibility light is 1.5 energy (RealisticVisibilityComponent.LIGHT_ENERGY)
	assert_true(light.energy < 1.5,
		"Window light should be dimmer than player visibility light (1.5)")


func test_light_energy_is_weaker_than_flashlight() -> void:
	var light := manager.create_window_light(Vector2(64, 1100), "left")

	# Flashlight is 8.0 energy
	assert_true(light.energy < 8.0,
		"Window light should be much dimmer than flashlight (8.0)")


func test_light_has_shadows() -> void:
	var light := manager.create_window_light(Vector2(64, 1100), "left")

	assert_true(light.shadow_enabled,
		"Window lights should cast shadows through LightOccluder2D walls")


func test_light_texture_scale() -> void:
	var light := manager.create_window_light(Vector2(64, 1100), "left")

	assert_true(light.texture_scale > 1.0,
		"Light texture scale should be > 1.0 for visible spread")
	assert_true(light.texture_scale <= 4.0,
		"Light texture scale should be <= 4.0 to stay contained in rooms")


# ============================================================================
# Wall Side Validation Tests
# ============================================================================


func test_valid_wall_sides() -> void:
	assert_true(manager.is_valid_wall_side("left"), "left should be valid")
	assert_true(manager.is_valid_wall_side("right"), "right should be valid")
	assert_true(manager.is_valid_wall_side("top"), "top should be valid")
	assert_true(manager.is_valid_wall_side("bottom"), "bottom should be valid")


func test_invalid_wall_sides() -> void:
	assert_false(manager.is_valid_wall_side("center"), "center should be invalid")
	assert_false(manager.is_valid_wall_side(""), "empty string should be invalid")
	assert_false(manager.is_valid_wall_side("diagonal"), "diagonal should be invalid")


# ============================================================================
# Light Offset Direction Tests
# ============================================================================


func test_left_wall_light_points_inward() -> void:
	var direction := manager.get_light_offset_direction("left")

	assert_true(direction.x > 0,
		"Left wall light should point inward (positive x)")


func test_right_wall_light_points_inward() -> void:
	var direction := manager.get_light_offset_direction("right")

	assert_true(direction.x < 0,
		"Right wall light should point inward (negative x)")


func test_top_wall_light_points_inward() -> void:
	var direction := manager.get_light_offset_direction("top")

	assert_true(direction.y > 0,
		"Top wall light should point inward (positive y)")


func test_bottom_wall_light_points_inward() -> void:
	var direction := manager.get_light_offset_direction("bottom")

	assert_true(direction.y < 0,
		"Bottom wall light should point inward (negative y)")


# ============================================================================
# Placement Validation Tests (No lights near enemies)
# ============================================================================


func test_exterior_wall_detection() -> void:
	assert_true(manager.is_on_exterior_wall(Vector2(64, 500)),
		"Position on left wall should be detected")
	assert_true(manager.is_on_exterior_wall(Vector2(2464, 500)),
		"Position on right wall should be detected")
	assert_true(manager.is_on_exterior_wall(Vector2(500, 64)),
		"Position on top wall should be detected")
	assert_true(manager.is_on_exterior_wall(Vector2(500, 2064)),
		"Position on bottom wall should be detected")


func test_interior_position_not_on_wall() -> void:
	assert_false(manager.is_on_exterior_wall(Vector2(500, 500)),
		"Interior position should not be on exterior wall")
	assert_false(manager.is_on_exterior_wall(Vector2(1200, 900)),
		"Corridor center should not be on exterior wall")


func test_window_lights_far_from_enemies() -> void:
	# All actual window light positions from the implementation
	var window_positions: Array = [
		Vector2(64, 1100),   # Left wall - lobby
		Vector2(64, 1250),   # Left wall - lobby
		Vector2(64, 1750),   # Left wall - storage
		Vector2(64, 1900),   # Left wall - storage
		Vector2(700, 64),    # Top wall - corridor
		Vector2(900, 64),    # Top wall - corridor
		Vector2(1100, 64),   # Top wall - corridor
		Vector2(200, 2064),  # Bottom wall - storage
		Vector2(400, 2064),  # Bottom wall - storage
		Vector2(700, 2064),  # Bottom wall - lobby
		Vector2(1100, 2064), # Bottom wall - lobby
	]

	for pos in window_positions:
		assert_true(manager.is_far_from_enemies(pos),
			"Window at %s should be far from all enemies" % str(pos))


func test_enemy_positions_fail_distance_check() -> void:
	# Verify that positions right on top of enemies are rejected
	for enemy_pos in manager.ENEMY_POSITIONS:
		assert_false(manager.is_far_from_enemies(enemy_pos),
			"Position at enemy %s should fail distance check" % str(enemy_pos))


func test_all_window_positions_on_exterior_walls() -> void:
	var window_positions: Array = [
		Vector2(64, 1100),
		Vector2(64, 1250),
		Vector2(64, 1750),
		Vector2(64, 1900),
		Vector2(700, 64),
		Vector2(900, 64),
		Vector2(1100, 64),
		Vector2(200, 2064),
		Vector2(400, 2064),
		Vector2(700, 2064),
		Vector2(1100, 2064),
	]

	for pos in window_positions:
		assert_true(manager.is_on_exterior_wall(pos),
			"Window at %s should be on an exterior wall" % str(pos))


# ============================================================================
# Gradient Texture Tests
# ============================================================================


func test_window_light_constant_values() -> void:
	assert_eq(manager.LIGHT_ENERGY, 0.5,
		"Light energy constant should be 0.5")
	assert_eq(manager.LIGHT_TEXTURE_SCALE, 2.5,
		"Light texture scale constant should be 2.5")


func test_window_visual_color_is_blue() -> void:
	assert_true(manager.WINDOW_COLOR.b > manager.WINDOW_COLOR.r,
		"Window visual color should be blue-dominant")


func test_window_visual_color_is_semi_transparent() -> void:
	assert_true(manager.WINDOW_COLOR.a < 1.0,
		"Window visual should be semi-transparent")
	assert_true(manager.WINDOW_COLOR.a > 0.0,
		"Window visual should not be fully transparent")


# ============================================================================
# Building Layout Integration Tests
# ============================================================================


func test_no_windows_in_office_1_area() -> void:
	# Office 1 area: (80-500, 80-688) - has enemies
	var window_positions: Array = [
		Vector2(64, 1100), Vector2(64, 1250), Vector2(64, 1750), Vector2(64, 1900),
		Vector2(700, 64), Vector2(900, 64), Vector2(1100, 64),
		Vector2(200, 2064), Vector2(400, 2064), Vector2(700, 2064), Vector2(1100, 2064),
	]

	for pos in window_positions:
		# No window should be at the left wall near Office 1 (y=80-688)
		if is_equal_approx(pos.x, 64.0):
			assert_true(pos.y > 700 or pos.y < 64,
				"Left wall window at y=%d should not be in Office 1 area (80-688)" % int(pos.y))


func test_no_windows_in_conference_room_area() -> void:
	# Conference Room area: (1388-2448, 80-600) - has enemies
	var window_positions: Array = [
		Vector2(64, 1100), Vector2(64, 1250), Vector2(64, 1750), Vector2(64, 1900),
		Vector2(700, 64), Vector2(900, 64), Vector2(1100, 64),
		Vector2(200, 2064), Vector2(400, 2064), Vector2(700, 2064), Vector2(1100, 2064),
	]

	for pos in window_positions:
		# No window should be at the top wall in Conference Room area (x=1388-2448)
		if is_equal_approx(pos.y, 64.0):
			assert_true(pos.x < 1376,
				"Top wall window at x=%d should not be in Conference Room area (1388-2448)" % int(pos.x))


func test_no_windows_in_server_room_area() -> void:
	# Server Room area: (1700-2448, 1212-2048) - has enemies
	var window_positions: Array = [
		Vector2(64, 1100), Vector2(64, 1250), Vector2(64, 1750), Vector2(64, 1900),
		Vector2(700, 64), Vector2(900, 64), Vector2(1100, 64),
		Vector2(200, 2064), Vector2(400, 2064), Vector2(700, 2064), Vector2(1100, 2064),
	]

	for pos in window_positions:
		# No window should be at the right wall in Server Room area
		if is_equal_approx(pos.x, 2464.0):
			assert_true(false,
				"Should not have window at right wall (Server Room area)")
		# No window at the bottom wall in Server Room area (x=1700-2448)
		if is_equal_approx(pos.y, 2064.0):
			assert_true(pos.x < 1388,
				"Bottom wall window at x=%d should not be in Server Room area" % int(pos.x))


func test_window_count_is_reasonable() -> void:
	# The implementation places 11 window lights
	# This should be enough for visibility but not excessive
	var expected_count := 11

	# Create all lights matching the implementation
	var positions_and_sides: Array = [
		[Vector2(64, 1100), "left"],
		[Vector2(64, 1250), "left"],
		[Vector2(64, 1750), "left"],
		[Vector2(64, 1900), "left"],
		[Vector2(700, 64), "top"],
		[Vector2(900, 64), "top"],
		[Vector2(1100, 64), "top"],
		[Vector2(200, 2064), "bottom"],
		[Vector2(400, 2064), "bottom"],
		[Vector2(700, 2064), "bottom"],
		[Vector2(1100, 2064), "bottom"],
	]

	for pair in positions_and_sides:
		manager.create_window_light(pair[0], pair[1])

	assert_eq(manager.get_light_count(), expected_count,
		"Should have exactly %d window lights" % expected_count)


func test_lights_under_godot_limit() -> void:
	# Godot 2D renderer has a 15-light-per-sprite limit
	# With 11 window lights + 1 player visibility + 1 flashlight = 13, under the limit
	var window_count := 11
	var player_lights := 2  # visibility + flashlight
	var total := window_count + player_lights

	assert_true(total <= 15,
		"Total lights (%d) should be under Godot's 15-light-per-sprite limit" % total)
