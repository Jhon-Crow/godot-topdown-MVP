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

## Whether the bullet is currently penetrating through a wall.
var _is_penetrating: bool = false

## Distance traveled while penetrating through walls.
var _penetration_distance_traveled: float = 0.0

## Entry point into the current obstacle being penetrated.
var _penetration_entry_point: Vector2 = Vector2.ZERO

## The body currently being penetrated (for tracking exit).
var _penetrating_body: Node2D = null

## Whether the bullet has penetrated at least one wall (for damage reduction).
var _has_penetrated: bool = false

## Enable/disable debug logging for penetration calculations.
var _debug_penetration: bool = true

## Default penetration settings (used when caliber_data is not set).
const DEFAULT_CAN_PENETRATE: bool = true
const DEFAULT_MAX_PENETRATION_DISTANCE: float = 48.0
const DEFAULT_POST_PENETRATION_DAMAGE_MULTIPLIER: float = 0.9

## Distance-based penetration chance settings.
## At point-blank (0 distance): 100% penetration, ignores ricochet
## At 40% of viewport: normal ricochet rules apply (if not ricochet, then penetrate)
## At viewport distance: max 30% penetration chance for 5.45
const POINT_BLANK_DISTANCE_RATIO: float = 0.0  # 0% of viewport = point blank
const RICOCHET_RULES_DISTANCE_RATIO: float = 0.4  # 40% of viewport = ricochet rules apply
const MAX_PENETRATION_CHANCE_AT_DISTANCE: float = 0.3  # 30% max at viewport distance

## Shooter's position at the time of firing (for distance-based penetration).
var shooter_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Connect to collision signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	area_entered.connect(_on_area_entered)

	# Get trail reference if it exists
	_trail = get_node_or_null("Trail")
	if _trail:
		_trail.clear_points()
		# Set trail to use global coordinates (not relative to bullet)
		_trail.top_level = true
		# Reset position to origin so points added are truly global
		# (when top_level becomes true, the Line2D's position becomes its global position,
		# so we need to reset it to (0,0) for added points to be at their true global positions)
		_trail.position = Vector2.ZERO

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


## Logs a penetration-related message to both console and file logger.
## @param message: The message to log.
func _log_penetration(message: String) -> void:
	if not _debug_penetration:
		return
	var full_message := "[Bullet] " + message
	print(full_message)
	# Also log to FileLogger if available
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info(full_message)


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

	# Track penetration distance while inside a wall
	if _is_penetrating:
		_penetration_distance_traveled += movement.length()
		var max_pen_distance := _get_max_penetration_distance()

		# Check if we've exceeded max penetration distance
		if max_pen_distance > 0 and _penetration_distance_traveled >= max_pen_distance:
			_log_penetration("Max penetration distance exceeded: %s >= %s" % [_penetration_distance_traveled, max_pen_distance])
			# Bullet stopped inside the wall - destroy it
			# Visual effects disabled as per user request
			queue_free()
			return

		# Check if we've exited the obstacle (raycast forward to see if still inside)
		# Note: body_exited signal also triggers _exit_penetration for reliability
		if not _is_still_inside_obstacle():
			_exit_penetration()

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

	# If we're currently penetrating the same body, ignore re-entry
	if _is_penetrating and _penetrating_body == body:
		return

	# Check if bullet is inside an existing penetration hole - pass through without re-triggering
	if _is_inside_penetration_hole():
		_log_penetration("Inside existing penetration hole, passing through")
		return

	# Hit a static body (wall or obstacle) or alive enemy body
	# Try to ricochet off static bodies (walls/obstacles)
	if body is StaticBody2D or body is TileMap:
		# Always spawn dust effect when hitting walls, regardless of ricochet
		_spawn_wall_hit_effect(body)

		# Calculate distance from shooter to determine penetration behavior
		var distance_to_wall := _get_distance_to_shooter()
		var distance_ratio := distance_to_wall / _viewport_diagonal if _viewport_diagonal > 0 else 1.0

		_log_penetration("Distance to wall: %s (%s%% of viewport)" % [distance_to_wall, distance_ratio * 100])

		# Point-blank shots (very close to shooter): 100% penetration, ignore ricochet
		if distance_ratio <= POINT_BLANK_DISTANCE_RATIO + 0.05:  # ~5% tolerance for "point blank"
			_log_penetration("Point-blank shot - 100% penetration, ignoring ricochet")
			if _try_penetration(body):
				return  # Bullet is penetrating
		# At 40% or less of viewport: normal ricochet rules apply
		elif distance_ratio <= RICOCHET_RULES_DISTANCE_RATIO:
			_log_penetration("Within ricochet range - trying ricochet first")
			# First try ricochet
			if _try_ricochet(body):
				return  # Bullet ricocheted, don't destroy
			# Ricochet failed - try penetration (if not ricochet, then penetrate)
			if _try_penetration(body):
				return  # Bullet is penetrating, don't destroy
		# Beyond 40% of viewport: distance-based penetration chance
		else:
			# First try ricochet (shallow angles still ricochet)
			if _try_ricochet(body):
				return  # Bullet ricocheted, don't destroy

			# Calculate penetration chance based on distance
			# At 40% distance: 100% chance (if ricochet failed)
			# At 100% (viewport) distance: 30% chance
			var penetration_chance := _calculate_distance_penetration_chance(distance_ratio)

			_log_penetration("Distance-based penetration chance: %s%%" % [penetration_chance * 100])

			# Roll for penetration
			if randf() <= penetration_chance:
				if _try_penetration(body):
					return  # Bullet is penetrating
			else:
				_log_penetration("Penetration failed (distance roll)")

	# Play wall impact sound and destroy bullet
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		audio_manager.play_bullet_wall_hit(global_position)
	queue_free()


