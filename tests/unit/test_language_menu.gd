extends GutTest
## Unit tests for LanguageMenu (Issue #1718).
##
## Tests language selection logic using a mock class.


# ============================================================================
# Mock LanguageMenu for Testing
# ============================================================================


class MockLanguageMenu:
	## Supported locale codes (mirrors LocalizationSettings).
	const LOCALE_EN: String = "en"
	const LOCALE_RU: String = "ru"

	## Track back_pressed signal.
	var back_pressed_count: int = 0

	## Simulate current locale held by a mock LocalizationSettings.
	var _current_locale: String = LOCALE_EN

	## Track which button is visually selected (highlighted).
	var _selected_locale: String = LOCALE_EN

	## Simulates pressing the English button.
	func press_english() -> void:
		_current_locale = LOCALE_EN
		_selected_locale = LOCALE_EN

	## Simulates pressing the Russian button.
	func press_russian() -> void:
		_current_locale = LOCALE_RU
		_selected_locale = LOCALE_RU

	## Simulates pressing the back button.
	func press_back() -> void:
		back_pressed_count += 1

	## Simulates pressing the ESC / pause action (Issue #1718 fix).
	func simulate_esc_press() -> void:
		press_back()

	## Returns the current locale.
	func get_current_locale() -> String:
		return _current_locale

	## Returns which locale button is currently highlighted.
	func get_selected_locale() -> String:
		return _selected_locale

	## Simulates an external locale change (e.g. from another source).
	func on_locale_changed(new_locale: String) -> void:
		_selected_locale = new_locale


var menu: MockLanguageMenu


func before_each() -> void:
	menu = MockLanguageMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_locale_is_english() -> void:
	assert_eq(menu.get_current_locale(), "en",
		"Default locale should be English")


func test_initial_selection_highlights_english() -> void:
	assert_eq(menu.get_selected_locale(), "en",
		"English button should be highlighted by default")


# ============================================================================
# Language Selection Tests
# ============================================================================


func test_press_russian_sets_locale_to_ru() -> void:
	menu.press_russian()
	assert_eq(menu.get_current_locale(), "ru",
		"Pressing Russian button should set locale to 'ru'")


func test_press_russian_highlights_russian_button() -> void:
	menu.press_russian()
	assert_eq(menu.get_selected_locale(), "ru",
		"Russian button should be highlighted after pressing Russian")


func test_press_english_sets_locale_to_en() -> void:
	menu.press_russian()
	menu.press_english()
	assert_eq(menu.get_current_locale(), "en",
		"Pressing English button should set locale to 'en'")


func test_press_english_highlights_english_button() -> void:
	menu.press_russian()
	menu.press_english()
	assert_eq(menu.get_selected_locale(), "en",
		"English button should be highlighted after pressing English")


# ============================================================================
# Back Button Tests
# ============================================================================


func test_back_button_emits_signal() -> void:
	menu.press_back()
	assert_eq(menu.back_pressed_count, 1,
		"back_pressed signal should be emitted once when back is pressed")


func test_back_button_multiple_presses() -> void:
	menu.press_back()
	menu.press_back()
	assert_eq(menu.back_pressed_count, 2,
		"back_pressed signal should be emitted each time back is pressed")


# ============================================================================
# External Locale Change Tests
# ============================================================================


func test_on_locale_changed_updates_selection() -> void:
	menu.on_locale_changed("ru")
	assert_eq(menu.get_selected_locale(), "ru",
		"Receiving locale_changed signal should update the highlighted button")


func test_on_locale_changed_back_to_english() -> void:
	menu.on_locale_changed("ru")
	menu.on_locale_changed("en")
	assert_eq(menu.get_selected_locale(), "en",
		"Receiving locale_changed for 'en' should highlight the English button")


# ============================================================================
# ESC / Pause Action Tests
# ============================================================================


func test_esc_press_emits_back_pressed() -> void:
	menu.simulate_esc_press()
	assert_eq(menu.back_pressed_count, 1,
		"Pressing ESC (pause action) should emit back_pressed signal")
