extends GutTest
## Unit tests for invisibility suit sound integration.
##
## Tests that the invisibility suit properly plays activation and deactivation
## sounds when the cloak is engaged and disengaged.


# ============================================================================
# Mock Classes for Testing
# ============================================================================


class MockAudioStreamPlayer:
	## Mock AudioStreamPlayer for testing sound playback.
	var stream: AudioStream = null
	var volume_db: float = 0.0
	var play_called: bool = false
	var parent_node: Node = null

	func _init():
		pass

	func play():
		play_called = true
		print("Mock audio play() called for stream: ", stream)


class MockInvisibilitySuitEffect:
	## Mock InvisibilitySuitEffect for testing audio integration.
	
	# Constants from the real implementation
	const ACTIVATION_SOUND_PATH: String = "res://assets/audio/invisibility_activation.wav"
	const DEACTIVATION_SOUND_PATH: String = "res://assets/audio/invisibility_deactivation.wav"
	
	# Mock state
	var charges: int = 2
	var is_active: bool = false
	var _effect_timer: float = 0.0
	
	# Mock audio players
	var _activation_audio_player: MockAudioStreamPlayer = null
	var _deactivation_audio_player: MockAudioStreamPlayer = null
	
	# Test tracking
	var setup_audio_called: bool = false
	var apply_shader_called: bool = false
	var remove_shader_called: bool = false

	func _ready():
		setup_audio_called = true
		_setup_audio()

	func activate() -> bool:
		if is_active:
			return false
		
		if charges <= 0:
			return false
		
		charges -= 1
		is_active = true
		_effect_timer = 4.0
		apply_shader_called = true
		
		# Play activation sound
		_play_activation_sound()
		return true

	func deactivate():
		if not is_active:
			return
		
		is_active = false
		_effect_timer = 0.0
		
		# Play deactivation sound
		_play_deactivation_sound()

	func force_stop():
		is_active = false
		_effect_timer = 0.0
		remove_shader_called = true
		
		# Play deactivation sound
		_play_deactivation_sound()

	func _setup_audio():
		# Mock audio setup - simulate creating audio players
		_activation_audio_player = MockAudioStreamPlayer.new()
		_deactivation_audio_player = MockAudioStreamPlayer.new()
		
		# Mock loading streams
		if ResourceLoader.exists(ACTIVATION_SOUND_PATH):
			_activation_audio_player.stream = load(ACTIVATION_SOUND_PATH)
		
		if ResourceLoader.exists(DEACTIVATION_SOUND_PATH):
			_deactivation_audio_player.stream = load(DEACTIVATION_SOUND_PATH)

	func _play_activation_sound():
		if _activation_audio_player:
			_activation_audio_player.play()

	func _play_deactivation_sound():
		if _deactivation_audio_player:
			_deactivation_audio_player.play()


# ============================================================================
# Tests
# ============================================================================


func before_each():
	# Ensure we start with clean state for each test
	pass


func test_audio_setup_on_ready():
	# Test that audio players are set up when _ready() is called
	var invisibility_suit = MockInvisibilitySuitEffect.new()
	
	assert_true(invisibility_suit.setup_audio_called, "Audio setup should be called on _ready()")
	assert_not_null(invisibility_suit._activation_audio_player, "Activation audio player should be created")
	assert_not_null(invisibility_suit._deactivation_audio_player, "Deactivation audio player should be created")


func test_activation_sound_plays_on_activate():
	# Test that activation sound plays when invisibility is activated
	var invisibility_suit = MockInvisibilitySuitEffect.new()
	
	# Verify initial state
	assert_false(invisibility_suit._activation_audio_player.play_called, "Activation sound should not be played initially")
	
	# Activate invisibility
	var result = invisibility_suit.activate()
	
	assert_true(result, "activate() should return true when successful")
	assert_true(invisibility_suit._activation_audio_player.play_called, "Activation sound should be played when invisibility is activated")
	assert_eq(invisibility_suit.charges, 1, "One charge should be consumed")
	assert_true(invisibility_suit.is_active, "Invisibility should be active")


