extends Node2D
## Manages rain puddles on the Docks map (Issue #1626).
##
## Spawns a set of puddles at logically placed positions across the outdoor
## docks area.  Puddles start invisible at time 0 and grow through three
## phases over the first ~60+ seconds of gameplay, matching the real-world
## behaviour of rainwater pooling on flat concrete/tarmac surfaces.
##
## Indoor exclusion zones (WarehouseA and WarehouseB) are respected: puddles
## that fall inside a warehouse are never shown.
##
## All puddles are pre-instantiated at _ready() so they are available
## immediately; start_growing() is called on each one right away so they
## begin their staggered appearance sequence from the moment the level loads.

## Path to the PuddleEffect scene.
const PUDDLE_SCENE_PATH: StringName = &"res://scenes/effects/PuddleEffect.tscn"

## Pre-defined puddle spawn positions in world space.
## Chosen to be logically placed: open outdoor areas, near water edges,
## loading docks, and between containers — places where rainwater pools.
## Positions avoid the two warehouse interiors (WarehouseA ~400,1800 and
## WarehouseB ~4400,2800).
const PUDDLE_POSITIONS: Array = [
	# --- Crane platform / north-west edge (near water) ---
	Vector2(280, 420),
	Vector2(480, 360),
	Vector2(560, 580),

	# --- Open area north ---
	Vector2(1100, 340),
	Vector2(1650, 390),
	Vector2(2400, 300),
	Vector2(3000, 350),

	# --- Loading dock / east cranes ---
	Vector2(3750, 1480),
	Vector2(4150, 1380),
	Vector2(4550, 1620),

	# --- Open area mid-left ---
	Vector2(1450, 1380),
	Vector2(900, 1200),

	# --- Open area mid ---
	Vector2(2100, 1150),
	Vector2(2700, 1600),
	Vector2(1900, 2200),

	# --- Container yard A (between containers, east) ---
	Vector2(3480, 480),
	Vector2(3950, 320),

	# --- Open area south ---
	Vector2(1150, 3150),
	Vector2(2450, 3380),
	Vector2(3150, 3620),

	# --- South / near player start zone ---
	Vector2(380, 3520),
	Vector2(950, 3780),
	Vector2(1700, 3900),
]

## Indoor exclusion zone rectangles (same as used by RainEffect).
## Puddles whose positions fall inside these will be hidden permanently.
const EXCLUSION_ZONES: Array = [
	# WarehouseA (~400, 1800)
	[Vector2(130, 1480), Vector2(540, 640)],
	# WarehouseB (~4400, 2800)
	[Vector2(4030, 2380), Vector2(740, 840)],
]

## Per-puddle size variation range applied randomly at spawn.
const SIZE_VARIATION_MIN: float = 0.7
const SIZE_VARIATION_MAX: float = 1.3

var _puddle_scene: PackedScene = null
var _puddles: Array[Node] = []


func _ready() -> void:
	_puddle_scene = load(PUDDLE_SCENE_PATH)
	if _puddle_scene == null:
		push_warning("[PuddleManager] PuddleEffect scene not found at %s" % PUDDLE_SCENE_PATH)
		return

	_spawn_puddles()
	_log("Puddle manager ready: %d puddles spawned" % _puddles.size())


## Spawns all puddles and starts their growth sequences.
func _spawn_puddles() -> void:
	for pos in PUDDLE_POSITIONS:
		if _is_in_exclusion_zone(pos):
			continue

		var puddle: Node = _puddle_scene.instantiate()
		puddle.position = pos

		# Apply per-puddle size variation for a natural look.
		if puddle.get("size_variation") != null:
			puddle.size_variation = randf_range(SIZE_VARIATION_MIN, SIZE_VARIATION_MAX)

		# Slightly elongate each puddle on the X axis to look more natural
		# (puddles are rarely perfect circles).
		var stretch_x: float = randf_range(0.85, 1.35)
		var stretch_y: float = randf_range(0.6, 0.95)
		puddle.scale = Vector2(stretch_x, stretch_y)

		add_child(puddle)
		_puddles.append(puddle)

		# Begin growing immediately — staggered delay is handled internally.
		if puddle.has_method("start_growing"):
			puddle.start_growing()


## Returns true when a world-space point falls inside any exclusion zone.
func _is_in_exclusion_zone(point: Vector2) -> bool:
	for zone in EXCLUSION_ZONES:
		var rect := Rect2(zone[0], zone[1])
		if rect.has_point(point):
			return true
	return false


func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[PuddleManager] " + message)
	else:
		print("[PuddleManager] " + message)
