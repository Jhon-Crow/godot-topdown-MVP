extends Area2D
class_name RpgRocket
## RPG rocket projectile that explodes on impact (Issue #583).
##
## Travels in a direction and explodes on hitting walls, enemies, or player.
## Deals area-of-effect damage within explosion radius.
## No ricochet or penetration - always explodes on first contact.

## Speed of the rocket in pixels per second.
@export var speed: float = 800.0

## Maximum lifetime in seconds before auto-destruction.
@export var lifetime: float = 5.0

## Explosion effect radius in pixels.
@export var explosion_radius: float = 150.0

## Explosion damage dealt to entities in radius.
@export var explosion_damage: int = 3

## Maximum number of trail points.
@export var trail_length: int = 12

## Direction the rocket travels (set by the shooter).
var direction: Vector2 = Vector2.RIGHT

## Instance ID of the node that shot this rocket.
var shooter_id: int = -1

## Shooter position at time of firing.
var shooter_position: Vector2 = Vector2.ZERO

## Timer tracking remaining lifetime.
var _time_alive: float = 0.0

## Whether the rocket has exploded.
var _has_exploded: bool = false

## Reference to the trail Line2D node (if present).
var _trail: Line2D = null

## History of global positions for the trail effect.
var _position_history: Array[Vector2] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	_trail = get_node_or_null("Trail")
	if _trail:
		_trail.clear_points()
		_trail.top_level = true
		_trail.position = Vector2.ZERO

	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	if _has_exploded:
		return

	position += direction * speed * delta
	_update_trail()

	_time_alive += delta
	if _time_alive >= lifetime:
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


func _on_body_entered(body: Node2D) -> void:
	if _has_exploded:
		return
	if shooter_id == body.get_instance_id():
		return
	if body.has_method("is_alive") and not body.is_alive():
		return
	if body is StaticBody2D or body is TileMap or body is CharacterBody2D:
		_explode()


func _on_area_entered(area: Area2D) -> void:
	if _has_exploded:
		return
	if not area.has_method("on_hit"):
		return
	var parent: Node = area.get_parent()
	if parent and shooter_id == parent.get_instance_id():
		return
	if parent and parent.has_method("is_alive") and not parent.is_alive():
		return
	_explode()


func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

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

	# Damage enemies
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy is Node2D and _is_in_radius(enemy.global_position):
			if _has_line_of_sight(space_state, enemy.global_position):
				_apply_damage(enemy)

	# Damage player
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
