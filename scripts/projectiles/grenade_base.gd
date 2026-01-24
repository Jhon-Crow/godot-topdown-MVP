extends RigidBody2D
class_name GrenadeBase
## Abstract base class for all grenades.
##
## Handles common grenade mechanics:
## - Timer-based detonation (4 seconds)
## - Physics-based throwing with drag distance/direction determining velocity
## - Explosion sound audible at 2 viewport distance
## - Max throw distance = viewport length
## - Min throw distance = at player feet (short drag)
##
## Subclasses should override:
## - _on_explode(): Define explosion effects
## - _get_effect_radius(): Define effect area

## Time until explosion in seconds (starts when timer is activated).
@export var fuse_time: float = 4.0

## Maximum throw speed in pixels per second.
## At max speed with default friction (300), grenade travels ~1200px (viewport width).
## Formula: max_distance = max_throw_speed² / (2 × ground_friction)
@export var max_throw_speed: float = 850.0

## Minimum throw speed for a minimal drag (gentle lob).
@export var min_throw_speed: float = 100.0

## Drag multiplier to convert drag distance to throw speed (DEPRECATED - kept for compatibility).
## At viewport width (~1280px) drag, reaches near max speed.
## At ~100px drag (short swing), produces gentle throw.
@export var drag_to_speed_multiplier: float = 2.0

## Mass of the grenade in kg. Affects how mouse velocity translates to throw velocity.
## Heavier grenades require more "swing momentum" to achieve full velocity transfer.
## Light grenade (0.2kg) = quick flick throw, Heavy grenade (0.6kg) = needs full swing.
@export var grenade_mass: float = 0.4

## Multiplier to convert mouse velocity (pixels/second) to throw velocity.
## This is the base ratio before mass adjustment.
## Lower values = require faster mouse movement for maximum throw (easier to control strength).
## At 0.5: max throw requires ~2700 px/s mouse velocity for 1352 px/s throw speed.
## This allows for a wider range of controllable throw distances.
@export var mouse_velocity_to_throw_multiplier: float = 0.5

## Minimum swing distance (in pixels) required for full velocity transfer at grenade's mass.
## For a 0.4kg grenade, need ~80px of mouse movement to transfer full velocity.
## Reduced from 200px to allow quick flicks to throw reasonably far.
## Formula: actual_min_swing = min_swing_distance * (grenade_mass / 0.4)
@export var min_swing_distance: float = 80.0

## Minimum transfer efficiency (0.0 to 1.0) for any intentional throw.
## This ensures quick flicks with high velocity still result in a reasonable throw distance.
## Set to 0.35 to guarantee at least 35% velocity transfer for any swing > 10px.
@export var min_transfer_efficiency: float = 0.35

## Friction/damping applied to slow the grenade.
## Higher friction = shorter throw distance for same speed.
## Formula: max_distance = max_throw_speed² / (2 × ground_friction)
## Default 300 with 850 speed → max distance ~1200px (viewport width).
@export var ground_friction: float = 300.0

## Bounce coefficient when hitting walls (0.0 = no bounce, 1.0 = full bounce).
@export var wall_bounce: float = 0.4

## Sound range multiplier (2 = audible at 2 viewport distance).
@export var sound_range_multiplier: float = 2.0

## Minimum velocity to trigger landing sound (prevents multiple triggers).
@export var landing_velocity_threshold: float = 50.0

## Whether the grenade timer has been activated.
var _timer_active: bool = false

## Time remaining until explosion.
var _time_remaining: float = 0.0

## Whether the grenade has exploded.
var _has_exploded: bool = false

## Reference to the sprite for visual feedback.
@onready var _sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else null

## Blink timer for visual feedback when about to explode.
var _blink_timer: float = 0.0

## Blink interval - gets faster as explosion approaches.
var _blink_interval: float = 0.5

## Track if landing sound has been played (grenade has come to rest).
var _has_landed: bool = false

## Track if activation sound has been played.
var _activation_sound_played: bool = false

## Track previous velocity for landing detection.
var _previous_velocity: Vector2 = Vector2.ZERO

## Signal emitted when the grenade explodes.
signal exploded(position: Vector2, grenade: GrenadeBase)


