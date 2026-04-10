extends GutTest
## Unit tests for LocalizationSettings autoload (Issue #1718).
##
## Tests locale management, validation, and persistence logic
## without requiring Godot's TranslationServer.


# ============================================================================
# Mock LocalizationSettings for Logic Tests
# ============================================================================


class MockLocalizationSettings:
	## Supported locale codes.
	const LOCALE_EN: String = "en"
	const LOCALE_RU: String = "ru"

	## All supported locales in display order.
	const SUPPORTED_LOCALES: Array[String] = [LOCALE_EN, LOCALE_RU]

	## Current locale code.
	var current_locale: String = LOCALE_EN

	## Track locale_changed signal emissions.
	var locale_changed_count: int = 0
	var last_emitted_locale: String = ""

	## Track TranslationServer.set_locale calls.
	var applied_locale: String = ""

	## Sets the display language.
	func set_locale(locale: String) -> void:
		if locale not in SUPPORTED_LOCALES:
			return
		if current_locale == locale:
			return
		current_locale = locale
		applied_locale = locale
		locale_changed_count += 1
		last_emitted_locale = locale

	## Returns the current locale code.
	func get_locale() -> String:
		return current_locale


var loc: MockLocalizationSettings


func before_each() -> void:
	loc = MockLocalizationSettings.new()


func after_each() -> void:
	loc = null


# ============================================================================
# Default Values Tests
# ============================================================================


func test_default_locale_is_english() -> void:
	assert_eq(loc.get_locale(), "en",
		"Default locale should be English (en)")


func test_supported_locales_contains_english() -> void:
	assert_true(loc.SUPPORTED_LOCALES.has("en"),
		"SUPPORTED_LOCALES should contain 'en'")


func test_supported_locales_contains_russian() -> void:
	assert_true(loc.SUPPORTED_LOCALES.has("ru"),
		"SUPPORTED_LOCALES should contain 'ru'")


func test_supported_locales_count_is_two() -> void:
	assert_eq(loc.SUPPORTED_LOCALES.size(), 2,
		"SUPPORTED_LOCALES should have exactly 2 entries")


# ============================================================================
# set_locale Tests
# ============================================================================


func test_set_locale_to_russian() -> void:
	loc.set_locale("ru")
	assert_eq(loc.get_locale(), "ru",
		"Locale should be set to Russian (ru)")


func test_set_locale_to_english() -> void:
	loc.set_locale("ru")
	loc.set_locale("en")
	assert_eq(loc.get_locale(), "en",
		"Locale should be switched back to English (en)")


func test_set_unsupported_locale_is_ignored() -> void:
	loc.set_locale("fr")
	assert_eq(loc.get_locale(), "en",
		"Unsupported locale should be ignored, locale should remain 'en'")


func test_set_empty_locale_is_ignored() -> void:
	loc.set_locale("")
	assert_eq(loc.get_locale(), "en",
		"Empty locale string should be ignored")


func test_set_same_locale_does_not_emit_signal() -> void:
	loc.set_locale("en")  # Already "en" by default
	assert_eq(loc.locale_changed_count, 0,
		"locale_changed should NOT be emitted when locale does not change")


func test_set_locale_emits_signal_on_change() -> void:
	loc.set_locale("ru")
	assert_eq(loc.locale_changed_count, 1,
		"locale_changed should be emitted when locale changes")


func test_set_locale_emits_correct_value() -> void:
	loc.set_locale("ru")
	assert_eq(loc.last_emitted_locale, "ru",
		"locale_changed should emit the new locale code")


func test_set_locale_applies_to_translation_server() -> void:
	loc.set_locale("ru")
	assert_eq(loc.applied_locale, "ru",
		"New locale should be applied to the translation system")


# ============================================================================
# Locale Change Sequence Tests
# ============================================================================


func test_multiple_locale_changes_count_signals() -> void:
	loc.set_locale("ru")
	loc.set_locale("en")
	loc.set_locale("ru")
	assert_eq(loc.locale_changed_count, 3,
		"locale_changed should be emitted 3 times for 3 different locale changes")


func test_locale_const_en_is_en() -> void:
	assert_eq(loc.LOCALE_EN, "en",
		"LOCALE_EN constant should equal 'en'")


func test_locale_const_ru_is_ru() -> void:
	assert_eq(loc.LOCALE_RU, "ru",
		"LOCALE_RU constant should equal 'ru'")
