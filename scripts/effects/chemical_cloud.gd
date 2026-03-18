extends Node2D
class_name ChemicalCloud
## Persistent caustic yellow gas cloud that causes enemies to create illusory copies (Issue #1129).
##
## Spawned by ChemicalGasGrenade on gas release (NOT explosion).
## - Radius: 300px (same as aggression gas grenade)
## - Duration: 20 seconds before dissipating
## - Effect: All enemies in cloud create 1–4 illusory copies for 20 seconds
## - Visual: Caustic yellow gas cloud (едкого жёлтого цвета)
## - Guard: If player is already under this effect, cloud has no new effect
##
## Per issue #1129 requirements:
## - выглядит и выделяет газ как газовая граната игрока, но газ едкого жёлтого цвета
## - эффект: все враги создают иллюзорные копии (от 1 до 4), эффект длится 20 секунд
## - все иллюзорные копии врага исчезают, если убит оригинал
## - когда эффект гранаты истекает, все иллюзорные копии исчезают

## Radius of the gas cloud in pixels.
@export var cloud_radius: float = 300.0

## How long the cloud persists before dissipating (seconds).
@export var cloud_duration: float = 20.0

## How long the illusion effect lasts (seconds).
@export var illusion_effect_duration: float = 20.0

## Time remaining before cloud dissipates.
var _time_remaining: float = 0.0

## Area2D for detecting enemies in the cloud.
var _detection_area: Area2D = null

## Visual representation of the gas cloud.
var _cloud_visual: Node2D = null

## Whether we're using particle system (true) or sprite fallback (false).
var _using_particles: bool = false

## Timer for initial effect application (apply once on spawn, not repeatedly).
var _initial_applied: bool = false

## Timer for periodic effect application.
var _effect_tick_timer: float = 0.0
const EFFECT_TICK_INTERVAL: float = 0.5


func _ready() -> void:
	FileLogger.info("[ChemicalCloud] _ready() called at %s" % str(global_position))
	_time_remaining = cloud_duration
	_setup_detection_area()
	_setup_cloud_visual()
	FileLogger.info("[ChemicalCloud] Cloud spawned at %s, radius=%.0f, duration=%.0fs, particles=%s" % [
		str(global_position), cloud_radius, cloud_duration, str(_using_particles)
	])


func _physics_process(delta: float) -> void:
	_time_remaining -= delta

	# Apply initial effect once when cloud first appears
	if not _initial_applied:
		_initial_applied = true
		_apply_effect_to_enemies_in_cloud()

	# Periodic effect re-check (enemies that walk into cloud later)
	_effect_tick_timer += delta
	if _effect_tick_timer >= EFFECT_TICK_INTERVAL:
		_effect_tick_timer = 0.0
		_apply_effect_to_enemies_in_cloud()

	# Update visual fade
	_update_cloud_visual()

	# Check if cloud should dissipate
	if _time_remaining <= 0.0:
		FileLogger.info("[ChemicalCloud] Cloud dissipated at %s" % str(global_position))
		queue_free()


## Set up the Area2D for detecting enemies inside the cloud.
func _setup_detection_area() -> void:
	_detection_area = Area2D.new()
	_detection_area.name = "DetectionArea"
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


## Set up the visual representation of the gas cloud (caustic yellow color).
func _setup_cloud_visual() -> void:
	var particles := _create_particle_visual()
	if particles:
		_cloud_visual = particles
		_using_particles = true
		add_child(_cloud_visual)
		FileLogger.info("[ChemicalCloud] Particle system created successfully")
	else:
		FileLogger.warning("[ChemicalCloud] Could not create particles, using sprite fallback")
		_cloud_visual = _create_sprite_fallback()
		_using_particles = false
		add_child(_cloud_visual)


## Create GPUParticles2D visual programmatically with caustic yellow color.
func _create_particle_visual() -> GPUParticles2D:
	var particles := GPUParticles2D.new()

	# Create gradient for particle color (caustic yellow, едкого жёлтого цвета)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.8, 0.8, 0.1, 0.9),   # Start: bright yellow, 90% opacity
		Color(0.75, 0.75, 0.1, 0.75), # Early: slightly darker
		Color(0.7, 0.7, 0.08, 0.5),   # Mid: fading
		Color(0.6, 0.6, 0.05, 0.0)    # End: fully transparent
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
	material.emission_sphere_radius = cloud_radius * 0.8
	material.direction = Vector3(0, -1, 0)  # Drift upward
	material.spread = 180.0
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 20.0
	material.gravity = Vector3(0, -10, 0)
	material.damping_min = 5.0
	material.damping_max = 15.0
	material.scale_min = 0.8
	material.scale_max = 2.5
	material.color = Color(0.75, 0.75, 0.1, 0.85)  # Caustic yellow base color

	# Configure particle system
	particles.z_index = 1
	particles.amount = 100
	particles.process_material = material
	particles.texture = texture
	particles.lifetime = 4.0
	particles.preprocess = 1.0  # Pre-fill so effect is visible immediately
	particles.explosiveness = 0.1
	particles.randomness = 0.3
	particles.one_shot = false
	particles.emitting = true

	return particles


