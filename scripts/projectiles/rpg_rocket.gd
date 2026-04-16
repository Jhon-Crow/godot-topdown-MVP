extends Area2D
class_name RpgRocket
## RPG rocket projectile that explodes on impact (Issue #583).
##
## Travels in a direction and explodes on hitting walls, enemies, or player.
## Deals area-of-effect damage within explosion radius.
## No ricochet — always explodes on first contact.
## Wall penetration (Issue #1131): hitting a StaticBody2D wall carves a 120 px passage
## at the impact point, identical to the "Breaching Charges" active item effect.
##
## Movement: Uses Area2D with manual position updates in _physics_process(),
## identical to how bullet.gd works. This ensures reliable body_entered
## collision detection - Area2D.body_entered fires when a physics body overlaps
## the area, regardless of speed. RigidBody2D._integrate_forces() was tried but
## prevented body_entered from firing (rocket would launch but never explode).
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

## Weak homing: turning speed toward the player in radians per second (Issue #1135).
## A small value gives a subtle "guided missile" feel without making it unavoidable.
## Set to 0.0 to disable homing entirely.
@export var homing_steer_speed: float = 1.2

## Maximum total turn from the original firing direction (radians) (Issue #1135).
## Limits how far the rocket can veer — keeps it feeling like a light correction.
@export var homing_max_turn_angle: float = deg_to_rad(30.0)

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

## StaticBody2D wall that was hit last, stored for passage creation in _explode().
var _hit_wall: StaticBody2D = null

## Original firing direction, stored when rocket spawns (for homing angle limit) (Issue #1135).
var _homing_original_direction: Vector2 = Vector2.ZERO

## Maximum number of trail points.
@export var trail_length: int = 20


func _ready() -> void:
	# Orient rocket sprite to travel direction
	rotation = direction.angle()

	# Orient exhaust particles to emit backward
	_exhaust = get_node_or_null("ExhaustParticles")
	if _exhaust and _exhaust.process_material is ParticleProcessMaterial:
		var mat := _exhaust.process_material as ParticleProcessMaterial
		var back := -direction
		mat.direction = Vector3(back.x, back.y, 0.0)

	_trail = get_node_or_null("Trail")
	if _trail:
		_trail.clear_points()
		_trail.top_level = true
		_trail.global_position = Vector2.ZERO

	# Connect collision signals (Area2D.body_entered fires on physics body overlap)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)

	# Set initial speed
	_current_speed = speed_initial

	# Store original direction for homing angle limit (Issue #1135)
	_homing_original_direction = direction.normalized()

	FileLogger.info("[RpgRocket] Spawned: pos=%s dir=%s initial_speed=%.0f max_speed=%.0f" % [str(global_position), str(direction), speed_initial, speed])


func _physics_process(delta: float) -> void:
	if _has_exploded:
		return

	# Track lifetime
	_time_alive += delta

	# Update spawn immunity
	if _spawn_immunity_active and _time_alive >= spawn_immunity_time:
		_spawn_immunity_active = false
		FileLogger.info("[RpgRocket] Immunity ended at pos=%s speed=%.0f" % [str(global_position), _current_speed])

	# Lifetime expiry
	if _time_alive >= lifetime:
		FileLogger.info("[RpgRocket] Lifetime expired at pos=%s" % str(global_position))
		_explode()
		return

	# Acceleration phase: speed increases from speed_initial to speed over accel_distance
	if _distance_traveled < accel_distance:
		var t := _distance_traveled / accel_distance  # 0.0 → 1.0
		# Smooth acceleration curve (ease-in)
		_current_speed = lerpf(speed_initial, speed, t * t)
	else:
		_current_speed = speed

	# Weak homing: gently steer toward the player (Issue #1135)
	if homing_steer_speed > 0.0:
		_apply_homing_steering(delta)

	# Move in travel direction (same pattern as bullet.gd)
	var movement := direction.normalized() * _current_speed * delta
	position += movement
	_distance_traveled += movement.length()

	# Update visual trail
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


## Called by Area2D physics engine when rocket overlaps a physics body.
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
	if body is StaticBody2D or body is TileMap or body is CharacterBody2D or body is RigidBody2D or body is AnimatableBody2D:
		FileLogger.info("[RpgRocket] Impact on %s (type: %s) after %.2fs dist=%.0fpx" % [body.name, body.get_class(), _time_alive, _distance_traveled])
		# Record wall for passage creation (Issue #1131)
		if body is StaticBody2D:
			_hit_wall = body as StaticBody2D
		_explode()


