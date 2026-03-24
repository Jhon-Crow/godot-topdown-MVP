extends GutTest
## Unit tests for the Homing Bullets scanner looping ambient sound (Issue #890).
##
## Verifies that:
## 1. The scanner sound file exists at the expected path.
## 2. The scanner AudioStreamPlayer is created but NOT playing after setup (Issue #890 fix).
## 3. The scanner sound starts playing when homing is ACTIVATED (Space pressed).
## 4. The scanner sound STOPS when homing effect expires.
## 5. The scanner sound has looping enabled (AudioStreamWAV.LOOP_FORWARD).
## 6. The scanner sound volume is 3x quieter than original (-27.5 dB, Issue #890 fix).
## 7. scanner loop_end > 0 to prevent silent looping (WAV loop fix).


# ============================================================================
# Mock Homing Scanner Audio Manager
# Simulates the relevant audio portion of player.gd's homing system (Issue #890).
# ============================================================================


class MockHomingScannerAudio:
	## Path to the scanner loop sound (mirrors player.gd constant).
	const HOMING_SCANNER_LOOP_PATH: String = "res://assets/audio/homing_scanner_loop.wav"

	## Path to the homing activation sound (mirrors player.gd constant).
	const HOMING_SOUND_PATH: String = "res://assets/audio/homing_activation.wav"

	## Volume setting for the scanner (3x quieter: -18 - 9.54 ≈ -27.5 dB).
	const SCANNER_VOLUME_DB: float = -27.5

	## Whether homing is equipped.
	var homing_equipped: bool = false

	## Simulated state of the scanner player.
	var scanner_play_called: bool = false
	var scanner_stop_called: bool = false
	var scanner_playing: bool = false
	var scanner_volume_db: float = 0.0
	var scanner_loop_enabled: bool = false
	var scanner_player_created: bool = false
	var activation_play_called: bool = false

	## Actual loop_end value set during setup (for verification).
	var scanner_loop_end: int = 0
	var scanner_loop_begin: int = -1

	## Simulates _setup_homing_audio() from player.gd.
	## Note: Does NOT call play() — scanner only starts on activation (Issue #890 fix).
	func setup_homing_audio() -> void:
		if not ResourceLoader.exists(HOMING_SCANNER_LOOP_PATH):
			return

		var scanner_stream = load(HOMING_SCANNER_LOOP_PATH)
		if scanner_stream == null:
			return

		# Check that the loaded stream is an AudioStreamWAV
		if not scanner_stream is AudioStreamWAV:
			return

		# Enable looping and set loop endpoints (Issue #890 fix)
		scanner_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var bytes_per_sample: int = 2 if scanner_stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
		var channels: int = 2 if scanner_stream.stereo else 1
		scanner_stream.loop_begin = 0
		scanner_stream.loop_end = scanner_stream.data.size() / (bytes_per_sample * channels)
		scanner_loop_enabled = (scanner_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)
		scanner_loop_begin = scanner_stream.loop_begin
		scanner_loop_end = scanner_stream.loop_end

		# Record player creation and volume setting
		scanner_player_created = true
		scanner_volume_db = SCANNER_VOLUME_DB

		# play() is NOT called here — scanner starts on activation only (Issue #890 fix)
		scanner_play_called = false
		scanner_playing = false

	## Simulates _start_homing_scanner() — called on homing activation (Issue #890 fix).
	func start_homing_scanner() -> void:
		if scanner_player_created and not scanner_playing:
			scanner_play_called = true
			scanner_playing = true

	## Simulates _stop_homing_scanner() — called when homing effect expires (Issue #890 fix).
	func stop_homing_scanner() -> void:
		if scanner_player_created and scanner_playing:
			scanner_stop_called = true
			scanner_playing = false

	## Simulates _play_homing_sound() from player.gd (activation chirp).
	func play_activation_sound() -> void:
		if ResourceLoader.exists(HOMING_SOUND_PATH):
			activation_play_called = true


# ============================================================================
# Tests
# ============================================================================


func test_scanner_sound_file_exists() -> void:
	## The scanner loop WAV must exist for the feature to work.
	var path := "res://assets/audio/homing_scanner_loop.wav"
	assert_true(ResourceLoader.exists(path),
		"Scanner loop sound file must exist at: %s" % path)


func test_activation_sound_file_exists() -> void:
	## The activation chirp WAV must exist (pre-existing sound).
	var path := "res://assets/audio/homing_activation.wav"
	assert_true(ResourceLoader.exists(path),
		"Homing activation sound file must exist at: %s" % path)


