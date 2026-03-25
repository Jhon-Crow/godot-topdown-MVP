extends Node2D
## Flashbang visual effect using shadow-enabled PointLight2D.
##
## Creates a bright flash of light at the grenade explosion position.
## The light uses shadow_enabled = true so it doesn't pass through walls,
## matching how weapon muzzle flash works (Issue #469).
##
## Issue #1460 Round 6: Pooling support added. When pooled, the node is NOT
## freed after use — it deactivates itself and returns control to the pool timer.
## The _is_pooled flag prevents queue_free() when the pool manages the node.

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

## Issue #1460 Round 6: When true, the pool manages this node's lifetime.
## Prevents queue_free() so the node can be reused without re-instantiation.
var _is_pooled: bool = false


func _ready() -> void:
	# Get reference to the PointLight2D child node
	_point_light = get_node_or_null("PointLight2D")

	# If not pooled (direct instantiation), start the effect immediately.
	# When pooled, restart_effect() is called explicitly by the pool manager.
	if not _is_pooled:
		_start_effect()


## Sets the effect radius and adjusts light texture scale accordingly.
func set_effect_radius(radius: float) -> void:
	effect_radius = radius
	if _point_light:
		# Scale texture to cover the effect radius
		# Base texture is 512x512, so scale = radius / 256 to get desired diameter
		_point_light.texture_scale = radius / 64.0


## Issue #1460 Round 6: Restarts a pooled effect node without re-instantiation.
## Called by ImpactEffectsManager when reusing a pooled FlashbangEffect node.
func restart_effect() -> void:
	_start_effect()


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
		if _point_light:
			_point_light.visible = false
			_point_light.energy = 0.0
		# Issue #1460 Round 6: Don't queue_free() when pooled — the pool manager
		# returns this node to the pool via a timer. Only free if not pooled.
		if not _is_pooled:
			queue_free()
