extends Node2D
## Visual teleportation effect for level transitions (Issue #721).
##
## Creates a sci-fi style teleportation effect with:
## - A bottom portal ring (concentric circles)
## - A top portal ring (descends/ascends during animation)
## - Particle effects (sparkles, light beams)
## - A light column between the portals
##
## Animation phases:
## - DISAPPEAR: Top ring descends, player fades out (sinking into portal)
## - APPEAR: Top ring ascends, player fades in (emerging from portal)
##
## Usage:
## 1. Instantiate this scene at the player's position
## 2. Call play_disappear() to start the disappear animation
## 3. Connect to animation_finished signal to know when done
## 4. Optionally call play_appear() at destination for appear effect

## Signal emitted when the animation finishes (either disappear or appear).
signal animation_finished(animation_type: String)

## Signal emitted during disappear when player should be hidden.
signal player_should_hide

## Signal emitted during appear when player should be shown.
signal player_should_show

## Animation phases.
enum AnimPhase { IDLE, DISAPPEAR, APPEAR }

## Current animation phase.
var _current_phase: AnimPhase = AnimPhase.IDLE

## Duration of the teleport animation in seconds.
const ANIMATION_DURATION: float = 0.8

## Color for the portal rings (cyan/blue sci-fi style).
const PORTAL_COLOR: Color = Color(0.2, 0.8, 1.0, 0.9)

## Color for the light column.
const LIGHT_COLOR: Color = Color(0.3, 0.9, 1.0, 0.7)

## Color for particles.
const PARTICLE_COLOR: Color = Color(0.5, 0.95, 1.0, 0.8)

## Radius of the portal rings.
const PORTAL_RADIUS: float = 40.0

## Height of the light column at maximum.
const COLUMN_HEIGHT: float = 80.0

## Ring thickness.
const RING_THICKNESS: float = 3.0

## Number of concentric rings.
const RING_COUNT: int = 3

## Animation progress (0.0 to 1.0).
var _progress: float = 0.0

## Bottom portal ring (stays at player feet).
var _bottom_ring: Node2D = null

## Top portal ring (moves up/down during animation).
var _top_ring: Node2D = null

## Light column between portals.
var _light_column: ColorRect = null

## Particle emitter for sparkles.
var _particles: GPUParticles2D = null

## Point light for glow effect.
var _point_light: PointLight2D = null

## Reference to the target (usually player) for visibility control.
var _target: Node2D = null

## Initial player modulate value to restore.
var _original_modulate: Color = Color.WHITE


func _ready() -> void:
	# Create visual components
	_create_portal_rings()
	_create_light_column()
	_create_particles()
	_create_point_light()

	# Start hidden
	_set_effect_visible(false)


## Set the target node whose visibility will be controlled during the effect.
func set_target(target: Node2D) -> void:
	_target = target
	if _target:
		_original_modulate = _target.modulate


## Play the disappear animation (player sinks into portal).
func play_disappear() -> void:
	if _current_phase != AnimPhase.IDLE:
		return

	_current_phase = AnimPhase.DISAPPEAR
	_progress = 0.0
	_set_effect_visible(true)

	FileLogger.info("[TeleportEffect] Playing disappear animation")


## Play the appear animation (player emerges from portal).
func play_appear() -> void:
	if _current_phase != AnimPhase.IDLE:
		return

	_current_phase = AnimPhase.APPEAR
	_progress = 0.0
	_set_effect_visible(true)

	# Start with target hidden for appear animation
	if _target and is_instance_valid(_target):
		_target.modulate = Color(_original_modulate.r, _original_modulate.g, _original_modulate.b, 0.0)

	FileLogger.info("[TeleportEffect] Playing appear animation")


func _process(delta: float) -> void:
	if _current_phase == AnimPhase.IDLE:
		return

	# Update animation progress
	_progress += delta / ANIMATION_DURATION
	_progress = clampf(_progress, 0.0, 1.0)

	# Update visual elements based on progress and phase
	_update_animation()

	# Check if animation is complete
	if _progress >= 1.0:
		_complete_animation()


## Update all visual elements based on current progress.
func _update_animation() -> void:
	var t: float = _progress

	# Apply easing for smooth animation
	var ease_t: float = _ease_in_out(t)

	match _current_phase:
		AnimPhase.DISAPPEAR:
			_update_disappear_animation(ease_t)
		AnimPhase.APPEAR:
			_update_appear_animation(ease_t)


