extends GutTest
## Unit tests for UI menu scripts: controls_menu.gd, levels_menu.gd,
## difficulty_menu.gd, and pause_menu.gd.
##
## Tests the core logic of each menu using mock classes that mirror the
## testable functionality without requiring Godot scene tree dependencies.


# ============================================================================
# Mock Controls Menu
# ============================================================================


class MockControlsMenu:
	## Mirrors the key binding management logic from controls_menu.gd.
	## Focuses on _pending_bindings, conflict detection, apply/cancel.

	## Currently selected action for rebinding. Empty means not rebinding.
	var _rebinding_action: String = ""

	## Temporary storage for new bindings before applying.
	## Maps action name -> key scancode (int).
	var _pending_bindings: Dictionary = {}

	## Flag to track if there are unsaved changes.
	var _has_changes: bool = false

	## Simulated current action bindings (action -> keycode).
	var _current_bindings: Dictionary = {}

	## Track status messages for verification.
	var status_text: String = ""

	signal back_pressed

	func start_rebinding(action_name: String) -> void:
		_rebinding_action = action_name
		status_text = "Press a key for " + action_name + " (Escape to cancel)"

	func cancel_rebinding() -> void:
		if _rebinding_action.is_empty():
			return
		_rebinding_action = ""
		status_text = ""

	func is_rebinding() -> bool:
		return not _rebinding_action.is_empty()

	func get_rebinding_action() -> String:
		return _rebinding_action

	## Check if a key conflicts with another action's binding.
	## Returns the name of the conflicting action or empty string.
	func _check_key_conflict(action: String, key: int) -> String:
		# Check current bindings
		for bound_action in _current_bindings:
			if bound_action == action:
				continue
			if _current_bindings[bound_action] == key:
				return bound_action
		# Also check pending bindings (they override current)
		for pending_action in _pending_bindings:
			if pending_action == action:
				continue
			if _pending_bindings[pending_action] == key:
				return pending_action
		return ""

	## Add a pending binding for an action.
	func add_pending_binding(action: String, key: int) -> void:
		_pending_bindings[action] = key
		_has_changes = true
		_rebinding_action = ""
		status_text = "Changes pending. Click Apply to save."

	## Returns true if there are unsaved pending changes.
	func has_pending_changes() -> bool:
		return _pending_bindings.size() > 0

	## Apply all pending bindings to current bindings.
	func apply_bindings() -> void:
		for action_name in _pending_bindings:
			var key = _pending_bindings[action_name]
			if key != null:
				_current_bindings[action_name] = key
			else:
				_current_bindings.erase(action_name)
		_pending_bindings.clear()
		_has_changes = false
		status_text = "Settings saved!"

	## Cancel all pending changes.
	func cancel_pending() -> void:
		_pending_bindings.clear()
		_has_changes = false
		_rebinding_action = ""
		status_text = ""

	## Get the binding for an action (pending overrides current).
	func get_effective_binding(action: String) -> int:
		if action in _pending_bindings:
			return _pending_bindings[action]
		if action in _current_bindings:
			return _current_bindings[action]
		return -1

	## Clear a conflicting action by setting its pending binding to null.
	func clear_conflicting_action(conflicting_action: String) -> void:
		_pending_bindings[conflicting_action] = null
		_has_changes = true


# ============================================================================
# Mock Levels Menu
# ============================================================================


class MockLevelsMenu:
	## Mirrors the card-based level selection logic from levels_menu.gd.

	## Level metadata matching the actual levels_menu.gd LEVELS constant.
	const LEVELS: Array[Dictionary] = [
		{
			"name": "Building Level",
			"path": "res://scenes/levels/BuildingLevel.tscn",
			"description": "Hotline Miami style building with interconnected rooms and corridors.",
			"preview_color": Color(0.35, 0.25, 0.2, 1.0),
			"preview_accent": Color(0.6, 0.4, 0.3, 1.0),
			"enemy_count": 10,
			"map_size": "2400x2000"
		},
		{
			"name": "Polygon",
			"name_ru": "Полигон",
			"path": "res://scenes/levels/TestTier.tscn",
			"description": "Open training ground for testing weapons and practicing combat skills.",
			"preview_color": Color(0.2, 0.3, 0.2, 1.0),
			"preview_accent": Color(0.35, 0.5, 0.35, 1.0),
			"enemy_count": 5,
			"map_size": "1280x720"
		},
		{
			"name": "Castle",
			"name_ru": "Замок",
			"path": "res://scenes/levels/CastleLevel.tscn",
			"description": "Medieval fortress assault across a massive oval-shaped courtyard.",
			"preview_color": Color(0.25, 0.25, 0.35, 1.0),
			"preview_accent": Color(0.4, 0.4, 0.55, 1.0),
			"enemy_count": 15,
			"map_size": "6000x2560"
		},
		{
			"name": "Tutorial",
			"name_ru": "Обучение",
			"path": "res://scenes/levels/csharp/TestTier.tscn",
			"description": "Step-by-step training: movement, shooting, bolt-action, scope, grenades.",
			"preview_color": Color(0.2, 0.25, 0.3, 1.0),
			"preview_accent": Color(0.3, 0.45, 0.55, 1.0),
			"enemy_count": 4,
			"map_size": "1280x720"
		}
	]

	## Difficulty names in display order.
	const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard", "Power Fantasy"]

	## Card dimensions.
	const CARD_WIDTH: float = 220.0
	const CARD_HEIGHT: float = 290.0

	## Currently playing level path.
	var current_scene_path: String = ""

	## Track which card is selected (for highlighting).
	var _selected_card_index: int = -1

	signal back_pressed

	func get_level_count() -> int:
		return LEVELS.size()

	func get_level_names() -> Array:
		var names: Array = []
		for level in LEVELS:
			names.append(level["name"])
		return names

	func get_level_path(level_name: String) -> String:
		for level in LEVELS:
			if level["name"] == level_name:
				return level["path"]
		return ""

	func get_level_data(level_name: String) -> Dictionary:
		for level in LEVELS:
			if level["name"] == level_name:
				return level
		return {}

	func get_level_data_by_index(index: int) -> Dictionary:
		if index >= 0 and index < LEVELS.size():
			return LEVELS[index]
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

	func get_map_size(level_name: String) -> String:
		var data := get_level_data(level_name)
		return data.get("map_size", "")

	func select_card(index: int) -> void:
		if index >= 0 and index < LEVELS.size():
			_selected_card_index = index

	func get_selected_card_index() -> int:
		return _selected_card_index

	func has_russian_name(level_name: String) -> bool:
		var data := get_level_data(level_name)
		return data.has("name_ru")

	## Get rank color based on rank string (mirrors _get_rank_color in levels_menu.gd).
	func get_rank_color(rank: String) -> Color:
		match rank:
			"S":
				return Color(1.0, 0.85, 0.0, 1.0)
			"A+":
				return Color(0.3, 1.0, 0.3, 1.0)
			"A":
				return Color(0.4, 0.9, 0.4, 1.0)
			"B":
				return Color(0.5, 0.8, 1.0, 1.0)
			"C":
				return Color(0.8, 0.8, 0.8, 1.0)
			"D":
				return Color(0.8, 0.5, 0.3, 1.0)
			"F":
				return Color(0.8, 0.3, 0.3, 1.0)
			_:
				return Color(0.7, 0.7, 0.7, 1.0)


