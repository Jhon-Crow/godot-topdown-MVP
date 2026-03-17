extends Area2D
class_name RpgRocket
## RPG-7 rocket projectile — flies straight with rocket motor acceleration and explodes on impact.
##
## Physics model based on real RPG-7 data:
## - Two-phase propulsion: initial launch velocity, then sustainer motor accelerates to max speed
## - Fin-stabilized straight flight: no free rotation, no physics drift (same as bullet.gd Area2D pattern)
## - Explodes on any solid contact: walls, player, enemies, other projectiles, grenade shockwaves
## - Self-destructs after lifetime expires
##
## See docs/case-studies/issue-583/rpg7_physics_research.md for data sources.

## Initial launch speed (pixels/s). Analogous to real RPG-7 muzzle velocity ~115 m/s.
@export var launch_speed: float = 300.0

## Maximum speed after motor burns out (pixels/s). Analogous to real RPG-7 ~294 m/s.
@export var max_speed: float = 900.0

## Motor acceleration (pixels/s²). Sustainer fires for motor_burn_time seconds.
## Derived: (max_speed - launch_speed) / motor_burn_time ≈ 600 / 0.8 = 750.
@export var motor_acceleration: float = 750.0

## How long the rocket motor burns (seconds). Based on RPG-7 ~2–3 s real, scaled for gameplay.
@export var motor_burn_time: float = 0.8

## Maximum lifetime before self-destruct (seconds). Real RPG-7 fuze: 4.5 s.
@export var lifetime: float = 4.5

## Explosion effect radius in pixels.
@export var explosion_radius: float = 150.0

## Explosion damage dealt to entities in radius.
@export var explosion_damage: int = 3

## Seconds after spawn during which collisions are ignored (avoids exploding next to shooter).
@export var spawn_immunity_time: float = 0.25

## Direction the rocket travels (set by the shooter before add_child, same as bullet.gd).
var direction: Vector2 = Vector2.RIGHT

## Instance ID of the node that shot this rocket (ignore self-collision).
var shooter_id: int = -1

## Shooter position at time of firing.
var shooter_position: Vector2 = Vector2.ZERO

## Current speed (starts at launch_speed, increases during motor burn).
var _speed: float = 0.0

## Time elapsed since spawn.
var _time_alive: float = 0.0

## Whether the rocket has already exploded.
var _has_exploded: bool = false

## Reference to the trail Line2D node (if present).
var _trail: Line2D = null

## Reference to the exhaust GPUParticles2D node (if present).
var _exhaust: GPUParticles2D = null

## History of global positions for the trail effect.
var _position_history: Array[Vector2] = []

## Maximum number of trail points.
@export var trail_length: int = 20


func _ready() -> void:
	# Start at launch speed
	_speed = launch_speed

	# Connect collision signals (Area2D pattern from bullet.gd)
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	_trail = get_node_or_null("Trail")
	if _trail:
		_trail.clear_points()
		_trail.top_level = true
		_trail.global_position = Vector2.ZERO

	_exhaust = get_node_or_null("ExhaustParticles")

	# Note: direction is set by the spawner AFTER add_child (same as bullet.gd pattern).
	# _physics_process updates rotation every frame so the initial rotation here is just a best-effort.
	rotation = direction.angle()

	# Orient exhaust particles to emit backward from rocket direction
	if _exhaust and _exhaust.process_material is ParticleProcessMaterial:
		var mat := _exhaust.process_material as ParticleProcessMaterial
		var back := -direction
		mat.direction = Vector3(back.x, back.y, 0.0)

	FileLogger.info("[RpgRocket] Spawned: pos=%s dir=%s (will be overridden by spawner) launch_speed=%.0f max_speed=%.0f" % [
		str(global_position), str(direction), launch_speed, max_speed])


func _physics_process(delta: float) -> void:
	if _has_exploded:
		return

	_time_alive += delta

	# Keep rotation locked to direction (prevent any accidental rotation)
	# Note: direction may be set AFTER _ready() by the spawner (same as bullet.gd pattern),
	# so rotation is updated every frame to stay correct.
	rotation = direction.angle()

	# Phase 1: Motor burn — accelerate from launch_speed to max_speed
	if _time_alive <= motor_burn_time:
		_speed = min(_speed + motor_acceleration * delta, max_speed)

	# Move straight in direction (no physics drift, no free rotation — same as bullet.gd)
	position += direction * _speed * delta

	# Log first-frame movement for diagnostics (helps confirm _physics_process is running in exports)
	if _time_alive <= delta * 2.0:
		FileLogger.info("[RpgRocket] First frame: pos=%s dir=%s speed=%.0f delta=%.4f" % [
			str(global_position), str(direction), _speed, delta])

	_update_trail()

	# Self-destruct after lifetime
	if _time_alive >= lifetime:
		FileLogger.info("[RpgRocket] Self-destruct at pos=%s after %.2fs" % [str(global_position), _time_alive])
		_explode()


func _update_trail() -> void:
	if not _trail:
		return
	_position_history.push_front(global_position)
	while _position_history.size() > trail_length:
		_position_history.pop_back()
	_trail.clear_points()
	for pos in _position_history:
		_trail.add_point(pos)


## Called when rocket enters a solid body (wall, enemy CharacterBody2D, player).
func _on_body_entered(body: Node) -> void:
	if _has_exploded:
		return
	if _time_alive < spawn_immunity_time:
		return
	# Ignore the shooter
	if shooter_id == body.get_instance_id():
		return
	# Ignore dead entities
	if body.has_method("is_alive") and not body.is_alive():
		return
	FileLogger.info("[RpgRocket] Body impact: %s (%s) at pos=%s after %.2fs" % [
		body.name, body.get_class(), str(global_position), _time_alive])
	_explode()


## Called when rocket enters an area (enemy HitArea, grenade shockwave, other projectile area).
func _on_area_entered(area: Area2D) -> void:
	if _has_exploded:
		return
	if _time_alive < spawn_immunity_time:
		return
	# Ignore own child areas
	if area.get_parent() == self:
		return
	# Ignore the shooter's areas
	var area_parent := area.get_parent()
	if area_parent != null and shooter_id == area_parent.get_instance_id():
		return
	# Explode on contact with any foreign area (enemy HitArea, shockwave, other projectile)
	FileLogger.info("[RpgRocket] Area impact: %s (parent: %s) at pos=%s after %.2fs" % [
		area.name, area_parent.name if area_parent else "none", str(global_position), _time_alive])
	_explode()


func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	FileLogger.info("[RpgRocket] Exploded at pos=%s speed=%.0f after %.2fs travel" % [
		str(global_position), _speed, _time_alive])

	# Stop exhaust particles
	if _exhaust:
		_exhaust.emitting = false

	# Trigger Power Fantasy effect
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

	# Damage entities in blast radius
	_damage_entities_in_radius()

	# Visual explosion effect
	_spawn_explosion_effect()

	# Scatter casings
	_scatter_casings()

	# Destroy rocket (short delay for effects to start)
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
