extends Node2D
## Blood diffusion effect for water (Issue #1445).
##
## When blood enters the water, instead of leaving footprints it spreads
## as a slowly expanding, fading color cloud. Drawn procedurally with
## draw_circle() — no textures needed.

class_name WaterBloodDiffusion

## Maximum radius the blood cloud expands to.
const MAX_RADIUS: float = 45.0

## Duration of the expansion + fade effect in seconds.
const DURATION: float = 4.0

## Duration of the initial fast expansion phase.
const EXPAND_DURATION: float = 1.5

## Blood color (set by WaterBody when spawning).
var _blood_color: Color = Color(0.5, 0.02, 0.02, 0.55)

## Elapsed time since spawn.
var _elapsed: float = 0.0

## Whether the effect has finished.
var _done: bool = false


func _ready() -> void:
	# Render at the same level as water visual, below characters
	z_index = 1


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION and not _done:
		_done = true
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	if _done:
		return

	var t: float = _elapsed / DURATION  # 0 → 1

	# Radius expands quickly at first, then slows (ease-out)
	var expand_t: float = clampf(_elapsed / EXPAND_DURATION, 0.0, 1.0)
	var radius: float = MAX_RADIUS * (1.0 - pow(1.0 - expand_t, 3.0))

	# Alpha fades out over the full duration
	var alpha: float = _blood_color.a * (1.0 - t * t)

	# Draw multiple concentric translucent circles for a soft cloud look
	var col: Color = _blood_color
	for i in range(3):
		var ring_radius: float = radius * (0.4 + 0.3 * i)
		col.a = alpha * (1.0 - 0.25 * i)
		if col.a > 0.01:
			draw_circle(Vector2.ZERO, ring_radius, col)


## Set the blood color (called by WaterBody after instantiation).
func set_blood_color(color: Color) -> void:
	_blood_color = Color(color.r, color.g, color.b, 0.55)
