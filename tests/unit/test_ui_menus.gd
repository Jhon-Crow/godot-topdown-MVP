extends GutTest
## Unit tests for UI menu scripts.
##
## Tests the logic for pause menu, controls menu, difficulty menu, levels menu, and armory menu.
## Tests the state management and button states without requiring actual UI nodes.


# ============================================================================
# Mock Pause Menu
# ============================================================================


class MockPauseMenu:
	var _controls_menu_visible: bool = false
	var _difficulty_menu_visible: bool = false
	var _levels_menu_visible: bool = false
	var _armory_menu_visible: bool = false
	var visible: bool = false
	var paused: bool = false

	func toggle_pause() -> void:
		if visible:
			resume_game()
		else:
			pause_game()

	func pause_game() -> void:
		paused = true
		visible = true

	func resume_game() -> void:
		paused = false
		visible = false
		_controls_menu_visible = false
		_difficulty_menu_visible = false
		_levels_menu_visible = false
		_armory_menu_visible = false

	func show_controls_menu() -> void:
		_controls_menu_visible = true

	func hide_controls_menu() -> void:
		_controls_menu_visible = false

	func show_difficulty_menu() -> void:
		_difficulty_menu_visible = true

	func hide_difficulty_menu() -> void:
		_difficulty_menu_visible = false

	func show_levels_menu() -> void:
		_levels_menu_visible = true

	func hide_levels_menu() -> void:
		_levels_menu_visible = false

	func show_armory_menu() -> void:
		_armory_menu_visible = true

	func hide_armory_menu() -> void:
		_armory_menu_visible = false


# ============================================================================
# Mock Controls Menu
# ============================================================================


class MockControlsMenu:
	var _rebinding_action: String = ""
	var _pending_bindings: Dictionary = {}
	var _has_changes: bool = false

	signal back_pressed

	func start_rebinding(action_name: String) -> void:
		_rebinding_action = action_name

	func cancel_rebinding() -> void:
		_rebinding_action = ""

	func is_rebinding() -> bool:
		return not _rebinding_action.is_empty()

	func get_rebinding_action() -> String:
		return _rebinding_action

	func add_pending_binding(action: String, key: String) -> void:
		_pending_bindings[action] = key
		_has_changes = true

	func has_pending_changes() -> bool:
		return _has_changes

	func apply_changes() -> void:
		_pending_bindings.clear()
		_has_changes = false

	func reset_changes() -> void:
		_pending_bindings.clear()
		_has_changes = false

	func get_pending_binding(action: String) -> String:
		if action in _pending_bindings:
			return _pending_bindings[action]
		return ""


# ============================================================================
# Mock Difficulty Menu
# ============================================================================


class MockDifficultyMenu:
	enum Difficulty { EASY, NORMAL, HARD, POWER_FANTASY }

	var current_difficulty: Difficulty = Difficulty.NORMAL
	var night_mode_enabled: bool = false

	signal back_pressed

	func set_difficulty(difficulty: Difficulty) -> void:
		current_difficulty = difficulty

	func get_difficulty() -> Difficulty:
		return current_difficulty

	func set_night_mode(enabled: bool) -> void:
		night_mode_enabled = enabled

	func is_night_mode_enabled() -> bool:
		return night_mode_enabled

	func is_easy_selected() -> bool:
		return current_difficulty == Difficulty.EASY

	func is_normal_selected() -> bool:
		return current_difficulty == Difficulty.NORMAL

	func is_hard_selected() -> bool:
		return current_difficulty == Difficulty.HARD

	func is_power_fantasy_selected() -> bool:
		return current_difficulty == Difficulty.POWER_FANTASY

	func get_easy_button_text() -> String:
		return "Easy (Selected)" if is_easy_selected() else "Easy"

	func get_normal_button_text() -> String:
		return "Normal (Selected)" if is_normal_selected() else "Normal"

	func get_hard_button_text() -> String:
		return "Hard (Selected)" if is_hard_selected() else "Hard"

	func get_power_fantasy_button_text() -> String:
		return "Power Fantasy (Selected)" if is_power_fantasy_selected() else "Power Fantasy"

	func get_status_text() -> String:
		var base_text: String = ""
		match current_difficulty:
			Difficulty.EASY:
				base_text = "Easy mode: Enemies react slower"
			Difficulty.HARD:
				base_text = "Hard mode: Enemies react when you look away"
			Difficulty.POWER_FANTASY:
				base_text = "Power Fantasy: 10 HP, 3x ammo, blue lasers"
			_:
				base_text = "Normal mode: Classic gameplay"
		if night_mode_enabled:
			base_text += " | Night Mode ON"
		return base_text