## Called when the rocket enters an Area2D (e.g. grenade shockwave or bullet).
func _on_area_entered(area: Area2D) -> void:
	if _has_exploded or _spawn_immunity_active:
		return
	# Explode when hit by grenade blast shockwave or similar area
	if area.is_in_group("explosion") or area.is_in_group("shockwave") or area.name.to_lower().contains("explosion") or area.name.to_lower().contains("blast"):
		FileLogger.info("[RpgRocket] Hit by area %s - exploding" % area.name)
		_explode()
		return
	# Incoming bullet/shrapnel on projectiles layer (Issue #1307).
	# Skip other RPG rockets to avoid mutual destruction.
	if area.collision_layer & 16:
		if area is RpgRocket:
			return
		FileLogger.info("[RpgRocket] Hit by projectile %s - exploding" % area.name)
		_explode()


## Receive incoming damage from bullets, shrapnel, or explosions (Issue #1307).
## Triggers full explosion so the rocket detonates when shot.
func on_hit() -> void:
	if _has_exploded:
		return
	FileLogger.info("[RpgRocket] on_hit() — exploding at pos=%s" % str(global_position))
	_explode()


## Variant accepting hit direction and caliber data (Issue #1307).
func on_hit_with_info(_hit_direction: Vector2, _caliber: Resource) -> void:
	on_hit()


## Variant accepting full bullet info including damage amount (Issue #1307).
func on_hit_with_bullet_info_and_damage(_hit_direction: Vector2, _caliber: Resource,
		_ricocheted: bool, _penetrated: bool, _dmg: float) -> void:
	on_hit()


func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	FileLogger.info("[RpgRocket] Exploded at pos=%s after %.2fs, dist=%.0fpx" % [str(global_position), _time_alive, _distance_traveled])

	# Carve a wall passage when the rocket hits a StaticBody2D wall (Issue #1131).
	# Uses WallBreachHelper — same 120 px passage as the "Breaching Charges" active item.
	if _hit_wall != null and is_instance_valid(_hit_wall):
		FileLogger.info("[RpgRocket] Creating wall passage in '%s'" % _hit_wall.name)
		WallBreachHelper.open_wall_passage(_hit_wall, global_position)
		_hit_wall = null

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


## Gently steers the rocket toward the player (Issue #1135).
## Uses the same angular-clamping pattern as bullet.gd homing:
##   1. Find player position.
##   2. Compute angle difference between current direction and direction-to-player.
##   3. Clamp the per-frame turn to homing_steer_speed * delta (smooth).
##   4. Reject the turn if it would exceed homing_max_turn_angle from the original
##      firing direction — keeps the effect subtle.
func _apply_homing_steering(delta: float) -> void:
	var tree := get_tree()
	if tree == null:
		return

	# Find the player
	var players := tree.get_nodes_in_group("player")
	if players.is_empty():
		return
	var player: Node = players[0]
	if not player is Node2D:
		return
	# Skip dead player
	if player.has_method("is_alive") and not player.is_alive():
		return

	var target_pos: Vector2 = (player as Node2D).global_position

	# Direction toward player from current rocket position
	var to_target := (target_pos - global_position).normalized()

	# Signed angle between current direction and desired direction
	var angle_diff := direction.angle_to(to_target)

	# Clamp per-frame turn (smooth steering)
	var max_steer_this_frame := homing_steer_speed * delta
	angle_diff = clampf(angle_diff, -max_steer_this_frame, max_steer_this_frame)

	# Candidate new direction
	var new_direction := direction.rotated(angle_diff).normalized()

	# Do not exceed total turn limit from original firing direction
	var angle_from_original := _homing_original_direction.angle_to(new_direction)
	if absf(angle_from_original) > homing_max_turn_angle:
		return

	# Apply steering and update sprite/trail orientation
	direction = new_direction
	rotation = direction.angle()


func _scatter_casings() -> void:
	var casings := get_tree().get_nodes_in_group("casings")
	if casings.is_empty():
		return
	var space_state := get_world_2d().direct_space_state
	for casing in casings:
		if not is_instance_valid(casing) or not casing is RigidBody2D:
			continue
		var casing_body := casing as RigidBody2D
		var distance: float = global_position.distance_to(casing_body.global_position)
		if distance > explosion_radius * 1.5:
			continue
		if not _has_line_of_sight(space_state, casing_body.global_position):
			continue
		var dir: Vector2 = (casing_body.global_position - global_position).normalized().rotated(randf_range(-0.2, 0.2))
		var impulse_strength := 1500.0 * (1.0 - distance / (explosion_radius * 1.5))
		if casing_body.has_method("receive_kick"):
			casing_body.receive_kick(dir * impulse_strength)
