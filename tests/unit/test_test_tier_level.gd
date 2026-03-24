extends GutTest
## Unit tests for test_tier.gd level script.
##
## Tests saturation constants, exit zone configuration, and level initialization
## for the Tactical Combat Arena (Polyhon) level with 12 enemies.


# ============================================================================
# Mock Classes
# ============================================================================


class MockTestTierLevel:
	## Saturation effect constants (must match test_tier.gd).
	const SATURATION_DURATION: float = 0.15
	const SATURATION_INTENSITY: float = 0.25

	## Level state variables.
	var _initial_enemy_count: int = 0
	var _current_enemy_count: int = 0
	var _level_cleared: bool = false
	var _game_over_shown: bool = false
	var _score_shown: bool = false
	var _enemies: Array = []

	## Exit zone configuration.
	var exit_zone_position: Vector2 = Vector2(120, 1544)
	var exit_zone_width: float = 60.0
	var exit_zone_height: float = 100.0

	## Track state changes.
	var exit_zone_activated: bool = false

	## Level name for identification.
	var level_name: String = "TestTier"

	## Map dimensions (4000x2960 playable area).
	var map_width: int = 4000
	var map_height: int = 2960

	## Default enemy count for test tier level.
	var default_enemy_count: int = 12

	## Initialize with default enemies.
	func initialize() -> void:
		_enemies.clear()
		for i in range(default_enemy_count):
			_enemies.append("TestTierEnemy%d" % (i + 1))
		_initial_enemy_count = _enemies.size()
		_current_enemy_count = _initial_enemy_count

	## Called when an enemy dies.
	func on_enemy_died() -> void:
		_current_enemy_count -= 1
		if _current_enemy_count <= 0:
			_level_cleared = true
			exit_zone_activated = true

	## Format enemy count label.
	func format_enemy_count() -> String:
		return "Enemies: %d" % _current_enemy_count


var level: MockTestTierLevel


func before_each() -> void:
	level = MockTestTierLevel.new()


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
	assert_eq(level.exit_zone_position, Vector2(120, 1544),
		"TestTier exit zone should be at (120, 1544)")


func test_exit_zone_dimensions() -> void:
	assert_eq(level.exit_zone_width, 60.0,
		"Exit zone width should be 60.0")
	assert_eq(level.exit_zone_height, 100.0,
		"Exit zone height should be 100.0")


# ============================================================================
# Level Initialization Tests
# ============================================================================


func test_default_enemy_count() -> void:
	assert_eq(level.default_enemy_count, 12,
		"TestTier level should have 12 enemies by default")


func test_level_starts_not_cleared() -> void:
	level.initialize()
	assert_false(level._level_cleared,
		"Level should not be cleared at start")


func test_enemy_count_initialized_correctly() -> void:
	level.initialize()
	assert_eq(level._initial_enemy_count, 12,
		"Initial enemy count should be 12")
	assert_eq(level._current_enemy_count, 12,
		"Current enemy count should be 12 at start")


func test_level_cleared_when_all_enemies_dead() -> void:
	level.initialize()
	for i in range(11):
		level.on_enemy_died()
	assert_false(level._level_cleared, "Not cleared with 1 enemy remaining")
	level.on_enemy_died()
	assert_true(level._level_cleared, "Level should be cleared when all 12 enemies dead")
	assert_true(level.exit_zone_activated, "Exit zone should activate on clear")


func test_format_enemy_count_label() -> void:
	level.initialize()
	assert_eq(level.format_enemy_count(), "Enemies: 12",
		"Label should show full count at start")
	level.on_enemy_died()
	assert_eq(level.format_enemy_count(), "Enemies: 11",
		"Label should update after kill")


func test_map_dimensions() -> void:
	assert_eq(level.map_width, 4000, "TestTier map width should be 4000")
	assert_eq(level.map_height, 2960, "TestTier map height should be 2960")
