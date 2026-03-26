extends CanvasLayer
## Issue #997: Background level loading with loading screen to prevent FPS drops.
##
## This autoload handles level transitions with:
## - Background loading using ResourceLoader.load_threaded_request()
## - Simple fade-to-black loading screen with progress indicator
## - Prevents FPS drops during level loading by loading scenes asynchronously
##
## Usage:
##   SceneLoader.load_level("res://scenes/levels/DocksLevel.tscn")

const FADE_DURATION: float = 0.3  ## Duration of fade in/out transitions

## Reference to the loading screen overlay
var _loading_overlay: ColorRect
var _loading_label: Label
var _progress_bar: ProgressBar
var _current_load_path: String = ""
var _is_loading: bool = false

## Log a message to the file logger (consistent with other autoloads).
## Issue #1293: print() fallback gated to debug builds to avoid FPS drops.
func _log(msg: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[SceneLoader] " + msg)
	elif OS.is_debug_build():
		print("[SceneLoader] " + msg)


func _ready() -> void:
	layer = 100  # On top of everything
	process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when paused
	_create_loading_overlay()
	_log("SceneLoader initialized")


## Create the loading screen overlay (hidden by default)
func _create_loading_overlay() -> void:
	_loading_overlay = ColorRect.new()
	_loading_overlay.name = "LoadingOverlay"
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.color = Color(0, 0, 0, 1)
	_loading_overlay.visible = false
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input during loading
	add_child(_loading_overlay)

	# Center container for loading content
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	# Loading text
	_loading_label = Label.new()
	_loading_label.text = "LOADING..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 24)
	_loading_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
	vbox.add_child(_loading_label)

	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(300, 20)
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	vbox.add_child(_progress_bar)


## Load a level asynchronously with a loading screen.
## @param level_path: The resource path to the level scene
func load_level(level_path: String) -> void:
	if _is_loading:
		_log("Already loading a level, ignoring request for: %s" % level_path)
		return

	if not ResourceLoader.exists(level_path):
		_log("ERROR: Level path does not exist: %s" % level_path)
		return

	_log("Starting background load for: %s" % level_path)
	_is_loading = true
	_current_load_path = level_path

	# Show loading screen with fade
	_loading_overlay.visible = true
	_loading_overlay.modulate.a = 0.0
	_progress_bar.value = 0.0

	var fade_tween := create_tween()
	fade_tween.tween_property(_loading_overlay, "modulate:a", 1.0, FADE_DURATION)
	fade_tween.tween_callback(_start_background_load)


## Start the background loading after fade in
func _start_background_load() -> void:
	# Issue #1526: Check if resource is already cached. In Godot 4.3, requesting a
	# threaded load for an already-loaded resource can return INVALID_RESOURCE during
	# polling, causing a freeze from the sync fallback. Use the cache directly instead.
	if ResourceLoader.has_cached(_current_load_path):
		_log("Resource already cached, skipping threaded load: %s" % _current_load_path)
		var cached := load(_current_load_path) as PackedScene
		if cached:
			get_tree().paused = false
			get_tree().change_scene_to_packed(cached)
			_log("Scene changed successfully (from cache)")
			var fade_tween := create_tween()
			fade_tween.tween_property(_loading_overlay, "modulate:a", 0.0, FADE_DURATION)
			fade_tween.tween_callback(_hide_loading_screen)
			return
	# Request background loading
	var error := ResourceLoader.load_threaded_request(_current_load_path, "", true)
	if error != OK:
		_log("ERROR: Failed to start threaded load, falling back to sync: %s" % _current_load_path)
		_fallback_sync_load()
		return

	_log("Background load started successfully")
	set_process(true)  # Enable process to poll loading status


func _process(_delta: float) -> void:
	if not _is_loading:
		set_process(false)
		return

	# Poll loading status
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_current_load_path, progress)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# Update progress bar
			if progress.size() > 0:
				_progress_bar.value = progress[0]

		ResourceLoader.THREAD_LOAD_LOADED:
			_log("Background load complete: %s" % _current_load_path)
			_progress_bar.value = 1.0
			_on_load_complete()

		ResourceLoader.THREAD_LOAD_FAILED:
			_log("ERROR: Background load failed: %s" % _current_load_path)
			_fallback_sync_load()

		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			# Issue #1456: treat invalid-resource the same as failed — fall back to
			# synchronous loading so the scene transition still completes.
			_log("ERROR: Invalid resource (falling back to sync): %s" % _current_load_path)
			_fallback_sync_load()


## Called when background loading is complete
func _on_load_complete() -> void:
	set_process(false)

	# Get the loaded resource
	var loaded_scene: PackedScene = ResourceLoader.load_threaded_get(_current_load_path)
	if not loaded_scene:
		_log("ERROR: Failed to get loaded scene")
		_hide_loading_screen()
		return

	# Unpause before changing scene
	get_tree().paused = false

	# Change to the loaded scene
	var error := get_tree().change_scene_to_packed(loaded_scene)
	if error != OK:
		_log("ERROR: Failed to change to loaded scene: %s" % error)
	else:
		_log("Scene changed successfully")

	# Fade out loading screen
	var fade_tween := create_tween()
	fade_tween.tween_property(_loading_overlay, "modulate:a", 0.0, FADE_DURATION)
	fade_tween.tween_callback(_hide_loading_screen)


## Hide loading screen and reset state
func _hide_loading_screen() -> void:
	_loading_overlay.visible = false
	_is_loading = false
	_current_load_path = ""


## Fallback to synchronous loading if threaded loading fails
func _fallback_sync_load() -> void:
	_log("Using synchronous load fallback")
	var loaded_scene := load(_current_load_path) as PackedScene
	if loaded_scene:
		get_tree().paused = false
		get_tree().change_scene_to_packed(loaded_scene)
	_hide_loading_screen()