func _ready() -> void:
	# Set up collision
	collision_layer = 32  # Layer 6 (custom for grenades)
	collision_mask = 4 | 2  # obstacles + enemies (NOT player, to avoid collision when throwing)

	# Enable contact monitoring for body_entered signal (required for collision detection)
	# Without this, body_entered signal will never fire!
	contact_monitor = true
	max_contacts_reported = 4  # Track up to 4 simultaneous contacts

	# Enable Continuous Collision Detection to prevent tunneling through walls
	# at high velocities (grenades can reach ~1200 px/s, which is ~20px per frame at 60 FPS)
	# CCD_MODE_CAST_RAY (1) is reliable and recommended for fast-moving objects
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	FileLogger.info("[GrenadeBase] CCD enabled (mode: CAST_RAY) to prevent wall tunneling")

	# Set up physics
	gravity_scale = 0.0  # Top-down, no gravity
	linear_damp = 1.0  # Reduced for easier rolling

	# Set up physics material for wall bouncing
	var physics_material := PhysicsMaterial.new()
	physics_material.bounce = wall_bounce
	physics_material.friction = 0.3  # Low friction for rolling
	physics_material_override = physics_material

	# IMPORTANT: Start frozen to prevent physics interference while grenade follows player
	# This fixes the bug where grenade was thrown from activation position instead of current position
	# The physics engine can overwrite manual position updates on active RigidBody2D nodes
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

	# Connect to body entered for bounce effects
	body_entered.connect(_on_body_entered)

	FileLogger.info("[GrenadeBase] Grenade created at %s (frozen)" % str(global_position))


func _physics_process(delta: float) -> void:
	if _has_exploded:
		return

	# Apply ground friction to slow down
	if linear_velocity.length() > 0:
		var friction_force := linear_velocity.normalized() * ground_friction * delta
		if friction_force.length() > linear_velocity.length():
			linear_velocity = Vector2.ZERO
		else:
			linear_velocity -= friction_force

	# Check for landing (grenade comes to near-stop after being thrown)
	if not _has_landed and _timer_active:
		var current_speed := linear_velocity.length()
		var previous_speed := _previous_velocity.length()
		# Grenade has landed when it was moving fast and now nearly stopped
		if previous_speed > landing_velocity_threshold and current_speed < landing_velocity_threshold:
			_on_grenade_landed()
	_previous_velocity = linear_velocity

	# Update timer if active
	if _timer_active:
		_time_remaining -= delta
		_update_blink_effect(delta)

		if _time_remaining <= 0:
			_explode()


## Activate the grenade timer. Call this when the player starts the throwing motion.
func activate_timer() -> void:
	if _timer_active:
		FileLogger.info("[GrenadeBase] Timer already active")
		return
	_timer_active = true
	_time_remaining = fuse_time

	# Play activation sound (pin pull)
	if not _activation_sound_played:
		_activation_sound_played = true
		_play_activation_sound()

	FileLogger.info("[GrenadeBase] Timer activated! %.1f seconds until explosion" % fuse_time)