# ============================================================================
# Mock Difficulty Menu
# ============================================================================


class MockDifficultyMenu:
	## Mirrors the difficulty selection logic from difficulty_menu.gd.

	## Difficulty modes matching difficulty_menu.gd button structure.
	const VALID_MODES: Array[String] = ["power_fantasy", "easy", "normal", "hard"]

	## Current difficulty mode.
	var current_mode: String = "normal"

	## Night mode toggle state.
	var night_mode_enabled: bool = false

	signal back_pressed

	func set_mode(mode: String) -> void:
		if mode in VALID_MODES:
			current_mode = mode

	func get_mode() -> String:
		return current_mode

	func set_night_mode(enabled: bool) -> void:
		night_mode_enabled = enabled

	func is_night_mode_enabled() -> bool:
		return night_mode_enabled

	func is_power_fantasy_selected() -> bool:
		return current_mode == "power_fantasy"

	func is_easy_selected() -> bool:
		return current_mode == "easy"

	func is_normal_selected() -> bool:
		return current_mode == "normal"

	func is_hard_selected() -> bool:
		return current_mode == "hard"

	## Returns description string for each difficulty mode.
	func _get_difficulty_description(mode: String) -> String:
		match mode:
			"power_fantasy":
				return "Power Fantasy: 10 HP, 3x ammo, blue lasers"
			"easy":
				return "Easy mode: Enemies react slower"
			"normal":
				return "Normal mode: Classic gameplay"
			"hard":
				return "Hard mode: Enemies react when you look away"
			_:
				return ""

	## Build the full status text (with optional night mode suffix).
	func get_status_text() -> String:
		var base_text := _get_difficulty_description(current_mode)
		if night_mode_enabled:
			base_text += " | Night Mode ON"
		return base_text

	## Get button text for a mode (shows "(Selected)" suffix when active).
	func get_button_text(mode: String) -> String:
		var display_name: String = ""
		match mode:
			"power_fantasy":
				display_name = "Power Fantasy"
			"easy":
				display_name = "Easy"
			"normal":
				display_name = "Normal"
			"hard":
				display_name = "Hard"
			_:
				return ""
		if current_mode == mode:
			return display_name + " (Selected)"
		return display_name

	## Check if a mode string is valid.
	func is_valid_mode(mode: String) -> bool:
		return mode in VALID_MODES


# ============================================================================
# Mock Pause Menu
# ============================================================================


class MockPauseMenu:
	## Mirrors the pause state tracking and navigation from pause_menu.gd.

	## Whether the game is currently paused.
	var _is_paused: bool = false

	## Visibility state.
	var visible: bool = false

	## Sub-menu visibility states.
	var _controls_menu_visible: bool = false
	var _difficulty_menu_visible: bool = false
	var _levels_menu_visible: bool = false
	var _armory_menu_visible: bool = false
	var _experimental_menu_visible: bool = false

	## Menu navigation stack for back button.
	var _navigation_stack: Array[String] = []

	## Main menu container visibility.
	var _main_menu_visible: bool = true

	func toggle_pause() -> void:
		if _is_paused:
			resume_game()
		else:
			pause_game()

	func is_paused() -> bool:
		return _is_paused

	func pause_game() -> void:
		_is_paused = true
		visible = true
		# Close any open submenus and restore main menu container
		_controls_menu_visible = false
		_difficulty_menu_visible = false
		_levels_menu_visible = false
		_armory_menu_visible = false
		_experimental_menu_visible = false
		_main_menu_visible = true

	func resume_game() -> void:
		_is_paused = false
		visible = false
		# Close all submenus
		_controls_menu_visible = false
		_difficulty_menu_visible = false
		_levels_menu_visible = false
		_armory_menu_visible = false
		_experimental_menu_visible = false

	func navigate_to(submenu: String) -> void:
		_navigation_stack.append("main")
		_main_menu_visible = false
		match submenu:
			"controls":
				_controls_menu_visible = true
			"difficulty":
				_difficulty_menu_visible = true
			"levels":
				_levels_menu_visible = true
			"armory":
				_armory_menu_visible = true
			"experimental":
				_experimental_menu_visible = true

	func navigate_back() -> void:
		# Close current submenu
		_controls_menu_visible = false
		_difficulty_menu_visible = false
		_levels_menu_visible = false
		_armory_menu_visible = false
		_experimental_menu_visible = false
		# Restore previous menu
		if _navigation_stack.size() > 0:
			_navigation_stack.pop_back()
		_main_menu_visible = true

	func get_navigation_depth() -> int:
		return _navigation_stack.size()

	func is_submenu_open() -> bool:
		return (
			_controls_menu_visible or
			_difficulty_menu_visible or
			_levels_menu_visible or
			_armory_menu_visible or
			_experimental_menu_visible
		)


# ============================================================================
# Test Variables
# ============================================================================


var controls_menu: MockControlsMenu
var levels_menu: MockLevelsMenu
var difficulty_menu: MockDifficultyMenu
var pause_menu: MockPauseMenu


# ============================================================================
# Setup / Teardown
# ============================================================================


func before_each() -> void:
	controls_menu = MockControlsMenu.new()
	levels_menu = MockLevelsMenu.new()
	difficulty_menu = MockDifficultyMenu.new()
	pause_menu = MockPauseMenu.new()


func after_each() -> void:
	controls_menu = null
	levels_menu = null
	difficulty_menu = null
	pause_menu = null


# ============================================================================
# Controls Menu: Initial State Tests
# ============================================================================


func test_controls_menu_not_rebinding_initially() -> void:
	assert_false(controls_menu.is_rebinding(),
		"Should not be rebinding initially")


func test_controls_menu_no_pending_changes_initially() -> void:
	assert_false(controls_menu.has_pending_changes(),
		"Should have no pending changes initially")


func test_controls_menu_rebinding_action_empty_initially() -> void:
	assert_eq(controls_menu.get_rebinding_action(), "",
		"Rebinding action should be empty initially")


func test_controls_menu_status_text_empty_initially() -> void:
	assert_eq(controls_menu.status_text, "",
		"Status text should be empty initially")


func test_controls_menu_has_changes_flag_false_initially() -> void:
	assert_false(controls_menu._has_changes,
		"_has_changes flag should be false initially")


# ============================================================================
# Controls Menu: Rebinding State Tests
# ============================================================================


func test_start_rebinding_sets_action() -> void:
	controls_menu.start_rebinding("move_up")

	assert_true(controls_menu.is_rebinding(),
		"Should be rebinding after start")
	assert_eq(controls_menu.get_rebinding_action(), "move_up",
		"Rebinding action should be 'move_up'")


func test_start_rebinding_updates_status_text() -> void:
	controls_menu.start_rebinding("shoot")

	assert_true(controls_menu.status_text.contains("shoot"),
		"Status text should mention the action being rebound")
	assert_true(controls_menu.status_text.contains("Escape"),
		"Status text should mention Escape to cancel")


