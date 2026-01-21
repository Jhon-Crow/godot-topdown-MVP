extends Node2D
## Procedural blood particle/droplet that moves with physics and spawns decals.
##
## Fully procedural blood system that:
## - Travels in the direction of the bullet hit
## - Properly collides with walls using continuous raycast checking
## - Spawns blood decals/puddles where it lands
## - Creates varied patterns based on hit context
##
## This replaces the hybrid GPU+physics approach with a pure procedural system
## that guarantees proper wall collision.

## Blood particle speed range (pixels per second).
## Balanced for realistic blood travel without excessive spread.
@export var min_speed: float = 40.0
@export var max_speed: float = 120.0

## Gravity applied to the particle (pixels per second squared).
@export var gravity: float = 450.0

## How much the particle slows down per second (0-1, higher = more damping).
@export var damping: float = 0.92

## Maximum lifetime in seconds before auto-destruction.
@export var max_lifetime: float = 1.5

## Collision layer mask for wall detection.
## Bit 4 = Layer 3 (obstacles/walls) per project physics layers.
@export_flags_2d_physics var collision_mask: int = 4

## Minimum movement distance to check for collision (pixels).
## Helps prevent false positives on very small movements.
const MIN_COLLISION_CHECK_DISTANCE: float = 1.0

## Maximum steps for continuous collision detection per frame.
## Higher values = more accurate but slower.
const MAX_COLLISION_STEPS: int = 4

## Current velocity of the particle.
var velocity: Vector2 = Vector2.ZERO

## Reference to the visual sprite.
var _sprite: Sprite2D = null

## Time alive tracker.
var _time_alive: float = 0.0

## Has this particle already landed (spawned decal)?
var _has_landed: bool = false

## Size multiplier for decal when particle lands.
var _decal_size: float = 1.0

## Enable/disable debug logging (off by default for production).
var _debug: bool = false


func _ready() -> void:
	# Create a simple visual representation (small red circle)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"

	# Create a procedural blood droplet texture
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.75, 0.08, 0.04, 1.0),  # Dark red center
		Color(0.6, 0.04, 0.02, 0.85),
		Color(0.4, 0.02, 0.02, 0.0)    # Transparent edge
	])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 6
	texture.height = 6
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	_sprite.texture = texture
	add_child(_sprite)

	# Random size variation for natural look
	var size_scale := randf_range(0.4, 1.2)
	_sprite.scale = Vector2(size_scale, size_scale)
	_decal_size = size_scale


func _physics_process(delta: float) -> void:
	if _has_landed:
		return

	# Apply gravity
	velocity.y += gravity * delta

	# Apply damping (air resistance)
	velocity *= pow(damping, delta)

	# Calculate total movement for this frame
	var total_movement := velocity * delta
	var movement_length := total_movement.length()

	# Skip collision check for very small movements
	if movement_length < MIN_COLLISION_CHECK_DISTANCE:
		global_position += total_movement
		_update_lifetime(delta)
		return

	# Continuous collision detection: subdivide movement into smaller steps
	# to prevent particles from tunneling through thin walls
	var steps := mini(ceili(movement_length / 8.0), MAX_COLLISION_STEPS)
	var step_movement := total_movement / float(steps)

	for i in range(steps):
		if _check_wall_collision(step_movement):
			_on_wall_hit()
			return
		global_position += step_movement

	# Update lifetime
	_update_lifetime(delta)


## Updates lifetime counter and handles timeout.
func _update_lifetime(delta: float) -> void:
	_time_alive += delta

	# Fade out as particle ages
	if _sprite and _time_alive > max_lifetime * 0.6:
		var fade_progress := (_time_alive - max_lifetime * 0.6) / (max_lifetime * 0.4)
		_sprite.modulate.a = 1.0 - fade_progress

	if _time_alive >= max_lifetime:
		_on_timeout()


