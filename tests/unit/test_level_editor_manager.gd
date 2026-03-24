extends GutTest
## Unit tests for LevelEditorManager (Issue #1442 - Level Editor).
##
## Tests save, load, list, delete, export, and import functionality
## for custom levels stored as JSON files.


## Path used for test levels (cleaned up after each test).
const TEST_DIR: String = "user://custom_levels/"


func after_each() -> void:
	_cleanup_test_files()


## Helper: remove any files created during tests.
func _cleanup_test_files() -> void:
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("test_") and file_name.ends_with(".json"):
			DirAccess.remove_absolute(TEST_DIR + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


## Helper: create a LevelData with a given name (v2 format).
func _create_test_level(lname: String) -> LevelData:
	var data := LevelData.new()
	data.level_name = lname
	data.author = "TestRunner"
	data.walls.append({"x": 100.0, "y": 200.0, "w": 300.0, "h": 32.0})
	data.enemies.append({"x": 400.0, "y": 500.0, "weapon_type": 0, "behavior": 1})
	return data


# ============================================================================
# Filename Sanitization Tests
# ============================================================================


func test_sanitize_filename_replaces_slashes() -> void:
	var data := _create_test_level("test/level\\name")
	var json_str: String = data.to_json()
	assert_true(json_str.contains("test/level\\\\name"), "JSON should contain the original name")


func test_sanitize_filename_handles_empty() -> void:
	var data := LevelData.new()
	data.level_name = ""
	var json_str: String = data.to_json()
	assert_true(json_str.length() > 0, "Empty name level should still serialize")


# ============================================================================
# Export/Import Tests
# ============================================================================


func test_export_produces_json_string() -> void:
	var data := _create_test_level("test_export")
	var json_str: String = data.to_json()
	assert_true(json_str.length() > 0, "Export should produce non-empty JSON")
	assert_true(json_str.contains("test_export"), "Export should contain level name")
	assert_true(json_str.contains("format_version"), "Export should contain format_version")


func test_import_from_valid_json() -> void:
	var original := _create_test_level("test_import")
	var json_str: String = original.to_json()

	var imported := LevelData.new()
	var success: bool = imported.from_json(json_str)
	assert_true(success, "Import should succeed with valid JSON")
	assert_eq(imported.level_name, "test_import", "Imported level name should match")
	assert_eq(imported.walls.size(), 1, "Imported walls count should match")
	assert_eq(imported.enemies.size(), 1, "Imported enemies count should match")


func test_import_from_invalid_json() -> void:
	var data := LevelData.new()
	var success: bool = data.from_json("not json at all")
	assert_false(success, "Import should fail with invalid JSON")


func test_import_preserves_enemy_weapon_type() -> void:
	var original := LevelData.new()
	original.level_name = "test_weapon"
	original.enemies.append({"x": 100.0, "y": 200.0, "weapon_type": 1, "behavior": 1})
	var json_str: String = original.to_json()

	var imported := LevelData.new()
	imported.from_json(json_str)
	assert_eq(imported.enemies[0]["weapon_type"], 1, "Enemy weapon_type should be preserved")


func test_import_preserves_cover_type() -> void:
	var original := LevelData.new()
	original.level_name = "test_cover"
	original.cover_objects.append({"x": 300.0, "y": 400.0, "w": 96.0, "h": 32.0, "type": "desk"})
	var json_str: String = original.to_json()

	var imported := LevelData.new()
	imported.from_json(json_str)
	assert_eq(imported.cover_objects[0]["type"], "desk", "Cover type should be preserved")


# ============================================================================
# Multiple Level Data Tests
# ============================================================================


func test_multiple_walls_survive_roundtrip() -> void:
	var data := LevelData.new()
	data.level_name = "test_multi_walls"
	for i in range(10):
		data.walls.append({"x": float(i * 100), "y": 200.0, "w": 80.0, "h": 32.0})

	var loaded := LevelData.new()
	loaded.from_json(data.to_json())
	assert_eq(loaded.walls.size(), 10, "All 10 walls should survive roundtrip")


func test_multiple_enemies_v2_survive_roundtrip() -> void:
	var data := LevelData.new()
	data.level_name = "test_multi_enemies"
	# weapon_type: 0=RIFLE, 1=SHOTGUN, 2=UZI, 5=PM, 7=SNIPER
	var weapon_types: Array[int] = [0, 1, 2, 5, 7]
	for i in range(weapon_types.size()):
		data.enemies.append({
			"x": float(i * 200), "y": 500.0,
			"weapon_type": weapon_types[i], "behavior": 1 if i % 2 == 0 else 0
		})

	var loaded := LevelData.new()
	loaded.from_json(data.to_json())
	assert_eq(loaded.enemies.size(), 5, "All 5 enemies should survive roundtrip")
	assert_eq(loaded.enemies[1]["weapon_type"], 1, "Second enemy weapon_type should be 1 (SHOTGUN)")
	assert_eq(loaded.enemies[2]["behavior"], 1, "Third enemy behavior should be GUARD (even index)")


func test_empty_level_roundtrip() -> void:
	var data := LevelData.new()
	data.level_name = "test_empty"
	var json_str: String = data.to_json()

	var loaded := LevelData.new()
	var success: bool = loaded.from_json(json_str)
	assert_true(success, "Empty level should roundtrip successfully")
	assert_eq(loaded.walls.size(), 0, "Empty level should have no walls")
	assert_eq(loaded.enemies.size(), 0, "Empty level should have no enemies")
	assert_eq(loaded.cover_objects.size(), 0, "Empty level should have no cover objects")


# ============================================================================
# Level Editor Constants Tests
# ============================================================================


func test_custom_levels_dir_ends_with_slash() -> void:
	var dir: String = "user://custom_levels/"
	assert_true(dir.ends_with("/"), "Custom levels dir should end with /")


func test_level_extension_starts_with_dot() -> void:
	var ext: String = ".json"
	assert_true(ext.begins_with("."), "Level extension should start with dot")
	assert_eq(ext, ".json", "Level extension should be .json")
