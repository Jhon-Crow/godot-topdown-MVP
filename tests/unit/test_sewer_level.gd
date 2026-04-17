extends GutTest
## Unit tests for sewer_level.gd level script (Issue #1438).
##
## Tests saturation constants, exit zone configuration, level initialization,
## enemy counting, and level completion for the Sewer corridor level.


# ============================================================================
# Mock Classes
# ============================================================================


class MockSewerLevel:
	## Saturation effect constants (must match sewer_level.gd).
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

	## Exit zone configuration — at the end of the right fork branch.
	var exit_zone_position: Vector2 = Vector2(1050, 1450)
	var exit_zone_width: float = 60.0
	var exit_zone_height: float = 60.0

	## Track state changes.
	var exit_zone_activated: bool = false

	## Level name for identification.
	var level_name: String = "SewerLevel"

	## Sewer dimensions (1200x3200 pixels — vertical corridor with right branch fork).
	var map_width: int = 1200
	var map_height: int = 3200

	## Far-left impassable wall bounds.
	var left_wall_position: Vector2 = Vector2(88, 1600)
	var left_wall_size: Vector2 = Vector2(48, 3200)

	## Initialize with enemies.
	func initialize(enemy_count: int) -> void:
		_enemies.clear()
		for i in range(enemy_count):
			_enemies.append("SewerEnemy%d" % (i + 1))
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


var level: MockSewerLevel


func before_each() -> void:
	level = MockSewerLevel.new()


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
	assert_eq(level.exit_zone_position, Vector2(1050, 1450),
		"Sewer level exit zone should be at (1050, 1450) — end of right fork branch")


func test_exit_zone_dimensions() -> void:
	assert_eq(level.exit_zone_width, 60.0,
		"Exit zone width should be 60.0")
	assert_eq(level.exit_zone_height, 60.0,
		"Exit zone height should be 60.0")


# ============================================================================
# Level Initialization Tests
# ============================================================================


func test_level_starts_not_cleared() -> void:
	level.initialize(8)
	assert_false(level._level_cleared,
		"Level should not be cleared at start")
	assert_false(level._level_completed,
		"Level should not be completed at start")


func test_enemy_count_tracking() -> void:
	level.initialize(8)
	assert_eq(level._initial_enemy_count, 8,
		"Initial enemy count should be 8")
	assert_eq(level._current_enemy_count, 8,
		"Current enemy count should match initial")


func test_level_cleared_when_all_enemies_dead() -> void:
	level.initialize(8)
	for i in range(7):
		level.on_enemy_died()
	assert_false(level._level_cleared, "Not cleared with 1 enemy remaining")
	level.on_enemy_died()
	assert_true(level._level_cleared, "Level should be cleared when all enemies dead")
	assert_true(level.exit_zone_activated, "Exit zone should activate on clear")


func test_player_exit_completes_level() -> void:
	level.initialize(2)
	level.on_enemy_died()
	level.on_enemy_died()
	level.on_player_reached_exit()
	assert_true(level._level_completed,
		"Level should complete when player reaches exit after clearing")


func test_player_exit_blocked_before_clear() -> void:
	level.initialize(3)
	level.on_player_reached_exit()
	assert_false(level._level_completed,
		"Level should not complete if enemies remain")


func test_map_dimensions() -> void:
	assert_eq(level.map_width, 1200, "Sewer map width should be 1200 (corridor + right branch)")
	assert_eq(level.map_height, 3200, "Sewer map height should be 3200 (long corridor)")


func test_left_wall_is_thickened_left_without_narrowing_corridor() -> void:
	var left_edge := level.left_wall_position.x - level.left_wall_size.x / 2.0
	var right_edge := level.left_wall_position.x + level.left_wall_size.x / 2.0
	assert_eq(level.left_wall_size, Vector2(48, 3200),
		"Far-left wall should be twice as thick to block illusion pathing")
	assert_eq(left_edge, 64.0,
		"Far-left wall should extend left from its old 24px footprint")
	assert_eq(right_edge, 112.0,
		"Far-left wall right edge should stay aligned with the corridor floor")


func test_double_exit_prevented() -> void:
	level.initialize(1)
	level.on_enemy_died()
	level.on_player_reached_exit()
	level.on_player_reached_exit()
	assert_true(level._level_completed,
		"Level should remain completed after double exit")
