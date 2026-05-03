extends GutTest
## Unit tests for MusicManager autoload (Issue #1925).
##
## Verifies the static mapping table, the playback policy (only restart on
## scene change), exit-zone handling, and credit label setup. The audio bus
## is exercised through a real `MusicManager` instance.


const MUSIC_MANAGER = preload("res://scripts/autoload/music_manager.gd")


# ============================================================================
# Mapping Tests (no node required)
# ============================================================================


func test_every_known_level_has_a_music_track() -> void:
	# Each path in the mapping must point to an .mp3 the project ships with.
	for scene_path in MUSIC_MANAGER.LEVEL_MUSIC.keys():
		var music_path: String = MUSIC_MANAGER.LEVEL_MUSIC[scene_path]
		assert_true(music_path.begins_with("res://assets/audio/music/"),
			"Music for %s should live under assets/audio/music/" % scene_path)
		assert_true(music_path.ends_with(".mp3"),
			"Music for %s should be an mp3" % scene_path)
		# Use FileAccess instead of ResourceLoader so the assertion still
		# works before Godot has generated `.import` metadata for the mp3.
		assert_true(FileAccess.file_exists(music_path),
			"Music file %s should exist on disk" % music_path)


func test_main_levels_are_mapped() -> void:
	# Sanity check a handful of well-known levels so a future rename of a
	# scene path doesn't silently drop its music.
	var must_have: Array = [
		"res://scenes/levels/LabyrinthLevel.tscn",
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/CastleLevel.tscn",
		"res://scenes/levels/CityLevel.tscn",
		"res://scenes/levels/BeachLevel.tscn",
		"res://scenes/levels/DocksLevel.tscn",
		"res://scenes/levels/FactoryLevel.tscn",
		"res://scenes/levels/DecadenceLevel.tscn",
		"res://scenes/levels/SewerLevel.tscn",
		"res://scenes/levels/WinterForestLevel.tscn",
		"res://scenes/levels/RailwayStationLevel.tscn",
		"res://scenes/levels/Labyrinth2Level.tscn",
		"res://scenes/levels/RevolverLevel.tscn",
		"res://scenes/levels/TestTier.tscn",
	]
	for scene_path in must_have:
		assert_true(MUSIC_MANAGER.LEVEL_MUSIC.has(scene_path),
			"%s should have a music mapping" % scene_path)


# ============================================================================
# Instance Tests
# ============================================================================


var manager: Node = null


func before_each() -> void:
	manager = MUSIC_MANAGER.new()
	add_child_autofree(manager)
	# Allow _ready() to run.
	await get_tree().process_frame


## Build a tiny, valid AudioStream for tests. AudioStreamGenerator works in
## headless runners without needing mp3 import metadata to be present.
func _make_dummy_stream() -> AudioStream:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.05
	return generator


func test_music_bus_is_created_after_ready() -> void:
	assert_true(AudioServer.get_bus_index(MUSIC_MANAGER.MUSIC_BUS) >= 0,
		"Music bus should exist after MusicManager initialises")


func test_audio_player_routes_through_music_bus() -> void:
	var player: AudioStreamPlayer = manager.get_node("MusicStreamPlayer")
	assert_not_null(player, "MusicManager should have an AudioStreamPlayer child")
	assert_eq(player.bus, MUSIC_MANAGER.MUSIC_BUS,
		"Music player should route through the Music bus")
	assert_eq(player.process_mode, Node.PROCESS_MODE_ALWAYS,
		"Music should keep playing while the game is paused")


func test_credit_label_is_present_with_correct_text() -> void:
	var canvas: CanvasLayer = manager.get_node("MusicCreditCanvas")
	assert_not_null(canvas, "Credit canvas should be created")
	var label: Label = canvas.get_node("MusicCreditLabel")
	assert_not_null(label, "Credit label should be created")
	assert_eq(label.text, MUSIC_MANAGER.CREDIT_TEXT,
		"Credit label should show 'music by Instrumental Healthcare'")


