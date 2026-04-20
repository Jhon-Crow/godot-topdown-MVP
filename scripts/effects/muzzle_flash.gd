extends Node2D
## Muzzle flash effect combining particles, dynamic lighting, and an additive
## floor-glow sprite.
##
## Creates a brief flash of light and particles at the gun's muzzle when firing.
## The PointLight2D illuminates nearby walls with intensity that fades over
## distance. An additional Sprite2D ("FloorGlow") draws an additive orange glow
## below the muzzle so the flash is clearly visible on the floor on every map,
## even when a map already has warm ambient lighting that dominates the
## PointLight2D contribution (Issue #1845 — Labyrinth Complex).

## Duration of the muzzle flash effect in seconds (3x longer for residual glow).
const FLASH_DURATION: float = 0.3

## Starting energy (intensity) of the point light.
const LIGHT_START_ENERGY: float = 4.5

## Starting alpha of the floor glow sprite.
const FLOOR_GLOW_START_ALPHA: float = 0.9

## Scale applied to the floor glow sprite (256px texture at 1.25x -> ~320px wide glow circle).
const FLOOR_GLOW_SCALE: float = 1.25

## Reference to the point light child node.
var _point_light: PointLight2D = null

## Reference to the particles child node.
var _particles: GPUParticles2D = null

## Reference to the floor glow child node.
var _floor_glow: Sprite2D = null

## Time tracker for fade animation.
var _elapsed_time: float = 0.0

## Whether the effect has started.
var _is_active: bool = false


func _ready() -> void:
	# Get references to child nodes
	_point_light = get_node_or_null("PointLight2D")
	_particles = get_node_or_null("GPUParticles2D")
	_floor_glow = get_node_or_null("FloorGlow")

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

	# Initialise floor glow visibility
	if _floor_glow:
		_floor_glow.scale = Vector2(FLOOR_GLOW_SCALE, FLOOR_GLOW_SCALE)
		_floor_glow.modulate.a = FLOOR_GLOW_START_ALPHA
		_floor_glow.visible = true


func _process(delta: float) -> void:
	if not _is_active:
		return

	_elapsed_time += delta

	# Calculate fade progress (0 to 1)
	var progress := clampf(_elapsed_time / FLASH_DURATION, 0.0, 1.0)

	var fade := 1.0 - progress
	# Apply ease-out curve (starts fast, slows down)
	fade = fade * fade

	# Fade out the light using ease-out curve for more natural falloff
	if _point_light:
		_point_light.energy = LIGHT_START_ENERGY * fade

	# Fade out the floor glow sprite so the flash is visible on any floor
	if _floor_glow:
		_floor_glow.modulate.a = FLOOR_GLOW_START_ALPHA * fade

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
