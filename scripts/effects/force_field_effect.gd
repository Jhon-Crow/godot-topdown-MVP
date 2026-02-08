extends Node2D
## Force field active item effect.
##
## Creates a glowing circular force field around the player that reflects
## all incoming projectiles (bullets, shrapnel, and grenades).
## Frag (offensive) grenades bounce off without detonating on contact.
##
## Activated by HOLDING Space. The charge depletes while held and can be
## used in portions (e.g., hold 8s straight, or 8×1s, or 2×4s, etc.).
## Total charge: 8 seconds per fight.
## A progress bar shows the remaining charge when active.

## Total charge duration in seconds (shared across all activations).
const MAX_CHARGE: float = 8.0

## Radius of the force field in pixels.
const FIELD_RADIUS: float = 80.0

## Whether the force field is currently active (Space held and charge remaining).
var _is_active: bool = false

## Remaining charge in seconds.
var _charge_remaining: float = MAX_CHARGE

## Reference to the shield visual sprite (uses shader).
var _shield_sprite: Sprite2D = null

## Reference to the deflection Area2D.
var _deflection_area: Area2D = null

## Reference to the PointLight2D for glow effect.
var _glow_light: PointLight2D = null

## Reference to the progress bar CanvasLayer.
var _progress_canvas: CanvasLayer = null

## Reference to the progress bar Control container.
var _progress_bar_container: Control = null

## Reference to the progress bar background.
var _progress_bg: ColorRect = null

## Reference to the progress bar fill.
var _progress_fill: ColorRect = null

## Reference to the progress bar label.
var _progress_label: Label = null

## Set of projectile instance IDs already reflected (to prevent double-reflection).
var _reflected_projectiles: Dictionary = {}

## Whether the charge has been fully depleted (no more use possible).
var _depleted: bool = false

## Progress bar dimensions.
const BAR_WIDTH: float = 200.0
const BAR_HEIGHT: float = 16.0
const BAR_MARGIN_BOTTOM: float = 80.0


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

	# Create the progress bar UI
	_create_progress_bar()

	# Start hidden (inactive)
	_set_visible(false)

	FileLogger.info("[ForceField] Initialized with %.1fs charge, %.0fpx radius" % [
		_charge_remaining, FIELD_RADIUS
	])


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	# Deplete charge while active
	_charge_remaining -= delta

	# Update progress bar
	_update_progress_bar()

	# Visual flashing warning when charge is low (last 2 seconds)
	if _charge_remaining <= 2.0 and _shield_sprite:
		var flash_speed: float = 8.0 if _charge_remaining <= 1.0 else 4.0
		var flash_alpha: float = 0.5 + sin(Time.get_ticks_msec() * 0.001 * flash_speed) * 0.5
		_shield_sprite.modulate.a = flash_alpha

	# If charge runs out, deactivate
	if _charge_remaining <= 0:
		_charge_remaining = 0.0
		_depleted = true
		deactivate()


## Activate the force field (called when Space is pressed/held).
func activate() -> void:
	if _is_active:
		return

	if _depleted or _charge_remaining <= 0:
		FileLogger.info("[ForceField] No charge remaining, cannot activate")
		return

	_is_active = true
	_reflected_projectiles.clear()

	_set_visible(true)

	# Reset sprite alpha for fresh activation
	if _shield_sprite:
		_shield_sprite.modulate.a = 1.0

	# Play activation sound
	_play_activation_sound()

	FileLogger.info("[ForceField] Activated! Charge remaining: %.1fs" % _charge_remaining)


## Deactivate the force field (called when Space is released or charge runs out).
func deactivate() -> void:
	if not _is_active:
		return

	_is_active = false
	_reflected_projectiles.clear()

	_set_visible(false)

	# Play deactivation sound
	_play_deactivation_sound()

	FileLogger.info("[ForceField] Deactivated. Charge remaining: %.1fs" % _charge_remaining)


## Check if the force field is currently active.
func is_active() -> bool:
	return _is_active


## Check if the force field has charge remaining.
func has_charge() -> bool:
	return not _depleted and _charge_remaining > 0


## Get remaining charge in seconds.
func get_charge_remaining() -> float:
	return _charge_remaining


## Get the charge fraction (0.0 to 1.0).
func get_charge_fraction() -> float:
	return _charge_remaining / MAX_CHARGE


## Set visibility of the force field visual elements.
func _set_visible(visible_state: bool) -> void:
	if _shield_sprite:
		_shield_sprite.visible = visible_state
	if _glow_light:
		_glow_light.visible = visible_state
	if _deflection_area:
		_deflection_area.monitoring = visible_state
	# Show/hide progress bar
	if _progress_bar_container:
		_progress_bar_container.visible = visible_state
	if _progress_canvas:
		_progress_canvas.visible = visible_state


## Create the progress bar UI overlay.
func _create_progress_bar() -> void:
	# Create a CanvasLayer so the bar is always on screen (not in world space)
	_progress_canvas = CanvasLayer.new()
	_progress_canvas.layer = 50  # Above game, below pause menu
	_progress_canvas.name = "ForceFieldProgressCanvas"
	add_child(_progress_canvas)

	# Container for centering the bar at bottom of screen
	_progress_bar_container = Control.new()
	_progress_bar_container.name = "ProgressBarContainer"
	_progress_bar_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_progress_canvas.add_child(_progress_bar_container)

	# Background bar (dark)
	_progress_bg = ColorRect.new()
	_progress_bg.name = "ProgressBG"
	_progress_bg.color = Color(0.1, 0.1, 0.15, 0.7)
	_progress_bg.size = Vector2(BAR_WIDTH + 4, BAR_HEIGHT + 4)
	_progress_bar_container.add_child(_progress_bg)

	# Fill bar (colored)
	_progress_fill = ColorRect.new()
	_progress_fill.name = "ProgressFill"
	_progress_fill.color = Color(0.3, 0.7, 1.0, 0.9)
	_progress_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_progress_fill.position = Vector2(2, 2)
	_progress_bg.add_child(_progress_fill)

	# Label
	_progress_label = Label.new()
	_progress_label.name = "ProgressLabel"
	_progress_label.text = "FORCE FIELD"
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress_label.size = Vector2(BAR_WIDTH + 4, BAR_HEIGHT + 4)
	_progress_label.position = Vector2.ZERO
	_progress_label.add_theme_font_size_override("font_size", 10)
	_progress_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_progress_bg.add_child(_progress_label)

	# Position the bar at center-bottom of the viewport
	_reposition_progress_bar()

	# Hide initially
	_progress_canvas.visible = false


