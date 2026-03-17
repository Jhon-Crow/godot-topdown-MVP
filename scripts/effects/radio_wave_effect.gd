extends Node2D
## Animated radio wave effect and jamming logic for the Radio Jammer enemy (Issue #1036).
##
## Draws expanding semi-transparent concentric rings around the enemy
## to visually indicate the jamming field is active.
## Rings expand outward and fade out as they reach full size.
##
## This node also manages the jamming of the player's active items:
## while the parent enemy is alive and the player is within jammer_radius,
## ActiveItemManager.set_jammed(true) is called each physics frame.

## Radius at which a ring is fully faded out (pixels).
const MAX_RING_RADIUS: float = 60.0

## Radius at which a ring starts (pixels).
const MIN_RING_RADIUS: float = 10.0

## Speed at which rings expand outward (pixels/second).
const RING_EXPAND_SPEED: float = 40.0

## Time between spawning new rings (seconds).
const RING_SPAWN_INTERVAL: float = 0.5

## Base color of the radio waves (cyan-ish, semi-transparent).
const RING_COLOR: Color = Color(0.2, 0.8, 1.0, 0.6)

## Line width for drawing rings.
const LINE_WIDTH: float = 2.0

## Radius within which the player's active items are jammed (pixels).
@export var jammer_radius: float = 1000.0

## Internal structure representing one expanding ring.
class Ring:
	var radius: float = 0.0
	var alpha: float = 1.0

## List of active rings.
var _rings: Array[Ring] = []

## Timer accumulator for ring spawning.
var _spawn_timer: float = 0.0


func _ready() -> void:
	# Spawn the first ring immediately so the effect is visible at start
	_spawn_ring()


func _process(delta: float) -> void:
	# Advance all rings
	for ring in _rings:
		ring.radius += RING_EXPAND_SPEED * delta
		# Fade from fully opaque to transparent as it reaches max radius
		var t: float = (ring.radius - MIN_RING_RADIUS) / (MAX_RING_RADIUS - MIN_RING_RADIUS)
		ring.alpha = clampf(1.0 - t, 0.0, 1.0)

	# Remove rings that have finished expanding
	_rings = _rings.filter(func(r: Ring) -> bool: return r.alpha > 0.0)

	# Spawn new rings at the configured interval
	_spawn_timer += delta
	if _spawn_timer >= RING_SPAWN_INTERVAL:
		_spawn_timer -= RING_SPAWN_INTERVAL
		_spawn_ring()

	queue_redraw()


func _physics_process(delta: float) -> void:
	# NOTE (Issue #1036): The authoritative jam check is now in ActiveItemManager.is_active_item_jammed()
	# which queries the scene tree directly each call, eliminating the physics-process race condition
	# where player input could be processed before this update ran in the same physics step.
	# Emit periodic diagnostics to help debug jam state in game logs.
	var active_item_manager := get_node_or_null("/root/ActiveItemManager")
	if active_item_manager and active_item_manager.has_method("log_jammer_diagnostics"):
		active_item_manager.log_jammer_diagnostics(delta)


func _draw() -> void:
	for ring in _rings:
		var color := RING_COLOR
		color.a = RING_COLOR.a * ring.alpha
		draw_arc(Vector2.ZERO, ring.radius, 0.0, TAU, 32, color, LINE_WIDTH, true)


func _spawn_ring() -> void:
	var ring := Ring.new()
	ring.radius = MIN_RING_RADIUS
	ring.alpha = 1.0
	_rings.append(ring)
