extends Node2D
class_name ChemicalCloud
## Chemical gas cloud that creates visual illusion copies of enemies (Issue #1353).
##
## Spawned by the Gas Mask Enemy's chemical grenade. Instead of spawning
## real Enemy clones (which caused severe FPS drops), this creates lightweight
## visual-only IllusionEffect nodes that:
## - Copy the visual appearance of nearby enemies using sprites + shader
## - Follow their original enemy with a fixed offset
## - Fire phantom bullets (only damage the player)
## - Have 1 HP (one-shot by any weapon)
## - Auto-expire after 20 seconds
##
## Performance approach: Uses ~6 nodes per illusion instead of ~50+ for
## a real Enemy clone. No AI, no physics, no navigation — just visuals.

## Radius of the gas cloud in pixels.
@export var cloud_radius: float = 300.0

## How long the cloud persists (seconds).
@export var cloud_duration: float = 20.0

## Number of illusion copies to create per enemy (random range).
@export var min_copies_per_enemy: int = 2

## Maximum copies per enemy.
@export var max_copies_per_enemy: int = 6

## How long each illusion copy lasts (seconds).
@export var illusion_duration: float = 20.0

## Time remaining before cloud dissipates.
var _time_remaining: float = 0.0

## Area2D for detecting enemies and player in the cloud.
var _detection_area: Area2D = null

## Visual cloud particle system.
var _cloud_visual: Node2D = null

## Whether we're using particle system.
var _using_particles: bool = false

## Whether the initial batch of illusions has been spawned.
var _illusions_spawned: bool = false

## Reference to player for proximity check.
var _player: Node2D = null

## Issue #1367: Progressive illusion spawning — +1 illusion every 2 seconds in cloud.
## Maximum total illusions this cloud can spawn (initial batch + progressive).
@export var max_illusions_per_cloud: int = 10

## Interval for spawning additional illusions while player stays in cloud (seconds).
@export var progressive_spawn_interval: float = 2.0

## Total illusions spawned by this cloud so far.
var _total_illusions_spawned: int = 0

## Timer tracking time player has spent in the cloud.
var _player_time_in_cloud: float = 0.0

## Timer for progressive illusion spawning.
var _progressive_spawn_timer: float = 0.0

## Issue #1688: Duration for gradual grow-in when cloud first appears (seconds).
## When > 0, the cloud scale grows from 0 to 1 over this duration, making it
## appear to spread gradually starting when the sound begins playing.
@export var grow_in_duration: float = 0.0

## Elapsed time since cloud was spawned (used for grow-in).
var _spawn_elapsed: float = 0.0


func _ready() -> void:
	FileLogger.info("[ChemicalCloud] _ready() at %s" % str(global_position))
	_time_remaining = cloud_duration
	_setup_detection_area()
	_setup_cloud_visual()
	# Find player
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node2D
	FileLogger.info("[ChemicalCloud] Cloud spawned at %s, radius=%.0f, duration=%.0fs" % [
		str(global_position), cloud_radius, cloud_duration
	])


func _physics_process(delta: float) -> void:
	_time_remaining -= delta
	_spawn_elapsed += delta

	# Issue #1688: Grow-in effect — scale cloud from 0 to 1 over grow_in_duration
	if grow_in_duration > 0.0:
		var grow_progress := clampf(_spawn_elapsed / grow_in_duration, 0.0, 1.0)
		scale = Vector2(grow_progress, grow_progress)

	# Spawn initial batch of illusions when the cloud first appears
	# Only if player is within blast radius
	if not _illusions_spawned:
		_illusions_spawned = true
		if _is_player_in_range():
			_spawn_illusions_for_nearby_enemies()
		else:
			FileLogger.info("[ChemicalCloud] Player not in range (%.0fpx), no illusions spawned" % [
				_player.global_position.distance_to(global_position) if _player else -1.0
			])

	# Issue #1367: Progressive illusion spawning while player stays in cloud.
	# +1 illusion every 2 seconds, up to max_illusions_per_cloud total.
	if _is_player_in_range():
		_player_time_in_cloud += delta
		_progressive_spawn_timer += delta
		if _progressive_spawn_timer >= progressive_spawn_interval:
			_progressive_spawn_timer -= progressive_spawn_interval
			if _total_illusions_spawned < max_illusions_per_cloud:
				_spawn_progressive_illusion()

	# Update visual fade
	_update_cloud_visual()

	# Dissipate
	if _time_remaining <= 0.0:
		FileLogger.info("[ChemicalCloud] Cloud dissipated at %s (spawned %d total illusions)" % [
			str(global_position), _total_illusions_spawned
		])
		queue_free()


