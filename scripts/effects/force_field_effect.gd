extends Node2D
## Force field effect controller (Issue #676).
##
## Creates a glowing energy shield around the player that reflects all projectiles.
## Activated by holding Space key with a depletable 8-second charge.
##
## Gameplay rules:
## - Hold Space to activate, release to deactivate
## - 8 second total charge (usable in portions: 8×1s, 2×4s, etc.)
## - 100% projectile reflection (bullets, shrapnel, grenades)
## - Frag grenades bounce WITHOUT detonating on contact
## - Full damage protection while active
## - Visual warning when charge is low (last 2 seconds)

## Maximum charge duration in seconds.
const MAX_CHARGE: float = 8.0

## Radius of the force field protection area (pixels).
const FIELD_RADIUS: float = 80.0

## Shield visual scale.
const SHIELD_SCALE: float = 2.5

## Reflection velocity boost multiplier for grenades.
const GRENADE_REFLECTION_BOOST: float = 1.2

## Duration to disable grenade impact detection after bounce (seconds).
const GRENADE_BOUNCE_IMMUNITY_TIME: float = 0.15

## Low charge warning threshold (seconds).
const LOW_CHARGE_WARNING: float = 2.0

## Flash frequency when charge is low (Hz).
const WARNING_FLASH_FREQUENCY: float = 3.0

## Path to the force field shader.
const SHADER_PATH: String = "res://scripts/shaders/force_field.gdshader"

## Remaining charge in seconds.
var remaining_charge: float = MAX_CHARGE

## Whether the force field is currently active.
var is_active: bool = false

## Reference to the visual shield sprite (Sprite2D or similar).
var _shield_sprite: Sprite2D = null

## Reference to the Area2D for projectile detection.
var _area2d: Area2D = null

## Reference to the CollisionShape2D.
var _collision_shape: CollisionShape2D = null

## Shader material for the glowing effect.
var _shader_material: ShaderMaterial = null

## Warning flash timer.
var _warning_flash_timer: float = 0.0

## Signal emitted when force field is activated.
signal force_field_activated()

## Signal emitted when force field is deactivated.
signal force_field_deactivated()

## Signal emitted when charge changes.
signal charge_changed(current: float, maximum: float)

## Signal emitted when charge is depleted.
signal charge_depleted()


func _ready() -> void:
	_setup_area2d()
	_setup_shield_visual()
	_set_field_active(false)
	FileLogger.info("[ForceFieldEffect] Initialized with %.1fs charge" % MAX_CHARGE)


## Set up the Area2D for projectile detection.
func _setup_area2d() -> void:
	_area2d = Area2D.new()
	_area2d.name = "ForceFieldArea"
	_area2d.collision_layer = 0  # Don't register on any layer
	_area2d.collision_mask = 0   # Will detect projectiles via custom layer
	add_child(_area2d)

	# Create circular collision shape
	var shape := CircleShape2D.new()
	shape.radius = FIELD_RADIUS
	_collision_shape = CollisionShape2D.new()
	_collision_shape.shape = shape
	_area2d.add_child(_collision_shape)

	# Connect area entered signal for projectile reflection
	_area2d.area_entered.connect(_on_projectile_entered)

	FileLogger.info("[ForceFieldEffect] Area2D setup with radius %.0fpx" % FIELD_RADIUS)


## Set up the shield visual (glowing sprite with shader).
func _setup_shield_visual() -> void:
	_shield_sprite = Sprite2D.new()
	_shield_sprite.name = "ShieldVisual"
	_shield_sprite.scale = Vector2(SHIELD_SCALE, SHIELD_SCALE)
	_shield_sprite.z_index = 10  # Draw above player
	add_child(_shield_sprite)

	# Create a circular texture for the shield
	_shield_sprite.texture = _create_shield_texture()

	# Load and apply shader
	if ResourceLoader.exists(SHADER_PATH):
		var shader = load(SHADER_PATH)
		if shader:
			_shader_material = ShaderMaterial.new()
			_shader_material.shader = shader
			_shield_sprite.material = _shader_material
			FileLogger.info("[ForceFieldEffect] Shader loaded successfully")
		else:
			FileLogger.info("[ForceFieldEffect] WARNING: Failed to load shader")
	else:
		FileLogger.info("[ForceFieldEffect] WARNING: Shader not found: %s" % SHADER_PATH)


## Create a circular gradient texture for the shield visual.
func _create_shield_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.4, 0.6, 1.0, 1.0))  # Blue center
	gradient.set_color(1, Color(0.4, 0.6, 1.0, 0.0))  # Fade to transparent

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture


## Activate the force field.
func activate() -> bool:
	if is_active:
		return false  # Already active

	if remaining_charge <= 0.0:
		FileLogger.info("[ForceFieldEffect] No charge remaining")
		return false

	is_active = true
	_set_field_active(true)
	FileLogger.info("[ForceFieldEffect] Activated! Charge: %.1fs/%.1fs" % [remaining_charge, MAX_CHARGE])
	force_field_activated.emit()
	return true


