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

## Settings file path for persistence.
const SETTINGS_PATH: String = "user://gameplay_settings.cfg"

## Minimum blood amount multiplier.
const MIN_BLOOD_AMOUNT: float = 0.0

## Maximum blood amount multiplier.
const MAX_BLOOD_AMOUNT: float = 3.0


func _ready() -> void:
	_load_settings()
	_log_to_file("GameplaySettings initialized - blood_amount: %.2f" % blood_amount)


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


## Saves settings to file.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("gameplay", "blood_amount", blood_amount)
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
	else:
		blood_amount = 1.0


## Logs a message via FileLogger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[GameplaySettings] " + message)
	else:
		print("[GameplaySettings] " + message)