## Update the disappear animation state.
func _update_disappear_animation(t: float) -> void:
	# Top ring descends from COLUMN_HEIGHT to 0
	if _top_ring:
		_top_ring.position.y = -COLUMN_HEIGHT * (1.0 - t)

	# Light column shrinks as top ring descends
	if _light_column:
		var column_height: float = COLUMN_HEIGHT * (1.0 - t)
		_light_column.size.y = column_height
		_light_column.position.y = -column_height
		# Fade out as it shrinks
		_light_column.modulate.a = (1.0 - t) * LIGHT_COLOR.a

	# Fade out target (player)
	if _target and is_instance_valid(_target):
		var alpha: float = 1.0 - t
		_target.modulate = Color(_original_modulate.r, _original_modulate.g, _original_modulate.b, alpha)

		# Emit signal when player should be fully hidden (at 50% progress)
		if t >= 0.5 and t < 0.55:
			player_should_hide.emit()

	# Particle intensity decreases
	if _particles:
		_particles.amount_ratio = 1.0 - (t * 0.5)

	# Light intensity follows animation
	if _point_light:
		_point_light.energy = 2.0 * (1.0 - t * 0.7)

	# Ring opacity pulses
	_update_ring_opacity(1.0 - t * 0.3)


## Update the appear animation state.
func _update_appear_animation(t: float) -> void:
	# Top ring ascends from 0 to COLUMN_HEIGHT
	if _top_ring:
		_top_ring.position.y = -COLUMN_HEIGHT * t

	# Light column grows as top ring ascends
	if _light_column:
		var column_height: float = COLUMN_HEIGHT * t
		_light_column.size.y = column_height
		_light_column.position.y = -column_height
		# Fade in as it grows, then fade out at end
		var column_alpha: float = 0.0
		if t < 0.5:
			column_alpha = t * 2.0
		else:
			column_alpha = (1.0 - t) * 2.0
		_light_column.modulate.a = column_alpha * LIGHT_COLOR.a

	# Fade in target (player)
	if _target and is_instance_valid(_target):
		var alpha: float = t
		_target.modulate = Color(_original_modulate.r, _original_modulate.g, _original_modulate.b, alpha)

		# Emit signal when player should start showing (at 50% progress)
		if t >= 0.5 and t < 0.55:
			player_should_show.emit()

	# Particle intensity peaks in middle
	if _particles:
		var particle_ratio: float = 0.0
		if t < 0.5:
			particle_ratio = t * 2.0
		else:
			particle_ratio = (1.0 - t) * 2.0
		_particles.amount_ratio = particle_ratio

	# Light intensity follows animation
	if _point_light:
		var light_energy: float = 0.0
		if t < 0.5:
			light_energy = t * 4.0
		else:
			light_energy = (1.0 - t) * 4.0
		_point_light.energy = light_energy

	# Ring opacity pulses
	var ring_opacity: float = 0.7 + 0.3 * sin(t * PI)
	_update_ring_opacity(ring_opacity)


## Update the opacity of portal rings.
func _update_ring_opacity(opacity: float) -> void:
	if _bottom_ring:
		_bottom_ring.modulate.a = opacity
	if _top_ring:
		_top_ring.modulate.a = opacity


## Complete the current animation.
func _complete_animation() -> void:
	var finished_phase: String = "disappear" if _current_phase == AnimPhase.DISAPPEAR else "appear"

	# Restore target visibility based on animation type
	if _target and is_instance_valid(_target):
		if _current_phase == AnimPhase.DISAPPEAR:
			_target.modulate = Color(_original_modulate.r, _original_modulate.g, _original_modulate.b, 0.0)
		else:
			_target.modulate = _original_modulate

	_current_phase = AnimPhase.IDLE
	_set_effect_visible(false)

	FileLogger.info("[TeleportEffect] Animation completed: %s" % finished_phase)
	animation_finished.emit(finished_phase)


## Create the portal ring nodes.
func _create_portal_rings() -> void:
	# Bottom ring (at feet level)
	_bottom_ring = _create_ring_node("BottomRing")
	_bottom_ring.position = Vector2.ZERO
	add_child(_bottom_ring)

	# Top ring (moves during animation)
	_top_ring = _create_ring_node("TopRing")
	_top_ring.position = Vector2(0, -COLUMN_HEIGHT)
	add_child(_top_ring)