func test_cancel_rebinding_clears_action() -> void:
	controls_menu.start_rebinding("move_up")
	controls_menu.cancel_rebinding()

	assert_false(controls_menu.is_rebinding(),
		"Should not be rebinding after cancel")
	assert_eq(controls_menu.get_rebinding_action(), "",
		"Rebinding action should be cleared")


func test_cancel_rebinding_clears_status_text() -> void:
	controls_menu.start_rebinding("move_up")
	controls_menu.cancel_rebinding()

	assert_eq(controls_menu.status_text, "",
		"Status text should be cleared after cancel")


func test_cancel_rebinding_when_not_rebinding_is_safe() -> void:
	controls_menu.cancel_rebinding()

	assert_false(controls_menu.is_rebinding(),
		"Should remain not rebinding when cancel called without start")


func test_start_rebinding_different_action_overrides() -> void:
	controls_menu.start_rebinding("move_up")
	controls_menu.start_rebinding("move_down")

	assert_eq(controls_menu.get_rebinding_action(), "move_down",
		"Second rebinding call should override the first")


# ============================================================================
# Controls Menu: Pending Bindings Tests
# ============================================================================


func test_add_pending_binding_stores_key() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)

	assert_true(controls_menu.has_pending_changes(),
		"Should have pending changes after adding a binding")
	assert_eq(controls_menu._pending_bindings["move_up"], KEY_W,
		"Pending binding should store the key scancode")


func test_add_pending_binding_clears_rebinding_state() -> void:
	controls_menu.start_rebinding("move_up")
	controls_menu.add_pending_binding("move_up", KEY_W)

	assert_false(controls_menu.is_rebinding(),
		"Adding a pending binding should clear the rebinding state")


func test_add_pending_binding_updates_status_text() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)

	assert_true(controls_menu.status_text.contains("pending"),
		"Status text should indicate pending changes")


func test_multiple_pending_bindings() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)
	controls_menu.add_pending_binding("move_down", KEY_S)
	controls_menu.add_pending_binding("move_left", KEY_A)
	controls_menu.add_pending_binding("move_right", KEY_D)

	assert_eq(controls_menu._pending_bindings.size(), 4,
		"Should have 4 pending bindings")
	assert_true(controls_menu.has_pending_changes(),
		"Should have pending changes with 4 bindings")


func test_pending_binding_overrides_same_action() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)
	controls_menu.add_pending_binding("move_up", KEY_UP)

	assert_eq(controls_menu._pending_bindings["move_up"], KEY_UP,
		"Later binding should override earlier one for same action")
	assert_eq(controls_menu._pending_bindings.size(), 1,
		"Should still have only 1 pending binding for the same action")


func test_has_pending_changes_reflects_dictionary_size() -> void:
	assert_false(controls_menu.has_pending_changes(),
		"Empty pending bindings means no pending changes")

	controls_menu.add_pending_binding("shoot", KEY_SPACE)

	assert_true(controls_menu.has_pending_changes(),
		"Non-empty pending bindings means pending changes exist")


# ============================================================================
# Controls Menu: Key Conflict Detection Tests
# ============================================================================


func test_no_conflict_when_key_unused() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W
	controls_menu._current_bindings["move_down"] = KEY_S

	var conflict := controls_menu._check_key_conflict("move_left", KEY_A)

	assert_eq(conflict, "",
		"Should find no conflict when key is not used by any other action")


func test_conflict_detected_with_current_binding() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W
	controls_menu._current_bindings["move_down"] = KEY_S

	var conflict := controls_menu._check_key_conflict("move_left", KEY_W)

	assert_eq(conflict, "move_up",
		"Should detect conflict with move_up which uses KEY_W")


func test_no_conflict_with_own_action() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W

	var conflict := controls_menu._check_key_conflict("move_up", KEY_W)

	assert_eq(conflict, "",
		"Should not conflict with the same action being rebound")


func test_conflict_detected_with_pending_binding() -> void:
	controls_menu.add_pending_binding("shoot", KEY_SPACE)

	var conflict := controls_menu._check_key_conflict("pause", KEY_SPACE)

	assert_eq(conflict, "shoot",
		"Should detect conflict with pending binding for 'shoot'")


func test_no_conflict_with_own_pending_binding() -> void:
	controls_menu.add_pending_binding("shoot", KEY_SPACE)

	var conflict := controls_menu._check_key_conflict("shoot", KEY_SPACE)

	assert_eq(conflict, "",
		"Should not conflict with own pending binding")


func test_conflict_detection_multiple_actions() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W
	controls_menu._current_bindings["move_down"] = KEY_S
	controls_menu._current_bindings["move_left"] = KEY_A
	controls_menu._current_bindings["move_right"] = KEY_D

	var conflict := controls_menu._check_key_conflict("shoot", KEY_A)

	assert_eq(conflict, "move_left",
		"Should detect conflict with move_left for KEY_A")


func test_conflict_returns_first_conflicting_action() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W

	var conflict := controls_menu._check_key_conflict("move_down", KEY_W)

	assert_false(conflict.is_empty(),
		"Should return a non-empty conflict string")


func test_conflict_detection_empty_bindings() -> void:
	var conflict := controls_menu._check_key_conflict("move_up", KEY_W)

	assert_eq(conflict, "",
		"Should find no conflict when no bindings exist")


# ============================================================================
# Controls Menu: Apply Bindings Tests
# ============================================================================


func test_apply_bindings_moves_to_current() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)
	controls_menu.add_pending_binding("move_down", KEY_S)
	controls_menu.apply_bindings()

	assert_eq(controls_menu._current_bindings["move_up"], KEY_W,
		"move_up should be applied to current bindings")
	assert_eq(controls_menu._current_bindings["move_down"], KEY_S,
		"move_down should be applied to current bindings")


func test_apply_bindings_clears_pending() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)
	controls_menu.apply_bindings()

	assert_false(controls_menu.has_pending_changes(),
		"Pending changes should be cleared after apply")
	assert_eq(controls_menu._pending_bindings.size(), 0,
		"Pending bindings dictionary should be empty after apply")


func test_apply_bindings_clears_has_changes_flag() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)
	controls_menu.apply_bindings()

	assert_false(controls_menu._has_changes,
		"_has_changes flag should be false after apply")


func test_apply_bindings_updates_status() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)
	controls_menu.apply_bindings()

	assert_eq(controls_menu.status_text, "Settings saved!",
		"Status should indicate settings were saved")


func test_apply_null_binding_erases_action() -> void:
	controls_menu._current_bindings["shoot"] = KEY_SPACE
	controls_menu._pending_bindings["shoot"] = null
	controls_menu._has_changes = true
	controls_menu.apply_bindings()

	assert_false(controls_menu._current_bindings.has("shoot"),
		"Null pending binding should erase the action from current bindings")


func test_apply_preserves_non_pending_bindings() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W
	controls_menu._current_bindings["move_down"] = KEY_S
	controls_menu.add_pending_binding("move_left", KEY_A)
	controls_menu.apply_bindings()

	assert_eq(controls_menu._current_bindings["move_up"], KEY_W,
		"Non-pending bindings should be preserved")
	assert_eq(controls_menu._current_bindings["move_down"], KEY_S,
		"Non-pending bindings should be preserved")
	assert_eq(controls_menu._current_bindings["move_left"], KEY_A,
		"New pending binding should be applied")


