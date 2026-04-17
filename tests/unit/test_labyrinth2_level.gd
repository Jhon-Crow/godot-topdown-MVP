extends GutTest
## Unit tests for labyrinth2_level.gd level script.
##
## Tests saturation constants, exit zone configuration, and level initialization
## for the larger labyrinth-style building with 17 enemies.


# ============================================================================
# Mock Classes
# ============================================================================


class MockLabyrinth2Level:
	## Saturation effect constants (must match labyrinth2_level.gd).
	const SATURATION_DURATION: float = 0.15
	const SATURATION_INTENSITY: float = 0.25

	## Level state variables.
	var _initial_enemy_count: int = 0
	var _current_enemy_count: int = 0
	var _level_cleared: bool = false
	var _level_completed: bool = false
	var _game_over_shown: bool = false
	var _score_shown: bool = false
	var _enemies: Array = []

	## Exit zone configuration.
	var exit_zone_position: Vector2 = Vector2(3200, 1200)
	var exit_zone_width: float = 60.0
	var exit_zone_height: float = 100.0

	## Track state changes.
	var exit_zone_activated: bool = false

	## Level name for identification.
	var level_name: String = "Labyrinth2Level"

	## Labyrinth 2 dimensions (~3200x2400 pixels).
	var map_width: int = 3200
	var map_height: int = 2400

	## Floor rendering contract.
	var floor_node_type: String = "Polygon2D"
	var environment_light_mask: int = 3
	var muzzle_flash_light_mask: int = 3
	var floor_polygon: PackedVector2Array = PackedVector2Array([
		Vector2(64, 64),
		Vector2(3264, 64),
		Vector2(3264, 2464),
		Vector2(64, 2464),
	])
	var floor_color: Color = Color(0.17, 0.15, 0.13, 1)

	## Default enemy count for labyrinth 2 level.
	var default_enemy_count: int = 17

	## Initialize with default enemies.
	func initialize() -> void:
		_enemies.clear()
		for i in range(default_enemy_count):
			_enemies.append("Lab2Enemy%d" % (i + 1))
		_initial_enemy_count = _enemies.size()
		_current_enemy_count = _initial_enemy_count

	## Called when an enemy dies.
	func on_enemy_died() -> void:
		_current_enemy_count -= 1
		if _current_enemy_count <= 0:
			_level_cleared = true
			exit_zone_activated = true

	## Called when player reaches exit after clearing.
	func on_player_reached_exit() -> void:
		if not _level_cleared or _level_completed:
			return
		_level_completed = true


var level: MockLabyrinth2Level


func before_each() -> void:
	level = MockLabyrinth2Level.new()


func after_each() -> void:
	level = null


# ============================================================================
# Saturation Constants Tests
# ============================================================================


func test_saturation_duration() -> void:
	assert_eq(level.SATURATION_DURATION, 0.15,
		"SATURATION_DURATION should be 0.15 seconds")


func test_saturation_intensity() -> void:
	assert_eq(level.SATURATION_INTENSITY, 0.25,
		"SATURATION_INTENSITY should be 0.25")


# ============================================================================
# Exit Zone Tests
# ============================================================================


func test_exit_zone_position() -> void:
	assert_eq(level.exit_zone_position, Vector2(3200, 1200),
		"Labyrinth 2 exit zone should be at (3200, 1200)")


func test_exit_zone_dimensions() -> void:
	assert_eq(level.exit_zone_width, 60.0,
		"Exit zone width should be 60.0")
	assert_eq(level.exit_zone_height, 100.0,
		"Exit zone height should be 100.0")


# ============================================================================
# Level Initialization Tests
# ============================================================================


func test_default_enemy_count() -> void:
	assert_eq(level.default_enemy_count, 17,
		"Labyrinth 2 level should have 17 enemies by default")


func test_level_starts_not_cleared() -> void:
	level.initialize()
	assert_false(level._level_cleared,
		"Level should not be cleared at start")
	assert_false(level._level_completed,
		"Level should not be completed at start")


func test_enemy_count_initialized_correctly() -> void:
	level.initialize()
	assert_eq(level._initial_enemy_count, 17,
		"Initial enemy count should be 17")
	assert_eq(level._current_enemy_count, 17,
		"Current enemy count should be 17 at start")


func test_level_cleared_when_all_enemies_dead() -> void:
	level.initialize()
	for i in range(16):
		level.on_enemy_died()
	assert_false(level._level_cleared, "Not cleared with 1 enemy remaining")
	level.on_enemy_died()
	assert_true(level._level_cleared, "Level should be cleared when all 17 enemies dead")
	assert_true(level.exit_zone_activated, "Exit zone should activate on clear")


func test_player_exit_completes_level() -> void:
	level.initialize()
	for i in range(17):
		level.on_enemy_died()
	level.on_player_reached_exit()
	assert_true(level._level_completed,
		"Level should complete when player reaches exit after clearing")


func test_player_exit_blocked_before_clear() -> void:
	level.initialize()
	level.on_player_reached_exit()
	assert_false(level._level_completed,
		"Level should not complete if enemies remain")


func test_map_dimensions() -> void:
	assert_eq(level.map_width, 3200, "Labyrinth 2 map width should be 3200")
	assert_eq(level.map_height, 2400, "Labyrinth 2 map height should be 2400")


func test_floor_uses_light_reactive_canvas_geometry() -> void:
	assert_eq(level.floor_node_type, "Polygon2D",
		"Labyrinth Complex floor should be Polygon2D so PointLight2D muzzle flashes affect it")


func test_floor_preserves_original_bounds() -> void:
	var expected := PackedVector2Array([
		Vector2(64, 64),
		Vector2(3264, 64),
		Vector2(3264, 2464),
		Vector2(64, 2464),
	])
	assert_eq(level.floor_polygon, expected,
		"Light-reactive floor should preserve the original 64..3264 by 64..2464 playfield bounds")


func test_floor_preserves_original_color() -> void:
	assert_eq(level.floor_color, Color(0.17, 0.15, 0.13, 1),
		"Light-reactive floor should preserve the original Labyrinth Complex floor color")


func test_floor_shares_muzzle_flash_light_mask() -> void:
	assert_eq(level.environment_light_mask, level.muzzle_flash_light_mask,
		"Labyrinth Complex floor should share the muzzle flash light mask so it visibly pulses")


func test_wall_and_cover_visuals_share_muzzle_flash_light_mask() -> void:
	assert_eq(level.environment_light_mask, 3,
		"Labyrinth Complex wall and cover ColorRects should stay on light mask 3 for muzzle flashes and shadows")
