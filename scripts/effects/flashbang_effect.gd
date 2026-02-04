extends Node2D
## Flashbang visual effect using shadow-enabled PointLight2D.
##
## Creates a bright flash of light at the grenade explosion position.
## The light uses shadow_enabled = true so it doesn't pass through walls,
## matching how weapon muzzle flash works (Issue #469).
##
## The effect fades out over FLASH_DURATION seconds and then self-destructs.

## Duration of the flashbang effect in seconds.
const FLASH_DURATION: float = 0.5

## Starting energy (intensity) of the point light.
## Flashbang is much brighter than muzzle flash.
const LIGHT_START_ENERGY: float = 8.0

## Reference to the point light child node.
var _point_light: PointLight2D = null

## Time tracker for fade animation.
var _elapsed_time: float = 0.0

## Whether the effect has started.
var _is_active: bool = false

## Effect radius (used to scale the light texture).
var effect_radius: float = 400.0


func _ready() -> void:
	# Get reference to the PointLight2D child node
	_point_light = get_node_or_null("PointLight2D")

	# Start the effect
	_start_effect()


## Sets the effect radius and adjusts light texture scale accordingly.
func set_effect_radius(radius: float) -> void:
	effect_radius = radius
	if _point_light:
		# Scale texture to cover the effect radius
		# Base texture is 512x512, so scale = radius / 256 to get desired diameter
		_point_light.texture_scale = radius / 64.0


## Starts the flashbang flash effect.
func _start_effect() -> void:
	_is_active = true
	_elapsed_time = 0.0

	# Set initial light energy
	if _point_light:
		_point_light.energy = LIGHT_START_ENERGY
		_point_light.visible = true


func _process(delta: float) -> void:
	if not _is_active:
		return

	_elapsed_time += delta

	# Calculate fade progress (0 to 1)
	var progress := clampf(_elapsed_time / FLASH_DURATION, 0.0, 1.0)

	# Fade out the light using ease-out curve for more natural falloff
	if _point_light:
		var fade := 1.0 - progress
		# Apply ease-out curve (starts fast, slows down)
		fade = fade * fade
		_point_light.energy = LIGHT_START_ENERGY * fade

	# Check if effect is complete
	if progress >= 1.0:
		_is_active = false
		queue_free()
