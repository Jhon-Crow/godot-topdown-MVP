extends GutTest
## Unit tests for DifficultyMenu.
##
## Tests difficulty mode constants, Gothic font path, gradient colors,
## and difficulty selection logic using a mock class.


# ============================================================================
# Mock DifficultyMenu for Testing
# ============================================================================


class MockDifficultyMenu:
	## Path to the Gothic bitmap font file.
	const GOTHIC_FONT_PATH: String = "res://assets/fonts/gothic_bitmap.fnt"

	## Gradient colors for Power Fantasy text (Issue #1014).
	## Bright vibrant gradient from cyan through magenta to yellow.
	const POWER_FANTASY_GRADIENT_COLORS: Array[Color] = [
		Color(0.0, 1.0, 1.0),    # Cyan
		Color(0.5, 0.0, 1.0),    # Purple
		Color(1.0, 0.0, 1.0),    # Magenta
		Color(1.0, 0.5, 0.0),    # Orange
		Color(1.0, 1.0, 0.0),    # Yellow
	]

	## Semi-transparent background colour drawn over a settings row on hover.
	const ROW_HOVER_BG: Color = Color(1.0, 1.0, 1.0, 0.08)

	## Difficulty modes enumeration.
	enum Difficulty { POWER_FANTASY, EASY, NORMAL, HARD, BLACK_METAL }

	## Current difficulty.
	var current_difficulty: int = Difficulty.NORMAL

	## Signal tracking.
	var back_pressed_count: int = 0

	## First-launch mode flag (Issue #1734).
	var first_launch_mode: bool = false

	## Tracks whether difficulty_selected_first_launch was emitted (Issue #1734).
	var first_launch_signal_emitted: bool = false

	## Set difficulty.
	func set_difficulty(difficulty: int) -> void:
		current_difficulty = difficulty

	## Check difficulty mode.
	func is_power_fantasy_mode() -> bool:
		return current_difficulty == Difficulty.POWER_FANTASY

	func is_easy_mode() -> bool:
		return current_difficulty == Difficulty.EASY

	func is_normal_mode() -> bool:
		return current_difficulty == Difficulty.NORMAL

	func is_hard_mode() -> bool:
		return current_difficulty == Difficulty.HARD

	func is_black_metal_mode() -> bool:
		return current_difficulty == Difficulty.BLACK_METAL

	## Get all difficulty names.
	func get_all_difficulty_names() -> Array[String]:
		return ["power_fantasy", "easy", "normal", "hard", "black_metal"]

	## Press back.
	func press_back() -> void:
		back_pressed_count += 1

	## Tracks mouse mode changes (Issue #1734).
	## 0 = default, 1 = CONFINED (cursor shown), 2 = CONFINED_HIDDEN (cursor hidden).
	var mouse_mode_on_enter: int = 0
	var mouse_mode_on_exit: int = 0

	## Simulate entering first-launch mode (_ready logic) (Issue #1734).
	func simulate_enter_first_launch() -> void:
		if first_launch_mode:
			# Simulates: Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED)
			mouse_mode_on_enter = 1  # CONFINED = cursor visible

	## Simulate pressing a difficulty button in first-launch mode (Issue #1734).
	## Returns true if the signal would be emitted (i.e., first_launch_mode is set).
	func simulate_difficulty_press_first_launch(difficulty: int) -> bool:
		set_difficulty(difficulty)
		if first_launch_mode:
			# Simulates _finish_first_launch_selection():
			# Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
			mouse_mode_on_exit = 2  # CONFINED_HIDDEN = cursor hidden
			first_launch_signal_emitted = true
			return true
		return false

	## Whether the back button would be visible (Issue #1734).
	func is_back_button_visible() -> bool:
		return not first_launch_mode

	## Whether ESC can close the menu (Issue #1734).
	func can_close_with_esc() -> bool:
		return not first_launch_mode

	## Returns button text for a difficulty in the current mode (Issue #1734).
	## In first-launch mode no button shows "(Selected)" even if it matches current difficulty.
	func get_easy_button_text() -> String:
		if is_easy_mode() and not first_launch_mode:
			return "Easy (Selected)"
		return "Easy"

	func get_normal_button_text() -> String:
		if is_normal_mode() and not first_launch_mode:
			return "Normal (Selected)"
		return "Normal"


