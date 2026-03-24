extends GutTest
## Unit tests for SettingsMenu.
##
## Tests submenu count and submenu types using a mock class.


# ============================================================================
# Mock SettingsMenu for Testing
# ============================================================================


class MockSettingsMenu:
	## Submenu categories in the settings menu.
	const SUBMENU_TYPES: Array[String] = [
		"controls",
		"difficulty",
		"sound",
		"gameplay",
		"performance",
		"experimental",
	]

	## Submenu visibility tracking.
	var _submenu_visible: Dictionary = {
		"controls": false,
		"difficulty": false,
		"sound": false,
		"gameplay": false,
		"performance": false,
		"experimental": false,
	}

	## Main menu container visibility.
	var menu_container_visible: bool = true

	## Signal tracking.
	var back_pressed_count: int = 0

	## Open a submenu.
	func open_submenu(submenu_name: String) -> bool:
		if submenu_name not in _submenu_visible:
			return false
		menu_container_visible = false
		_submenu_visible[submenu_name] = true
		return true

	## Close a submenu and return to main settings.
	func close_submenu(submenu_name: String) -> void:
		if submenu_name in _submenu_visible:
			_submenu_visible[submenu_name] = false
		menu_container_visible = true

	## Check if a submenu is open.
	func is_submenu_open(submenu_name: String) -> bool:
		return _submenu_visible.get(submenu_name, false)

	## Get submenu count.
	func get_submenu_count() -> int:
		return SUBMENU_TYPES.size()

	## Press back.
	func press_back() -> void:
		back_pressed_count += 1


var menu: MockSettingsMenu


func before_each() -> void:
	menu = MockSettingsMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# Submenu Count Tests
# ============================================================================


func test_submenu_count_is_6() -> void:
	assert_eq(menu.get_submenu_count(), 6,
		"Settings menu should have 6 submenu categories")


func test_submenu_types_size() -> void:
	assert_eq(menu.SUBMENU_TYPES.size(), 6,
		"SUBMENU_TYPES array should have 6 entries")


# ============================================================================
# Submenu Types Existence Tests
# ============================================================================


func test_controls_submenu_exists() -> void:
	assert_true(menu.SUBMENU_TYPES.has("controls"),
		"Should have controls submenu")


func test_difficulty_submenu_exists() -> void:
	assert_true(menu.SUBMENU_TYPES.has("difficulty"),
		"Should have difficulty submenu")


func test_sound_submenu_exists() -> void:
	assert_true(menu.SUBMENU_TYPES.has("sound"),
		"Should have sound submenu")


func test_gameplay_submenu_exists() -> void:
	assert_true(menu.SUBMENU_TYPES.has("gameplay"),
		"Should have gameplay submenu")


func test_performance_submenu_exists() -> void:
	assert_true(menu.SUBMENU_TYPES.has("performance"),
		"Should have performance submenu")


func test_experimental_submenu_exists() -> void:
	assert_true(menu.SUBMENU_TYPES.has("experimental"),
		"Should have experimental submenu")


# ============================================================================
# Submenu Navigation Tests
# ============================================================================


func test_open_submenu_hides_main_container() -> void:
	menu.open_submenu("controls")

	assert_false(menu.menu_container_visible,
		"Opening submenu should hide main container")


func test_open_submenu_shows_submenu() -> void:
	menu.open_submenu("difficulty")

	assert_true(menu.is_submenu_open("difficulty"),
		"Opened submenu should be visible")


func test_close_submenu_shows_main_container() -> void:
	menu.open_submenu("sound")
	menu.close_submenu("sound")

	assert_true(menu.menu_container_visible,
		"Closing submenu should show main container")
	assert_false(menu.is_submenu_open("sound"),
		"Closed submenu should not be visible")


func test_open_invalid_submenu_returns_false() -> void:
	var result := menu.open_submenu("nonexistent")

	assert_false(result,
		"Opening invalid submenu should return false")
	assert_true(menu.menu_container_visible,
		"Main container should remain visible on invalid submenu")


func test_all_submenus_initially_closed() -> void:
	for submenu_name in menu.SUBMENU_TYPES:
		assert_false(menu.is_submenu_open(submenu_name),
			"Submenu '%s' should be closed initially" % submenu_name)


# ============================================================================
# Back Button Tests
# ============================================================================


func test_back_button() -> void:
	menu.press_back()

	assert_eq(menu.back_pressed_count, 1,
		"Should track back press")