## Called when the bullet exits a body (wall).
## Used for detecting penetration exit via the physics system.
func _on_body_exited(body: Node2D) -> void:
	# Only process if we're currently penetrating this specific body
	if not _is_penetrating or _penetrating_body != body:
		return

	# Log exit detection
	_log_penetration("Body exited signal received for penetrating body")

	# Call exit penetration
	_exit_penetration()


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


# ============================================================================
# Distance-Based Penetration Helpers
# ============================================================================


## Gets the distance from the current bullet position to the shooter's original position.
func _get_distance_to_shooter() -> float:
	_log_penetration("_get_distance_to_shooter: shooter_position=%s, shooter_id=%s, bullet_pos=%s" % [shooter_position, shooter_id, global_position])

	if shooter_position == Vector2.ZERO:
		# Fallback: use shooter instance position if available
		if shooter_id != -1:
			var shooter: Object = instance_from_id(shooter_id)
			if shooter != null and shooter is Node2D:
				var dist := global_position.distance_to((shooter as Node2D).global_position)
				_log_penetration("Using shooter_id fallback, distance=%s" % dist)
				return dist
		# Unable to determine shooter position - assume close range
		_log_penetration("WARNING: Unable to determine shooter position, defaulting to bullet position distance from origin")

	var dist := global_position.distance_to(shooter_position)
	_log_penetration("Using shooter_position, distance=%s" % dist)
	return dist


