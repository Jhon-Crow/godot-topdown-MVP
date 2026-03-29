extends GutTest
## Unit tests for the main scene script.
##
## Tests that the main script follows the expected Node2D pattern
## using a mock class.


# ============================================================================
# Mock Main for Testing
# ============================================================================


class MockMain:
	## The base type that main.gd extends.
	const EXTENDS_TYPE: String = "Node2D"

	## Path constant for the DifficultyMenu scene (Issue #1734).
	const DIFFICULTY_MENU_SCENE_PATH: String = "res://scenes/ui/DifficultyMenu.tscn"

	## Simulated ready state.
	var is_ready: bool = false

	## Ready message.
	var ready_message: String = ""

	## Simulated first-launch menu reference (Issue #1734).
	var _first_launch_menu: Object = null

	## Whether _show_first_launch_difficulty_menu was called (Issue #1734).
	var first_launch_menu_shown: bool = false

	## Called when the node enters the scene tree.
	func ready(is_first_launch: bool = false) -> void:
		is_ready = true
		ready_message = "Godot Top-Down Template loaded successfully!"
		if is_first_launch:
			_show_first_launch_difficulty_menu()

	## Simulate showing the first-launch difficulty menu (Issue #1734).
	func _show_first_launch_difficulty_menu() -> void:
		first_launch_menu_shown = true
		_first_launch_menu = RefCounted.new()  # stand-in for the menu node

	## Simulate the player selecting a difficulty (Issue #1734).
	func _on_first_launch_difficulty_selected() -> void:
		_first_launch_menu = null


var main: MockMain


func before_each() -> void:
	main = MockMain.new()


func after_each() -> void:
	main = null


# ============================================================================
# Base Type Tests
# ============================================================================


func test_extends_node2d() -> void:
	assert_eq(main.EXTENDS_TYPE, "Node2D",
		"Main script should extend Node2D")


# ============================================================================
# Ready State Tests
# ============================================================================


func test_not_ready_initially() -> void:
	assert_false(main.is_ready,
		"Should not be ready before _ready is called")


func test_ready_sets_flag() -> void:
	main.ready()

	assert_true(main.is_ready,
		"Should be ready after _ready is called")


func test_ready_message() -> void:
	main.ready()

	assert_eq(main.ready_message, "Godot Top-Down Template loaded successfully!",
		"Ready message should match the expected print output")


func test_ready_message_not_empty_after_ready() -> void:
	main.ready()

	assert_false(main.ready_message.is_empty(),
		"Ready message should not be empty after _ready")


# ============================================================================
# First Launch Tests (Issue #1734)
# ============================================================================


func test_difficulty_menu_scene_path_constant() -> void:
	assert_eq(main.DIFFICULTY_MENU_SCENE_PATH, "res://scenes/ui/DifficultyMenu.tscn",
		"DIFFICULTY_MENU_SCENE_PATH should point to the correct scene")


func test_no_first_launch_menu_initially() -> void:
	assert_null(main._first_launch_menu,
		"No first-launch menu should exist before _ready is called")


func test_first_launch_menu_shown_when_is_first_launch() -> void:
	main.ready(true)  # Simulate first launch

	assert_true(main.first_launch_menu_shown,
		"First-launch difficulty menu should be shown on first launch")
	assert_not_null(main._first_launch_menu,
		"First-launch menu reference should be set after showing")


func test_first_launch_menu_not_shown_on_subsequent_launch() -> void:
	main.ready(false)  # Not a first launch

	assert_false(main.first_launch_menu_shown,
		"First-launch difficulty menu should NOT be shown on subsequent launches")
	assert_null(main._first_launch_menu,
		"First-launch menu reference should remain null on subsequent launches")


func test_first_launch_menu_freed_after_difficulty_selected() -> void:
	main.ready(true)  # First launch shows menu
	assert_not_null(main._first_launch_menu, "Menu should exist before selection")

	main._on_first_launch_difficulty_selected()

	assert_null(main._first_launch_menu,
		"First-launch menu should be freed after a difficulty is selected")
