extends Node
## MusicManager - Background music playback for levels (Issue #1925).
##
## Plays a per-level background music track from `assets/audio/music/`.
##
## Behaviour required by the issue:
## - Each level plays its own track; the track loops when finished.
## - Music does NOT restart when the same level is reloaded
##   (e.g. after death/restart). This is achieved by remembering the scene
##   path and skipping playback if the new scene path matches the current one.
## - Music stops as soon as the level's exit zone activates (the level is
##   cleared and the exit appears).
## - Volume is controlled by the existing music slider in sound settings via
##   the "Music" audio bus (see `SoundSettings`).
## - A small "music by Instrumental Healthcare" credit is drawn in the
##   bottom-left corner of the screen as a persistent CanvasLayer.

## Maps a level scene path to its music file in `assets/audio/music/`.
const LEVEL_MUSIC: Dictionary = {
	"res://scenes/levels/LabyrinthLevel.tscn": "res://assets/audio/music/labyrinth.mp3",
	"res://scenes/levels/BuildingLevel.tscn": "res://assets/audio/music/building v2.mp3",
	"res://scenes/levels/TestTier.tscn": "res://assets/audio/music/polygon.mp3",
	"res://scenes/levels/CastleLevel.tscn": "res://assets/audio/music/castle.mp3",
	"res://scenes/levels/RevolverLevel.tscn": "res://assets/audio/music/double-corridor v2.mp3",
	"res://scenes/levels/CityLevel.tscn": "res://assets/audio/music/city.mp3",
	"res://scenes/levels/BeachLevel.tscn": "res://assets/audio/music/beach.mp3",
	"res://scenes/levels/DocksLevel.tscn": "res://assets/audio/music/docks.mp3",
	"res://scenes/levels/FactoryLevel.tscn": "res://assets/audio/music/factory.mp3",
	"res://scenes/levels/DecadenceLevel.tscn": "res://assets/audio/music/decadence.mp3",
	"res://scenes/levels/Labyrinth2Level.tscn": "res://assets/audio/music/labyrinth-complex.mp3",
	"res://scenes/levels/SewerLevel.tscn": "res://assets/audio/music/sewer.mp3",
	"res://scenes/levels/WinterForestLevel.tscn": "res://assets/audio/music/winter-forest.mp3",
	"res://scenes/levels/RailwayStationLevel.tscn": "res://assets/audio/music/railway-station(fixed).mp3",
}

## Name of the audio bus that the music slider in sound settings drives.
const MUSIC_BUS: String = "Music"

## Credit text drawn in the bottom-left of the GUI.
const CREDIT_TEXT: String = "music by Instrumental Healthcare"

## Margin from the screen edges for the credit label.
const CREDIT_MARGIN: Vector2 = Vector2(8.0, 8.0)

## AudioStreamPlayer used for music playback.
var _player: AudioStreamPlayer = null

## CanvasLayer hosting the credit label.
var _credit_canvas: CanvasLayer = null

## Label showing the music credit.
var _credit_label: Label = null

## Path of the scene whose music is currently playing (or queued).
var _current_scene_path: String = ""

## Set to true once we've connected to at least one ExitZone in the current
## scene, so we stop walking the scene tree every frame.
var _exit_zones_connected: bool = false


func _ready() -> void:
	_ensure_music_bus()
	_create_player()
	_create_credit_label()

	# Detect scene changes so we can switch tracks. Connecting to
	# `tree_changed` is too noisy; we instead watch the SceneTree's
	# current scene each frame (cheap pointer/string compare).
	set_process(true)

	# Sync once at startup (the autoload may be ready before the scene tree
	# settles or after — handle both via the deferred call).
	call_deferred("_sync_to_current_scene")


func _process(_delta: float) -> void:
	_sync_to_current_scene()


## Ensures the "Music" audio bus exists so that `SoundSettings.set_music_volume`
## has a target. The default Godot project ships with only the Master bus, so
## we create one programmatically when the project hasn't defined a custom
## bus layout.
func _ensure_music_bus() -> void:
	if AudioServer.get_bus_index(MUSIC_BUS) >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, MUSIC_BUS)
	AudioServer.set_bus_send(idx, "Master")
	# SoundSettings ran first and tried to apply the music volume to a bus
	# that did not yet exist. Re-apply it now that the bus is available so
	# the slider's persisted value takes effect from the first frame.
	var sound_settings: Node = get_node_or_null("/root/SoundSettings")
	if sound_settings and sound_settings.has_method("_apply_music_volume"):
		sound_settings._apply_music_volume()


