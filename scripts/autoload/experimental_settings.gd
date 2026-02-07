extends Node
## ExperimentalSettings - Global experimental features manager.
##
## Provides a centralized way to manage experimental game features.
## All experimental features are disabled by default.

## Signal emitted when experimental settings change.
signal settings_changed

## Whether FOV (Field of View) limitation for enemies is enabled.
## When enabled (default), enemies can only see within a 100-degree cone.
## When disabled, enemies have 360-degree vision.
var fov_enabled: bool = true

## Whether complex grenade throwing is enabled.
## When enabled, uses the complex 3-step throwing mechanic (G+RMB drag, G+RMB hold, RMB release).
## When disabled (default), uses simple trajectory aiming (hold RMB to aim, release to throw).
var complex_grenade_throwing: bool = false

## Whether AI player prediction is enabled (Issue #298).
## When enabled, enemies predict player movement when losing line of sight,
## generating probability-weighted hypotheses about the player's position.
## When disabled (default), enemies use standard pursuit/search behavior.
var ai_prediction_enabled: bool = false

## Settings file path for persistence.
const SETTINGS_PATH := "user://experimental_settings.cfg"


func _ready() -> void:
	# Load saved settings on startup
	_load_settings()
	_log_to_file("ExperimentalSettings initialized - FOV enabled: %s, Complex grenade throwing: %s, AI prediction: %s" % [fov_enabled, complex_grenade_throwing, ai_prediction_enabled])


## Set FOV enabled/disabled.
func set_fov_enabled(enabled: bool) -> void:
	if fov_enabled != enabled:
		fov_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("FOV limitation %s" % ("enabled" if enabled else "disabled"))


## Check if FOV limitation is enabled.
func is_fov_enabled() -> bool:
	return fov_enabled


## Set complex grenade throwing enabled/disabled.
func set_complex_grenade_throwing(enabled: bool) -> void:
	if complex_grenade_throwing != enabled:
		complex_grenade_throwing = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Complex grenade throwing %s" % ("enabled" if enabled else "disabled"))


## Check if complex grenade throwing is enabled.
func is_complex_grenade_throwing() -> bool:
	return complex_grenade_throwing


## Set AI prediction enabled/disabled (Issue #298).
func set_ai_prediction_enabled(enabled: bool) -> void:
	if ai_prediction_enabled != enabled:
		ai_prediction_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("AI prediction %s" % ("enabled" if enabled else "disabled"))


## Check if AI prediction is enabled (Issue #298).
func is_ai_prediction_enabled() -> bool:
	return ai_prediction_enabled


## Save settings to file.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("experimental", "fov_enabled", fov_enabled)
	config.set_value("experimental", "complex_grenade_throwing", complex_grenade_throwing)
	config.set_value("experimental", "ai_prediction_enabled", ai_prediction_enabled)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("ExperimentalSettings: Failed to save settings: " + str(error))


## Load settings from file.
func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == OK:
		fov_enabled = config.get_value("experimental", "fov_enabled", true)
		complex_grenade_throwing = config.get_value("experimental", "complex_grenade_throwing", false)
		ai_prediction_enabled = config.get_value("experimental", "ai_prediction_enabled", false)
	else:
		# File doesn't exist or failed to load - use defaults
		fov_enabled = true
		complex_grenade_throwing = false
		ai_prediction_enabled = false


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[ExperimentalSettings] " + message)
	else:
		print("[ExperimentalSettings] " + message)
