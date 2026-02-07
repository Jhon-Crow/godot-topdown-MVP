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

## Flashlight beam angle in degrees (narrow tactical flashlight beam).
const BEAM_ANGLE_DEGREES: float = 6.0

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
		# Create a narrow cone-shaped texture for 6-degree beam
		_setup_cone_texture()
	# Start with light off
	_set_light_visible(false)
	# Load toggle sound
	_setup_audio()


## Create a cone-shaped texture for the narrow flashlight beam.
## The texture is a radial gradient masked to a narrow cone angle.
func _setup_cone_texture() -> void:
	if not _point_light:
		return

	# Create a 512x512 image for the cone texture
	var size := 512
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var max_radius := size / 2.0
	var half_angle_rad := deg_to_rad(BEAM_ANGLE_DEGREES / 2.0)

	# Fill the image with the cone gradient
	for y in range(size):
		for x in range(size):
			var pos := Vector2(x, y) - center
			var distance := pos.length()
			var angle := pos.angle()  # Angle from center, pointing right is 0

			# Normalize angle to [-PI, PI] range
			# We want the beam to point to the right (0 degrees)
			var angle_from_beam := abs(angle)

			# Check if pixel is within the cone angle
			if angle_from_beam <= half_angle_rad:
				# Inside the cone - apply gradient based on distance
				var distance_factor := 1.0 - (distance / max_radius)
				distance_factor = clamp(distance_factor, 0.0, 1.0)

				# Apply smooth falloff from center
				var intensity := pow(distance_factor, 0.8)

				# Also fade based on angle (softer edges)
				var angle_factor := 1.0 - (angle_from_beam / half_angle_rad)
				angle_factor = pow(angle_factor, 2.0)  # Sharper falloff at edges

				intensity *= angle_factor

				# Set pixel color (white with varying alpha/intensity)
				var color := Color(1.0, 1.0, 1.0, intensity)
				image.set_pixel(x, y, color)
			else:
				# Outside the cone - fully transparent
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	# Convert image to texture and apply to light
	var texture := ImageTexture.create_from_image(image)
	_point_light.texture = texture
	FileLogger.info("[FlashlightEffect] Created cone texture with %d° beam angle" % BEAM_ANGLE_DEGREES)


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
