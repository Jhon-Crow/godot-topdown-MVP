extends RefCounted
class_name WallBreachHelper
## Shared helper for carving passages through StaticBody2D walls (Issues #1043, #1131).
##
## Used by BreachingChargesEffect (active item) and RpgRocket (projectile) to open
## a consistent-width passage in a wall at a given world-space hit position.
##
## The passage is BREACH_PASSAGE_WIDTH pixels wide, carved perpendicular to the wall's
## long axis.  Thin walls (shorter than the passage in the split axis) are made fully
## passable with a faded visual instead of being split.
##
## Safe to call multiple times on the same wall (e.g. two rockets hit the same wall).
## Each call disables ALL existing collision shapes (including segment shapes from prior
## breaches) and removes prior dynamic visual nodes before placing new ones.
## This prevents invisible-wall "ghost" shapes that blocked movement after multiple
## RPG hits on the same wall (Issue #1144 follow-up).

## Width of the passage carved through a wall (pixels).
## Must match BreachingChargesEffect.BREACH_PASSAGE_WIDTH for consistent feel.
const BREACH_PASSAGE_WIDTH: float = 120.0

## Minimum segment length to keep after splitting; smaller segments are dropped.
const MIN_SEGMENT_SIZE: float = 8.0

## Metadata key used to mark dynamically-added collision/visual nodes created by this helper.
## Allows cleanup of prior-breach remnants when the same wall is breached again.
const DYNAMIC_NODE_META: StringName = &"wall_breach_dynamic"