func test_apply_overrides_existing_binding() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W
	controls_menu.add_pending_binding("move_up", KEY_UP)
	controls_menu.apply_bindings()

	assert_eq(controls_menu._current_bindings["move_up"], KEY_UP,
		"Applied pending binding should override the existing current binding")


# ============================================================================
# Controls Menu: Cancel Pending Tests
# ============================================================================


func test_cancel_pending_clears_all_pending() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)
	controls_menu.add_pending_binding("move_down", KEY_S)
	controls_menu.cancel_pending()

	assert_false(controls_menu.has_pending_changes(),
		"Should have no pending changes after cancel")
	assert_eq(controls_menu._pending_bindings.size(), 0,
		"Pending bindings should be empty after cancel")


func test_cancel_pending_clears_has_changes_flag() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)
	controls_menu.cancel_pending()

	assert_false(controls_menu._has_changes,
		"_has_changes flag should be false after cancel")


func test_cancel_pending_clears_rebinding_state() -> void:
	controls_menu.start_rebinding("move_up")
	controls_menu.cancel_pending()

	assert_false(controls_menu.is_rebinding(),
		"Should not be rebinding after cancel_pending")


func test_cancel_pending_does_not_affect_current_bindings() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W
	controls_menu.add_pending_binding("move_up", KEY_UP)
	controls_menu.cancel_pending()

	assert_eq(controls_menu._current_bindings["move_up"], KEY_W,
		"Current bindings should remain unchanged after cancel")


func test_cancel_pending_clears_status_text() -> void:
	controls_menu.add_pending_binding("move_up", KEY_W)
	controls_menu.cancel_pending()

	assert_eq(controls_menu.status_text, "",
		"Status text should be cleared after cancel")


# ============================================================================
# Controls Menu: Clear Conflicting Action Tests
# ============================================================================


func test_clear_conflicting_action_sets_null_pending() -> void:
	controls_menu.clear_conflicting_action("move_up")

	assert_true(controls_menu._pending_bindings.has("move_up"),
		"Should have a pending entry for the conflicting action")
	assert_eq(controls_menu._pending_bindings["move_up"], null,
		"Conflicting action pending binding should be null")


func test_clear_conflicting_action_marks_has_changes() -> void:
	controls_menu.clear_conflicting_action("move_up")

	assert_true(controls_menu._has_changes,
		"Clearing a conflicting action should mark has_changes")


# ============================================================================
# Controls Menu: Effective Binding Tests
# ============================================================================


func test_effective_binding_returns_pending_over_current() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W
	controls_menu.add_pending_binding("move_up", KEY_UP)

	assert_eq(controls_menu.get_effective_binding("move_up"), KEY_UP,
		"Pending binding should take precedence over current binding")


func test_effective_binding_returns_current_when_no_pending() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W

	assert_eq(controls_menu.get_effective_binding("move_up"), KEY_W,
		"Should return current binding when no pending exists")


func test_effective_binding_returns_negative_one_when_unset() -> void:
	assert_eq(controls_menu.get_effective_binding("unknown_action"), -1,
		"Should return -1 for actions with no binding")


# ============================================================================
# Controls Menu: Full Workflow Tests
# ============================================================================


func test_full_rebind_workflow() -> void:
	# Setup initial bindings
	controls_menu._current_bindings["move_up"] = KEY_W
	controls_menu._current_bindings["move_down"] = KEY_S

	# Start rebinding
	controls_menu.start_rebinding("move_up")
	assert_true(controls_menu.is_rebinding(), "Should be rebinding")

	# Check for conflict (no conflict with KEY_UP)
	var conflict := controls_menu._check_key_conflict("move_up", KEY_UP)
	assert_eq(conflict, "", "KEY_UP should not conflict")

	# Add the binding
	controls_menu.add_pending_binding("move_up", KEY_UP)
	assert_true(controls_menu.has_pending_changes(), "Should have pending changes")
	assert_false(controls_menu.is_rebinding(), "Should stop rebinding after adding binding")

	# Apply
	controls_menu.apply_bindings()
	assert_eq(controls_menu._current_bindings["move_up"], KEY_UP,
		"move_up should now be KEY_UP")
	assert_false(controls_menu.has_pending_changes(), "No pending changes after apply")


func test_full_rebind_with_conflict_workflow() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W
	controls_menu._current_bindings["move_down"] = KEY_S

	# Try to bind move_left to KEY_W (conflicts with move_up)
	controls_menu.start_rebinding("move_left")
	var conflict := controls_menu._check_key_conflict("move_left", KEY_W)
	assert_eq(conflict, "move_up", "Should detect conflict with move_up")

	# User confirms conflict resolution: clear the conflicting action
	controls_menu.clear_conflicting_action("move_up")
	controls_menu.add_pending_binding("move_left", KEY_W)

	# Apply both changes
	controls_menu.apply_bindings()
	assert_false(controls_menu._current_bindings.has("move_up"),
		"move_up should be erased (null pending)")
	assert_eq(controls_menu._current_bindings["move_left"], KEY_W,
		"move_left should now be KEY_W")


func test_cancel_workflow() -> void:
	controls_menu._current_bindings["move_up"] = KEY_W
	controls_menu.add_pending_binding("move_up", KEY_UP)

	# Cancel instead of apply
	controls_menu.cancel_pending()

	assert_eq(controls_menu._current_bindings["move_up"], KEY_W,
		"Original binding should be unchanged after cancel")
	assert_false(controls_menu.has_pending_changes(),
		"No pending changes after cancel")


# ============================================================================
# Levels Menu: Level Data Structure Validation Tests
# ============================================================================


func test_levels_menu_has_four_levels() -> void:
	assert_eq(levels_menu.get_level_count(), 4,
		"Should have exactly 4 levels")


func test_levels_menu_level_names() -> void:
	var names := levels_menu.get_level_names()

	assert_has(names, "Building Level", "Should contain Building Level")
	assert_has(names, "Polygon", "Should contain Polygon")
	assert_has(names, "Castle", "Should contain Castle")
	assert_has(names, "Tutorial", "Should contain Tutorial")


func test_levels_all_have_required_fields() -> void:
	var required_fields := ["name", "path", "description", "enemy_count", "map_size"]
	for i in range(levels_menu.LEVELS.size()):
		var level := levels_menu.get_level_data_by_index(i)
		for field in required_fields:
			assert_true(level.has(field),
				"Level '%s' should have field '%s'" % [level.get("name", "unknown"), field])


func test_levels_all_have_preview_colors() -> void:
	for i in range(levels_menu.LEVELS.size()):
		var level := levels_menu.get_level_data_by_index(i)
		assert_true(level.has("preview_color"),
			"Level '%s' should have preview_color" % level["name"])
		assert_true(level.has("preview_accent"),
			"Level '%s' should have preview_accent" % level["name"])


func test_levels_all_paths_are_tscn() -> void:
	for i in range(levels_menu.LEVELS.size()):
		var level := levels_menu.get_level_data_by_index(i)
		assert_true(level["path"].ends_with(".tscn"),
			"Level path should end with .tscn: %s" % level["path"])


