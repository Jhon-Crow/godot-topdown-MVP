extends Node2D
## HUD overlay for the Dead Eye passive item (Issue #1069).
##
## Displays a red eye icon with the current hit-streak counter above the player.
## The eye pulses red on hits and flashes briefly when the multiplier resets.
## Always visible while Dead Eye is active.

## Vertical offset above the player center (negative = above).
const OFFSET_Y: float = -36.0

## Eye body color (dark red).
const EYE_COLOR: Color = Color(0.75, 0.1, 0.1, 0.9)

## Eye outline color.
const EYE_OUTLINE_COLOR: Color = Color(0.9, 0.15, 0.15, 1.0)

## Iris/pupil glow color on active streak.
const IRIS_HIT_COLOR: Color = Color(1.0, 0.2, 0.1, 1.0)

## Iris base color (no streak).
const IRIS_BASE_COLOR: Color = Color(0.55, 0.05, 0.05, 0.9)

## Counter label text color.
const COUNTER_COLOR: Color = Color(1.0, 0.9, 0.9, 1.0)

## Counter label text color when multiplier is at base (debuff active).
const COUNTER_DEBUFF_COLOR: Color = Color(0.9, 0.4, 0.4, 0.85)

## Flash color on miss/reset.
const RESET_FLASH_COLOR: Color = Color(0.3, 0.3, 0.3, 0.8)

## Duration of hit-flash pulse (seconds).
const HIT_FLASH_DURATION: float = 0.25

## Duration of reset-flash (seconds).
const RESET_FLASH_DURATION: float = 0.35

## Eye half-width.
const EYE_HALF_W: float = 11.0

## Eye half-height.
const EYE_HALF_H: float = 5.0

## Iris radius.
const IRIS_RADIUS: float = 3.5

## Pupil radius.
const PUPIL_RADIUS: float = 1.5

## Reference to DeadEyeManager autoload.
var _manager: Node = null

## Cached hit streak count (number of stacks above base).
var _streak: int = 0

## Cached current multiplier.
var _multiplier: float = 0.8

## Flash timer for hit pulse (>0 = flashing).
var _hit_flash_timer: float = 0.0

## Flash timer for reset (>0 = reset flash).
var _reset_flash_timer: float = 0.0

## Previous streak value to detect changes.
var _prev_streak: int = 0

## Previous multiplier to detect resets.
var _prev_multiplier: float = 0.8


func _ready() -> void:
	z_index = 10
	visible = false


## Called by player.gd after Dead Eye is activated.
func initialize(manager: Node) -> void:
	_manager = manager
	visible = true
	_streak = 0
	_multiplier = 0.8
	_prev_streak = 0
	_prev_multiplier = 0.8
	queue_redraw()


## Called when Dead Eye is deactivated (item unequipped).
func deactivate() -> void:
	visible = false
	_manager = null


func _process(delta: float) -> void:
	position = Vector2(0.0, OFFSET_Y)

	if not _manager:
		return

	# Poll state from manager each frame
	var new_multiplier: float = _manager.get_damage_multiplier()
	var new_streak: int = _manager.get_hit_streak()

	# Detect hit (streak increased)
	if new_streak > _prev_streak:
		_hit_flash_timer = HIT_FLASH_DURATION

	# Detect reset (multiplier went back to base while streak was > 0)
	if new_multiplier <= _manager.BASE_MULTIPLIER and _prev_streak > 0 and new_streak == 0:
		_reset_flash_timer = RESET_FLASH_DURATION

	_prev_streak = new_streak
	_prev_multiplier = new_multiplier
	_streak = new_streak
	_multiplier = new_multiplier

	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
	if _reset_flash_timer > 0.0:
		_reset_flash_timer -= delta

	queue_redraw()


func _draw() -> void:
	# === Eye shape (ellipse approximated as polygon) ===
	var eye_color := EYE_COLOR
	var iris_color := IRIS_BASE_COLOR

	if _reset_flash_timer > 0.0:
		# Gray flash on reset
		var t := _reset_flash_timer / RESET_FLASH_DURATION
		eye_color = eye_color.lerp(RESET_FLASH_COLOR, t)
		iris_color = iris_color.lerp(RESET_FLASH_COLOR, t)
	elif _hit_flash_timer > 0.0:
		# Bright red flash on hit
		var t := _hit_flash_timer / HIT_FLASH_DURATION
		iris_color = iris_color.lerp(IRIS_HIT_COLOR, t * 0.8)

	# Draw eye white (ellipse)
	_draw_ellipse(Vector2.ZERO, EYE_HALF_W, EYE_HALF_H, eye_color, 24)

	# Draw eye outline
	_draw_ellipse_outline(Vector2.ZERO, EYE_HALF_W, EYE_HALF_H, EYE_OUTLINE_COLOR, 24, 1.5)

	# Draw iris
	draw_circle(Vector2.ZERO, IRIS_RADIUS, iris_color)

	# Draw pupil
	draw_circle(Vector2.ZERO, PUPIL_RADIUS, Color(0.05, 0.0, 0.0, 1.0))

	# Specular highlight
	draw_circle(Vector2(-1.5, -1.2), 0.9, Color(1.0, 0.9, 0.9, 0.7))

	# === Hit streak counter ===
	var label_text: String
	if _streak > 0:
		label_text = "x%d" % (_streak + 1)
	else:
		label_text = "-20%"

	var label_color := COUNTER_COLOR if _streak > 0 else COUNTER_DEBUFF_COLOR
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-9, -EYE_HALF_H - 3),
		label_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		label_color
	)


## Draw a filled ellipse using polygon approximation.
func _draw_ellipse(center: Vector2, half_w: float, half_h: float, color: Color, segments: int) -> void:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(center + Vector2(cos(angle) * half_w, sin(angle) * half_h))
	draw_colored_polygon(points, color)


## Draw an ellipse outline.
func _draw_ellipse_outline(center: Vector2, half_w: float, half_h: float, color: Color, segments: int, width: float) -> void:
	for i in range(segments):
		var a1 := TAU * i / segments
		var a2 := TAU * (i + 1) / segments
		var p1 := center + Vector2(cos(a1) * half_w, sin(a1) * half_h)
		var p2 := center + Vector2(cos(a2) * half_w, sin(a2) * half_h)
		draw_line(p1, p2, color, width)
