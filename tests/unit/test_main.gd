extends GutTest
## Unit tests for the main scene script.
##
## Tests that the main script follows the expected Node2D pattern
## using a mock class.
##
## Note: Main.tscn is NOT the startup scene — the project's run/main_scene is
## LabyrinthLevel.tscn. First-launch difficulty selection (Issue #1734) lives in
## PersistManager, which runs as an autoload on every startup.


# ============================================================================
# Mock Main for Testing
# ============================================================================


class MockMain:
	## The base type that main.gd extends.
	const EXTENDS_TYPE: String = "Node2D"

	## Simulated ready state.
	var is_ready: bool = false

	## Ready message.
	var ready_message: String = ""

	## Called when the node enters the scene tree.
	func ready() -> void:
		is_ready = true
		ready_message = "Godot Top-Down Template loaded successfully!"


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
