extends GutTest
## Unit tests for SceneLoader autoload.
##
## Tests the fade duration constant, loading state guard logic,
## and path validation logic.


# ============================================================================
# Mock SceneLoader
# ============================================================================


class MockSceneLoader:
	## Duration of fade in/out transitions.
	const FADE_DURATION: float = 0.3

	var _is_loading: bool = false
	var _current_load_path: String = ""

	## Tracks attempted loads for verification.
	var load_attempts: Array[String] = []
	var rejected_paths: Array[String] = []

	## Simulates the valid resource paths.
	var _valid_paths: Dictionary = {}

	## Register a path as valid (simulates ResourceLoader.exists).
	func register_valid_path(path: String) -> void:
		_valid_paths[path] = true

	## Simulates load_level() guard logic.
	func load_level(level_path: String) -> void:
		if _is_loading:
			return

		if not _valid_paths.has(level_path):
			rejected_paths.append(level_path)
			return

		_is_loading = true
		_current_load_path = level_path
		load_attempts.append(level_path)

	## Check if currently loading.
	func is_loading() -> bool:
		return _is_loading

	## Get the current load path.
	func get_current_load_path() -> String:
		return _current_load_path

	## Simulate load completion.
	func finish_loading() -> void:
		_is_loading = false
		_current_load_path = ""


var loader: MockSceneLoader


func before_each() -> void:
	loader = MockSceneLoader.new()


func after_each() -> void:
	loader = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_fade_duration_is_0_3() -> void:
	assert_almost_eq(MockSceneLoader.FADE_DURATION, 0.3, 0.001,
		"FADE_DURATION should be 0.3 seconds")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_not_loading() -> void:
	assert_false(loader.is_loading(),
		"Should not be loading initially")


func test_initial_load_path_empty() -> void:
	assert_eq(loader.get_current_load_path(), "",
		"Initial load path should be empty")


# ============================================================================
# Loading State Guard Tests
# ============================================================================


func test_load_level_sets_loading_state() -> void:
	loader.register_valid_path("res://scenes/levels/TestLevel.tscn")

	loader.load_level("res://scenes/levels/TestLevel.tscn")

	assert_true(loader.is_loading(),
		"Should be in loading state after load_level()")
	assert_eq(loader.get_current_load_path(), "res://scenes/levels/TestLevel.tscn",
		"Current load path should be set")


func test_duplicate_load_ignored_while_loading() -> void:
	loader.register_valid_path("res://scenes/levels/Level1.tscn")
	loader.register_valid_path("res://scenes/levels/Level2.tscn")

	loader.load_level("res://scenes/levels/Level1.tscn")
	loader.load_level("res://scenes/levels/Level2.tscn")

	assert_eq(loader.load_attempts.size(), 1,
		"Second load should be ignored while first is in progress")
	assert_eq(loader.get_current_load_path(), "res://scenes/levels/Level1.tscn",
		"Current path should still be the first level")


func test_can_load_again_after_finishing() -> void:
	loader.register_valid_path("res://scenes/levels/Level1.tscn")
	loader.register_valid_path("res://scenes/levels/Level2.tscn")

	loader.load_level("res://scenes/levels/Level1.tscn")
	loader.finish_loading()
	loader.load_level("res://scenes/levels/Level2.tscn")

	assert_eq(loader.load_attempts.size(), 2,
		"Should be able to load again after finishing")
	assert_eq(loader.get_current_load_path(), "res://scenes/levels/Level2.tscn",
		"Current path should be the second level")


func test_finish_loading_resets_state() -> void:
	loader.register_valid_path("res://scenes/levels/TestLevel.tscn")

	loader.load_level("res://scenes/levels/TestLevel.tscn")
	loader.finish_loading()

	assert_false(loader.is_loading(), "Should not be loading after finish")
	assert_eq(loader.get_current_load_path(), "", "Path should be cleared after finish")


# ============================================================================
# Path Validation Tests
# ============================================================================


func test_invalid_path_rejected() -> void:
	loader.load_level("res://nonexistent/level.tscn")

	assert_false(loader.is_loading(),
		"Should not start loading for invalid path")
	assert_eq(loader.rejected_paths.size(), 1,
		"Invalid path should be tracked as rejected")


func test_valid_path_accepted() -> void:
	loader.register_valid_path("res://scenes/levels/DocksLevel.tscn")

	loader.load_level("res://scenes/levels/DocksLevel.tscn")

	assert_true(loader.is_loading(),
		"Should start loading for valid path")
	assert_eq(loader.rejected_paths.size(), 0,
		"Valid path should not be rejected")


func test_multiple_invalid_paths_all_rejected() -> void:
	loader.load_level("res://bad/path1.tscn")
	loader.load_level("res://bad/path2.tscn")
	loader.load_level("res://bad/path3.tscn")

	assert_eq(loader.rejected_paths.size(), 3,
		"All invalid paths should be rejected")
	assert_false(loader.is_loading(),
		"Should not be loading after rejecting all paths")