func test_levels_all_paths_start_with_res() -> void:
	for i in range(levels_menu.LEVELS.size()):
		var level := levels_menu.get_level_data_by_index(i)
		assert_true(level["path"].begins_with("res://"),
			"Level path should start with res://: %s" % level["path"])


func test_levels_all_have_nonempty_descriptions() -> void:
	for i in range(levels_menu.LEVELS.size()):
		var level := levels_menu.get_level_data_by_index(i)
		assert_true(level["description"].length() > 0,
			"Level '%s' description should not be empty" % level["name"])


func test_levels_all_enemy_counts_non_negative() -> void:
	for i in range(levels_menu.LEVELS.size()):
		var level := levels_menu.get_level_data_by_index(i)
		assert_true(level["enemy_count"] >= 0,
			"Level '%s' enemy count should be non-negative" % level["name"])


# ============================================================================
# Levels Menu: Level Path Lookup Tests
# ============================================================================


func test_get_level_path_building() -> void:
	assert_eq(levels_menu.get_level_path("Building Level"),
		"res://scenes/levels/BuildingLevel.tscn",
		"Building Level path should be correct")


func test_get_level_path_polygon() -> void:
	assert_eq(levels_menu.get_level_path("Polygon"),
		"res://scenes/levels/TestTier.tscn",
		"Polygon path should be correct")


func test_get_level_path_castle() -> void:
	assert_eq(levels_menu.get_level_path("Castle"),
		"res://scenes/levels/CastleLevel.tscn",
		"Castle path should be correct")


func test_get_level_path_tutorial() -> void:
	assert_eq(levels_menu.get_level_path("Tutorial"),
		"res://scenes/levels/csharp/TestTier.tscn",
		"Tutorial path should be correct")


func test_get_level_path_invalid_returns_empty() -> void:
	assert_eq(levels_menu.get_level_path("NonExistent"),
		"",
		"Invalid level name should return empty string")


func test_get_level_data_invalid_returns_empty_dict() -> void:
	var data := levels_menu.get_level_data("NonExistent")

	assert_true(data.is_empty(),
		"Invalid level name should return empty dictionary")


# ============================================================================
# Levels Menu: Card Selection State Tests
# ============================================================================


func test_card_selection_initially_none() -> void:
	assert_eq(levels_menu.get_selected_card_index(), -1,
		"No card should be selected initially")


func test_select_card_valid_index() -> void:
	levels_menu.select_card(0)

	assert_eq(levels_menu.get_selected_card_index(), 0,
		"Card at index 0 should be selected")


func test_select_card_last_index() -> void:
	levels_menu.select_card(3)

	assert_eq(levels_menu.get_selected_card_index(), 3,
		"Card at last index should be selected")


func test_select_card_invalid_negative_index() -> void:
	levels_menu.select_card(-1)

	assert_eq(levels_menu.get_selected_card_index(), -1,
		"Negative index should not change selection")


func test_select_card_invalid_out_of_bounds() -> void:
	levels_menu.select_card(99)

	assert_eq(levels_menu.get_selected_card_index(), -1,
		"Out-of-bounds index should not change selection")


func test_select_card_overrides_previous() -> void:
	levels_menu.select_card(0)
	levels_menu.select_card(2)

	assert_eq(levels_menu.get_selected_card_index(), 2,
		"Latest card selection should override previous")


# ============================================================================
# Levels Menu: Current Level Detection Tests
# ============================================================================


func test_is_current_level_matches() -> void:
	levels_menu.current_scene_path = "res://scenes/levels/BuildingLevel.tscn"

	assert_true(levels_menu.is_current_level("res://scenes/levels/BuildingLevel.tscn"),
		"Should detect the current level")


func test_is_current_level_no_match() -> void:
	levels_menu.current_scene_path = "res://scenes/levels/BuildingLevel.tscn"

	assert_false(levels_menu.is_current_level("res://scenes/levels/TestTier.tscn"),
		"Should not match a different level")


func test_is_current_level_empty_path() -> void:
	levels_menu.current_scene_path = ""

	assert_false(levels_menu.is_current_level("res://scenes/levels/BuildingLevel.tscn"),
		"Should not match when current path is empty")


func test_should_disable_current_level_card() -> void:
	levels_menu.current_scene_path = "res://scenes/levels/CastleLevel.tscn"

	assert_true(levels_menu.should_disable_card("Castle"),
		"Current level card should be disabled")
	assert_false(levels_menu.should_disable_card("Building Level"),
		"Other level cards should not be disabled")
	assert_false(levels_menu.should_disable_card("Polygon"),
		"Other level cards should not be disabled")


# ============================================================================
# Levels Menu: Display Name / Localization Tests
# ============================================================================


func test_display_name_with_russian_name() -> void:
	assert_eq(levels_menu.get_display_name("Polygon"), "Полигон",
		"Polygon should display as Полигон")


func test_display_name_castle_russian() -> void:
	assert_eq(levels_menu.get_display_name("Castle"), "Замок",
		"Castle should display as Замок")


func test_display_name_tutorial_russian() -> void:
	assert_eq(levels_menu.get_display_name("Tutorial"), "Обучение",
		"Tutorial should display as Обучение")


func test_display_name_fallback_english() -> void:
	assert_eq(levels_menu.get_display_name("Building Level"), "Building Level",
		"Building Level has no Russian name, should use English")


func test_has_russian_name_polygon() -> void:
	assert_true(levels_menu.has_russian_name("Polygon"),
		"Polygon should have a Russian name")


func test_has_russian_name_building_level() -> void:
	assert_false(levels_menu.has_russian_name("Building Level"),
		"Building Level should not have a Russian name")


# ============================================================================
# Levels Menu: Enemy Count and Map Size Tests
# ============================================================================


func test_enemy_count_building_level() -> void:
	assert_eq(levels_menu.get_enemy_count("Building Level"), 10,
		"Building Level should have 10 enemies")


func test_enemy_count_polygon() -> void:
	assert_eq(levels_menu.get_enemy_count("Polygon"), 5,
		"Polygon should have 5 enemies")


func test_enemy_count_castle() -> void:
	assert_eq(levels_menu.get_enemy_count("Castle"), 15,
		"Castle should have 15 enemies")


func test_enemy_count_tutorial() -> void:
	assert_eq(levels_menu.get_enemy_count("Tutorial"), 4,
		"Tutorial should have 4 enemies")


func test_enemy_count_invalid_level() -> void:
	assert_eq(levels_menu.get_enemy_count("NonExistent"), 0,
		"Invalid level should return 0 enemies")


func test_map_size_building_level() -> void:
	assert_eq(levels_menu.get_map_size("Building Level"), "2400x2000",
		"Building Level map size should be 2400x2000")


func test_map_size_castle() -> void:
	assert_eq(levels_menu.get_map_size("Castle"), "6000x2560",
		"Castle map size should be 6000x2560")


func test_map_size_polygon() -> void:
	assert_eq(levels_menu.get_map_size("Polygon"), "1280x720",
		"Polygon map size should be 1280x720")