## Reposition the progress bar to center-bottom of the viewport.
func _reposition_progress_bar() -> void:
	if _progress_bg == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var bar_x: float = (viewport_size.x - BAR_WIDTH - 4) / 2.0
	var bar_y: float = viewport_size.y - BAR_MARGIN_BOTTOM
	_progress_bg.position = Vector2(bar_x, bar_y)


## Update the progress bar fill based on remaining charge.
func _update_progress_bar() -> void:
	if _progress_fill == null:
		return

	var fraction: float = get_charge_fraction()
	_progress_fill.size.x = BAR_WIDTH * fraction

	# Change color based on charge level
	if fraction <= 0.25:
		_progress_fill.color = Color(1.0, 0.2, 0.2, 0.9)  # Red when low
	elif fraction <= 0.5:
		_progress_fill.color = Color(1.0, 0.7, 0.2, 0.9)  # Orange when medium
	else:
		_progress_fill.color = Color(0.3, 0.7, 1.0, 0.9)  # Blue when high

	# Update label
	if _progress_label:
		_progress_label.text = "FORCE FIELD  %.1fs" % _charge_remaining

	# Reposition in case viewport changed
	_reposition_progress_bar()


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
func _reflect_projectile(projectile: Area2D) -> void:
	var field_center: Vector2 = global_position
	var projectile_pos: Vector2 = projectile.global_position
	var surface_normal: Vector2 = (projectile_pos - field_center).normalized()

	var incoming_direction: Vector2
	if "direction" in projectile:
		incoming_direction = projectile.direction
	else:
		incoming_direction = Vector2.RIGHT.rotated(projectile.rotation)

	# R = D - 2(D.N)N
	var reflected_direction: Vector2 = incoming_direction - 2.0 * incoming_direction.dot(surface_normal) * surface_normal
	reflected_direction = reflected_direction.normalized()

	if "direction" in projectile:
		projectile.direction = reflected_direction

	projectile.rotation = reflected_direction.angle()

	# Move projectile outside field to prevent re-detection
	projectile.global_position = field_center + surface_normal * (FIELD_RADIUS + 10.0)

	# Clear trail history if present
	if "_position_history" in projectile:
		projectile._position_history.clear()

	# Reset shooter_id so reflected bullets can damage anyone
	if "shooter_id" in projectile:
		projectile.shooter_id = -1

	if "_has_ricocheted" in projectile:
		projectile._has_ricocheted = true

	# Play ricochet sound
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_bullet_ricochet"):
		audio_manager.play_bullet_ricochet(projectile_pos)

	FileLogger.info("[ForceField] Reflected projectile %s (type: %s)" % [
		projectile.name,
		projectile.get_script().resource_path.get_file() if projectile.get_script() else "unknown"
	])


## Reflect a grenade off the force field surface.
func _reflect_grenade(grenade: RigidBody2D) -> void:
	var field_center: Vector2 = global_position
	var grenade_pos: Vector2 = grenade.global_position
	var surface_normal: Vector2 = (grenade_pos - field_center).normalized()

	var incoming_velocity: Vector2 = grenade.linear_velocity

	if incoming_velocity.length() < 10.0:
		incoming_velocity = -surface_normal * 200.0

	# R = V - 2(V.N)N
	var reflected_velocity: Vector2 = incoming_velocity - 2.0 * incoming_velocity.dot(surface_normal) * surface_normal
	reflected_velocity *= 1.2

	grenade.global_position = field_center + surface_normal * (FIELD_RADIUS + 15.0)
	grenade.linear_velocity = reflected_velocity

	# For frag grenades: prevent impact explosion on force field bounce
	if grenade is FragGrenade:
		grenade._has_impacted = false
		grenade._is_thrown = false
		_reenable_frag_impact.call_deferred(grenade)

	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_grenade_wall_hit"):
		audio_manager.play_grenade_wall_hit(grenade_pos)

	FileLogger.info("[ForceField] Reflected grenade %s (type: %s, velocity: %s)" % [
		grenade.name,
		grenade.get_class(),
		str(reflected_velocity)
	])


## Re-enable impact detection on a frag grenade after it clears the force field.
func _reenable_frag_impact(grenade: RigidBody2D) -> void:
	if not is_instance_valid(grenade):
		return

	await get_tree().create_timer(0.15).timeout

	if not is_instance_valid(grenade):
		return

	if grenade is FragGrenade:
		grenade._is_thrown = true
		FileLogger.info("[ForceField] Re-enabled impact detection for frag grenade %s" % grenade.name)


## Play activation sound effect.
func _play_activation_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_grenade_activation"):
		audio_manager.play_grenade_activation(global_position)


## Play deactivation sound effect.
func _play_deactivation_sound() -> void:
	pass


## Create a radial gradient texture for the PointLight2D glow.
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