## Check if the player is within the cloud radius.
func _is_player_in_range() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	return _player.global_position.distance_to(global_position) <= cloud_radius


## Spawn illusion copies for all enemies on the map.
func _spawn_illusions_for_nearby_enemies() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var spawned_count: int = 0

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if not enemy is Node2D:
			continue
		# Skip dead enemies
		if enemy.has_method("is_alive") and not enemy.is_alive():
			continue

		# Check if we can spawn more illusions (global cap or per-cloud cap)
		if not IllusionEffect.can_spawn_more(get_tree()):
			FileLogger.info("[ChemicalCloud] Global illusion cap reached (%d), stopping" % IllusionEffect.MAX_TOTAL_ILLUSIONS)
			break
		if spawned_count >= max_illusions_per_cloud:
			FileLogger.info("[ChemicalCloud] Per-cloud cap reached (%d), stopping initial batch" % max_illusions_per_cloud)
			break

		# Spawn 2-6 copies per enemy
		var copies: int = randi_range(min_copies_per_enemy, max_copies_per_enemy)

		# Issue #1361: Generate all positions (copies + 1 for original),
		# then randomly assign the original to one of the non-center positions
		# so the real enemy is not always in the center of the cluster.
		var total_positions: int = copies + 1  # copies for illusions + 1 center
		var offsets: Array[Vector2] = []
		# Position 0 is the center (offset 0,0)
		offsets.append(Vector2.ZERO)
		# Remaining positions are spread in a circle
		for i in range(copies):
			var angle: float = (TAU / copies) * i + randf_range(-0.3, 0.3)
			var distance: float = randf_range(60.0, 120.0)
			offsets.append(Vector2(cos(angle), sin(angle)) * distance)

		# Pick a random position for the original enemy (any of the total_positions)
		var original_index: int = randi_range(0, total_positions - 1)
		var original_offset: Vector2 = offsets[original_index]

		# Move the original enemy to its new position
		if original_offset != Vector2.ZERO:
			var new_pos: Vector2 = enemy.global_position + original_offset.rotated(enemy.rotation)
			FileLogger.info("[ChemicalCloud] Moving original enemy from %s to %s (offset=%s)" % [
				str(enemy.global_position), str(new_pos), str(original_offset)
			])
			enemy.global_position = new_pos

		# Spawn illusions at all positions except the one assigned to the original
		for i in range(total_positions):
			if i == original_index:
				continue  # This position is occupied by the real enemy
			if not IllusionEffect.can_spawn_more(get_tree()):
				break
			if spawned_count >= max_illusions_per_cloud:
				break
			# Offset relative to the enemy's new position
			var illusion_offset: Vector2 = offsets[i] - original_offset
			_spawn_single_illusion(enemy, illusion_offset)
			spawned_count += 1

	_total_illusions_spawned += spawned_count
	FileLogger.info("[ChemicalCloud] Spawned %d illusion copies for %d enemies (total: %d/%d)" % [
		spawned_count, enemies.size(), _total_illusions_spawned, max_illusions_per_cloud
	])


## Spawn a single illusion copy of an enemy at a given offset.
func _spawn_single_illusion(enemy: Node2D, offset: Vector2) -> void:
	var illusion := IllusionEffect.new()
	illusion.illusion_duration = illusion_duration

	illusion.setup(enemy, offset)
	illusion.phantom_shoot_interval = randf_range(1.5, 3.0)

	get_tree().current_scene.add_child(illusion)


## Issue #1367: Spawn one additional illusion for a random alive enemy.
## Called every progressive_spawn_interval seconds while player is in the cloud.
func _spawn_progressive_illusion() -> void:
	if not IllusionEffect.can_spawn_more(get_tree()):
		FileLogger.info("[ChemicalCloud] Progressive spawn skipped — global illusion cap reached")
		return

	# Find alive enemies to copy
	var enemies := get_tree().get_nodes_in_group("enemies")
	var alive_enemies: Array[Node2D] = []
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if enemy.has_method("is_alive") and not enemy.is_alive():
			continue
		alive_enemies.append(enemy as Node2D)

	if alive_enemies.is_empty():
		FileLogger.info("[ChemicalCloud] Progressive spawn skipped — no alive enemies")
		return

	# Pick a random enemy and spawn one illusion copy
	var enemy: Node2D = alive_enemies[randi() % alive_enemies.size()]
	var angle: float = randf_range(0.0, TAU)
	var distance: float = randf_range(60.0, 120.0)
	var offset := Vector2(cos(angle), sin(angle)) * distance

	_spawn_single_illusion(enemy, offset)
	_total_illusions_spawned += 1
	FileLogger.info("[ChemicalCloud] Progressive illusion spawned (total: %d/%d, player in cloud: %.1fs)" % [
		_total_illusions_spawned, max_illusions_per_cloud, _player_time_in_cloud
	])


