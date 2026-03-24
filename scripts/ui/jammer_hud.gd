extends Node2D
## Jammer HUD icon shown above the player when active items are jammed (Issue #1036).
##
## Displays a red prohibition sign (circle with diagonal line) above the player
## to indicate that the Radio Jammer enemy is blocking active item use.
## Only shown when the player has an active item equipped (not NONE).

## Vertical offset above the player center (negative = above).
const OFFSET_Y: float = -56.0

## Radius of the prohibition circle in pixels.
## Sized to match the Combat Disposition item icon (~32 px) shown above the player (Issue #1115).
const CIRCLE_RADIUS: float = 10.0

## Color of the prohibition sign (red, slightly transparent).
const SIGN_COLOR: Color = Color(0.9, 0.1, 0.05, 0.95)

## Line width for both the circle and diagonal bar.
const LINE_WIDTH: float = 3.0


func _ready() -> void:
	visible = false
	z_index = 12


func _process(_delta: float) -> void:
	position = Vector2(0.0, OFFSET_Y)


## Show or hide the icon.
func set_jammed_visible(show: bool) -> void:
	if visible != show:
		visible = show
		queue_redraw()


func _draw() -> void:
	# Draw outer circle
	draw_arc(Vector2.ZERO, CIRCLE_RADIUS, 0.0, TAU, 32, SIGN_COLOR, LINE_WIDTH, true)

	# Draw diagonal bar (top-right to bottom-left, matching prohibition sign angle ~45°)
	var r: float = CIRCLE_RADIUS - LINE_WIDTH * 0.5
	var dir := Vector2(1.0, -1.0).normalized() * r
	draw_line(-dir, dir, SIGN_COLOR, LINE_WIDTH, true)
