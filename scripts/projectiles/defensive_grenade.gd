extends GrenadeBase
class_name DefensiveGrenade
## Defensive (F-1) grenade that explodes on a timer and releases heavy shrapnel.
##
## Key characteristics:
## - Timer-based detonation (4 second fuse, like flashbang)
## - Large explosion radius (700px) - designed for area denial
## - Releases 40 shrapnel pieces in all directions (with random deviation)
## - Shrapnel ricochets off walls and deals 1 damage each
## - Heavier than frag grenade (real F-1 weighs 0.6kg)
##
## Per issue #495 requirements:
## - радиус поражения = 700px (damage radius)
## - количество осколков = 40 (shrapnel count)
## - таймер = 4 секунды (timer = 4 seconds)
## - звук взрыва = assets/audio/взрыв оборонительной гранаты.wav

## Effect radius for the explosion.
## Per issue #495: radius must be 700px.
@export var effect_radius: float = 700.0

## Number of shrapnel pieces to spawn.
## Per issue #495: 40 shrapnel pieces.
@export var shrapnel_count: int = 40

## Shrapnel scene to instantiate.
@export var shrapnel_scene: PackedScene

## Random angle deviation for shrapnel spread in degrees.
@export var shrapnel_spread_deviation: float = 15.0

## Direct explosive (HE/blast wave) damage to enemies in effect radius.
## High damage to all enemies in the blast zone.
@export var explosion_damage: int = 99

## Issue #692: Instance ID of the enemy who threw this grenade.
## Used to prevent self-damage from own grenade explosion and shrapnel.
## -1 means no thrower tracked (e.g., player-thrown grenades).
var thrower_id: int = -1


func _ready() -> void:
	super._ready()

	# F-1 is heavier than frag grenade (0.6kg real weight)
	# This means slightly slower throw speed
	grenade_mass = 0.6

	# Load shrapnel scene if not set
	if shrapnel_scene == null:
		var shrapnel_path := "res://scenes/projectiles/Shrapnel.tscn"
		if ResourceLoader.exists(shrapnel_path):
			shrapnel_scene = load(shrapnel_path)
			FileLogger.info("[DefensiveGrenade] Shrapnel scene loaded from: %s" % shrapnel_path)
		else:
			FileLogger.info("[DefensiveGrenade] WARNING: Shrapnel scene not found at: %s" % shrapnel_path)


## Override to define the explosion effect.
func _on_explode() -> void:
	# Find all enemies within effect radius and apply direct explosion damage
	var enemies := _get_enemies_in_radius()

	for enemy in enemies:
		_apply_explosion_damage(enemy)

	# Also damage the player if in blast radius (defensive grenade deals same damage to all)
	var player := _get_player_in_radius()
	if player != null:
		_apply_explosion_damage(player)

	# Scatter shell casings on the floor
	_scatter_casings(effect_radius)

	# Spawn shrapnel in all directions (40 pieces!)
	_spawn_shrapnel()

	# Spawn visual explosion effect
	_spawn_explosion_effect()


## Override explosion sound to play defensive grenade specific sound.
func _play_explosion_sound() -> void:
	# Use AudioManager to play the defensive grenade explosion sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_defensive_grenade_explosion"):
		audio_manager.play_defensive_grenade_explosion(global_position)

	# Also emit sound for AI awareness via SoundPropagation
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		var viewport := get_viewport()
		var viewport_diagonal := 1469.0  # Default 1280x720 diagonal
		if viewport:
			var size := viewport.get_visible_rect().size
			viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)
		var sound_range := viewport_diagonal * sound_range_multiplier
		# 1 = EXPLOSION type, 2 = NEUTRAL source
		sound_propagation.emit_sound(1, global_position, 2, self, sound_range)


## Get the effect radius for this grenade type.
func _get_effect_radius() -> float:
	return effect_radius


## Find all enemies within the effect radius.
## Issue #692: Excludes the thrower from explosion damage to prevent self-kills.
func _get_enemies_in_radius() -> Array:
	var enemies_in_range: Array = []

	# Get all enemies in the scene
	var enemies := get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if enemy is Node2D and is_in_effect_radius(enemy.global_position):
			# Issue #692: Skip the enemy who threw this grenade
			if thrower_id >= 0 and enemy.get_instance_id() == thrower_id:
				FileLogger.info("[DefensiveGrenade] Skipping thrower (instance ID: %d) - self-damage prevention" % thrower_id)
				continue
			# Check line of sight for explosion damage
			if _has_line_of_sight_to(enemy):
				enemies_in_range.append(enemy)

	return enemies_in_range