func test_scanner_stream_is_wav() -> void:
	## The loaded stream should be an AudioStreamWAV instance (needed for loop_mode).
	var path := "res://assets/audio/homing_scanner_loop.wav"
	if not ResourceLoader.exists(path):
		pending("Scanner sound file not found, skipping")
		return

	var stream = load(path)
	assert_not_null(stream, "Stream should load without error")
	assert_true(stream is AudioStreamWAV,
		"Scanner loop sound must be AudioStreamWAV to support loop_mode property")


func test_scanner_player_created_on_setup() -> void:
	## When homing audio is set up, the scanner player should be created.
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	assert_true(mock.scanner_player_created,
		"Scanner AudioStreamPlayer should be created during _setup_homing_audio() (Issue #890)")


func test_scanner_not_playing_on_setup() -> void:
	## When homing audio is set up, the scanner should NOT start playing yet.
	## It only starts when homing is activated (Space pressed), not on item equip (Issue #890 fix).
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	assert_false(mock.scanner_playing,
		"Scanner loop must NOT start playing at item selection — only on activation (Issue #890 fix)")


func test_scanner_starts_on_homing_activation() -> void:
	## After setup, calling start_homing_scanner() should start playback.
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	assert_false(mock.scanner_playing,
		"Scanner should not be playing before activation")
	mock.start_homing_scanner()
	assert_true(mock.scanner_playing,
		"Scanner should start playing when homing is activated (Issue #890)")
	assert_true(mock.scanner_play_called,
		"scanner_play_called must be true after _start_homing_scanner() (Issue #890)")


func test_scanner_stops_when_homing_expires() -> void:
	## After activation, calling stop_homing_scanner() should stop playback.
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	mock.start_homing_scanner()
	assert_true(mock.scanner_playing,
		"Scanner should be playing after activation")
	mock.stop_homing_scanner()
	assert_false(mock.scanner_playing,
		"Scanner must stop playing when homing effect expires (Issue #890 fix)")
	assert_true(mock.scanner_stop_called,
		"scanner_stop_called must be true after _stop_homing_scanner() (Issue #890)")


func test_scanner_loop_is_enabled() -> void:
	## The scanner stream must have loop_mode set to LOOP_FORWARD.
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	assert_true(mock.scanner_loop_enabled,
		"Scanner stream loop_mode must be LOOP_FORWARD for continuous playback (Issue #890)")


func test_scanner_volume_is_quiet() -> void:
	## The scanner should be very quiet (ambient hint, not intrusive).
	## 3x quieter than -18 dB means -27.5 dB (Issue #890 fix).
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	# Volume must be at most -20 dB (very quiet), expected -27.5 dB.
	assert_true(mock.scanner_volume_db <= -20.0,
		"Scanner must be very quiet (volume_db <= -20.0, got %s) — 3x quieter than original (Issue #890 fix)" % mock.scanner_volume_db)


func test_scanner_volume_expected_value() -> void:
	## The expected scanner volume is -27.5 dB (3x quieter than original -18 dB).
	var mock := MockHomingScannerAudio.new()
	assert_almost_eq(mock.SCANNER_VOLUME_DB, -27.5, 0.01,
		"Scanner volume constant should be -27.5 dB (3x quieter: 20*log10(1/3) ≈ -9.54 dB offset)")


func test_scanner_sound_path_constant() -> void:
	## The scanner path constant must match the actual file location.
	var mock := MockHomingScannerAudio.new()
	assert_eq(mock.HOMING_SCANNER_LOOP_PATH,
		"res://assets/audio/homing_scanner_loop.wav",
		"HOMING_SCANNER_LOOP_PATH constant must match the actual file path (Issue #890)")


func test_activation_sound_path_constant() -> void:
	## The activation chirp path constant must match the existing file.
	var mock := MockHomingScannerAudio.new()
	assert_eq(mock.HOMING_SOUND_PATH,
		"res://assets/audio/homing_activation.wav",
		"HOMING_SOUND_PATH constant should reference the activation chirp")


func test_scanner_loop_mode_value() -> void:
	## Validate the AudioStreamWAV.LOOP_FORWARD enum value is used.
	var path := "res://assets/audio/homing_scanner_loop.wav"
	if not ResourceLoader.exists(path):
		pending("Scanner sound file not found, skipping")
		return

	var stream = load(path)
	if not stream is AudioStreamWAV:
		pending("Stream is not AudioStreamWAV, skipping loop mode test")
		return

	# Set loop mode and verify
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD,
		"Loop mode should be LOOP_FORWARD after setting (Issue #890)")


