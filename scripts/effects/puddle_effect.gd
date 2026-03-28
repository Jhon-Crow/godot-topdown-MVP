extends Sprite2D
## Rain puddle that gradually grows on the Docks map (Issue #1626).
##
## Puddles appear from the start of the level and grow indefinitely through
## continuous size phases at a slow rate:
##   - Phase 1 (0–60 s): small puddle appears (scale 0 → SMALL_SCALE)
##   - Phase 2 (60–120 s): grows to medium size (SMALL_SCALE → MEDIUM_SCALE)
##   - Phase 3 (120 s+): continues growing without limit, one step at a time
##
## Growth speed is intentionally slow — half the original rate — so puddles
## accumulate gradually over the course of gameplay.
##
## Visual appearance: semi-transparent gray, z_index = 0 so obstacles/
## structures render above puddles (structures use z_index = 2).
class_name PuddleEffect

## Scale at the end of the initial appearance phase (0 → small).
const SMALL_SCALE: float = 0.4

## Scale after phase-2 growth (small → medium).
const MEDIUM_SCALE: float = 0.85

## How much scale is added per unbounded growth step after phase 2.
const GROWTH_STEP: float = 0.45

## Duration (seconds) of the initial fade-in / appear animation.
## (doubled from original 8 s → 16 s for half speed)
const APPEAR_DURATION: float = 16.0

## Duration (seconds) of the phase-2 growth tween.
## (doubled from original 20 s → 40 s for half speed)
const GROW_TO_MEDIUM_DURATION: float = 40.0

## Duration (seconds) of each unbounded growth step after phase 2.
## (doubled from original 25 s → 50 s for half speed)
const GROW_STEP_DURATION: float = 50.0

## Randomisation window (seconds) applied to each puddle's start delay so
## puddles do not all appear at the exact same time.
@export var start_delay_randomise: float = 15.0

## Per-puddle size variation multiplier (set by PuddleManager, range 0.7–1.3).
@export var size_variation: float = 1.0

## Track current accumulated scale for unbounded growth.
var _current_scale: float = 0.0


## Assigns a specific texture to this puddle sprite (called by PuddleManager
## before start_growing() to give each puddle a different shape).
func set_puddle_texture(tex: Texture2D) -> void:
	texture = tex


func _ready() -> void:
	# Start invisible and at zero scale; will grow via start_growing().
	scale = Vector2.ZERO
	modulate.a = 0.0
	_current_scale = 0.0


## Begins the puddle growth sequence.
## Call this once the level is ready (e.g. from PuddleManager).
## Puddles grow indefinitely — there is no maximum size cap.
func start_growing() -> void:
	# Randomise the initial delay so puddles appear at staggered times.
	var delay: float = randf() * start_delay_randomise
	await get_tree().create_timer(delay).timeout

	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Phase 1: fade in and grow to small size.
	# Small puddles are very transparent — the floor should clearly show through.
	_current_scale = SMALL_SCALE * size_variation
	var target_small := Vector2.ONE * _current_scale
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", target_small, APPEAR_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.35, APPEAR_DURATION * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished

	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Phase 2: grow to medium size, become slightly more opaque.
	_current_scale = MEDIUM_SCALE * size_variation
	var target_medium := Vector2.ONE * _current_scale
	var tween2 := create_tween().set_parallel(true)
	tween2.tween_property(self, "scale", target_medium, GROW_TO_MEDIUM_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween2.tween_property(self, "modulate:a", 0.45, GROW_TO_MEDIUM_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween2.finished

	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Phase 3+: grow indefinitely, one step at a time.
	# Each step increases scale by GROWTH_STEP, with no upper bound.
	while is_instance_valid(self) and is_inside_tree():
		_current_scale += GROWTH_STEP * size_variation
		var target_next := Vector2.ONE * _current_scale
		var tween3 := create_tween().set_parallel(true)
		tween3.tween_property(self, "scale", target_next, GROW_STEP_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		# Gradually increase opacity as the puddle grows larger, cap at 0.7.
		var next_alpha: float = minf(0.70, modulate.a + 0.05)
		tween3.tween_property(self, "modulate:a", next_alpha, GROW_STEP_DURATION)
		await tween3.finished


## Immediately hides the puddle (e.g. when entering an indoor area).
func hide_puddle() -> void:
	visible = false


## Shows the puddle again after leaving an indoor area.
func show_puddle() -> void:
	visible = true
