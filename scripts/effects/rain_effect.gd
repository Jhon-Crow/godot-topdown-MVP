extends GPUParticles2D
class_name RainEffect
## Top-down rain precipitation effect (Issue #1394).
##
## Provides a reusable rain particle system for top-down levels.
## Supports configurable rain intensity, intermittent (rare) rain timing,
## and indoor exclusion zones where rain should not appear.
## The effect follows the camera so rain covers the visible viewport area.

## Minimum seconds between rain episodes.
@export var min_interval: float = 15.0

## Maximum seconds between rain episodes.
@export var max_interval: float = 45.0

## Minimum duration of a rain episode in seconds.
@export var min_duration: float = 15.0

## Maximum duration of a rain episode in seconds.
@export var max_duration: float = 40.0

## Whether rain starts automatically or waits for first interval.
@export var start_raining: bool = true

## Seconds before the very first rain episode (shorter than normal interval).
@export var initial_delay: float = 0.0

## Indoor exclusion zones (rain stops when camera center is inside).
## Each Rect2 defines a rectangular area in global coordinates.
var exclusion_zones: Array[Rect2] = []

## Current camera reference for following and zone checks.
var _camera: Camera2D = null

## Whether rain is currently in an active episode.
var _episode_active: bool = false

## Whether rain is hidden due to being inside an exclusion zone.
var _inside_exclusion: bool = false

## Timer for scheduling rain episodes.
var _schedule_timer: Timer = null

## Timer for rain episode duration.
var _duration_timer: Timer = null

## Tracks if the system has been set up.
var _initialized: bool = false


func _ready() -> void:
	emitting = false
	_setup_timers()
	_initialized = true
	if start_raining:
		_start_rain_episode()
	else:
		# Use shorter initial delay so rain appears sooner in the level
		_schedule_timer.start(initial_delay)
		_log("Scheduled first rain episode in %.1f seconds" % initial_delay)


func _setup_timers() -> void:
	_schedule_timer = Timer.new()
	_schedule_timer.name = "ScheduleTimer"
	_schedule_timer.one_shot = true
	_schedule_timer.timeout.connect(_on_schedule_timeout)
	add_child(_schedule_timer)

	_duration_timer = Timer.new()
	_duration_timer.name = "DurationTimer"
	_duration_timer.one_shot = true
	_duration_timer.timeout.connect(_on_duration_timeout)
	add_child(_duration_timer)


func _process(_delta: float) -> void:
	if _camera == null:
		_find_camera()
		return

	# Follow camera position so rain always covers the visible area
	global_position = _camera.get_screen_center_position()

	# Check exclusion zones
	var camera_center := _camera.get_screen_center_position()
	var was_inside := _inside_exclusion
	_inside_exclusion = _is_point_in_exclusion_zone(camera_center)

	if _episode_active:
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


## Returns true if rain episode is currently active.
func is_raining() -> bool:
	return _episode_active and not _inside_exclusion


## Manually start a rain episode.
func start_rain() -> void:
	_start_rain_episode()


## Manually stop rain.
func stop_rain() -> void:
	_stop_rain_episode()


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


func _schedule_next_episode() -> void:
	var wait_time := randf_range(min_interval, max_interval)
	_schedule_timer.start(wait_time)
	_log("Next rain episode scheduled in %.1f seconds" % wait_time)


func _start_rain_episode() -> void:
	_episode_active = true
	if not _inside_exclusion:
		emitting = true
	var duration := randf_range(min_duration, max_duration)
	_duration_timer.start(duration)
	_schedule_timer.stop()
	_log("Rain episode STARTED (duration: %.1f seconds, emitting: %s)" % [duration, str(emitting)])


func _stop_rain_episode() -> void:
	_episode_active = false
	emitting = false
	_schedule_next_episode()
	_log("Rain episode STOPPED")


func _on_schedule_timeout() -> void:
	_start_rain_episode()


func _on_duration_timeout() -> void:
	_stop_rain_episode()


## Logs a rain effect message through the FileLogger autoload if available.
func _log(message: String) -> void:
	var file_logger: Node = Engine.get_singleton("FileLogger") if Engine.has_singleton("FileLogger") else null
	if file_logger == null:
		file_logger = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[RainEffect] " + message)
	else:
		print("[RainEffect] " + message)