## Create a single ring node with concentric circles.
func _create_ring_node(ring_name: String) -> Node2D:
	var ring_container := Node2D.new()
	ring_container.name = ring_name

	# Create multiple concentric rings using Line2D
	for i in range(RING_COUNT):
		var ring := Line2D.new()
		ring.name = "Ring%d" % i
		ring.width = RING_THICKNESS - i * 0.5
		ring.default_color = PORTAL_COLOR
		ring.default_color.a = 1.0 - (i * 0.2)
		ring.joint_mode = Line2D.LINE_JOINT_ROUND
		ring.end_cap_mode = Line2D.LINE_CAP_ROUND
		ring.begin_cap_mode = Line2D.LINE_CAP_ROUND

		# Create circular points
		var radius: float = PORTAL_RADIUS - (i * 8.0)
		var points: PackedVector2Array = PackedVector2Array()
		var segments: int = 32
		for j in range(segments + 1):
			var angle: float = (j / float(segments)) * TAU
			points.append(Vector2(cos(angle) * radius, sin(angle) * radius * 0.4))  # Ellipse for perspective
		ring.points = points

		ring_container.add_child(ring)

	return ring_container


## Create the light column between portals.
func _create_light_column() -> void:
	_light_column = ColorRect.new()
	_light_column.name = "LightColumn"
	_light_column.color = LIGHT_COLOR
	_light_column.size = Vector2(PORTAL_RADIUS * 1.2, COLUMN_HEIGHT)
	_light_column.position = Vector2(-PORTAL_RADIUS * 0.6, -COLUMN_HEIGHT)

	# Add some transparency gradient effect via modulate
	_light_column.modulate = Color(1, 1, 1, 0.6)

	add_child(_light_column)


## Create particle effects for sparkles.
func _create_particles() -> void:
	_particles = GPUParticles2D.new()
	_particles.name = "Particles"
	_particles.emitting = true
	_particles.amount = 40
	_particles.lifetime = 1.0
	_particles.one_shot = false
	_particles.explosiveness = 0.1
	_particles.randomness = 0.5

	# Create process material
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = PORTAL_RADIUS
	material.direction = Vector3(0, -1, 0)
	material.spread = 30.0
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 60.0
	material.gravity = Vector3(0, -20, 0)
	material.scale_min = 0.5
	material.scale_max = 1.5
	material.color = PARTICLE_COLOR

	_particles.process_material = material

	# Create a simple texture (small circle)
	var texture := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		PARTICLE_COLOR,
		Color(PARTICLE_COLOR.r, PARTICLE_COLOR.g, PARTICLE_COLOR.b, 0.8),
		Color(PARTICLE_COLOR.r, PARTICLE_COLOR.g, PARTICLE_COLOR.b, 0.4),
		Color(PARTICLE_COLOR.r, PARTICLE_COLOR.g, PARTICLE_COLOR.b, 0.0)
	])
	texture.gradient = gradient
	texture.width = 16
	texture.height = 16
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)

	_particles.texture = texture

	add_child(_particles)


## Create a point light for the glow effect.
func _create_point_light() -> void:
	_point_light = PointLight2D.new()
	_point_light.name = "PointLight"
	_point_light.color = PORTAL_COLOR
	_point_light.energy = 2.0
	_point_light.shadow_enabled = false

	# Create gradient texture for the light
	var texture := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 1),
		Color(1, 1, 1, 0.6),
		Color(1, 1, 1, 0.2),
		Color(1, 1, 1, 0)
	])
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)

	_point_light.texture = texture
	_point_light.texture_scale = 2.0

	add_child(_point_light)


## Set the visibility of all effect components.
func _set_effect_visible(visible_state: bool) -> void:
	if _bottom_ring:
		_bottom_ring.visible = visible_state
	if _top_ring:
		_top_ring.visible = visible_state
	if _light_column:
		_light_column.visible = visible_state
	if _particles:
		_particles.visible = visible_state
		_particles.emitting = visible_state
	if _point_light:
		_point_light.visible = visible_state


## Easing function for smooth animation (ease in-out cubic).
func _ease_in_out(t: float) -> float:
	if t < 0.5:
		return 4.0 * t * t * t
	else:
		var f: float = (2.0 * t) - 2.0
		return 0.5 * f * f * f + 1.0


## Check if the effect is currently playing.
func is_playing() -> bool:
	return _current_phase != AnimPhase.IDLE


## Get the current animation phase as string.
func get_current_phase() -> String:
	match _current_phase:
		AnimPhase.IDLE:
			return "idle"
		AnimPhase.DISAPPEAR:
			return "disappear"
		AnimPhase.APPEAR:
			return "appear"
	return "unknown"
