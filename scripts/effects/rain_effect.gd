extends Node2D
class_name RainEffect
## Hotline Miami 2-style top-down rain effect (Issue #1394, fixed #1499, #1546, #1579).
##
## Two-layer world-space particle system so raindrops stay at their spawned
## world positions as the camera moves — the rain no longer follows the player.
## The emitters track the camera center each frame so new drops always appear
## in the visible viewport area:
##   - RainStreaks: short oval dashes falling inward (top-down radial perspective)
##   - RainSplashes: circular ring ripples at the point where streaks land
##
## Rain is always active (continuous) while outdoors.
## Supports indoor exclusion zones where rain should not appear.
## Camera position is checked each frame to detect building entry/exit.
##
## Fix #1579: Emitters moved to world space (no CanvasLayer) and tracked to
## camera center each frame, matching the SnowEffect world-space approach so
## rain drops stay fixed in the world instead of following the screen.

## Indoor exclusion zones (rain stops when camera center is inside).
## Each Rect2 defines a rectangular area in global coordinates.
var exclusion_zones: Array[Rect2] = []

## Whether rain is hidden due to being inside an exclusion zone.
var _inside_exclusion: bool = false

## Inward radial rain streaks particle node (defined in .tscn).
@onready var _streaks: GPUParticles2D = $RainStreaks

## Ground splash ripples particle node (defined in .tscn).
@onready var _splashes: GPUParticles2D = $RainSplashes

## Controls emission state of both particle layers.
var emitting: bool = false:
	set(value):
		emitting = value
		if _streaks:
			_streaks.emitting = value
		if _splashes:
			_splashes.emitting = value


func _ready() -> void:
	# Rain is always on from the start
	emitting = true
	_log("Rain started (continuous mode, world-space emitters)")


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return

	# Keep emitters centered on the current camera so new drops always
	# spawn within the visible viewport area. Already-spawned drops remain
	# at their world positions — the rain does not follow the player.
	var cam_pos := camera.get_screen_center_position()
	if _streaks:
		_streaks.global_position = cam_pos
	if _splashes:
		_splashes.global_position = cam_pos

	# Check exclusion zones using camera world position
	var was_inside := _inside_exclusion
	_inside_exclusion = _is_point_in_exclusion_zone(cam_pos)

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
