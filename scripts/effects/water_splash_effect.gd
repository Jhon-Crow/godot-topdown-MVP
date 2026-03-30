extends Node2D
## Expanding ripple / splash that appears when a body moves through water (Issue #1445).
##
## Spawned by WaterBody when the player (or an enemy) walks into or moves inside the
## water area, or when objects (casings, grenades) fall into the water.
## The effect draws concentric circles that expand outward and fade.
## No texture assets required — everything is drawn procedurally with draw_arc().

class_name WaterSplashEffect

## Ripple rings
var ring_count: int = 3
var ring_delay: float = 0.08   # seconds between successive ring spawns
var max_radius: float = 28.0
var ring_duration: float = 0.55 # seconds for a single ring to fully expand + fade

## Visual tunables
const LINE_WIDTH: float = 1.5
var base_color: Color = Color(0.55, 0.78, 0.92, 0.65)

## Per-ring state: [elapsed, start_delay]
var _rings: Array = []

## Whether the effect has been fully consumed (all rings finished)
var _done: bool = false


func _ready() -> void:
	for i in range(ring_count):
		_rings.append({"elapsed": 0.0, "delay": i * ring_delay, "alive": false})
	# Render below characters (player body z=1, head z=3) but above water visual (z=1)
	# Using z_index = 0 so it renders at base level, below any character parts
	z_index = 0


func _process(delta: float) -> void:
	var all_done: bool = true
	for ring in _rings:
		ring["elapsed"] += delta
		if ring["elapsed"] >= ring["delay"]:
			ring["alive"] = true
		# Check if this ring is still running
		var ring_elapsed: float = ring["elapsed"] - ring["delay"]
		if ring_elapsed < ring_duration:
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
		if ring_elapsed < 0.0 or ring_elapsed > ring_duration:
			continue

		var t: float = ring_elapsed / ring_duration           # 0 → 1
		var radius: float = t * max_radius
		var alpha: float = (1.0 - t) * base_color.a           # fade out

		var col: Color = base_color
		col.a = alpha
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, col, LINE_WIDTH)


## Configure splash for smaller objects (casings, small impacts).
func configure_small() -> void:
	ring_count = 2
	ring_delay = 0.06
	max_radius = 14.0
	ring_duration = 0.35
	base_color = Color(0.55, 0.78, 0.92, 0.5)
	# Rebuild rings
	_rings.clear()
	for i in range(ring_count):
		_rings.append({"elapsed": 0.0, "delay": i * ring_delay, "alive": false})


## Configure splash for large impacts (grenades, explosions).
func configure_large() -> void:
	ring_count = 5
	ring_delay = 0.06
	max_radius = 60.0
	ring_duration = 0.8
	base_color = Color(0.55, 0.78, 0.92, 0.75)
	# Rebuild rings
	_rings.clear()
	for i in range(ring_count):
		_rings.append({"elapsed": 0.0, "delay": i * ring_delay, "alive": false})