var menu: MockDifficultyMenu


# ============================================================================
# Mock GameManager for restart-on-difficulty-change tests (Issue #1432)
# ============================================================================


class MockGameManager:
	## Whether restart_scene was called.
	var restart_called: bool = false
	## Simulated player node (null means not in-game).
	var player = null

	func restart_scene() -> void:
		restart_called = true


## Helper: creates a MockDifficultyMenu wired to a MockGameManager
## and simulates what _restart_if_in_game() does.
## Returns a dictionary with "menu" and "game_manager" keys.
func _make_restart_harness(has_player: bool) -> Dictionary:
	var gm := MockGameManager.new()
	if has_player:
		gm.player = RefCounted.new()  # any non-null object acts as the player

	var dm := MockDifficultyMenu.new()

	return {"menu": dm, "game_manager": gm}


## Simulate _restart_if_in_game logic using the mock objects.
func _simulate_restart_if_in_game(gm: MockGameManager) -> void:
	if gm == null:
		return
	if gm.player == null:
		return
	# get_tree().paused = false  -- skipped in unit test (no scene tree)
	gm.restart_scene()


func before_each() -> void:
	menu = MockDifficultyMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# GOTHIC_FONT_PATH Constant Tests
# ============================================================================


func test_gothic_font_path_value() -> void:
	assert_eq(menu.GOTHIC_FONT_PATH, "res://assets/fonts/gothic_bitmap.fnt",
		"Gothic font path should point to the bitmap font file")


func test_gothic_font_path_is_res_path() -> void:
	assert_true(menu.GOTHIC_FONT_PATH.begins_with("res://"),
		"Gothic font path should be a Godot resource path")


func test_gothic_font_path_has_fnt_extension() -> void:
	assert_true(menu.GOTHIC_FONT_PATH.ends_with(".fnt"),
		"Gothic font path should have .fnt extension")


# ============================================================================
# Power Fantasy Gradient Color Tests
# ============================================================================


func test_gradient_color_count() -> void:
	assert_eq(menu.POWER_FANTASY_GRADIENT_COLORS.size(), 5,
		"Should have 5 gradient colors for Power Fantasy")


func test_gradient_first_color_is_cyan() -> void:
	var cyan := menu.POWER_FANTASY_GRADIENT_COLORS[0]
	assert_eq(cyan.r, 0.0, "Cyan red channel should be 0")
	assert_eq(cyan.g, 1.0, "Cyan green channel should be 1")
	assert_eq(cyan.b, 1.0, "Cyan blue channel should be 1")


func test_gradient_second_color_is_purple() -> void:
	var purple := menu.POWER_FANTASY_GRADIENT_COLORS[1]
	assert_eq(purple.r, 0.5, "Purple red channel should be 0.5")
	assert_eq(purple.g, 0.0, "Purple green channel should be 0")
	assert_eq(purple.b, 1.0, "Purple blue channel should be 1")


func test_gradient_third_color_is_magenta() -> void:
	var magenta := menu.POWER_FANTASY_GRADIENT_COLORS[2]
	assert_eq(magenta.r, 1.0, "Magenta red channel should be 1")
	assert_eq(magenta.g, 0.0, "Magenta green channel should be 0")
	assert_eq(magenta.b, 1.0, "Magenta blue channel should be 1")


func test_gradient_fourth_color_is_orange() -> void:
	var orange := menu.POWER_FANTASY_GRADIENT_COLORS[3]
	assert_eq(orange.r, 1.0, "Orange red channel should be 1")
	assert_eq(orange.g, 0.5, "Orange green channel should be 0.5")
	assert_eq(orange.b, 0.0, "Orange blue channel should be 0")


func test_gradient_fifth_color_is_yellow() -> void:
	var yellow := menu.POWER_FANTASY_GRADIENT_COLORS[4]
	assert_eq(yellow.r, 1.0, "Yellow red channel should be 1")
	assert_eq(yellow.g, 1.0, "Yellow green channel should be 1")
	assert_eq(yellow.b, 0.0, "Yellow blue channel should be 0")


# ============================================================================
# Difficulty Mode Count Tests
# ============================================================================


func test_difficulty_mode_count() -> void:
	var names := menu.get_all_difficulty_names()
	assert_eq(names.size(), 5,
		"Should have 5 difficulty modes")


