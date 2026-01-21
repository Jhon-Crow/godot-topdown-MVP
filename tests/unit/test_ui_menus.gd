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
	enum Difficulty { EASY, NORMAL, HARD }

	var current_difficulty: Difficulty = Difficulty.NORMAL

	signal back_pressed

	func set_difficulty(difficulty: Difficulty) -> void:
		current_difficulty = difficulty

	func get_difficulty() -> Difficulty:
		return current_difficulty

	func is_easy_selected() -> bool:
		return current_difficulty == Difficulty.EASY

	func is_normal_selected() -> bool:
		return current_difficulty == Difficulty.NORMAL

	func is_hard_selected() -> bool:
		return current_difficulty == Difficulty.HARD

	func get_easy_button_text() -> String:
		return "Easy (Selected)" if is_easy_selected() else "Easy"

	func get_normal_button_text() -> String:
		return "Normal (Selected)" if is_normal_selected() else "Normal"

	func get_hard_button_text() -> String:
		return "Hard (Selected)" if is_hard_selected() else "Hard"

	func get_status_text() -> String:
		match current_difficulty:
			Difficulty.EASY:
				return "Easy mode: Enemies react slower"
			Difficulty.HARD:
				return "Hard mode: Enemies react when you look away"
			_:
				return "Normal mode: Classic gameplay"


# ============================================================================
# Mock Levels Menu
# ============================================================================


class MockLevelsMenu:
	const LEVELS: Dictionary = {
		"Building Level": "res://scenes/levels/BuildingLevel.tscn",
		"Test Tier": "res://scenes/levels/TestTier.tscn",
		"Tutorial": "res://scenes/levels/csharp/TestTier.tscn"
	}

	var current_scene_path: String = ""

	signal back_pressed

	func get_level_count() -> int:
		return LEVELS.size()

	func get_level_names() -> Array:
		return LEVELS.keys()

	func get_level_path(name: String) -> String:
		if name in LEVELS:
			return LEVELS[name]
		return ""

	func is_current_level(level_path: String) -> bool:
		return level_path == current_scene_path

	func get_button_text(level_name: String) -> String:
		var path := get_level_path(level_name)
		if is_current_level(path):
			return level_name + " (Current)"
		return level_name

	func should_disable_button(level_name: String) -> bool:
		var path := get_level_path(level_name)
		return is_current_level(path)


# ============================================================================
# Mock Armory Menu
# ============================================================================


class MockArmoryMenu:
	const WEAPONS: Dictionary = {
		"m16": {
			"name": "M16",
			"icon_path": "res://assets/sprites/weapons/m16_rifle.png",
			"unlocked": true,
			"description": "Standard assault rifle"
		},
		"ak47": {
			"name": "???",
			"icon_path": "",
			"unlocked": false,
			"description": "Coming soon"
		},
		"shotgun": {
			"name": "???",
			"icon_path": "",
			"unlocked": false,
			"description": "Coming soon"
		}
	}

	signal back_pressed

	func get_weapon_count() -> int:
		return WEAPONS.size()

	func get_weapon_ids() -> Array:
		return WEAPONS.keys()

	func get_weapon_data(weapon_id: String) -> Dictionary:
		if weapon_id in WEAPONS:
			return WEAPONS[weapon_id]
		return {}

	func is_weapon_unlocked(weapon_id: String) -> bool:
		if weapon_id in WEAPONS:
			return WEAPONS[weapon_id]["unlocked"]
		return false

	func get_unlocked_count() -> int:
		var count: int = 0
		for weapon_id in WEAPONS:
			if WEAPONS[weapon_id]["unlocked"]:
				count += 1
		return count

	func get_status_text() -> String:
		return "Unlocked: %d / %d" % [get_unlocked_count(), get_weapon_count()]


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


# ============================================================================
# Levels Menu Tests
# ============================================================================


var levels_menu: MockLevelsMenu


func test_levels_menu_has_levels() -> void:
	levels_menu = MockLevelsMenu.new()
	assert_true(levels_menu.get_level_count() > 0, "Should have at least one level")


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


func test_button_text_shows_current() -> void:
	levels_menu = MockLevelsMenu.new()
	levels_menu.current_scene_path = "res://scenes/levels/BuildingLevel.tscn"

	var text := levels_menu.get_button_text("Building Level")

	assert_eq(text, "Building Level (Current)", "Current level should show (Current)")


func test_button_text_normal_for_other() -> void:
	levels_menu = MockLevelsMenu.new()
	levels_menu.current_scene_path = "res://scenes/levels/BuildingLevel.tscn"

	var text := levels_menu.get_button_text("Test Tier")

	assert_eq(text, "Test Tier", "Other levels should have normal text")


func test_should_disable_current_level_button() -> void:
	levels_menu = MockLevelsMenu.new()
	levels_menu.current_scene_path = "res://scenes/levels/BuildingLevel.tscn"

	assert_true(levels_menu.should_disable_button("Building Level"),
		"Current level button should be disabled")
	assert_false(levels_menu.should_disable_button("Test Tier"),
		"Other level buttons should not be disabled")


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
	assert_false(armory_menu.is_weapon_unlocked("shotgun"), "Shotgun should be locked")


func test_armory_menu_unlocked_count() -> void:
	armory_menu = MockArmoryMenu.new()
	assert_eq(armory_menu.get_unlocked_count(), 1, "Should have 1 unlocked weapon")


func test_armory_menu_status_text() -> void:
	armory_menu = MockArmoryMenu.new()
	var status := armory_menu.get_status_text()
	assert_eq(status, "Unlocked: 1 / 3", "Status should show 1 of 3 unlocked")


func test_armory_menu_get_weapon_data() -> void:
	armory_menu = MockArmoryMenu.new()
	var data := armory_menu.get_weapon_data("m16")

	assert_eq(data["name"], "M16", "Should return correct weapon name")
	assert_eq(data["description"], "Standard assault rifle", "Should return correct description")
	assert_true(data["unlocked"], "Should show as unlocked")


func test_armory_menu_invalid_weapon() -> void:
	armory_menu = MockArmoryMenu.new()
	var data := armory_menu.get_weapon_data("invalid_weapon")

	assert_true(data.is_empty(), "Should return empty dictionary for invalid weapon")
	assert_false(armory_menu.is_weapon_unlocked("invalid_weapon"), "Invalid weapon should not be unlocked")