## Calculates the penetration chance based on distance from shooter.
## @param distance_ratio: Distance as a ratio of viewport diagonal (0.0 to 1.0+).
## @return: Penetration chance (0.0 to 1.0).
func _calculate_distance_penetration_chance(distance_ratio: float) -> float:
	# At 40% (RICOCHET_RULES_DISTANCE_RATIO): 100% penetration chance
	# At 100% (viewport diagonal): MAX_PENETRATION_CHANCE_AT_DISTANCE (30%)
	# Beyond 100%: continues to decrease linearly

	if distance_ratio <= RICOCHET_RULES_DISTANCE_RATIO:
		return 1.0  # Full penetration chance within ricochet rules range

	# Linear interpolation from 100% at 40% to 30% at 100%
	# penetration_chance = 1.0 - (distance_ratio - 0.4) / 0.6 * 0.7
	var range_start := RICOCHET_RULES_DISTANCE_RATIO  # 0.4
	var range_end := 1.0  # viewport distance
	var range_span := range_end - range_start  # 0.6

	var position_in_range := (distance_ratio - range_start) / range_span
	position_in_range = clampf(position_in_range, 0.0, 1.0)

	# Interpolate from 1.0 to MAX_PENETRATION_CHANCE_AT_DISTANCE
	var penetration_chance := lerpf(1.0, MAX_PENETRATION_CHANCE_AT_DISTANCE, position_in_range)

	# Beyond viewport distance, continue decreasing (but clamp to minimum of 5%)
	if distance_ratio > 1.0:
		var beyond_viewport := distance_ratio - 1.0
		penetration_chance = maxf(MAX_PENETRATION_CHANCE_AT_DISTANCE - beyond_viewport * 0.2, 0.05)

	return penetration_chance


## Checks if the bullet is currently inside an existing penetration hole area.
## If so, the bullet should pass through without triggering new penetration.
func _is_inside_penetration_hole() -> bool:
	# Get overlapping areas
	var overlapping_areas := get_overlapping_areas()
	for area in overlapping_areas:
		# Check if this is a penetration hole (by script or name)
		if area.get_script() != null:
			var script_path: String = area.get_script().resource_path
			if script_path.contains("penetration_hole"):
				return true
		# Also check by node name as fallback
		if area.name.contains("PenetrationHole"):
			return true
	return false


# ============================================================================
# Wall Penetration System
# ============================================================================


## Attempts to penetrate through a wall when ricochet fails.
## Returns true if penetration started successfully.
## @param body: The static body (wall) to penetrate.
func _try_penetration(body: Node2D) -> bool:
	# Check if caliber allows penetration
	if not _can_penetrate():
		_log_penetration("Caliber cannot penetrate walls")
		return false

	# Don't start a new penetration if already penetrating
	if _is_penetrating:
		_log_penetration("Already penetrating, cannot start new penetration")
		return false

	_log_penetration("Starting wall penetration at %s" % global_position)

	# Mark as penetrating
	_is_penetrating = true
	_penetrating_body = body
	_penetration_entry_point = global_position
	_penetration_distance_traveled = 0.0

	# Spawn entry hole effect
	_spawn_penetration_hole_effect(body, global_position, true)

	# Move bullet slightly forward to avoid immediate re-collision
	global_position += direction * 5.0

	return true


## Checks if the bullet can penetrate walls based on caliber data.
func _can_penetrate() -> bool:
	if caliber_data and caliber_data.has_method("can_penetrate_walls"):
		return caliber_data.can_penetrate_walls()
	if caliber_data and "can_penetrate" in caliber_data:
		return caliber_data.can_penetrate
	return DEFAULT_CAN_PENETRATE


## Gets the maximum penetration distance from caliber data.
func _get_max_penetration_distance() -> float:
	if caliber_data and caliber_data.has_method("get_max_penetration_distance"):
		return caliber_data.get_max_penetration_distance()
	if caliber_data and "max_penetration_distance" in caliber_data:
		return caliber_data.max_penetration_distance
	return DEFAULT_MAX_PENETRATION_DISTANCE


## Gets the post-penetration damage multiplier from caliber data.
func _get_post_penetration_damage_multiplier() -> float:
	if caliber_data and "post_penetration_damage_multiplier" in caliber_data:
		return caliber_data.post_penetration_damage_multiplier
	return DEFAULT_POST_PENETRATION_DAMAGE_MULTIPLIER