func test_difficulty_modes_include_power_fantasy() -> void:
	var names := menu.get_all_difficulty_names()
	assert_true(names.has("power_fantasy"),
		"Should include power_fantasy mode")


func test_difficulty_modes_include_easy() -> void:
	var names := menu.get_all_difficulty_names()
	assert_true(names.has("easy"),
		"Should include easy mode")


func test_difficulty_modes_include_normal() -> void:
	var names := menu.get_all_difficulty_names()
	assert_true(names.has("normal"),
		"Should include normal mode")


func test_difficulty_modes_include_hard() -> void:
	var names := menu.get_all_difficulty_names()
	assert_true(names.has("hard"),
		"Should include hard mode")


func test_difficulty_modes_include_black_metal() -> void:
	var names := menu.get_all_difficulty_names()
	assert_true(names.has("black_metal"),
		"Should include black_metal mode")


# ============================================================================
# Difficulty Selection Tests
# ============================================================================


func test_default_difficulty_is_normal() -> void:
	assert_true(menu.is_normal_mode(),
		"Default difficulty should be normal")


func test_set_power_fantasy() -> void:
	menu.set_difficulty(MockDifficultyMenu.Difficulty.POWER_FANTASY)

	assert_true(menu.is_power_fantasy_mode(),
		"Should be in Power Fantasy mode after setting")
	assert_false(menu.is_normal_mode(),
		"Should not be in Normal mode")


func test_set_black_metal() -> void:
	menu.set_difficulty(MockDifficultyMenu.Difficulty.BLACK_METAL)

	assert_true(menu.is_black_metal_mode(),
		"Should be in Black Metal mode after setting")


func test_set_easy() -> void:
	menu.set_difficulty(MockDifficultyMenu.Difficulty.EASY)

	assert_true(menu.is_easy_mode(),
		"Should be in Easy mode after setting")


func test_set_hard() -> void:
	menu.set_difficulty(MockDifficultyMenu.Difficulty.HARD)

	assert_true(menu.is_hard_mode(),
		"Should be in Hard mode after setting")


# ============================================================================
# ROW_HOVER_BG Tests
# ============================================================================


func test_row_hover_bg_color() -> void:
	assert_eq(menu.ROW_HOVER_BG, Color(1.0, 1.0, 1.0, 0.08),
		"ROW_HOVER_BG should be semi-transparent white")


# ============================================================================
# Back Button Tests
# ============================================================================


func test_back_button() -> void:
	menu.press_back()

	assert_eq(menu.back_pressed_count, 1,
		"Should track back press")


# ============================================================================
# Auto-restart on Difficulty Change Tests (Issue #1432)
# ============================================================================


func test_restart_is_triggered_when_player_exists() -> void:
	var harness := _make_restart_harness(true)
	var gm: MockGameManager = harness["game_manager"]

	_simulate_restart_if_in_game(gm)

	assert_true(gm.restart_called,
		"restart_scene should be called when a player is present (in-game)")


func test_restart_is_not_triggered_without_player() -> void:
	var harness := _make_restart_harness(false)
	var gm: MockGameManager = harness["game_manager"]

	_simulate_restart_if_in_game(gm)

	assert_false(gm.restart_called,
		"restart_scene should NOT be called when no player is present (main menu)")


func test_restart_is_not_triggered_without_game_manager() -> void:
	# Passing null game manager — should not crash and should not restart.
	_simulate_restart_if_in_game(null)
	# If we reach here without errors the test passes.
	assert_true(true, "Should handle null GameManager gracefully")


# ============================================================================
# First Launch Mode Tests (Issue #1734)
# ============================================================================


func test_first_launch_mode_defaults_to_false() -> void:
	assert_false(menu.first_launch_mode,
		"first_launch_mode should be false by default")


func test_back_button_visible_in_normal_mode() -> void:
	menu.first_launch_mode = false

	assert_true(menu.is_back_button_visible(),
		"Back button should be visible in normal (non-first-launch) mode")


func test_back_button_hidden_in_first_launch_mode() -> void:
	menu.first_launch_mode = true

	assert_false(menu.is_back_button_visible(),
		"Back button should be hidden in first-launch mode so player must choose")


func test_esc_closes_menu_in_normal_mode() -> void:
	menu.first_launch_mode = false

	assert_true(menu.can_close_with_esc(),
		"ESC should be able to close the menu in normal mode")


