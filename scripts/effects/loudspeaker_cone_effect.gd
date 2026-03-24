extends Node2D
## Sound cone visual effect for the Loudspeaker active item (Issue #959).
##
## Renders an expanding sound wave arc in the player's facing direction.
## The effect:
## - Draws a sector/arc with a wider angle than the flashlight
## - Shows as an expanding ring (like a sound wave emanating outward)
## - Has a shimmer style similar to the invisibility cloak effect
## - Automatically fades out after a short duration

## Half-angle of the sound cone in degrees (wider than flashlight's 9 deg).
const CONE_HALF_ANGLE_DEG: float = 50.0

## Maximum radius of the sound wave expansion.
const MAX_RADIUS: float = 400.0

## Minimum radius where the wave starts.
const MIN_RADIUS: float = 30.0

## Width (thickness) of the sound wave ring.
const WAVE_THICKNESS: float = 28.0

## Duration the wave takes to expand (seconds).
const EXPAND_DURATION: float = 0.55

## Inner wave: arc color (sound wave cyan-blue, like a shimmer).
const WAVE_COLOR: Color = Color(0.3, 0.9, 1.0, 0.75)

## Outer fade: near-transparent outer edge.
const WAVE_OUTER_COLOR: Color = Color(0.4, 0.8, 1.0, 0.0)

## Number of arc segments for smooth rendering.
const ARC_SEGMENTS: int = 32

## Whether the effect is currently playing.
var _is_playing: bool = false

## Current expand progress (0.0 - 1.0).
var _progress: float = 0.0

## Direction the cone is pointing (unit vector).
var _direction: Vector2 = Vector2.RIGHT

## Reference to the player for direction tracking.
var _player: Node2D = null


## Initialize with a reference to the player node.
func initialize(player: Node2D) -> void:
	_player = player


## Activate the sound cone in the given direction.
## @param direction: Normalized Vector2 of the player's aim/facing direction.
func play(direction: Vector2) -> void:
	_direction = direction.normalized() if direction.length() > 0.001 else Vector2.RIGHT
	_progress = 0.0
	_is_playing = true
	queue_redraw()


## Stop the effect immediately.
func stop() -> void:
	_is_playing = false
	_progress = 0.0
	queue_redraw()


## Whether the effect is currently active.
func is_playing() -> bool:
	return _is_playing


func _process(delta: float) -> void:
	if not _is_playing:
		return

	_progress += delta / EXPAND_DURATION

	if _progress >= 1.0:
		_progress = 1.0
		_is_playing = false

	queue_redraw()


func _draw() -> void:
	if not _is_playing:
		return

	# Calculate current wave ring radii
	var eased := _ease_out_quad(_progress)
	var wave_center_radius := MIN_RADIUS + eased * (MAX_RADIUS - MIN_RADIUS)
	var inner_radius := maxf(wave_center_radius - WAVE_THICKNESS * 0.5, 0.0)
	var outer_radius := wave_center_radius + WAVE_THICKNESS * 0.5

	# Fade alpha: full at start, fades out in last third of animation
	var fade := 1.0
	if _progress > 0.6:
		fade = 1.0 - (_progress - 0.6) / 0.4
	fade = clampf(fade, 0.0, 1.0)

	# Draw the wave as a filled sector ring
	_draw_ring_sector(inner_radius, outer_radius, fade)


## Draw a sector ring (donut slice) pointing in _direction.
func _draw_ring_sector(inner_r: float, outer_r: float, alpha: float) -> void:
	var half_angle := deg_to_rad(CONE_HALF_ANGLE_DEG)
	var base_angle := _direction.angle()

	# Build polygon from inner arc to outer arc
	var points: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()

	var step := (half_angle * 2.0) / ARC_SEGMENTS

	# Outer arc (forward direction)
	for i in range(ARC_SEGMENTS + 1):
		var a := base_angle - half_angle + step * i
		points.append(Vector2(cos(a), sin(a)) * outer_r)

	# Inner arc (reverse direction to close polygon)
	for i in range(ARC_SEGMENTS, -1, -1):
		var a := base_angle - half_angle + step * i
		points.append(Vector2(cos(a), sin(a)) * inner_r)

	# Color with shimmer gradient: brighter in middle, transparent at edges
	for i in range(ARC_SEGMENTS + 1):
		# Outer arc: fade from solid center to transparent edges
		var t := float(i) / float(ARC_SEGMENTS)
		# Shimmer: pulse brightness at the front of the cone
		var shimmer := 0.7 + 0.3 * sin(_progress * TAU * 2.0 + t * PI)
		var c := Color(WAVE_COLOR.r * shimmer, WAVE_COLOR.g * shimmer, WAVE_COLOR.b * shimmer,
			WAVE_COLOR.a * alpha * shimmer)
		colors.append(c)

	for i in range(ARC_SEGMENTS, -1, -1):
		# Inner arc: mostly transparent
		var t := float(i) / float(ARC_SEGMENTS)
		var shimmer := 0.5 + 0.5 * sin(_progress * TAU * 2.0 + t * PI)
		var c := Color(WAVE_COLOR.r, WAVE_COLOR.g, WAVE_COLOR.b,
			WAVE_COLOR.a * alpha * 0.3 * shimmer)
		colors.append(c)

	draw_polygon(points, colors)

	# Draw a thin bright leading edge on the outer arc for the "wave front"
	_draw_arc_line(outer_r, alpha)


## Draw a thin arc at the outer edge as the wave front.
func _draw_arc_line(radius: float, alpha: float) -> void:
	var half_angle := deg_to_rad(CONE_HALF_ANGLE_DEG)
	var base_angle := _direction.angle()
	var step := (half_angle * 2.0) / ARC_SEGMENTS

	var bright := Color(0.7, 1.0, 1.0, alpha * 0.9)

	for i in range(ARC_SEGMENTS):
		var a1 := base_angle - half_angle + step * i
		var a2 := base_angle - half_angle + step * (i + 1)
		var p1 := Vector2(cos(a1), sin(a1)) * radius
		var p2 := Vector2(cos(a2), sin(a2)) * radius
		draw_line(p1, p2, bright, 1.5, true)


## Quadratic ease-out for smooth wave expansion.
func _ease_out_quad(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)
