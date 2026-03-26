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

	# Issue #1460 Round 7: Get shrapnel scene from ProjectilePoolManager to avoid
	# calling load() here. load() blocks the main thread and causes a frame spike
	# every time a grenade is created. The pool manager pre-loads the scene at startup
	# so we can reuse its cached reference at zero cost.
	if shrapnel_scene == null:
		var pool_manager: Node = get_node_or_null("/root/ProjectilePoolManager")
		if pool_manager and pool_manager.get("_shrapnel_scene") != null:
			shrapnel_scene = pool_manager._shrapnel_scene
			FileLogger.info("[DefensiveGrenade] Shrapnel scene obtained from ProjectilePoolManager")
		else:
			# Fallback: load only if pool manager is unavailable
			var shrapnel_path := "res://scenes/projectiles/Shrapnel.tscn"
			if ResourceLoader.exists(shrapnel_path):
				shrapnel_scene = load(shrapnel_path)
				FileLogger.info("[DefensiveGrenade] Shrapnel scene loaded from: %s (fallback)" % shrapnel_path)
			else:
				FileLogger.info("[DefensiveGrenade] WARNING: Shrapnel scene not found at: %s" % shrapnel_path)


## Override to define the explosion effect.
## Issue #1460 optimization: Scorch mark textures are pre-cached at startup,
## particles use fixed_fps=30 and visibility_rect, shrapnel is staggered in batches.
func _on_explode() -> void:
	var t0 := Time.get_ticks_msec()

	# Find all enemies within effect radius and apply direct explosion damage
	var enemies := _get_enemies_in_radius()

	for enemy in enemies:
		_apply_explosion_damage(enemy)

	var t1 := Time.get_ticks_msec()

	# Also damage the player if in blast radius (defensive grenade deals same damage to all)
	var player := _get_player_in_radius()
	if player != null:
		_apply_explosion_damage(player)

	# Scatter shell casings on the floor
	_scatter_casings(effect_radius)

	var t2 := Time.get_ticks_msec()

	# Spawn shrapnel in all directions (40 pieces, staggered in batches)
	_spawn_shrapnel()

	var t3 := Time.get_ticks_msec()

	# Spawn visual explosion effect (pooled PointLight2D, no shadows)
	_spawn_explosion_effect()

	var t4 := Time.get_ticks_msec()

	# Issue #1005: Spawn scorch mark on floor (texture is cached, Issue #1460)
	# F-1 (defensive): 2x frag size (~80px), prominent burnt mark (alpha 0.7)
	_spawn_scorch_mark(80.0, 0.7, "defensive")

	var t5 := Time.get_ticks_msec()
	FileLogger.info("[DefensiveGrenade] Explosion timing (ms): damage=%d, casings=%d, shrapnel=%d, flash=%d, scorch=%d, total=%d" % [
		t1 - t0, t2 - t1, t3 - t2, t4 - t3, t5 - t4, t5 - t0
	])


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
## Issue #692: When thrown by an enemy (thrower_id >= 0), excludes ALL enemies
## from explosion damage to prevent both self-kills and friendly fire.
func _get_enemies_in_radius() -> Array:
	var enemies_in_range: Array = []

	# Issue #692: If this grenade was thrown by an enemy, skip ALL enemies
	# to prevent both self-damage and friendly fire between allies.
	if thrower_id >= 0:
		FileLogger.info("[DefensiveGrenade] Skipping all enemies - enemy-thrown grenade (thrower ID: %d)" % thrower_id)
		return enemies_in_range

	# Get all enemies in the scene (only for player-thrown grenades)
	var enemies := get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if enemy is Node2D and is_in_effect_radius(enemy.global_position):
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
## Issue #1460: Uses bulk damage via on_hit_with_bullet_info() instead of calling
## on_hit_with_info() in a loop. The old approach called on_hit 99 times per enemy,
## each spawning blood particles — causing 198+ GPUParticles2D instantiations in one
## frame and a 22-fps drop. The new approach applies all damage in a single call.
func _apply_explosion_damage(enemy: Node2D) -> void:
	var distance := global_position.distance_to(enemy.global_position)

	# Flat damage to all enemies in blast zone - no distance scaling
	var final_damage := explosion_damage

	# Calculate direction from explosion to enemy
	var hit_direction := (enemy.global_position - global_position).normalized()

	# Issue #1460: Apply all damage in a single call to avoid spawning hundreds of
	# blood particle effects per enemy. on_hit_with_bullet_info supports a damage
	# parameter that applies the full amount at once.
	if enemy.has_method("on_hit_with_bullet_info"):
		enemy.on_hit_with_bullet_info(hit_direction, null, false, false, float(final_damage))
	elif enemy.has_method("on_hit_with_info"):
		# Fallback for entities without bulk damage support
		enemy.on_hit_with_info(hit_direction, null)
	elif enemy.has_method("on_hit"):
		enemy.on_hit()

	FileLogger.info("[DefensiveGrenade] Applied %d HE damage to enemy at distance %.1f" % [final_damage, distance])