# ============================================================================
# Mock Levels Menu (Card-based)
# ============================================================================


class MockLevelsMenu:
	## Level data with card metadata (matches card-based levels_menu.gd).
	const LEVELS: Array[Dictionary] = [
		{
			"name": "Technical Facility",
			"name_ru": "Техзона",
			"path": "res://scenes/levels/TechnicalLevel.tscn",
			"description": "Labyrinth of enclosed technical rooms. Tight corridors and compact spaces.",
			"enemy_count": 4,
			"map_size": "1600x1600"
		},
		{
			"name": "Building Level",
			"path": "res://scenes/levels/BuildingLevel.tscn",
			"description": "Hotline Miami style building with interconnected rooms and corridors.",
			"enemy_count": 10,
			"map_size": "2400x2000"
		},
		{
			"name": "Polygon",
			"name_ru": "Полигон",
			"path": "res://scenes/levels/TestTier.tscn",
			"description": "Open training ground for testing weapons and practicing combat skills.",
			"enemy_count": 5,
			"map_size": "1280x720"
		},
		{
			"name": "Castle",
			"name_ru": "Замок",
			"path": "res://scenes/levels/CastleLevel.tscn",
			"description": "Medieval fortress assault across a massive oval-shaped courtyard.",
			"enemy_count": 15,
			"map_size": "6000x2560"
		},
		{
			"name": "Tutorial",
			"name_ru": "Обучение",
			"path": "res://scenes/levels/csharp/TestTier.tscn",
			"description": "Step-by-step training: movement, shooting, bolt-action, scope, grenades.",
			"enemy_count": 4,
			"map_size": "1280x720"
		},
		{
			"name": "Beach",
			"name_ru": "Пляж",
			"path": "res://scenes/levels/BeachLevel.tscn",
			"description": "Outdoor beach environment with machete-wielding enemies and scattered cover.",
			"enemy_count": 8,
			"map_size": "2400x2000"
		}
	]

	const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard", "Power Fantasy"]

	var current_scene_path: String = ""

	signal back_pressed

	func get_level_count() -> int:
		return LEVELS.size()

	func get_level_names() -> Array:
		var names: Array = []
		for level in LEVELS:
			names.append(level["name"])
		return names

	func get_level_path(name: String) -> String:
		for level in LEVELS:
			if level["name"] == name:
				return level["path"]
		return ""

	func get_level_data(name: String) -> Dictionary:
		for level in LEVELS:
			if level["name"] == name:
				return level
		return {}

	func is_current_level(level_path: String) -> bool:
		return level_path == current_scene_path

	func get_display_name(level_name: String) -> String:
		var data := get_level_data(level_name)
		return data.get("name_ru", data.get("name", level_name))

	func should_disable_card(level_name: String) -> bool:
		var path := get_level_path(level_name)
		return is_current_level(path)

	func get_enemy_count(level_name: String) -> int:
		var data := get_level_data(level_name)
		return data.get("enemy_count", 0)

	## Progress data per level per difficulty: "path:difficulty" → {"rank": String, "score": int}
	var _progress: Dictionary = {}

	func set_level_progress(level_name: String, difficulty: String, rank: String, score: int) -> void:
		var path := get_level_path(level_name)
		if not path.is_empty():
			_progress[path + ":" + difficulty] = {"rank": rank, "score": score}

	func get_best_rank(level_name: String, difficulty: String) -> String:
		var path := get_level_path(level_name)
		var key: String = path + ":" + difficulty
		if key in _progress:
			return _progress[key].get("rank", "")
		return ""

	func get_best_score(level_name: String, difficulty: String) -> int:
		var path := get_level_path(level_name)
		var key: String = path + ":" + difficulty
		if key in _progress:
			return _progress[key].get("score", 0)
		return 0

	func is_level_completed_on(level_name: String, difficulty: String) -> bool:
		var path := get_level_path(level_name)
		return (path + ":" + difficulty) in _progress