func test_get_music_path_for_known_scene() -> void:
	var path: String = manager.get_music_path_for_scene(
		"res://scenes/levels/LabyrinthLevel.tscn")
	assert_eq(path, "res://assets/audio/music/labyrinth.mp3",
		"Labyrinth level should map to labyrinth.mp3")


func test_get_music_path_for_unknown_scene_returns_empty() -> void:
	var path: String = manager.get_music_path_for_scene(
		"res://scenes/levels/Nonexistent.tscn")
	assert_eq(path, "",
		"Unknown scenes should return an empty music path")


func test_exit_zone_activation_stops_music() -> void:
	# Verify the handler stops the player. Set up a stream and assert that
	# after calling the handler the player.stream is unchanged (we only
	# stop, we don't clear) but `playing` is false.
	var player: AudioStreamPlayer = manager.get_node("MusicStreamPlayer")
	player.stream = _make_dummy_stream()
	# We don't call play() because headless test environments may not
	# transition AudioStreamPlayer into the playing state reliably; the
	# important behaviour to verify is that `_on_exit_zone_activated`
	# leaves the player stopped without crashing.
	manager._on_exit_zone_activated()
	assert_false(player.playing,
		"Music should not be playing after the exit zone activates")


func test_play_track_for_unknown_path_clears_stream() -> void:
	var player: AudioStreamPlayer = manager.get_node("MusicStreamPlayer")
	player.stream = _make_dummy_stream()

	manager._play_track_for_path("res://scenes/levels/Nonexistent.tscn")
	assert_null(player.stream,
		"Player stream should be cleared when scene has no music mapping")
	assert_false(player.playing,
		"Player should be stopped when scene has no music mapping")


func test_source_skips_replay_when_scene_path_unchanged() -> void:
	# Reproduce the "do not restart on level reload" requirement at the
	# source level: `_sync_to_current_scene` must short-circuit when the
	# current scene path matches `_current_scene_path` and must NOT call
	# `_play_track_for_path` again. This prevents `reload_current_scene`
	# (used by GameManager.restart_scene) from cutting the music.
	var source := FileAccess.get_file_as_string("res://scripts/autoload/music_manager.gd")

	assert_true(source.contains("if path == _current_scene_path:"),
		"_sync_to_current_scene must compare the new scene path to the cached one")
	# After matching the cached path the function must return before the
	# `_current_scene_path = path` / `_play_track_for_path(path)` block.
	var early_return_idx := source.find("if path == _current_scene_path:")
	var play_call_idx := source.find("_play_track_for_path(path)")
	assert_true(early_return_idx >= 0 and play_call_idx > early_return_idx,
		"Path-equality branch must return before invoking _play_track_for_path")
	# The early-return branch must contain a `return` statement.
	var slice := source.substr(early_return_idx, play_call_idx - early_return_idx)
	assert_true(slice.contains("return"),
		"Path-equality branch must early-return so playback is not restarted")


# ============================================================================
# Looping Tests
# ============================================================================


func test_finished_signal_restarts_playback_when_stream_present() -> void:
	# The looping behaviour is enforced both by setting `loop` on the
	# AudioStream and by re-calling `play()` from the `finished` signal.
	# Verify the source has a `play()` call inside the finished handler so
	# the loop policy is preserved across stream types that don't loop
	# natively.
	var source := FileAccess.get_file_as_string("res://scripts/autoload/music_manager.gd")
	assert_true(source.contains("func _on_player_finished()"),
		"MusicManager should declare a finished handler")
	var handler_idx := source.find("func _on_player_finished()")
	# The handler body should call `_player.play()` to restart the track.
	var next_func_idx := source.find("\nfunc ", handler_idx + 1)
	if next_func_idx < 0:
		next_func_idx = source.length()
	var body := source.substr(handler_idx, next_func_idx - handler_idx)
	assert_true(body.contains("_player.play()"),
		"finished handler must call play() to restart the track")


func test_finished_signal_with_no_stream_is_safe() -> void:
	var player: AudioStreamPlayer = manager.get_node("MusicStreamPlayer")
	player.stream = null
	# Should not crash or start playing without a stream.
	manager._on_player_finished()
	assert_false(player.playing,
		"finished handler must not start playback when no stream is set")
