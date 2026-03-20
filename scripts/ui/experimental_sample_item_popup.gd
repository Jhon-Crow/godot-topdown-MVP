extends Node2D
## Floating item icon popup shown above the player when Experimental Sample fires an effect.
##
## Displays the icon of the triggered active item for 300ms, then fades out.
## Appears above the player slightly to the right (matching the spec in Issue #1127).

## Duration the icon is visible (seconds).
const SHOW_DURATION: float = 0.3

## Vertical offset above the player center (negative = above).
const OFFSET_Y: float = -52.0

## Horizontal offset to the right of the player center.
const OFFSET_X: float = 12.0

## Size of the displayed icon in pixels.
const ICON_SIZE: float = 20.0

## Background circle radius.
const BG_RADIUS: float = 13.0

## Background color (semi-transparent dark).
const BG_COLOR: Color = Color(0.05, 0.05, 0.05, 0.72)

## Icon tint color.
const ICON_TINT: Color = Color(1.0, 1.0, 1.0, 1.0)

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

	# Fade out in last 100ms
	var alpha: float = clampf(_timer / SHOW_DURATION, 0.0, 1.0)
	modulate.a = alpha
	queue_redraw()


## Show the popup with the icon at the given path.
## @param icon_path: Resource path to the icon texture (from ActiveItemManager).
func show_icon(icon_path: String) -> void:
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

	_timer = SHOW_DURATION
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