# ============================================================================
# Mock Armory Menu
# ============================================================================


class MockArmoryMenu:
	## Firearms data — separate from grenades.
	const FIREARMS: Dictionary = {
		"m16": {
			"name": "M16",
			"icon_path": "res://assets/sprites/weapons/m16_rifle.png",
			"unlocked": true,
			"description": "Standard assault rifle with auto/burst modes, red laser sight"
		},
		"ak47": {
			"name": "???",
			"icon_path": "",
			"unlocked": false,
			"description": "Coming soon"
		},
		"shotgun": {
			"name": "Shotgun",
			"icon_path": "res://assets/sprites/weapons/shotgun_icon.png",
			"unlocked": true,
			"description": "Pump-action shotgun — shell-by-shell loading, multi-pellet spread"
		},
		"mini_uzi": {
			"name": "Mini UZI",
			"icon_path": "res://assets/sprites/weapons/mini_uzi_icon.png",
			"unlocked": true,
			"description": "High fire rate SMG"
		},
		"silenced_pistol": {
			"name": "Silenced Pistol",
			"icon_path": "res://assets/sprites/weapons/silenced_pistol_topdown.png",
			"unlocked": true,
			"description": "Beretta M9 with suppressor"
		},
		"sniper": {
			"name": "ASVK",
			"icon_path": "res://assets/sprites/weapons/asvk_topdown.png",
			"unlocked": true,
			"description": "Anti-materiel sniper"
		}
	}

	signal back_pressed
	signal weapon_selected(weapon_id: String)

	var _applied_weapon: String = "m16"
	var _pending_weapon: String = "m16"

	func get_weapon_count() -> int:
		return FIREARMS.size()

	func get_weapon_ids() -> Array:
		return FIREARMS.keys()

	func get_weapon_data(weapon_id: String) -> Dictionary:
		if weapon_id in FIREARMS:
			return FIREARMS[weapon_id]
		return {}

	func is_weapon_unlocked(weapon_id: String) -> bool:
		if weapon_id in FIREARMS:
			return FIREARMS[weapon_id]["unlocked"]
		return false

	func get_unlocked_count() -> int:
		var count: int = 0
		for weapon_id in FIREARMS:
			if FIREARMS[weapon_id]["unlocked"]:
				count += 1
		return count

	func select_weapon(weapon_id: String) -> void:
		if weapon_id in FIREARMS and FIREARMS[weapon_id]["unlocked"]:
			_pending_weapon = weapon_id

	func has_pending_changes() -> bool:
		return _pending_weapon != _applied_weapon

	func apply() -> void:
		if has_pending_changes():
			_applied_weapon = _pending_weapon
			weapon_selected.emit(_applied_weapon)

	func get_selected_weapon() -> String:
		return _applied_weapon

	func get_pending_weapon() -> String:
		return _pending_weapon


# ============================================================================
# Pause Menu Tests
# ============================================================================


var pause_menu: MockPauseMenu


func test_pause_menu_initial_state() -> void:
	pause_menu = MockPauseMenu.new()
	assert_false(pause_menu.visible, "Pause menu should start hidden")
	assert_false(pause_menu.paused, "Game should not be paused initially")


func test_toggle_pause_shows_menu() -> void:
	pause_menu = MockPauseMenu.new()
	pause_menu.toggle_pause()

	assert_true(pause_menu.visible, "Menu should be visible after pause")
	assert_true(pause_menu.paused, "Game should be paused")


