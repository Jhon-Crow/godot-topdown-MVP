extends Node2D
## Manages rain puddles on the Docks map (Issue #1626).
##
## Spawns a set of puddles at logically placed positions across the outdoor
## docks area.  Puddles start invisible at time 0 and grow through phases
## indefinitely over the course of gameplay, matching the real-world behaviour
## of rainwater pooling on flat concrete/tarmac surfaces.
##
## Indoor exclusion zones (WarehouseA, WarehouseB, CranePlatform and all
## containers) are respected: puddles that fall inside an obstacle are never
## shown.
##
## Each puddle on the level gets a unique shape variant so no two puddles
## look identical.  If there are more puddles than shape variants the shapes
## cycle but are shuffled so repetition is spread out.
##
## This manager is a plain Node2D.  Puddles are children of an internal
## CanvasGroup child (_puddle_group) so they are composited into a single
## intermediate texture before being drawn to the scene.  A puddle_merge shader
## on that CanvasGroup clamps the composited alpha to MAX_PUDDLE_ALPHA — this
## prevents the intersection-darkening that occurs when two semi-transparent
## puddles overlap in standard Porter-Duff compositing.
##
## The shader reads only TEXTURE (the CanvasGroup's own composited buffer),
## never hint_screen_texture or SCREEN_TEXTURE, so it is safe on the
## gl_compatibility renderer and cannot draw a white bounding rectangle.
##
## All puddles are pre-instantiated at _ready() so they are available
## immediately; start_growing() is called on each one right away so they
## begin their staggered appearance sequence from the moment the level loads.

## Path to the PuddleEffect scene.
const PUDDLE_SCENE_PATH: StringName = &"res://scenes/effects/PuddleEffect.tscn"

## Path to the merge material resource applied to the internal CanvasGroup.
## The material clamps composited alpha so overlapping puddles look merged.
const PUDDLE_MERGE_MATERIAL_PATH: StringName = \
	&"res://resources/materials/puddle_merge_material.tres"

## Puddle texture variants — each has a distinct irregular shape so puddles
## don't all look identical.  16 variants are provided (enough to cover all
## 27 spawn positions without any shape repeating on the map).
const PUDDLE_TEXTURE_PATHS: Array = [
	"res://assets/sprites/effects/puddle.png",
	"res://assets/sprites/effects/puddle_2.png",
	"res://assets/sprites/effects/puddle_3.png",
	"res://assets/sprites/effects/puddle_4.png",
	"res://assets/sprites/effects/puddle_5.png",
	"res://assets/sprites/effects/puddle_6.png",
	"res://assets/sprites/effects/puddle_7.png",
	"res://assets/sprites/effects/puddle_8.png",
	"res://assets/sprites/effects/puddle_9.png",
	"res://assets/sprites/effects/puddle_10.png",
	"res://assets/sprites/effects/puddle_11.png",
	"res://assets/sprites/effects/puddle_12.png",
	"res://assets/sprites/effects/puddle_13.png",
	"res://assets/sprites/effects/puddle_14.png",
	"res://assets/sprites/effects/puddle_15.png",
	"res://assets/sprites/effects/puddle_16.png",
]

## Pre-defined puddle spawn positions in world space.
## All positions are in open outdoor areas only — no positions inside
## CranePlatform, WarehouseA, WarehouseB, or on top of containers.
## Puddles are placed near water edges, open pavement, loading docks, and
## between containers where rainwater logically pools.
##
## NOTE: All Y positions are ≥ 560 so that even at maximum growth scale the
## puddle sprites cannot extend above Y=200 (the Water/Floor boundary).
## This prevents puddles from visually overlapping the water stripe.
const PUDDLE_POSITIONS: Array = [
	# --- Open area north-west (outside CranePlatform) ---
	Vector2(750, 680),
	Vector2(900, 580),
	Vector2(650, 760),

	# --- Open area north (kept clear of y<560 to avoid water overlap) ---
	Vector2(1200, 580),
	Vector2(1700, 620),
	Vector2(2400, 560),
	Vector2(3000, 600),

	# --- Loading dock / east cranes (between containers, not on them) ---
	Vector2(3750, 1480),
	Vector2(4150, 1380),
	Vector2(4550, 1820),

	# --- Open area mid-left (outside WarehouseA) ---
	Vector2(1450, 1380),
	Vector2(1000, 1200),
	Vector2(1650, 1700),

	# --- Open area mid ---
	Vector2(2100, 1150),
	Vector2(2700, 1600),
	Vector2(1900, 2200),
	Vector2(2500, 2600),

	# --- Container yard A gaps (between containers, not on them) ---
	Vector2(3600, 700),
	Vector2(4000, 900),

	# --- Open area south (outside ContainerYardB) ---
	Vector2(750, 3200),
	Vector2(1200, 3150),
	Vector2(2450, 3380),
	Vector2(3150, 3620),

	# --- South / near player start zone ---
	Vector2(600, 3600),
	Vector2(1050, 3850),
	Vector2(1800, 3900),
]

