extends Node
## LocalizationSettings - Global language/locale manager (Issue #1718).
##
## Provides centralized control over the game's display language.
## Supports English (en) and Russian (ru).
## The selected locale is applied to Godot's TranslationServer and
## persisted to disk so the choice survives restarts.

## Signal emitted when the locale changes.
signal locale_changed(new_locale: String)

## Supported locale codes.
const LOCALE_EN: String = "en"
const LOCALE_RU: String = "ru"

## All supported locales in display order.
const SUPPORTED_LOCALES: Array[String] = [LOCALE_EN, LOCALE_RU]

## Settings file path for persistence.
const SETTINGS_PATH: String = "user://localization_settings.cfg"

## Current locale code.
var current_locale: String = LOCALE_EN


func _ready() -> void:
	_load_settings()
	_apply_locale(current_locale)
	_log_to_file("LocalizationSettings initialized — locale: %s" % current_locale)


## Sets the display language and persists the choice.
## @param locale: A supported locale code (LOCALE_EN or LOCALE_RU).
func set_locale(locale: String) -> void:
	if locale not in SUPPORTED_LOCALES:
		push_warning("LocalizationSettings: Unsupported locale '%s'" % locale)
		return
	if current_locale == locale:
		return
	current_locale = locale
	_apply_locale(locale)
	_save_settings()
	locale_changed.emit(locale)
	_log_to_file("Locale changed to: %s" % locale)


## Returns the current locale code.
func get_locale() -> String:
	return current_locale


## Applies the given locale to Godot's TranslationServer.
func _apply_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)


## Saves the current locale to disk.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("locale", "current_locale", current_locale)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("LocalizationSettings: Failed to save settings: " + str(error))


## Loads the saved locale from disk.
func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == OK:
		var saved := config.get_value("locale", "current_locale", LOCALE_EN)
		if saved in SUPPORTED_LOCALES:
			current_locale = saved
		else:
			current_locale = LOCALE_EN
	else:
		current_locale = LOCALE_EN


## Logs a message via FileLogger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[LocalizationSettings] " + message)
	else:
		print("[LocalizationSettings] " + message)
