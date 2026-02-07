extends GutTest
## Unit tests for ReplaySystem autoload.
##
## Tests the replay recording and playback functionality including state
## transitions, frame data structure, speed control, seek operations,
## max duration enforcement, and clear behavior.


# Mock class that mirrors ReplaySystem's testable functionality
# without depending on Godot scene tree, nodes, or autoloads
class MockReplaySystem:
	## Recording interval in seconds (physics frames).
	const RECORD_INTERVAL: float = 1.0 / 60.0  # 60 FPS recording

	## Maximum recording duration in seconds (prevent memory issues).
	const MAX_RECORDING_DURATION: float = 300.0  # 5 minutes

	## All recorded frames for the current/last level.
	var _frames: Array = []

	## Current recording time.
	var _recording_time: float = 0.0

	## Whether we are currently recording.
	var _is_recording: bool = false

	## Whether we are currently playing back.
	var _is_playing_back: bool = false

	## Whether playback ending is scheduled.
	var _playback_ending: bool = false

	## Timer for playback end delay.
	var _playback_end_timer: float = 0.0

	## Current playback frame index.
	var _playback_frame: int = 0

	## Playback speed multiplier (1.0 = normal, 2.0 = 2x speed).
	var _playback_speed: float = 1.0

	## Accumulated time for playback interpolation.
	var _playback_time: float = 0.0

	## Signal emitted when replay playback ends.
	signal replay_ended

	## Signal emitted when replay playback starts.
	signal replay_started

	## Signal emitted when playback progress changes.
	signal playback_progress(current_time: float, total_time: float)


	## Creates a new frame data dictionary with default values.
	func _create_frame_data() -> Dictionary:
		return {
			"time": 0.0,
			"player_position": Vector2.ZERO,
			"player_rotation": 0.0,
			"player_model_scale": Vector2.ONE,
			"player_alive": true,
			"enemies": [],
			"bullets": [],
			"grenades": [],
			"events": []
		}


	## Starts recording a new replay.
	func start_recording() -> void:
		_frames.clear()
		_recording_time = 0.0
		_is_recording = true
		_is_playing_back = false


	## Stops recording and saves the replay data.
	func stop_recording() -> void:
		if not _is_recording:
			return
		_is_recording = false


	## Returns true if there is a recorded replay available.
	func has_replay() -> bool:
		return _frames.size() > 0


	## Returns the duration of the recorded replay in seconds.
	func get_replay_duration() -> float:
		if _frames.is_empty():
			return 0.0
		return _frames[-1].time


	## Starts playback of the recorded replay.
	func start_playback() -> void:
		if _frames.is_empty():
			return
		_is_playing_back = true
		_is_recording = false
		_playback_ending = false
		_playback_end_timer = 0.0
		_playback_frame = 0
		_playback_time = 0.0
		_playback_speed = 1.0
		replay_started.emit()


	## Stops playback and cleans up.
	func stop_playback() -> void:
		if not _is_playing_back and not _playback_ending:
			return
		_is_playing_back = false
		_playback_ending = false
		_playback_end_timer = 0.0
		replay_ended.emit()


	## Sets the playback speed.
	func set_playback_speed(speed: float) -> void:
		_playback_speed = clampf(speed, 0.25, 4.0)


	## Gets the current playback speed.
	func get_playback_speed() -> float:
		return _playback_speed


	## Returns whether replay is currently playing.
	func is_replaying() -> bool:
		return _is_playing_back


	## Returns whether replay is currently recording.
	func is_recording() -> bool:
		return _is_recording


	## Clears the recorded replay data.
	func clear_replay() -> void:
		_frames.clear()
		_recording_time = 0.0
		_is_recording = false


	## Seeks to a specific time in the replay.
	func seek_to(time: float) -> void:
		if _frames.is_empty():
			return
		time = clampf(time, 0.0, get_replay_duration())
		_playback_time = time
		# Find the frame at or before this time
		for i in range(_frames.size()):
			if _frames[i].time >= time:
				_playback_frame = maxi(0, i - 1)
				break


	## Simulates recording a frame with a given delta (mirrors _record_frame).
	func simulate_record_frame(delta: float) -> void:
		if not _is_recording:
			return
		_recording_time += delta
		# Check max duration
		if _recording_time > MAX_RECORDING_DURATION:
			stop_recording()
			return
		var frame := _create_frame_data()
		frame.time = _recording_time
		_frames.append(frame)


	## Simulates playback frame update (mirrors _playback_frame_update).
	func simulate_playback_frame_update(delta: float) -> void:
		if _frames.is_empty():
			stop_playback()
			return
		# Advance playback time
		_playback_time += delta * _playback_speed
		# Emit progress signal
		playback_progress.emit(_playback_time, get_replay_duration())
		# Check if playback is complete
		if _playback_time >= get_replay_duration():
			_playback_time = get_replay_duration()
			# Schedule playback end after a short delay
			_playback_ending = true
			_playback_end_timer = 0.5
			_is_playing_back = false
			return
		# Find the frame to display
		while _playback_frame < _frames.size() - 1 and _frames[_playback_frame + 1].time <= _playback_time:
			_playback_frame += 1


	## Simulates physics process for playback ending timer.
	func simulate_physics_process(delta: float) -> void:
		if _is_recording:
			simulate_record_frame(delta)
		elif _playback_ending:
			_playback_end_timer -= delta
			if _playback_end_timer <= 0.0:
				_playback_ending = false
				stop_playback()
		elif _is_playing_back:
			simulate_playback_frame_update(delta)


	## Helper: add a frame with specific time directly for testing.
	func _add_test_frame(time: float) -> void:
		var frame := _create_frame_data()
		frame.time = time
		_frames.append(frame)


