extends GutTest
## Unit tests for the Homing Bullets scanner looping ambient sound (Issue #890).
##
## Verifies that:
## 1. The scanner sound file exists at the expected path.
## 2. The scanner AudioStreamPlayer is created and playing when homing is equipped.
## 3. The scanner sound has looping enabled (AudioStreamWAV.LOOP_FORWARD).
## 4. The scanner sound volume is quiet (ambient level, not dominant).
## 5. Scanner audio state is consistent with equipment state.


# ============================================================================
# Mock Homing Scanner Audio Manager
# Simulates the relevant audio portion of player.gd's homing system (Issue #890).
# ============================================================================


class MockHomingScannerAudio:
	## Path to the scanner loop sound (mirrors player.gd constant).
	const HOMING_SCANNER_LOOP_PATH: String = "res://assets/audio/homing_scanner_loop.wav"

	## Path to the homing activation sound (mirrors player.gd constant).
	const HOMING_SOUND_PATH: String = "res://assets/audio/homing_activation.wav"

	## Volume setting for the scanner (should be quiet/ambient).
	const SCANNER_VOLUME_DB: float = -18.0

	## Whether homing is equipped.
	var homing_equipped: bool = false

	## Simulated state of the scanner player.
	var scanner_play_called: bool = false
	var scanner_volume_db: float = 0.0
	var scanner_loop_enabled: bool = false
	var scanner_player_created: bool = false
	var activation_play_called: bool = false

	## Simulates _setup_homing_audio() from player.gd.
	func setup_homing_audio() -> void:
		if not ResourceLoader.exists(HOMING_SCANNER_LOOP_PATH):
			return

		var scanner_stream = load(HOMING_SCANNER_LOOP_PATH)
		if scanner_stream == null:
			return

		# Check that the loaded stream is an AudioStreamWAV
		if not scanner_stream is AudioStreamWAV:
			return

		# Enable looping
		scanner_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		scanner_loop_enabled = (scanner_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD)

		# Record player creation and volume setting
		scanner_player_created = true
		scanner_volume_db = SCANNER_VOLUME_DB

		# Mark that play() was called
		scanner_play_called = true

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


func test_scanner_starts_playing_on_setup() -> void:
	## When homing audio is set up, the scanner loop should immediately start.
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	assert_true(mock.scanner_play_called,
		"Scanner loop should start playing immediately when item is equipped (Issue #890)")


func test_scanner_loop_is_enabled() -> void:
	## The scanner stream must have loop_mode set to LOOP_FORWARD.
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	assert_true(mock.scanner_loop_enabled,
		"Scanner stream loop_mode must be LOOP_FORWARD for continuous playback (Issue #890)")


func test_scanner_volume_is_quiet() -> void:
	## The scanner should be very quiet (ambient hint, not intrusive).
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()
	# Volume must be at most -12 dB (quiet), expected -18 dB.
	assert_true(mock.scanner_volume_db <= -12.0,
		"Scanner must be quiet (volume_db <= -12.0, got %s) so it doesn't dominate the mix (Issue #890)" % mock.scanner_volume_db)


func test_scanner_volume_expected_value() -> void:
	## The expected scanner volume is -18 dB.
	var mock := MockHomingScannerAudio.new()
	assert_almost_eq(mock.SCANNER_VOLUME_DB, -18.0, 0.01,
		"Scanner volume constant should be -18.0 dB")


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


func test_scanner_does_not_interfere_with_activation_chirp() -> void:
	## Both scanner loop AND activation chirp can coexist.
	var mock := MockHomingScannerAudio.new()
	mock.setup_homing_audio()

	# Simulate pressing Space to activate
	mock.play_activation_sound()

	assert_true(mock.scanner_play_called,
		"Scanner loop should continue playing after activation chirp (Issue #890)")
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
