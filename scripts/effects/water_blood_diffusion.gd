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

## Total lifetime of the effect in seconds.
const DURATION: float = 12.0

## How long the effect expands before entering the hold phase.
const EXPAND_DURATION: float = 3.0

## Hold phase length — visible dissolving cloud before fading out.
const HOLD_DURATION: float = 5.0

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
		# During fade phase, call tint update each frame so water tint grows gradually
		# in sync with the cloud fading out (Issue #1578 feedback).
		if _elapsed >= HOLD_DURATION and not _done and on_tint_update.is_valid():
			var fade_t: float = clampf((_elapsed - HOLD_DURATION) / maxf(DURATION - HOLD_DURATION, 0.001), 0.0, 1.0)
			on_tint_update.call(global_position, _absorbed_hits, fade_t)
		queue_redraw()


func _draw() -> void:
	if _done:
		return

	var expand_t: float = clampf(_elapsed / EXPAND_DURATION, 0.0, 1.0)
	var radius: float = MAX_RADIUS * (1.0 - pow(1.0 - expand_t, 3.0))

	var fade_t: float = clampf((_elapsed - HOLD_DURATION) / maxf(DURATION - HOLD_DURATION, 0.001), 0.0, 1.0)
	var base_alpha: float = minf(_blood_color.a + _extra_alpha * 0.3, 0.92)
	var alpha: float = base_alpha * (1.0 - fade_t * fade_t)

	# Dense core
	var core_col := _blood_color
	core_col.a = alpha * 0.45
	draw_circle(Vector2.ZERO, radius * 0.55, core_col)

	# Asymmetric lobes — simulate pigment tendrils spreading in liquid
	for i in range(7):
		var angle := _seed + float(i) * TAU / 7.0 + sin(_elapsed * 0.06 + float(i)) * 0.15
		var offset_len := radius * lerpf(0.1, 0.3, float(i) / 7.0)
		var offset := Vector2(cos(angle), sin(angle)) * offset_len
		var lobe_col := _blood_color
		lobe_col.a = alpha * lerpf(0.22, 0.10, float(i) / 7.0)
		draw_circle(offset, radius * lerpf(0.38, 0.25, float(i) / 7.0), lobe_col)

	# Soft outer diffusion ring
	var outer_col := _blood_color
	outer_col.a = alpha * 0.05
	if outer_col.a > 0.004:
		draw_circle(Vector2.ZERO, radius * 1.15, outer_col)


## Set the blood color (called after instantiation).
func set_blood_color(color: Color) -> void:
	_blood_color = Color(color.r, color.g, color.b, 0.72)


## Absorb a nearby blood hit: increase intensity and restart the expansion phase.
func absorb() -> void:
	_extra_alpha = minf(_extra_alpha + 0.2, 1.0)
	_absorbed_hits += 1
	_tint_started = false
	if _elapsed > EXPAND_DURATION:
		_elapsed = EXPAND_DURATION


func get_effect_duration() -> float:
	return DURATION
