extends GutTest
## Unit tests for LevelData serialization and new object types (Issue #1452).
##
## Tests format v2 features: trees, lights, decorations, plus backward
## compatibility with v1 levels and JSON roundtrip integrity.


# ============================================================================
# Basic LevelData Tests
# ============================================================================


func test_new_level_data_has_defaults() -> void:
	var data := LevelData.new()
	assert_eq(data.level_name, "Untitled")
	assert_eq(data.map_width, 2400)
	assert_eq(data.map_height, 2000)
	assert_eq(data.player_spawn, Vector2(200, 200))
	assert_eq(data.walls.size(), 0)
	assert_eq(data.enemies.size(), 0)
	assert_eq(data.cover_objects.size(), 0)
	assert_eq(data.trees.size(), 0)
	assert_eq(data.lights.size(), 0)
	assert_eq(data.decorations.size(), 0)


func test_format_version_is_2() -> void:
	assert_eq(LevelData.FORMAT_VERSION, 2)


func test_grid_snap() -> void:
	var snapped := LevelData.snap_to_grid(Vector2(50, 70))
	assert_eq(snapped, Vector2(64, 64))

	var snapped2 := LevelData.snap_to_grid(Vector2(16, 16))
	assert_eq(snapped2, Vector2(32, 32))

	var snapped3 := LevelData.snap_to_grid(Vector2(0, 0))
	assert_eq(snapped3, Vector2(0, 0))


# ============================================================================
# Serialization Tests
# ============================================================================


func test_to_dict_includes_all_fields() -> void:
	var data := LevelData.new()
	data.level_name = "Test Level"
	data.author = "Tester"
	var dict: Dictionary = data.to_dict()

	assert_eq(dict["format_version"], 2)
	assert_eq(dict["level_name"], "Test Level")
	assert_eq(dict["author"], "Tester")
	assert_has(dict, "walls")
	assert_has(dict, "enemies")
	assert_has(dict, "cover_objects")
	assert_has(dict, "trees")
	assert_has(dict, "lights")
	assert_has(dict, "decorations")
	assert_has(dict, "floor_color")
	assert_has(dict, "wall_color")
	assert_has(dict, "player_spawn")


func test_roundtrip_empty_level() -> void:
	var data := LevelData.new()
	data.level_name = "Empty"
	var json_str: String = data.to_json()

	var loaded := LevelData.new()
	var ok: bool = loaded.from_json(json_str)
	assert_true(ok)
	assert_eq(loaded.level_name, "Empty")
	assert_eq(loaded.trees.size(), 0)
	assert_eq(loaded.lights.size(), 0)
	assert_eq(loaded.decorations.size(), 0)


func test_roundtrip_with_walls() -> void:
	var data := LevelData.new()
	data.walls.append({"x": 100.0, "y": 200.0, "w": 300.0, "h": 32.0})
	var json_str: String = data.to_json()

	var loaded := LevelData.new()
	assert_true(loaded.from_json(json_str))
	assert_eq(loaded.walls.size(), 1)
	assert_eq(loaded.walls[0]["x"], 100.0)
	assert_eq(loaded.walls[0]["w"], 300.0)


func test_roundtrip_with_enemies() -> void:
	var data := LevelData.new()
	data.enemies.append({"x": 400.0, "y": 500.0, "weapon": "shotgun", "patrol": true})
	var json_str: String = data.to_json()

	var loaded := LevelData.new()
	assert_true(loaded.from_json(json_str))
	assert_eq(loaded.enemies.size(), 1)
	assert_eq(loaded.enemies[0]["weapon"], "shotgun")
	assert_eq(loaded.enemies[0]["patrol"], true)


# ============================================================================
# Tree Serialization Tests
# ============================================================================


func test_roundtrip_with_trees() -> void:
	var data := LevelData.new()
	data.trees.append({"x": 300.0, "y": 400.0, "type": "oak"})
	data.trees.append({"x": 500.0, "y": 600.0, "type": "pine"})
	data.trees.append({"x": 700.0, "y": 200.0, "type": "birch"})
	data.trees.append({"x": 900.0, "y": 100.0, "type": "dead"})
	var json_str: String = data.to_json()

	var loaded := LevelData.new()
	assert_true(loaded.from_json(json_str))
	assert_eq(loaded.trees.size(), 4)
	assert_eq(loaded.trees[0]["type"], "oak")
	assert_eq(loaded.trees[1]["type"], "pine")
	assert_eq(loaded.trees[2]["type"], "birch")
	assert_eq(loaded.trees[3]["type"], "dead")
	assert_eq(loaded.trees[0]["x"], 300.0)
	assert_eq(loaded.trees[0]["y"], 400.0)