## Set up Area2D for detecting enemies/player in the cloud.
func _setup_detection_area() -> void:
	_detection_area = Area2D.new()
	_detection_area.name = "DetectionArea"
	_detection_area.monitoring = true
	_detection_area.monitorable = false
	# Detect enemies (layer 2) and player (layer 1)
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = 3  # layers 1 + 2

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = cloud_radius
	shape.shape = circle
	shape.name = "CollisionShape2D"

	_detection_area.add_child(shape)
	add_child(_detection_area)


## Set up the visual gas cloud (yellow-green chemical gas).
func _setup_cloud_visual() -> void:
	var particles := _create_particle_visual()
	if particles:
		_cloud_visual = particles
		_using_particles = true
		add_child(_cloud_visual)
		FileLogger.info("[ChemicalCloud] Particle system created")
	else:
		FileLogger.warning("[ChemicalCloud] Could not create particles, using sprite fallback")
		_cloud_visual = _create_sprite_fallback()
		_using_particles = false
		add_child(_cloud_visual)


## Create GPUParticles2D for the chemical gas cloud (yellow-green).
func _create_particle_visual() -> GPUParticles2D:
	var particles := GPUParticles2D.new()

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.6, 0.7, 0.1, 0.85),   # Start: yellow-green, high opacity
		Color(0.5, 0.65, 0.15, 0.7),  # Early: slightly lighter
		Color(0.45, 0.6, 0.2, 0.45),  # Mid: fading
		Color(0.4, 0.55, 0.15, 0.0)   # End: fully transparent
	])

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)

	var material := ParticleProcessMaterial.new()
	material.lifetime_randomness = 0.4
	material.particle_flag_disable_z = true
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = cloud_radius * 0.8
	material.direction = Vector3(0, -1, 0)
	material.spread = 180.0
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 15.0
	material.gravity = Vector3(0, -8, 0)
	material.damping_min = 5.0
	material.damping_max = 12.0
	material.scale_min = 0.8
	material.scale_max = 2.0
	material.color = Color(0.55, 0.65, 0.15, 0.8)

	particles.z_index = 1
	particles.amount = 40  # Reduced from 100 for performance
	particles.process_material = material
	particles.texture = tex
	particles.lifetime = 4.0
	particles.preprocess = 1.0
	particles.explosiveness = 0.1
	particles.randomness = 0.3
	particles.one_shot = false
	particles.emitting = true

	return particles


## Sprite-based fallback visual.
func _create_sprite_fallback() -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = _create_cloud_texture(int(cloud_radius))
	sprite.modulate = Color(0.6, 0.7, 0.15, 0.7)
	sprite.z_index = 1
	return sprite


## Update cloud visual based on remaining time.
func _update_cloud_visual() -> void:
	if _cloud_visual == null:
		return

	if _using_particles:
		var particles := _cloud_visual as GPUParticles2D
		if particles and _time_remaining < 5.0 and particles.emitting:
			particles.emitting = false
			FileLogger.info("[ChemicalCloud] Stopped emission, dissipating")
	else:
		var sprite := _cloud_visual as Sprite2D
		if sprite:
			if _time_remaining < 5.0:
				sprite.modulate.a = 0.7 * (_time_remaining / 5.0)
			else:
				sprite.modulate.a = 0.7


## Create a circular cloud texture for fallback rendering.
func _create_cloud_texture(radius: int) -> ImageTexture:
	var size := radius * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(radius, radius)

	for x in range(size):
		for y in range(size):
			var pos := Vector2(x, y)
			var distance := pos.distance_to(center)
			if distance <= radius:
				var alpha := 1.0 - (distance / float(radius))
				alpha = alpha * alpha
				image.set_pixel(x, y, Color(0.55, 0.65, 0.15, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)