func test_toggle_pause_twice_hides_menu() -> void:
	pause_menu = MockPauseMenu.new()
	pause_menu.toggle_pause()
	pause_menu.toggle_pause()

	assert_false(pause_menu.visible, "Menu should be hidden after unpause")
	assert_false(pause_menu.paused, "Game should not be paused")


func test_resume_closes_submenus() -> void:
	pause_menu = MockPauseMenu.new()
	pause_menu.pause_game()
	pause_menu.show_controls_menu()
	pause_menu.show_difficulty_menu()
	pause_menu.show_armory_menu()

	pause_menu.resume_game()

	assert_false(pause_menu._controls_menu_visible, "Controls menu should close on resume")
	assert_false(pause_menu._difficulty_menu_visible, "Difficulty menu should close on resume")
	assert_false(pause_menu._armory_menu_visible, "Armory menu should close on resume")


# ============================================================================
# Controls Menu Tests
# ============================================================================


var controls_menu: MockControlsMenu


func test_controls_menu_not_rebinding_initially() -> void:
	controls_menu = MockControlsMenu.new()
	assert_false(controls_menu.is_rebinding(), "Should not be rebinding initially")


func test_start_rebinding_sets_action() -> void:
	controls_menu = MockControlsMenu.new()
	controls_menu.start_rebinding("move_up")

	assert_true(controls_menu.is_rebinding(), "Should be rebinding after start")
	assert_eq(controls_menu.get_rebinding_action(), "move_up", "Action should be set")


func test_cancel_rebinding_clears_action() -> void:
	controls_menu = MockControlsMenu.new()
	controls_menu.start_rebinding("move_up")
	controls_menu.cancel_rebinding()

	assert_false(controls_menu.is_rebinding(), "Should not be rebinding after cancel")


func test_add_pending_binding() -> void:
	controls_menu = MockControlsMenu.new()
	controls_menu.add_pending_binding("move_up", "W")

	assert_true(controls_menu.has_pending_changes(), "Should have pending changes")
	assert_eq(controls_menu.get_pending_binding("move_up"), "W", "Binding should be stored")


func test_apply_changes_clears_pending() -> void:
	controls_menu = MockControlsMenu.new()
	controls_menu.add_pending_binding("move_up", "W")
	controls_menu.apply_changes()

	assert_false(controls_menu.has_pending_changes(), "Should not have pending changes after apply")


func test_reset_changes_clears_pending() -> void:
	controls_menu = MockControlsMenu.new()
	controls_menu.add_pending_binding("move_up", "W")
	controls_menu.reset_changes()

	assert_false(controls_menu.has_pending_changes(), "Should not have pending changes after reset")


# ============================================================================
# Difficulty Menu Tests
# ============================================================================


var difficulty_menu: MockDifficultyMenu


func test_difficulty_menu_default_is_normal() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	assert_true(difficulty_menu.is_normal_selected(), "Normal should be default")


func test_set_difficulty_easy() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.EASY)

	assert_true(difficulty_menu.is_easy_selected(), "Easy should be selected")
	assert_false(difficulty_menu.is_normal_selected(), "Normal should not be selected")
	assert_false(difficulty_menu.is_hard_selected(), "Hard should not be selected")


func test_set_difficulty_hard() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.HARD)

	assert_true(difficulty_menu.is_hard_selected(), "Hard should be selected")


func test_button_text_shows_selected() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.EASY)

	assert_eq(difficulty_menu.get_easy_button_text(), "Easy (Selected)")
	assert_eq(difficulty_menu.get_normal_button_text(), "Normal")
	assert_eq(difficulty_menu.get_hard_button_text(), "Hard")


func test_status_text_for_easy() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.EASY)

	assert_eq(difficulty_menu.get_status_text(), "Easy mode: Enemies react slower")


func test_status_text_for_normal() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.NORMAL)

	assert_eq(difficulty_menu.get_status_text(), "Normal mode: Classic gameplay")