func test_tree_position_preserved() -> void:
	var data := LevelData.new()
	data.trees.append({"x": 123.5, "y": 456.7, "type": "oak"})
	var json_str: String = data.to_json()

	var loaded := LevelData.new()
	assert_true(loaded.from_json(json_str))
	assert_almost_eq(loaded.trees[0]["x"], 123.5, 0.01)
	assert_almost_eq(loaded.trees[0]["y"], 456.7, 0.01)


# ============================================================================
# Light Serialization Tests
# ============================================================================


func test_roundtrip_with_lights() -> void:
	var data := LevelData.new()
	data.lights.append({
		"x": 200.0, "y": 300.0,
		"type": "street_lamp",
		"color": {"r": 1.0, "g": 0.95, "b": 0.8, "a": 1.0},
		"energy": 1.5,
		"radius": 256.0,
	})
	data.lights.append({
		"x": 500.0, "y": 400.0,
		"type": "campfire",
		"color": {"r": 1.0, "g": 0.6, "b": 0.2, "a": 1.0},
		"energy": 2.0,
		"radius": 192.0,
	})
	var json_str: String = data.to_json()

	var loaded := LevelData.new()
	assert_true(loaded.from_json(json_str))
	assert_eq(loaded.lights.size(), 2)
	assert_eq(loaded.lights[0]["type"], "street_lamp")
	assert_eq(loaded.lights[1]["type"], "campfire")
	assert_eq(loaded.lights[0]["energy"], 1.5)
	assert_eq(loaded.lights[1]["radius"], 192.0)


func test_light_color_preserved() -> void:
	var data := LevelData.new()
	data.lights.append({
		"x": 100.0, "y": 100.0,
		"type": "neon",
		"color": {"r": 0.9, "g": 0.2, "b": 0.8, "a": 1.0},
		"energy": 2.5,
		"radius": 200.0,
	})
	var json_str: String = data.to_json()

	var loaded := LevelData.new()
	assert_true(loaded.from_json(json_str))
	var color_data: Dictionary = loaded.lights[0]["color"]
	assert_almost_eq(color_data["r"], 0.9, 0.01)
	assert_almost_eq(color_data["g"], 0.2, 0.01)
	assert_almost_eq(color_data["b"], 0.8, 0.01)


func test_all_light_types_roundtrip() -> void:
	var data := LevelData.new()
	var types: Array[String] = ["street_lamp", "campfire", "spotlight", "ambient", "neon"]
	for i in range(types.size()):
		data.lights.append({
			"x": float(i * 100), "y": 100.0,
			"type": types[i],
			"color": {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0},
			"energy": 1.0,
			"radius": 200.0,
		})

	var loaded := LevelData.new()
	assert_true(loaded.from_json(data.to_json()))
	assert_eq(loaded.lights.size(), 5)
	for i in range(types.size()):
		assert_eq(loaded.lights[i]["type"], types[i])


# ============================================================================
# Decoration Serialization Tests
# ============================================================================


func test_roundtrip_with_decorations() -> void:
	var data := LevelData.new()
	data.decorations.append({"x": 300.0, "y": 400.0, "type": "rock"})
	data.decorations.append({"x": 500.0, "y": 200.0, "type": "bush"})
	data.decorations.append({"x": 700.0, "y": 100.0, "type": "stump"})
	var json_str: String = data.to_json()

	var loaded := LevelData.new()
	assert_true(loaded.from_json(json_str))
	assert_eq(loaded.decorations.size(), 3)
	assert_eq(loaded.decorations[0]["type"], "rock")
	assert_eq(loaded.decorations[1]["type"], "bush")
	assert_eq(loaded.decorations[2]["type"], "stump")


func test_all_decoration_types_roundtrip() -> void:
	var data := LevelData.new()
	var types: Array[String] = ["rock", "stump", "log", "bush", "crate_small", "trash"]
	for i in range(types.size()):
		data.decorations.append({
			"x": float(i * 100), "y": 100.0,
			"type": types[i],
		})

	var loaded := LevelData.new()
	assert_true(loaded.from_json(data.to_json()))
	assert_eq(loaded.decorations.size(), 6)
	for i in range(types.size()):
		assert_eq(loaded.decorations[i]["type"], types[i])


# ============================================================================
# Backward Compatibility Tests
# ============================================================================


