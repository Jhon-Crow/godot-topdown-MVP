extends Area2D
## Bullet projectile that travels in a direction and handles collisions.
##
## The bullet moves at a constant speed in its rotation direction.
## It destroys itself when hitting walls or targets, and triggers
## target reactions on hit.
##
## Features a visual tracer trail effect for better visibility and
## realistic appearance during fast movement.
##
## Supports realistic ricochet mechanics based on caliber data:
## - Ricochet probability depends on impact angle (shallow = more likely)
## - Velocity and damage reduction after ricochet
## - Maximum ricochet count before destruction
## - Random angle deviation for realistic bounce behavior

## Speed of the bullet in pixels per second.
## Default is 2500 for faster projectiles that make combat more challenging.
@export var speed: float = 2500.0

## Maximum lifetime in seconds before auto-destruction.
@export var lifetime: float = 3.0

## Maximum number of trail points to maintain.
## Higher values create longer trails but use more memory.
@export var trail_length: int = 8

## Caliber data resource for ricochet and ballistic properties.
## If not set, default ricochet behavior is used.
@export var caliber_data: Resource = null

## Direction the bullet travels (set by the shooter).
var direction: Vector2 = Vector2.RIGHT

## Instance ID of the node that shot this bullet.
## Used to prevent self-detection (e.g., enemies detecting their own bullets).
var shooter_id: int = -1

## Current damage multiplier (decreases with each ricochet).
var damage_multiplier: float = 1.0

## Timer tracking remaining lifetime.
var _time_alive: float = 0.0

## Reference to the trail Line2D node (if present).
var _trail: Line2D = null

## History of global positions for the trail effect.
var _position_history: Array[Vector2] = []

## Number of ricochets that have occurred.
var _ricochet_count: int = 0

## Default ricochet settings (used when caliber_data is not set).
## -1 means unlimited ricochets.
const DEFAULT_MAX_RICOCHETS: int = -1
const DEFAULT_MAX_RICOCHET_ANGLE: float = 90.0
const DEFAULT_BASE_RICOCHET_PROBABILITY: float = 1.0
const DEFAULT_VELOCITY_RETENTION: float = 0.85
const DEFAULT_RICOCHET_DAMAGE_MULTIPLIER: float = 0.5
const DEFAULT_RICOCHET_ANGLE_DEVIATION: float = 10.0

## Viewport size used for calculating post-ricochet lifetime.
## Bullets disappear after traveling this distance after ricochet.
var _viewport_diagonal: float = 0.0

## Whether this bullet has ricocheted at least once.
var _has_ricocheted: bool = false

## Distance traveled since the last ricochet (for viewport-based lifetime).
var _distance_since_ricochet: float = 0.0

## Position at the moment of the last ricochet.
var _ricochet_position: Vector2 = Vector2.ZERO

## Maximum travel distance after ricochet (based on viewport and ricochet angle).
var _max_post_ricochet_distance: float = 0.0

## Enable/disable debug logging for ricochet calculations.
var _debug_ricochet: bool = false


func _ready() -> void:
	# Connect to collision signals
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

	# Get trail reference if it exists
	_trail = get_node_or_null("Trail")
	if _trail:
		_trail.clear_points()
		# Set trail to use global coordinates (not relative to bullet)
		_trail.top_level = true

	# Load default caliber data if not set
	if caliber_data == null:
		caliber_data = _load_default_caliber_data()

	# Calculate viewport diagonal for post-ricochet lifetime
	_calculate_viewport_diagonal()

	# Set initial rotation based on direction
	_update_rotation()


## Calculates the viewport diagonal distance for post-ricochet lifetime.
func _calculate_viewport_diagonal() -> void:
	var viewport := get_viewport()
	if viewport:
		var size := viewport.get_visible_rect().size
		_viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)
	else:
		# Fallback to a reasonable default (1920x1080 diagonal ~= 2203)
		_viewport_diagonal = 2203.0


