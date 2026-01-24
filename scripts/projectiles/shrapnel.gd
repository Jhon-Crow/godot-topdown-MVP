extends Area2D
class_name Shrapnel
## Shrapnel projectile from a frag grenade explosion.
##
## Shrapnel pieces travel in all directions from the grenade explosion point.
## They ricochet off walls (like bullets) and deal 1 damage on hit.
## Initial speed is 2x faster than assault rifle bullets (5000 px/s).

## Speed of the shrapnel in pixels per second (2x assault rifle speed of 2500).
@export var speed: float = 5000.0

## Maximum lifetime in seconds before auto-destruction.
@export var lifetime: float = 2.0

## Maximum number of ricochets before destruction.
@export var max_ricochets: int = 3

## Damage dealt on hit.
@export var damage: int = 1

## Maximum number of trail points to maintain.
@export var trail_length: int = 6

## Direction the shrapnel travels.
var direction: Vector2 = Vector2.RIGHT

## Instance ID of the entity that caused this shrapnel (grenade).
## Used to prevent self-damage during initial explosion.
var source_id: int = -1

## Timer tracking remaining lifetime.
var _time_alive: float = 0.0

## Number of ricochets that have occurred.
var _ricochet_count: int = 0

## Reference to the trail Line2D node (if present).
var _trail: Line2D = null

## History of global positions for the trail effect.
var _position_history: Array[Vector2] = []

## Velocity retention after each ricochet (slight energy loss).
const VELOCITY_RETENTION: float = 0.8

## Random angle deviation for ricochet direction in degrees.
const RICOCHET_ANGLE_DEVIATION: float = 15.0


func _ready() -> void:
	# Connect to collision signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Get trail reference if it exists
	_trail = get_node_or_null("Trail")
	if _trail:
		_trail.clear_points()
		_trail.top_level = true
		_trail.position = Vector2.ZERO

	# Set initial rotation based on direction
	_update_rotation()


func _physics_process(delta: float) -> void:
	# Move in the set direction
	var movement := direction * speed * delta
	position += movement

	# Update trail effect
	_update_trail()

	# Track lifetime and auto-destroy if exceeded
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()


## Updates the shrapnel rotation to match its travel direction.
func _update_rotation() -> void:
	rotation = direction.angle()


## Updates the visual trail effect by maintaining position history.
func _update_trail() -> void:
	if not _trail:
		return

	# Add current position to history
	_position_history.push_front(global_position)

	# Limit trail length
	while _position_history.size() > trail_length:
		_position_history.pop_back()

	# Update Line2D points
	_trail.clear_points()
	for pos in _position_history:
		_trail.add_point(pos)


func _on_body_entered(body: Node2D) -> void:
	# Don't collide with the grenade source
	if source_id == body.get_instance_id():
		return

	# Check if this is a dead enemy - shrapnel should pass through dead entities
	if body.has_method("is_alive") and not body.is_alive():
		return

	# Hit a static body (wall or obstacle) - try to ricochet
	if body is StaticBody2D or body is TileMap:
		# Spawn wall hit effect
		_spawn_wall_hit_effect(body)

		# Try to ricochet
		if _try_ricochet(body):
			return  # Shrapnel ricocheted, continue

	# Play wall impact sound and destroy
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		audio_manager.play_bullet_wall_hit(global_position)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# Hit a target with hit detection
	if area.has_method("on_hit"):
		# Check against parent's instance ID
		var parent: Node = area.get_parent()
		if parent and source_id == parent.get_instance_id():
			return  # Don't hit the source

		# Check if the parent is dead
		if parent and parent.has_method("is_alive") and not parent.is_alive():
			return  # Pass through dead entities

		# Deal damage - shrapnel always deals 1 damage
		if area.has_method("on_hit_with_info"):
			area.on_hit_with_info(direction, null)
		else:
			area.on_hit()

		queue_free()


## Attempts to ricochet the shrapnel off a surface.
## Returns true if ricochet occurred, false if shrapnel should be destroyed.
func _try_ricochet(body: Node2D) -> bool:
	# Check if we've exceeded maximum ricochets
	if _ricochet_count >= max_ricochets:
		return false

	# Get the surface normal at the collision point
	var surface_normal := _get_surface_normal(body)
	if surface_normal == Vector2.ZERO:
		return false

	# Perform ricochet
	_perform_ricochet(surface_normal)
	return true


## Gets the surface normal at the collision point using raycasting.
func _get_surface_normal(body: Node2D) -> Vector2:
	var space_state := get_world_2d().direct_space_state

	# Cast ray from slightly behind the shrapnel to current position
	var ray_start := global_position - direction * 50.0
	var ray_end := global_position + direction * 10.0

	var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end)
	query.collision_mask = collision_mask
	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		# Fallback: estimate normal based on direction
		return -direction.normalized()

	return result.normal


## Performs the ricochet: updates direction and reduces speed.
func _perform_ricochet(surface_normal: Vector2) -> void:
	_ricochet_count += 1

	# Calculate reflected direction
	var reflected := direction - 2.0 * direction.dot(surface_normal) * surface_normal
	reflected = reflected.normalized()

	# Add random deviation for realism
	var deviation_rad := deg_to_rad(randf_range(-RICOCHET_ANGLE_DEVIATION, RICOCHET_ANGLE_DEVIATION))
	reflected = reflected.rotated(deviation_rad)

	# Update direction
	direction = reflected
	_update_rotation()

	# Reduce velocity
	speed *= VELOCITY_RETENTION

	# Move shrapnel slightly away from surface to prevent immediate re-collision
	global_position += direction * 5.0

	# Clear trail history to avoid visual artifacts
	_position_history.clear()

	# Play ricochet sound
	_play_ricochet_sound()


## Plays the ricochet sound effect.
func _play_ricochet_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_ricochet"):
		audio_manager.play_bullet_ricochet(global_position)
	elif audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		audio_manager.play_bullet_wall_hit(global_position)


## Spawns dust/debris particles when shrapnel hits a wall.
func _spawn_wall_hit_effect(body: Node2D) -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager == null or not impact_manager.has_method("spawn_dust_effect"):
		return

	# Get surface normal for particle direction
	var surface_normal := _get_surface_normal(body)

	# Spawn dust effect at hit position (without caliber data - small effect)
	impact_manager.spawn_dust_effect(global_position, surface_normal, null)