var replay: MockReplaySystem


func before_each() -> void:
	replay = MockReplaySystem.new()


func after_each() -> void:
	replay = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_record_interval_is_60fps() -> void:
	var expected := 1.0 / 60.0
	assert_almost_eq(MockReplaySystem.RECORD_INTERVAL, expected, 0.0001,
		"RECORD_INTERVAL should be 1/60 second for 60 FPS recording")


func test_max_recording_duration_is_300_seconds() -> void:
	assert_eq(MockReplaySystem.MAX_RECORDING_DURATION, 300.0,
		"MAX_RECORDING_DURATION should be 300 seconds (5 minutes)")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_frames_empty() -> void:
	assert_eq(replay._frames.size(), 0,
		"Frames array should be empty initially")


func test_initial_recording_time_zero() -> void:
	assert_eq(replay._recording_time, 0.0,
		"Recording time should be 0.0 initially")


func test_initial_is_recording_false() -> void:
	assert_false(replay.is_recording(),
		"is_recording() should return false initially")


func test_initial_is_replaying_false() -> void:
	assert_false(replay.is_replaying(),
		"is_replaying() should return false initially")


func test_initial_playback_speed_is_one() -> void:
	assert_eq(replay.get_playback_speed(), 1.0,
		"Playback speed should be 1.0 initially")


func test_initial_playback_frame_zero() -> void:
	assert_eq(replay._playback_frame, 0,
		"Playback frame index should be 0 initially")


func test_initial_playback_time_zero() -> void:
	assert_eq(replay._playback_time, 0.0,
		"Playback time should be 0.0 initially")


func test_initial_playback_ending_false() -> void:
	assert_false(replay._playback_ending,
		"Playback ending flag should be false initially")


func test_initial_playback_end_timer_zero() -> void:
	assert_eq(replay._playback_end_timer, 0.0,
		"Playback end timer should be 0.0 initially")


func test_initial_has_replay_false() -> void:
	assert_false(replay.has_replay(),
		"has_replay() should return false initially with no frames")


func test_initial_get_replay_duration_zero() -> void:
	assert_eq(replay.get_replay_duration(), 0.0,
		"get_replay_duration() should return 0.0 with no frames")


# ============================================================================
# Frame Data Structure Tests
# ============================================================================


func test_create_frame_data_returns_dictionary() -> void:
	var frame := replay._create_frame_data()
	assert_typeof(frame, TYPE_DICTIONARY,
		"_create_frame_data() should return a Dictionary")


func test_create_frame_data_has_time_key() -> void:
	var frame := replay._create_frame_data()
	assert_true(frame.has("time"),
		"Frame data should have 'time' key")
	assert_eq(frame.time, 0.0,
		"Default time should be 0.0")


func test_create_frame_data_has_player_position() -> void:
	var frame := replay._create_frame_data()
	assert_true(frame.has("player_position"),
		"Frame data should have 'player_position' key")
	assert_eq(frame.player_position, Vector2.ZERO,
		"Default player_position should be Vector2.ZERO")


func test_create_frame_data_has_player_rotation() -> void:
	var frame := replay._create_frame_data()
	assert_true(frame.has("player_rotation"),
		"Frame data should have 'player_rotation' key")
	assert_eq(frame.player_rotation, 0.0,
		"Default player_rotation should be 0.0")


func test_create_frame_data_has_player_model_scale() -> void:
	var frame := replay._create_frame_data()
	assert_true(frame.has("player_model_scale"),
		"Frame data should have 'player_model_scale' key")
	assert_eq(frame.player_model_scale, Vector2.ONE,
		"Default player_model_scale should be Vector2.ONE")


func test_create_frame_data_has_player_alive() -> void:
	var frame := replay._create_frame_data()
	assert_true(frame.has("player_alive"),
		"Frame data should have 'player_alive' key")
	assert_true(frame.player_alive,
		"Default player_alive should be true")


func test_create_frame_data_has_enemies_array() -> void:
	var frame := replay._create_frame_data()
	assert_true(frame.has("enemies"),
		"Frame data should have 'enemies' key")
	assert_eq(frame.enemies.size(), 0,
		"Default enemies array should be empty")


