extends Node
## FpsMonitor - Monitors frames per second, displays an on-screen counter,
## and logs FPS drops to the log file.
##
## Controlled by ExperimentalSettings:
##   - fps_counter_enabled: show on-screen FPS label (default: off)
##   - fps_drop_logging_enabled: log to file when FPS < FPS_DROP_THRESHOLD (default: off)
##
## Issue #883: Added as part of performance monitoring for enemy raycast optimization.
## Issue #1460 Round 6: Added per-frame spike detection to catch sub-second frame drops
## (the old 1-second average missed explosion spikes that last only 1-3 frames).

## FPS below this value is considered a drop and will be logged.
const FPS_DROP_THRESHOLD: int = 30

## Frame time above this threshold (ms) is a spike and will be logged immediately.
## 33ms = ~30fps equivalent for a single frame. A single frame taking >33ms is a spike
## even if the 1-second average stays above 30fps.
const FRAME_SPIKE_THRESHOLD_MS: float = 33.0

## How often (in seconds) to sample average FPS and check for sustained drops.
const SAMPLE_INTERVAL: float = 1.0

## Minimum seconds between spike log entries to avoid log spam.
const SPIKE_LOG_COOLDOWN: float = 0.5

## Label node used for the on-screen FPS counter.
var _fps_label: Label = null

## Accumulated time since last sample.
var _sample_timer: float = 0.0

## Last sampled FPS value.
var _last_fps: int = 0

## Time since last spike was logged (to prevent log spam).
var _spike_log_cooldown: float = 0.0


func _ready() -> void:
	_create_fps_label()
	# Sync visibility with current settings
	_apply_settings()
	# Connect to settings changes
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_signal("settings_changed"):
		experimental_settings.settings_changed.connect(_apply_settings)


## Create the persistent on-screen FPS label.
func _create_fps_label() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 200  # Above everything else
	add_child(canvas)

	_fps_label = Label.new()
	_fps_label.name = "FpsLabel"
	_fps_label.position = Vector2(10, 10)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 0, 1))
	_fps_label.add_theme_font_size_override("font_size", 16)
	_fps_label.visible = false
	canvas.add_child(_fps_label)


## Called every frame; updates the FPS counter and checks for drops.
func _process(delta: float) -> void:
	# Issue #1460 Round 6: Check for per-frame spikes EVERY frame, not just every second.
	# A spike that takes 50ms (20fps for one frame) will NOT show in a 1-second average
	# if other frames are fast. We log it immediately so the log captures spike timing.
	_spike_log_cooldown -= delta
	if _spike_log_cooldown <= 0.0:
		var frame_ms := delta * 1000.0
		if frame_ms > FRAME_SPIKE_THRESHOLD_MS:
			var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
			var logging_drops: bool = experimental_settings != null and \
				experimental_settings.has_method("is_fps_drop_logging_enabled") and \
				experimental_settings.is_fps_drop_logging_enabled()
			if logging_drops:
				var fps_this_frame := int(1000.0 / frame_ms)
				var fl: Node = get_node_or_null("/root/FileLogger")
				if fl and fl.has_method("log_warning"):
					fl.log_warning("[FPS] Frame spike: %.1fms (%dfps this frame, threshold: %.0fms)" % [
						frame_ms, fps_this_frame, FRAME_SPIKE_THRESHOLD_MS])
				_spike_log_cooldown = SPIKE_LOG_COOLDOWN

	_sample_timer += delta
	if _sample_timer < SAMPLE_INTERVAL:
		return

	_sample_timer = 0.0
	_last_fps = int(Engine.get_frames_per_second())

	# Update on-screen label if visible
	if _fps_label and _fps_label.visible:
		_fps_label.text = "FPS: %d" % _last_fps

	# Log sustained drops if enabled (averaged over 1 second)
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	var logging_drops: bool = experimental_settings != null and \
		experimental_settings.has_method("is_fps_drop_logging_enabled") and \
		experimental_settings.is_fps_drop_logging_enabled()

	if logging_drops and _last_fps < FPS_DROP_THRESHOLD:
		var fl: Node = get_node_or_null("/root/FileLogger")
		if fl and fl.has_method("log_warning"):
			fl.log_warning("[FPS] Sustained drop: %d fps avg (threshold: %d)" % [_last_fps, FPS_DROP_THRESHOLD])


## Apply current experimental settings (counter visibility).
func _apply_settings() -> void:
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings == null or _fps_label == null:
		return
	var show_counter: bool = experimental_settings.has_method("is_fps_counter_enabled") and \
		experimental_settings.is_fps_counter_enabled()
	_fps_label.visible = show_counter
	# If counter just became visible, show current FPS immediately
	if show_counter:
		_fps_label.text = "FPS: %d" % int(Engine.get_frames_per_second())
