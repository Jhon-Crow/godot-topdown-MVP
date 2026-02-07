class_name StatusEffectAnimationComponent
extends Node2D
## Renders animated visual indicators for status effects (stun, blindness).
##
## Stun: Orbiting stars above the enemy's head (classic "seeing stars" dizziness effect).
## Blindness: X marks drawn over the enemy's head area (eyes covered / cannot see).
##
## Created as a child of the enemy's EnemyModel so it rotates with the model.
## Uses _draw() for efficient programmatic rendering without additional sprite assets.
## Issue #602.

## Number of orbiting stars for stun animation.
const STAR_COUNT: int = 3
## Orbit radius for stars (pixels from center).
const STAR_ORBIT_RADIUS: float = 14.0
## Star size (radius of each star circle).
const STAR_SIZE: float = 2.5
## Orbit speed (radians per second).
const STAR_ORBIT_SPEED: float = 3.0
## Star color (gold/yellow - classic stun indicator).
const STAR_COLOR: Color = Color(1.0, 0.9, 0.2, 0.9)
## Star highlight color (brighter center).
const STAR_HIGHLIGHT_COLOR: Color = Color(1.0, 1.0, 0.6, 1.0)

## Size of the X marks for blindness.
const BLIND_X_SIZE: float = 3.5
## Gap between two X marks (horizontal offset from center).
const BLIND_X_SPACING: float = 4.0
## Blindness X mark color (white with slight yellow tint).
const BLIND_X_COLOR: Color = Color(1.0, 1.0, 0.7, 0.9)
## Line width for X marks.
const BLIND_X_WIDTH: float = 1.5
## Pulse speed for blindness animation (radians per second).
const BLIND_PULSE_SPEED: float = 4.0

## Vertical offset from parent origin to position effects near the head.
var head_offset: Vector2 = Vector2(-6.0, -2.0)

## Whether stun animation is active.
var _is_stunned: bool = false
## Whether blindness animation is active.
var _is_blinded: bool = false
## Animation time accumulator.
var _anim_time: float = 0.0


func _ready() -> void:
	# Start invisible - only show when effects are active
	visible = false


func _process(delta: float) -> void:
	if not _is_stunned and not _is_blinded:
		if visible:
			visible = false
		return

	_anim_time += delta
	visible = true
	queue_redraw()


func _draw() -> void:
	if _is_stunned:
		_draw_stun_stars()
	if _is_blinded:
		_draw_blind_x_marks()


## Draw orbiting stars above the head for stun/dizziness effect.
func _draw_stun_stars() -> void:
	var center := head_offset + Vector2(0, -12.0)  # Above the head

	for i in range(STAR_COUNT):
		# Calculate star position on orbit circle
		var angle_offset := (TAU / STAR_COUNT) * i
		var angle := _anim_time * STAR_ORBIT_SPEED + angle_offset
		var star_pos := center + Vector2(cos(angle), sin(angle)) * STAR_ORBIT_RADIUS

		# Draw star as a small diamond shape (4 points)
		var size := STAR_SIZE
		# Slight size pulsing per star
		var pulse := 1.0 + 0.3 * sin(_anim_time * 5.0 + angle_offset)
		size *= pulse

		var points := PackedVector2Array([
			star_pos + Vector2(0, -size),       # Top
			star_pos + Vector2(size * 0.6, 0),  # Right
			star_pos + Vector2(0, size),         # Bottom
			star_pos + Vector2(-size * 0.6, 0),  # Left
		])
		draw_colored_polygon(points, STAR_COLOR)

		# Draw bright center dot
		draw_circle(star_pos, size * 0.3, STAR_HIGHLIGHT_COLOR)


## Draw X marks over the head area for blindness effect.
func _draw_blind_x_marks() -> void:
	var center := head_offset

	# Pulse opacity for visual feedback
	var pulse_alpha := 0.7 + 0.3 * sin(_anim_time * BLIND_PULSE_SPEED)
	var color := Color(BLIND_X_COLOR.r, BLIND_X_COLOR.g, BLIND_X_COLOR.b, pulse_alpha)

	# Draw two X marks (one for each eye)
	for side in [-1.0, 1.0]:
		var eye_center := center + Vector2(BLIND_X_SPACING * side, 0)
		# Draw X shape with two crossing lines
		draw_line(
			eye_center + Vector2(-BLIND_X_SIZE, -BLIND_X_SIZE),
			eye_center + Vector2(BLIND_X_SIZE, BLIND_X_SIZE),
			color, BLIND_X_WIDTH
		)
		draw_line(
			eye_center + Vector2(BLIND_X_SIZE, -BLIND_X_SIZE),
			eye_center + Vector2(-BLIND_X_SIZE, BLIND_X_SIZE),
			color, BLIND_X_WIDTH
		)


## Update the stun state. Called by the enemy when stun status changes.
func set_stunned(stunned: bool) -> void:
	_is_stunned = stunned
	if not _is_stunned and not _is_blinded:
		visible = false
		_anim_time = 0.0


## Update the blindness state. Called by the enemy when blindness status changes.
func set_blinded(blinded: bool) -> void:
	_is_blinded = blinded
	if not _is_stunned and not _is_blinded:
		visible = false
		_anim_time = 0.0


## Check if any status animation is currently active.
func is_active() -> bool:
	return _is_stunned or _is_blinded