# ============================================================================
# Levels Menu: Rank Color Tests
# ============================================================================


func test_rank_color_s_is_gold() -> void:
	var color := levels_menu.get_rank_color("S")

	assert_eq(color, Color(1.0, 0.85, 0.0, 1.0),
		"S rank should be gold")


func test_rank_color_a_plus_is_bright_green() -> void:
	var color := levels_menu.get_rank_color("A+")

	assert_eq(color, Color(0.3, 1.0, 0.3, 1.0),
		"A+ rank should be bright green")


func test_rank_color_f_is_red() -> void:
	var color := levels_menu.get_rank_color("F")

	assert_eq(color, Color(0.8, 0.3, 0.3, 1.0),
		"F rank should be red")


func test_rank_color_unknown_is_gray() -> void:
	var color := levels_menu.get_rank_color("Z")

	assert_eq(color, Color(0.7, 0.7, 0.7, 1.0),
		"Unknown rank should be gray")


func test_rank_color_empty_is_gray() -> void:
	var color := levels_menu.get_rank_color("")

	assert_eq(color, Color(0.7, 0.7, 0.7, 1.0),
		"Empty rank should be gray")


# ============================================================================
# Levels Menu: Difficulty Names Constant Tests
# ============================================================================


func test_difficulty_names_count() -> void:
	assert_eq(levels_menu.DIFFICULTY_NAMES.size(), 4,
		"Should have 4 difficulty names")


func test_difficulty_names_contain_expected() -> void:
	assert_has(levels_menu.DIFFICULTY_NAMES, "Easy", "Should contain Easy")
	assert_has(levels_menu.DIFFICULTY_NAMES, "Normal", "Should contain Normal")
	assert_has(levels_menu.DIFFICULTY_NAMES, "Hard", "Should contain Hard")
	assert_has(levels_menu.DIFFICULTY_NAMES, "Power Fantasy", "Should contain Power Fantasy")


# ============================================================================
# Levels Menu: Card Dimensions Tests
# ============================================================================


func test_card_width() -> void:
	assert_eq(levels_menu.CARD_WIDTH, 220.0,
		"Card width should be 220.0")


func test_card_height() -> void:
	assert_eq(levels_menu.CARD_HEIGHT, 290.0,
		"Card height should be 290.0")


# ============================================================================
# Difficulty Menu: Initial State Tests
# ============================================================================


func test_difficulty_menu_default_is_normal() -> void:
	assert_true(difficulty_menu.is_normal_selected(),
		"Normal should be selected by default")
	assert_eq(difficulty_menu.get_mode(), "normal",
		"Default mode should be 'normal'")


func test_difficulty_menu_night_mode_off_initially() -> void:
	assert_false(difficulty_menu.is_night_mode_enabled(),
		"Night mode should be disabled by default")


# ============================================================================
# Difficulty Menu: Mode Selection Tests
# ============================================================================


func test_set_mode_power_fantasy() -> void:
	difficulty_menu.set_mode("power_fantasy")

	assert_true(difficulty_menu.is_power_fantasy_selected(),
		"Power Fantasy should be selected")
	assert_false(difficulty_menu.is_easy_selected(),
		"Easy should not be selected")
	assert_false(difficulty_menu.is_normal_selected(),
		"Normal should not be selected")
	assert_false(difficulty_menu.is_hard_selected(),
		"Hard should not be selected")


func test_set_mode_easy() -> void:
	difficulty_menu.set_mode("easy")

	assert_true(difficulty_menu.is_easy_selected(),
		"Easy should be selected")
	assert_false(difficulty_menu.is_power_fantasy_selected(),
		"Power Fantasy should not be selected")
	assert_false(difficulty_menu.is_normal_selected(),
		"Normal should not be selected")
	assert_false(difficulty_menu.is_hard_selected(),
		"Hard should not be selected")


func test_set_mode_hard() -> void:
	difficulty_menu.set_mode("hard")

	assert_true(difficulty_menu.is_hard_selected(),
		"Hard should be selected")


func test_set_mode_normal() -> void:
	difficulty_menu.set_mode("easy")
	difficulty_menu.set_mode("normal")

	assert_true(difficulty_menu.is_normal_selected(),
		"Normal should be selected after switching back")


func test_set_invalid_mode_ignored() -> void:
	difficulty_menu.set_mode("invalid_mode")

	assert_eq(difficulty_menu.get_mode(), "normal",
		"Invalid mode should be ignored, keeping current mode")


func test_set_empty_mode_ignored() -> void:
	difficulty_menu.set_mode("")

	assert_eq(difficulty_menu.get_mode(), "normal",
		"Empty mode should be ignored, keeping current mode")


func test_is_valid_mode_all_modes() -> void:
	assert_true(difficulty_menu.is_valid_mode("power_fantasy"),
		"power_fantasy should be valid")
	assert_true(difficulty_menu.is_valid_mode("easy"),
		"easy should be valid")
	assert_true(difficulty_menu.is_valid_mode("normal"),
		"normal should be valid")
	assert_true(difficulty_menu.is_valid_mode("hard"),
		"hard should be valid")


func test_is_valid_mode_invalid() -> void:
	assert_false(difficulty_menu.is_valid_mode("extreme"),
		"extreme should not be a valid mode")
	assert_false(difficulty_menu.is_valid_mode(""),
		"Empty string should not be a valid mode")


# ============================================================================
# Difficulty Menu: Description Tests
# ============================================================================


func test_description_power_fantasy() -> void:
	var desc := difficulty_menu._get_difficulty_description("power_fantasy")

	assert_eq(desc, "Power Fantasy: 10 HP, 3x ammo, blue lasers",
		"Power Fantasy description should mention HP, ammo, and lasers")


func test_description_easy() -> void:
	var desc := difficulty_menu._get_difficulty_description("easy")

	assert_eq(desc, "Easy mode: Enemies react slower",
		"Easy description should mention slower enemy reactions")


func test_description_normal() -> void:
	var desc := difficulty_menu._get_difficulty_description("normal")

	assert_eq(desc, "Normal mode: Classic gameplay",
		"Normal description should mention classic gameplay")


func test_description_hard() -> void:
	var desc := difficulty_menu._get_difficulty_description("hard")

	assert_eq(desc, "Hard mode: Enemies react when you look away",
		"Hard description should mention enemies reacting when looking away")


func test_description_invalid_mode() -> void:
	var desc := difficulty_menu._get_difficulty_description("unknown")

	assert_eq(desc, "",
		"Invalid mode should return empty description")


func test_all_valid_modes_have_descriptions() -> void:
	for mode in difficulty_menu.VALID_MODES:
		var desc := difficulty_menu._get_difficulty_description(mode)
		assert_true(desc.length() > 0,
			"Mode '%s' should have a non-empty description" % mode)


# ============================================================================
# Difficulty Menu: Night Mode Toggle Tests
# ============================================================================


func test_night_mode_enable() -> void:
	difficulty_menu.set_night_mode(true)

	assert_true(difficulty_menu.is_night_mode_enabled(),
		"Night mode should be enabled")