## Carve a passage through a StaticBody2D wall at the given world-space position.
##
## @param wall            The StaticBody2D to modify (must not be null).
## @param breach_world_pos  World-space point where the passage should be centered
##                          (typically the impact/explosion position).
static func open_wall_passage(wall: Node, breach_world_pos: Vector2) -> void:
	if wall == null or not is_instance_valid(wall):
		FileLogger.info("[WallBreachHelper] WARNING: invalid wall reference, skipping")
		return

	# Remove dynamic nodes added by any previous breach on this same wall.
	# This cleans up ghost collision shapes and stale visual segments.
	_remove_dynamic_nodes(wall)

	# Find the original RectangleShape2D collision child to determine wall dimensions.
	# We look for the shape with the LARGEST area — this is the original full-wall shape
	# even if it was disabled by a previous breach call.
	var col_shape: CollisionShape2D = null
	var largest_area: float = -1.0
	for child in wall.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape is RectangleShape2D:
			var s: RectangleShape2D = (child as CollisionShape2D).shape as RectangleShape2D
			var area := s.size.x * s.size.y
			if area > largest_area:
				largest_area = area
				col_shape = child as CollisionShape2D

	# Disable ALL existing collision shapes (original + any remaining from prior breaches).
	# This prevents invisible-wall ghost shapes left by repeated calls on the same wall.
	for child in wall.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).disabled = true
		elif child is CollisionPolygon2D:
			(child as CollisionPolygon2D).disabled = true

	# Fallback: all shapes disabled above; just fade visuals if no RectangleShape2D found.
	if col_shape == null:
		_fade_wall_visuals(wall)
		FileLogger.info("[WallBreachHelper] Fallback: disabled all shapes on '%s'" % wall.name)
		return

	var rect_shape: RectangleShape2D = col_shape.shape as RectangleShape2D
	var wall_size: Vector2 = rect_shape.size

	# Breach point in wall-local coordinates.
	var breach_local: Vector2 = wall.to_local(breach_world_pos)

	var half_w: float = wall_size.x * 0.5
	var half_h: float = wall_size.y * 0.5
	var half_breach: float = BREACH_PASSAGE_WIDTH * 0.5

	# Determine orientation: wide walls split along X, tall walls along Y.
	var is_horizontal: bool = wall_size.x >= wall_size.y

	if is_horizontal:
		# Thin wall (shorter than one passage width) — make fully passable.
		if wall_size.x < BREACH_PASSAGE_WIDTH:
			_fade_wall_visuals(wall)
			FileLogger.info("[WallBreachHelper] Thin wall '%s' breached (fully passable)" % wall.name)
			return

		# Snap breach centre toward the nearest end for corner placements.
		var bx: float = breach_local.x
		bx = clampf(bx, -half_w + half_breach, half_w - half_breach)

		var left_end: float = bx - half_breach
		var right_start: float = bx + half_breach

		var left_width: float = left_end + half_w
		var right_width: float = half_w - right_start

		# Short wall — make fully passable.
		if left_width < MIN_SEGMENT_SIZE and right_width < MIN_SEGMENT_SIZE:
			_fade_wall_visuals(wall)
			FileLogger.info("[WallBreachHelper] Short wall '%s' breached (fully passable)" % wall.name)
			return

		if left_width >= MIN_SEGMENT_SIZE:
			var left_shape := RectangleShape2D.new()
			left_shape.size = Vector2(left_width, wall_size.y)
			var left_col := CollisionShape2D.new()
			left_col.shape = left_shape
			left_col.position = Vector2(-half_w + left_width * 0.5, 0.0)
			left_col.set_meta(DYNAMIC_NODE_META, true)
			wall.add_child(left_col)

		if right_width >= MIN_SEGMENT_SIZE:
			var right_shape := RectangleShape2D.new()
			right_shape.size = Vector2(right_width, wall_size.y)
			var right_col := CollisionShape2D.new()
			right_col.shape = right_shape
			right_col.position = Vector2(half_w - right_width * 0.5, 0.0)
			right_col.set_meta(DYNAMIC_NODE_META, true)
			wall.add_child(right_col)

		_split_visual_horizontal(wall, bx, half_w, half_h)

		FileLogger.info("[WallBreachHelper] Horizontal passage in '%s' at local x=%.0f (width %.0fpx)" % [
			wall.name, bx, BREACH_PASSAGE_WIDTH
		])
	else:
		# Thin wall (shorter than one passage height) — make fully passable.
		if wall_size.y < BREACH_PASSAGE_WIDTH:
			_fade_wall_visuals(wall)
			FileLogger.info("[WallBreachHelper] Thin wall '%s' breached (fully passable)" % wall.name)
			return

		var by: float = breach_local.y
		by = clampf(by, -half_h + half_breach, half_h - half_breach)

		var top_end: float = by - half_breach
		var bottom_start: float = by + half_breach

		var top_height: float = top_end + half_h
		var bottom_height: float = half_h - bottom_start

		# Short wall — make fully passable.
		if top_height < MIN_SEGMENT_SIZE and bottom_height < MIN_SEGMENT_SIZE:
			_fade_wall_visuals(wall)
			FileLogger.info("[WallBreachHelper] Short wall '%s' breached (fully passable)" % wall.name)
			return

		if top_height >= MIN_SEGMENT_SIZE:
			var top_shape := RectangleShape2D.new()
			top_shape.size = Vector2(wall_size.x, top_height)
			var top_col := CollisionShape2D.new()
			top_col.shape = top_shape
			top_col.position = Vector2(0.0, -half_h + top_height * 0.5)
			top_col.set_meta(DYNAMIC_NODE_META, true)
			wall.add_child(top_col)

		if bottom_height >= MIN_SEGMENT_SIZE:
			var bot_shape := RectangleShape2D.new()
			bot_shape.size = Vector2(wall_size.x, bottom_height)
			var bot_col := CollisionShape2D.new()
			bot_col.shape = bot_shape
			bot_col.position = Vector2(0.0, half_h - bottom_height * 0.5)
			bot_col.set_meta(DYNAMIC_NODE_META, true)
			wall.add_child(bot_col)

		_split_visual_vertical(wall, by, half_w, half_h)

		FileLogger.info("[WallBreachHelper] Vertical passage in '%s' at local y=%.0f (height %.0fpx)" % [
			wall.name, by, BREACH_PASSAGE_WIDTH
		])


