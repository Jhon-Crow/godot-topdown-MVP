extends RigidBody2D
class_name RpgRocket
## RPG rocket projectile that explodes on impact (Issue #583).
##
## Travels in a direction and explodes on hitting walls, enemies, or player.
## Deals area-of-effect damage within explosion radius.
## No ricochet or penetration - always explodes on first contact.
##
## Movement: Uses _integrate_forces() to enforce rocket propulsion.
## Unlike a grenade (VOGGrenade bounces with physics), a rocket has an engine
## that keeps it on course - collisions cannot deflect it sideways.
##
## Realistic RPG-7 acceleration model:
##   - Launch velocity: ~115 m/s (initial propellant charge)
##   - Sustainer rocket motor activates ~10m from muzzle
##   - Max velocity: ~300 m/s at ~11m from muzzle, then coasts
##   Scaled to game pixels (~100px = 1m):
##   - Launch: speed_initial (300 px/s)
##   - Accelerates to speed (800 px/s) over accel_distance (1000 px)

## Maximum cruise speed in pixels per second (reached after acceleration phase).
@export var speed: float = 800.0

## Initial launch speed in pixels per second (slower at muzzle, like real RPG-7).
@export var speed_initial: float = 300.0

## Distance over which the rocket accelerates from speed_initial to speed.
@export var accel_distance: float = 1000.0

## Maximum lifetime in seconds before auto-destruction.
@export var lifetime: float = 5.0

## Explosion effect radius in pixels.
@export var explosion_radius: float = 150.0

## Explosion damage dealt to entities in radius.
@export var explosion_damage: int = 3

## Seconds after spawn during which collisions are ignored (avoids immediate explosion near shooter).
@export var spawn_immunity_time: float = 0.3

## Direction the rocket travels (set by the shooter before add_child).
var direction: Vector2 = Vector2.RIGHT

## Instance ID of the node that shot this rocket.
var shooter_id: int = -1

## Shooter position at time of firing.
var shooter_position: Vector2 = Vector2.ZERO

## Timer tracking remaining lifetime.
var _time_alive: float = 0.0

## Whether the rocket has exploded.
var _has_exploded: bool = false

## Whether spawn immunity has passed.
var _spawn_immunity_active: bool = true

## Distance traveled so far (for acceleration curve).
var _distance_traveled: float = 0.0

## Current rocket speed (increases during acceleration phase).
var _current_speed: float = 0.0

## Reference to the trail Line2D node (if present).
var _trail: Line2D = null

## Reference to the exhaust GPUParticles2D node (if present).
var _exhaust: GPUParticles2D = null

## History of global positions for the trail effect.
var _position_history: Array[Vector2] = []

## Maximum number of trail points.
@export var trail_length: int = 20


func _ready() -> void:
	# RigidBody2D setup for propelled rocket:
	# - Zero gravity (rocket travels in straight line)
	# - Zero linear/angular damping (engine overcomes air resistance)
	# - lock_rotation = true prevents physics engine from rotating the body
	# - continuous_cd = 1 for reliable wall detection
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 0.0
	continuous_cd = 1
	lock_rotation = true

	# Enable contact monitoring for body_entered signal
	contact_monitor = true
	max_contacts_reported = 8

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	_trail = get_node_or_null("Trail")
	if _trail:
		_trail.clear_points()
		_trail.top_level = true
		_trail.global_position = Vector2.ZERO

	_exhaust = get_node_or_null("ExhaustParticles")

	# Orient rocket sprite to travel direction
	rotation = direction.angle()

	# Orient exhaust particles to emit backward
	if _exhaust and _exhaust.process_material is ParticleProcessMaterial:
		var mat := _exhaust.process_material as ParticleProcessMaterial
		var back := -direction
		mat.direction = Vector3(back.x, back.y, 0.0)

	# Set initial speed
	_current_speed = speed_initial
	# Apply initial velocity so the rocket starts moving immediately
	linear_velocity = direction.normalized() * _current_speed

	FileLogger.info("[RpgRocket] Spawned: pos=%s dir=%s initial_speed=%.0f max_speed=%.0f" % [str(global_position), str(direction), speed_initial, speed])


