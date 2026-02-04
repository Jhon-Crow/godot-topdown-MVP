extends Node2D
## Explosion flash effect combining particles and dynamic lighting with wall occlusion.
##
## Creates a bright flash of light at the explosion point that respects wall geometry.
## Uses PointLight2D with shadow_enabled=true to automatically prevent the flash
## from being visible through walls (same approach as muzzle_flash.gd).
##
## Issue #470 Fix: Unlike a simple Sprite2D which ignores walls, the PointLight2D's
## shadow system ensures the flash is occluded by any obstacle that casts shadows.

## Explosion type determines visual appearance.
enum ExplosionType {
	FLASHBANG,  # Bright white flash
	FRAG        # Orange/red explosion
}

## Duration of the explosion flash effect in seconds.
const FLASH_DURATION: float = 0.4

## Starting energy (intensity) of the point light for flashbang.
const FLASHBANG_LIGHT_ENERGY: float = 8.0

## Starting energy (intensity) of the point light for frag.
const FRAG_LIGHT_ENERGY: float = 6.0

## The type of explosion (affects color and intensity).
var explosion_type: ExplosionType = ExplosionType.FLASHBANG

## Effect radius (used to scale the light).
var effect_radius: float = 400.0

## Reference to the point light child node.
var _point_light: PointLight2D = null

## Reference to the particles child node.
var _particles: GPUParticles2D = null

## Time tracker for fade animation.
var _elapsed_time: float = 0.0

## Whether the effect has started.
var _is_active: bool = false


func _ready() -> void:
	# Get references to child nodes
	_point_light = get_node_or_null("PointLight2D")
	_particles = get_node_or_null("GPUParticles2D")

	# Configure based on explosion type
	_configure_for_type()

	# Start the effect
	_start_effect()


## Configures the effect based on explosion type.
func _configure_for_type() -> void:
	if _point_light == null:
		return

	if explosion_type == ExplosionType.FLASHBANG:
		# Flashbang: bright white flash
		_point_light.color = Color(1.0, 0.95, 0.9, 1.0)
		_point_light.energy = FLASHBANG_LIGHT_ENERGY
		# Scale light based on effect radius (flashbang has larger radius)
		_point_light.texture_scale = effect_radius / 100.0
	else:
		# Frag: orange/red explosion
		_point_light.color = Color(1.0, 0.6, 0.2, 1.0)
		_point_light.energy = FRAG_LIGHT_ENERGY
		# Scale light based on effect radius
		_point_light.texture_scale = effect_radius / 80.0

	# Update particle color to match
	if _particles and _particles.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = _particles.process_material as ParticleProcessMaterial
		if explosion_type == ExplosionType.FLASHBANG:
			mat.color = Color(1.0, 1.0, 0.9, 1.0)
		else:
			mat.color = Color(1.0, 0.7, 0.3, 1.0)


## Starts the explosion flash effect.
func _start_effect() -> void:
	_is_active = true
	_elapsed_time = 0.0

	# Start particles emitting
	if _particles:
		_particles.emitting = true

	# Set initial light energy
	if _point_light:
		if explosion_type == ExplosionType.FLASHBANG:
			_point_light.energy = FLASHBANG_LIGHT_ENERGY
		else:
			_point_light.energy = FRAG_LIGHT_ENERGY
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
		var start_energy: float
		if explosion_type == ExplosionType.FLASHBANG:
			start_energy = FLASHBANG_LIGHT_ENERGY
		else:
			start_energy = FRAG_LIGHT_ENERGY
		_point_light.energy = start_energy * fade

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
	var cleanup_delay := 0.3
	if _particles:
		cleanup_delay = _particles.lifetime + 0.2

	await tree.create_timer(cleanup_delay).timeout

	if is_instance_valid(self):
		queue_free()


## Static helper to create and configure the explosion flash.
## Called by GrenadeTimer or other scripts to spawn the effect.
static func create_at(pos: Vector2, type: ExplosionType, radius: float, parent: Node) -> void:
	var scene: PackedScene = load("res://scenes/effects/ExplosionFlash.tscn")
	if scene == null:
		push_error("[ExplosionFlash] Failed to load ExplosionFlash.tscn")
		return

	var instance: Node2D = scene.instantiate() as Node2D
	if instance == null:
		push_error("[ExplosionFlash] Failed to instantiate ExplosionFlash")
		return

	instance.global_position = pos
	instance.explosion_type = type
	instance.effect_radius = radius

	parent.add_child(instance)
