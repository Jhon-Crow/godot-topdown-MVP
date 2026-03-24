extends GutTest
## Unit tests for LevelData (Issue #1442 - Level Editor).
##
## Tests JSON serialization/deserialization, data integrity,
## grid snapping, and edge cases for the level data model.


# ============================================================================
# LevelData Construction Tests
# ============================================================================


func test_new_level_data_has_default_name() -> void:
	var data := LevelData.new()
	assert_eq(data.level_name, "Untitled", "New level should have 'Untitled' as default name")


func test_new_level_data_has_default_author() -> void:
	var data := LevelData.new()
	assert_eq(data.author, "Player", "New level should have 'Player' as default author")


func test_new_level_data_has_default_map_size() -> void:
	var data := LevelData.new()
	assert_eq(data.map_width, 2400, "Default map width should be 2400")
	assert_eq(data.map_height, 2000, "Default map height should be 2000")


func test_new_level_data_has_default_player_spawn() -> void:
	var data := LevelData.new()
	assert_eq(data.player_spawn, Vector2(200, 200), "Default player spawn should be (200, 200)")


func test_new_level_data_has_empty_walls() -> void:
	var data := LevelData.new()
	assert_eq(data.walls.size(), 0, "New level should have no walls")


func test_new_level_data_has_empty_enemies() -> void:
	var data := LevelData.new()
	assert_eq(data.enemies.size(), 0, "New level should have no enemies")


func test_new_level_data_has_empty_cover() -> void:
	var data := LevelData.new()
	assert_eq(data.cover_objects.size(), 0, "New level should have no cover objects")


# ============================================================================
# JSON Serialization Tests
# ============================================================================


func test_to_dict_contains_format_version() -> void:
	var data := LevelData.new()
	var dict: Dictionary = data.to_dict()
	assert_true(dict.has("format_version"), "Serialized dict should have format_version")
	assert_eq(dict["format_version"], LevelData.FORMAT_VERSION, "Format version should match constant")


func test_to_dict_contains_level_name() -> void:
	var data := LevelData.new()
	data.level_name = "Test Level"
	var dict: Dictionary = data.to_dict()
	assert_eq(dict["level_name"], "Test Level", "Serialized dict should contain level name")


func test_to_dict_contains_player_spawn() -> void:
	var data := LevelData.new()
	data.player_spawn = Vector2(500, 300)
	var dict: Dictionary = data.to_dict()
	assert_eq(dict["player_spawn"]["x"], 500.0, "Player spawn x should be serialized")
	assert_eq(dict["player_spawn"]["y"], 300.0, "Player spawn y should be serialized")


func test_to_dict_contains_walls() -> void:
	var data := LevelData.new()
	data.walls.append({"x": 100.0, "y": 200.0, "w": 300.0, "h": 32.0})
	var dict: Dictionary = data.to_dict()
	assert_eq(dict["walls"].size(), 1, "Should serialize 1 wall")
	assert_eq(dict["walls"][0]["x"], 100.0, "Wall x should be preserved")


func test_to_dict_contains_enemies() -> void:
	var data := LevelData.new()
	data.enemies.append({"x": 400.0, "y": 500.0, "weapon": "m16", "patrol": true})
	var dict: Dictionary = data.to_dict()
	assert_eq(dict["enemies"].size(), 1, "Should serialize 1 enemy")
	assert_eq(dict["enemies"][0]["weapon"], "m16", "Enemy weapon should be preserved")


func test_to_dict_contains_cover_objects() -> void:
	var data := LevelData.new()
	data.cover_objects.append({"x": 300.0, "y": 400.0, "w": 64.0, "h": 64.0, "type": "crate"})
	var dict: Dictionary = data.to_dict()
	assert_eq(dict["cover_objects"].size(), 1, "Should serialize 1 cover object")
	assert_eq(dict["cover_objects"][0]["type"], "crate", "Cover type should be preserved")


func test_to_json_produces_valid_string() -> void:
	var data := LevelData.new()
	data.level_name = "JSON Test"
	var json_str: String = data.to_json()
	assert_true(json_str.length() > 0, "JSON string should not be empty")
	assert_true(json_str.contains("JSON Test"), "JSON should contain level name")