## _integrate_forces is called by the physics engine every physics step.
## This is the ONLY correct way to enforce propulsion in exported Godot 4 builds:
## - Runs inside the physics server, no GDScript method dispatch needed
## - Overrides any collision impulses (prevents deflection from walls before exploding)
## - Allows us to implement the acceleration curve
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if _has_exploded:
		state.linear_velocity = Vector2.ZERO
		return

	var delta := state.step

	# Track lifetime
	_time_alive += delta

	# Update spawn immunity
	if _spawn_immunity_active and _time_alive >= spawn_immunity_time:
		_spawn_immunity_active = false
		FileLogger.info("[RpgRocket] Immunity ended, speed=%.0f" % _current_speed)

	# Lifetime expiry
	if _time_alive >= lifetime:
		FileLogger.info("[RpgRocket] Lifetime expired at pos=%s" % str(global_position))
		call_deferred("_explode")
		state.linear_velocity = Vector2.ZERO
		return

	# Acceleration phase: speed increases from speed_initial to speed over accel_distance
	if _distance_traveled < accel_distance:
		var t := _distance_traveled / accel_distance  # 0.0 → 1.0
		# Smooth acceleration curve (ease-in)
		_current_speed = lerpf(speed_initial, speed, t * t)
	else:
		_current_speed = speed

	# Enforce propulsion: always travel in the original direction at current speed.
	# This overrides any collision impulses - the rocket engine keeps it on course.
	state.linear_velocity = direction.normalized() * _current_speed

	# Track distance traveled for acceleration curve
	_distance_traveled += _current_speed * delta

	# Keep visual rotation aligned to direction (lock_rotation=true prevents physics rotation,
	# but we manually set transform.x to match direction for sprite alignment)
	state.transform = Transform2D(direction.angle(), state.transform.origin)


## _physics_process handles visual updates only (trail, exhaust orientation).
## Physics (velocity, rotation) are handled in _integrate_forces.
func _physics_process(_delta: float) -> void:
	if _has_exploded:
		return
	_update_trail()


func _update_trail() -> void:
	if not _trail:
		return
	_position_history.push_front(global_position)
	while _position_history.size() > trail_length:
		_position_history.pop_back()
	_trail.clear_points()
	for pos in _position_history:
		_trail.add_point(pos)


## Called by RigidBody2D physics engine when rocket collides with something.
func _on_body_entered(body: Node) -> void:
	if _has_exploded:
		return
	# Ignore collisions during spawn immunity
	if _spawn_immunity_active:
		return
	# Ignore the shooter
	if shooter_id == body.get_instance_id():
		return
	# Ignore dead entities
	if body.has_method("is_alive") and not body.is_alive():
		return
	# Explode on any solid body: walls, tilemap, player, enemies, other projectiles
	# RigidBody2D covers projectiles (bullets, grenades) and physics objects
	if body is StaticBody2D or body is TileMap or body is CharacterBody2D or body is RigidBody2D or body is AnimatableBody2D:
		FileLogger.info("[RpgRocket] Impact on %s (type: %s) after %.2fs dist=%.0fpx" % [body.name, body.get_class(), _time_alive, _distance_traveled])
		_explode()


## Called when the rocket enters an Area2D (e.g. grenade shockwave).
func _on_area_entered(area: Area2D) -> void:
	if _has_exploded or _spawn_immunity_active:
		return
	# Explode when hit by grenade blast shockwave or similar area
	if area.is_in_group("explosion") or area.is_in_group("shockwave") or area.name.to_lower().contains("explosion") or area.name.to_lower().contains("blast"):
		FileLogger.info("[RpgRocket] Hit by area %s - exploding" % area.name)
		_explode()