## Loads the default 5.45x39mm caliber data.
func _load_default_caliber_data() -> Resource:
	var path := "res://resources/calibers/caliber_545x39.tres"
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Updates the bullet rotation to match its travel direction.
func _update_rotation() -> void:
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	# Calculate movement this frame
	var movement := direction * speed * delta

	# Move in the set direction
	position += movement

	# Track distance traveled since last ricochet (for viewport-based lifetime)
	if _has_ricocheted:
		_distance_since_ricochet += movement.length()
		# Destroy bullet if it has traveled more than the viewport-based max distance
		if _distance_since_ricochet >= _max_post_ricochet_distance:
			if _debug_ricochet:
				print("[Bullet] Post-ricochet distance exceeded: ", _distance_since_ricochet, " >= ", _max_post_ricochet_distance)
			queue_free()
			return

	# Update trail effect
	_update_trail()

	# Track lifetime and auto-destroy if exceeded
	_time_alive += delta
	if _time_alive >= lifetime:
		queue_free()


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
	# Check if this is the shooter - don't collide with own body
	if shooter_id == body.get_instance_id():
		return  # Pass through the shooter

	# Check if this is a dead enemy - bullets should pass through dead entities
	# This handles the CharacterBody2D collision (separate from HitArea collision)
	if body.has_method("is_alive") and not body.is_alive():
		return  # Pass through dead entities

	# Hit a static body (wall or obstacle) or alive enemy body
	# Try to ricochet off static bodies (walls/obstacles)
	if body is StaticBody2D or body is TileMap:
		if _try_ricochet(body):
			return  # Bullet ricocheted, don't destroy

	# Spawn wall dust effect
	_spawn_wall_hit_effect(body)

	# Play wall impact sound and destroy bullet
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		audio_manager.play_bullet_wall_hit(global_position)
	queue_free()


func _on_area_entered(area: Area2D) -> void:
	# Hit another area (like a target or hit detection area)
	# Only destroy bullet if the area has on_hit method (actual hit targets)
	# This allows bullets to pass through detection-only areas like ThreatSpheres
	if area.has_method("on_hit"):
		# Check if this is a HitArea - if so, check against parent's instance ID
		# This prevents the shooter from damaging themselves with direct shots
		# BUT ricocheted bullets CAN damage the shooter (realistic self-damage)
		var parent: Node = area.get_parent()
		if parent and shooter_id == parent.get_instance_id() and not _has_ricocheted:
			return  # Don't hit the shooter with direct shots

		# Check if the parent is dead - bullets should pass through dead entities
		# This is a fallback check in case the collision shape/layer disabling
		# doesn't take effect immediately (see Godot issues #62506, #100687)
		if parent and parent.has_method("is_alive") and not parent.is_alive():
			return  # Pass through dead entities

		# Call on_hit with extended parameters if supported, otherwise use basic call
		if area.has_method("on_hit_with_info"):
			area.on_hit_with_info(direction, caliber_data)
		else:
			area.on_hit()

		# Trigger hit effects if this is a player bullet hitting an enemy
		if _is_player_bullet():
			_trigger_player_hit_effects()

		queue_free()


## Attempts to ricochet the bullet off a surface.
## Returns true if ricochet occurred, false if bullet should be destroyed.
## @param body: The body the bullet collided with.
func _try_ricochet(body: Node2D) -> bool:
	# Check if we've exceeded maximum ricochets (-1 = unlimited)
	var max_ricochets := _get_max_ricochets()
	if max_ricochets >= 0 and _ricochet_count >= max_ricochets:
		if _debug_ricochet:
			print("[Bullet] Max ricochets reached: ", _ricochet_count)
		return false

	# Get the surface normal at the collision point
	var surface_normal := _get_surface_normal(body)
	if surface_normal == Vector2.ZERO:
		if _debug_ricochet:
			print("[Bullet] Could not determine surface normal")
		return false

	# Calculate impact angle (angle between bullet direction and surface)
	# 0 degrees = parallel to surface (grazing shot)
	# 90 degrees = perpendicular to surface (direct hit)
	var impact_angle_rad := _calculate_impact_angle(surface_normal)
	var impact_angle_deg := rad_to_deg(impact_angle_rad)

	if _debug_ricochet:
		print("[Bullet] Impact angle: ", impact_angle_deg, " degrees")

	# Calculate ricochet probability based on impact angle
	var ricochet_probability := _calculate_ricochet_probability(impact_angle_deg)

	if _debug_ricochet:
		print("[Bullet] Ricochet probability: ", ricochet_probability * 100, "%")

	# Random roll to determine if ricochet occurs
	if randf() > ricochet_probability:
		if _debug_ricochet:
			print("[Bullet] Ricochet failed (random)")
		return false

	# Ricochet successful - calculate new direction
	_perform_ricochet(surface_normal)
	return true


## Gets the maximum number of ricochets allowed.
func _get_max_ricochets() -> int:
	if caliber_data and caliber_data.has_method("get") and "max_ricochets" in caliber_data:
		return caliber_data.max_ricochets
	return DEFAULT_MAX_RICOCHETS


