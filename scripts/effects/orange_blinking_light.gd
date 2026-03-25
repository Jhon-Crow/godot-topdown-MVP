extends Node2D
## Orange blinking warning light for the Factory level (Issue #1436).
##
## Simulates an industrial emergency/warning light (мигалка) that:
## - Rotates continuously like a beacon lamp
## - Blinks on and off (alternates between two PointLight2D beams pointing
##   in opposite directions to give a "light in two directions" effect)
## - Emits orange light with shadows
##
## The node contains two PointLight2D children (LightA and LightB) pointing
## in opposite directions (180 degrees apart). The whole Node2D rotates at
## ROTATION_SPEED radians/sec. The lights blink by toggling energy between
## LIGHT_ON_ENERGY and 0.0 on a BLINK_INTERVAL cycle.

## Rotation speed in radians per second (about 1 full turn per 2 seconds).
const ROTATION_SPEED: float = PI

## Blink interval in seconds. Light is ON for this duration, then OFF for
## the same duration (50% duty cycle).
const BLINK_INTERVAL: float = 0.4

## Light energy (brightness) when on.
const LIGHT_ON_ENERGY: float = 4.0

## Orange color for industrial warning lamps.
const LIGHT_COLOR: Color = Color(1.0, 0.45, 0.05, 1.0)

## Accumulated time used to determine the current blink phase.
var _blink_timer: float = 0.0

## Reference to the two directional light children.
var _light_a: PointLight2D = null
var _light_b: PointLight2D = null


func _ready() -> void:
	_light_a = get_node_or_null("LightA")
	_light_b = get_node_or_null("LightB")


func _process(delta: float) -> void:
	# Rotate the whole beacon
	rotation += ROTATION_SPEED * delta

	# Blink: toggle lights every BLINK_INTERVAL seconds
	_blink_timer += delta
	var phase: float = fmod(_blink_timer, BLINK_INTERVAL * 2.0)
	var lights_on: bool = phase < BLINK_INTERVAL

	if _light_a:
		_light_a.energy = LIGHT_ON_ENERGY if lights_on else 0.0
	if _light_b:
		_light_b.energy = LIGHT_ON_ENERGY if lights_on else 0.0