## Checks if the bullet is still inside an obstacle using raycasting.
## Returns true if still inside, false if exited.
## Uses longer raycasts to account for high bullet speeds (2500 px/s = ~41 pixels/frame at 60 FPS).
func _is_still_inside_obstacle() -> bool:
	if _penetrating_body == null or not is_instance_valid(_penetrating_body):
		return false

	var space_state := get_world_2d().direct_space_state

	# Use longer raycasts to account for bullet speed
	# Cast forward ~50 pixels (slightly more than max penetration of 48)
	var ray_length := 50.0
	var ray_start := global_position
	var ray_end := global_position + direction * ray_length

	var query := PhysicsRayQueryParameters2D.create(ray_start, ray_end)
	query.collision_mask = collision_mask
	query.exclude = [self]

	var result := space_state.intersect_ray(query)

	# If we hit the same body in front, we're still inside
	if not result.is_empty() and result.collider == _penetrating_body:
		_log_penetration("Raycast forward hit penetrating body at distance %s" % ray_start.distance_to(result.position))
		return true

	# Also check backwards to see if we're still overlapping
	ray_end = global_position - direction * ray_length
	query = PhysicsRayQueryParameters2D.create(ray_start, ray_end)
	query.collision_mask = collision_mask
	query.exclude = [self]

	result = space_state.intersect_ray(query)
	if not result.is_empty() and result.collider == _penetrating_body:
		_log_penetration("Raycast backward hit penetrating body at distance %s" % ray_start.distance_to(result.position))
		return true

	_log_penetration("No longer inside obstacle - raycasts found no collision with penetrating body")
	return false


## Called when the bullet exits a penetrated wall.
func _exit_penetration() -> void:
	# Prevent double-calling (can happen from both body_exited and raycast check)
	if not _is_penetrating:
		return

	var exit_point := global_position

	_log_penetration("Exiting penetration at %s after traveling %s pixels through wall" % [exit_point, _penetration_distance_traveled])

	# Visual effects disabled as per user request
	# The entry/exit positions couldn't be properly anchored to wall surfaces

	# Apply damage reduction after penetration
	if not _has_penetrated:
		damage_multiplier *= _get_post_penetration_damage_multiplier()
		_has_penetrated = true

		_log_penetration("Damage multiplier after penetration: %s" % damage_multiplier)

	# Play penetration exit sound (use wall hit sound for now)
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_wall_hit"):
		audio_manager.play_bullet_wall_hit(exit_point)

	# Reset penetration state
	_is_penetrating = false
	_penetrating_body = null
	_penetration_distance_traveled = 0.0

	# Destroy bullet after successful penetration
	# Bullets don't continue flying after penetrating a wall
	queue_free()


## Spawns a visual hole effect at penetration entry or exit point.
## DISABLED: As per user request, all penetration visual effects are removed.
## The penetration functionality remains (bullet passes through thin walls),
## but no visual effects (dust, trails, holes) are spawned.
## @param body: The wall being penetrated.
## @param pos: Position of the hole.
## @param is_entry: True for entry hole, false for exit hole.
func _spawn_penetration_hole_effect(_body: Node2D, _pos: Vector2, _is_entry: bool) -> void:
	# All visual effects disabled as per user request
	# The entry/exit positions couldn't be properly anchored to wall surfaces
	pass


## Spawns a collision hole that creates an actual gap in wall collision.
## This allows other bullets and vision to pass through the hole.
## @param entry_point: Where the bullet entered the wall.
## @param exit_point: Where the bullet exited the wall.
func _spawn_collision_hole(entry_point: Vector2, exit_point: Vector2) -> void:
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager == null:
		return

	if impact_manager.has_method("spawn_collision_hole"):
		impact_manager.spawn_collision_hole(entry_point, exit_point, direction, caliber_data)
		_log_penetration("Collision hole spawned from %s to %s" % [entry_point, exit_point])


## Returns whether the bullet has penetrated at least one wall.
func has_penetrated() -> bool:
	return _has_penetrated


## Returns whether the bullet is currently penetrating a wall.
func is_penetrating() -> bool:
	return _is_penetrating


## Returns the distance traveled through walls while penetrating.
func get_penetration_distance() -> float:
	return _penetration_distance_traveled
