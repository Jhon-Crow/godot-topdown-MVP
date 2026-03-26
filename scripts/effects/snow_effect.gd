extends Node2D
class_name SnowEffect
## Top-down snowfall effect for the Winter Forest map (Issue #1548, updated #1569).
##
## Two-layer world-space particle system so snowflakes stay at their spawned
## world positions as the camera moves — the snow no longer follows the player.
## The emitters track the camera center each frame so new flakes always appear
## in the visible area:
##   - SnowFlakesLarge: larger circular flakes with inward radial velocity (fish-eye top-down perspective)
##   - SnowFlakesSmall: smaller circular flakes at slower inward radial velocity for depth variation
##
## Particles use negative radial_velocity so they move inward toward the emitter
## center, matching the top-down falling appearance of the RainEffect (Issue #1394).
## Since emitters are in world space (no CanvasLayer), already-spawned flakes stay
## fixed in the world while new ones spawn around the current viewport area.
##
## Snow is always active (continuous) while on the Winter Forest map.
## No exclusion zones needed — the level is fully outdoor.

## Large snowflake particle node (defined in .tscn).
@onready var _flakes_large: GPUParticles2D = $SnowFlakesLarge

## Small snowflake particle node (defined in .tscn).
@onready var _flakes_small: GPUParticles2D = $SnowFlakesSmall

## Controls emission state of both particle layers.
var emitting: bool = false:
	set(value):
		emitting = value
		if _flakes_large:
			_flakes_large.emitting = value
		if _flakes_small:
			_flakes_small.emitting = value

## Whether time is currently stopped (e.g. last chance effect). When true,
## particle emission is paused and emitter position is not updated.
var _time_stopped: bool = false


func _ready() -> void:
	# Snow is always on from the start
	emitting = true
	_log("Snow started (continuous mode, world-space emitters)")


func _process(_delta: float) -> void:
	# While time is stopped, do not spawn new flakes or update emitter position.
	if _time_stopped:
		return

	# Keep emitters centered on the current camera so new flakes always
	# spawn within the visible viewport area. Already-spawned flakes remain
	# at their world positions — the snow does not follow the player.
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var cam_pos := camera.get_screen_center_position()
	if _flakes_large:
		_flakes_large.global_position = cam_pos
	if _flakes_small:
		_flakes_small.global_position = cam_pos


## Pauses or resumes particle emission for time-stop effects (e.g. last chance).
## When paused is true, both particle layers stop emitting immediately.
## When paused is false, emission resumes.
func set_time_stopped(paused: bool) -> void:
	if _time_stopped == paused:
		return
	_time_stopped = paused
	emitting = not paused
	_log("Snow %s (time %s)" % ["paused" if paused else "resumed", "stopped" if paused else "resumed"])


## Logs a snow effect message through the FileLogger autoload if available.
func _log(message: String) -> void:
	var file_logger: Node = Engine.get_singleton("FileLogger") if Engine.has_singleton("FileLogger") else null
	if file_logger == null:
		file_logger = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[SnowEffect] " + message)
	else:
		print("[SnowEffect] " + message)