## Remove all dynamically-added nodes from a prior breach on this wall.
## Only nodes tagged with DYNAMIC_NODE_META are removed; original scene nodes are untouched.
static func _remove_dynamic_nodes(wall: Node) -> void:
	for child in wall.get_children():
		if child.has_meta(DYNAMIC_NODE_META):
			child.queue_free()


## Fade all CanvasItem children to alpha 0.25 to show the wall is breached
## without removing it from the scene entirely.
static func _fade_wall_visuals(wall: Node) -> void:
	for child in wall.get_children():
		if child is CanvasItem:
			(child as CanvasItem).modulate = Color(1.0, 1.0, 1.0, 0.25)


## Split horizontal wall visuals into left and right segments with a gap.
static func _split_visual_horizontal(wall: Node, breach_cx: float, half_w: float, half_h: float) -> void:
	var wall_color := Color(0.35, 0.28, 0.22, 1.0)
	for child in wall.get_children():
		if child is ColorRect:
			wall_color = (child as ColorRect).color
			(child as ColorRect).visible = false
		elif child is Sprite2D:
			(child as Sprite2D).visible = false
		elif child is LightOccluder2D:
			# Disable light occlusion in the passage gap so no shadow remains (Issue #1144).
			(child as LightOccluder2D).visible = false

	var half_breach: float = BREACH_PASSAGE_WIDTH * 0.5
	var bx: float = clampf(breach_cx, -half_w + half_breach, half_w - half_breach)

	var left_width: float = bx - half_breach + half_w
	var right_width: float = half_w - (bx + half_breach)
	var wall_height: float = half_h * 2.0

	if left_width >= MIN_SEGMENT_SIZE:
		var cr := ColorRect.new()
		cr.size = Vector2(left_width, wall_height)
		cr.position = Vector2(-half_w, -half_h)
		cr.color = wall_color
		cr.set_meta(DYNAMIC_NODE_META, true)
		wall.add_child(cr)

	if right_width >= MIN_SEGMENT_SIZE:
		var cr := ColorRect.new()
		cr.size = Vector2(right_width, wall_height)
		cr.position = Vector2(half_w - right_width, -half_h)
		cr.color = wall_color
		cr.set_meta(DYNAMIC_NODE_META, true)
		wall.add_child(cr)


## Split vertical wall visuals into top and bottom segments with a gap.
static func _split_visual_vertical(wall: Node, breach_cy: float, half_w: float, half_h: float) -> void:
	var wall_color := Color(0.35, 0.28, 0.22, 1.0)
	for child in wall.get_children():
		if child is ColorRect:
			wall_color = (child as ColorRect).color
			(child as ColorRect).visible = false
		elif child is Sprite2D:
			(child as Sprite2D).visible = false
		elif child is LightOccluder2D:
			# Disable light occlusion in the passage gap so no shadow remains (Issue #1144).
			(child as LightOccluder2D).visible = false

	var half_breach: float = BREACH_PASSAGE_WIDTH * 0.5
	var by: float = clampf(breach_cy, -half_h + half_breach, half_h - half_breach)

	var top_height: float = by - half_breach + half_h
	var bottom_height: float = half_h - (by + half_breach)
	var wall_width: float = half_w * 2.0

	if top_height >= MIN_SEGMENT_SIZE:
		var cr := ColorRect.new()
		cr.size = Vector2(wall_width, top_height)
		cr.position = Vector2(-half_w, -half_h)
		cr.color = wall_color
		cr.set_meta(DYNAMIC_NODE_META, true)
		wall.add_child(cr)

	if bottom_height >= MIN_SEGMENT_SIZE:
		var cr := ColorRect.new()
		cr.size = Vector2(wall_width, bottom_height)
		cr.position = Vector2(-half_w, half_h - bottom_height)
		cr.color = wall_color
		cr.set_meta(DYNAMIC_NODE_META, true)
		wall.add_child(cr)
