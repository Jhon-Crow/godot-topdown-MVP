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
## Slightly less bright than flashbang (8.0) but still very bright.
const LIGHT_ENERGY: float = 5.0

## Texture scale for the light cone size.
const LIGHT_TEXTURE_SCALE: float = 4.0

## Reference to the PointLight2D child node.
var _point_light: PointLight2D = null

## Whether the flashlight is currently active (on).
var _is_on: bool = false


func _ready() -> void:
	_point_light = get_node_or_null("PointLight2D")
	# Start with light off
	_set_light_visible(false)


## Turn the flashlight on.
func turn_on() -> void:
	if _is_on:
		return
	_is_on = true
	_set_light_visible(true)


## Turn the flashlight off.
func turn_off() -> void:
	if not _is_on:
		return
	_is_on = false
	_set_light_visible(false)


## Check if the flashlight is currently on.
func is_on() -> bool:
	return _is_on


## Set the light visibility and energy.
func _set_light_visible(visible_state: bool) -> void:
	if _point_light:
		_point_light.visible = visible_state
		_point_light.energy = LIGHT_ENERGY if visible_state else 0.0