func test_status_text_for_hard() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.HARD)

	assert_eq(difficulty_menu.get_status_text(), "Hard mode: Enemies react when you look away")


func test_set_difficulty_power_fantasy() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.POWER_FANTASY)

	assert_true(difficulty_menu.is_power_fantasy_selected(), "Power Fantasy should be selected")
	assert_false(difficulty_menu.is_normal_selected(), "Normal should not be selected")
	assert_false(difficulty_menu.is_easy_selected(), "Easy should not be selected")
	assert_false(difficulty_menu.is_hard_selected(), "Hard should not be selected")


func test_button_text_shows_power_fantasy_selected() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.POWER_FANTASY)

	assert_eq(difficulty_menu.get_power_fantasy_button_text(), "Power Fantasy (Selected)")
	assert_eq(difficulty_menu.get_easy_button_text(), "Easy")
	assert_eq(difficulty_menu.get_normal_button_text(), "Normal")
	assert_eq(difficulty_menu.get_hard_button_text(), "Hard")


func test_status_text_for_power_fantasy() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.POWER_FANTASY)

	assert_eq(difficulty_menu.get_status_text(), "Power Fantasy: 10 HP, 3x ammo, blue lasers")


func test_night_mode_default_disabled() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	assert_false(difficulty_menu.is_night_mode_enabled(), "Night mode should be disabled by default")


func test_night_mode_enable() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_night_mode(true)

	assert_true(difficulty_menu.is_night_mode_enabled(), "Night mode should be enabled")


func test_night_mode_disable() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_night_mode(true)
	difficulty_menu.set_night_mode(false)

	assert_false(difficulty_menu.is_night_mode_enabled(), "Night mode should be disabled")


func test_status_text_with_night_mode() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_night_mode(true)

	assert_eq(difficulty_menu.get_status_text(), "Normal mode: Classic gameplay | Night Mode ON")


func test_status_text_power_fantasy_with_night_mode() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.POWER_FANTASY)
	difficulty_menu.set_night_mode(true)

	assert_eq(difficulty_menu.get_status_text(), "Power Fantasy: 10 HP, 3x ammo, blue lasers | Night Mode ON")


func test_night_mode_independent_of_difficulty() -> void:
	difficulty_menu = MockDifficultyMenu.new()
	difficulty_menu.set_night_mode(true)
	difficulty_menu.set_difficulty(MockDifficultyMenu.Difficulty.HARD)

	assert_true(difficulty_menu.is_night_mode_enabled(), "Night mode should stay enabled after difficulty change")
	assert_true(difficulty_menu.is_hard_selected(), "Hard should be selected")


# ============================================================================
# Levels Menu Tests (Card-based)
# ============================================================================


var levels_menu: MockLevelsMenu


func test_levels_menu_has_levels() -> void:
	levels_menu = MockLevelsMenu.new()
	assert_true(levels_menu.get_level_count() > 0, "Should have at least one level")


func test_levels_menu_has_six_levels() -> void:
	levels_menu = MockLevelsMenu.new()
	assert_eq(levels_menu.get_level_count(), 6, "Should have 6 levels")


func test_get_level_path() -> void:
	levels_menu = MockLevelsMenu.new()
	var path := levels_menu.get_level_path("Building Level")

	assert_eq(path, "res://scenes/levels/BuildingLevel.tscn", "Should return correct path")


func test_get_level_path_invalid() -> void:
	levels_menu = MockLevelsMenu.new()
	var path := levels_menu.get_level_path("Non Existent Level")

	assert_eq(path, "", "Should return empty string for invalid level")


func test_is_current_level() -> void:
	levels_menu = MockLevelsMenu.new()
	levels_menu.current_scene_path = "res://scenes/levels/BuildingLevel.tscn"

	assert_true(levels_menu.is_current_level("res://scenes/levels/BuildingLevel.tscn"),
		"Should detect current level")
	assert_false(levels_menu.is_current_level("res://scenes/levels/TestTier.tscn"),
		"Should not match different level")


