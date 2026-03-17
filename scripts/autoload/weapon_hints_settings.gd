extends Node
## WeaponHintsSettings - Manages weapon-specific tutorial hints display settings.
##
## Controls when weapon hints are shown to the player:
## - ALWAYS: Show hints every time a weapon is equipped
## - FIRST_TIME_ONLY: Show hints only for the first use of each weapon
## - NEVER: Never show weapon hints
##
## Issue #809: добавь обучение новому оружию (add weapon training)

## Signal emitted when settings change.
signal settings_changed

## Signal emitted when a weapon is marked as seen.
signal weapon_seen(weapon_id: String)

## Hint display mode enum.
enum HintMode {
	ALWAYS = 0,
	FIRST_TIME_ONLY = 1,
	NEVER = 2
}

## Current hint display mode.
var hint_mode: HintMode = HintMode.ALWAYS

## Dictionary tracking which weapons have been seen (for FIRST_TIME_ONLY mode).
## Keys: weapon_id (String), Values: true if seen.
var weapons_seen: Dictionary = {}

## Settings file path for persistence.
const SETTINGS_PATH := "user://weapon_hints_settings.cfg"

## Section names for config file.
const SECTION_SETTINGS := "settings"
const SECTION_WEAPONS_SEEN := "weapons_seen"

## Key names for config file.
const KEY_HINT_MODE := "hint_mode"


func _ready() -> void:
	_load_settings()
	_log_to_file("WeaponHintsSettings initialized - mode: %s, weapons seen: %s" % [
		_get_mode_name(hint_mode),
		weapons_seen.keys()
	])


## Set the hint display mode.
## @param mode: The new HintMode to use.
func set_hint_mode(mode: HintMode) -> void:
	if hint_mode != mode:
		hint_mode = mode
		settings_changed.emit()
		_save_settings()
		_log_to_file("Hint mode changed to: %s" % _get_mode_name(mode))


## Get the current hint display mode.
## @return: The current HintMode.
func get_hint_mode() -> HintMode:
	return hint_mode


## Check if hints should be shown for a given weapon.
## @param weapon_id: The weapon identifier to check.
## @return: true if hints should be shown, false otherwise.
func should_show_hints(weapon_id: String) -> bool:
	match hint_mode:
		HintMode.ALWAYS:
			return true
		HintMode.FIRST_TIME_ONLY:
			return not weapons_seen.get(weapon_id, false)
		HintMode.NEVER:
			return false
	return false


## Mark a weapon as seen (hints have been shown).
## @param weapon_id: The weapon identifier to mark as seen.
func mark_weapon_seen(weapon_id: String) -> void:
	if not weapons_seen.get(weapon_id, false):
		weapons_seen[weapon_id] = true
		weapon_seen.emit(weapon_id)
		_save_settings()
		_log_to_file("Weapon marked as seen: %s" % weapon_id)


## Check if a weapon has been seen before.
## @param weapon_id: The weapon identifier to check.
## @return: true if the weapon has been seen, false otherwise.
func is_weapon_seen(weapon_id: String) -> bool:
	return weapons_seen.get(weapon_id, false)


## Reset seen tracking for a single weapon (e.g. when it is unlocked for the first time).
## This allows hints to reappear for a weapon that was previously seen if it is newly unlocked.
## @param weapon_id: The weapon identifier to reset.
func reset_weapon_seen(weapon_id: String) -> void:
	if weapons_seen.get(weapon_id, false):
		weapons_seen.erase(weapon_id)
		_save_settings()
		_log_to_file("Weapon seen data cleared for: %s" % weapon_id)


## Reset all weapons seen tracking (for "first time" mode).
## Called when user wants to see all hints again.
func reset_weapons_seen() -> void:
	weapons_seen.clear()
	settings_changed.emit()
	_save_settings()
	_log_to_file("All weapons seen data cleared")


## Get mode name for logging.
func _get_mode_name(mode: HintMode) -> String:
	match mode:
		HintMode.ALWAYS:
			return "ALWAYS"
		HintMode.FIRST_TIME_ONLY:
			return "FIRST_TIME_ONLY"
		HintMode.NEVER:
			return "NEVER"
	return "UNKNOWN"


## Save settings to file.
func _save_settings() -> void:
	var config := ConfigFile.new()

	# Save hint mode
	config.set_value(SECTION_SETTINGS, KEY_HINT_MODE, hint_mode)

	# Save weapons seen
	for weapon_id in weapons_seen:
		config.set_value(SECTION_WEAPONS_SEEN, weapon_id, weapons_seen[weapon_id])

	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("WeaponHintsSettings: Failed to save settings: " + str(error))


## Load settings from file.
func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)

	if error == OK:
		# Load hint mode
		hint_mode = config.get_value(SECTION_SETTINGS, KEY_HINT_MODE, HintMode.ALWAYS)

		# Load weapons seen
		if config.has_section(SECTION_WEAPONS_SEEN):
			for weapon_id in config.get_section_keys(SECTION_WEAPONS_SEEN):
				weapons_seen[weapon_id] = config.get_value(SECTION_WEAPONS_SEEN, weapon_id, false)
	else:
		# File doesn't exist or failed to load - use defaults
		hint_mode = HintMode.ALWAYS
		weapons_seen = {}


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[WeaponHintsSettings] " + message)
	else:
		print("[WeaponHintsSettings] " + message)