## Throw the grenade using realistic velocity-based physics.
## The throw velocity is derived from mouse velocity at release, adjusted by grenade mass.
## Quick flicks (high velocity, short swing) now throw reasonably far thanks to minimum transfer.
## @param mouse_velocity: The mouse velocity vector at moment of release (pixels/second).
## @param swing_distance: Total distance the mouse traveled during the swing (pixels).
func throw_grenade_velocity_based(mouse_velocity: Vector2, swing_distance: float) -> void:
	# Unfreeze the grenade so physics can take over
	freeze = false

	# Calculate mass-adjusted minimum swing distance
	# Heavier grenades need more swing to transfer full velocity
	var mass_ratio := grenade_mass / 0.4  # Normalized to "standard" 0.4kg grenade
	var required_swing := min_swing_distance * mass_ratio

	# Calculate velocity transfer efficiency with minimum guarantee for quick flicks
	# FIX for issue #281: Short fast mouse movements now get reasonable transfer
	# The swing-based transfer scales from 0 to (1 - min_transfer) based on swing distance
	# The minimum transfer (0.35 default) ensures quick flicks still throw reasonably far
	var swing_transfer := clampf(swing_distance / required_swing, 0.0, 1.0 - min_transfer_efficiency)
	var transfer_efficiency := min_transfer_efficiency + swing_transfer
	# Ensure we don't exceed 1.0 (full transfer at required_swing or beyond)
	transfer_efficiency = clampf(transfer_efficiency, 0.0, 1.0)

	# Convert mouse velocity to throw velocity
	# Base formula: throw_velocity = mouse_velocity * multiplier * transfer_efficiency / mass_ratio
	# Heavier grenades are harder to throw far with same mouse speed
	var base_throw_velocity := mouse_velocity * mouse_velocity_to_throw_multiplier * transfer_efficiency
	var mass_adjusted_velocity := base_throw_velocity / sqrt(mass_ratio)  # sqrt for more natural feel

	# Clamp the final speed
	var throw_speed := clampf(mass_adjusted_velocity.length(), 0.0, max_throw_speed)

	# Set velocity (use original direction if speed is non-zero)
	if throw_speed > 1.0:
		linear_velocity = mass_adjusted_velocity.normalized() * throw_speed
		rotation = linear_velocity.angle()
	else:
		# Mouse wasn't moving - grenade drops at feet
		linear_velocity = Vector2.ZERO

	FileLogger.info("[GrenadeBase] Velocity-based throw! Mouse vel: %s, Swing: %.1f, Transfer: %.2f, Final speed: %.1f" % [
		str(mouse_velocity), swing_distance, transfer_efficiency, throw_speed
	])


## Throw the grenade with explicit direction and speed derived from mouse velocity.
## FIX for issue #313: direction is now mouse velocity direction (how mouse is MOVING).
## @param throw_direction: The normalized direction to throw (mouse velocity direction).
## @param velocity_magnitude: The mouse velocity magnitude at release (pixels/second).
## @param swing_distance: Total distance the mouse traveled during the swing (pixels).
func throw_grenade_with_direction(throw_direction: Vector2, velocity_magnitude: float, swing_distance: float) -> void:
	# Unfreeze the grenade so physics can take over
	freeze = false

	# Calculate mass-adjusted minimum swing distance
	var mass_ratio := grenade_mass / 0.4  # Normalized to "standard" 0.4kg grenade
	var required_swing := min_swing_distance * mass_ratio

	# Calculate velocity transfer efficiency (same formula as throw_grenade_velocity_based)
	var swing_transfer := clampf(swing_distance / required_swing, 0.0, 1.0 - min_transfer_efficiency)
	var transfer_efficiency := min_transfer_efficiency + swing_transfer
	transfer_efficiency = clampf(transfer_efficiency, 0.0, 1.0)

	# Calculate throw speed from velocity magnitude
	var base_speed := velocity_magnitude * mouse_velocity_to_throw_multiplier * transfer_efficiency
	var throw_speed := clampf(base_speed / sqrt(mass_ratio), 0.0, max_throw_speed)

	# Set velocity using the provided direction (mouse velocity direction)
	if throw_speed > 1.0:
		linear_velocity = throw_direction.normalized() * throw_speed
		rotation = throw_direction.angle()
	else:
		linear_velocity = Vector2.ZERO

	FileLogger.info("[GrenadeBase] Mouse velocity direction throw! Dir: %s, Vel mag: %.1f, Swing: %.1f, Transfer: %.2f, Speed: %.1f" % [
		str(throw_direction), velocity_magnitude, swing_distance, transfer_efficiency, throw_speed
	])


## Throw the grenade in a direction with speed based on drag distance (LEGACY method).
## @param direction: Normalized direction to throw.
## @param drag_distance: Distance of the drag in pixels.
func throw_grenade(direction: Vector2, drag_distance: float) -> void:
	# Unfreeze the grenade so physics can take over
	# This must happen before setting velocity, otherwise the velocity won't be applied
	freeze = false

	# Calculate throw speed based on drag distance
	var throw_speed := clampf(
		drag_distance * drag_to_speed_multiplier,
		min_throw_speed,
		max_throw_speed
	)

	# Set velocity
	linear_velocity = direction.normalized() * throw_speed

	# Rotate to face direction
	rotation = direction.angle()

	FileLogger.info("[GrenadeBase] LEGACY throw_grenade() called! Direction: %s, Speed: %.1f (unfrozen)" % [str(direction), throw_speed])
	FileLogger.info("[GrenadeBase] NOTE: Using DRAG-BASED system. If velocity-based is expected, ensure grenade has throw_grenade_velocity_based() method.")


