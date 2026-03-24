extends Node2D
## Floating item icon popup shown above the player when Experimental Sample fires an effect.
##
## Displays the icon of the triggered active item for the full effect duration, then fades out.
## Includes a circular countdown arc that depletes as the effect timer runs down.
## Appears above the player slightly to the right (matching the spec in Issue #1127).

## Default duration if no duration is provided.
const DEFAULT_DURATION: float = 1.2

## Fade-out duration at end of display (seconds).
const FADE_OUT_DURATION: float = 0.4

## Vertical offset above the player center (negative = above).
const OFFSET_Y: float = -60.0

## Horizontal offset to the right of the player center.
const OFFSET_X: float = 16.0

## Size of the displayed icon in pixels.
const ICON_SIZE: float = 36.0

## Background circle radius.
const BG_RADIUS: float = 22.0

## Countdown arc radius (slightly larger than the background circle).
const ARC_RADIUS: float = 25.0

## Width of the countdown arc stroke in pixels.
const ARC_WIDTH: float = 4.0

## Number of segments used to approximate the arc (higher = smoother).
const ARC_SEGMENTS: int = 48

## Arc color when time is plentiful (green-ish).
const ARC_COLOR_FULL: Color = Color(0.3, 1.0, 0.4, 0.9)

## Arc color when time is nearly expired (red).
const ARC_COLOR_LOW: Color = Color(1.0, 0.2, 0.2, 0.9)

## Fraction of total duration at which arc color shifts to LOW (below this = red).
const ARC_LOW_THRESHOLD: float = 0.3

## Background color (semi-transparent dark).
const BG_COLOR: Color = Color(0.05, 0.05, 0.05, 0.72)

## Icon tint color.
const ICON_TINT: Color = Color(1.0, 1.0, 1.0, 1.0)

## Total display duration for current activation.
var _total_duration: float = DEFAULT_DURATION

## Remaining display time.
var _timer: float = 0.0

## Whether the popup is currently visible.
var _active: bool = false

## The texture to display.
var _texture: Texture2D = null

## Sprite node for the icon.
var _sprite: Sprite2D = null


func _ready() -> void:
	visible = false
	z_index = 15

	_sprite = Sprite2D.new()
	_sprite.position = Vector2.ZERO
	add_child(_sprite)


func _process(delta: float) -> void:
	if not _active:
		return

	_timer -= delta
	if _timer <= 0.0:
		_active = false
		visible = false
		return

	# Keep positioned relative to parent (player) with right-of-centre offset
	position = Vector2(OFFSET_X, OFFSET_Y)

	# Fade out only in the last FADE_OUT_DURATION seconds
	var alpha: float = 1.0
	if _timer < FADE_OUT_DURATION:
		alpha = clampf(_timer / FADE_OUT_DURATION, 0.0, 1.0)
	modulate.a = alpha
	queue_redraw()


## Show the popup with the icon at the given path.
## @param icon_path: Resource path to the icon texture (from ActiveItemManager).
## @param duration: How long to keep the icon visible (seconds). Defaults to DEFAULT_DURATION.
func show_icon(icon_path: String, duration: float = DEFAULT_DURATION) -> void:
	if icon_path.is_empty():
		return

	# Load texture (safe: we check existence first)
	if not ResourceLoader.exists(icon_path):
		return

	var tex = load(icon_path)
	if not tex is Texture2D:
		return

	_texture = tex
	if _sprite:
		_sprite.texture = _texture
		# Scale sprite so the icon fits within ICON_SIZE pixels
		var tex_size: Vector2 = _texture.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			var scale_factor: float = ICON_SIZE / maxf(tex_size.x, tex_size.y)
			_sprite.scale = Vector2(scale_factor, scale_factor)

	_total_duration = maxf(duration, 0.0)
	_timer = _total_duration
	_active = true
	visible = true
	modulate.a = 1.0
	position = Vector2(OFFSET_X, OFFSET_Y)
	queue_redraw()


func _draw() -> void:
	if not _active or _texture == null:
		return

	# Draw background circle behind the icon
	draw_circle(Vector2.ZERO, BG_RADIUS, BG_COLOR)

	# Draw circular countdown arc: starts full at top (-PI/2) and depletes clockwise.
	# Only draw the arc if there is meaningful time remaining (skip instant/very short effects).
	var fraction: float = clampf(_timer / _total_duration, 0.0, 1.0)
	if _total_duration >= DEFAULT_DURATION and fraction > 0.01:
		var arc_color: Color = ARC_COLOR_FULL.lerp(ARC_COLOR_LOW, clampf(
			(ARC_LOW_THRESHOLD - fraction) / ARC_LOW_THRESHOLD, 0.0, 1.0))
		var start_angle: float = -PI / 2.0          # top of circle
		var end_angle: float = start_angle + TAU * fraction  # sweeps clockwise
		var seg_count: int = max(2, int(ARC_SEGMENTS * fraction))
		var prev_pt: Vector2 = Vector2(cos(start_angle), sin(start_angle)) * ARC_RADIUS
		for i in range(1, seg_count + 1):
			var t: float = float(i) / float(seg_count)
			var angle: float = start_angle + (end_angle - start_angle) * t
			var pt: Vector2 = Vector2(cos(angle), sin(angle)) * ARC_RADIUS
			draw_line(prev_pt, pt, arc_color, ARC_WIDTH, true)
			prev_pt = pt
