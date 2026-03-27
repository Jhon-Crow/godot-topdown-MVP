extends Sprite2D
## Rain puddle that gradually grows on the Docks map (Issue #1626).
##
## Puddles appear from the start of the level and grow through three size phases:
##   - Phase 1 (0–30 s): small puddle appears (scale 0 → SMALL_SCALE)
##   - Phase 2 (30–60 s): grows to normal size (SMALL_SCALE → MEDIUM_SCALE)
##   - Phase 3 (60 s+):   grows to large size  (MEDIUM_SCALE → LARGE_SCALE)
##
## Visual appearance: semi-transparent blue-grey radial gradient, z_index = -1
## so puddles render below characters but above the floor.
class_name PuddleEffect

## Maximum scale multiplier for the initial appearance tween (0 → small).
const SMALL_SCALE: float = 0.4

## Scale after phase-2 growth (small → medium, at 30 s).
const MEDIUM_SCALE: float = 0.85

## Final large scale (medium → large, at 60 s).
const LARGE_SCALE: float = 1.4

## Duration (seconds) of the initial fade-in / appear animation.
const APPEAR_DURATION: float = 8.0

## Duration (seconds) of the phase-2 growth tween.
const GROW_TO_MEDIUM_DURATION: float = 20.0

## Duration (seconds) of the phase-3 growth tween.
const GROW_TO_LARGE_DURATION: float = 25.0

## Randomisation window (seconds) applied to each puddle's start delay so
## puddles do not all appear at the exact same time.
@export var start_delay_randomise: float = 10.0

## Per-puddle size variation multiplier (set by PuddleManager, range 0.7–1.3).
@export var size_variation: float = 1.0


func _ready() -> void:
	# Start invisible and at zero scale; will grow via _start_growing().
	scale = Vector2.ZERO
	modulate.a = 0.0


## Begins the puddle growth sequence.
## Call this once the level is ready (e.g. from PuddleManager).
func start_growing() -> void:
	# Randomise the initial delay so puddles appear at staggered times.
	var delay: float = randf() * start_delay_randomise
	await get_tree().create_timer(delay).timeout

	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Phase 1: fade in and grow to small size.
	var target_small := Vector2.ONE * SMALL_SCALE * size_variation
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", target_small, APPEAR_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.72, APPEAR_DURATION * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tween.finished

	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Wait until 30 s mark before growing further (accounting for start delay).
	var wait_to_medium: float = maxf(0.0, 30.0 - delay - APPEAR_DURATION)
	if wait_to_medium > 0.0:
		await get_tree().create_timer(wait_to_medium).timeout

	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Phase 2: grow to medium size.
	var target_medium := Vector2.ONE * MEDIUM_SCALE * size_variation
	var tween2 := create_tween()
	tween2.tween_property(self, "scale", target_medium, GROW_TO_MEDIUM_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween2.finished

	if not is_instance_valid(self) or not is_inside_tree():
		return

	# Phase 3: grow to large size.
	var target_large := Vector2.ONE * LARGE_SCALE * size_variation
	var tween3 := create_tween()
	tween3.tween_property(self, "scale", target_large, GROW_TO_LARGE_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Large puddles become slightly more opaque as they grow.
	tween3.parallel().tween_property(self, "modulate:a", 0.85, GROW_TO_LARGE_DURATION)


## Immediately hides the puddle (e.g. when entering an indoor area).
func hide_puddle() -> void:
	visible = false


## Shows the puddle again after leaving an indoor area.
func show_puddle() -> void:
	visible = true