func test_should_disable_current_level_card() -> void:
	levels_menu = MockLevelsMenu.new()
	levels_menu.current_scene_path = "res://scenes/levels/BuildingLevel.tscn"

	assert_true(levels_menu.should_disable_card("Building Level"),
		"Current level card should be disabled")
	assert_false(levels_menu.should_disable_card("Polygon"),
		"Other level cards should not be disabled")


func test_level_display_name_russian() -> void:
	levels_menu = MockLevelsMenu.new()
	assert_eq(levels_menu.get_display_name("Technical Facility"), "Техзона",
		"Technical Facility should display as Техзона")
	assert_eq(levels_menu.get_display_name("Polygon"), "Полигон",
		"Polygon should display as Полигон")
	assert_eq(levels_menu.get_display_name("Castle"), "Замок",
		"Castle should display as Замок")
	assert_eq(levels_menu.get_display_name("Tutorial"), "Обучение",
		"Tutorial should display as Обучение")


func test_level_display_name_fallback() -> void:
	levels_menu = MockLevelsMenu.new()
	assert_eq(levels_menu.get_display_name("Building Level"), "Building Level",
		"Building Level has no Russian name, should use English")


func test_level_enemy_count() -> void:
	levels_menu = MockLevelsMenu.new()
	assert_eq(levels_menu.get_enemy_count("Technical Facility"), 4)
	assert_eq(levels_menu.get_enemy_count("Building Level"), 10)
	assert_eq(levels_menu.get_enemy_count("Polygon"), 5)
	assert_eq(levels_menu.get_enemy_count("Castle"), 15)
	assert_eq(levels_menu.get_enemy_count("Tutorial"), 4)
	assert_eq(levels_menu.get_enemy_count("Beach"), 8)


func test_level_has_description() -> void:
	levels_menu = MockLevelsMenu.new()
	var data := levels_menu.get_level_data("Building Level")
	assert_true(data.has("description"), "Level should have a description")
	assert_true(data["description"].length() > 0, "Description should not be empty")


func test_level_progress_not_completed_initially() -> void:
	levels_menu = MockLevelsMenu.new()
	assert_false(levels_menu.is_level_completed_on("Building Level", "Normal"),
		"Level should not be completed initially")


func test_level_progress_no_rank_initially() -> void:
	levels_menu = MockLevelsMenu.new()
	assert_eq(levels_menu.get_best_rank("Building Level", "Normal"), "",
		"Best rank should be empty initially")


func test_level_progress_save_and_retrieve() -> void:
	levels_menu = MockLevelsMenu.new()
	levels_menu.set_level_progress("Building Level", "Normal", "A", 7000)

	assert_true(levels_menu.is_level_completed_on("Building Level", "Normal"),
		"Level should be completed after saving progress")
	assert_eq(levels_menu.get_best_rank("Building Level", "Normal"), "A",
		"Best rank should be A")
	assert_eq(levels_menu.get_best_score("Building Level", "Normal"), 7000,
		"Best score should be 7000")


func test_level_progress_per_difficulty() -> void:
	levels_menu = MockLevelsMenu.new()
	levels_menu.set_level_progress("Castle", "Easy", "S", 15000)
	levels_menu.set_level_progress("Castle", "Hard", "D", 2000)

	assert_eq(levels_menu.get_best_rank("Castle", "Easy"), "S",
		"Easy rank should be S")
	assert_eq(levels_menu.get_best_rank("Castle", "Hard"), "D",
		"Hard rank should be D")
	assert_false(levels_menu.is_level_completed_on("Castle", "Normal"),
		"Normal should not be completed")


func test_level_progress_per_level() -> void:
	levels_menu = MockLevelsMenu.new()
	levels_menu.set_level_progress("Building Level", "Normal", "A+", 9000)
	levels_menu.set_level_progress("Polygon", "Normal", "C", 3000)

	assert_eq(levels_menu.get_best_rank("Building Level", "Normal"), "A+")
	assert_eq(levels_menu.get_best_rank("Polygon", "Normal"), "C")