## Create a sprite-based fallback visual with yellow color.
func _create_sprite_fallback() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _create_cloud_texture(int(cloud_radius))
	sprite.modulate = Color(0.8, 0.8, 0.1, 0.75)  # Caustic yellow
	sprite.z_index = 1
	return sprite


## Apply illusion effect to all enemies currently in the cloud.
## Guard: Only applies if player is NOT already under the illusion effect.
func _apply_effect_to_enemies_in_cloud() -> void:
	if _detection_area == null:
		return

	# Guard: If player is already under illusion effect, cloud does nothing (Issue #1129 req.9)
	if _is_player_under_illusion_effect():
		FileLogger.info("[ChemicalCloud] Player already under illusion effect — cloud has no effect")
		return

	var bodies := _detection_area.get_overlapping_bodies()
	for body in bodies:
		if not is_instance_valid(body):
			continue
		if body.is_in_group("enemies") and body is Node2D:
			_apply_illusion_to_enemy(body)


## Check if the player is already under the illusion effect.
func _is_player_under_illusion_effect() -> bool:
	var status_manager: Node = get_node_or_null("/root/StatusEffectsManager")
	if status_manager == null or not status_manager.has_method("is_player_under_illusion"):
		return false
	return status_manager.is_player_under_illusion()


## Apply illusion effect to a single enemy, spawning 1–4 illusory copies.
func _apply_illusion_to_enemy(enemy: Node2D) -> void:
	# Check line of sight (gas doesn't go through walls)
	if not _has_line_of_sight_to(enemy):
		return

	# Skip illusion enemies themselves (they don't spawn more copies)
	if enemy.has_method("is_illusion") and enemy.is_illusion():
		return

	# Use StatusEffectsManager to track illusion state
	var status_manager: Node = get_node_or_null("/root/StatusEffectsManager")
	if status_manager and status_manager.has_method("apply_illusion_to_enemy"):
		# Only spawn copies once per cloud (on initial application)
		if not status_manager.is_enemy_under_illusion(enemy):
			status_manager.apply_illusion_to_enemy(enemy, illusion_effect_duration)
			_spawn_illusion_copies(enemy)
	else:
		# Fallback: spawn copies directly
		_spawn_illusion_copies(enemy)


## Spawn 1–4 illusory copies of an enemy.
func _spawn_illusion_copies(original_enemy: Node2D) -> void:
	var copy_count := randi_range(1, 4)
	FileLogger.info("[ChemicalCloud] Spawning %d illusion copies for enemy at %s" % [copy_count, str(original_enemy.global_position)])

	for i in range(copy_count):
		var illusion := IllusionEnemy.new()
		illusion.original_enemy = original_enemy
		illusion.illusion_duration = illusion_effect_duration

		# Spread copies around the original enemy
		var angle := (TAU / copy_count) * i + randf_range(-0.3, 0.3)
		var spread_radius := randf_range(30.0, 80.0)
		illusion.spawn_offset = Vector2(cos(angle), sin(angle)) * spread_radius

		get_tree().current_scene.add_child(illusion)
		FileLogger.info("[ChemicalCloud] Illusion copy %d spawned" % (i + 1))


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
func _update_cloud_visual() -> void:
	if _cloud_visual == null:
		return

	if _using_particles:
		var particles := _cloud_visual as GPUParticles2D
		if particles and _time_remaining < 5.0 and particles.emitting:
			particles.emitting = false
			FileLogger.info("[ChemicalCloud] Stopped particle emission, cloud dissipating")
	else:
		var sprite := _cloud_visual as Sprite2D
		if sprite:
			if _time_remaining < 5.0:
				var fade_ratio := _time_remaining / 5.0
				sprite.modulate.a = 0.75 * fade_ratio
			else:
				sprite.modulate.a = 0.75


## Create a circular cloud texture with soft edges (fallback).
func _create_cloud_texture(radius: int) -> ImageTexture:
	var size := radius * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(radius, radius)

	for x in range(size):
		for y in range(size):
			var pos := Vector2(x, y)
			var distance := pos.distance_to(center)
			if distance <= radius:
				var alpha := 1.0 - (distance / radius)
				alpha = alpha * alpha
				# Caustic yellow gas color
				image.set_pixel(x, y, Color(0.8, 0.8, 0.1, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)
