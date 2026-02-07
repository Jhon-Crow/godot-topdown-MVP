extends GrenadeBase
class_name VOGGrenade
## VOG-25 grenade launched from the GP-25 underbarrel grenade launcher on the AK.
##
## Key characteristics:
## - Launched from the weapon (not hand-thrown) - has higher initial velocity
## - Explodes on impact with walls/enemies or on landing
## - Explosion radius 50% larger than offensive (frag) grenade (225 * 1.5 = 337)
## - 8 shrapnel pieces (more than frag grenade's 4)
## - Flies approximately 1.5 viewport widths
## - No timer - impact-triggered only
##
## Per issue: "граната (ВОГ) летит на расстояние 1.5 вьюпорта,
## взрывается сразу когда врезается или падает
## взрыв подствольной гранаты на 50% больше чем у наступательной
## 8 осколков"

## Effect radius for the explosion.
## 50% larger than frag grenade (225 * 1.5 = 337.5, rounded to 337).
@export var effect_radius: float = 337.0

## Number of shrapnel pieces to spawn.
@export var shrapnel_count: int = 8

## Shrapnel scene to instantiate.
@export var shrapnel_scene: PackedScene

## Random angle deviation for shrapnel spread in degrees.
@export var shrapnel_spread_deviation: float = 25.0

## Direct explosive (HE/blast wave) damage to enemies in effect radius.
@export var explosion_damage: int = 99

## Whether the grenade has impacted (landed or hit wall).
var _has_impacted: bool = false

## Track if we've been launched (to avoid impact during initial spawn).
var _is_launched: bool = false

## Track the previous freeze state to detect when grenade is released.
var _was_frozen: bool = true


func _ready() -> void:
	super._ready()

	# Load shrapnel scene if not set
	if shrapnel_scene == null:
		var shrapnel_path := "res://scenes/projectiles/Shrapnel.tscn"
		if ResourceLoader.exists(shrapnel_path):
			shrapnel_scene = load(shrapnel_path)
			FileLogger.info("[VOGGrenade] Shrapnel scene loaded from: %s" % shrapnel_path)
		else:
			FileLogger.info("[VOGGrenade] WARNING: Shrapnel scene not found at: %s" % shrapnel_path)


## Mark the grenade as launched from the underbarrel launcher.
## Unlike hand grenades, VOG is fired with high initial velocity.
func mark_as_launched() -> void:
	_is_launched = true
	FileLogger.info("[VOGGrenade] Grenade launched from underbarrel - impact detection enabled")


## Override to prevent timer countdown for VOG grenades.
## VOG grenades explode ONLY on impact (landing or wall hit), NOT on a timer.
func activate_timer() -> void:
	if _timer_active:
		FileLogger.info("[VOGGrenade] Already activated")
		return
	_timer_active = true
	# Set to very high value to prevent timer-based explosion
	_time_remaining = 999999.0

	# Play activation sound (launcher thump)
	if not _activation_sound_played:
		_activation_sound_played = true
		_play_activation_sound()
	FileLogger.info("[VOGGrenade] Launched - waiting for impact (no timer, impact-triggered only)")


## Override _physics_process to disable blinking (no timer countdown for VOG grenades).
func _physics_process(delta: float) -> void:
	if _has_exploded:
		return

	# Detect when grenade is unfrozen by external code
	if _was_frozen and not freeze:
		_was_frozen = false
		if not _is_launched:
			_is_launched = true
			FileLogger.info("[VOGGrenade] Detected unfreeze - enabling impact detection (fallback)")

	# Apply velocity-dependent ground friction
	if linear_velocity.length() > 0:
		var current_speed := linear_velocity.length()

		var friction_multiplier: float
		if current_speed >= friction_ramp_velocity:
			friction_multiplier = min_friction_multiplier
		else:
			var t := current_speed / friction_ramp_velocity
			friction_multiplier = min_friction_multiplier + (1.0 - min_friction_multiplier) * (1.0 - t * t)

		var effective_friction := ground_friction * friction_multiplier
		var friction_force := linear_velocity.normalized() * effective_friction * delta
		if friction_force.length() > linear_velocity.length():
			linear_velocity = Vector2.ZERO
		else:
			linear_velocity -= friction_force

	# Check for landing
	if not _has_landed and _timer_active:
		var current_speed := linear_velocity.length()
		var previous_speed := _previous_velocity.length()
		if previous_speed > landing_velocity_threshold and current_speed < landing_velocity_threshold:
			_on_grenade_landed()
	_previous_velocity = linear_velocity


## Override body_entered to detect wall impacts.
func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)

	# Only explode on impact if we've been launched and haven't exploded yet
	if _is_launched and not _has_impacted and not _has_exploded:
		if body is StaticBody2D or body is TileMap or body is CharacterBody2D:
			FileLogger.info("[VOGGrenade] Impact detected! Body: %s (type: %s), triggering explosion" % [body.name, body.get_class()])
			_trigger_impact_explosion()
		else:
			FileLogger.info("[VOGGrenade] Non-solid collision (body: %s, type: %s) - not triggering explosion" % [body.name, body.get_class()])


## Called when grenade lands on the ground.
func _on_grenade_landed() -> void:
	super._on_grenade_landed()

	# Trigger explosion on landing
	if _is_launched and not _has_impacted and not _has_exploded:
		_trigger_impact_explosion()