## Gets the surface normal at the collision point.
## Uses raycasting to determine the exact collision point and normal.
func _get_surface_normal(body: Node2D) -> Vector2:
	# Create a raycast to find the exact collision point
	var space_state := get_world_2d().direct_space_state

	# Cast ray from slightly behind the bullet to current position
	var ray_start := global_position - direction * 50.0
	var ray_end := global_position + direction * 10.0

	var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end)
	query.collision_mask = collision_mask
	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		# Fallback: estimate normal based on bullet direction
		# Assume the surface is perpendicular to the approach
		return -direction.normalized()

	return result.normal


## Calculates the impact angle between bullet direction and surface.
## This returns the GRAZING angle (angle from the surface plane).
## Returns angle in radians (0 = grazing/parallel to surface, PI/2 = perpendicular/head-on).
func _calculate_impact_angle(surface_normal: Vector2) -> float:
	# We want the GRAZING angle (angle from the surface, not from the normal).
	# The grazing angle is 90° - (angle from normal).
	#
	# Using dot product with the normal:
	# dot(direction, -normal) = cos(angle_from_normal)
	#
	# The grazing angle = 90° - angle_from_normal
	# So: grazing_angle = asin(|dot(direction, normal)|)
	#
	# For grazing shots (parallel to surface): direction ⊥ normal, dot ≈ 0, grazing_angle ≈ 0°
	# For direct hits (perpendicular to surface): direction ∥ -normal, dot ≈ 1, grazing_angle ≈ 90°

	var dot := absf(direction.normalized().dot(surface_normal.normalized()))
	# Clamp to avoid numerical issues with asin
	dot = clampf(dot, 0.0, 1.0)
	return asin(dot)


## Calculates the ricochet probability based on impact angle.
## Uses a custom curve designed for realistic 5.45x39mm behavior:
## - 0-15°: ~100% (grazing shots always ricochet)
## - 45°: ~80% (moderate angles have good ricochet chance)
## - 90°: ~10% (perpendicular shots rarely ricochet)
func _calculate_ricochet_probability(impact_angle_deg: float) -> float:
	var max_angle: float
	var base_probability: float

	if caliber_data:
		max_angle = caliber_data.max_ricochet_angle if "max_ricochet_angle" in caliber_data else DEFAULT_MAX_RICOCHET_ANGLE
		base_probability = caliber_data.base_ricochet_probability if "base_ricochet_probability" in caliber_data else DEFAULT_BASE_RICOCHET_PROBABILITY
	else:
		max_angle = DEFAULT_MAX_RICOCHET_ANGLE
		base_probability = DEFAULT_BASE_RICOCHET_PROBABILITY

	# No ricochet if angle exceeds maximum
	if impact_angle_deg > max_angle:
		return 0.0

	# Custom curve for realistic ricochet probability:
	# probability = base * (0.9 * (1 - (angle/90)^2.17) + 0.1)
	# This gives approximately:
	# - 0°: 100%, 15°: 98%, 45°: 80%, 90°: 10%
	var normalized_angle := impact_angle_deg / 90.0
	# Power of 2.17 creates a curve matching real-world ballistics
	var power_factor := pow(normalized_angle, 2.17)
	var angle_factor := (1.0 - power_factor) * 0.9 + 0.1
	return base_probability * angle_factor