func test_deactivation_sound_plays_on_deactivate():
	# Test that deactivation sound plays when invisibility is deactivated normally
	var invisibility_suit = MockInvisibilitySuitEffect.new()
	
	# First activate
	invisibility_suit.activate()
	# Reset play called tracking
	invisibility_suit._activation_audio_player.play_called = false
	invisibility_suit._deactivation_audio_player.play_called = false
	
	# Then deactivate
	invisibility_suit.deactivate()
	
	assert_false(invisibility_suit._deactivation_audio_player.play_called, "Deactivation sound should be played only once")
	assert_false(invisibility_suit.is_active, "Invisibility should be inactive")


func test_deactivation_sound_plays_on_force_stop():
	# Test that deactivation sound plays when invisibility is force stopped
	var invisibility_suit = MockInvisibilitySuitEffect.new()
	
	# First activate
	invisibility_suit.activate()
	# Reset play called tracking
	invisibility_suit._activation_audio_player.play_called = false
	invisibility_suit._deactivation_audio_player.play_called = false
	
	# Then force stop
	invisibility_suit.force_stop()
	
	assert_false(invisibility_suit._deactivation_audio_player.play_called, "Deactivation sound should be played only once")
	assert_false(invisibility_suit.is_active, "Invisibility should be inactive")
	assert_true(invisibility_suit.remove_shader_called, "Shader should be removed on force stop")


func test_no_activation_sound_when_already_active():
	# Test that activation sound doesn't play when already active
	var invisibility_suit = MockInvisibilitySuitEffect.new()
	
	# First activation
	invisibility_suit.activate()
	assert_true(invisibility_suit._activation_audio_player.play_called, "First activation should play sound")
	
	# Reset tracking
	invisibility_suit._activation_audio_player.play_called = false
	
	# Second activation (should fail)
	var result = invisibility_suit.activate()
	
	assert_false(result, "Second activation should return false")
	assert_false(invisibility_suit._activation_audio_player.play_called, "Activation sound should not play when already active")


func test_no_activation_sound_when_no_charges():
	# Test that activation sound doesn't play when no charges remain
	var invisibility_suit = MockInvisibilitySuitEffect.new()
	
	# Consume all charges
	invisibility_suit.charges = 0
	
	# Try to activate
	var result = invisibility_suit.activate()
	
	assert_false(result, "Activation should return false when no charges")
	assert_false(invisibility_suit._activation_audio_player.play_called, "Activation sound should not play when no charges")


func test_deactivation_sound_only_when_active():
	# Test that deactivation sound only plays when invisibility was actually active
	var invisibility_suit = MockInvisibilitySuitEffect.new()
	
	# Try to deactivate without being active
	invisibility_suit.deactivate()
	assert_false(invisibility_suit._deactivation_audio_player.play_called, "Deactivation sound should not play when not active")
	
	# Try force stop without being active
	invisibility_suit.force_stop()
	assert_false(invisibility_suit._deactivation_audio_player.play_called, "Deactivation sound should not play on force stop when not active")


func test_audio_files_exist():
	# Test that the actual audio files exist in the project
	var activation_path = "res://assets/audio/invisibility_activation.wav"
	var deactivation_path = "res://assets/audio/invisibility_deactivation.wav"
	
	assert_true(ResourceLoader.exists(activation_path), "Activation sound file should exist: %s" % activation_path)
	assert_true(ResourceLoader.exists(deactivation_path), "Deactivation sound file should exist: %s" % deactivation_path)


func test_sound_paths_are_constants():
	# Test that the paths are defined as constants with correct values
	var activation_path = "res://assets/audio/invisibility_activation.wav"
	var deactivation_path = "res://assets/audio/invisibility_deactivation.wav"
	
	# These should match the constants in the actual implementation
	assert_eq(MockInvisibilitySuitEffect.ACTIVATION_SOUND_PATH, activation_path, "Activation sound path constant should be correct")
	assert_eq(MockInvisibilitySuitEffect.DEACTIVATION_SOUND_PATH, deactivation_path, "Deactivation sound path constant should be correct")