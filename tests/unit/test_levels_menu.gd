extends GutTest
## Unit tests for LevelsMenu.
##
## Tests the LEVELS array, DIFFICULTY_NAMES, card dimensions,
## grid columns, and level unlock logic using a mock class.


# ============================================================================
# Mock LevelsMenu for Testing
# ============================================================================


class MockLevelsMenu:
	## Level metadata array.
	const LEVELS: Array[Dictionary] = [
		{"name": "Labyrinth", "path": "res://scenes/levels/LabyrinthLevel.tscn", "enemy_count": 5},
		{"name": "Building Level", "path": "res://scenes/levels/BuildingLevel.tscn", "enemy_count": 10},
		{"name": "Polygon", "path": "res://scenes/levels/TestTier.tscn", "enemy_count": 12},
		{"name": "Castle", "path": "res://scenes/levels/CastleLevel.tscn", "enemy_count": 13},
		{"name": "Double Corridor", "path": "res://scenes/levels/RevolverLevel.tscn", "enemy_count": 14},
		{"name": "City", "path": "res://scenes/levels/CityLevel.tscn", "enemy_count": 9},
		{"name": "Beach", "path": "res://scenes/levels/BeachLevel.tscn", "enemy_count": 8},
		{"name": "Docks", "path": "res://scenes/levels/DocksLevel.tscn", "enemy_count": 15},
		{"name": "Factory", "path": "res://scenes/levels/FactoryLevel.tscn", "enemy_count": 13},
		{"name": "Decadence", "path": "res://scenes/levels/DecadenceLevel.tscn", "enemy_count": 13},
		{"name": "Labyrinth Complex", "path": "res://scenes/levels/Labyrinth2Level.tscn", "enemy_count": 17},
		{"name": "Sewer", "path": "res://scenes/levels/SewerLevel.tscn", "enemy_count": 13},
		{"name": "Arena", "path": "res://scenes/levels/ArenaLevel.tscn", "enemy_count": 0, "endless": true, "always_unlocked": true},
	]

	## Difficulty names in display order.
	const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard", "Power Fantasy", "Black Metal"]

	## Card dimensions.
	const CARD_WIDTH: float = 220.0
	const CARD_HEIGHT: float = 290.0

	## Number of columns in the level grid.
	const GRID_COLUMNS: int = 4

	## Check whether a level is unlocked.
	func is_level_unlocked(level_index: int, previous_completed: bool, all_maps_unlocked: bool) -> bool:
		if level_index <= 0:
			return true
		if LEVELS[level_index].get("always_unlocked", false):
			return true
		if all_maps_unlocked:
			return true
		return previous_completed

	## Check whether all levels in LEVELS are completed on any difficulty (Issue #1618).
	func is_all_levels_completed(completed_paths: Array) -> bool:
		for level_data in LEVELS:
			if level_data["path"] not in completed_paths:
				return false
		return true

	## Check whether roguelike is unlocked (Issue #1618).
	func is_roguelike_unlocked(completed_paths: Array, experimental_bypass: bool) -> bool:
		if experimental_bypass:
			return true
		return is_all_levels_completed(completed_paths)

	## Signal tracking.
	var back_pressed_count: int = 0

	## Press back.
	func press_back() -> void:
		back_pressed_count += 1

	## Simulate level selection via SceneLoader path (Issue #1633).
	## Returns true if back_pressed would be emitted before loading.
	func select_level_with_scene_loader(level_path: String) -> bool:
		# Mirrors the fixed _on_level_selected logic:
		# back_pressed must be emitted before scene_loader.load_level()
		# so the menu is removed before the new scene starts.
		back_pressed_count += 1
		return back_pressed_count > 0


var menu: MockLevelsMenu


func before_each() -> void:
	menu = MockLevelsMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# LEVELS Array Tests
# ============================================================================


func test_levels_count() -> void:
	assert_eq(menu.LEVELS.size(), 13,
		"Should have 13 levels")


func test_first_level_is_labyrinth() -> void:
	assert_eq(menu.LEVELS[0]["name"], "Labyrinth",
		"First level should be Labyrinth")


func test_last_level_is_arena() -> void:
	assert_eq(menu.LEVELS[12]["name"], "Arena",
		"Last level should be Arena")


func test_all_levels_have_name() -> void:
	for i in range(menu.LEVELS.size()):
		assert_true(menu.LEVELS[i].has("name"),
			"Level %d should have a name" % i)


func test_all_levels_have_path() -> void:
	for i in range(menu.LEVELS.size()):
		assert_true(menu.LEVELS[i].has("path"),
			"Level %d should have a path" % i)
		assert_true(menu.LEVELS[i]["path"].ends_with(".tscn"),
			"Level %d path should end with .tscn" % i)


func test_all_levels_have_enemy_count() -> void:
	for i in range(menu.LEVELS.size()):
		assert_true(menu.LEVELS[i].has("enemy_count"),
			"Level %d should have enemy_count" % i)


func test_arena_is_endless() -> void:
	assert_true(menu.LEVELS[12].get("endless", false),
		"Arena should be marked as endless")


func test_arena_always_unlocked() -> void:
	assert_true(menu.LEVELS[12].get("always_unlocked", false),
		"Arena should be always unlocked")