# ============================================================================
# JSON Deserialization Tests
# ============================================================================


func test_from_dict_loads_level_name() -> void:
	var data := LevelData.new()
	data.level_name = "Original"
	var dict: Dictionary = data.to_dict()

	var loaded := LevelData.new()
	var success: bool = loaded.from_dict(dict)
	assert_true(success, "from_dict should succeed")
	assert_eq(loaded.level_name, "Original", "Level name should be loaded")


func test_from_dict_loads_map_size() -> void:
	var data := LevelData.new()
	data.map_width = 3000
	data.map_height = 2500
	var dict: Dictionary = data.to_dict()

	var loaded := LevelData.new()
	loaded.from_dict(dict)
	assert_eq(loaded.map_width, 3000, "Map width should be loaded")
	assert_eq(loaded.map_height, 2500, "Map height should be loaded")


func test_from_dict_loads_player_spawn() -> void:
	var data := LevelData.new()
	data.player_spawn = Vector2(800, 600)
	var dict: Dictionary = data.to_dict()

	var loaded := LevelData.new()
	loaded.from_dict(dict)
	assert_eq(loaded.player_spawn, Vector2(800, 600), "Player spawn should be loaded")


func test_from_dict_loads_walls() -> void:
	var data := LevelData.new()
	data.walls.append({"x": 100.0, "y": 200.0, "w": 300.0, "h": 32.0})
	data.walls.append({"x": 500.0, "y": 600.0, "w": 32.0, "h": 200.0})
	var dict: Dictionary = data.to_dict()

	var loaded := LevelData.new()
	loaded.from_dict(dict)
	assert_eq(loaded.walls.size(), 2, "Should load 2 walls")


func test_from_dict_loads_enemies() -> void:
	var data := LevelData.new()
	data.enemies.append({"x": 400.0, "y": 500.0, "weapon": "shotgun", "patrol": false})
	var dict: Dictionary = data.to_dict()

	var loaded := LevelData.new()
	loaded.from_dict(dict)
	assert_eq(loaded.enemies.size(), 1, "Should load 1 enemy")
	assert_eq(loaded.enemies[0]["weapon"], "shotgun", "Enemy weapon should be loaded")


func test_from_dict_loads_cover_objects() -> void:
	var data := LevelData.new()
	data.cover_objects.append({"x": 300.0, "y": 400.0, "w": 96.0, "h": 32.0, "type": "desk"})
	var dict: Dictionary = data.to_dict()

	var loaded := LevelData.new()
	loaded.from_dict(dict)
	assert_eq(loaded.cover_objects.size(), 1, "Should load 1 cover object")
	assert_eq(loaded.cover_objects[0]["type"], "desk", "Cover type should be loaded")


func test_from_dict_rejects_missing_format_version() -> void:
	var bad_dict: Dictionary = {"level_name": "Bad"}
	var data := LevelData.new()
	var success: bool = data.from_dict(bad_dict)
	assert_false(success, "from_dict should reject dict without format_version")


func test_from_dict_rejects_invalid_format_version() -> void:
	var bad_dict: Dictionary = {"format_version": 999}
	var data := LevelData.new()
	var success: bool = data.from_dict(bad_dict)
	assert_false(success, "from_dict should reject dict with future format version")


func test_from_json_roundtrip() -> void:
	var original := LevelData.new()
	original.level_name = "Roundtrip Test"
	original.author = "TestRunner"
	original.description = "A test level for roundtrip serialization"
	original.map_width = 3200
	original.map_height = 2400
	original.player_spawn = Vector2(640, 480)
	original.walls.append({"x": 100.0, "y": 200.0, "w": 500.0, "h": 32.0})
	original.enemies.append({"x": 800.0, "y": 600.0, "weapon": "m16", "patrol": true})
	original.cover_objects.append({"x": 400.0, "y": 300.0, "w": 64.0, "h": 64.0, "type": "crate"})

	var json_str: String = original.to_json()
	var loaded := LevelData.new()
	var success: bool = loaded.from_json(json_str)

	assert_true(success, "from_json should succeed with valid JSON")
	assert_eq(loaded.level_name, "Roundtrip Test", "Level name should survive roundtrip")
	assert_eq(loaded.author, "TestRunner", "Author should survive roundtrip")
	assert_eq(loaded.description, "A test level for roundtrip serialization", "Description should survive roundtrip")
	assert_eq(loaded.map_width, 3200, "Map width should survive roundtrip")
	assert_eq(loaded.map_height, 2400, "Map height should survive roundtrip")
	assert_eq(loaded.player_spawn, Vector2(640, 480), "Player spawn should survive roundtrip")
	assert_eq(loaded.walls.size(), 1, "Walls should survive roundtrip")
	assert_eq(loaded.enemies.size(), 1, "Enemies should survive roundtrip")
	assert_eq(loaded.cover_objects.size(), 1, "Cover objects should survive roundtrip")