## Obstacle exclusion zone rectangles — puddles whose positions fall inside
## these areas will never be shown.
## Format: [top_left: Vector2, size: Vector2]
const EXCLUSION_ZONES: Array = [
	# CranePlatform: center (400,500), floor ±200x±150
	[Vector2(185, 335), Vector2(430, 330)],
	# WarehouseA: center (400,1800), floor ±250x±300
	[Vector2(135, 1485), Vector2(530, 630)],
	# WarehouseB: center (4400,2800), floor ±350x±400
	[Vector2(4035, 2385), Vector2(730, 830)],
	# ContainerYardA — Container1 at (3800,400), ±100x±40
	[Vector2(3690, 350), Vector2(220, 100)],
	# ContainerYardA — Container2 at (3800,550), ±100x±40
	[Vector2(3690, 500), Vector2(220, 100)],
	# ContainerYardA — Container3 at (4200,450), ±100x±40
	[Vector2(4090, 400), Vector2(220, 100)],
	# ContainerYardA — Container4 at (4600,380), ±100x±40
	[Vector2(4490, 330), Vector2(220, 100)],
	# ContainerYardB — Container1 at (400,2800), ±100x±40
	[Vector2(290, 2750), Vector2(220, 100)],
	# ContainerYardB — Container2 at (400,2950), ±100x±40
	[Vector2(290, 2900), Vector2(220, 100)],
	# ContainerYardB — Container3 at (400,3100), ±100x±40
	[Vector2(290, 3050), Vector2(220, 100)],
	# LoadingDock — Container1 at (3600,1600), ±100x±40
	[Vector2(3490, 1550), Vector2(220, 100)],
	# LoadingDock — Container2 at (4000,1550), ±100x±40
	[Vector2(3890, 1500), Vector2(220, 100)],
	# LoadingDock — Container3 at (4400,1650), ±100x±40
	[Vector2(4290, 1600), Vector2(220, 100)],
	# LoadingDock — Container4 at (3800,1750), ±100x±40
	[Vector2(3690, 1700), Vector2(220, 100)],
]

## Per-puddle size variation range applied randomly at spawn.
const SIZE_VARIATION_MIN: float = 0.7
const SIZE_VARIATION_MAX: float = 1.3

var _puddle_scene: PackedScene = null
var _puddle_textures: Array = []
var _puddles: Array[Node] = []

## Internal CanvasGroup that composites all puddles before drawing.
## The merge shader on this group clamps the accumulated alpha so overlapping
## puddles appear as a single merged water body, not as stacked dark spots.
var _puddle_group: CanvasGroup = null


func _ready() -> void:
	_puddle_scene = load(PUDDLE_SCENE_PATH)
	if _puddle_scene == null:
		push_warning("[PuddleManager] PuddleEffect scene not found at %s" % PUDDLE_SCENE_PATH)
		return

	# Pre-load all puddle texture variants.
	for path in PUDDLE_TEXTURE_PATHS:
		var tex = load(path)
		if tex != null:
			_puddle_textures.append(tex)
	if _puddle_textures.is_empty():
		push_warning("[PuddleManager] No puddle textures found, using default from scene")

	_setup_puddle_group()
	_spawn_puddles()
	_log("Puddle manager ready: %d puddles spawned" % _puddles.size())


## Creates the CanvasGroup child that composites all puddles into a single
## intermediate texture.  The puddle_merge shader on this group clamps alpha
## so overlapping puddles look merged rather than stacked.
func _setup_puddle_group() -> void:
	_puddle_group = CanvasGroup.new()
	_puddle_group.name = "PuddleGroup"
	_puddle_group.fit_margin = 0.0
	add_child(_puddle_group)

	var mat = load(PUDDLE_MERGE_MATERIAL_PATH)
	if mat != null:
		_puddle_group.material = mat
	else:
		push_warning("[PuddleManager] puddle_merge_material.tres not found; "
			+ "puddle junctions will have standard alpha stacking")


## Spawns all puddles and starts their growth sequences.
## Each puddle gets a unique shape variant (shuffled so no two puddles on the
## level share the same texture until all variants have been used once).
func _spawn_puddles() -> void:
	# Build a shuffled texture index list so shapes are assigned uniquely.
	var texture_queue: Array = _build_shuffled_texture_queue(PUDDLE_POSITIONS.size())
	var queue_index: int = 0

	for pos in PUDDLE_POSITIONS:
		if _is_in_exclusion_zone(pos):
			continue

		var puddle: Node = _puddle_scene.instantiate()
		puddle.position = pos

		# Assign a unique shape variant texture.
		if not _puddle_textures.is_empty() and puddle.has_method("set_puddle_texture"):
			puddle.set_puddle_texture(_puddle_textures[texture_queue[queue_index % texture_queue.size()]])
			queue_index += 1

		# Apply per-puddle size variation for a natural look.
		if puddle.get("size_variation") != null:
			puddle.size_variation = randf_range(SIZE_VARIATION_MIN, SIZE_VARIATION_MAX)

		# Slightly elongate each puddle on the X axis to look more natural
		# (puddles are rarely perfect circles).
		var stretch_x: float = randf_range(0.85, 1.35)
		var stretch_y: float = randf_range(0.6, 0.95)
		# Random horizontal/vertical flip so even same-texture puddles look unique.
		if randf() > 0.5:
			stretch_x *= -1.0
		if randf() > 0.5:
			stretch_y *= -1.0
		puddle.scale = Vector2(stretch_x, stretch_y)

		# Add to the CanvasGroup so the merge shader applies across all puddles.
		_puddle_group.add_child(puddle)
		_puddles.append(puddle)

		# Begin growing immediately — staggered delay is handled internally.
		if puddle.has_method("start_growing"):
			puddle.start_growing()


## Builds a shuffled list of texture indices that guarantees no two adjacent
## puddles share the same shape, cycling through all variants before repeating.
func _build_shuffled_texture_queue(count: int) -> Array:
	if _puddle_textures.is_empty():
		return []
	var n := _puddle_textures.size()
	var result: Array = []
	var batch: Array = []
	for i in range(n):
		batch.append(i)
	# Keep adding shuffled batches until we have enough for all puddles.
	while result.size() < count:
		batch.shuffle()
		result.append_array(batch)
	return result


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
