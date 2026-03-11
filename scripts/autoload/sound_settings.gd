extends Node
## SoundSettings - Global audio volume manager (Issue #839).
##
## Provides centralized control over audio volumes:
## - Effects volume (громкость эффектов): controls all sound effects
## - Music volume (громкость музыки): controls background music
##
## Volumes are stored as linear values [0.0, 1.0] and converted to dB for
## Godot's audio bus system. Settings are persisted to disk.

## Signal emitted when any sound setting changes.
signal settings_changed

## Linear volume for sound effects [0.0, 1.0]. Default is full volume.
var effects_volume: float = 1.0

## Linear volume for music [0.0, 1.0]. Default is full volume.
var music_volume: float = 1.0

## Name of the audio bus used for sound effects.
const EFFECTS_BUS: String = "Effects"

## Name of the audio bus used for music.
const MUSIC_BUS: String = "Music"

## Settings file path for persistence.
const SETTINGS_PATH: String = "user://sound_settings.cfg"

## Minimum volume in dB (effectively silent).
const MIN_VOLUME_DB: float = -80.0

## Maximum volume in dB (full volume).
const MAX_VOLUME_DB: float = 0.0


func _ready() -> void:
	_load_settings()
	_apply_volumes()
	_log_to_file("SoundSettings initialized - effects: %.2f, music: %.2f" % [effects_volume, music_volume])


## Sets the effects volume.
## @param volume: Linear volume value [0.0, 1.0].
func set_effects_volume(volume: float) -> void:
	volume = clamp(volume, 0.0, 1.0)
	if not is_equal_approx(effects_volume, volume):
		effects_volume = volume
		_apply_effects_volume()
		settings_changed.emit()
		_save_settings()
		_log_to_file("Effects volume set to %.2f" % volume)


## Gets the current effects volume as a linear value [0.0, 1.0].
func get_effects_volume() -> float:
	return effects_volume


## Sets the music volume.
## @param volume: Linear volume value [0.0, 1.0].
func set_music_volume(volume: float) -> void:
	volume = clamp(volume, 0.0, 1.0)
	if not is_equal_approx(music_volume, volume):
		music_volume = volume
		_apply_music_volume()
		settings_changed.emit()
		_save_settings()
		_log_to_file("Music volume set to %.2f" % volume)


## Gets the current music volume as a linear value [0.0, 1.0].
func get_music_volume() -> float:
	return music_volume


## Converts a linear volume [0.0, 1.0] to decibels.
## Returns MIN_VOLUME_DB for zero volume (silence).
func linear_to_db(linear: float) -> float:
	if linear <= 0.0:
		return MIN_VOLUME_DB
	return 20.0 * log(linear) / log(10.0)


## Applies effects volume to the Effects audio bus (or Master bus as fallback).
func _apply_effects_volume() -> void:
	var bus_idx := AudioServer.get_bus_index(EFFECTS_BUS)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(effects_volume))
	else:
		# Fallback: apply to Master bus if Effects bus doesn't exist
		var master_idx := AudioServer.get_bus_index("Master")
		if master_idx >= 0:
			AudioServer.set_bus_volume_db(master_idx, linear_to_db(effects_volume))


## Applies music volume to the Music audio bus.
func _apply_music_volume() -> void:
	var bus_idx := AudioServer.get_bus_index(MUSIC_BUS)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(music_volume))


## Applies all stored volumes to audio buses.
func _apply_volumes() -> void:
	_apply_effects_volume()
	_apply_music_volume()


## Saves settings to file.
func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("sound", "effects_volume", effects_volume)
	config.set_value("sound", "music_volume", music_volume)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("SoundSettings: Failed to save settings: " + str(error))


## Loads settings from file.
func _load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == OK:
		effects_volume = config.get_value("sound", "effects_volume", 1.0)
		music_volume = config.get_value("sound", "music_volume", 1.0)
		# Clamp values in case the file was edited manually
		effects_volume = clamp(effects_volume, 0.0, 1.0)
		music_volume = clamp(music_volume, 0.0, 1.0)
	else:
		effects_volume = 1.0
		music_volume = 1.0


## Logs a message via FileLogger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[SoundSettings] " + message)
	else:
		print("[SoundSettings] " + message)