func test_create_frame_data_has_bullets_array() -> void:
	var frame := replay._create_frame_data()
	assert_true(frame.has("bullets"),
		"Frame data should have 'bullets' key")
	assert_eq(frame.bullets.size(), 0,
		"Default bullets array should be empty")


func test_create_frame_data_has_grenades_array() -> void:
	var frame := replay._create_frame_data()
	assert_true(frame.has("grenades"),
		"Frame data should have 'grenades' key")
	assert_eq(frame.grenades.size(), 0,
		"Default grenades array should be empty")


func test_create_frame_data_has_events_array() -> void:
	var frame := replay._create_frame_data()
	assert_true(frame.has("events"),
		"Frame data should have 'events' key")
	assert_eq(frame.events.size(), 0,
		"Default events array should be empty")


func test_create_frame_data_has_all_nine_keys() -> void:
	var frame := replay._create_frame_data()
	var expected_keys := ["time", "player_position", "player_rotation",
		"player_model_scale", "player_alive", "enemies", "bullets",
		"grenades", "events"]
	assert_eq(frame.size(), expected_keys.size(),
		"Frame data should have exactly 9 keys")
	for key in expected_keys:
		assert_true(frame.has(key),
			"Frame data should have key '%s'" % key)


func test_create_frame_data_returns_independent_instances() -> void:
	var frame1 := replay._create_frame_data()
	var frame2 := replay._create_frame_data()
	frame1.time = 1.0
	frame1.enemies.append({"position": Vector2.ZERO})
	assert_eq(frame2.time, 0.0,
		"Modifying one frame should not affect another")
	assert_eq(frame2.enemies.size(), 0,
		"Modifying one frame's enemies should not affect another")


# ============================================================================
# Recording Lifecycle Tests
# ============================================================================


func test_start_recording_sets_is_recording_true() -> void:
	replay.start_recording()
	assert_true(replay.is_recording(),
		"is_recording() should return true after start_recording()")


func test_start_recording_clears_frames() -> void:
	# Add some frames first
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	assert_eq(replay._frames.size(), 2)

	replay.start_recording()
	assert_eq(replay._frames.size(), 0,
		"start_recording() should clear existing frames")


func test_start_recording_resets_recording_time() -> void:
	replay._recording_time = 42.0
	replay.start_recording()
	assert_eq(replay._recording_time, 0.0,
		"start_recording() should reset recording time to 0.0")


func test_start_recording_sets_is_playing_back_false() -> void:
	replay._is_playing_back = true
	replay.start_recording()
	assert_false(replay.is_replaying(),
		"start_recording() should set is_playing_back to false")


func test_stop_recording_sets_is_recording_false() -> void:
	replay.start_recording()
	assert_true(replay.is_recording())
	replay.stop_recording()
	assert_false(replay.is_recording(),
		"is_recording() should return false after stop_recording()")


func test_stop_recording_when_not_recording_is_noop() -> void:
	assert_false(replay.is_recording())
	# Should not error or change state
	replay.stop_recording()
	assert_false(replay.is_recording(),
		"stop_recording() when not recording should be a no-op")


func test_start_recording_clears_previous_replay() -> void:
	# Record some frames
	replay.start_recording()
	replay.simulate_record_frame(0.016)
	replay.simulate_record_frame(0.016)
	replay.simulate_record_frame(0.016)
	replay.stop_recording()
	assert_true(replay.has_replay())

	# Start a new recording
	replay.start_recording()
	assert_false(replay.has_replay(),
		"Starting a new recording should clear previous replay frames")


func test_recording_then_stopping_preserves_frames() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.016)
	replay.simulate_record_frame(0.016)
	replay.stop_recording()
	assert_eq(replay._frames.size(), 2,
		"Frames should be preserved after stopping recording")


# ============================================================================
# Simulate Record Frame Tests
# ============================================================================


func test_simulate_record_frame_adds_frame() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.016)
	assert_eq(replay._frames.size(), 1,
		"Should have 1 frame after recording one frame")


func test_simulate_record_frame_accumulates_time() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.016)
	assert_almost_eq(replay._recording_time, 0.016, 0.0001,
		"Recording time should accumulate delta")


func test_simulate_record_frame_sets_frame_time() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.016)
	assert_almost_eq(replay._frames[0].time, 0.016, 0.0001,
		"First frame time should equal first delta")


func test_simulate_record_multiple_frames_increments_time() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.016)
	replay.simulate_record_frame(0.016)
	replay.simulate_record_frame(0.016)
	assert_eq(replay._frames.size(), 3,
		"Should have 3 frames after recording three frames")
	assert_almost_eq(replay._frames[2].time, 0.048, 0.001,
		"Third frame time should be cumulative")


func test_simulate_record_frame_does_nothing_when_not_recording() -> void:
	# Not recording
	replay.simulate_record_frame(0.016)
	assert_eq(replay._frames.size(), 0,
		"Should not add frames when not recording")