func test_from_json_rejects_invalid_json() -> void:
	var data := LevelData.new()
	var success: bool = data.from_json("not valid json {{{")
	assert_false(success, "from_json should reject invalid JSON")


func test_from_json_rejects_non_dict_json() -> void:
	var data := LevelData.new()
	var success: bool = data.from_json("[1, 2, 3]")
	assert_false(success, "from_json should reject JSON that is not a dictionary")


# ============================================================================
# Grid Snapping Tests
# ============================================================================


func test_snap_to_grid_exact_position() -> void:
	var pos := Vector2(128, 256)
	var snapped := LevelData.snap_to_grid(pos)
	assert_eq(snapped, Vector2(128, 256), "Exact grid position should not change")


func test_snap_to_grid_rounds_to_nearest() -> void:
	var pos := Vector2(140, 250)
	var snapped := LevelData.snap_to_grid(pos)
	assert_eq(snapped, Vector2(128, 256), "Position should snap to nearest grid cell")


func test_snap_to_grid_zero() -> void:
	var pos := Vector2(0, 0)
	var snapped := LevelData.snap_to_grid(pos)
	assert_eq(snapped, Vector2(0, 0), "Zero position should remain at zero")


func test_snap_to_grid_small_offset() -> void:
	var pos := Vector2(15, 15)
	var snapped := LevelData.snap_to_grid(pos)
	assert_eq(snapped, Vector2(0, 0), "Small offset should snap to (0, 0)")


# ============================================================================
# Color Serialization Tests
# ============================================================================


func test_floor_color_survives_roundtrip() -> void:
	var data := LevelData.new()
	data.floor_color = Color(0.5, 0.6, 0.7, 1.0)
	var dict: Dictionary = data.to_dict()

	var loaded := LevelData.new()
	loaded.from_dict(dict)
	assert_almost_eq(loaded.floor_color.r, 0.5, 0.01, "Floor color red should survive roundtrip")
	assert_almost_eq(loaded.floor_color.g, 0.6, 0.01, "Floor color green should survive roundtrip")
	assert_almost_eq(loaded.floor_color.b, 0.7, 0.01, "Floor color blue should survive roundtrip")


func test_wall_color_survives_roundtrip() -> void:
	var data := LevelData.new()
	data.wall_color = Color(0.8, 0.3, 0.1, 1.0)
	var dict: Dictionary = data.to_dict()

	var loaded := LevelData.new()
	loaded.from_dict(dict)
	assert_almost_eq(loaded.wall_color.r, 0.8, 0.01, "Wall color red should survive roundtrip")
	assert_almost_eq(loaded.wall_color.g, 0.3, 0.01, "Wall color green should survive roundtrip")
	assert_almost_eq(loaded.wall_color.b, 0.1, 0.01, "Wall color blue should survive roundtrip")


# ============================================================================
# Constants Tests
# ============================================================================


func test_format_version_is_positive() -> void:
	assert_gt(LevelData.FORMAT_VERSION, 0, "FORMAT_VERSION should be positive")


func test_cell_size_is_positive() -> void:
	assert_gt(LevelData.CELL_SIZE, 0, "CELL_SIZE should be positive")


func test_cell_size_is_power_of_two() -> void:
	var cell := LevelData.CELL_SIZE
	# 32 is 2^5
	assert_eq(cell & (cell - 1), 0, "CELL_SIZE should be a power of 2")
