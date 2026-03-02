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

## Whether debug mode is enabled (shows debug labels on enemies).
## Toggle with F7 key or via experimental menu.
## When enabled, displays AI state labels above enemies and debug visuals.
## When disabled (default), no debug information is shown.
var debug_mode_enabled: bool = false

## Whether invincibility mode is enabled (player takes no damage).
## Toggle with F6 key or via experimental menu.
## When enabled, the player cannot be killed by any damage source.
## When disabled (default), normal damage rules apply.
var invincibility_enabled: bool = false

## Whether realistic visibility mode is enabled (Issue #540).
## When enabled, the player cannot see through walls (Door Kickers 2 style).
## Uses PointLight2D + CanvasModulate + LightOccluder2D for fog of war.
## When disabled (default), the player has full visibility of the entire level.
var realistic_visibility_enabled: bool = false

## Whether replay viewing is enabled (Issue #807).
## When enabled, the player can watch replays after completing levels.
## When disabled (default), the "Watch Replay" button is hidden on score screens.
var replay_enabled: bool = false

## Whether log recording is enabled (Issue #848).
## When enabled (default), game events are written to a log file for debugging.
## When disabled, no log file is created, which can improve performance (FPS).
var logging_enabled: bool = true

## Whether enemy flashlight blinding is enabled (Issue #903).
## When enabled, enemy flashlights can blind the player in night mode.
## When disabled (default), enemy flashlights only serve as a visual warning
## without applying any blinding effect to the player.
var enemy_flashlight_blinding_enabled: bool = false

## Whether the on-screen FPS counter is shown (Issue #883).
## When enabled, displays current FPS in the top-left corner of the screen.
## When disabled (default), no FPS counter is shown.
var fps_counter_enabled: bool = false

## Whether FPS drop logging is enabled (Issue #883).
## When enabled, logs a warning to the log file whenever FPS drops below 30.
## When disabled (default), no FPS drop warnings are written.
var fps_drop_logging_enabled: bool = false

## Whether the blood decal budget limit is enabled (Issue #953).
## When enabled, removes the oldest blood decals once the count exceeds
## blood_decal_max_count, preventing unbounded scene-node accumulation.
## When disabled (default), all blood decals persist forever (original behavior,
## preserving issues #293 and #370 design intent).
var blood_decal_budget_enabled: bool = false

## Maximum number of blood decals when budget is enabled (Issue #953).
## At 20 decals per lethal hit a long session can accumulate 2000+ decals
## (6000+ scene nodes), causing significant render and physics overhead.
## 200 provides a visually rich battlefield while bounding scene-tree growth.
var blood_decal_max_count: int = 200

## Settings file path for persistence.
const SETTINGS_PATH := "user://experimental_settings.cfg"


func _ready() -> void:
	# Load saved settings on startup
	_load_settings()
	# Apply logging setting to FileLogger (Issue #848)
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("set_logging_enabled"):
		file_logger.set_logging_enabled(logging_enabled)
	_log_to_file("ExperimentalSettings initialized - FOV: %s, Complex grenades: %s, AI prediction: %s, Debug: %s, Invincibility: %s, Realistic visibility: %s, Replay: %s, Logging: %s, Enemy flashlight blinding: %s, FPS counter: %s, FPS drop logging: %s, Blood decal budget: %s (max: %d)" % [fov_enabled, complex_grenade_throwing, ai_prediction_enabled, debug_mode_enabled, invincibility_enabled, realistic_visibility_enabled, replay_enabled, logging_enabled, enemy_flashlight_blinding_enabled, fps_counter_enabled, fps_drop_logging_enabled, blood_decal_budget_enabled, blood_decal_max_count])


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


## Set debug mode enabled/disabled.
func set_debug_mode_enabled(enabled: bool) -> void:
	if debug_mode_enabled != enabled:
		debug_mode_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Debug mode %s" % ("enabled" if enabled else "disabled"))


## Check if debug mode is enabled.
func is_debug_mode_enabled() -> bool:
	return debug_mode_enabled


## Set invincibility mode enabled/disabled.
func set_invincibility_enabled(enabled: bool) -> void:
	if invincibility_enabled != enabled:
		invincibility_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Invincibility mode %s" % ("enabled" if enabled else "disabled"))


## Check if invincibility mode is enabled.
func is_invincibility_enabled() -> bool:
	return invincibility_enabled


## Set realistic visibility enabled/disabled (Issue #540).
func set_realistic_visibility_enabled(enabled: bool) -> void:
	if realistic_visibility_enabled != enabled:
		realistic_visibility_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Realistic visibility %s" % ("enabled" if enabled else "disabled"))


## Check if realistic visibility is enabled (Issue #540).
func is_realistic_visibility_enabled() -> bool:
	return realistic_visibility_enabled


## Set replay viewing enabled/disabled (Issue #807).
func set_replay_enabled(enabled: bool) -> void:
	if replay_enabled != enabled:
		replay_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Replay viewing %s" % ("enabled" if enabled else "disabled"))


## Check if replay viewing is enabled (Issue #807).
func is_replay_enabled() -> bool:
	return replay_enabled


## Set log recording enabled/disabled (Issue #848).
func set_logging_enabled(enabled: bool) -> void:
	if logging_enabled != enabled:
		logging_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Log recording %s" % ("enabled" if enabled else "disabled"))
		# Notify FileLogger about the change
		var file_logger: Node = get_node_or_null("/root/FileLogger")
		if file_logger and file_logger.has_method("set_logging_enabled"):
			file_logger.set_logging_enabled(enabled)


