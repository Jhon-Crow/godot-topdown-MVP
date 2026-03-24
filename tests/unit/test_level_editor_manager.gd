extends GutTest
## Unit tests for LevelEditorManager operations.
##
## Tests save/load/export/import/delete functionality and filename sanitization.


# ============================================================================
# Export / Import Tests (no filesystem needed)
# ============================================================================


func test_export_returns_valid_json() -> void:
	var data := LevelData.new()
	data.level_name = "Export Test"
	data.trees.append({"x": 100.0, "y": 200.0, "type": "pine"})

	var json_str: String = data.to_json()
	assert_true(json_str.length() > 0)
	assert_true(json_str.contains("Export Test"))
	assert_true(json_str.contains("pine"))


func test_import_from_valid_json() -> void:
	var json_str := '{"format_version":2,"level_name":"Imported","author":"Imp","description":"","map_width":2400,"map_height":2000,"player_spawn":{"x":200,"y":200},"floor_color":{"r":0.25,"g":0.25,"b":0.28,"a":1},"wall_color":{"r":0.35,"g":0.35,"b":0.4,"a":1},"walls":[],"enemies":[],"cover_objects":[],"trees":[{"x":300,"y":400,"type":"oak"}],"lights":[],"decorations":[]}'

	var data := LevelData.new()
	var ok: bool = data.from_json(json_str)
	assert_true(ok)
	assert_eq(data.level_name, "Imported")
	assert_eq(data.trees.size(), 1)
	assert_eq(data.trees[0]["type"], "oak")


func test_import_from_invalid_json_fails() -> void:
	var data := LevelData.new()
	assert_false(data.from_json("not json at all"))
	assert_false(data.from_json(""))
	assert_false(data.from_json("42"))


func test_import_from_missing_version_fails() -> void:
	var data := LevelData.new()
	assert_false(data.from_json('{"level_name":"No Version"}'))


func test_export_import_roundtrip() -> void:
	var original := LevelData.new()
	original.level_name = "Roundtrip"
	original.trees.append({"x": 100.0, "y": 200.0, "type": "birch"})
	original.lights.append({
		"x": 300.0, "y": 400.0, "type": "neon",
		"color": {"r": 0.9, "g": 0.2, "b": 0.8, "a": 1.0},
		"energy": 2.5, "radius": 200.0,
	})
	original.decorations.append({"x": 500.0, "y": 600.0, "type": "log"})

	var json_str: String = original.to_json()
	var loaded := LevelData.new()
	assert_true(loaded.from_json(json_str))

	assert_eq(loaded.level_name, "Roundtrip")
	assert_eq(loaded.trees.size(), 1)
	assert_eq(loaded.trees[0]["type"], "birch")
	assert_eq(loaded.lights.size(), 1)
	assert_eq(loaded.lights[0]["type"], "neon")
	assert_eq(loaded.decorations.size(), 1)
	assert_eq(loaded.decorations[0]["type"], "log")


# ============================================================================
# v1 Compatibility via Import
# ============================================================================


func test_v1_json_import_succeeds() -> void:
	var v1_json := '{"format_version":1,"level_name":"OldLevel","author":"V1","description":"","map_width":2400,"map_height":2000,"player_spawn":{"x":200,"y":200},"floor_color":{"r":0.25,"g":0.25,"b":0.28,"a":1},"wall_color":{"r":0.35,"g":0.35,"b":0.4,"a":1},"walls":[],"enemies":[],"cover_objects":[]}'

	var data := LevelData.new()
	assert_true(data.from_json(v1_json))
	assert_eq(data.level_name, "OldLevel")
	assert_eq(data.trees.size(), 0)
	assert_eq(data.lights.size(), 0)
	assert_eq(data.decorations.size(), 0)
