class_name StatusEffectAnimationComponent
extends Node2D
## Renders animated visual indicators for status effects (stun, blindness, aggression).
##
## Stun: Orbiting stars above the enemy's head (classic "seeing stars" dizziness effect).
## Blindness: X marks drawn over the enemy's head area (eyes covered / cannot see).
## Aggression: Red anger mark above the head (Issue #675 — rotating/pulsing anger symbol).
##
## Created as a child of the enemy's EnemyModel so it rotates with the model.
## Uses _draw() for efficient programmatic rendering without additional sprite assets.
## Issue #602, #675.

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

## Aggression anger mark color (bright red — matches owner's reference icon).
const AGGRESSION_COLOR: Color = Color(1.0, 0.1, 0.05, 0.9)
## Aggression mark line width.
const AGGRESSION_LINE_WIDTH: float = 1.8
## Aggression mark size (radius of the anger symbol).
const AGGRESSION_MARK_SIZE: float = 5.5
## Aggression pulse speed (radians per second — fast pulsing for angry feel).
const AGGRESSION_PULSE_SPEED: float = 5.0
## Number of curved arms in the anger mark.
const AGGRESSION_ARM_COUNT: int = 6
## Aggression rotation speed (radians per second — slow spin).
const AGGRESSION_ROTATION_SPEED: float = 1.5

## Vertical offset from parent origin to position effects near the head.
var head_offset: Vector2 = Vector2(-6.0, -2.0)

## Whether stun animation is active.
var _is_stunned: bool = false
## Whether blindness animation is active.
var _is_blinded: bool = false
## Whether aggression animation is active (Issue #675).
var _is_aggressive: bool = false
## Animation time accumulator.
var _anim_time: float = 0.0


func _ready() -> void:
	# Start invisible - only show when effects are active
	visible = false


func _process(delta: float) -> void:
	if not _is_stunned and not _is_blinded and not _is_aggressive:
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
	if _is_aggressive:
		_draw_aggression_mark()


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


## Draw the anger mark above the head for aggression effect (Issue #675).
## Renders the classic manga/anime anger symbol: curved arms radiating from center.
## Matches the red anger mark icon from the owner's reference image.
func _draw_aggression_mark() -> void:
	# Position above the head (offset from stun stars to avoid overlap)
	var center := head_offset + Vector2(0, -14.0)

	# Pulsing size and opacity for animated feel
	var pulse := 1.0 + 0.15 * sin(_anim_time * AGGRESSION_PULSE_SPEED)
	var size := AGGRESSION_MARK_SIZE * pulse
	var pulse_alpha := 0.75 + 0.25 * sin(_anim_time * AGGRESSION_PULSE_SPEED)
	var color := Color(AGGRESSION_COLOR.r, AGGRESSION_COLOR.g, AGGRESSION_COLOR.b, pulse_alpha)

	# Slow rotation
	var base_rotation := _anim_time * AGGRESSION_ROTATION_SPEED

	# Draw the anger mark — 6 curved arms radiating outward (like the reference icon)
	for i in range(AGGRESSION_ARM_COUNT):
		var arm_angle := base_rotation + (TAU / AGGRESSION_ARM_COUNT) * i
		# Each arm is a short curved line segment from inner to outer radius
		# Curve outward with a slight bend (like the reference anger mark)
		var inner_radius := size * 0.3
		var outer_radius := size
		var curve_offset := 0.4  # How much the arm curves

		# Start point (inner)
		var start := center + Vector2(cos(arm_angle), sin(arm_angle)) * inner_radius
		# End point (outer, with curve offset for the swirl look)
		var end_angle := arm_angle + curve_offset
		var end_pt := center + Vector2(cos(end_angle), sin(end_angle)) * outer_radius

		# Draw each arm as a thick line
		draw_line(start, end_pt, color, AGGRESSION_LINE_WIDTH)

		# Draw a small rounded cap at the end for the bulbous tip look
		draw_circle(end_pt, AGGRESSION_LINE_WIDTH * 0.6, color)


## Update the stun state. Called by the enemy when stun status changes.
func set_stunned(stunned: bool) -> void:
	_is_stunned = stunned
	if not _is_stunned and not _is_blinded and not _is_aggressive:
		visible = false
		_anim_time = 0.0


## Update the blindness state. Called by the enemy when blindness status changes.
func set_blinded(blinded: bool) -> void:
	_is_blinded = blinded
	if not _is_stunned and not _is_blinded and not _is_aggressive:
		visible = false
		_anim_time = 0.0


## Update the aggression state (Issue #675). Called by the enemy when aggression status changes.
func set_aggressive(aggressive: bool) -> void:
	_is_aggressive = aggressive
	if not _is_stunned and not _is_blinded and not _is_aggressive:
		visible = false
		_anim_time = 0.0


## Check if any status animation is currently active.
func is_active() -> bool:
	return _is_stunned or _is_blinded or _is_aggressive