# ============================================================================
# Armory Menu Tests
# ============================================================================


var armory_menu: MockArmoryMenu


func test_armory_menu_has_weapons() -> void:
	armory_menu = MockArmoryMenu.new()
	assert_true(armory_menu.get_weapon_count() > 0, "Should have at least one weapon")


func test_armory_menu_m16_unlocked() -> void:
	armory_menu = MockArmoryMenu.new()
	assert_true(armory_menu.is_weapon_unlocked("m16"), "M16 should be unlocked")


func test_armory_menu_other_weapons_locked() -> void:
	armory_menu = MockArmoryMenu.new()
	assert_false(armory_menu.is_weapon_unlocked("ak47"), "AK47 should be locked")


func test_armory_menu_unlocked_count() -> void:
	armory_menu = MockArmoryMenu.new()
	assert_eq(armory_menu.get_unlocked_count(), 5, "Should have 5 unlocked weapons (M16, Shotgun, Mini UZI, Silenced Pistol, ASVK)")


func test_armory_menu_get_weapon_data() -> void:
	armory_menu = MockArmoryMenu.new()
	var data := armory_menu.get_weapon_data("m16")

	assert_eq(data["name"], "M16", "Should return correct weapon name")
	assert_true(data["description"].begins_with("Standard assault rifle"), "Should return correct description")
	assert_true(data["unlocked"], "Should show as unlocked")


func test_armory_menu_invalid_weapon() -> void:
	armory_menu = MockArmoryMenu.new()
	var data := armory_menu.get_weapon_data("invalid_weapon")

	assert_true(data.is_empty(), "Should return empty dictionary for invalid weapon")
	assert_false(armory_menu.is_weapon_unlocked("invalid_weapon"), "Invalid weapon should not be unlocked")


func test_armory_menu_shotgun_unlocked() -> void:
	armory_menu = MockArmoryMenu.new()
	assert_true(armory_menu.is_weapon_unlocked("shotgun"), "Shotgun should be unlocked")


func test_armory_menu_select_weapon_sets_pending() -> void:
	armory_menu = MockArmoryMenu.new()
	assert_eq(armory_menu.get_selected_weapon(), "m16", "Default weapon should be M16")

	armory_menu.select_weapon("shotgun")

	assert_eq(armory_menu.get_pending_weapon(), "shotgun", "Pending should be shotgun")
	assert_eq(armory_menu.get_selected_weapon(), "m16", "Applied should still be M16 until Apply")


func test_armory_menu_apply_changes_selection() -> void:
	armory_menu = MockArmoryMenu.new()
	armory_menu.select_weapon("shotgun")
	armory_menu.apply()

	assert_eq(armory_menu.get_selected_weapon(), "shotgun", "Should select shotgun after Apply")


func test_armory_menu_cannot_select_locked_weapon() -> void:
	armory_menu = MockArmoryMenu.new()
	armory_menu.select_weapon("ak47")  # Locked weapon

	assert_eq(armory_menu.get_pending_weapon(), "m16", "Pending should remain M16 when trying to select locked weapon")


func test_armory_menu_get_shotgun_data() -> void:
	armory_menu = MockArmoryMenu.new()
	var data := armory_menu.get_weapon_data("shotgun")

	assert_eq(data["name"], "Shotgun", "Should return correct weapon name")
	assert_true(data["unlocked"], "Shotgun should be unlocked")


func test_armory_menu_sniper_unlocked() -> void:
	armory_menu = MockArmoryMenu.new()
	assert_true(armory_menu.is_weapon_unlocked("sniper"), "ASVK sniper should be unlocked")


func test_armory_menu_has_six_weapons() -> void:
	armory_menu = MockArmoryMenu.new()
	assert_eq(armory_menu.get_weapon_count(), 6, "Should have 6 weapons (5 unlocked + 1 locked)")
