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

## Color of the ghost outlines (bright red, higher alpha for visibility).
const GHOST_COLOR: Color = Color(1.0, 0.1, 0.1, 0.8)

## Radius of the ghost outline circle (larger for visibility ~32px).
const GHOST_RADIUS: float = 32.0

## Line width for drawing ghost outline circles.
const GHOST_LINE_WIDTH: float = 4.0

## Number of segments for drawing ghost circles (smoothness).
const GHOST_CIRCLE_SEGMENTS: int = 32

## Inner fill color for ghost outlines (semi-transparent red).
const GHOST_FILL_COLOR: Color = Color(1.0, 0.1, 0.1, 0.25)

## Color of the connecting line from current to predicted position.
const GHOST_LINE_COLOR: Color = Color(1.0, 0.2, 0.2, 0.4)

## Outer glow radius for ghost outlines (extra visibility).
const GHOST_GLOW_RADIUS: float = 40.0

## Outer glow color (faint red for halo effect).
const GHOST_GLOW_COLOR: Color = Color(1.0, 0.1, 0.1, 0.1)

## Remaining charges for this battle.
var _charges: int = MAX_CHARGES

## Whether the helmet effect is currently active.
var _is_active: bool = false

## Time remaining for the current activation (seconds).
var _remaining_time: float = 0.0

## Cached predicted positions for drawing (updated each frame).
## Array of Dictionary: [{"position": Vector2, "rotation": float, "current_position": Vector2}, ...]
var _ghost_data: Array = []

## Whether we've logged the first draw frame (to avoid log spam).
var _first_draw_logged: bool = false

## Frame counter for pulsing animation.
var _pulse_time: float = 0.0

## Whether we've logged diagnostics for this activation (to avoid log spam).
var _diagnostics_logged: bool = false

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
	# Ensure this node is visible and at the origin.
	visible = true
	position = Vector2.ZERO
	FileLogger.info("[HelmetEffect] Ready. Charges: %d/%d, position: %s, visible: %s, z_index: %d" % [
		_charges, MAX_CHARGES, str(position), str(visible), z_index
	])


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
	_first_draw_logged = false
	_diagnostics_logged = false
	_pulse_time = 0.0

	FileLogger.info("[HelmetEffect] Activated! Charges left: %d/%d, Duration: %.1fs" % [
		_charges, MAX_CHARGES, EFFECT_DURATION
	])

	helmet_activated.emit(_charges)
	charges_changed.emit(_charges)

	# Ghost positions will be updated on the next _physics_process frame.
	# Do NOT call _update_ghost_positions() here — iterating enemies during
	# input processing can cause crashes in exported builds (Issue #671).

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
	_pulse_time += delta

	if _remaining_time <= 0.0:
		deactivate()
		return

	_update_ghost_positions()
	queue_redraw()


## Calculate predicted positions for all enemies.
func _update_ghost_positions() -> void:
	_ghost_data.clear()

	if not is_inside_tree():
		return

	var tree := get_tree()
	if tree == null:
		return

	var enemies := tree.get_nodes_in_group("enemies")

	# Log diagnostics once per activation (deferred to first physics frame)
	if not _diagnostics_logged:
		_diagnostics_logged = true
		var alive_count := 0
		var cb2d_count := 0
		for e in enemies:
			if not is_instance_valid(e):
				continue
			if e is CharacterBody2D:
				cb2d_count += 1
				if e.has_method("is_alive"):
					if e.is_alive():
						alive_count += 1
				elif e.get("_is_alive") != null:
					if e.get("_is_alive"):
						alive_count += 1
		FileLogger.info("[HelmetEffect] Diagnostics: Enemies in group: %d, CharacterBody2D: %d, Alive: %d" % [
			enemies.size(), cb2d_count, alive_count
		])

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
		# Skip enemies with NaN positions or velocities
		if is_nan(current_pos.x) or is_nan(current_pos.y):
			continue
		if is_nan(vel.x) or is_nan(vel.y):
			continue
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

	# Log on the first draw frame for diagnostic purposes
	if not _first_draw_logged:
		_first_draw_logged = true
		FileLogger.info("[HelmetEffect] Drawing %d ghost outlines. Node pos: %s, global_pos: %s, visible: %s" % [
			_ghost_data.size(), str(position), str(global_position), str(visible)
		])
		if _ghost_data.size() > 0:
			var first_ghost: Dictionary = _ghost_data[0]
			FileLogger.info("[HelmetEffect] First ghost: predicted=%s, current=%s" % [
				str(first_ghost.get("position", Vector2.ZERO)),
				str(first_ghost.get("current_position", Vector2.ZERO))
			])

	# Calculate pulse factor for breathing animation (makes ghosts more noticeable)
	var pulse: float = 0.85 + 0.15 * sin(_pulse_time * 4.0)

	for ghost in _ghost_data:
		var pos: Vector2 = ghost.get("position", Vector2.ZERO)
		var current_pos: Vector2 = ghost.get("current_position", Vector2.ZERO)

		# Convert global positions to local coordinates for drawing.
		var local_predicted := to_local(pos)
		var local_current := to_local(current_pos)

		# Draw outer glow at predicted position (halo effect for visibility)
		_draw_filled_circle(local_predicted, GHOST_GLOW_RADIUS * pulse, GHOST_GLOW_COLOR)

		# Draw filled ghost circle at predicted position
		_draw_filled_circle(local_predicted, GHOST_RADIUS * pulse, GHOST_FILL_COLOR)

		# Draw outline circle at predicted position (bright red)
		_draw_circle_outline(local_predicted, GHOST_RADIUS * pulse, GHOST_COLOR, GHOST_LINE_WIDTH)

		# Draw a line from current enemy position to predicted position
		draw_line(local_current, local_predicted, GHOST_LINE_COLOR, 2.0)

		# Draw small marker at current enemy position
		_draw_circle_outline(local_current, 8.0, GHOST_LINE_COLOR, 1.5)


## Draw a circle outline using line segments.
func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	if radius <= 0.0:
		return
	var points := PackedVector2Array()
	for i in range(GHOST_CIRCLE_SEGMENTS + 1):
		var angle := float(i) / float(GHOST_CIRCLE_SEGMENTS) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, width)


## Draw a filled circle using polygon.
func _draw_filled_circle(center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	var points := PackedVector2Array()
	for i in range(GHOST_CIRCLE_SEGMENTS):
		var angle := float(i) / float(GHOST_CIRCLE_SEGMENTS) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	if points.size() >= 3:
		draw_colored_polygon(points, color)