## Get the explosion effect radius. Override in subclasses.
func _get_effect_radius() -> float:
	# Default: small room size (~200 pixels, roughly 1/6 of viewport width)
	return 200.0


## Called when the grenade explodes. Override in subclasses for specific effects.
func _on_explode() -> void:
	# Base implementation does nothing - subclasses define explosion behavior
	pass


## Internal explosion handling.
func _explode() -> void:
	if _has_exploded:
		return
	_has_exploded = true

	FileLogger.info("[GrenadeBase] EXPLODED at %s!" % str(global_position))

	# Play explosion sound
	_play_explosion_sound()

	# Call subclass explosion effect
	_on_explode()

	# Emit signal
	exploded.emit(global_position, self)

	# Destroy grenade after a short delay for effects
	await get_tree().create_timer(0.1).timeout
	queue_free()


## Play explosion sound audible at 2 viewport distance.
func _play_explosion_sound() -> void:
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		# Calculate sound range (2 viewport diagonals)
		var viewport := get_viewport()
		var viewport_diagonal := 1469.0  # Default 1280x720 diagonal
		if viewport:
			var size := viewport.get_visible_rect().size
			viewport_diagonal = sqrt(size.x * size.x + size.y * size.y)

		var sound_range := viewport_diagonal * sound_range_multiplier
		# 1 = EXPLOSION type, 2 = NEUTRAL source
		sound_propagation.emit_sound(1, global_position, 2, self, sound_range)


## Update visual blink effect as explosion approaches.
func _update_blink_effect(delta: float) -> void:
	if not _sprite:
		return

	# Blink faster as time decreases
	if _time_remaining < 1.0:
		_blink_interval = 0.05
	elif _time_remaining < 2.0:
		_blink_interval = 0.15
	elif _time_remaining < 3.0:
		_blink_interval = 0.3
	else:
		_blink_interval = 0.5

	_blink_timer += delta
	if _blink_timer >= _blink_interval:
		_blink_timer = 0.0
		# Toggle visibility or color
		if _sprite.modulate.r > 0.9:
			_sprite.modulate = Color(1.0, 0.3, 0.3, 1.0)  # Red tint
		else:
			_sprite.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal


## Handle collision with bodies (bounce off walls).
func _on_body_entered(body: Node) -> void:
	# Log collision for debugging
	var body_type := "Unknown"
	if body is StaticBody2D:
		body_type = "StaticBody2D"
	elif body is TileMap:
		body_type = "TileMap"
	elif body is CharacterBody2D:
		body_type = "CharacterBody2D"
	elif body is RigidBody2D:
		body_type = "RigidBody2D"

	FileLogger.info("[GrenadeBase] Collision detected with %s (type: %s)" % [body.name, body_type])

	# Play wall collision sound if hitting a wall/obstacle
	if body is StaticBody2D or body is TileMap:
		_play_wall_collision_sound()


## Check if a position is within the grenade's effect radius.
func is_in_effect_radius(pos: Vector2) -> bool:
	return global_position.distance_to(pos) <= _get_effect_radius()


## Get the remaining time until explosion.
func get_time_remaining() -> float:
	return _time_remaining


## Check if the timer is active.
func is_timer_active() -> bool:
	return _timer_active


## Check if the grenade has exploded.
func has_exploded() -> bool:
	return _has_exploded


## Play activation sound (pin pull) when grenade timer is activated.
func _play_activation_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_grenade_activation"):
		audio_manager.play_grenade_activation(global_position)


## Play wall collision sound when grenade hits a wall.
func _play_wall_collision_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_grenade_wall_hit"):
		audio_manager.play_grenade_wall_hit(global_position)


## Called when grenade comes to rest on the ground.
func _on_grenade_landed() -> void:
	_has_landed = true
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_grenade_landing"):
		audio_manager.play_grenade_landing(global_position)
	FileLogger.info("[GrenadeBase] Grenade landed at %s" % str(global_position))
