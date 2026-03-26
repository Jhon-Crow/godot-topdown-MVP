extends Node2D
class_name SnowEffect
## Top-down snowfall effect for the Winter Forest map (Issue #1548).
##
## Two-layer particle system rendered on a CanvasLayer (screen space) so snow
## always covers the visible viewport regardless of camera position:
##   - SnowFlakesLarge: larger circular flakes with inward radial velocity (fish-eye top-down perspective)
##   - SnowFlakesSmall: smaller circular flakes at slower inward radial velocity for depth variation
##
## Particles use negative radial_velocity so they move inward toward screen center,
## matching the top-down falling appearance of the RainEffect (Issue #1394).
##
## Snow is always active (continuous) while on the Winter Forest map.
## No exclusion zones needed — the level is fully outdoor.

## Snow canvas layer node (defined in .tscn).
@onready var _snow_canvas: CanvasLayer = $SnowCanvas

## Large snowflake particle node (defined in .tscn).
@onready var _flakes_large: GPUParticles2D = $SnowCanvas/SnowFlakesLarge

## Small snowflake particle node (defined in .tscn).
@onready var _flakes_small: GPUParticles2D = $SnowCanvas/SnowFlakesSmall

## Controls emission state of both particle layers.
var emitting: bool = false:
	set(value):
		emitting = value
		if _flakes_large:
			_flakes_large.emitting = value
		if _flakes_small:
			_flakes_small.emitting = value


func _ready() -> void:
	# Snow is always on from the start
	emitting = true
	_log("Snow started (continuous mode)")


## Logs a snow effect message through the FileLogger autoload if available.
func _log(message: String) -> void:
	var file_logger: Node = Engine.get_singleton("FileLogger") if Engine.has_singleton("FileLogger") else null
	if file_logger == null:
		file_logger = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[SnowEffect] " + message)
	else:
		print("[SnowEffect] " + message)