func test_frame_time_increases_monotonically() -> void:
	replay.start_recording()
	for i in range(10):
		replay.simulate_record_frame(0.016)

	for i in range(1, replay._frames.size()):
		assert_true(replay._frames[i].time > replay._frames[i - 1].time,
			"Frame times should be strictly increasing")


# ============================================================================
# Max Recording Duration Tests
# ============================================================================


func test_max_duration_stops_recording() -> void:
	replay.start_recording()
	# Record frames just past max duration
	var delta := 1.0  # 1 second per frame for fast testing
	for i in range(301):
		if not replay.is_recording():
			break
		replay.simulate_record_frame(delta)

	assert_false(replay.is_recording(),
		"Recording should stop when max duration is exceeded")


func test_max_duration_stops_at_correct_time() -> void:
	replay.start_recording()
	# Record exactly at the boundary
	replay._recording_time = 299.9
	replay.simulate_record_frame(0.2)  # This pushes past 300.0
	assert_false(replay.is_recording(),
		"Recording should stop once _recording_time exceeds MAX_RECORDING_DURATION")


func test_max_duration_does_not_add_frame_when_exceeded() -> void:
	replay.start_recording()
	replay._recording_time = 300.1  # Already past max
	var frames_before := replay._frames.size()
	replay.simulate_record_frame(0.016)
	assert_eq(replay._frames.size(), frames_before,
		"Should not add frame when max duration is already exceeded")


func test_frames_recorded_before_max_duration_are_preserved() -> void:
	replay.start_recording()
	# Record a few frames
	replay.simulate_record_frame(100.0)
	replay.simulate_record_frame(100.0)
	replay.simulate_record_frame(100.0)
	# Third frame puts us at 300s, fourth triggers stop
	replay.simulate_record_frame(1.0)
	assert_false(replay.is_recording())
	assert_eq(replay._frames.size(), 3,
		"Frames recorded before max duration should be preserved")


# ============================================================================
# has_replay() Tests
# ============================================================================


func test_has_replay_false_when_no_frames() -> void:
	assert_false(replay.has_replay(),
		"has_replay() should be false with no frames")


func test_has_replay_true_after_recording() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.016)
	replay.stop_recording()
	assert_true(replay.has_replay(),
		"has_replay() should be true after recording frames")


func test_has_replay_true_with_manually_added_frame() -> void:
	replay._add_test_frame(1.0)
	assert_true(replay.has_replay(),
		"has_replay() should be true when frames exist")


# ============================================================================
# get_replay_duration() Tests
# ============================================================================


func test_get_replay_duration_zero_when_empty() -> void:
	assert_eq(replay.get_replay_duration(), 0.0,
		"get_replay_duration() should return 0.0 when no frames")


func test_get_replay_duration_returns_last_frame_time() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	replay._add_test_frame(3.5)
	assert_eq(replay.get_replay_duration(), 3.5,
		"get_replay_duration() should return the time of the last frame")


func test_get_replay_duration_with_single_frame() -> void:
	replay._add_test_frame(0.5)
	assert_eq(replay.get_replay_duration(), 0.5,
		"get_replay_duration() should return time of the single frame")


func test_get_replay_duration_after_recording() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.5)
	replay.simulate_record_frame(0.5)
	replay.stop_recording()
	assert_almost_eq(replay.get_replay_duration(), 1.0, 0.001,
		"get_replay_duration() should match cumulative recording time")


# ============================================================================
# Playback Speed Tests
# ============================================================================


func test_set_playback_speed_normal() -> void:
	replay.set_playback_speed(1.0)
	assert_eq(replay.get_playback_speed(), 1.0,
		"Setting speed to 1.0 should give normal speed")


func test_set_playback_speed_double() -> void:
	replay.set_playback_speed(2.0)
	assert_eq(replay.get_playback_speed(), 2.0,
		"Setting speed to 2.0 should work")


func test_set_playback_speed_half() -> void:
	replay.set_playback_speed(0.5)
	assert_eq(replay.get_playback_speed(), 0.5,
		"Setting speed to 0.5 should work")


func test_set_playback_speed_max() -> void:
	replay.set_playback_speed(4.0)
	assert_eq(replay.get_playback_speed(), 4.0,
		"Setting speed to 4.0 (max) should work")


func test_set_playback_speed_min() -> void:
	replay.set_playback_speed(0.25)
	assert_eq(replay.get_playback_speed(), 0.25,
		"Setting speed to 0.25 (min) should work")


func test_set_playback_speed_clamps_above_max() -> void:
	replay.set_playback_speed(10.0)
	assert_eq(replay.get_playback_speed(), 4.0,
		"Speed above 4.0 should be clamped to 4.0")


func test_set_playback_speed_clamps_below_min() -> void:
	replay.set_playback_speed(0.1)
	assert_eq(replay.get_playback_speed(), 0.25,
		"Speed below 0.25 should be clamped to 0.25")


