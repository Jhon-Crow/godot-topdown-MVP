extends GrenadeBase
class_name FragGrenade
## Offensive (frag) grenade that explodes on impact and releases shrapnel.
##
## Key characteristics:
## - Explodes ONLY on landing or hitting a wall (NO timer - impact-triggered only)
## - Smaller explosion radius than flashbang
## - Releases 4 shrapnel pieces in all directions (with random deviation)
## - Shrapnel ricochets off walls and deals 1 damage each
## - Slightly lighter than flashbang (throws a bit farther/easier)
##
## Per issue requirement: "взрывается при приземлении/ударе об стену (без таймера)"
## Translation: "explodes on landing/hitting a wall (without timer)"

## Effect radius for the explosion (smaller than flashbang's 400).
@export var effect_radius: float = 250.0

## Number of shrapnel pieces to spawn.
@export var shrapnel_count: int = 4

## Shrapnel scene to instantiate.
@export var shrapnel_scene: PackedScene

## Random angle deviation for shrapnel spread in degrees.
@export var shrapnel_spread_deviation: float = 20.0

## Direct explosive (HE/blast wave) damage to enemies in effect radius.
## Per user requirement: should deal 99 damage to all enemies in the blast zone.
@export var explosion_damage: int = 99

## Whether the grenade has impacted (landed or hit wall).
var _has_impacted: bool = false

## Track if we've started throwing (to avoid impact during initial spawn).
var _is_thrown: bool = false


func _ready() -> void:
	super._ready()

	# Frag grenade is slightly lighter - increase max throw speed slightly
	# (5% increase for "slightly lighter")
	max_throw_speed *= 1.05

	# Load shrapnel scene if not set
	if shrapnel_scene == null:
		var shrapnel_path := "res://scenes/projectiles/Shrapnel.tscn"
		if ResourceLoader.exists(shrapnel_path):
			shrapnel_scene = load(shrapnel_path)
			FileLogger.info("[FragGrenade] Shrapnel scene loaded from: %s" % shrapnel_path)
		else:
			FileLogger.info("[FragGrenade] WARNING: Shrapnel scene not found at: %s" % shrapnel_path)


## Override to prevent timer countdown for frag grenades.
## Frag grenades explode ONLY on impact (landing or wall hit), NOT on a timer.
## Per issue requirement: "без таймера" = "without timer"
func activate_timer() -> void:
	# Set _timer_active to true so landing detection works (line 114 in base class)
	# But do NOT set _time_remaining - no countdown, no timer-based explosion
	if _timer_active:
		FileLogger.info("[FragGrenade] Already activated")
		return
	_timer_active = true
	# Do NOT set _time_remaining - leave it at 0 so timer never triggers explosion
	# The base class checks `if _time_remaining <= 0: _explode()` only when _timer_active is true
	# But since _time_remaining starts at 0, we need to set it to a very high value to prevent timer explosion
	# Actually, better approach: set to infinity-like value so timer never triggers
	_time_remaining = 999999.0  # Effectively infinite - grenade will only explode on impact

	# Play activation sound (pin pull)
	if not _activation_sound_played:
		_activation_sound_played = true
		_play_activation_sound()
	FileLogger.info("[FragGrenade] Pin pulled - waiting for impact (no timer, impact-triggered only)")


## Override _physics_process to disable blinking (no timer countdown for frag grenades).
func _physics_process(delta: float) -> void:
	if _has_exploded:
		return

	# Apply ground friction to slow down (copied from base class)
	if linear_velocity.length() > 0:
		var friction_force := linear_velocity.normalized() * ground_friction * delta
		if friction_force.length() > linear_velocity.length():
			linear_velocity = Vector2.ZERO
		else:
			linear_velocity -= friction_force

	# Check for landing (grenade comes to near-stop after being thrown)
	if not _has_landed and _timer_active:
		var current_speed := linear_velocity.length()
		var previous_speed := _previous_velocity.length()
		# Grenade has landed when it was moving fast and now nearly stopped
		if previous_speed > landing_velocity_threshold and current_speed < landing_velocity_threshold:
			_on_grenade_landed()
	_previous_velocity = linear_velocity

	# NOTE: No timer countdown or blink effect for frag grenades
	# They only explode on impact, not on a timer


