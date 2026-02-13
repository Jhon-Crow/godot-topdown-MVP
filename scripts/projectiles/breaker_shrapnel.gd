extends Area2D
class_name BreakerShrapnel
## Shrapnel projectile from a breaker bullet explosion (Issue #678).
##
## Unlike grenade shrapnel, breaker shrapnel:
## - Does NOT ricochet off walls (destroyed on wall hit)
## - Does NOT penetrate walls
## - Deals 0.1 damage per piece
## - Has an uneven smoky tracer trail
## - Travels in a forward cone from the bullet's direction

## Speed of the shrapnel in pixels per second.
@export var speed: float = 1800.0

## Maximum lifetime in seconds before auto-destruction.
## Reduced from 1.5s to 0.8s for performance (Issue #678 optimization).
@export var lifetime: float = 0.8

## Damage dealt on hit.
@export var damage: float = 0.1

## Maximum number of trail points to maintain.
## Reduced from 10 to 6 for performance (Issue #678 optimization).
@export var trail_length: int = 6

## Direction the shrapnel travels.
var direction: Vector2 = Vector2.RIGHT

## Instance ID of the entity that caused this shrapnel (bullet shooter).
## Used to prevent self-damage.
var source_id: int = -1

## Timer tracking remaining lifetime.
var _time_alive: float = 0.0

## Reference to the trail Line2D node (if present).
var _trail: Line2D = null

## History of global positions for the trail effect.
var _position_history: Array[Vector2] = []

## Noise offset for the smoky trail wobble.
var _trail_noise_offset: float = 0.0

## Random seed per shrapnel for unique trail shapes.
var _trail_noise_speed: float = 0.0

## Enable/disable debug logging.
var _debug: bool = false


func _ready() -> void:
	# Add to group for global shrapnel count tracking (Issue #678 optimization)
	add_to_group("breaker_shrapnel")

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

	# Randomize noise offset for unique trail wobble per shrapnel
	_trail_noise_offset = randf() * 100.0
	_trail_noise_speed = randf_range(8.0, 15.0)


func _physics_process(delta: float) -> void:
	# Move in the set direction
	var movement := direction * speed * delta
	position += movement

	# Slow down gradually (air resistance / deceleration)
	speed = maxf(speed * 0.995, 200.0)

	# Update smoky trail effect
	_update_smoky_trail(delta)

	# Track lifetime and auto-destroy if exceeded
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()


## Updates the shrapnel rotation to match its travel direction.
func _update_rotation() -> void:
	rotation = direction.angle()


## Updates the visual smoky trail effect with noise-based wobble.
func _update_smoky_trail(delta: float) -> void:
	if not _trail:
		return

	# Advance noise offset for animated wobble
	_trail_noise_offset += _trail_noise_speed * delta

	# Calculate a perpendicular wobble offset for the current position
	var perpendicular := Vector2(-direction.y, direction.x).normalized()
	var wobble_amount := sin(_trail_noise_offset) * 1.5 + sin(_trail_noise_offset * 2.3) * 0.8
	var wobbled_pos := global_position + perpendicular * wobble_amount

	# Add wobbled position to history
	_position_history.push_front(wobbled_pos)

	# Limit trail length
	while _position_history.size() > trail_length:
		_position_history.pop_back()

	# Update Line2D points
	_trail.clear_points()
	for pos in _position_history:
		_trail.add_point(pos)


func _on_body_entered(body: Node2D) -> void:
	# Don't collide with the source shooter
	if source_id == body.get_instance_id():
		return

	# Pass through dead entities
	if body.has_method("is_alive") and not body.is_alive():
		return

	# Hit a wall/obstacle — breaker shrapnel does NOT ricochet, just destroy
	if body is StaticBody2D or body is TileMap:
		# Spawn wall hit effect
		_spawn_wall_hit_effect(body)

		# Play wall impact sound and destroy
		var audio_manager: Node = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
			audio_manager.play_bullet_wall_hit(global_position)
		queue_free()
		return

	# Hit other bodies — destroy
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

		# Deal fractional damage (0.1)
		if area.has_method("on_hit_with_bullet_info_and_damage"):
			area.on_hit_with_bullet_info_and_damage(direction, null, false, false, damage)
		elif area.has_method("on_hit_with_info"):
			area.on_hit_with_info(direction, null)
		else:
			area.on_hit()

		queue_free()


## Spawns dust/debris particles when shrapnel hits a wall.
func _spawn_wall_hit_effect(body: Node2D) -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager == null or not impact_manager.has_method("spawn_dust_effect"):
		return

	# Get surface normal for particle direction
	var surface_normal := _get_surface_normal(body)

	# Spawn dust effect at hit position (without caliber data - small effect)
	impact_manager.spawn_dust_effect(global_position, surface_normal, null)


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


# ============================================================================
# Object Pooling Support (Issue #724)
# ============================================================================


## Whether this shrapnel is currently pooled (inactive).
var _is_pooled: bool = false

## Original speed value for reset.
var _original_speed: float = 1800.0


## Activates the breaker shrapnel from the pool with the given parameters.
## @param pos: Global position to spawn at.
## @param dir: Direction of travel.
## @param source: Instance ID of the source (bullet shooter) for self-damage prevention.
func pool_activate(pos: Vector2, dir: Vector2, source: int) -> void:
	# Reset all state to defaults
	_reset_state()

	# Set activation parameters
	global_position = pos
	direction = dir.normalized()
	source_id = source

	# Randomize trail noise for unique look
	_trail_noise_offset = randf() * 100.0
	_trail_noise_speed = randf_range(8.0, 15.0)

	# Update rotation to match direction
	_update_rotation()

	# Re-enable processing and visibility
	visible = true
	set_physics_process(true)
	set_process(true)

	# Re-enable collision detection
	monitoring = true
	monitorable = true

	_is_pooled = false


## Deactivates the breaker shrapnel and prepares it for return to the pool.
func pool_deactivate() -> void:
	if _is_pooled:
		return

	_is_pooled = true

	# Disable processing
	set_physics_process(false)
	set_process(false)

	# Hide shrapnel
	visible = false

	# Disable collision detection
	monitoring = false
	monitorable = false

	# Clear trail
	if _trail:
		_trail.clear_points()
	_position_history.clear()

	# Return to pool manager
	var pool_manager: Node = get_node_or_null("/root/ProjectilePoolManager")
	if pool_manager and pool_manager.has_method("return_breaker_shrapnel"):
		pool_manager.return_breaker_shrapnel(self)


## Resets all breaker shrapnel state to defaults for reuse.
func _reset_state() -> void:
	# Reset core properties
	speed = _original_speed
	damage = 0.1
	_time_alive = 0.0
	direction = Vector2.RIGHT
	source_id = -1

	# Reset trail noise
	_trail_noise_offset = 0.0
	_trail_noise_speed = 10.0

	# Clear position history
	_position_history.clear()

	# Clear trail
	if _trail:
		_trail.clear_points()


## Returns whether this breaker shrapnel is currently pooled (inactive).
func is_pooled() -> bool:
	return _is_pooled


## Convenience method to get a breaker shrapnel from the pool.
static func from_pool() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var pool_manager: Node = tree.root.get_node_or_null("ProjectilePoolManager")
		if pool_manager and pool_manager.has_method("get_breaker_shrapnel"):
			return pool_manager.get_breaker_shrapnel()
	return null