## Performs the ricochet: updates direction, speed, and damage.
## Also calculates the post-ricochet maximum travel distance based on viewport and angle.
func _perform_ricochet(surface_normal: Vector2) -> void:
	_ricochet_count += 1

	# Calculate the impact angle for determining post-ricochet distance
	var impact_angle_rad := _calculate_impact_angle(surface_normal)
	var impact_angle_deg := rad_to_deg(impact_angle_rad)

	# Calculate reflected direction
	# reflection = direction - 2 * dot(direction, normal) * normal
	var reflected := direction - 2.0 * direction.dot(surface_normal) * surface_normal
	reflected = reflected.normalized()

	# Add random deviation for realism
	var deviation := _get_ricochet_deviation()
	reflected = reflected.rotated(deviation)

	# Update direction
	direction = reflected
	_update_rotation()

	# Reduce velocity
	var velocity_retention := _get_velocity_retention()
	speed *= velocity_retention

	# Reduce damage multiplier
	var damage_mult := _get_ricochet_damage_multiplier()
	damage_multiplier *= damage_mult

	# Move bullet slightly away from surface to prevent immediate re-collision
	global_position += direction * 5.0

	# Mark bullet as having ricocheted and set viewport-based lifetime
	_has_ricocheted = true
	_ricochet_position = global_position
	_distance_since_ricochet = 0.0

	# Calculate max post-ricochet distance based on viewport and ricochet angle
	# Shallow angles (grazing) -> bullet travels longer after ricochet
	# Steeper angles -> bullet travels shorter distance (more energy lost)
	# Formula: max_distance = viewport_diagonal * (1 - angle/90)
	# At 0° (grazing): full viewport diagonal
	# At 90° (perpendicular): 0 distance (but this wouldn't ricochet anyway)
	var angle_factor := 1.0 - (impact_angle_deg / 90.0)
	angle_factor = clampf(angle_factor, 0.1, 1.0)  # Minimum 10% to prevent instant destruction
	_max_post_ricochet_distance = _viewport_diagonal * angle_factor

	# Clear trail history to avoid visual artifacts
	_position_history.clear()

	# Play ricochet sound
	_play_ricochet_sound()

	if _debug_ricochet:
		print("[Bullet] Ricochet #", _ricochet_count, " - New speed: ", speed, ", Damage mult: ", damage_multiplier, ", Max post-ricochet distance: ", _max_post_ricochet_distance)


## Gets the velocity retention factor for ricochet.
func _get_velocity_retention() -> float:
	if caliber_data and "velocity_retention" in caliber_data:
		return caliber_data.velocity_retention
	return DEFAULT_VELOCITY_RETENTION


## Gets the damage multiplier for ricochet.
func _get_ricochet_damage_multiplier() -> float:
	if caliber_data and "ricochet_damage_multiplier" in caliber_data:
		return caliber_data.ricochet_damage_multiplier
	return DEFAULT_RICOCHET_DAMAGE_MULTIPLIER


## Gets a random deviation angle for ricochet direction.
func _get_ricochet_deviation() -> float:
	var deviation_deg: float
	if caliber_data:
		if caliber_data.has_method("get_random_ricochet_deviation"):
			return caliber_data.get_random_ricochet_deviation()
		deviation_deg = caliber_data.ricochet_angle_deviation if "ricochet_angle_deviation" in caliber_data else DEFAULT_RICOCHET_ANGLE_DEVIATION
	else:
		deviation_deg = DEFAULT_RICOCHET_ANGLE_DEVIATION

	var deviation_rad := deg_to_rad(deviation_deg)
	return randf_range(-deviation_rad, deviation_rad)


## Plays the ricochet sound effect.
func _play_ricochet_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_ricochet"):
		audio_manager.play_bullet_ricochet(global_position)
	elif audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		# Fallback to wall hit sound if ricochet sound not available
		audio_manager.play_bullet_wall_hit(global_position)


## Checks if this bullet was fired by the player.
func _is_player_bullet() -> bool:
	if shooter_id == -1:
		return false

	var shooter: Object = instance_from_id(shooter_id)
	if shooter == null:
		return false

	# Check if the shooter is a player by script path
	var script: Script = shooter.get_script()
	if script and script.resource_path.contains("player"):
		return true

	return false


## Triggers hit effects via the HitEffectsManager autoload.
## Effects: time slowdown to 0.9 for 3 seconds, saturation boost for 400ms.
func _trigger_player_hit_effects() -> void:
	var hit_effects_manager: Node = get_node_or_null("/root/HitEffectsManager")
	if hit_effects_manager and hit_effects_manager.has_method("on_player_hit_enemy"):
		hit_effects_manager.on_player_hit_enemy()


## Returns the current ricochet count.
func get_ricochet_count() -> int:
	return _ricochet_count


## Returns the current damage multiplier (accounting for ricochets).
func get_damage_multiplier() -> float:
	return damage_multiplier


## Returns whether ricochet is enabled for this bullet.
func can_ricochet() -> bool:
	if caliber_data and "can_ricochet" in caliber_data:
		return caliber_data.can_ricochet
	return true  # Default to enabled


## Spawns dust/debris particles when bullet hits a wall or static body.
## @param body: The body that was hit (used to get surface normal).
func _spawn_wall_hit_effect(body: Node2D) -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager == null or not impact_manager.has_method("spawn_dust_effect"):
		return

	# Get surface normal for particle direction
	var surface_normal := _get_surface_normal(body)

	# Spawn dust effect at hit position
	impact_manager.spawn_dust_effect(global_position, surface_normal, caliber_data)