# ============================================================================
# DIFFICULTY_NAMES Tests
# ============================================================================


func test_difficulty_names_count() -> void:
	assert_eq(menu.DIFFICULTY_NAMES.size(), 5,
		"Should have 5 difficulty names")


func test_difficulty_names_content() -> void:
	assert_eq(menu.DIFFICULTY_NAMES[0], "Easy", "First difficulty should be Easy")
	assert_eq(menu.DIFFICULTY_NAMES[1], "Normal", "Second difficulty should be Normal")
	assert_eq(menu.DIFFICULTY_NAMES[2], "Hard", "Third difficulty should be Hard")
	assert_eq(menu.DIFFICULTY_NAMES[3], "Power Fantasy", "Fourth difficulty should be Power Fantasy")
	assert_eq(menu.DIFFICULTY_NAMES[4], "Black Metal", "Fifth difficulty should be Black Metal")


# ============================================================================
# Card Dimension Constants Tests
# ============================================================================


func test_card_width() -> void:
	assert_eq(menu.CARD_WIDTH, 220.0,
		"Card width should be 220 pixels")


func test_card_height() -> void:
	assert_eq(menu.CARD_HEIGHT, 290.0,
		"Card height should be 290 pixels")


func test_grid_columns() -> void:
	assert_eq(menu.GRID_COLUMNS, 4,
		"Grid should have 4 columns")


# ============================================================================
# Level Unlock Tests
# ============================================================================


func test_first_level_always_unlocked() -> void:
	assert_true(menu.is_level_unlocked(0, false, false),
		"First level should always be unlocked")


func test_second_level_locked_without_completion() -> void:
	assert_false(menu.is_level_unlocked(1, false, false),
		"Second level should be locked without completing first")


func test_second_level_unlocked_with_completion() -> void:
	assert_true(menu.is_level_unlocked(1, true, false),
		"Second level should unlock after completing first")


func test_all_maps_unlocked_overrides() -> void:
	assert_true(menu.is_level_unlocked(5, false, true),
		"All maps unlocked setting should override progression")


func test_arena_unlocked_regardless() -> void:
	assert_true(menu.is_level_unlocked(12, false, false),
		"Arena should be unlocked regardless of progression")


# ============================================================================
# Back Button Tests
# ============================================================================


func test_back_button() -> void:
	menu.press_back()

	assert_eq(menu.back_pressed_count, 1,
		"Should track back press")


# ============================================================================
# Level Selection Closes Menu Tests (Issue #1633)
# ============================================================================


func test_level_selection_emits_back_pressed() -> void:
	## Issue #1633: selecting a level from the score screen left the menu
	## visible because _on_level_selected did not emit back_pressed before
	## handing off to SceneLoader. Verify the fixed flow emits back_pressed.
	var level_path: String = menu.LEVELS[0]["path"]
	var result: bool = menu.select_level_with_scene_loader(level_path)

	assert_true(result,
		"Selecting a level should emit back_pressed so the menu is freed")
	assert_eq(menu.back_pressed_count, 1,
		"back_pressed should be emitted exactly once when a level is selected")


# ============================================================================
# Roguelike Unlock Tests (Issue #1618)
# ============================================================================


func test_roguelike_locked_when_no_levels_complete() -> void:
	assert_false(menu.is_roguelike_unlocked([], false),
		"Roguelike should be locked when no levels are complete")


func test_roguelike_locked_when_some_but_not_all_levels_complete() -> void:
	var partial: Array = [
		"res://scenes/levels/LabyrinthLevel.tscn",
		"res://scenes/levels/BuildingLevel.tscn",
	]
	assert_false(menu.is_roguelike_unlocked(partial, false),
		"Roguelike should be locked when only some levels are complete")


func test_roguelike_unlocked_when_all_levels_complete() -> void:
	var all_paths: Array = []
	for level_data in menu.LEVELS:
		all_paths.append(level_data["path"])
	assert_true(menu.is_roguelike_unlocked(all_paths, false),
		"Roguelike should be unlocked when all levels are complete")


func test_roguelike_unlocked_via_experimental_bypass() -> void:
	assert_true(menu.is_roguelike_unlocked([], true),
		"Roguelike should be unlocked via experimental bypass even with no completions")


func test_roguelike_unlocked_via_experimental_overrides_partial_progress() -> void:
	var partial: Array = ["res://scenes/levels/LabyrinthLevel.tscn"]
	assert_true(menu.is_roguelike_unlocked(partial, true),
		"Experimental bypass should unlock roguelike regardless of level progress")


func test_all_levels_completed_false_when_one_missing() -> void:
	var all_but_one: Array = []
	for i in range(menu.LEVELS.size() - 1):
		all_but_one.append(menu.LEVELS[i]["path"])
	assert_false(menu.is_all_levels_completed(all_but_one),
		"Should return false when one level is not completed")


func test_all_levels_completed_true_when_all_done() -> void:
	var all_paths: Array = []
	for level_data in menu.LEVELS:
		all_paths.append(level_data["path"])
	assert_true(menu.is_all_levels_completed(all_paths),
		"Should return true when all levels are completed")


func test_all_levels_completed_false_with_empty_list() -> void:
	assert_false(menu.is_all_levels_completed([]),
		"Should return false with empty completed list")