## Find the player if within the effect radius (defensive grenade damages everyone).
## Returns null if player is not in radius or has no line of sight.
func _get_player_in_radius() -> Node2D:
	var player: Node2D = null

	# Check for player in "player" group
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		player = players[0] as Node2D

	# Fallback: check for node named "Player" in current scene
	if player == null:
		var scene := get_tree().current_scene
		if scene:
			player = scene.get_node_or_null("Player") as Node2D

	if player == null:
		return null

	# Check if player is in effect radius
	if not is_in_effect_radius(player.global_position):
		return null

	# Check line of sight (player must be exposed to blast, walls block damage)
	if not _has_line_of_sight_to(player):
		return null

	FileLogger.info("[DefensiveGrenade] Player found in blast radius at distance %.1f" % global_position.distance_to(player.global_position))
	return player


## Check if there's line of sight from grenade to target.
func _has_line_of_sight_to(target: Node2D) -> bool:
	var space_state := get_world_2d().direct_space_state

	var query := PhysicsRayQueryParameters2D.create(
		global_position,
		target.global_position
	)
	query.collision_mask = 4  # Only check against obstacles
	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	# If no hit, we have line of sight
	return result.is_empty()


## Apply direct explosion damage to an enemy.
## Flat damage to ALL enemies in the blast zone (no distance scaling).
func _apply_explosion_damage(enemy: Node2D) -> void:
	var distance := global_position.distance_to(enemy.global_position)

	# Flat damage to all enemies in blast zone - no distance scaling
	var final_damage := explosion_damage

	# Try to apply damage through various methods
	if enemy.has_method("on_hit_with_info"):
		# Calculate direction from explosion to enemy
		var hit_direction := (enemy.global_position - global_position).normalized()
		for i in range(final_damage):
			enemy.on_hit_with_info(hit_direction, null)
	elif enemy.has_method("on_hit"):
		for i in range(final_damage):
			enemy.on_hit()

	FileLogger.info("[DefensiveGrenade] Applied %d HE damage to enemy at distance %.1f" % [final_damage, distance])


## Spawn shrapnel pieces in all directions.
func _spawn_shrapnel() -> void:
	if shrapnel_scene == null:
		FileLogger.info("[DefensiveGrenade] Cannot spawn shrapnel: scene is null")
		return

	# Calculate base angle step for even distribution
	var angle_step := TAU / shrapnel_count  # TAU = 2*PI

	for i in range(shrapnel_count):
		# Base direction for this shrapnel piece
		var base_angle := i * angle_step

		# Add random deviation
		var deviation := deg_to_rad(randf_range(-shrapnel_spread_deviation, shrapnel_spread_deviation))
		var final_angle := base_angle + deviation

		# Calculate direction vector
		var direction := Vector2(cos(final_angle), sin(final_angle))

		# Create shrapnel instance
		var shrapnel := shrapnel_scene.instantiate()
		if shrapnel == null:
			continue

		# Set shrapnel properties
		shrapnel.global_position = global_position + direction * 10.0  # Slight offset from center
		shrapnel.direction = direction
		shrapnel.source_id = get_instance_id()
		# Issue #692: Pass thrower_id so shrapnel doesn't hit the enemy who threw it
		shrapnel.thrower_id = thrower_id

		# Add to scene
		get_tree().current_scene.add_child(shrapnel)

		FileLogger.info("[DefensiveGrenade] Spawned shrapnel #%d at angle %.1f degrees" % [i + 1, rad_to_deg(final_angle)])


## Spawn visual explosion effect at explosion position.
## Uses wall-aware effect spawning to prevent visual effects from passing through walls.
func _spawn_explosion_effect() -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")

	if impact_manager and impact_manager.has_method("spawn_explosion_effect"):
		# Use the wall-aware explosion effect (blocks visual through walls)
		impact_manager.spawn_explosion_effect(global_position, effect_radius)
	elif impact_manager and impact_manager.has_method("spawn_flashbang_effect"):
		# Fallback to flashbang effect (also wall-aware)
		impact_manager.spawn_flashbang_effect(global_position, effect_radius)
	else:
		# Final fallback: create simple explosion effect without wall occlusion
		_create_simple_explosion()


## Create a simple explosion effect if no manager is available.
func _create_simple_explosion() -> void:
	# Create an orange/red explosion flash
	var flash := Sprite2D.new()
	flash.texture = _create_explosion_texture(int(effect_radius))
	flash.global_position = global_position
	flash.modulate = Color(1.0, 0.6, 0.2, 0.8)
	flash.z_index = 100  # Draw on top

	get_tree().current_scene.add_child(flash)

	# Fade out the flash
	var tween := get_tree().create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.2)
	tween.tween_callback(flash.queue_free)


## Create an explosion texture.
func _create_explosion_texture(radius: int) -> ImageTexture:
	var size := radius * 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(radius, radius)

	for x in range(size):
		for y in range(size):
			var pos := Vector2(x, y)
			var distance := pos.distance_to(center)
			if distance <= radius:
				# Fade from center
				var alpha := 1.0 - (distance / radius)
				# Orange/yellow explosion color
				image.set_pixel(x, y, Color(1.0, 0.7, 0.3, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)
