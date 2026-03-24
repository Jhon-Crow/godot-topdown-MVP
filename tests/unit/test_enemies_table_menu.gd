extends GutTest
## Unit tests for EnemiesTableMenu.
##
## Tests the LEVEL_NAMES dictionary, ENEMY_COUNTS format,
## and ENEMY_FEATURES format using a mock class.


# ============================================================================
# Mock EnemiesTableMenu for Testing
# ============================================================================


class MockEnemiesTableMenu:
	## Level name mapping (scene path -> display name).
	const LEVEL_NAMES: Dictionary = {
		"res://scenes/levels/LabyrinthLevel.tscn": "Labyrinth",
		"res://scenes/levels/BuildingLevel.tscn": "Building",
		"res://scenes/levels/CastleLevel.tscn": "Castle",
		"res://scenes/levels/BeachLevel.tscn": "Beach",
		"res://scenes/levels/DocksLevel.tscn": "Docks",
		"res://scenes/levels/Labyrinth2Level.tscn": "Labyrinth 2",
		"res://scenes/levels/CityLevel.tscn": "City",
		"res://scenes/levels/DecadenceLevel.tscn": "Decadence",
		"res://scenes/levels/TestTier.tscn": "Polygon",
		"res://scenes/levels/RevolverLevel.tscn": "Double Corridor",
		"res://scenes/levels/FactoryLevel.tscn": "Factory",
	}

	## Enemy counts per level: [Rifle, Shotgun, UZI, Machete, Machine Gun]
	const ENEMY_COUNTS: Dictionary = {
		"res://scenes/levels/LabyrinthLevel.tscn": [4, 1, 0, 0, 0],
		"res://scenes/levels/BuildingLevel.tscn": [9, 0, 1, 0, 0],
		"res://scenes/levels/CastleLevel.tscn": [2, 3, 8, 0, 0],
		"res://scenes/levels/BeachLevel.tscn": [2, 1, 0, 5, 0],
		"res://scenes/levels/DocksLevel.tscn": [9, 3, 6, 2, 0],
		"res://scenes/levels/Labyrinth2Level.tscn": [10, 2, 2, 0, 1],
		"res://scenes/levels/CityLevel.tscn": [5, 2, 2, 0, 0],
		"res://scenes/levels/DecadenceLevel.tscn": [7, 2, 0, 3, 0],
		"res://scenes/levels/TestTier.tscn": [10, 0, 0, 0, 0],
		"res://scenes/levels/RevolverLevel.tscn": [13, 0, 0, 0, 0],
		"res://scenes/levels/FactoryLevel.tscn": [13, 0, 0, 0, 0],
	}

	## Enemy features per level: [Grenadier, Teleport, Force Field, Jammer]
	const ENEMY_FEATURES: Dictionary = {
		"res://scenes/levels/LabyrinthLevel.tscn":  [false, false, false, false],
		"res://scenes/levels/BuildingLevel.tscn":   [true,  false, false, false],
		"res://scenes/levels/CastleLevel.tscn":     [false, false, false, false],
		"res://scenes/levels/BeachLevel.tscn":      [false, false, false, false],
		"res://scenes/levels/DocksLevel.tscn":      [true,  false, false, false],
		"res://scenes/levels/Labyrinth2Level.tscn": [true,  false, false, false],
		"res://scenes/levels/CityLevel.tscn":       [false, true,  false, false],
		"res://scenes/levels/DecadenceLevel.tscn":  [false, false, false, true],
		"res://scenes/levels/TestTier.tscn":        [false, false, false, false],
		"res://scenes/levels/RevolverLevel.tscn":   [false, false, true,  false],
		"res://scenes/levels/FactoryLevel.tscn":    [false, false, false, false],
	}

	## Convert count to display text.
	func count_text(count: int) -> String:
		if count > 0:
			return str(count)
		return "—"

	## Extract level name from scene path.
	func extract_level_name(path: String) -> String:
		var filename: String = path.get_file().get_basename()
		return filename.replace("Level", "").replace("_", " ")


var menu: MockEnemiesTableMenu


func before_each() -> void:
	menu = MockEnemiesTableMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# LEVEL_NAMES Dictionary Tests
# ============================================================================


func test_level_names_has_11_entries() -> void:
	assert_eq(menu.LEVEL_NAMES.size(), 11,
		"LEVEL_NAMES should have 11 entries")


func test_level_names_contains_labyrinth() -> void:
	assert_true(menu.LEVEL_NAMES.has("res://scenes/levels/LabyrinthLevel.tscn"),
		"Should contain Labyrinth level")
	assert_eq(menu.LEVEL_NAMES["res://scenes/levels/LabyrinthLevel.tscn"], "Labyrinth",
		"Labyrinth level display name should be 'Labyrinth'")


func test_level_names_contains_factory() -> void:
	assert_true(menu.LEVEL_NAMES.has("res://scenes/levels/FactoryLevel.tscn"),
		"Should contain Factory level")
	assert_eq(menu.LEVEL_NAMES["res://scenes/levels/FactoryLevel.tscn"], "Factory",
		"Factory level display name should be 'Factory'")


