extends GutTest
## Unit tests for building_level.gd level script.
##
## Tests saturation constants, exit zone configuration, and level initialization
## for the Hotline Miami style building interior environment.


# ============================================================================
# Mock Classes
# ============================================================================


class MockBuildingLevel:
	## Saturation effect constants (must match building_level.gd).
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
	var exit_zone_position: Vector2 = Vector2(120, 1250)
	var exit_zone_width: float = 60.0
	var exit_zone_height: float = 100.0

	## Track state changes.
	var exit_zone_activated: bool = false

	## Level name for identification.
	var level_name: String = "BuildingLevel"

	## Building dimensions (~2400x2000 pixels).
	var map_width: int = 2400
	var map_height: int = 2000

	## Default enemy count for building level.
	var default_enemy_count: int = 10

	## Debug mode flag.
	var _debug_mode: bool = false

	## Initialize with default enemies.
	func initialize() -> void:
		_enemies.clear()
		for i in range(default_enemy_count):
			_enemies.append("Enemy%d" % (i + 1))
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

var level: MockBuildingLevel


func before_each() -> void:
	level = MockBuildingLevel.new()


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
	assert_eq(level.exit_zone_position, Vector2(120, 1250),
		"Building level exit zone should be at (120, 1250)")


func test_exit_zone_dimensions() -> void:
	assert_eq(level.exit_zone_width, 60.0,
		"Exit zone width should be 60.0")
	assert_eq(level.exit_zone_height, 100.0,
		"Exit zone height should be 100.0")


# ============================================================================
# Level Initialization Tests
# ============================================================================


func test_default_enemy_count() -> void:
	assert_eq(level.default_enemy_count, 10,
		"Building level should have 10 enemies by default")


func test_level_starts_not_cleared() -> void:
	level.initialize()
	assert_false(level._level_cleared,
		"Level should not be cleared at start")
	assert_false(level._level_completed,
		"Level should not be completed at start")


func test_enemy_count_initialized_correctly() -> void:
	level.initialize()
	assert_eq(level._initial_enemy_count, 10,
		"Initial enemy count should be 10")
	assert_eq(level._current_enemy_count, 10,
		"Current enemy count should be 10 at start")


func test_level_cleared_when_all_enemies_dead() -> void:
	level.initialize()
	for i in range(9):
		level.on_enemy_died()
	assert_false(level._level_cleared, "Not cleared with 1 enemy remaining")
	level.on_enemy_died()
	assert_true(level._level_cleared, "Level should be cleared when all 10 enemies dead")
	assert_true(level.exit_zone_activated, "Exit zone should activate on clear")


func test_player_exit_completes_level() -> void:
	level.initialize()
	for i in range(10):
		level.on_enemy_died()
	level.on_player_reached_exit()
	assert_true(level._level_completed,
		"Level should complete when player reaches exit after clearing")


func test_player_exit_blocked_before_clear() -> void:
	level.initialize()
	level.on_player_reached_exit()
	assert_false(level._level_completed,
		"Level should not complete if enemies remain")


func test_debug_mode_default_off() -> void:
	assert_false(level._debug_mode,
		"Debug mode should be off by default")


func test_map_dimensions() -> void:
	assert_eq(level.map_width, 2400, "Building map width should be 2400")
	assert_eq(level.map_height, 2000, "Building map height should be 2000")


func test_building_level_uses_shared_weapon_hints_component() -> void:
	var script := load("res://scripts/levels/building_level.gd") as GDScript
	assert_not_null(script, "Building level script should load")

	var source := script.source_code
	assert_string_contains(source, "func _setup_weapon_hints() -> void:",
		"Building level should define weapon hints setup for issue #1810")
	assert_string_contains(source, "load(\"res://scripts/components/weapon_hints_component.gd\")",
		"Building level should load the shared weapon hints component")
	assert_string_contains(source, "_weapon_hints_component.setup(_player, canvas_layer)",
		"Building level should initialize the shared weapon hints component with player and CanvasLayer")
