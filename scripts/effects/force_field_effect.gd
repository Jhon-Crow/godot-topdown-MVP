extends Node2D
## Force field active item effect.
##
## Creates a glowing circular force field around the player that reflects
## all incoming projectiles (bullets, shrapnel, and grenades).
## Frag (offensive) grenades bounce off without detonating on contact.
##
## Activated by pressing Space. 1 charge per fight, lasts 8 seconds.
##
## The force field uses an Area2D to detect incoming projectiles and
## reflects them by reversing their direction relative to the field surface.

## Duration of the force field effect in seconds.
const EFFECT_DURATION: float = 8.0

## Radius of the force field in pixels.
## Large enough to cover the player character and provide a visible barrier.
const FIELD_RADIUS: float = 80.0

## Maximum charges available per fight/level.
const MAX_CHARGES: int = 1

## Whether the force field is currently active (deflecting projectiles).
var _is_active: bool = false

## Remaining duration of the current activation.
var _time_remaining: float = 0.0

## Number of charges remaining.
var _charges_remaining: int = MAX_CHARGES

## Reference to the shield visual sprite (uses shader).
var _shield_sprite: Sprite2D = null

## Reference to the deflection Area2D.
var _deflection_area: Area2D = null

## Reference to the PointLight2D for glow effect.
var _glow_light: PointLight2D = null

## Set of projectile instance IDs already reflected (to prevent double-reflection).
var _reflected_projectiles: Dictionary = {}

## Activation sound path.
const ACTIVATION_SOUND_PATH: String = ""

## Deactivation sound path.
const DEACTIVATION_SOUND_PATH: String = ""


func _ready() -> void:
	# Get child nodes
	_shield_sprite = get_node_or_null("ShieldSprite")
	_deflection_area = get_node_or_null("DeflectionArea")
	_glow_light = get_node_or_null("GlowLight")

	# Connect deflection area signals
	if _deflection_area:
		_deflection_area.area_entered.connect(_on_area_entered)
		_deflection_area.body_entered.connect(_on_body_entered)

	# Set up glow light texture (PointLight2D requires a texture to emit light)
	if _glow_light and _glow_light.texture == null:
		_glow_light.texture = _create_glow_texture()

	# Start hidden (inactive)
	_set_visible(false)

	FileLogger.info("[ForceField] Initialized with %d charges, %.1fs duration, %.0fpx radius" % [
		_charges_remaining, EFFECT_DURATION, FIELD_RADIUS
	])


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	_time_remaining -= delta

	# Update visual pulsing intensity based on remaining time
	if _time_remaining <= 2.0 and _shield_sprite:
		# Flash faster when about to expire (warning)
		var flash_speed: float = 8.0 if _time_remaining <= 1.0 else 4.0
		var flash_alpha: float = 0.5 + sin(Time.get_ticks_msec() * 0.001 * flash_speed) * 0.5
		_shield_sprite.modulate.a = flash_alpha

	if _time_remaining <= 0:
		deactivate()


## Activate the force field. Returns true if activation was successful.
func activate() -> bool:
	if _is_active:
		FileLogger.info("[ForceField] Already active, cannot activate again")
		return false

	if _charges_remaining <= 0:
		FileLogger.info("[ForceField] No charges remaining")
		return false

	_charges_remaining -= 1
	_is_active = true
	_time_remaining = EFFECT_DURATION
	_reflected_projectiles.clear()

	_set_visible(true)

	# Reset sprite alpha for fresh activation
	if _shield_sprite:
		_shield_sprite.modulate.a = 1.0

	# Play activation sound
	_play_activation_sound()

	FileLogger.info("[ForceField] Activated! Charges remaining: %d, Duration: %.1fs" % [
		_charges_remaining, EFFECT_DURATION
	])
	return true


## Deactivate the force field.
func deactivate() -> void:
	if not _is_active:
		return

	_is_active = false
	_time_remaining = 0.0
	_reflected_projectiles.clear()

	_set_visible(false)

	# Play deactivation sound
	_play_deactivation_sound()

	FileLogger.info("[ForceField] Deactivated. Charges remaining: %d" % _charges_remaining)


## Check if the force field is currently active.
func is_active() -> bool:
	return _is_active


## Check if the force field has charges remaining.
func has_charges() -> bool:
	return _charges_remaining > 0


## Get remaining charges.
func get_charges_remaining() -> int:
	return _charges_remaining


## Get remaining duration of current activation.
func get_time_remaining() -> float:
	return _time_remaining


## Set visibility of the force field visual elements.
func _set_visible(visible_state: bool) -> void:
	if _shield_sprite:
		_shield_sprite.visible = visible_state
	if _glow_light:
		_glow_light.visible = visible_state
	if _deflection_area:
		# Enable/disable monitoring to prevent unnecessary collision checks
		_deflection_area.monitoring = visible_state


## Called when a projectile Area2D enters the force field (bullets, shrapnel).
func _on_area_entered(area: Area2D) -> void:
	if not _is_active:
		return

	var area_id := area.get_instance_id()

	# Prevent double-reflection
	if _reflected_projectiles.has(area_id):
		return

	# Check if this is a bullet
	if area.get_script() != null:
		var script_path: String = area.get_script().resource_path
		if script_path.contains("bullet") or script_path.contains("shrapnel"):
			_reflect_projectile(area)
			_reflected_projectiles[area_id] = true
			return

	# Fallback: check if it has bullet-like properties
	if "direction" in area and "speed" in area:
		_reflect_projectile(area)
		_reflected_projectiles[area_id] = true


## Called when a RigidBody2D enters the force field (grenades).
func _on_body_entered(body: Node2D) -> void:
	if not _is_active:
		return

	# Check if this is a grenade
	if body is RigidBody2D and body.is_in_group("grenades"):
		_reflect_grenade(body)


