extends Node
## GameplaySettings - Global gameplay preferences manager (Issue #1090).
##
## Provides centralized control over gameplay-affecting visual settings:
## - Blood amount (количество крови): multiplier for blood decals spawned per hit
##
## Settings are persisted to disk.

## Signal emitted when any gameplay setting changes.
signal settings_changed

## Blood amount multiplier [0.0, 3.0]. Default is 1.0 (normal amount).
## 0.0 = no blood, 1.0 = default, 2.0 = double, 3.0 = triple
var blood_amount: float = 1.0

## Whether wall hit dust particles are enabled (Issue #1145).
## When enabled (default), a dust puff effect appears when bullets hit walls.
## When disabled, no dust particles are spawned — improves FPS on low-end hardware.
## Kept for backward compatibility — new code uses dust_quality instead.
var wall_hit_particles_enabled: bool = true

## Dust particle quality level (Issue #1487).
## 0 = Full — all particles, default visuals.
## 1 = Half — amount_ratio 0.5, fewer particles, better FPS on weak GPUs.
## 2 = Off  — no dust spawned, maximum FPS gain.
const DUST_QUALITY_FULL: int = 0
const DUST_QUALITY_HALF: int = 1
const DUST_QUALITY_OFF: int = 2
var dust_quality: int = DUST_QUALITY_FULL

## Whether revolver aim assist (slight bullet homing) is enabled (Issue #1332).
## When enabled (default), revolver bullets gently steer toward enemies near the crosshair.
var revolver_aim_assist_enabled: bool = true

## Settings file path for persistence.
const SETTINGS_PATH: String = "user://gameplay_settings.cfg"

## Minimum blood amount multiplier.
const MIN_BLOOD_AMOUNT: float = 0.0

## Maximum blood amount multiplier.
const MAX_BLOOD_AMOUNT: float = 3.0


func _ready() -> void:
	_load_settings()
	_log_to_file("GameplaySettings initialized - blood_amount: %.2f, wall_hit_particles: %s, revolver_aim_assist: %s, dust_quality: %d" % [blood_amount, wall_hit_particles_enabled, revolver_aim_assist_enabled, dust_quality])


## Sets the blood amount multiplier.
## @param amount: Multiplier value [0.0, 3.0]. 1.0 = default amount.
func set_blood_amount(amount: float) -> void:
	amount = clamp(amount, MIN_BLOOD_AMOUNT, MAX_BLOOD_AMOUNT)
	if not is_equal_approx(blood_amount, amount):
		blood_amount = amount
		settings_changed.emit()
		_save_settings()
		_log_to_file("Blood amount set to %.2f" % amount)


## Gets the current blood amount multiplier [0.0, 3.0].
func get_blood_amount() -> float:
	return blood_amount


## Sets whether wall hit dust particles are enabled (Issue #1145).
## @param enabled: true to show dust effects, false to skip them.
func set_wall_hit_particles_enabled(enabled: bool) -> void:
	if wall_hit_particles_enabled != enabled:
		wall_hit_particles_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Wall hit particles %s" % ("enabled" if enabled else "disabled"))


## Returns whether wall hit dust particles are enabled (Issue #1145).
func is_wall_hit_particles_enabled() -> bool:
	return wall_hit_particles_enabled


## Sets the dust particle quality level (Issue #1487).
## @param quality: DUST_QUALITY_FULL (0), DUST_QUALITY_HALF (1), or DUST_QUALITY_OFF (2).
func set_dust_quality(quality: int) -> void:
	quality = clampi(quality, DUST_QUALITY_FULL, DUST_QUALITY_OFF)
	if dust_quality != quality:
		dust_quality = quality
		settings_changed.emit()
		_save_settings()
		_log_to_file("Dust quality set to %d" % quality)


## Returns the current dust quality level (Issue #1487).
func get_dust_quality() -> int:
	return dust_quality


## Sets whether revolver aim assist (slight bullet homing) is enabled (Issue #1332).
## @param enabled: true to enable aim assist, false to disable it.
func set_revolver_aim_assist_enabled(enabled: bool) -> void:
	if revolver_aim_assist_enabled != enabled:
		revolver_aim_assist_enabled = enabled
		settings_changed.emit()
		_save_settings()
		_log_to_file("Revolver aim assist %s" % ("enabled" if enabled else "disabled"))


## Returns whether revolver aim assist is enabled (Issue #1332).
func is_revolver_aim_assist_enabled() -> bool:
	return revolver_aim_assist_enabled


## Saves settings to file.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("gameplay", "blood_amount", blood_amount)
	config.set_value("gameplay", "wall_hit_particles_enabled", wall_hit_particles_enabled)
	config.set_value("gameplay", "revolver_aim_assist_enabled", revolver_aim_assist_enabled)
	config.set_value("gameplay", "dust_quality", dust_quality)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("GameplaySettings: Failed to save settings: " + str(error))


## Loads settings from file.
func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == OK:
		blood_amount = config.get_value("gameplay", "blood_amount", 1.0)
		blood_amount = clamp(blood_amount, MIN_BLOOD_AMOUNT, MAX_BLOOD_AMOUNT)
		wall_hit_particles_enabled = config.get_value("gameplay", "wall_hit_particles_enabled", true)
		revolver_aim_assist_enabled = config.get_value("gameplay", "revolver_aim_assist_enabled", true)
		dust_quality = config.get_value("gameplay", "dust_quality", DUST_QUALITY_FULL)
		dust_quality = clampi(dust_quality, DUST_QUALITY_FULL, DUST_QUALITY_OFF)
	else:
		blood_amount = 1.0
		wall_hit_particles_enabled = true
		revolver_aim_assist_enabled = true
		dust_quality = DUST_QUALITY_FULL


## Logs a message via FileLogger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[GameplaySettings] " + message)
	else:
		print("[GameplaySettings] " + message)
