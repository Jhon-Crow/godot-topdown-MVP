extends Node2D
## Tactical flashlight effect attached to the player's weapon.
##
## Creates a directional beam of bright white light from the weapon barrel.
## Uses PointLight2D with shadow_enabled = true so light doesn't pass through walls.
## The light is toggled on/off by holding the Space key (flashlight_toggle action).
##
## The flashlight is positioned at the weapon barrel offset and rotates
## with the player model to always point in the aiming direction.

## Light energy (brightness) when the flashlight is on.
## Bright white light — same level as flashbang (8.0) for clear visibility.
const LIGHT_ENERGY: float = 8.0

## Texture scale for the light cone size.
const LIGHT_TEXTURE_SCALE: float = 4.0

## Path to the flashlight toggle sound file.
const FLASHLIGHT_SOUND_PATH: String = "res://assets/audio/звук включения и выключения фанарика.mp3"

## Reference to the PointLight2D child node.
var _point_light: PointLight2D = null

## Whether the flashlight is currently active (on).
var _is_on: bool = false

## AudioStreamPlayer for flashlight toggle sound.
var _audio_player: AudioStreamPlayer = null


func _ready() -> void:
	_point_light = get_node_or_null("PointLight2D")
	if _point_light == null:
		FileLogger.info("[FlashlightEffect] WARNING: PointLight2D child not found")
	else:
		FileLogger.info("[FlashlightEffect] PointLight2D found, energy=%.1f, shadow=%s" % [_point_light.energy, str(_point_light.shadow_enabled)])
	# Start with light off
	_set_light_visible(false)
	# Load toggle sound
	_setup_audio()


## Set up the audio player for flashlight toggle sound.
func _setup_audio() -> void:
	if ResourceLoader.exists(FLASHLIGHT_SOUND_PATH):
		var stream = load(FLASHLIGHT_SOUND_PATH)
		if stream:
			_audio_player = AudioStreamPlayer.new()
			_audio_player.stream = stream
			_audio_player.volume_db = 0.0
			add_child(_audio_player)
			FileLogger.info("[FlashlightEffect] Flashlight sound loaded")
	else:
		FileLogger.info("[FlashlightEffect] Flashlight sound not found: %s" % FLASHLIGHT_SOUND_PATH)


## Play the flashlight toggle sound.
func _play_toggle_sound() -> void:
	if _audio_player and is_instance_valid(_audio_player):
		_audio_player.play()


## Turn the flashlight on.
func turn_on() -> void:
	if _is_on:
		return
	_is_on = true
	_set_light_visible(true)
	_play_toggle_sound()


## Turn the flashlight off.
func turn_off() -> void:
	if not _is_on:
		return
	_is_on = false
	_set_light_visible(false)
	_play_toggle_sound()


## Check if the flashlight is currently on.
func is_on() -> bool:
	return _is_on


## Set the light visibility and energy.
func _set_light_visible(visible_state: bool) -> void:
	if _point_light:
		_point_light.visible = visible_state
		_point_light.energy = LIGHT_ENERGY if visible_state else 0.0