func _create_player() -> void:
	_player = AudioStreamPlayer.new()
	_player.name = "MusicStreamPlayer"
	_player.bus = MUSIC_BUS
	# Music must continue playing even when the game is paused (settings menu).
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.finished.connect(_on_player_finished)
	add_child(_player)


func _create_credit_label() -> void:
	_credit_canvas = CanvasLayer.new()
	_credit_canvas.name = "MusicCreditCanvas"
	# High layer so it sits above level UI but the value is below FpsMonitor's
	# debug overlay (200) so it doesn't overlap performance HUD elements.
	_credit_canvas.layer = 100
	add_child(_credit_canvas)

	_credit_label = Label.new()
	_credit_label.name = "MusicCreditLabel"
	_credit_label.text = CREDIT_TEXT
	_credit_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_credit_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_credit_label.add_theme_constant_override("shadow_offset_x", 1)
	_credit_label.add_theme_constant_override("shadow_offset_y", 1)
	_credit_label.add_theme_font_size_override("font_size", 12)
	_credit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor to the bottom-left corner of the viewport.
	_credit_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_credit_label.position = Vector2(CREDIT_MARGIN.x, -CREDIT_MARGIN.y)
	_credit_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_credit_canvas.add_child(_credit_label)


## Looks up the currently active scene and switches the playing track if the
## scene path has changed. Reloading the same scene is a no-op so the track
## keeps playing seamlessly across restarts.
func _sync_to_current_scene() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null:
		return
	var path: String = scene.scene_file_path
	if path == _current_scene_path:
		# Levels add their ExitZone via `call_deferred` during _ready, so the
		# zone may not exist yet on the first sync. Keep retrying until we
		# successfully connect to one.
		if not _exit_zones_connected:
			_exit_zones_connected = _connect_exit_zones(scene)
		return

	_current_scene_path = path
	_exit_zones_connected = _connect_exit_zones(scene)
	_play_track_for_path(path)


## Plays the music associated with `scene_path`. If there is no mapping for
## the scene, any currently playing track is stopped.
func _play_track_for_path(scene_path: String) -> void:
	if _player == null:
		return
	if not LEVEL_MUSIC.has(scene_path):
		_player.stop()
		_player.stream = null
		return

	var music_path: String = LEVEL_MUSIC[scene_path]
	var stream: AudioStream = load(music_path)
	if stream == null:
		push_warning("[MusicManager] Failed to load music: %s" % music_path)
		_player.stop()
		_player.stream = null
		return

	# Looping is enforced in `_on_player_finished` so it works for both
	# AudioStreamMP3 (which has its own `loop` property) and any other stream
	# type Godot may import the file as.
	if stream.has_method("set_loop"):
		stream.set_loop(true)
	elif "loop" in stream:
		stream.loop = true

	_player.stream = stream
	_player.play()


## Restart the track when it ends (covers stream types that don't loop
## natively).
func _on_player_finished() -> void:
	if _player and _player.stream:
		_player.play()


## Connects to the `activated` signal on every ExitZone in the current scene
## so the music can stop the moment the level is cleared. Returns true when
## at least one ExitZone was found (so the caller can stop walking the tree
## every frame).
func _connect_exit_zones(scene: Node) -> bool:
	var any_found := false
	for node in _find_exit_zones(scene):
		any_found = true
		if node.has_signal("activated") and not node.activated.is_connected(_on_exit_zone_activated):
			node.activated.connect(_on_exit_zone_activated)
		# If the exit was already active before we connected (e.g. a level
		# starts cleared), stop immediately.
		if "_is_active" in node and node._is_active:
			_on_exit_zone_activated()
	return any_found


## Recursively collect ExitZone nodes (Area2D with the `activate` method).
func _find_exit_zones(node: Node) -> Array:
	var found: Array = []
	if node == null:
		return found
	if node is Area2D and node.has_method("activate") and node.has_signal("activated"):
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_exit_zones(child))
	return found


## Stop music when the level is cleared (exit zone activated).
func _on_exit_zone_activated() -> void:
	if _player and _player.playing:
		_player.stop()


## Public API: returns the currently mapped music path for a scene, or
## an empty string if none. Used by tests and external integrations.
func get_music_path_for_scene(scene_path: String) -> String:
	return LEVEL_MUSIC.get(scene_path, "")


## Public API: returns true when the music player is currently playing.
func is_playing() -> bool:
	return _player != null and _player.playing