## Maximum shrapnel pieces to spawn per frame to avoid single-frame CPU spike.
## Issue #1460: Spawning all 40 shrapnel in one frame caused FPS drops. Spreading
## across frames (10 per frame × 4 frames = ~67ms at 60fps) is imperceptible to
## the player but prevents the spike.
const SHRAPNEL_BATCH_SIZE: int = 10


## Spawn shrapnel pieces in all directions, staggered across multiple frames.
## Issue #1460: Spawning all 40 shrapnel in one frame caused CPU spikes. Now
## spawns in batches of SHRAPNEL_BATCH_SIZE per frame using SceneTree timers
## so spawning continues even after the grenade node is freed.
func _spawn_shrapnel() -> void:
	if shrapnel_scene == null:
		FileLogger.info("[DefensiveGrenade] Cannot spawn shrapnel: scene is null")
		return

	# Pre-calculate all shrapnel data before spawning (grenade will be freed shortly).
	var spawn_origin := global_position
	var grenade_instance_id := get_instance_id()
	var grenade_thrower_id := thrower_id
	var angle_step := TAU / shrapnel_count
	var shrapnel_data: Array = []

	for i in range(shrapnel_count):
		var base_angle := i * angle_step
		var deviation := deg_to_rad(randf_range(-shrapnel_spread_deviation, shrapnel_spread_deviation))
		var final_angle := base_angle + deviation
		var direction := Vector2(cos(final_angle), sin(final_angle))
		var spawn_pos := spawn_origin + direction * 10.0
		shrapnel_data.append({"pos": spawn_pos, "dir": direction})

	# Capture references that survive grenade being freed.
	var scene_ref := shrapnel_scene
	var pool_manager: Node = get_node_or_null("/root/ProjectilePoolManager")
	var tree := get_tree()
	if tree == null:
		return

	# Spawn first batch immediately, schedule remaining batches via SceneTree timers.
	# Using create_timer(0.0) schedules execution on the next frame, independent of
	# the grenade node's lifetime (timers are owned by SceneTree, not this node).
	var batch_index := 0
	for batch_start in range(0, shrapnel_data.size(), SHRAPNEL_BATCH_SIZE):
		var batch_end := mini(batch_start + SHRAPNEL_BATCH_SIZE, shrapnel_data.size())
		var batch_slice := shrapnel_data.slice(batch_start, batch_end)

		if batch_index == 0:
			# Spawn first batch immediately (same frame as explosion).
			for data in batch_slice:
				_spawn_single_shrapnel_static(data, scene_ref, pool_manager, grenade_instance_id, grenade_thrower_id, tree)
		else:
			# Schedule subsequent batches with increasing delays (~1 frame apart).
			# At 60fps one frame is ~0.017s. Using batch_index * 0.02s ensures each
			# batch fires on a separate frame. SceneTree timers survive node destruction.
			var delay := batch_index * 0.02
			var captured_batch := batch_slice
			var captured_scene := scene_ref
			var captured_pool := pool_manager
			var captured_source := grenade_instance_id
			var captured_thrower := grenade_thrower_id
			var captured_tree := tree
			tree.create_timer(delay).timeout.connect(func() -> void:
				for data in captured_batch:
					_spawn_single_shrapnel_static(data, captured_scene, captured_pool, captured_source, captured_thrower, captured_tree)
			)
		batch_index += 1


## Spawns a single shrapnel piece using pooling when available.
## Static-safe: does not depend on the grenade node being alive.
static func _spawn_single_shrapnel_static(data: Dictionary, scene_ref: PackedScene, pool_manager: Node, source_id_val: int, thrower_id_val: int, tree: SceneTree) -> void:
	# Try pooled shrapnel first for performance (Issue #724)
	if is_instance_valid(pool_manager) and pool_manager.has_method("get_shrapnel"):
		var shrapnel: Node = pool_manager.get_shrapnel()
		if shrapnel and shrapnel.has_method("pool_activate"):
			shrapnel.pool_activate(data["pos"], data["dir"], source_id_val, thrower_id_val)
			return

	# Fallback to instantiation
	var shrapnel: Node = scene_ref.instantiate()
	if shrapnel == null:
		return

	shrapnel.global_position = data["pos"]
	shrapnel.direction = data["dir"]
	shrapnel.source_id = source_id_val
	shrapnel.thrower_id = thrower_id_val

	if tree and tree.current_scene:
		tree.current_scene.add_child(shrapnel)


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
