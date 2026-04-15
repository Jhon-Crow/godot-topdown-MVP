extends Node2D
## Muzzle flash effect combining particles and dynamic lighting.
##
## Creates a brief flash of light and particles at the gun's muzzle when firing.
## The light illuminates nearby walls with intensity that fades over distance.
## Both the particles and light fade out quickly (0.1 seconds) for realistic effect.

## Duration of the muzzle flash effect in seconds (3x longer for residual glow).
const FLASH_DURATION: float = 0.3

## Starting energy (intensity) of the point light (3x larger).
const LIGHT_START_ENERGY: float = 4.5

## Initial alpha for the floor-visible flash sprite.
const SPRITE_START_ALPHA: float = 0.8

## Minimum sprite scale multiplier at the end of the flash.
const SPRITE_END_SCALE_MULTIPLIER: float = 0.55

## Reference to the point light child node.
var _point_light: PointLight2D = null

## Reference to the particles child node.
var _particles: GPUParticles2D = null

## Reference to the additive sprite that keeps the flash readable on flat floors.
var _flash_sprite: Sprite2D = null

## Time tracker for fade animation.
var _elapsed_time: float = 0.0

## Whether the effect has started.
var _is_active: bool = false


func _ready() -> void:
	# Get references to child nodes
	_point_light = get_node_or_null("PointLight2D")
	_particles = get_node_or_null("GPUParticles2D")
	_flash_sprite = get_node_or_null("FlashSprite")

	# Start the effect
	_start_effect()


## Starts the muzzle flash effect.
func _start_effect() -> void:
	_is_active = true
	_elapsed_time = 0.0

	# Start particles emitting
	if _particles:
		_particles.emitting = true

	# Set initial light energy
	if _point_light:
		_point_light.energy = LIGHT_START_ENERGY
		_point_light.visible = true

	if _flash_sprite:
		_flash_sprite.visible = true
		_flash_sprite.modulate = Color(1.0, 1.0, 1.0, SPRITE_START_ALPHA)
		_flash_sprite.scale = Vector2.ONE


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

	if _flash_sprite:
		var sprite_fade := 1.0 - progress
		sprite_fade = sprite_fade * sprite_fade
		_flash_sprite.modulate.a = SPRITE_START_ALPHA * sprite_fade
		var scale_mult := lerpf(1.0, SPRITE_END_SCALE_MULTIPLIER, progress)
		_flash_sprite.scale = Vector2(scale_mult, scale_mult)

	# Check if effect is complete
	if progress >= 1.0:
		_is_active = false
		# Schedule cleanup after particles finish
		_schedule_cleanup()


## Schedules the node for cleanup after particles finish.
func _schedule_cleanup() -> void:
	# Wait a bit for particles to fully fade, then remove
	var tree := get_tree()
	if tree == null:
		queue_free()
		return

	# Use the particle lifetime plus small buffer for cleanup
	var cleanup_delay := 0.2
	if _particles:
		cleanup_delay = _particles.lifetime + 0.1

	await tree.create_timer(cleanup_delay).timeout

	if is_instance_valid(self):
		queue_free()
