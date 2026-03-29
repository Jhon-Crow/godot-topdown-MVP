extends Node
## LocalizationSettings - Global language/locale manager (Issue #1718).
##
## Provides centralized control over the game's display language.
## Supports English (en) and Russian (ru).
## The selected locale is applied to Godot's TranslationServer and
## persisted to disk so the choice survives restarts.
##
## Translations are loaded at runtime by parsing the CSV directly so that
## exported builds work without requiring compiled .translation files.

## Signal emitted when the locale changes.
signal locale_changed(new_locale: String)

## Supported locale codes.
const LOCALE_EN: String = "en"
const LOCALE_RU: String = "ru"

## All supported locales in display order.
const SUPPORTED_LOCALES: Array[String] = [LOCALE_EN, LOCALE_RU]

## Path to the CSV translation source file.
const CSV_PATH: String = "res://resources/translations/translations.csv"

## Settings file path for persistence.
const SETTINGS_PATH: String = "user://localization_settings.cfg"

## Current locale code.
var current_locale: String = LOCALE_EN


func _ready() -> void:
	_load_csv_translations()
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


## Parses the CSV file and registers a Translation object per locale column.
## This ensures translations work in exported builds without requiring compiled
## .translation binary files (which are gitignored and not bundled otherwise).
## Uses FileAccess.get_csv_line() to correctly handle values that contain commas.
func _load_csv_translations() -> void:
	if not FileAccess.file_exists(CSV_PATH):
		push_warning("LocalizationSettings: CSV not found at %s" % CSV_PATH)
		return

	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_warning("LocalizationSettings: Cannot open CSV at %s" % CSV_PATH)
		return

	# Read header row: keys,en,ru,...
	var header: PackedStringArray = file.get_csv_line()
	if header.size() < 2:
		push_warning("LocalizationSettings: CSV header has fewer than 2 columns")
		file.close()
		return

	# Build one Translation object per locale column (skip index 0 = "keys")
	var translations: Array[Translation] = []
	for i in range(1, header.size()):
		var locale_code: String = header[i].strip_edges()
		if locale_code.is_empty():
			continue
		var t := Translation.new()
		t.locale = locale_code
		translations.append(t)

	# Populate translations row by row
	while not file.eof_reached():
		var parts: PackedStringArray = file.get_csv_line()
		if parts.size() < 2:
			continue
		var key: String = parts[0].strip_edges()
		if key.is_empty():
			continue
		for i in range(translations.size()):
			var col_index: int = i + 1
			var value: String = parts[col_index].strip_edges() if col_index < parts.size() else key
			translations[i].add_message(key, value)

	file.close()

	# Register all translations with TranslationServer
	for t in translations:
		TranslationServer.add_translation(t)

	_log_to_file("Loaded %d locale(s) from CSV" % translations.size())


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