func test_night_mode_disable() -> void:
	difficulty_menu.set_night_mode(true)
	difficulty_menu.set_night_mode(false)

	assert_false(difficulty_menu.is_night_mode_enabled(),
		"Night mode should be disabled")


func test_night_mode_toggle_multiple_times() -> void:
	difficulty_menu.set_night_mode(true)
	assert_true(difficulty_menu.is_night_mode_enabled(), "Should be enabled")
	difficulty_menu.set_night_mode(false)
	assert_false(difficulty_menu.is_night_mode_enabled(), "Should be disabled")
	difficulty_menu.set_night_mode(true)
	assert_true(difficulty_menu.is_night_mode_enabled(), "Should be enabled again")


func test_night_mode_independent_of_difficulty() -> void:
	difficulty_menu.set_night_mode(true)
	difficulty_menu.set_mode("hard")

	assert_true(difficulty_menu.is_night_mode_enabled(),
		"Night mode should remain enabled after changing difficulty")
	assert_true(difficulty_menu.is_hard_selected(),
		"Hard should be selected")


func test_difficulty_change_does_not_affect_night_mode() -> void:
	difficulty_menu.set_night_mode(true)
	difficulty_menu.set_mode("easy")
	difficulty_menu.set_mode("power_fantasy")
	difficulty_menu.set_mode("normal")

	assert_true(difficulty_menu.is_night_mode_enabled(),
		"Night mode should persist through multiple difficulty changes")


# ============================================================================
# Difficulty Menu: Status Text Tests
# ============================================================================


func test_status_text_normal() -> void:
	assert_eq(difficulty_menu.get_status_text(),
		"Normal mode: Classic gameplay",
		"Status text should show normal mode description")


func test_status_text_easy() -> void:
	difficulty_menu.set_mode("easy")

	assert_eq(difficulty_menu.get_status_text(),
		"Easy mode: Enemies react slower",
		"Status text should show easy mode description")


func test_status_text_hard() -> void:
	difficulty_menu.set_mode("hard")

	assert_eq(difficulty_menu.get_status_text(),
		"Hard mode: Enemies react when you look away",
		"Status text should show hard mode description")


func test_status_text_power_fantasy() -> void:
	difficulty_menu.set_mode("power_fantasy")

	assert_eq(difficulty_menu.get_status_text(),
		"Power Fantasy: 10 HP, 3x ammo, blue lasers",
		"Status text should show power fantasy description")


func test_status_text_with_night_mode() -> void:
	difficulty_menu.set_night_mode(true)

	assert_eq(difficulty_menu.get_status_text(),
		"Normal mode: Classic gameplay | Night Mode ON",
		"Status text should append night mode indicator")


func test_status_text_power_fantasy_with_night_mode() -> void:
	difficulty_menu.set_mode("power_fantasy")
	difficulty_menu.set_night_mode(true)

	assert_eq(difficulty_menu.get_status_text(),
		"Power Fantasy: 10 HP, 3x ammo, blue lasers | Night Mode ON",
		"Power fantasy status should include night mode suffix")


func test_status_text_night_mode_off_no_suffix() -> void:
	difficulty_menu.set_night_mode(false)

	assert_false(difficulty_menu.get_status_text().contains("Night Mode"),
		"Status text should not contain night mode when disabled")


# ============================================================================
# Difficulty Menu: Button Text Tests
# ============================================================================


func test_button_text_normal_selected() -> void:
	assert_eq(difficulty_menu.get_button_text("normal"), "Normal (Selected)",
		"Normal button should show (Selected)")
	assert_eq(difficulty_menu.get_button_text("easy"), "Easy",
		"Easy button should not show (Selected)")
	assert_eq(difficulty_menu.get_button_text("hard"), "Hard",
		"Hard button should not show (Selected)")
	assert_eq(difficulty_menu.get_button_text("power_fantasy"), "Power Fantasy",
		"Power Fantasy button should not show (Selected)")


func test_button_text_easy_selected() -> void:
	difficulty_menu.set_mode("easy")

	assert_eq(difficulty_menu.get_button_text("easy"), "Easy (Selected)",
		"Easy button should show (Selected)")
	assert_eq(difficulty_menu.get_button_text("normal"), "Normal",
		"Normal button should not show (Selected)")


func test_button_text_hard_selected() -> void:
	difficulty_menu.set_mode("hard")

	assert_eq(difficulty_menu.get_button_text("hard"), "Hard (Selected)",
		"Hard button should show (Selected)")


func test_button_text_power_fantasy_selected() -> void:
	difficulty_menu.set_mode("power_fantasy")

	assert_eq(difficulty_menu.get_button_text("power_fantasy"),
		"Power Fantasy (Selected)",
		"Power Fantasy button should show (Selected)")


func test_button_text_invalid_mode() -> void:
	assert_eq(difficulty_menu.get_button_text("invalid"), "",
		"Invalid mode should return empty button text")


# ============================================================================
# Pause Menu: Initial State Tests
# ============================================================================


func test_pause_menu_not_paused_initially() -> void:
	assert_false(pause_menu.is_paused(),
		"Game should not be paused initially")


func test_pause_menu_not_visible_initially() -> void:
	assert_false(pause_menu.visible,
		"Pause menu should not be visible initially")


func test_pause_menu_no_submenu_open_initially() -> void:
	assert_false(pause_menu.is_submenu_open(),
		"No submenu should be open initially")


func test_pause_menu_navigation_depth_zero_initially() -> void:
	assert_eq(pause_menu.get_navigation_depth(), 0,
		"Navigation depth should be 0 initially")


# ============================================================================
# Pause Menu: Toggle Pause Tests
# ============================================================================


func test_toggle_pause_pauses_game() -> void:
	pause_menu.toggle_pause()

	assert_true(pause_menu.is_paused(),
		"Game should be paused after toggle")
	assert_true(pause_menu.visible,
		"Menu should be visible after pause")


func test_toggle_pause_twice_unpauses() -> void:
	pause_menu.toggle_pause()
	pause_menu.toggle_pause()

	assert_false(pause_menu.is_paused(),
		"Game should not be paused after double toggle")
	assert_false(pause_menu.visible,
		"Menu should not be visible after double toggle")


func test_toggle_pause_three_times_paused() -> void:
	pause_menu.toggle_pause()
	pause_menu.toggle_pause()
	pause_menu.toggle_pause()

	assert_true(pause_menu.is_paused(),
		"Game should be paused after triple toggle")


func test_pause_game_directly() -> void:
	pause_menu.pause_game()

	assert_true(pause_menu.is_paused(),
		"Game should be paused after pause_game()")
	assert_true(pause_menu.visible,
		"Menu should be visible after pause_game()")


func test_resume_game_directly() -> void:
	pause_menu.pause_game()
	pause_menu.resume_game()

	assert_false(pause_menu.is_paused(),
		"Game should not be paused after resume_game()")
	assert_false(pause_menu.visible,
		"Menu should not be visible after resume_game()")


# ============================================================================
# Pause Menu: Submenu Navigation Tests
# ============================================================================


func test_navigate_to_controls_menu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("controls")

	assert_true(pause_menu._controls_menu_visible,
		"Controls menu should be visible")
	assert_false(pause_menu._main_menu_visible,
		"Main menu should be hidden when submenu is open")
	assert_true(pause_menu.is_submenu_open(),
		"Should report submenu as open")


func test_navigate_to_difficulty_menu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("difficulty")

	assert_true(pause_menu._difficulty_menu_visible,
		"Difficulty menu should be visible")
	assert_false(pause_menu._main_menu_visible,
		"Main menu should be hidden")


func test_navigate_to_levels_menu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("levels")

	assert_true(pause_menu._levels_menu_visible,
		"Levels menu should be visible")


func test_navigate_to_armory_menu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("armory")

	assert_true(pause_menu._armory_menu_visible,
		"Armory menu should be visible")


func test_navigate_to_experimental_menu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("experimental")

	assert_true(pause_menu._experimental_menu_visible,
		"Experimental menu should be visible")


func test_navigation_increases_depth() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("controls")

	assert_eq(pause_menu.get_navigation_depth(), 1,
		"Navigation depth should be 1 after opening submenu")


# ============================================================================
# Pause Menu: Back Navigation Tests
# ============================================================================


func test_navigate_back_from_controls() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("controls")
	pause_menu.navigate_back()

	assert_false(pause_menu._controls_menu_visible,
		"Controls menu should be hidden after back")
	assert_true(pause_menu._main_menu_visible,
		"Main menu should be visible after back")


func test_navigate_back_from_difficulty() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("difficulty")
	pause_menu.navigate_back()

	assert_false(pause_menu._difficulty_menu_visible,
		"Difficulty menu should be hidden after back")
	assert_true(pause_menu._main_menu_visible,
		"Main menu should be visible after back")


func test_navigate_back_decreases_depth() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("controls")
	pause_menu.navigate_back()

	assert_eq(pause_menu.get_navigation_depth(), 0,
		"Navigation depth should be 0 after navigating back")


func test_navigate_back_no_submenu_open() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("levels")
	pause_menu.navigate_back()

	assert_false(pause_menu.is_submenu_open(),
		"No submenu should be open after back")


# ============================================================================
# Pause Menu: Resume Closes All Submenus Tests
# ============================================================================


func test_resume_closes_controls_submenu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("controls")
	pause_menu.resume_game()

	assert_false(pause_menu._controls_menu_visible,
		"Controls menu should close on resume")
	assert_false(pause_menu.is_paused(),
		"Game should not be paused after resume")


func test_resume_closes_difficulty_submenu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("difficulty")
	pause_menu.resume_game()

	assert_false(pause_menu._difficulty_menu_visible,
		"Difficulty menu should close on resume")


func test_resume_closes_levels_submenu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("levels")
	pause_menu.resume_game()

	assert_false(pause_menu._levels_menu_visible,
		"Levels menu should close on resume")


func test_resume_closes_armory_submenu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("armory")
	pause_menu.resume_game()

	assert_false(pause_menu._armory_menu_visible,
		"Armory menu should close on resume")


func test_resume_closes_experimental_submenu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("experimental")
	pause_menu.resume_game()

	assert_false(pause_menu._experimental_menu_visible,
		"Experimental menu should close on resume")


func test_resume_closes_all_submenus_at_once() -> void:
	pause_menu.pause_game()
	# Simulate multiple submenus open (shouldn't normally happen but test cleanup)
	pause_menu._controls_menu_visible = true
	pause_menu._difficulty_menu_visible = true
	pause_menu._levels_menu_visible = true
	pause_menu._armory_menu_visible = true
	pause_menu._experimental_menu_visible = true

	pause_menu.resume_game()

	assert_false(pause_menu._controls_menu_visible, "Controls should close")
	assert_false(pause_menu._difficulty_menu_visible, "Difficulty should close")
	assert_false(pause_menu._levels_menu_visible, "Levels should close")
	assert_false(pause_menu._armory_menu_visible, "Armory should close")
	assert_false(pause_menu._experimental_menu_visible, "Experimental should close")


# ============================================================================
# Pause Menu: Re-pause Resets Submenu State Tests
# ============================================================================


func test_repause_closes_submenus() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("controls")
	pause_menu.resume_game()
	pause_menu.pause_game()

	assert_false(pause_menu._controls_menu_visible,
		"Controls submenu should not be visible after re-pause")
	assert_true(pause_menu._main_menu_visible,
		"Main menu should be visible after re-pause")


func test_repause_shows_main_menu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("difficulty")
	# Simulate that main menu was hidden by navigation
	pause_menu._main_menu_visible = false
	pause_menu.resume_game()
	pause_menu.pause_game()

	assert_true(pause_menu._main_menu_visible,
		"Main menu container should be restored on re-pause")


# ============================================================================
# Pause Menu: Only One Submenu Visible Tests
# ============================================================================


func test_navigating_opens_only_target_submenu() -> void:
	pause_menu.pause_game()
	pause_menu.navigate_to("controls")

	assert_true(pause_menu._controls_menu_visible, "Controls should be visible")
	assert_false(pause_menu._difficulty_menu_visible, "Difficulty should not be visible")
	assert_false(pause_menu._levels_menu_visible, "Levels should not be visible")
	assert_false(pause_menu._armory_menu_visible, "Armory should not be visible")
	assert_false(pause_menu._experimental_menu_visible, "Experimental should not be visible")


# ============================================================================
# Pause Menu: Full Workflow Tests
# ============================================================================


func test_full_pause_navigate_back_resume_workflow() -> void:
	# Pause
	pause_menu.toggle_pause()
	assert_true(pause_menu.is_paused(), "Should be paused")
	assert_true(pause_menu.visible, "Should be visible")

	# Navigate to controls
	pause_menu.navigate_to("controls")
	assert_true(pause_menu._controls_menu_visible, "Controls open")
	assert_false(pause_menu._main_menu_visible, "Main hidden")

	# Navigate back
	pause_menu.navigate_back()
	assert_false(pause_menu._controls_menu_visible, "Controls closed")
	assert_true(pause_menu._main_menu_visible, "Main visible again")

	# Resume
	pause_menu.toggle_pause()
	assert_false(pause_menu.is_paused(), "Should not be paused")
	assert_false(pause_menu.visible, "Should not be visible")


func test_pause_navigate_to_multiple_submenus_sequentially() -> void:
	pause_menu.pause_game()

	# Open controls, then go back
	pause_menu.navigate_to("controls")
	assert_true(pause_menu._controls_menu_visible, "Controls should be visible")
	pause_menu.navigate_back()
	assert_false(pause_menu._controls_menu_visible, "Controls should be hidden")

	# Open difficulty, then go back
	pause_menu.navigate_to("difficulty")
	assert_true(pause_menu._difficulty_menu_visible, "Difficulty should be visible")
	pause_menu.navigate_back()
	assert_false(pause_menu._difficulty_menu_visible, "Difficulty should be hidden")

	# Open levels, then go back
	pause_menu.navigate_to("levels")
	assert_true(pause_menu._levels_menu_visible, "Levels should be visible")
	pause_menu.navigate_back()
	assert_false(pause_menu._levels_menu_visible, "Levels should be hidden")

	# Main menu should be visible throughout
	assert_true(pause_menu._main_menu_visible, "Main menu should be visible at the end")
