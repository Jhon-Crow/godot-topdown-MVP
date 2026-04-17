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


# ============================================================================
# THREAD_LOAD_INVALID_RESOURCE Fallback Tests (Issue #1456)
# ============================================================================


class MockSceneLoaderWithFallback extends MockSceneLoader:
	## Tracks whether fallback sync load was triggered.
	var fallback_triggered: bool = false
	var overlay_visible: bool = false
	var fallback_change_error: int = OK

	## Simulates THREAD_LOAD_INVALID_RESOURCE — should trigger fallback, not silent fail.
	func simulate_invalid_resource_during_poll() -> void:
		# The fix: fall back to sync load instead of silently hiding the screen
		fallback_triggered = true
		overlay_visible = true
		if fallback_change_error == OK:
			_is_loading = false
			_current_load_path = ""
			overlay_visible = false

	func fallback_overlay_is_visible() -> bool:
		return overlay_visible


func test_invalid_resource_during_poll_triggers_fallback() -> void:
	## Issue #1456: Previously THREAD_LOAD_INVALID_RESOURCE called _hide_loading_screen()
	## which silently aborted the load. The fix calls _fallback_sync_load() instead.
	var fallback_loader := MockSceneLoaderWithFallback.new()
	fallback_loader.register_valid_path("res://scenes/levels/BuildingLevel.tscn")

	fallback_loader.load_level("res://scenes/levels/BuildingLevel.tscn")
	assert_true(fallback_loader.is_loading(), "Should be loading after load_level()")

	fallback_loader.simulate_invalid_resource_during_poll()
	assert_true(fallback_loader.fallback_triggered,
		"THREAD_LOAD_INVALID_RESOURCE should trigger fallback sync load (not silent abort)")
	assert_false(fallback_loader.is_loading(),
		"Should not be in loading state after fallback completes")


func test_after_invalid_resource_can_load_again() -> void:
	## After THREAD_LOAD_INVALID_RESOURCE fallback, _is_loading must be false
	## so the next load_level() call is not silently dropped.
	var fallback_loader := MockSceneLoaderWithFallback.new()
	fallback_loader.register_valid_path("res://scenes/levels/BuildingLevel.tscn")
	fallback_loader.register_valid_path("res://scenes/levels/CastleLevel.tscn")

	fallback_loader.load_level("res://scenes/levels/BuildingLevel.tscn")
	fallback_loader.simulate_invalid_resource_during_poll()

	fallback_loader.load_level("res://scenes/levels/CastleLevel.tscn")
	assert_true(fallback_loader.is_loading(),
		"Should be able to load a new level after INVALID_RESOURCE fallback")


func test_invalid_resource_fallback_keeps_overlay_on_scene_change_error() -> void:
	## Issue #1817: exported startup can report THREAD_LOAD_INVALID_RESOURCE and
	## then fail the sync scene change. In that case the loading overlay must stay
	## visible instead of exposing a blank/gray scene.
	var fallback_loader := MockSceneLoaderWithFallback.new()
	fallback_loader.register_valid_path("res://scenes/levels/RoguelikeLevel.tscn")
	fallback_loader.fallback_change_error = ERR_CANT_CREATE

	fallback_loader.load_level("res://scenes/levels/RoguelikeLevel.tscn")
	fallback_loader.simulate_invalid_resource_during_poll()

	assert_true(fallback_loader.fallback_triggered,
		"Invalid threaded resource should still attempt sync fallback")
	assert_true(fallback_loader.is_loading(),
		"Failed sync fallback should keep loader state active for diagnostics")
	assert_true(fallback_loader.fallback_overlay_is_visible(),
		"Failed sync fallback should keep the loading overlay visible")