## Override throw to mark grenade as thrown.
func throw_grenade(direction: Vector2, drag_distance: float) -> void:
	super.throw_grenade(direction, drag_distance)
	_is_thrown = true
	FileLogger.info("[FragGrenade] Grenade thrown - impact detection enabled")


## Override body_entered to detect wall impacts.
func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)

	# Only explode on impact if we've been thrown and haven't exploded yet
	if _is_thrown and not _has_impacted and not _has_exploded:
		# Trigger impact explosion on wall/obstacle hit
		if body is StaticBody2D or body is TileMap:
			_trigger_impact_explosion()


## Called when grenade lands on the ground.
## Overridden to trigger immediate explosion on landing.
func _on_grenade_landed() -> void:
	super._on_grenade_landed()

	# Trigger explosion on landing
	if _is_thrown and not _has_impacted and not _has_exploded:
		_trigger_impact_explosion()


## Trigger explosion from impact (wall hit or landing).
func _trigger_impact_explosion() -> void:
	_has_impacted = true
	FileLogger.info("[FragGrenade] Impact detected - exploding immediately!")
	_explode()


## Override to define the explosion effect.
func _on_explode() -> void:
	# Find all enemies within effect radius and apply direct explosion damage
	var enemies := _get_enemies_in_radius()

	for enemy in enemies:
		_apply_explosion_damage(enemy)

	# Spawn shrapnel in all directions
	_spawn_shrapnel()

	# Spawn visual explosion effect
	_spawn_explosion_effect()


## Override explosion sound to play frag grenade specific sound.
func _play_explosion_sound() -> void:
	# Check if player is in the effect radius for audio variation
	var player_in_zone := _is_player_in_zone()

	# Use existing explosion sound system
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_flashbang_explosion"):
		# Reuse flashbang explosion sound for now (can be replaced with frag-specific sound later)
		audio_manager.play_flashbang_explosion(global_position, player_in_zone)

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


## Check if the player is within the explosion effect radius.
func _is_player_in_zone() -> bool:
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
		return false

	return is_in_effect_radius(player.global_position)


## Get the effect radius for this grenade type.
func _get_effect_radius() -> float:
	return effect_radius


## Find all enemies within the effect radius.
func _get_enemies_in_radius() -> Array:
	var enemies_in_range: Array = []

	# Get all enemies in the scene
	var enemies := get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if enemy is Node2D and is_in_effect_radius(enemy.global_position):
			# Check line of sight for explosion damage
			if _has_line_of_sight_to(enemy):
				enemies_in_range.append(enemy)

	return enemies_in_range


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
## Per user requirement: flat 99 damage to ALL enemies in the blast zone (no distance scaling).
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

	FileLogger.info("[FragGrenade] Applied %d HE damage to enemy at distance %.1f" % [final_damage, distance])


## Spawn shrapnel pieces in all directions.
func _spawn_shrapnel() -> void:
	if shrapnel_scene == null:
		FileLogger.info("[FragGrenade] Cannot spawn shrapnel: scene is null")
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

		# Add to scene
		get_tree().current_scene.add_child(shrapnel)

		FileLogger.info("[FragGrenade] Spawned shrapnel #%d at angle %.1f degrees" % [i + 1, rad_to_deg(final_angle)])


## Spawn visual explosion effect at explosion position.
func _spawn_explosion_effect() -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")

	if impact_manager and impact_manager.has_method("spawn_flashbang_effect"):
		# Reuse flashbang effect with our smaller radius
		impact_manager.spawn_flashbang_effect(global_position, effect_radius)
	else:
		# Fallback: create simple explosion effect
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
