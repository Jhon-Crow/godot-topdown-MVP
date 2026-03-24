extends Node2D
## Expanding ripple / splash that appears when a body moves through water (Issue #1445).
##
## Spawned by WaterBody when the player (or an enemy) walks into or moves inside the
## water area.  The effect draws three concentric circles that expand outward and fade.
## No texture assets required — everything is drawn procedurally with draw_arc().

class_name WaterSplashEffect

## Ripple rings
const RING_COUNT: int = 3
const RING_DELAY: float = 0.08   # seconds between successive ring spawns
const MAX_RADIUS: float = 28.0
const RING_DURATION: float = 0.55 # seconds for a single ring to fully expand + fade

## Visual tunables
const LINE_WIDTH: float = 2.0
const BASE_COLOR: Color = Color(0.75, 0.92, 1.0, 0.8)

## Per-ring state: [elapsed, start_delay]
var _rings: Array = []

## Whether the effect has been fully consumed (all rings finished)
var _done: bool = false


func _ready() -> void:
	for i in range(RING_COUNT):
		_rings.append({"elapsed": 0.0, "delay": i * RING_DELAY, "alive": false})
	z_index = 3  # Above water, below characters


func _process(delta: float) -> void:
	var all_done: bool = true
	for ring in _rings:
		ring["elapsed"] += delta
		if ring["elapsed"] >= ring["delay"]:
			ring["alive"] = true
		# Check if this ring is still running
		var ring_elapsed: float = ring["elapsed"] - ring["delay"]
		if ring_elapsed < RING_DURATION:
			all_done = false

	if all_done and not _done:
		_done = true
		queue_free()
	else:
		queue_redraw()


func _draw() -> void:
	for ring in _rings:
		if not ring["alive"]:
			continue
		var ring_elapsed: float = ring["elapsed"] - ring["delay"]
		if ring_elapsed < 0.0 or ring_elapsed > RING_DURATION:
			continue

		var t: float = ring_elapsed / RING_DURATION           # 0 → 1
		var radius: float = t * MAX_RADIUS
		var alpha: float = (1.0 - t) * BASE_COLOR.a           # fade out

		var col: Color = BASE_COLOR
		col.a = alpha
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, col, LINE_WIDTH)
