extends Node2D
## Snow footprint decal that persists on the snow ground (Issue #1627).
##
## Rendered procedurally with _draw() — no external texture needed.
## Shows as a compressed boot-shaped indentation in the snow (slightly darker,
## blue-grey tinted oval) that stays visible until the level reloads.
## Supports left/right foot offsets for realistic alternating prints.
class_name SnowFootprint

## Alpha of the footprint (set at spawn time by SnowFeetComponent).
var _alpha: float = 0.72

## Whether this is a left foot (true) or right foot (false).
## Used to mirror the footprint shape.
var _is_left: bool = true

## Rotation offset for alignment with character facing direction.
## Set from SnowFeetComponent before adding to scene.
## (node rotation is set by spawner)

## Compressed snow colour — slightly darker and bluer than the surface.
const SNOW_INDENT_COLOR: Color = Color(0.64, 0.70, 0.80, 1.0)

## Shadow rim colour — very subtle darker edge.
const SNOW_RIM_COLOR: Color = Color(0.54, 0.60, 0.72, 1.0)


func _ready() -> void:
	# Render above snow background (z_index 0) but below characters (z_index 1).
	# Use z_index 1 so footprints are drawn on top of the snow surface.
	z_index = 1


func _draw() -> void:
	# Draw a simple boot-print shape as two overlapping ellipses:
	# - Heel: small ellipse at the back
	# - Toe: slightly larger ellipse at the front
	# The shape is in local coordinates; rotation is applied via the node transform.

	var mirror: float = 1.0 if _is_left else -1.0

	# Colours with current alpha.
	var fill: Color = SNOW_INDENT_COLOR
	fill.a = _alpha
	var rim: Color = SNOW_RIM_COLOR
	rim.a = _alpha * 0.6

	# Toe ellipse (forward — negative Y in top-down because +Y is down).
	_draw_ellipse(Vector2(mirror * 2.5, -7.0), 4.5, 6.5, rim, fill)

	# Heel ellipse.
	_draw_ellipse(Vector2(mirror * 1.0, 5.0), 3.5, 4.5, rim, fill)


## Draws a filled ellipse with a subtle darker rim.
## center: local-space centre; rx/ry: half-axes; rim_col/fill_col: colours.
func _draw_ellipse(center: Vector2, rx: float, ry: float, rim_col: Color, fill_col: Color) -> void:
	const SEGMENTS: int = 14
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(SEGMENTS):
		var angle: float = TAU * float(i) / float(SEGMENTS)
		points.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_colored_polygon(points, fill_col)
	# Draw a slightly larger polygon as the rim.
	var rim_pts: PackedVector2Array = PackedVector2Array()
	for i in range(SEGMENTS):
		var angle: float = TAU * float(i) / float(SEGMENTS)
		rim_pts.append(center + Vector2(cos(angle) * (rx + 1.2), sin(angle) * (ry + 1.2)))
	draw_polyline(rim_pts, rim_col, 1.2, true)


## Sets the alpha of this footprint.
## Called by SnowFeetComponent at spawn time.
func set_alpha(alpha: float) -> void:
	_alpha = clampf(alpha, 0.0, 1.0)
	queue_redraw()


## Sets which foot this print belongs to.
## Called by SnowFeetComponent at spawn time.
func set_foot(is_left: bool) -> void:
	_is_left = is_left
	queue_redraw()


## Immediately removes this footprint.
func remove() -> void:
	queue_free()