func test_set_playback_speed_clamps_zero() -> void:
	replay.set_playback_speed(0.0)
	assert_eq(replay.get_playback_speed(), 0.25,
		"Speed of 0.0 should be clamped to 0.25")


func test_set_playback_speed_clamps_negative() -> void:
	replay.set_playback_speed(-1.0)
	assert_eq(replay.get_playback_speed(), 0.25,
		"Negative speed should be clamped to 0.25")


func test_set_playback_speed_very_large_value() -> void:
	replay.set_playback_speed(1000.0)
	assert_eq(replay.get_playback_speed(), 4.0,
		"Very large speed should be clamped to 4.0")


# ============================================================================
# Playback Lifecycle Tests
# ============================================================================


func test_start_playback_sets_is_playing_back() -> void:
	replay._add_test_frame(1.0)
	replay.start_playback()
	assert_true(replay.is_replaying(),
		"is_replaying() should return true after start_playback()")


func test_start_playback_with_empty_frames_does_nothing() -> void:
	replay.start_playback()
	assert_false(replay.is_replaying(),
		"start_playback() with no frames should not start playback")


func test_start_playback_resets_playback_frame() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	replay._playback_frame = 5
	replay.start_playback()
	assert_eq(replay._playback_frame, 0,
		"start_playback() should reset playback frame to 0")


func test_start_playback_resets_playback_time() -> void:
	replay._add_test_frame(1.0)
	replay._playback_time = 42.0
	replay.start_playback()
	assert_eq(replay._playback_time, 0.0,
		"start_playback() should reset playback time to 0.0")


func test_start_playback_resets_playback_speed() -> void:
	replay._add_test_frame(1.0)
	replay._playback_speed = 3.0
	replay.start_playback()
	assert_eq(replay._playback_speed, 1.0,
		"start_playback() should reset playback speed to 1.0")


func test_start_playback_sets_is_recording_false() -> void:
	replay._add_test_frame(1.0)
	replay._is_recording = true
	replay.start_playback()
	assert_false(replay.is_recording(),
		"start_playback() should set is_recording to false")


func test_start_playback_resets_playback_ending() -> void:
	replay._add_test_frame(1.0)
	replay._playback_ending = true
	replay._playback_end_timer = 0.3
	replay.start_playback()
	assert_false(replay._playback_ending,
		"start_playback() should reset playback_ending to false")
	assert_eq(replay._playback_end_timer, 0.0,
		"start_playback() should reset playback_end_timer to 0.0")


func test_start_playback_emits_replay_started_signal() -> void:
	replay._add_test_frame(1.0)
	var signal_emitted := false
	replay.replay_started.connect(func(): signal_emitted = true)
	replay.start_playback()
	assert_true(signal_emitted,
		"start_playback() should emit replay_started signal")


func test_stop_playback_sets_is_playing_back_false() -> void:
	replay._add_test_frame(1.0)
	replay.start_playback()
	assert_true(replay.is_replaying())
	replay.stop_playback()
	assert_false(replay.is_replaying(),
		"stop_playback() should set is_playing_back to false")


func test_stop_playback_emits_replay_ended_signal() -> void:
	replay._add_test_frame(1.0)
	replay.start_playback()
	var signal_emitted := false
	replay.replay_ended.connect(func(): signal_emitted = true)
	replay.stop_playback()
	assert_true(signal_emitted,
		"stop_playback() should emit replay_ended signal")


func test_stop_playback_resets_playback_ending() -> void:
	replay._add_test_frame(1.0)
	replay.start_playback()
	replay._playback_ending = true
	replay._playback_end_timer = 0.3
	replay.stop_playback()
	assert_false(replay._playback_ending,
		"stop_playback() should reset playback_ending to false")
	assert_eq(replay._playback_end_timer, 0.0,
		"stop_playback() should reset playback_end_timer to 0.0")


func test_stop_playback_when_not_playing_is_noop() -> void:
	var signal_emitted := false
	replay.replay_ended.connect(func(): signal_emitted = true)
	replay.stop_playback()
	assert_false(signal_emitted,
		"stop_playback() when not playing should not emit signal")


func test_stop_playback_works_during_playback_ending() -> void:
	replay._playback_ending = true
	replay._playback_end_timer = 0.3
	var signal_emitted := false
	replay.replay_ended.connect(func(): signal_emitted = true)
	replay.stop_playback()
	assert_true(signal_emitted,
		"stop_playback() should work when _playback_ending is true")
	assert_false(replay._playback_ending,
		"stop_playback() should clear _playback_ending")


# ============================================================================
# Playback Frame Update Tests
# ============================================================================


func test_playback_advances_time_by_delta_times_speed() -> void:
	replay._add_test_frame(0.5)
	replay._add_test_frame(1.0)
	replay._add_test_frame(5.0)
	replay.start_playback()
	replay.simulate_playback_frame_update(0.1)
	assert_almost_eq(replay._playback_time, 0.1, 0.001,
		"Playback time should advance by delta * speed (1.0)")