## Checks if movement will collide with a wall.
## @param movement: The movement vector to check.
## @return: True if collision detected, false otherwise.
func _check_wall_collision(movement: Vector2) -> bool:
	var space_state := get_world_2d()
	if space_state == null:
		return false

	var direct_space := space_state.direct_space_state
	if direct_space == null:
		return false

	var from := global_position
	var to := global_position + movement

	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = collision_mask
	query.hit_from_inside = true  # Important: detect if we're already inside a wall

	var result := direct_space.intersect_ray(query)

	if not result.is_empty():
		# Move to just before the collision point to avoid getting stuck
		var collision_point: Vector2 = result.position
		var normal: Vector2 = result.normal

		# Offset slightly from the wall surface
		global_position = collision_point + normal * 2.0
		return true

	return false


## Called when the particle hits a wall.
func _on_wall_hit() -> void:
	if _has_landed:
		return
	_has_landed = true

	if _debug:
		print("[BloodParticle] Hit wall at ", global_position)

	# Spawn a blood decal at this location
	_spawn_decal(_decal_size)

	# Remove this particle
	queue_free()


## Called when particle times out without hitting a wall.
func _on_timeout() -> void:
	if _has_landed:
		return
	_has_landed = true

	if _debug:
		print("[BloodParticle] Timeout at ", global_position)

	# Spawn a smaller decal where it ended (simulating floor landing)
	_spawn_decal(_decal_size * 0.6)

	queue_free()


## Spawns a blood decal at the current position.
## @param size_multiplier: Scale multiplier for the decal size.
func _spawn_decal(size_multiplier: float = 1.0) -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager == null:
		return

	# Use the manager's decal spawning if available
	if impact_manager.has_method("spawn_blood_decal_at"):
		impact_manager.spawn_blood_decal_at(global_position, size_multiplier)
	elif impact_manager.has_method("_spawn_blood_decal"):
		# Fallback to internal method
		impact_manager._spawn_blood_decal(global_position, velocity.normalized(), size_multiplier)


## Initializes the particle with direction and context parameters.
## @param direction: Direction the blood should travel (normalized).
## @param intensity: Intensity multiplier (affects speed and size).
## @param spread_angle: Random spread angle in radians.
## @param target_velocity: Optional velocity of the target when hit.
## @param distance: Optional distance from shooter.
## @param impact_angle: Optional angle of impact.
func initialize(
	direction: Vector2,
	intensity: float = 1.0,
	spread_angle: float = 0.3,
	target_velocity: Vector2 = Vector2.ZERO,
	distance: float = 0.0,
	impact_angle: float = 0.0
) -> void:
	# Calculate contextual variations
	var context_multiplier := 1.0
	var context_spread := spread_angle

	# Target velocity influence: moving targets affect spray direction
	if target_velocity.length() > 10.0:
		var velocity_influence := target_velocity.normalized() * 0.25
		direction = (direction + velocity_influence).normalized()
		context_spread *= 1.15
		context_multiplier *= 0.9

	# Distance influence: close shots = higher pressure
	if distance > 0.0:
		if distance < 100.0:
			# Close range: high pressure, tight spray
			context_multiplier *= 1.3
			context_spread *= 0.7
		elif distance > 300.0:
			# Long range: lower pressure, wider spray
			context_multiplier *= 0.75
			context_spread *= 1.2

	# Impact angle influence: grazing vs direct hits
	if impact_angle != 0.0:
		var angle_factor := absf(sin(impact_angle))
		if angle_factor < 0.3:
			# Grazing hit: elongated spray
			context_spread *= 1.4
			context_multiplier *= 0.7
		else:
			# Direct hit: concentrated spray
			context_spread *= 0.85

	# Apply random spread to direction
	var angle_deviation := randf_range(-context_spread, context_spread)
	var spread_direction := direction.rotated(angle_deviation)

	# Calculate final velocity
	var speed := randf_range(min_speed, max_speed) * intensity * context_multiplier
	velocity = spread_direction * speed

	# Store size for decal
	_decal_size = clampf(intensity * context_multiplier * randf_range(0.5, 1.3), 0.3, 2.0)

	# Apply visual scale
	if _sprite:
		_sprite.scale *= _decal_size * 0.8
