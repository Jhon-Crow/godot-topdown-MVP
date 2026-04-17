extends Node2D
## Blood diffusion effect for water (Issue #1445, enhanced Issue #1578).
##
## When blood enters the water it spreads as dense pigment under the water
## surface instead of leaving a floor puddle. The long-lived stain is drawn
## procedurally and is layered below WaterBody.WaterVisual; the particle system
## adds the smoke-like wisps requested in Issue #1578 feedback.

class_name WaterBloodDiffusion

## Maximum radius the blood cloud expands to.
const MAX_RADIUS: float = 145.0

## Duration of the expansion + fade effect in seconds.
const DURATION: float = 75.0

## Duration of the initial fast expansion phase.
const EXPAND_DURATION: float = 18.0

## Duration before the stain begins its final fade-out. Keeps a semi-dissolved
## cloud visible for more than a minute.
const HOLD_DURATION: float = 62.0

const PARTICLE_RADIUS: float = 95.0

## Blood color (set by WaterBody when spawning).
var _blood_color: Color = Color(0.42, 0.01, 0.01, 0.72)

## Elapsed time since spawn.
var _elapsed: float = 0.0

## Whether the effect has finished.
var _done: bool = false

var _wisp_particles: GPUParticles2D = null
var _seed: float = 0.0


func _ready() -> void:
	# Render below WaterVisual so the shader/waves sit naturally above the pigment.
	z_index = 0
	_seed = randf() * TAU
	_setup_wisp_particles()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION and not _done:
		_done = true
		queue_free()
	else:
		if _wisp_particles != null and _elapsed >= HOLD_DURATION:
			_wisp_particles.emitting = false
		queue_redraw()


func _draw() -> void:
	if _done:
		return

	var expand_t: float = clampf(_elapsed / EXPAND_DURATION, 0.0, 1.0)
	var radius: float = MAX_RADIUS * (1.0 - pow(1.0 - expand_t, 3.0))

	var fade_t: float = clampf((_elapsed - HOLD_DURATION) / maxf(DURATION - HOLD_DURATION, 0.001), 0.0, 1.0)
	var alpha: float = _blood_color.a * (1.0 - fade_t * fade_t)

	# Dense core plus asymmetric lobes: closer to pigment/smoke diffusion than a flat target circle.
	var core_col := _blood_color
	core_col.a = alpha * 0.42
	draw_circle(Vector2.ZERO, radius * 0.58, core_col)

	for i in range(9):
		var angle := _seed + float(i) * TAU / 9.0 + sin(_elapsed * 0.08 + float(i)) * 0.18
		var offset_len := radius * randf_range(0.08, 0.28)
		var offset := Vector2(cos(angle), sin(angle)) * offset_len
		var lobe_col := _blood_color
		lobe_col.a = alpha * randf_range(0.10, 0.22)
		draw_circle(offset, radius * randf_range(0.22, 0.48), lobe_col)

	for i in range(6):
		var ring_col := _blood_color
		ring_col.a = alpha * (0.07 - float(i) * 0.007)
		if ring_col.a > 0.005:
			draw_arc(Vector2.ZERO, radius * (0.55 + float(i) * 0.08), _seed + float(i), _seed + PI * 1.35 + float(i) * 0.3, 48, ring_col, 8.0, true)


## Set the blood color (called by WaterBody after instantiation).
func set_blood_color(color: Color) -> void:
	_blood_color = Color(color.r, color.g, color.b, 0.72)
	if _wisp_particles != null:
		var material := _wisp_particles.process_material as ParticleProcessMaterial
		if material != null:
			material.color = Color(_blood_color.r, _blood_color.g, _blood_color.b, 0.55)


func get_effect_duration() -> float:
	return DURATION


func _setup_wisp_particles() -> void:
	_wisp_particles = GPUParticles2D.new()
	_wisp_particles.name = "BloodPigmentWisps"
	_wisp_particles.z_index = 0
	_wisp_particles.amount = 90
	_wisp_particles.lifetime = 16.0
	_wisp_particles.preprocess = 4.0
	_wisp_particles.explosiveness = 0.05
	_wisp_particles.randomness = 0.65
	_wisp_particles.one_shot = false
	_wisp_particles.emitting = true

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	gradient.colors = PackedColorArray([
		Color(_blood_color.r, _blood_color.g, _blood_color.b, 0.55),
		Color(_blood_color.r * 0.85, _blood_color.g, _blood_color.b, 0.38),
		Color(_blood_color.r * 0.55, _blood_color.g, _blood_color.b, 0.18),
		Color(_blood_color.r * 0.35, _blood_color.g, _blood_color.b, 0.0)
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 96
	texture.height = 96
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	var material := ParticleProcessMaterial.new()
	material.particle_flag_disable_z = true
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = PARTICLE_RADIUS
	material.direction = Vector3(1, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 10.0
	material.angular_velocity_min = -18.0
	material.angular_velocity_max = 18.0
	material.gravity = Vector3(2.0, -1.0, 0.0)
	material.damping_min = 3.0
	material.damping_max = 12.0
	material.scale_min = 1.4
	material.scale_max = 4.0
	material.color = Color(_blood_color.r, _blood_color.g, _blood_color.b, 0.55)

	_wisp_particles.texture = texture
	_wisp_particles.process_material = material
	add_child(_wisp_particles)