func test_level_names_all_are_strings() -> void:
	for path in menu.LEVEL_NAMES:
		assert_typeof(menu.LEVEL_NAMES[path], TYPE_STRING,
			"Display name for %s should be a string" % path)


func test_level_names_all_keys_are_tscn_paths() -> void:
	for path in menu.LEVEL_NAMES:
		assert_true(path.ends_with(".tscn"),
			"Key '%s' should end with .tscn" % path)
		assert_true(path.begins_with("res://"),
			"Key '%s' should start with res://" % path)


# ============================================================================
# ENEMY_COUNTS Format Tests
# ============================================================================


func test_enemy_counts_has_11_entries() -> void:
	assert_eq(menu.ENEMY_COUNTS.size(), 11,
		"ENEMY_COUNTS should have 11 entries")


func test_enemy_counts_matches_level_names_keys() -> void:
	for path in menu.LEVEL_NAMES:
		assert_true(menu.ENEMY_COUNTS.has(path),
			"ENEMY_COUNTS should have entry for %s" % path)


func test_enemy_counts_arrays_have_5_integers() -> void:
	for path in menu.ENEMY_COUNTS:
		var counts: Array = menu.ENEMY_COUNTS[path]
		assert_eq(counts.size(), 5,
			"Enemy counts for %s should have 5 elements" % path)
		for i in range(counts.size()):
			assert_typeof(counts[i], TYPE_INT,
				"Enemy count[%d] for %s should be an integer" % [i, path])


func test_enemy_counts_are_non_negative() -> void:
	for path in menu.ENEMY_COUNTS:
		var counts: Array = menu.ENEMY_COUNTS[path]
		for i in range(counts.size()):
			assert_true(counts[i] >= 0,
				"Enemy count[%d] for %s should be non-negative" % [i, path])


func test_labyrinth_enemy_counts() -> void:
	var counts: Array = menu.ENEMY_COUNTS["res://scenes/levels/LabyrinthLevel.tscn"]
	assert_eq(counts, [4, 1, 0, 0, 0],
		"Labyrinth should have [4 Rifle, 1 Shotgun, 0 UZI, 0 Machete, 0 MG]")


func test_docks_enemy_counts() -> void:
	var counts: Array = menu.ENEMY_COUNTS["res://scenes/levels/DocksLevel.tscn"]
	assert_eq(counts, [9, 3, 6, 2, 0],
		"Docks should have [9 Rifle, 3 Shotgun, 6 UZI, 2 Machete, 0 MG]")


func test_labyrinth2_has_machine_gunner() -> void:
	var counts: Array = menu.ENEMY_COUNTS["res://scenes/levels/Labyrinth2Level.tscn"]
	assert_eq(counts[4], 1,
		"Labyrinth 2 should have 1 machine gunner")


# ============================================================================
# ENEMY_FEATURES Format Tests
# ============================================================================


func test_enemy_features_has_11_entries() -> void:
	assert_eq(menu.ENEMY_FEATURES.size(), 11,
		"ENEMY_FEATURES should have 11 entries")


func test_enemy_features_matches_level_names_keys() -> void:
	for path in menu.LEVEL_NAMES:
		assert_true(menu.ENEMY_FEATURES.has(path),
			"ENEMY_FEATURES should have entry for %s" % path)


func test_enemy_features_arrays_have_4_booleans() -> void:
	for path in menu.ENEMY_FEATURES:
		var features: Array = menu.ENEMY_FEATURES[path]
		assert_eq(features.size(), 4,
			"Enemy features for %s should have 4 elements" % path)
		for i in range(features.size()):
			assert_typeof(features[i], TYPE_BOOL,
				"Enemy feature[%d] for %s should be a boolean" % [i, path])


func test_building_has_grenadier() -> void:
	var features: Array = menu.ENEMY_FEATURES["res://scenes/levels/BuildingLevel.tscn"]
	assert_true(features[0],
		"Building should have grenadier feature")


func test_city_has_teleport() -> void:
	var features: Array = menu.ENEMY_FEATURES["res://scenes/levels/CityLevel.tscn"]
	assert_true(features[1],
		"City should have teleport feature")


func test_revolver_has_force_field() -> void:
	var features: Array = menu.ENEMY_FEATURES["res://scenes/levels/RevolverLevel.tscn"]
	assert_true(features[2],
		"Double Corridor should have force field feature")


func test_decadence_has_jammer() -> void:
	var features: Array = menu.ENEMY_FEATURES["res://scenes/levels/DecadenceLevel.tscn"]
	assert_true(features[3],
		"Decadence should have jammer feature")


func test_labyrinth_has_no_features() -> void:
	var features: Array = menu.ENEMY_FEATURES["res://scenes/levels/LabyrinthLevel.tscn"]
	assert_eq(features, [false, false, false, false],
		"Labyrinth should have no special features")


# ============================================================================
# Helper Function Tests
# ============================================================================


func test_count_text_positive() -> void:
	assert_eq(menu.count_text(5), "5",
		"Positive count should return string number")


func test_count_text_zero() -> void:
	assert_eq(menu.count_text(0), "—",
		"Zero count should return dash")
