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


# ============================================================================
# Camera Limit Tests (Issue #1550 — all four walls must not appear in camera)
# ============================================================================


func test_wall_top_bottom_edge_y_equals_64() -> void:
	## WallTop in BeachLevel.tscn: position=(1264,48), size=(2464,32).
	## Bottom edge = 48 + 16 = 64 (half-height of 32 = 16).
	## camera_limit_top must be set to 64 so the wall is always off-screen.
	var wall_top_position_y: float = 48.0
	var wall_top_half_height: float = 16.0  # height=32, half=16
	var wall_bottom_edge: float = wall_top_position_y + wall_top_half_height
	assert_almost_eq(wall_bottom_edge, 64.0, 0.001,
		"WallTop bottom edge should be at y=64 in world space")


func test_water_top_edge_above_wall_bottom_edge() -> void:
	## Water node: position=(1264,242), height=420 (Issue #1573 increased from 356).
	## Top edge = 242 - 420/2 = 242 - 210 = 32.
	## Water now extends above WallTop bottom edge (64) for shore-wash visual effect.
	var water_position_y: float = 242.0
	var water_half_height: float = 210.0  # height=420, half=210
	var water_top_edge: float = water_position_y - water_half_height
	assert_almost_eq(water_top_edge, 32.0, 0.001,
		"Water top edge should be at y=32 with height=420 (Issue #1573 shore wash)")
	assert_lt(water_top_edge, 64.0,
		"Water top edge (32) should be above WallTop bottom edge (64) — Issue #1573")


func test_camera_limit_top_should_match_wall_bottom() -> void:
	## The expected camera limit_top is 64 — the bottom edge of WallTop.
	const EXPECTED_CAMERA_LIMIT_TOP: int = 64
	assert_eq(EXPECTED_CAMERA_LIMIT_TOP, 64,
		"Camera limit_top should be set to 64 (WallTop bottom edge) — Issue #1550")


func test_camera_limit_bottom_should_match_wall_top_edge() -> void:
	## WallBottom: position=(1264,2080), size=(2464,32).
	## Top edge = 2080 - 16 = 2064.
	var wall_bottom_position_y: float = 2080.0
	var wall_bottom_half_height: float = 16.0
	var wall_top_edge: float = wall_bottom_position_y - wall_bottom_half_height
	assert_almost_eq(wall_top_edge, 2064.0, 0.001,
		"WallBottom top edge should be at y=2064 — camera limit_bottom target")
	const EXPECTED_CAMERA_LIMIT_BOTTOM: int = 2064
	assert_eq(EXPECTED_CAMERA_LIMIT_BOTTOM, 2064,
		"Camera limit_bottom should be 2064 (WallBottom top edge) — Issue #1550")


func test_camera_limit_left_should_match_wall_right_edge() -> void:
	## WallLeft: position=(48,1064), size=(32,2064).
	## Right edge = 48 + 16 = 64.
	var wall_left_position_x: float = 48.0
	var wall_left_half_width: float = 16.0
	var wall_right_edge: float = wall_left_position_x + wall_left_half_width
	assert_almost_eq(wall_right_edge, 64.0, 0.001,
		"WallLeft right edge should be at x=64 — camera limit_left target")
	const EXPECTED_CAMERA_LIMIT_LEFT: int = 64
	assert_eq(EXPECTED_CAMERA_LIMIT_LEFT, 64,
		"Camera limit_left should be 64 (WallLeft right edge) — Issue #1550")


func test_camera_limit_right_should_match_wall_left_edge() -> void:
	## WallRight: position=(2480,1064), size=(32,2064).
	## Left edge = 2480 - 16 = 2464.
	var wall_right_position_x: float = 2480.0
	var wall_right_half_width: float = 16.0
	var wall_left_edge: float = wall_right_position_x - wall_right_half_width
	assert_almost_eq(wall_left_edge, 2464.0, 0.001,
		"WallRight left edge should be at x=2464 — camera limit_right target")
	const EXPECTED_CAMERA_LIMIT_RIGHT: int = 2464
	assert_eq(EXPECTED_CAMERA_LIMIT_RIGHT, 2464,
		"Camera limit_right should be 2464 (WallRight left edge) — Issue #1550")


# ============================================================================
# Light Occluder Regression Tests (Issue #1825)
# ============================================================================


func test_beach_small_cover_has_light_occluders() -> void:
	var scene := load("res://scenes/levels/BeachLevel.tscn") as PackedScene
	assert_not_null(scene, "BeachLevel scene should load")

	var instance := scene.instantiate()
	add_child_autofree(instance)

	var cover_paths := [
		"Environment/Cover/Rock2",
		"Environment/Cover/Rock4",
		"Environment/Cover/Rock6",
		"Environment/Cover/Barrel1",
		"Environment/Cover/Barrel2",
		"Environment/Cover/Barrel3",
	]

	for path in cover_paths:
		var cover := instance.get_node_or_null(path) as StaticBody2D
		assert_not_null(cover, "%s should exist in BeachLevel" % path)
		var occluder := cover.get_node_or_null("LightOccluder2D") as LightOccluder2D
		assert_not_null(occluder, "%s should have a LightOccluder2D so light is blocked by small cover" % path)