## Deactivate the force field.
func deactivate() -> void:
	if not is_active:
		return

	is_active = false
	_set_field_active(false)
	FileLogger.info("[ForceFieldEffect] Deactivated. Charge remaining: %.1fs" % remaining_charge)
	force_field_deactivated.emit()


## Set the force field visual and collision active state.
func _set_field_active(active: bool) -> void:
	if _shield_sprite:
		_shield_sprite.visible = active
	if _collision_shape:
		_collision_shape.disabled = not active


func _process(delta: float) -> void:
	if not is_active:
		return

	# Deplete charge while active
	remaining_charge -= delta
	if remaining_charge <= 0.0:
		remaining_charge = 0.0
		deactivate()
		charge_depleted.emit()
		FileLogger.info("[ForceFieldEffect] Charge depleted")

	charge_changed.emit(remaining_charge, MAX_CHARGE)

	# Visual warning when charge is low
	if remaining_charge <= LOW_CHARGE_WARNING:
		_warning_flash_timer += delta
		var flash_period = 1.0 / WARNING_FLASH_FREQUENCY
		var flash_on = fmod(_warning_flash_timer, flash_period) < (flash_period * 0.5)
		if _shield_sprite:
			_shield_sprite.modulate.a = 1.0 if flash_on else 0.5


## Check if the player is currently protected by the force field.
func is_protecting() -> bool:
	return is_active


## Get the remaining charge in seconds.
func get_remaining_charge() -> float:
	return remaining_charge


## Handle projectile entering the force field area.
func _on_projectile_entered(area: Area2D) -> void:
	if not is_active:
		return

	var projectile = area.get_parent()
	if projectile == null or not is_instance_valid(projectile):
		return

	# Reflect bullets
	if projectile.is_in_group("bullets"):
		_reflect_bullet(projectile)
	# Reflect shrapnel
	elif projectile.is_in_group("shrapnel"):
		_reflect_shrapnel(projectile)
	# Reflect grenades
	elif projectile.is_in_group("grenades"):
		_reflect_grenade(projectile)


## Reflect a bullet off the force field.
func _reflect_bullet(bullet: Node2D) -> void:
	if not bullet.has("velocity"):
		return

	# Calculate reflection using surface normal
	var to_bullet := bullet.global_position - global_position
	var normal := to_bullet.normalized()
	var velocity: Vector2 = bullet.velocity

	# Reflection formula: R = V - 2(V·N)N
	var dot := velocity.dot(normal)
	var reflected := velocity - 2.0 * dot * normal

	bullet.velocity = reflected

	# Reset shooter ID so reflected bullet can damage anyone
	if bullet.has("shooter_id"):
		bullet.shooter_id = -1

	FileLogger.info("[ForceFieldEffect] Bullet reflected: %.1f°" % rad_to_deg(reflected.angle()))


## Reflect shrapnel off the force field.
func _reflect_shrapnel(shrapnel: Node2D) -> void:
	if not shrapnel.has("velocity"):
		return

	# Calculate reflection using surface normal
	var to_shrapnel := shrapnel.global_position - global_position
	var normal := to_shrapnel.normalized()
	var velocity: Vector2 = shrapnel.velocity

	# Reflection formula: R = V - 2(V·N)N
	var dot := velocity.dot(normal)
	var reflected := velocity - 2.0 * dot * normal

	shrapnel.velocity = reflected

	# Reset shooter ID so reflected shrapnel can damage anyone
	if shrapnel.has("shooter_id"):
		shrapnel.shooter_id = -1

	FileLogger.info("[ForceFieldEffect] Shrapnel reflected")


## Reflect a grenade off the force field.
func _reflect_grenade(grenade: Node2D) -> void:
	if not grenade.has("velocity"):
		return

	# Calculate reflection using surface normal
	var to_grenade := grenade.global_position - global_position
	var normal := to_grenade.normalized()
	var velocity: Vector2 = grenade.velocity

	# Reflection formula: R = V - 2(V·N)N with boost
	var dot := velocity.dot(normal)
	var reflected := (velocity - 2.0 * dot * normal) * GRENADE_REFLECTION_BOOST

	grenade.velocity = reflected

	# For frag/offensive grenades: temporarily disable impact detection
	# so they don't detonate on the force field surface
	if grenade.has_method("set_impact_detection_enabled"):
		grenade.set_impact_detection_enabled(false)
		# Re-enable after grenade clears the field
		get_tree().create_timer(GRENADE_BOUNCE_IMMUNITY_TIME).timeout.connect(
			func():
				if is_instance_valid(grenade) and grenade.has_method("set_impact_detection_enabled"):
					grenade.set_impact_detection_enabled(true)
		)

	FileLogger.info("[ForceFieldEffect] Grenade reflected: %.1f°" % rad_to_deg(reflected.angle()))