func test_esc_blocked_in_first_launch_mode() -> void:
	menu.first_launch_mode = true

	assert_false(menu.can_close_with_esc(),
		"ESC should be blocked in first-launch mode")


func test_difficulty_press_emits_first_launch_signal() -> void:
	menu.first_launch_mode = true

	var emitted := menu.simulate_difficulty_press_first_launch(MockDifficultyMenu.Difficulty.EASY)

	assert_true(emitted,
		"Pressing a difficulty button in first-launch mode should emit difficulty_selected_first_launch")
	assert_true(menu.first_launch_signal_emitted,
		"first_launch_signal_emitted flag should be set after selection")


func test_difficulty_press_does_not_emit_first_launch_signal_in_normal_mode() -> void:
	menu.first_launch_mode = false

	var emitted := menu.simulate_difficulty_press_first_launch(MockDifficultyMenu.Difficulty.NORMAL)

	assert_false(emitted,
		"Pressing a difficulty button in normal mode should NOT emit difficulty_selected_first_launch")
	assert_false(menu.first_launch_signal_emitted,
		"first_launch_signal_emitted flag should remain false in normal mode")


func test_no_selected_text_on_easy_in_first_launch_mode() -> void:
	menu.first_launch_mode = true
	menu.set_difficulty(MockDifficultyMenu.Difficulty.EASY)

	assert_eq(menu.get_easy_button_text(), "Easy",
		"Easy button should not show '(Selected)' in first-launch mode")


func test_selected_text_shown_on_easy_in_normal_mode() -> void:
	menu.first_launch_mode = false
	menu.set_difficulty(MockDifficultyMenu.Difficulty.EASY)

	assert_eq(menu.get_easy_button_text(), "Easy (Selected)",
		"Easy button should show '(Selected)' when active in normal mode")


func test_no_selected_text_on_normal_in_first_launch_mode() -> void:
	menu.first_launch_mode = true
	# Normal is the default current_difficulty

	assert_eq(menu.get_normal_button_text(), "Normal",
		"Normal button should not show '(Selected)' in first-launch mode")


func test_first_launch_difficulty_selection_sets_difficulty() -> void:
	menu.first_launch_mode = true

	menu.simulate_difficulty_press_first_launch(MockDifficultyMenu.Difficulty.HARD)

	assert_true(menu.is_hard_mode(),
		"Difficulty should be set to HARD after selection in first-launch mode")


# ============================================================================
# Cursor / Mouse Mode Tests (Issue #1734)
# ============================================================================


func test_cursor_shown_on_first_launch_enter() -> void:
	menu.first_launch_mode = true
	menu.simulate_enter_first_launch()

	assert_eq(menu.mouse_mode_on_enter, 1,
		"Mouse mode should be set to CONFINED (cursor visible) when first-launch menu opens")


func test_cursor_not_changed_in_normal_mode_enter() -> void:
	menu.first_launch_mode = false
	menu.simulate_enter_first_launch()

	assert_eq(menu.mouse_mode_on_enter, 0,
		"Mouse mode should NOT be changed when opening menu in normal (pause) mode")


func test_cursor_hidden_after_first_launch_selection() -> void:
	menu.first_launch_mode = true
	menu.simulate_enter_first_launch()

	menu.simulate_difficulty_press_first_launch(MockDifficultyMenu.Difficulty.NORMAL)

	assert_eq(menu.mouse_mode_on_exit, 2,
		"Mouse mode should be restored to CONFINED_HIDDEN when first-launch selection is made")


func test_cursor_restored_regardless_of_difficulty_chosen() -> void:
	for diff in [MockDifficultyMenu.Difficulty.POWER_FANTASY,
			MockDifficultyMenu.Difficulty.EASY,
			MockDifficultyMenu.Difficulty.NORMAL,
			MockDifficultyMenu.Difficulty.HARD,
			MockDifficultyMenu.Difficulty.BLACK_METAL]:
		var m := MockDifficultyMenu.new()
		m.first_launch_mode = true
		m.simulate_enter_first_launch()
		m.simulate_difficulty_press_first_launch(diff)

		assert_eq(m.mouse_mode_on_exit, 2,
			"Mouse mode should be CONFINED_HIDDEN after choosing difficulty %d" % diff)
