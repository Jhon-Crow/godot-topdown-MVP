extends Node2D
class_name SnowEffect
## Top-down snowfall effect for the Winter Forest map (Issue #1548).
##
## Single-layer particle system rendered on a CanvasLayer (screen space) so snow
## always covers the visible viewport regardless of camera position:
##   - SnowFlakes: simple square particles drifting downward with gentle horizontal sway
##
## Snow is always active (continuous) while on the Winter Forest map.
## No exclusion zones needed — the level is fully outdoor.

## Snow canvas layer node (defined in .tscn).
@onready var _snow_canvas: CanvasLayer = $SnowCanvas

## Snowflake particle node (defined in .tscn).
@onready var _flakes: GPUParticles2D = $SnowCanvas/SnowFlakes

## Controls emission state of the particle layer.
var emitting: bool = false:
	set(value):
		emitting = value
		if _flakes:
			_flakes.emitting = value


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