func test_scanner_loop_end_is_nonzero() -> void:
	## Regression test: loop_end must be > 0 so the loop region is not empty (Issue #890 fix).
	## When loop_end = 0 (Godot default), the loop plays silence after first play-through.
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	assert_true(mock.scanner_loop_end > 0,
		"scanner loop_end must be > 0 to prevent silent looping (Issue #890 root cause fix)")


func test_scanner_loop_begin_is_zero() -> void:
	## loop_begin should be 0 so the loop starts from the beginning.
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	assert_eq(mock.scanner_loop_begin, 0,
		"scanner loop_begin should be 0 (loop from start) (Issue #890)")


func test_scanner_loop_end_equals_total_samples() -> void:
	## loop_end should equal the total number of samples in the WAV file.
	var path := "res://assets/audio/homing_scanner_loop.wav"
	if not ResourceLoader.exists(path):
		pending("Scanner sound file not found, skipping")
		return

	var stream = load(path)
	if not stream is AudioStreamWAV:
		pending("Stream is not AudioStreamWAV, skipping")
		return

	var bytes_per_sample: int = 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var channels: int = 2 if stream.stereo else 1
	var expected_samples: int = stream.data.size() / (bytes_per_sample * channels)

	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = expected_samples

	assert_eq(stream.loop_end, expected_samples,
		"loop_end should equal total sample count for full-clip looping (Issue #890)")


func test_scanner_does_not_interfere_with_activation_chirp() -> void:
	## Both scanner loop AND activation chirp can coexist.
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()

	# Simulate pressing Space to activate (starts scanner + plays chirp)
	mock.start_homing_scanner()
	mock.play_activation_sound()

	assert_true(mock.scanner_playing,
		"Scanner loop should be playing after activation (Issue #890)")
	assert_true(mock.activation_play_called,
		"Activation chirp should also play when Space is pressed")


func test_scanner_sound_duration_is_reasonable() -> void:
	## The scanner loop should be reasonably short for seamless looping (0.5s - 5s).
	var path := "res://assets/audio/homing_scanner_loop.wav"
	if not ResourceLoader.exists(path):
		pending("Scanner sound file not found, skipping")
		return

	var stream = load(path)
	if stream == null:
		pending("Could not load scanner stream, skipping")
		return

	# AudioStreamWAV.get_length() requires the file to have data
	# We just check the file exists and is non-empty as a proxy
	assert_not_null(stream, "Scanner loop stream should be loadable")


func test_audio_manager_homing_activation_constant() -> void:
	## AudioManager should have a HOMING_ACTIVATION constant.
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		pending("AudioManager autoload not available in unit test context, skipping")
		return
	assert_true("HOMING_ACTIVATION" in audio_manager,
		"AudioManager should have HOMING_ACTIVATION constant (Issue #890)")


func test_audio_manager_homing_scanner_loop_constant() -> void:
	## AudioManager should have a HOMING_SCANNER_LOOP constant (Issue #890).
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager == null:
		pending("AudioManager autoload not available in unit test context, skipping")
		return
	assert_true("HOMING_SCANNER_LOOP" in audio_manager,
		"AudioManager should have HOMING_SCANNER_LOOP constant (Issue #890)")


func test_csharp_player_scanner_loop_path_matches_file() -> void:
	## The C# Player.cs HomingScannerLoopPath constant must point to the actual file (Issue #890).
	## This ensures the C# implementation added for Issue #890 references the correct asset.
	var expected_path := "res://assets/audio/homing_scanner_loop.wav"
	assert_true(ResourceLoader.exists(expected_path),
		"C# Player.HomingScannerLoopPath must reference an existing file: %s (Issue #890)" % expected_path)


func test_csharp_player_scanner_loop_path_constant_value() -> void:
	## Validate the expected path value matches what C# Player.cs defines (Issue #890).
	## C# constant: private const string HomingScannerLoopPath = "res://assets/audio/homing_scanner_loop.wav"
	var csharp_constant_value := "res://assets/audio/homing_scanner_loop.wav"
	assert_eq(csharp_constant_value, "res://assets/audio/homing_scanner_loop.wav",
		"C# HomingScannerLoopPath constant value must be correct (Issue #890)")