func test_playback_advances_time_at_double_speed() -> void:
	replay._add_test_frame(0.5)
	replay._add_test_frame(1.0)
	replay._add_test_frame(5.0)
	replay.start_playback()
	replay.set_playback_speed(2.0)
	replay.simulate_playback_frame_update(0.1)
	assert_almost_eq(replay._playback_time, 0.2, 0.001,
		"Playback time should advance by delta * 2.0 at double speed")


func test_playback_advances_frame_index() -> void:
	replay._add_test_frame(0.1)
	replay._add_test_frame(0.2)
	replay._add_test_frame(0.3)
	replay._add_test_frame(10.0)
	replay.start_playback()
	# Advance past first two frame times
	replay.simulate_playback_frame_update(0.25)
	assert_eq(replay._playback_frame, 1,
		"Playback frame should advance to frame before current time")


func test_playback_emits_progress_signal() -> void:
	replay._add_test_frame(0.5)
	replay._add_test_frame(5.0)
	replay.start_playback()
	var received_current := -1.0
	var received_total := -1.0
	replay.playback_progress.connect(func(current, total):
		received_current = current
		received_total = total
	)
	replay.simulate_playback_frame_update(0.1)
	assert_almost_eq(received_current, 0.1, 0.001,
		"Progress signal should report current playback time")
	assert_eq(received_total, 5.0,
		"Progress signal should report total replay duration")


func test_playback_ends_when_time_reaches_duration() -> void:
	replay._add_test_frame(0.5)
	replay._add_test_frame(1.0)
	replay.start_playback()
	# Advance past the full duration
	replay.simulate_playback_frame_update(1.5)
	assert_false(replay.is_replaying(),
		"Playback should end when time exceeds duration")
	assert_true(replay._playback_ending,
		"Playback ending should be scheduled")
	assert_almost_eq(replay._playback_end_timer, 0.5, 0.001,
		"Playback end timer should be 0.5 seconds")


func test_playback_time_clamped_at_duration_on_end() -> void:
	replay._add_test_frame(0.5)
	replay._add_test_frame(1.0)
	replay.start_playback()
	replay.simulate_playback_frame_update(2.0)
	assert_eq(replay._playback_time, 1.0,
		"Playback time should be clamped to replay duration when playback ends")


func test_playback_ending_timer_triggers_stop() -> void:
	replay._add_test_frame(0.5)
	replay._add_test_frame(1.0)
	replay.start_playback()
	# End playback
	replay.simulate_playback_frame_update(1.5)
	assert_true(replay._playback_ending)

	# Simulate physics ticks to drain the end timer
	var signal_emitted := false
	replay.replay_ended.connect(func(): signal_emitted = true)
	replay.simulate_physics_process(0.3)
	assert_true(replay._playback_ending,
		"Should still be in ending state after 0.3s (timer was 0.5)")
	replay.simulate_physics_process(0.3)
	assert_false(replay._playback_ending,
		"Playback ending should clear after timer expires")
	assert_true(signal_emitted,
		"replay_ended signal should be emitted after end timer expires")


func test_playback_update_with_empty_frames_stops() -> void:
	replay._is_playing_back = true
	var signal_emitted := false
	replay.replay_ended.connect(func(): signal_emitted = true)
	replay.simulate_playback_frame_update(0.016)
	assert_false(replay.is_replaying(),
		"Playback with empty frames should stop immediately")
	assert_true(signal_emitted,
		"Should emit replay_ended when stopping due to empty frames")


# ============================================================================
# seek_to() Tests
# ============================================================================


func test_seek_to_sets_playback_time() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	replay._add_test_frame(3.0)
	replay.seek_to(2.0)
	assert_eq(replay._playback_time, 2.0,
		"seek_to() should set _playback_time to the target time")


func test_seek_to_clamps_above_duration() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	replay.seek_to(10.0)
	assert_eq(replay._playback_time, 2.0,
		"seek_to() should clamp time to replay duration")


func test_seek_to_clamps_below_zero() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	replay.seek_to(-5.0)
	assert_eq(replay._playback_time, 0.0,
		"seek_to() should clamp negative time to 0.0")


func test_seek_to_finds_correct_frame() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	replay._add_test_frame(3.0)
	replay._add_test_frame(4.0)
	replay.seek_to(2.5)
	# Frame at index 2 has time 3.0 which is >= 2.5, so playback_frame = max(0, 2-1) = 1
	assert_eq(replay._playback_frame, 1,
		"seek_to() should find the frame at or before the target time")


func test_seek_to_beginning() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	replay._add_test_frame(3.0)
	replay.seek_to(0.0)
	assert_eq(replay._playback_time, 0.0,
		"seek_to(0.0) should set playback time to 0.0")
	# Frame at index 0 has time 1.0 which is >= 0.0, so playback_frame = max(0, 0-1) = 0
	assert_eq(replay._playback_frame, 0,
		"seek_to(0.0) should set playback frame to 0")