func test_v1_level_loads_with_empty_new_fields() -> void:
	# Simulate a v1 level (no trees, lights, decorations fields)
	var v1_dict: Dictionary = {
		"format_version": 1,
		"level_name": "Old Level",
		"author": "OldPlayer",
		"description": "",
		"map_width": 2400,
		"map_height": 2000,
		"player_spawn": {"x": 200, "y": 200},
		"floor_color": {"r": 0.25, "g": 0.25, "b": 0.28, "a": 1.0},
		"wall_color": {"r": 0.35, "g": 0.35, "b": 0.4, "a": 1.0},
		"walls": [{"x": 100, "y": 200, "w": 300, "h": 32}],
		"enemies": [],
		"cover_objects": [],
	}

	var data := LevelData.new()
	assert_true(data.from_dict(v1_dict))
	assert_eq(data.level_name, "Old Level")
	assert_eq(data.walls.size(), 1)
	assert_eq(data.trees.size(), 0, "v1 level should have empty trees")
	assert_eq(data.lights.size(), 0, "v1 level should have empty lights")
	assert_eq(data.decorations.size(), 0, "v1 level should have empty decorations")


func test_invalid_format_version_rejected() -> void:
	var data := LevelData.new()
	assert_false(data.from_dict({"format_version": 0}))
	assert_false(data.from_dict({"format_version": 99}))
	assert_false(data.from_dict({}))


func test_invalid_json_rejected() -> void:
	var data := LevelData.new()
	assert_false(data.from_json("not json"))
	assert_false(data.from_json(""))
	assert_false(data.from_json("[]"))


# ============================================================================
# Full Level Roundtrip Test
# ============================================================================


func test_full_level_roundtrip() -> void:
	var data := LevelData.new()
	data.level_name = "Full Test"
	data.author = "TestBot"
	data.description = "A level with all object types"
	data.map_width = 3200
	data.map_height = 2400
	data.player_spawn = Vector2(150, 150)
	data.floor_color = Color(0.3, 0.3, 0.35, 1.0)
	data.wall_color = Color(0.4, 0.4, 0.45, 1.0)
	data.walls.append({"x": 100.0, "y": 100.0, "w": 200.0, "h": 32.0})
	data.enemies.append({"x": 500.0, "y": 300.0, "weapon": "m16", "patrol": false})
	data.cover_objects.append({"x": 400.0, "y": 200.0, "w": 64.0, "h": 64.0, "type": "crate"})
	data.trees.append({"x": 800.0, "y": 600.0, "type": "oak"})
	data.trees.append({"x": 1000.0, "y": 400.0, "type": "dead"})
	data.lights.append({
		"x": 600.0, "y": 300.0, "type": "campfire",
		"color": {"r": 1.0, "g": 0.6, "b": 0.2, "a": 1.0},
		"energy": 2.0, "radius": 192.0,
	})
	data.decorations.append({"x": 700.0, "y": 500.0, "type": "rock"})
	data.decorations.append({"x": 900.0, "y": 300.0, "type": "bush"})

	var json_str: String = data.to_json()
	assert_true(json_str.length() > 0)

	var loaded := LevelData.new()
	assert_true(loaded.from_json(json_str))
	assert_eq(loaded.level_name, "Full Test")
	assert_eq(loaded.author, "TestBot")
	assert_eq(loaded.map_width, 3200)
	assert_eq(loaded.map_height, 2400)
	assert_eq(loaded.player_spawn, Vector2(150, 150))
	assert_eq(loaded.walls.size(), 1)
	assert_eq(loaded.enemies.size(), 1)
	assert_eq(loaded.cover_objects.size(), 1)
	assert_eq(loaded.trees.size(), 2)
	assert_eq(loaded.lights.size(), 1)
	assert_eq(loaded.decorations.size(), 2)


# ============================================================================
# Color Serialization Tests
# ============================================================================


func test_floor_color_roundtrip() -> void:
	var data := LevelData.new()
	data.floor_color = Color(0.5, 0.6, 0.7, 0.8)
	var loaded := LevelData.new()
	assert_true(loaded.from_json(data.to_json()))
	assert_almost_eq(loaded.floor_color.r, 0.5, 0.01)
	assert_almost_eq(loaded.floor_color.g, 0.6, 0.01)
	assert_almost_eq(loaded.floor_color.b, 0.7, 0.01)
	assert_almost_eq(loaded.floor_color.a, 0.8, 0.01)


func test_player_spawn_roundtrip() -> void:
	var data := LevelData.new()
	data.player_spawn = Vector2(999, 777)
	var loaded := LevelData.new()
	assert_true(loaded.from_json(data.to_json()))
	assert_eq(loaded.player_spawn, Vector2(999, 777))
