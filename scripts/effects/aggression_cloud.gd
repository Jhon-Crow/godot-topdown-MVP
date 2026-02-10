extends Node2D
class_name AggressionCloud
## Persistent reddish gas cloud that causes enemies to become aggressive toward each other.
##
## Spawned by AggressionGasGrenade on gas release (NOT explosion).
## - Radius: 300px (slightly larger than frag grenade's 225px)
## - Duration: 20 seconds before dissipating
## - Effect: Enemies in the cloud become aggressive for 10 seconds (refreshable)
## - Visual: Reddish semi-transparent gas cloud
##
## Per issue #675 requirements:
## - облако газа (чуть больше радиуса поражения наступательной гранаты)
## - враги начинают воспринимать других врагов как врагов
## - эффект длится 10 секунд и обновляется при повторном контакте с газом
## - газ рассеивается через 20 секунд
## - облако красноватого газа

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

## Visual representation of the gas cloud (particle system).
var _cloud_particles: GPUParticles2D = null

## Timer for periodic effect application (every 0.5s).
var _effect_tick_timer: float = 0.0
const EFFECT_TICK_INTERVAL: float = 0.5


func _ready() -> void:
	_time_remaining = cloud_duration
	_setup_detection_area()
	_setup_cloud_visual()
	FileLogger.info("[AggressionCloud] Cloud spawned at %s, radius=%.0f, duration=%.0fs" % [str(global_position), cloud_radius, cloud_duration])


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


## Set up the visual representation of the gas cloud using particles.
## Fixed issue #718: Effect was not visible due to low alpha (0.35) and z_index = -1
## Now uses GPUParticles2D matching codebase pattern (like DustEffect, BloodEffect)
func _setup_cloud_visual() -> void:
	# Load the particle effect scene
	var particle_scene := load("res://scenes/effects/AggressionCloudEffect.tscn")
	if particle_scene:
		_cloud_particles = particle_scene.instantiate() as GPUParticles2D
		if _cloud_particles:
			# Configure for continuous emission over cloud duration
			_cloud_particles.emitting = true
			_cloud_particles.one_shot = false
			# Particle lifetime is 5s, so we need to stop emitting after 15s
			# This way last particles finish at 20s total
			add_child(_cloud_particles)

			FileLogger.info("[AggressionCloud] Particle system created for gas cloud")
	else:
		# Fallback: create basic visual if scene not found
		FileLogger.warning("[AggressionCloud] Could not load particle scene, using fallback visual")
		_create_fallback_visual()


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
## Stops particle emission in the last 5 seconds so cloud naturally dissipates
func _update_cloud_visual() -> void:
	if _cloud_particles == null:
		return

	# Stop emitting new particles in the last 5 seconds
	# This allows existing particles (5s lifetime) to naturally fade out
	if _time_remaining < 5.0:
		if _cloud_particles.emitting:
			_cloud_particles.emitting = false
			FileLogger.info("[AggressionCloud] Stopped particle emission, cloud dissipating")


## Fallback visual if particle scene cannot be loaded (for backwards compatibility).
## Creates a simple sprite-based visual (legacy approach, replaced by particles).
func _create_fallback_visual() -> void:
	var fallback_sprite := Sprite2D.new()
	fallback_sprite.texture = _create_cloud_texture(int(cloud_radius))
	# Higher alpha than before (0.7 vs 0.35) to improve visibility
	fallback_sprite.modulate = Color(0.9, 0.25, 0.2, 0.7)
	# Draw above ground (z_index = 1) instead of below (-1)
	fallback_sprite.z_index = 1
	add_child(fallback_sprite)
	_cloud_particles = fallback_sprite  # Store reference for lifecycle management


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
				# Reddish gas color with alpha
				image.set_pixel(x, y, Color(0.85, 0.2, 0.15, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)