func test_seek_to_end() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	replay._add_test_frame(3.0)
	replay.seek_to(3.0)
	assert_eq(replay._playback_time, 3.0,
		"seek_to(duration) should set time to full duration")


func test_seek_to_exact_frame_time() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	replay._add_test_frame(3.0)
	replay.seek_to(2.0)
	# Frame at index 1 has time 2.0 which is >= 2.0, so playback_frame = max(0, 1-1) = 0
	assert_eq(replay._playback_frame, 0,
		"seek_to() at exact frame time should set frame to i-1")


func test_seek_to_empty_frames_is_noop() -> void:
	var initial_time := replay._playback_time
	var initial_frame := replay._playback_frame
	replay.seek_to(5.0)
	assert_eq(replay._playback_time, initial_time,
		"seek_to() with empty frames should not change playback time")
	assert_eq(replay._playback_frame, initial_frame,
		"seek_to() with empty frames should not change playback frame")


func test_seek_to_with_single_frame() -> void:
	replay._add_test_frame(2.0)
	replay.seek_to(1.0)
	assert_eq(replay._playback_time, 1.0,
		"seek_to() with single frame should clamp to duration")
	# Frame at index 0 has time 2.0 which is >= 1.0, so playback_frame = max(0, 0-1) = 0
	assert_eq(replay._playback_frame, 0,
		"seek_to() with single frame should set frame to 0")


# ============================================================================
# clear_replay() Tests
# ============================================================================


func test_clear_replay_empties_frames() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	assert_eq(replay._frames.size(), 2)
	replay.clear_replay()
	assert_eq(replay._frames.size(), 0,
		"clear_replay() should empty the frames array")


func test_clear_replay_resets_recording_time() -> void:
	replay._recording_time = 42.0
	replay.clear_replay()
	assert_eq(replay._recording_time, 0.0,
		"clear_replay() should reset recording time to 0.0")


func test_clear_replay_sets_is_recording_false() -> void:
	replay._is_recording = true
	replay.clear_replay()
	assert_false(replay.is_recording(),
		"clear_replay() should set is_recording to false")


func test_clear_replay_makes_has_replay_false() -> void:
	replay._add_test_frame(1.0)
	assert_true(replay.has_replay())
	replay.clear_replay()
	assert_false(replay.has_replay(),
		"has_replay() should return false after clear_replay()")


func test_clear_replay_makes_duration_zero() -> void:
	replay._add_test_frame(5.0)
	assert_eq(replay.get_replay_duration(), 5.0)
	replay.clear_replay()
	assert_eq(replay.get_replay_duration(), 0.0,
		"get_replay_duration() should return 0.0 after clear_replay()")


# ============================================================================
# State Transition Tests
# ============================================================================


func test_cannot_record_and_play_simultaneously() -> void:
	replay._add_test_frame(1.0)
	replay.start_playback()
	assert_true(replay.is_replaying())
	assert_false(replay.is_recording(),
		"Should not be recording during playback")

	replay.stop_playback()
	replay.start_recording()
	assert_true(replay.is_recording())
	assert_false(replay.is_replaying(),
		"Should not be playing back during recording")


func test_start_recording_during_playback_stops_playback() -> void:
	replay._add_test_frame(1.0)
	replay.start_playback()
	assert_true(replay.is_replaying())
	replay.start_recording()
	assert_false(replay.is_replaying(),
		"start_recording() should stop playback")
	assert_true(replay.is_recording(),
		"start_recording() should start recording")


func test_start_playback_during_recording_stops_recording() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.016)
	replay.simulate_record_frame(0.016)
	# Manually set frames so start_playback has data
	var had_frames := replay._frames.size() > 0
	replay.start_playback()
	if had_frames:
		assert_false(replay.is_recording(),
			"start_playback() should stop recording")
		assert_true(replay.is_replaying(),
			"start_playback() should start playback")


func test_full_record_then_playback_cycle() -> void:
	# Start recording
	replay.start_recording()
	assert_true(replay.is_recording())
	assert_false(replay.is_replaying())

	# Record some frames
	replay.simulate_record_frame(0.5)
	replay.simulate_record_frame(0.5)
	replay.simulate_record_frame(0.5)

	# Stop recording
	replay.stop_recording()
	assert_false(replay.is_recording())
	assert_false(replay.is_replaying())
	assert_true(replay.has_replay())
	assert_almost_eq(replay.get_replay_duration(), 1.5, 0.001)

	# Start playback
	replay.start_playback()
	assert_false(replay.is_recording())
	assert_true(replay.is_replaying())

	# Advance playback partially
	replay.simulate_playback_frame_update(0.5)
	assert_true(replay.is_replaying())
	assert_almost_eq(replay._playback_time, 0.5, 0.001)

	# Advance playback to completion
	replay.simulate_playback_frame_update(1.5)
	assert_false(replay.is_replaying())
	assert_true(replay._playback_ending)

	# Drain end timer
	replay.simulate_physics_process(0.5)
	assert_false(replay._playback_ending)


