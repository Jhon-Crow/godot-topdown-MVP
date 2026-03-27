extends Node2D
class_name RainEffect
## Hotline Miami 2-style top-down rain effect (Issue #1394, fixed #1499, #1546).
##
## Single-layer particle system rendered on a CanvasLayer (screen space) so rain
## always covers the visible viewport regardless of camera position:
##   - RainStreaks: short circular drops with inward radial velocity (fish-eye
##     top-down perspective). Splashes removed per Issue #1580 feedback.
##
## Rain is always active (continuous) while outdoors.
## Supports indoor exclusion zones where rain should not appear.
## Camera position is checked each frame to detect building entry/exit.
##
## Fix #1546: Streak texture made shorter and wider (2x16 → 4x8) so drops look
## like circles when viewed directly from above (center), not elongated streaks.
## Alpha reduced for more transparent, subtle rain. Radial inward direction
## preserved from main so rain appears to fall top-down (correct perspective).

## Indoor exclusion zones (rain stops when camera center is inside).
## Each Rect2 defines a rectangular area in global coordinates.
var exclusion_zones: Array[Rect2] = []

## Current camera reference for zone checks.
var _camera: Camera2D = null

## Whether rain is hidden due to being inside an exclusion zone.
var _inside_exclusion: bool = false

## Rain canvas layer node (defined in .tscn).
@onready var _rain_canvas: CanvasLayer = $RainCanvas

## Inward radial rain streaks particle node (defined in .tscn).
@onready var _streaks: GPUParticles2D = $RainCanvas/RainStreaks

## Controls emission state of the streak particle layer.
var emitting: bool = false:
	set(value):
		emitting = value
		if _streaks:
			_streaks.emitting = value

## Whether time is currently stopped (e.g. last chance effect). When true,
## particle emission is paused regardless of exclusion zone state.
var _time_stopped: bool = false


func _ready() -> void:
	# Register in group so LastChanceEffectsManager can find this node reliably
	# (script resource_path may be empty in exported builds).
	add_to_group("precipitation_effects")
	# Rain is always on from the start
	emitting = true
	_log("Rain started (continuous mode)")


func _process(_delta: float) -> void:
	# While time is stopped, do not update emission or exclusion zones.
	if _time_stopped:
		return

	if _camera == null:
		_find_camera()
		return

	# Check exclusion zones using camera world position
	var camera_center := _camera.get_screen_center_position()
	var was_inside := _inside_exclusion
	_inside_exclusion = _is_point_in_exclusion_zone(camera_center)

	if _inside_exclusion and not was_inside:
		# Entered a building - hide rain
		emitting = false
		_log("Rain hidden (entered exclusion zone)")
	elif not _inside_exclusion and was_inside:
		# Left a building - show rain again
		emitting = true
		_log("Rain visible (left exclusion zone)")


## Adds a rectangular exclusion zone where rain will not appear.
## The rect should be in global coordinates.
func add_exclusion_zone(rect: Rect2) -> void:
	exclusion_zones.append(rect)


## Removes all exclusion zones.
func clear_exclusion_zones() -> void:
	exclusion_zones.clear()


## Returns true if rain is currently visible.
func is_raining() -> bool:
	return not _inside_exclusion


## Pauses or resumes particle emission for time-stop effects (e.g. last chance).
## When paused is true, the streak layer is frozen in place by disabling its
## process mode — existing particles stay visible, no new ones are spawned.
## When paused is false, particle processing is restored and emission resumes if the
## camera is not inside an exclusion zone.
func set_time_stopped(paused: bool) -> void:
	if _time_stopped == paused:
		return
	_time_stopped = paused
	if paused:
		# Disable processing on streak node so it freezes in place (existing
		# particles remain visible) rather than disappearing via emitting = false.
		if _streaks:
			_streaks.process_mode = Node.PROCESS_MODE_DISABLED
		_log("Rain paused (time stopped)")
	else:
		# Restore particle processing.
		if _streaks:
			_streaks.process_mode = Node.PROCESS_MODE_INHERIT
		# Resume emission only when not inside a building exclusion zone.
		emitting = not _inside_exclusion
		_log("Rain resumed (time resumed)")


func _find_camera() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	_camera = viewport.get_camera_2d()


func _is_point_in_exclusion_zone(point: Vector2) -> bool:
	for zone in exclusion_zones:
		if zone.has_point(point):
			return true
	return false


## Logs a rain effect message through the FileLogger autoload if available.
func _log(message: String) -> void:
	var file_logger: Node = Engine.get_singleton("FileLogger") if Engine.has_singleton("FileLogger") else null
	if file_logger == null:
		file_logger = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[RainEffect] " + message)
	else:
		print("[RainEffect] " + message)