func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	# Stop movement
	linear_velocity = Vector2.ZERO

	FileLogger.info("[RpgRocket] Exploded at pos=%s after %.2fs, dist=%.0fpx" % [str(global_position), _time_alive, _distance_traveled])

	if _exhaust:
		_exhaust.emitting = false

	# Trigger Power Fantasy rocket explosion effect
	var power_fantasy_manager: Node = get_node_or_null("/root/PowerFantasyEffectsManager")
	if power_fantasy_manager and power_fantasy_manager.has_method("on_grenade_exploded"):
		power_fantasy_manager.on_grenade_exploded()

	# Play explosion sound via SoundPropagation
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		var viewport := get_viewport()
		var viewport_diagonal := 1469.0
		if viewport:
			var size := viewport.get_visible_rect().size
			viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)
		sound_propagation.emit_sound(1, global_position, 1, self, viewport_diagonal * 2.0)

	# Play explosion sound via AudioManager
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_offensive_grenade_explosion"):
		audio_manager.play_offensive_grenade_explosion(global_position)

	# Damage enemies in radius
	_damage_entities_in_radius()

	# Spawn visual explosion effect
	_spawn_explosion_effect()

	# Scatter casings
	_scatter_casings()

	# Destroy rocket after short delay for effects
	await get_tree().create_timer(0.1).timeout
	queue_free()


func _damage_entities_in_radius() -> void:
	var space_state := get_world_2d().direct_space_state

	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy is Node2D and _is_in_radius(enemy.global_position):
			if _has_line_of_sight(space_state, enemy.global_position):
				_apply_damage(enemy)

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		var player: Node2D = players[0]
		if _is_in_radius(player.global_position) and _has_line_of_sight(space_state, player.global_position):
			_apply_damage(player)


func _is_in_radius(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= explosion_radius


func _has_line_of_sight(space_state: PhysicsDirectSpaceState2D, target_pos: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos)
	query.collision_mask = 4  # Only check against obstacles
	query.exclude = [self]
	return space_state.intersect_ray(query).is_empty()


func _apply_damage(entity: Node2D) -> void:
	var hit_direction := (entity.global_position - global_position).normalized()
	if entity.has_method("on_hit_with_info"):
		for i in range(explosion_damage):
			entity.on_hit_with_info(hit_direction, null)
	elif entity.has_method("on_hit"):
		for i in range(explosion_damage):
			entity.on_hit()


func _spawn_explosion_effect() -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager and impact_manager.has_method("spawn_explosion_effect"):
		impact_manager.spawn_explosion_effect(global_position, explosion_radius)
	else:
		_create_simple_explosion()


func _create_simple_explosion() -> void:
	var flash := Sprite2D.new()
	flash.texture = _create_explosion_texture(int(explosion_radius))
	flash.global_position = global_position
	flash.modulate = Color(1.0, 0.5, 0.1, 0.9)
	flash.z_index = 100
	get_tree().current_scene.add_child(flash)
	var tween := get_tree().create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(flash.queue_free)


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
				image.set_pixel(x, y, Color(1.0, 0.5, 0.1, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


func _scatter_casings() -> void:
	var casings := get_tree().get_nodes_in_group("casings")
	if casings.is_empty():
		return
	var space_state := get_world_2d().direct_space_state
	for casing in casings:
		if not is_instance_valid(casing) or not casing is RigidBody2D:
			continue
		var distance := global_position.distance_to(casing.global_position)
		if distance > explosion_radius * 1.5:
			continue
		if not _has_line_of_sight(space_state, casing.global_position):
			continue
		var dir := (casing.global_position - global_position).normalized().rotated(randf_range(-0.2, 0.2))
		var impulse_strength := 1500.0 * (1.0 - distance / (explosion_radius * 1.5))
		if casing.has_method("receive_kick"):
			casing.receive_kick(dir * impulse_strength)
