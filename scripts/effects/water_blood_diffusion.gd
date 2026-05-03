extends Node2D
## Blood diffusion effect for water (Issue #1445, enhanced Issue #1578).
##
## Simulates dense pigment (blood) entering water: a semi-dissolved stain that
## spreads and disperses over ~20 seconds, then permanently tints the water color.
## Drawn entirely via _draw() to avoid the GPU-particle cost that caused FPS drops
## when many effects exist.
## New blood hits nearby are absorbed into this node (see absorb()) rather than
## spawning fresh instances.

class_name WaterBloodDiffusion

## Merge radius: blood landings within this distance are absorbed into the nearest
## existing diffusion instead of creating a new node. Must match the constant in
## ImpactEffectsManager.
const MERGE_RADIUS: float = 120.0

## Maximum radius the blood cloud expands to.
const MAX_RADIUS: float = 80.0

## Smallest cloud radius multiplier for tiny droplets.
const MIN_RADIUS_SCALE: float = 0.35

## Largest cloud radius multiplier for large droplets/bursts.
const MAX_RADIUS_SCALE: float = 1.15

## Total lifetime of the effect in seconds.
const DURATION: float = 12.0

## Historical early-growth marker used by absorb(); visible growth continues for
## the whole lifetime so clouds disappear while still spreading.
const EXPAND_DURATION: float = 3.0

## Tint grows over the whole visible cloud lifetime, not only after expansion.
const TINT_START_TIME: float = 0.0

## Same red target used by realistic_water.gdshader for blood-tinted waves.
const WATER_BLOOD_TINT_COLOR: Color = Color(0.50, 0.02, 0.025, 0.72)

## Blood color (default dark red, overridden by set_blood_color).
var _blood_color: Color = Color(0.42, 0.01, 0.01, 0.72)

## Elapsed time since spawn.
var _elapsed: float = 0.0

## Whether the effect has finished.
var _done: bool = false

## Deterministic seed for lobe layout.
var _seed: float = 0.0

## Extra intensity from absorbed hits (each absorbed hit adds 0.2, capped at 1.0).
var _extra_alpha: float = 0.0

## Per-drop size multiplier. Small floor-decal drops become small cloud blotches.
var _radius_scale: float = 1.0

## How many hits were absorbed (used to scale water tint on dispersal).
var _absorbed_hits: int = 1

## Callback invoked each frame during the fade phase to apply tint gradually.
## Signature: func(world_pos: Vector2, absorbed_hits: int, fade_t: float) -> void
var on_tint_update: Callable = Callable()

## Whether the tint update has been connected (first frame of fade phase).
var _tint_started: bool = false


func _ready() -> void:
	z_index = 0
	_seed = randf() * TAU


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION and not _done:
		_done = true
		queue_free()
	else:
		# Tint grows from the first frame while the cloud expands and fades, so the
		# wave recolor is synchronized with the whole visible diffusion lifecycle.
		if _elapsed >= TINT_START_TIME and not _done and on_tint_update.is_valid():
			var tint_t: float = clampf((_elapsed - TINT_START_TIME) / maxf(DURATION - TINT_START_TIME, 0.001), 0.0, 1.0)
			on_tint_update.call(global_position, _absorbed_hits, tint_t)
		queue_redraw()


func _draw() -> void:
	if _done:
		return

	var growth_t: float = clampf(_elapsed / maxf(DURATION, 0.001), 0.0, 1.0)
	var radius: float = MAX_RADIUS * _radius_scale * (0.18 + 0.82 * pow(growth_t, 0.62))

	var fade_t: float = clampf(_elapsed / maxf(DURATION, 0.001), 0.0, 1.0)
	var base_alpha: float = minf(_blood_color.a + _extra_alpha * 0.3, 0.92)
	var alpha: float = base_alpha * (1.0 - fade_t)

	# Dense core
	var core_col := _blood_color
	core_col.a = alpha * 0.58
	draw_circle(Vector2.ZERO, radius * 0.55, core_col)

	# Asymmetric lobes — simulate pigment tendrils spreading in liquid
	for i in range(7):
		var angle := _seed + float(i) * TAU / 7.0 + sin(_elapsed * 0.06 + float(i)) * 0.15
		var offset_len := radius * lerpf(0.1, 0.3, float(i) / 7.0)
		var offset := Vector2(cos(angle), sin(angle)) * offset_len
		var lobe_col := _blood_color
		lobe_col.a = alpha * lerpf(0.34, 0.16, float(i) / 7.0)
		draw_circle(offset, radius * lerpf(0.38, 0.25, float(i) / 7.0), lobe_col)


## Set the blood color (called after instantiation).
func set_blood_color(color: Color) -> void:
	_blood_color = Color(WATER_BLOOD_TINT_COLOR.r, WATER_BLOOD_TINT_COLOR.g, WATER_BLOOD_TINT_COLOR.b, 0.72)


## Set cloud size from the matching floor-decal scale.
func set_drop_scale(drop_scale: float) -> void:
	_radius_scale = clampf(drop_scale, MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)


## Absorb a nearby blood hit: increase intensity and restart the expansion phase.
func absorb(drop_scale: float = 1.0) -> void:
	_extra_alpha = minf(_extra_alpha + 0.2, 1.0)
	_radius_scale = clampf(maxf(_radius_scale, drop_scale), MIN_RADIUS_SCALE, MAX_RADIUS_SCALE)
	_absorbed_hits += 1
	_tint_started = false
	if _elapsed > EXPAND_DURATION:
		_elapsed = EXPAND_DURATION


func get_effect_duration() -> float:
	return DURATION
