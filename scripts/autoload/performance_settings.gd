extends Node
## PerformanceSettings - Global performance toggles manager (Issue #1186).
##
## Provides toggles for every system that can affect performance.
## Use these to isolate unoptimized subsystems during profiling.
## All features are enabled by default (no change in default gameplay).

## Signal emitted when any performance setting changes.
signal settings_changed

## Whether particle effects are enabled (dust, blood spray, sparks, muzzle flash).
## When disabled, no GPUParticles2D are spawned on hits or weapon fire.
## Disabling this has a significant positive impact on GPU performance.
var particles_enabled: bool = true

## Whether blood decals on floors and walls are enabled.
## When disabled, no Sprite2D blood decals are placed on the floor/walls after hits.
## Disabling this reduces the number of Sprite2D nodes in the scene tree.
var blood_decals_enabled: bool = true

## Whether screen shake (camera recoil) is enabled.
## When disabled, the camera stays still while shooting.
## Uses the existing ScreenShakeManager.enabled flag.
var screen_shake_enabled: bool = true

## Whether explosion/flashbang lights (PointLight2D) are enabled.
## When disabled, grenade and flashbang explosions produce no dynamic light flash.
## PointLight2D is a known GPU bottleneck (Issue #724).
var explosion_lights_enabled: bool = true

## Whether AI is enabled for all enemies.
## When disabled, enemies do not process AI logic (they stand still).
## Disabling this helps identify the CPU cost of the AI system.
var ai_enabled: bool = true

## Settings file path for persistence.
const SETTINGS_PATH: String = "user://performance_settings.cfg"


func _ready() -> void:
	_load_settings()
	# Apply screen shake setting immediately
	_apply_screen_shake()
	_log_to_file("PerformanceSettings initialized - particles: %s, blood_decals: %s, screen_shake: %s, explosion_lights: %s, ai: %s" % [
		particles_enabled, blood_decals_enabled, screen_shake_enabled, explosion_lights_enabled, ai_enabled])


## Set particles enabled/disabled (Issue #1186).
func set_particles_enabled(enabled: bool) -> void:
	if particles_enabled != enabled:
		particles_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Particles %s" % ("enabled" if enabled else "disabled"))


## Check if particles are enabled (Issue #1186).
func is_particles_enabled() -> bool:
	return particles_enabled


## Set blood decals enabled/disabled (Issue #1186).
func set_blood_decals_enabled(enabled: bool) -> void:
	if blood_decals_enabled != enabled:
		blood_decals_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Blood decals %s" % ("enabled" if enabled else "disabled"))


## Check if blood decals are enabled (Issue #1186).
func is_blood_decals_enabled() -> bool:
	return blood_decals_enabled


## Set screen shake enabled/disabled (Issue #1186).
func set_screen_shake_enabled(enabled: bool) -> void:
	if screen_shake_enabled != enabled:
		screen_shake_enabled = enabled
		_apply_screen_shake()
		settings_changed.emit()
		_save_settings()
		_log_to_file("Screen shake %s" % ("enabled" if enabled else "disabled"))


## Check if screen shake is enabled (Issue #1186).
func is_screen_shake_enabled() -> bool:
	return screen_shake_enabled


## Set explosion lights enabled/disabled (Issue #1186).
func set_explosion_lights_enabled(enabled: bool) -> void:
	if explosion_lights_enabled != enabled:
		explosion_lights_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Explosion lights %s" % ("enabled" if enabled else "disabled"))


## Check if explosion lights are enabled (Issue #1186).
func is_explosion_lights_enabled() -> bool:
	return explosion_lights_enabled


## Set AI enabled/disabled for all enemies (Issue #1186).
func set_ai_enabled(enabled: bool) -> void:
	if ai_enabled != enabled:
		ai_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("AI %s" % ("enabled" if enabled else "disabled"))


## Check if AI is enabled (Issue #1186).
func is_ai_enabled() -> bool:
	return ai_enabled


## Applies the screen shake setting to ScreenShakeManager.
func _apply_screen_shake() -> void:
	var ssm: Node = get_node_or_null("/root/ScreenShakeManager")
	if ssm and "enabled" in ssm:
		ssm.enabled = screen_shake_enabled


## Save settings to file.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("performance", "particles_enabled", particles_enabled)
	config.set_value("performance", "blood_decals_enabled", blood_decals_enabled)
	config.set_value("performance", "screen_shake_enabled", screen_shake_enabled)
	config.set_value("performance", "explosion_lights_enabled", explosion_lights_enabled)
	config.set_value("performance", "ai_enabled", ai_enabled)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("PerformanceSettings: Failed to save settings: " + str(error))


## Load settings from file.
func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == OK:
		particles_enabled = config.get_value("performance", "particles_enabled", true)
		blood_decals_enabled = config.get_value("performance", "blood_decals_enabled", true)
		screen_shake_enabled = config.get_value("performance", "screen_shake_enabled", true)
		explosion_lights_enabled = config.get_value("performance", "explosion_lights_enabled", true)
		ai_enabled = config.get_value("performance", "ai_enabled", true)
	else:
		particles_enabled = true
		blood_decals_enabled = true
		screen_shake_enabled = true
		explosion_lights_enabled = true
		ai_enabled = true


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[PerformanceSettings] " + message)
	else:
		print("[PerformanceSettings] " + message)
