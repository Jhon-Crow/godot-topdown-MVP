extends GutTest
## Unit tests for beach_level.gd level script.
##
## Tests saturation constants, exit zone configuration, and level initialization
## for the outdoor beach combat environment.


# ============================================================================
# Mock Classes
# ============================================================================


class MockBeachLevel:
	## Saturation effect constants (must match beach_level.gd).
	const SATURATION_DURATION: float = 0.15
	const SATURATION_INTENSITY: float = 0.25

	## Level state variables.
	var _initial_enemy_count: int = 0
	var _current_enemy_count: int = 0
	var _level_cleared: bool = false
	var _level_completed: bool = false
	var _game_over_shown: bool = false
	var _enemies: Array = []

	## Exit zone configuration.
	var exit_zone_position: Vector2 = Vector2(120, 1800)
	var exit_zone_width: float = 60.0
	var exit_zone_height: float = 100.0

	## Track state changes.
	var exit_zone_activated: bool = false

	## Level name for identification.
	var level_name: String = "BeachLevel"

	## Map dimensions (~2400x2000 pixels).
	var map_width: int = 2400
	var map_height: int = 2000

	## Initialize with enemies.
	func initialize(enemy_count: int) -> void:
		_enemies.clear()
		for i in range(enemy_count):
			_enemies.append("BeachEnemy%d" % (i + 1))
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


var level: MockBeachLevel


func before_each() -> void:
	level = MockBeachLevel.new()


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
	assert_eq(level.exit_zone_position, Vector2(120, 1800),
		"Beach level exit zone should be at (120, 1800)")


func test_exit_zone_dimensions() -> void:
	assert_eq(level.exit_zone_width, 60.0,
		"Exit zone width should be 60.0")
	assert_eq(level.exit_zone_height, 100.0,
		"Exit zone height should be 100.0")


# ============================================================================
# Level Initialization Tests
# ============================================================================


func test_level_starts_not_cleared() -> void:
	level.initialize(5)
	assert_false(level._level_cleared,
		"Level should not be cleared at start")
	assert_false(level._level_completed,
		"Level should not be completed at start")


func test_enemy_count_tracking() -> void:
	level.initialize(8)
	assert_eq(level._initial_enemy_count, 8,
		"Initial enemy count should match")
	assert_eq(level._current_enemy_count, 8,
		"Current enemy count should match initial at start")


func test_level_cleared_when_all_enemies_dead() -> void:
	level.initialize(3)
	level.on_enemy_died()
	level.on_enemy_died()
	assert_false(level._level_cleared, "Not cleared with enemies remaining")
	level.on_enemy_died()
	assert_true(level._level_cleared, "Level should be cleared when all enemies dead")
	assert_true(level.exit_zone_activated, "Exit zone should activate on clear")


func test_player_exit_completes_level() -> void:
	level.initialize(1)
	level.on_enemy_died()
	level.on_player_reached_exit()
	assert_true(level._level_completed,
		"Level should complete when player reaches exit after clearing")


func test_player_exit_blocked_before_clear() -> void:
	level.initialize(2)
	level.on_enemy_died()
	level.on_player_reached_exit()
	assert_false(level._level_completed,
		"Level should not complete if enemies remain")


func test_map_dimensions() -> void:
	assert_eq(level.map_width, 2400, "Beach map width should be 2400")
	assert_eq(level.map_height, 2000, "Beach map height should be 2000")