## Check if log recording is enabled (Issue #848).
func is_logging_enabled() -> bool:
	return logging_enabled


## Set enemy flashlight blinding enabled/disabled (Issue #903).
func set_enemy_flashlight_blinding_enabled(enabled: bool) -> void:
	if enemy_flashlight_blinding_enabled != enabled:
		enemy_flashlight_blinding_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Enemy flashlight blinding %s" % ("enabled" if enabled else "disabled"))


## Check if enemy flashlight blinding is enabled (Issue #903).
func is_enemy_flashlight_blinding_enabled() -> bool:
	return enemy_flashlight_blinding_enabled


## Set FPS counter display enabled/disabled (Issue #883).
func set_fps_counter_enabled(enabled: bool) -> void:
	if fps_counter_enabled != enabled:
		fps_counter_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("FPS counter %s" % ("enabled" if enabled else "disabled"))


## Check if FPS counter display is enabled (Issue #883).
func is_fps_counter_enabled() -> bool:
	return fps_counter_enabled


## Set FPS drop logging enabled/disabled (Issue #883).
func set_fps_drop_logging_enabled(enabled: bool) -> void:
	if fps_drop_logging_enabled != enabled:
		fps_drop_logging_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("FPS drop logging %s" % ("enabled" if enabled else "disabled"))


## Check if FPS drop logging is enabled (Issue #883).
func is_fps_drop_logging_enabled() -> bool:
	return fps_drop_logging_enabled


## Set blood decal budget limit enabled/disabled (Issue #953).
## When enabled, removes oldest decals beyond blood_decal_max_count to prevent
## unbounded scene-tree accumulation that causes FPS drops at high enemy counts.
func set_blood_decal_budget_enabled(enabled: bool) -> void:
	if blood_decal_budget_enabled != enabled:
		blood_decal_budget_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Blood decal budget %s (max: %d)" % [("enabled" if enabled else "disabled"), blood_decal_max_count])


## Check if blood decal budget limit is enabled (Issue #953).
func is_blood_decal_budget_enabled() -> bool:
	return blood_decal_budget_enabled


## Set the maximum blood decal count when budget is enabled (Issue #953).
func set_blood_decal_max_count(count: int) -> void:
	var clamped := max(1, count)
	if blood_decal_max_count != clamped:
		blood_decal_max_count = clamped
		settings_changed.emit()
		_save_settings()
		_log_to_file("Blood decal max count set to %d" % blood_decal_max_count)


## Get the maximum blood decal count (Issue #953).
func get_blood_decal_max_count() -> int:
	return blood_decal_max_count


## Save settings to file.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("experimental", "fov_enabled", fov_enabled)
	config.set_value("experimental", "complex_grenade_throwing", complex_grenade_throwing)
	config.set_value("experimental", "ai_prediction_enabled", ai_prediction_enabled)
	config.set_value("experimental", "debug_mode_enabled", debug_mode_enabled)
	config.set_value("experimental", "invincibility_enabled", invincibility_enabled)
	config.set_value("experimental", "realistic_visibility_enabled", realistic_visibility_enabled)
	config.set_value("experimental", "replay_enabled", replay_enabled)
	config.set_value("experimental", "logging_enabled", logging_enabled)
	config.set_value("experimental", "enemy_flashlight_blinding_enabled", enemy_flashlight_blinding_enabled)
	config.set_value("experimental", "fps_counter_enabled", fps_counter_enabled)
	config.set_value("experimental", "fps_drop_logging_enabled", fps_drop_logging_enabled)
	config.set_value("experimental", "blood_decal_budget_enabled", blood_decal_budget_enabled)
	config.set_value("experimental", "blood_decal_max_count", blood_decal_max_count)
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
		debug_mode_enabled = config.get_value("experimental", "debug_mode_enabled", false)
		invincibility_enabled = config.get_value("experimental", "invincibility_enabled", false)
		realistic_visibility_enabled = config.get_value("experimental", "realistic_visibility_enabled", false)
		replay_enabled = config.get_value("experimental", "replay_enabled", false)
		logging_enabled = config.get_value("experimental", "logging_enabled", true)
		enemy_flashlight_blinding_enabled = config.get_value("experimental", "enemy_flashlight_blinding_enabled", false)
		fps_counter_enabled = config.get_value("experimental", "fps_counter_enabled", false)
		fps_drop_logging_enabled = config.get_value("experimental", "fps_drop_logging_enabled", false)
		blood_decal_budget_enabled = config.get_value("experimental", "blood_decal_budget_enabled", false)
		blood_decal_max_count = config.get_value("experimental", "blood_decal_max_count", 200)
	else:
		# File doesn't exist or failed to load - use defaults
		fov_enabled = true
		complex_grenade_throwing = false
		ai_prediction_enabled = false
		debug_mode_enabled = false
		invincibility_enabled = false
		realistic_visibility_enabled = false
		replay_enabled = false
		logging_enabled = true
		enemy_flashlight_blinding_enabled = false
		fps_counter_enabled = false
		fps_drop_logging_enabled = false
		blood_decal_budget_enabled = false
		blood_decal_max_count = 200


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[ExperimentalSettings] " + message)
	else:
		print("[ExperimentalSettings] " + message)