## Reflect a projectile (bullet or shrapnel) off the force field surface.
## The projectile direction is reflected based on the surface normal at the point of contact.
func _reflect_projectile(projectile: Area2D) -> void:
	# Calculate the surface normal at the point where the projectile hits the field
	# Normal points from the field center toward the projectile
	var field_center: Vector2 = global_position
	var projectile_pos: Vector2 = projectile.global_position
	var surface_normal: Vector2 = (projectile_pos - field_center).normalized()

	# Get the current direction of the projectile
	var incoming_direction: Vector2
	if "direction" in projectile:
		incoming_direction = projectile.direction
	else:
		# Fallback: estimate from rotation
		incoming_direction = Vector2.RIGHT.rotated(projectile.rotation)

	# Calculate reflected direction: R = D - 2(D.N)N
	var reflected_direction: Vector2 = incoming_direction - 2.0 * incoming_direction.dot(surface_normal) * surface_normal
	reflected_direction = reflected_direction.normalized()

	# Apply reflected direction
	if "direction" in projectile:
		projectile.direction = reflected_direction

	# Update rotation to match new direction
	projectile.rotation = reflected_direction.angle()

	# Move projectile slightly outward to prevent immediate re-detection
	projectile.global_position = field_center + surface_normal * (FIELD_RADIUS + 10.0)

	# Clear trail history if present (to avoid visual artifacts)
	if "_position_history" in projectile:
		projectile._position_history.clear()

	# Mark as reflected for shooter_id purposes:
	# After reflection, the bullet should be able to damage the original shooter
	# Reset shooter_id so it can hit anyone (reflected bullets are dangerous to all)
	if "shooter_id" in projectile:
		projectile.shooter_id = -1

	# Mark as ricocheted so player bullet hit effects don't trigger incorrectly
	if "_has_ricocheted" in projectile:
		projectile._has_ricocheted = true

	# Play ricochet sound at the deflection point
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_ricochet"):
		audio_manager.play_bullet_ricochet(projectile_pos)

	FileLogger.info("[ForceField] Reflected projectile %s (type: %s)" % [
		projectile.name,
		projectile.get_script().resource_path.get_file() if projectile.get_script() else "unknown"
	])


## Reflect a grenade off the force field surface.
## Grenades bounce away without detonating (especially important for frag/offensive grenades).
func _reflect_grenade(grenade: RigidBody2D) -> void:
	# Calculate the surface normal at the point where the grenade hits the field
	var field_center: Vector2 = global_position
	var grenade_pos: Vector2 = grenade.global_position
	var surface_normal: Vector2 = (grenade_pos - field_center).normalized()

	# Get the current velocity of the grenade
	var incoming_velocity: Vector2 = grenade.linear_velocity

	# If grenade has no velocity (e.g., just spawned), push it away
	if incoming_velocity.length() < 10.0:
		incoming_velocity = -surface_normal * 200.0

	# Calculate reflected velocity: R = V - 2(V.N)N
	var reflected_velocity: Vector2 = incoming_velocity - 2.0 * incoming_velocity.dot(surface_normal) * surface_normal

	# Boost the reflected speed slightly to make the deflection feel impactful
	reflected_velocity *= 1.2

	# Move grenade outside the field to prevent re-collision
	grenade.global_position = field_center + surface_normal * (FIELD_RADIUS + 15.0)

	# Apply reflected velocity
	grenade.linear_velocity = reflected_velocity

	# For frag grenades: prevent impact explosion on force field bounce
	# The _has_impacted flag check in frag_grenade.gd prevents double explosion
	# We temporarily set _is_thrown to false so the next body_entered won't trigger explosion
	# Then re-enable it after a short delay so it can explode on the next real impact
	if grenade is FragGrenade:
		# Disable impact detection temporarily to prevent explosion from force field bounce
		grenade._has_impacted = false
		grenade._is_thrown = false
		# Re-enable impact detection after a short delay (after the grenade clears the field)
		_reenable_frag_impact.call_deferred(grenade)

	# Play wall collision sound for the bounce effect
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_grenade_wall_hit"):
		audio_manager.play_grenade_wall_hit(grenade_pos)

	FileLogger.info("[ForceField] Reflected grenade %s (type: %s, velocity: %s)" % [
		grenade.name,
		grenade.get_class(),
		str(reflected_velocity)
	])


## Re-enable impact detection on a frag grenade after it clears the force field.
## Called deferred to give the grenade time to move away from the field.
func _reenable_frag_impact(grenade: RigidBody2D) -> void:
	if not is_instance_valid(grenade):
		return

	# Wait a short time for the grenade to move away from the field
	await get_tree().create_timer(0.15).timeout

	if not is_instance_valid(grenade):
		return

	if grenade is FragGrenade:
		grenade._is_thrown = true
		FileLogger.info("[ForceField] Re-enabled impact detection for frag grenade %s" % grenade.name)


## Play activation sound effect.
func _play_activation_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	# Use a generic activation sound or grenade activation as placeholder
	if audio_manager and audio_manager.has_method("play_grenade_activation"):
		audio_manager.play_grenade_activation(global_position)


## Play deactivation sound effect.
func _play_deactivation_sound() -> void:
	# No deactivation sound currently - could be added later
	pass


## Create a radial gradient texture for the PointLight2D glow.
## Uses a smooth radial falloff for a soft ambient glow around the force field.
func _create_glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.3, Color(0.6, 0.6, 0.6, 1.0))
	gradient.add_point(0.6, Color(0.2, 0.2, 0.2, 1.0))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 1.0))

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture
