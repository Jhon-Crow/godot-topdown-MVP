extends Node2D
## AI Helmet effect that predicts enemy positions 1 second into the future (Issue #671).
##
## When activated by pressing Space, creates red semi-transparent ghost outlines
## of all enemies at their predicted positions (current_position + velocity * 1.0s).
## The effect lasts 10 seconds per activation and the helmet has 2 charges per battle.
##
## Ghost sprites are drawn using _draw() with red circles at predicted positions.
## Each frame during the active period, ghost positions are recalculated based
## on each enemy's current velocity vector for a continuous prediction display.

## Duration of the prediction effect in seconds.
const EFFECT_DURATION: float = 10.0

## Number of charges available per battle (level).
const MAX_CHARGES: int = 2

## Time ahead to predict enemy positions (in seconds).
const PREDICTION_TIME: float = 1.0

## Color of the ghost outlines (semi-transparent red).
const GHOST_COLOR: Color = Color(1.0, 0.15, 0.15, 0.55)

## Radius of the ghost outline circle (matches enemy collision radius ~24px).
const GHOST_RADIUS: float = 24.0

## Line width for drawing ghost outline circles.
const GHOST_LINE_WIDTH: float = 3.0

## Number of segments for drawing ghost circles (smoothness).
const GHOST_CIRCLE_SEGMENTS: int = 24

## Inner fill color for ghost outlines (very faint red).
const GHOST_FILL_COLOR: Color = Color(1.0, 0.1, 0.1, 0.15)

## Remaining charges for this battle.
var _charges: int = MAX_CHARGES

## Whether the helmet effect is currently active.
var _is_active: bool = false

## Time remaining for the current activation (seconds).
var _remaining_time: float = 0.0

## Cached predicted positions for drawing (updated each frame).
## Array of Dictionary: [{"position": Vector2, "rotation": float}, ...]
var _ghost_data: Array = []

## Signal emitted when the helmet is activated.
signal helmet_activated(charges_left: int)

## Signal emitted when the helmet effect expires.
signal helmet_deactivated()

## Signal emitted when charges change.
signal charges_changed(charges_left: int)


func _ready() -> void:
	# The HelmetEffect is added as a child of the level root (not PlayerModel)
	# so that ghost positions are in global coordinates.
	# z_index is set high so ghosts render above other sprites.
	z_index = 100
	FileLogger.info("[HelmetEffect] Ready. Charges: %d/%d" % [_charges, MAX_CHARGES])


## Activate the helmet prediction effect.
## Returns true if activation succeeded, false if no charges remain or already active.
func activate() -> bool:
	if _is_active:
		FileLogger.info("[HelmetEffect] Already active, ignoring activation")
		return false

	if _charges <= 0:
		FileLogger.info("[HelmetEffect] No charges remaining")
		return false

	_charges -= 1
	_is_active = true
	_remaining_time = EFFECT_DURATION

	FileLogger.info("[HelmetEffect] Activated! Charges left: %d/%d, Duration: %.1fs" % [
		_charges, MAX_CHARGES, EFFECT_DURATION
	])

	helmet_activated.emit(_charges)
	charges_changed.emit(_charges)
	return true


## Deactivate the helmet prediction effect.
func deactivate() -> void:
	if not _is_active:
		return

	_is_active = false
	_remaining_time = 0.0
	_ghost_data.clear()
	queue_redraw()

	FileLogger.info("[HelmetEffect] Deactivated")
	helmet_deactivated.emit()


## Check if the helmet effect is currently active.
func is_active() -> bool:
	return _is_active


## Get the number of remaining charges.
func get_charges() -> int:
	return _charges


## Get the remaining effect time in seconds.
func get_remaining_time() -> float:
	return _remaining_time


func _physics_process(delta: float) -> void:
	if not _is_active:
		return

	_remaining_time -= delta
	if _remaining_time <= 0.0:
		deactivate()
		return

	_update_ghost_positions()
	queue_redraw()


## Calculate predicted positions for all enemies.
func _update_ghost_positions() -> void:
	_ghost_data.clear()

	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if not enemy is CharacterBody2D:
			continue
		# Skip dead enemies (they have _is_alive = false or health <= 0)
		if enemy.has_method("is_alive") and not enemy.is_alive():
			continue
		if enemy.get("_is_alive") != null and not enemy.get("_is_alive"):
			continue

		var current_pos: Vector2 = enemy.global_position
		var vel: Vector2 = enemy.velocity
		var predicted_pos: Vector2 = current_pos + vel * PREDICTION_TIME
		var current_rot: float = 0.0
		# Get model rotation if available
		var enemy_model: Node2D = enemy.get_node_or_null("EnemyModel")
		if enemy_model:
			current_rot = enemy_model.global_rotation

		_ghost_data.append({
			"position": predicted_pos,
			"rotation": current_rot,
			"current_position": current_pos,
		})


## Draw ghost outlines at predicted enemy positions.
func _draw() -> void:
	if not _is_active or _ghost_data.is_empty():
		return

	for ghost in _ghost_data:
		var pos: Vector2 = ghost["position"]
		var current_pos: Vector2 = ghost["current_position"]

		# Convert global positions to local coordinates for drawing.
		var local_predicted := to_local(pos)
		var local_current := to_local(current_pos)

		# Draw filled ghost circle at predicted position
		_draw_filled_circle(local_predicted, GHOST_RADIUS, GHOST_FILL_COLOR)

		# Draw outline circle at predicted position
		_draw_circle_outline(local_predicted, GHOST_RADIUS, GHOST_COLOR, GHOST_LINE_WIDTH)

		# Draw a faint line from current to predicted position
		var line_color := Color(GHOST_COLOR.r, GHOST_COLOR.g, GHOST_COLOR.b, 0.25)
		draw_line(local_current, local_predicted, line_color, 1.5)


## Draw a circle outline using line segments.
func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in range(GHOST_CIRCLE_SEGMENTS + 1):
		var angle := float(i) / float(GHOST_CIRCLE_SEGMENTS) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, width)


## Draw a filled circle using polygon.
func _draw_filled_circle(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(GHOST_CIRCLE_SEGMENTS):
		var angle := float(i) / float(GHOST_CIRCLE_SEGMENTS) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	draw_colored_polygon(points, color)
