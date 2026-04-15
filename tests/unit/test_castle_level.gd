extends GutTest
## Unit tests for castle_level.gd level script.
##
## Tests saturation constants, exit zone configuration, and level initialization
## for the outdoor castle fortress environment spanning 3 viewports.


# ============================================================================
# Mock Classes
# ============================================================================


class MockCastleLevel:
	## Saturation effect constants (must match castle_level.gd).
	const SATURATION_DURATION: float = 0.15
	const SATURATION_INTENSITY: float = 0.25

	## Level state variables.
	var _initial_enemy_count: int = 0
	var _current_enemy_count: int = 0
	var _level_cleared: bool = false
	var _level_completed: bool = false
	var _game_over_shown: bool = false
	var _enemies: Array = []

	## Exit zone configuration (castle uses different dimensions than standard).
	var exit_zone_position: Vector2 = Vector2(3000, 2385)
	var exit_zone_width: float = 200.0
	var exit_zone_height: float = 70.0

	## Track state changes.
	var exit_zone_activated: bool = false

	## Level name for identification.
	var level_name: String = "CastleLevel"

	## Castle dimensions (~6000x2560 pixels, 3 viewports wide).
	var map_width: int = 6000
	var map_height: int = 2560

	## Default enemy count for castle level.
	var default_enemy_count: int = 13

	## Initialize with default enemies.
	func initialize() -> void:
		_enemies.clear()
		for i in range(default_enemy_count):
			_enemies.append("CastleEnemy%d" % (i + 1))
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


var level: MockCastleLevel


func before_each() -> void:
	level = MockCastleLevel.new()


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
	assert_eq(level.exit_zone_position, Vector2(3000, 2385),
		"Castle level exit zone should be at (3000, 2385) — bottom of castle")


func test_exit_zone_dimensions() -> void:
	assert_eq(level.exit_zone_width, 200.0,
		"Castle exit zone width should be 200.0 (wider than standard 60)")
	assert_eq(level.exit_zone_height, 70.0,
		"Castle exit zone height should be 70.0 (shorter than standard 100)")


func test_exit_zone_differs_from_standard() -> void:
	# Castle uses non-standard exit zone dimensions
	assert_ne(level.exit_zone_width, 60.0,
		"Castle exit zone width should differ from standard 60.0")
	assert_ne(level.exit_zone_height, 100.0,
		"Castle exit zone height should differ from standard 100.0")


# ============================================================================
# Level Initialization Tests
# ============================================================================


func test_default_enemy_count() -> void:
	assert_eq(level.default_enemy_count, 13,
		"Castle level should have 13 enemies by default")


func test_level_starts_not_cleared() -> void:
	level.initialize()
	assert_false(level._level_cleared,
		"Level should not be cleared at start")
	assert_false(level._level_completed,
		"Level should not be completed at start")


func test_level_cleared_when_all_enemies_dead() -> void:
	level.initialize()
	for i in range(12):
		level.on_enemy_died()
	assert_false(level._level_cleared, "Not cleared with 1 enemy remaining")
	level.on_enemy_died()
	assert_true(level._level_cleared, "Level should be cleared when all 13 enemies dead")
	assert_true(level.exit_zone_activated, "Exit zone should activate on clear")


func test_player_exit_completes_level() -> void:
	level.initialize()
	for i in range(13):
		level.on_enemy_died()
	level.on_player_reached_exit()
	assert_true(level._level_completed,
		"Level should complete when player reaches exit after clearing")


func test_map_dimensions() -> void:
	assert_eq(level.map_width, 6000, "Castle map width should be 6000 (3 viewports)")
	assert_eq(level.map_height, 2560, "Castle map height should be 2560")


func test_castle_scene_has_outer_wall_collider() -> void:
	var scene := load("res://scenes/levels/CastleLevel.tscn") as PackedScene
	assert_not_null(scene, "CastleLevel scene should load")

	var instance := scene.instantiate()
	add_child_autofree(instance)

	var outer_wall := instance.get_node_or_null("Environment/CastleWalls/WallOvalCollider") as StaticBody2D
	assert_not_null(outer_wall, "Castle outer oval wall must have a StaticBody2D collider")
	assert_eq(outer_wall.collision_layer, 4, "Outer wall collider should be on obstacle layer 4")

	var occluder := outer_wall.get_node_or_null("LightOccluder2D") as LightOccluder2D
	assert_not_null(occluder, "Outer wall collider should also occlude flash/light effects")

	var collision_shape_count := 0
	for child in outer_wall.get_children():
		if child is CollisionShape2D:
			collision_shape_count += 1

	assert_ge(collision_shape_count, 16,
		"Outer wall should be approximated by multiple collision segments so it blocks movement and LOS")


func test_castle_outer_wall_occluder_uses_closed_polygon() -> void:
	var scene := load("res://scenes/levels/CastleLevel.tscn") as PackedScene
	assert_not_null(scene, "CastleLevel scene should load")

	var instance := scene.instantiate()
	add_child_autofree(instance)

	var outer_wall := instance.get_node_or_null("Environment/CastleWalls/WallOvalCollider") as StaticBody2D
	assert_not_null(outer_wall, "Castle outer wall collider must exist")

	var occluder := outer_wall.get_node_or_null("LightOccluder2D") as LightOccluder2D
	assert_not_null(occluder, "Castle outer wall must expose an occluder")
	assert_not_null(occluder.occluder, "Castle outer wall occluder polygon must be assigned")

	var polygon := occluder.occluder.polygon
	assert_gt(polygon.size(), 3, "Outer wall occluder polygon should have enough points")
	assert_eq(polygon[0], polygon[polygon.size() - 1],
		"Outer wall occluder polygon should be explicitly closed so shadows do not leak through the seam")


func test_castle_scene_key_obstacles_have_light_occluders() -> void:
	var scene := load("res://scenes/levels/CastleLevel.tscn") as PackedScene
	assert_not_null(scene, "CastleLevel scene should load")

	var instance := scene.instantiate()
	add_child_autofree(instance)

	var obstacle_paths := [
		"Environment/CenterTower",
		"Environment/InnerTower",
		"Environment/CastleBuilding/LeftWingTopWall",
		"Environment/CastleBuilding/RightWingTopWall",
		"Environment/CastleBuilding/CenterSouthWallLeft",
		"Environment/Cover/CoverLowerLeft1",
		"Environment/Cover/CoverCenterRight2",
		"Environment/Cover/CoverBottom3",
	]

	for obstacle_path in obstacle_paths:
		var obstacle := instance.get_node_or_null(obstacle_path) as CollisionObject2D
		assert_not_null(obstacle, "Castle obstacle should exist: %s" % obstacle_path)

		var occluder := obstacle.get_node_or_null("LightOccluder2D") as LightOccluder2D
		assert_not_null(occluder, "Castle obstacle should cast 2D shadows: %s" % obstacle_path)
		assert_not_null(occluder.occluder, "Castle obstacle occluder polygon should be assigned: %s" % obstacle_path)
