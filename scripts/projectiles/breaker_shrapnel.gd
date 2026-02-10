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

# ============================================================================
# Issue #724: Optimization - Cached Manager References
# ============================================================================

## Cached reference to AudioManager autoload.
var _audio_manager: Node = null

## Cached reference to ImpactEffectsManager autoload.
var _impact_manager: Node = null

## Cached reference to ProjectilePool autoload.
var _projectile_pool: Node = null

## Whether this shrapnel is managed by the ProjectilePool.
var _is_pooled: bool = false


func _ready() -> void:
	# Cache manager references once (Issue #724 optimization)
	_cache_manager_references()

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


## Caches references to autoload managers.
## Issue #724 optimization: Reduces per-shrapnel overhead.
func _cache_manager_references() -> void:
	_audio_manager = get_node_or_null("/root/AudioManager")
	_impact_manager = get_node_or_null("/root/ImpactEffectsManager")
	_projectile_pool = get_node_or_null("/root/ProjectilePool")


## Resets the breaker shrapnel to its default state for pool reuse.
## Issue #724 optimization: Enables efficient shrapnel recycling.
func reset_for_pool() -> void:
	direction = Vector2.RIGHT
	speed = 1800.0
	damage = 0.1
	source_id = -1
	_time_alive = 0.0
	rotation = 0.0
	_trail_noise_offset = randf() * 100.0
	_trail_noise_speed = randf_range(8.0, 15.0)
	_position_history.clear()
	if _trail:
		_trail.clear_points()


## Deactivates the shrapnel, returning it to the pool if pooled, or freeing it.
## Issue #724 optimization: Enables shrapnel recycling.
func deactivate() -> void:
	if _is_pooled and _projectile_pool and _projectile_pool.has_method("return_breaker_shrapnel"):
		_projectile_pool.return_breaker_shrapnel(self)
	else:
		queue_free()


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
		deactivate()


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
		# Issue #724: Use cached _audio_manager reference
		if _audio_manager and _audio_manager.has_method("play_bullet_wall_hit"):
			_audio_manager.play_bullet_wall_hit(global_position)
		deactivate()
		return

	# Hit other bodies — destroy
	deactivate()


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

		deactivate()


## Spawns dust/debris particles when shrapnel hits a wall.
## Issue #724: Use cached _impact_manager reference.
func _spawn_wall_hit_effect(body: Node2D) -> void:
	if _impact_manager == null or not _impact_manager.has_method("spawn_dust_effect"):
		return

	# Get surface normal for particle direction
	var surface_normal := _get_surface_normal(body)

	# Spawn dust effect at hit position (without caliber data - small effect)
	_impact_manager.spawn_dust_effect(global_position, surface_normal, null)


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
