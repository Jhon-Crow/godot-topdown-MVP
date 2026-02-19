extends Node2D
class_name AggressionCloud
## Persistent reddish gas cloud that causes enemies to become aggressive toward each other.
##
## Spawned by AggressionGasGrenade on gas release (NOT explosion).
## - Radius: 300px (slightly larger than frag grenade's 225px)
## - Duration: 20 seconds before dissipating
## - Effect: Enemies in the cloud become aggressive for 10 seconds (refreshable)
## - Visual: Dark reddish semi-transparent gas cloud (тёмно-красноватого оттенка)
##
## Per issue #675 requirements:
## - облако газа (чуть больше радиуса поражения наступательной гранаты)
## - враги начинают воспринимать других врагов как врагов
## - эффект длится 10 секунд и обновляется при повторном контакте с газом
## - газ рассеивается через 20 секунд
## - облако красноватого газа
##
## Per issue #718 fix:
## - Visual effect was not visible (alpha too low, z_index wrong)
## - Now uses GPUParticles2D created programmatically for reliability
## - Higher opacity and proper z_index for visibility

## Radius of the gas cloud in pixels.
@export var cloud_radius: float = 300.0

## How long the cloud persists before dissipating (seconds).
@export var cloud_duration: float = 20.0

## How long the aggression effect lasts on each enemy (seconds).
@export var aggression_effect_duration: float = 10.0

## Time remaining before cloud dissipates.
var _time_remaining: float = 0.0

## Area2D for detecting enemies in the cloud.
var _detection_area: Area2D = null

## Visual representation of the gas cloud (can be GPUParticles2D or Sprite2D fallback).
var _cloud_visual: Node2D = null

## Whether we're using particle system (true) or sprite fallback (false).
var _using_particles: bool = false

## Timer for periodic effect application (every 0.5s).
var _effect_tick_timer: float = 0.0
const EFFECT_TICK_INTERVAL: float = 0.5


func _ready() -> void:
	FileLogger.info("[AggressionCloud] _ready() called at %s" % str(global_position))
	_time_remaining = cloud_duration
	_setup_detection_area()
	_setup_cloud_visual()
	FileLogger.info("[AggressionCloud] Cloud spawned at %s, radius=%.0f, duration=%.0fs, particles=%s" % [
		str(global_position), cloud_radius, cloud_duration, str(_using_particles)
	])


func _physics_process(delta: float) -> void:
	_time_remaining -= delta

	# Periodic effect application to enemies in the cloud
	_effect_tick_timer += delta
	if _effect_tick_timer >= EFFECT_TICK_INTERVAL:
		_effect_tick_timer = 0.0
		_apply_effect_to_enemies_in_cloud()

	# Update visual fade (cloud becomes more transparent as it dissipates)
	_update_cloud_visual()

	# Check if cloud should dissipate
	if _time_remaining <= 0.0:
		FileLogger.info("[AggressionCloud] Cloud dissipated at %s" % str(global_position))
		queue_free()


## Set up the Area2D for detecting enemies inside the cloud.
func _setup_detection_area() -> void:
	_detection_area = Area2D.new()
	_detection_area.name = "DetectionArea"
	# Monitor bodies (enemies are CharacterBody2D)
	_detection_area.monitoring = true
	_detection_area.monitorable = false
	# Detect enemies (collision layer 2)
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = 2

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = cloud_radius
	shape.shape = circle
	shape.name = "CollisionShape2D"

	_detection_area.add_child(shape)
	add_child(_detection_area)


## Set up the visual representation of the gas cloud.
## Fixed issue #718: Effect was not visible due to low alpha (0.35) and z_index = -1
## Now creates GPUParticles2D programmatically for reliability (no external scene dependency)
func _setup_cloud_visual() -> void:
	# Try to create particle system first (preferred approach)
	var particles := _create_particle_visual()
	if particles:
		_cloud_visual = particles
		_using_particles = true
		add_child(_cloud_visual)
		FileLogger.info("[AggressionCloud] Particle system created successfully")
	else:
		# Fallback: use enhanced sprite visual
		FileLogger.warning("[AggressionCloud] Could not create particles, using sprite fallback")
		_cloud_visual = _create_sprite_fallback()
		_using_particles = false
		add_child(_cloud_visual)