func test_multiple_record_playback_cycles() -> void:
	# First cycle
	replay.start_recording()
	replay.simulate_record_frame(0.5)
	replay.stop_recording()
	assert_eq(replay._frames.size(), 1)

	replay._add_test_frame(1.0)
	replay.start_playback()
	replay.stop_playback()

	# Second cycle - should reset cleanly
	replay.start_recording()
	assert_eq(replay._frames.size(), 0,
		"Second recording should start with clean frames")
	replay.simulate_record_frame(0.3)
	replay.simulate_record_frame(0.3)
	replay.stop_recording()
	assert_eq(replay._frames.size(), 2,
		"Second recording should have its own frames")


# ============================================================================
# Physics Process Simulation Tests
# ============================================================================


func test_physics_process_records_when_recording() -> void:
	replay.start_recording()
	replay.simulate_physics_process(0.016)
	assert_eq(replay._frames.size(), 1,
		"Physics process should record a frame when recording")


func test_physics_process_updates_playback_when_playing() -> void:
	replay._add_test_frame(0.5)
	replay._add_test_frame(5.0)
	replay.start_playback()
	replay.simulate_physics_process(0.1)
	assert_almost_eq(replay._playback_time, 0.1, 0.001,
		"Physics process should advance playback time when playing")


func test_physics_process_handles_ending_state() -> void:
	replay._playback_ending = true
	replay._playback_end_timer = 0.2
	replay.simulate_physics_process(0.1)
	assert_true(replay._playback_ending,
		"Should still be ending after partial timer drain")
	assert_almost_eq(replay._playback_end_timer, 0.1, 0.001,
		"End timer should decrease by delta")


func test_physics_process_resolves_ending_state() -> void:
	replay._playback_ending = true
	replay._playback_end_timer = 0.1
	var signal_emitted := false
	replay.replay_ended.connect(func(): signal_emitted = true)
	replay.simulate_physics_process(0.2)
	assert_false(replay._playback_ending,
		"Ending state should resolve when timer expires")
	assert_true(signal_emitted,
		"replay_ended should be emitted when ending state resolves")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_playback_speed_persists_across_updates() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(10.0)
	replay.start_playback()
	replay.set_playback_speed(3.0)
	replay.simulate_playback_frame_update(0.1)
	assert_almost_eq(replay._playback_time, 0.3, 0.001,
		"Speed 3.0 should persist and affect subsequent updates")
	replay.simulate_playback_frame_update(0.1)
	assert_almost_eq(replay._playback_time, 0.6, 0.001,
		"Speed should still be applied on second update")


func test_seek_then_playback_continues_from_seek_point() -> void:
	replay._add_test_frame(1.0)
	replay._add_test_frame(2.0)
	replay._add_test_frame(3.0)
	replay._add_test_frame(10.0)
	replay.start_playback()
	replay.seek_to(2.5)
	assert_almost_eq(replay._playback_time, 2.5, 0.001)
	replay.simulate_playback_frame_update(0.1)
	assert_almost_eq(replay._playback_time, 2.6, 0.001,
		"Playback should continue from the seek point")


func test_very_small_delta() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.0001)
	assert_eq(replay._frames.size(), 1)
	assert_almost_eq(replay._frames[0].time, 0.0001, 0.00001,
		"Very small delta should still be recorded accurately")


func test_very_large_single_delta() -> void:
	replay.start_recording()
	replay.simulate_record_frame(250.0)
	assert_eq(replay._frames.size(), 1,
		"Large delta within max duration should create a frame")
	assert_true(replay.is_recording(),
		"Should still be recording at 250s")
	replay.simulate_record_frame(51.0)
	assert_false(replay.is_recording(),
		"Should stop recording after exceeding max duration")


func test_clear_during_recording() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.5)
	replay.simulate_record_frame(0.5)
	replay.clear_replay()
	assert_false(replay.is_recording(),
		"clear_replay() should stop recording")
	assert_eq(replay._frames.size(), 0,
		"clear_replay() should remove all frames")
	assert_eq(replay._recording_time, 0.0,
		"clear_replay() should reset recording time")


func test_double_start_recording_resets_cleanly() -> void:
	replay.start_recording()
	replay.simulate_record_frame(0.5)
	replay.simulate_record_frame(0.5)
	assert_eq(replay._frames.size(), 2)
	# Start recording again without stopping
	replay.start_recording()
	assert_eq(replay._frames.size(), 0,
		"Double start_recording() should clear frames")
	assert_eq(replay._recording_time, 0.0,
		"Double start_recording() should reset recording time")
	assert_true(replay.is_recording(),
		"Should still be recording after double start")
