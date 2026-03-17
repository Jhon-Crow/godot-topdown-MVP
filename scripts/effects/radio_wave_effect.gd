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


func _physics_process(_delta: float) -> void:
	# Jam player's active items when within jammer_radius and parent enemy is alive (Issue #1036)
	var aim := get_node_or_null("/root/ActiveItemManager")
	if aim == null: return
	# RadioWaveEffect is a child of EnemyModel which is a child of RadioJammerEnemy.
	# Walk up to the actual enemy node (CharacterBody2D with is_alive()).
	var enemy := get_parent().get_parent()
	# If the enemy is not valid or not alive, release the jammer and stop.
	if not is_instance_valid(enemy) or (enemy.has_method("is_alive") and not enemy.is_alive()):
		aim.set_jammed(false)
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty(): return
	var player: Node = players[0]
	if not is_instance_valid(player): return
	var is_in_range: bool = enemy.global_position.distance_to(player.global_position) <= jammer_radius
	aim.set_jammed(is_in_range)


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