## Create GPUParticles2D visual programmatically (no external scene file needed).
## Returns null if particle creation fails.
func _create_particle_visual() -> GPUParticles2D:
	var particles := GPUParticles2D.new()

	# Create gradient for particle color (dark reddish, тёмно-красноватого оттенка)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.6, 0.15, 0.1, 0.9),   # Start: dark red, 90% opacity
		Color(0.55, 0.18, 0.12, 0.75), # Early: slightly lighter
		Color(0.5, 0.2, 0.15, 0.5),   # Mid: fading
		Color(0.45, 0.15, 0.1, 0.0)   # End: fully transparent
	])

	# Create gradient texture
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	# Create particle material
	var material := ParticleProcessMaterial.new()
	material.lifetime_randomness = 0.4
	material.particle_flag_disable_z = true
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = cloud_radius * 0.8  # Emit within cloud area
	material.direction = Vector3(0, -1, 0)  # Drift upward
	material.spread = 180.0  # Full spread
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 20.0
	material.gravity = Vector3(0, -10, 0)  # Slight upward pull (negative Y = up in 2D)
	material.damping_min = 5.0
	material.damping_max = 15.0
	material.scale_min = 0.8
	material.scale_max = 2.5
	material.color = Color(0.55, 0.17, 0.12, 0.85)  # Base color with high alpha

	# Configure particle system
	particles.z_index = 1  # Draw above ground, below UI
	particles.amount = 100  # Number of particles
	particles.process_material = material
	particles.texture = texture
	particles.lifetime = 4.0  # Particle lifetime
	particles.preprocess = 1.0  # Pre-fill so effect is visible immediately
	particles.explosiveness = 0.1  # Low explosiveness for continuous flow
	particles.randomness = 0.3
	particles.one_shot = false  # Continuous emission
	particles.emitting = true  # Start emitting immediately

	return particles


## Create a sprite-based fallback visual with enhanced visibility.
func _create_sprite_fallback() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _create_cloud_texture(int(cloud_radius))
	# Much higher alpha (0.75 vs original 0.35) for clear visibility
	sprite.modulate = Color(0.7, 0.2, 0.15, 0.75)
	# Draw above ground (z_index = 1) instead of below (-1)
	sprite.z_index = 1
	return sprite


## Apply aggression effect to all enemies currently in the cloud.
func _apply_effect_to_enemies_in_cloud() -> void:
	if _detection_area == null:
		return

	var bodies := _detection_area.get_overlapping_bodies()
	for body in bodies:
		if not is_instance_valid(body):
			continue
		# Check if this is an enemy (in "enemies" group)
		if body.is_in_group("enemies") and body is Node2D:
			_apply_aggression_to_enemy(body)


## Apply aggression effect to a single enemy.
func _apply_aggression_to_enemy(enemy: Node2D) -> void:
	# Check line of sight (gas doesn't go through walls)
	if not _has_line_of_sight_to(enemy):
		return

	# Use StatusEffectsManager to apply the aggression effect
	var status_manager: Node = get_node_or_null("/root/StatusEffectsManager")
	if status_manager and status_manager.has_method("apply_aggression"):
		status_manager.apply_aggression(enemy, aggression_effect_duration)
	else:
		# Fallback: apply directly to enemy if it supports the method
		if enemy.has_method("set_aggressive"):
			enemy.set_aggressive(true)


## Check if there's line of sight from cloud center to target.
func _has_line_of_sight_to(target: Node2D) -> bool:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		target.global_position
	)
	query.collision_mask = 4  # Only check against obstacles
	var result := space_state.intersect_ray(query)
	return result.is_empty()


## Update cloud visual based on remaining time.
## For particles: stops emission in last 5 seconds for natural dissipation
## For sprite fallback: fades alpha gradually
func _update_cloud_visual() -> void:
	if _cloud_visual == null:
		return

	if _using_particles:
		# Stop emitting new particles in the last 5 seconds
		# This allows existing particles (4s lifetime) to naturally fade out
		var particles := _cloud_visual as GPUParticles2D
		if particles and _time_remaining < 5.0 and particles.emitting:
			particles.emitting = false
			FileLogger.info("[AggressionCloud] Stopped particle emission, cloud dissipating")
	else:
		# For sprite fallback: fade out gradually
		var sprite := _cloud_visual as Sprite2D
		if sprite:
			if _time_remaining < 5.0:
				var fade_ratio := _time_remaining / 5.0
				sprite.modulate.a = 0.75 * fade_ratio
			else:
				sprite.modulate.a = 0.75


## Create a circular cloud texture with soft edges (legacy/fallback).
func _create_cloud_texture(radius: int) -> ImageTexture:
	var size := radius * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(radius, radius)

	for x in range(size):
		for y in range(size):
			var pos := Vector2(x, y)
			var distance := pos.distance_to(center)
			if distance <= radius:
				# Soft falloff from center - denser in the middle
				var alpha := 1.0 - (distance / radius)
				alpha = alpha * alpha  # Quadratic falloff for softer edges
				# Dark reddish gas color with alpha
				image.set_pixel(x, y, Color(0.65, 0.18, 0.12, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)