## Trigger explosion from impact (wall hit or landing).
func _trigger_impact_explosion() -> void:
	_has_impacted = true
	FileLogger.info("[VOGGrenade] Impact detected - exploding immediately!")
	_explode()


## Override to define the explosion effect.
func _on_explode() -> void:
	# Find all enemies within effect radius and apply direct explosion damage
	var enemies := _get_enemies_in_radius()

	for enemy in enemies:
		_apply_explosion_damage(enemy)

	# Also damage the player if in blast radius
	var player := _get_player_in_radius()
	if player != null:
		_apply_explosion_damage(player)

	# Scatter shell casings on the floor
	_scatter_casings(effect_radius)

	# Spawn shrapnel in all directions (8 pieces for VOG)
	_spawn_shrapnel()

	# Spawn visual explosion effect
	_spawn_explosion_effect()


## Override explosion sound.
func _play_explosion_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_offensive_grenade_explosion"):
		audio_manager.play_offensive_grenade_explosion(global_position)

	# Also emit sound for AI awareness via SoundPropagation
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		var viewport := get_viewport()
		var viewport_diagonal := 1469.0
		if viewport:
			var size := viewport.get_visible_rect().size
			viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)
		var sound_range := viewport_diagonal * sound_range_multiplier
		sound_propagation.emit_sound(1, global_position, 2, self, sound_range)


## Get the effect radius for this grenade type.
func _get_effect_radius() -> float:
	return effect_radius


## Find all enemies within the effect radius.
func _get_enemies_in_radius() -> Array:
	var enemies_in_range: Array = []

	var enemies := get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if enemy is Node2D and is_in_effect_radius(enemy.global_position):
			if _has_line_of_sight_to(enemy):
				enemies_in_range.append(enemy)

	return enemies_in_range


## Find the player if within the effect radius.
func _get_player_in_radius() -> Node2D:
	var player: Node2D = null

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		player = players[0] as Node2D

	if player == null:
		var scene := get_tree().current_scene
		if scene:
			player = scene.get_node_or_null("Player") as Node2D

	if player == null:
		return null

	if not is_in_effect_radius(player.global_position):
		return null

	if not _has_line_of_sight_to(player):
		return null

	FileLogger.info("[VOGGrenade] Player found in blast radius at distance %.1f" % global_position.distance_to(player.global_position))
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
	return result.is_empty()


## Apply direct explosion damage to an entity.
func _apply_explosion_damage(enemy: Node2D) -> void:
	var distance := global_position.distance_to(enemy.global_position)
	var final_damage := explosion_damage

	if enemy.has_method("on_hit_with_info"):
		var hit_direction := (enemy.global_position - global_position).normalized()
		for i in range(final_damage):
			enemy.on_hit_with_info(hit_direction, null)
	elif enemy.has_method("on_hit"):
		for i in range(final_damage):
			enemy.on_hit()

	FileLogger.info("[VOGGrenade] Applied %d HE damage to enemy at distance %.1f" % [final_damage, distance])


## Spawn shrapnel pieces in all directions (8 pieces for VOG).
func _spawn_shrapnel() -> void:
	if shrapnel_scene == null:
		FileLogger.info("[VOGGrenade] Cannot spawn shrapnel: scene is null")
		return

	var angle_step := TAU / shrapnel_count

	for i in range(shrapnel_count):
		var base_angle := i * angle_step
		var deviation := deg_to_rad(randf_range(-shrapnel_spread_deviation, shrapnel_spread_deviation))
		var final_angle := base_angle + deviation

		var direction := Vector2(cos(final_angle), sin(final_angle))

		var shrapnel := shrapnel_scene.instantiate()
		if shrapnel == null:
			continue

		shrapnel.global_position = global_position + direction * 10.0
		shrapnel.direction = direction
		shrapnel.source_id = get_instance_id()

		get_tree().current_scene.add_child(shrapnel)

		FileLogger.info("[VOGGrenade] Spawned shrapnel #%d at angle %.1f degrees" % [i + 1, rad_to_deg(final_angle)])


## Spawn visual explosion effect at explosion position.
func _spawn_explosion_effect() -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")

	if impact_manager and impact_manager.has_method("spawn_explosion_effect"):
		impact_manager.spawn_explosion_effect(global_position, effect_radius)
	elif impact_manager and impact_manager.has_method("spawn_flashbang_effect"):
		impact_manager.spawn_flashbang_effect(global_position, effect_radius)
	else:
		_create_simple_explosion()


## Create a simple explosion effect if no manager is available.
func _create_simple_explosion() -> void:
	var flash := Sprite2D.new()
	flash.texture = _create_explosion_texture(int(effect_radius))
	flash.global_position = global_position
	flash.modulate = Color(1.0, 0.6, 0.2, 0.8)
	flash.z_index = 100

	get_tree().current_scene.add_child(flash)

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
				var alpha := 1.0 - (distance / radius)
				image.set_pixel(x, y, Color(1.0, 0.7, 0.3, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

	return ImageTexture.create_from_image(image)


## Check if player is in the explosion zone.
func _is_player_in_zone() -> bool:
	var player: Node2D = null

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		player = players[0] as Node2D

	if player == null:
		var scene := get_tree().current_scene
		if scene:
			player = scene.get_node_or_null("Player") as Node2D

	if player == null:
		return false

	if not is_in_effect_radius(player.global_position):
		return false

	return _has_line_of_sight_to(player)
