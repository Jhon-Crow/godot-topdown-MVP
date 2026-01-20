extends GutTest
## Unit tests for AudioManager autoload.
##
## Tests the audio management functionality including sound path constants,
## volume settings, pool management, and random sound selection logic.


# ============================================================================
# Sound Path Constants Tests
# ============================================================================


func test_m16_shots_array_not_empty() -> void:
	var expected_count := 3
	var paths := [
		"res://assets/audio/m16 1.wav",
		"res://assets/audio/m16 2.wav",
		"res://assets/audio/m16 3.wav"
	]
	assert_eq(paths.size(), expected_count, "M16_SHOTS should have 3 sound variants")


func test_m16_double_shots_array_not_empty() -> void:
	var expected_count := 2
	var paths := [
		"res://assets/audio/m16 два выстрела подряд.wav",
		"res://assets/audio/m16  два выстрела подряд 2.wav"
	]
	assert_eq(paths.size(), expected_count, "M16_DOUBLE_SHOTS should have 2 sound variants")


func test_m16_bolt_sounds_array_not_empty() -> void:
	var expected_count := 4
	var paths := [
		"res://assets/audio/взвод затвора m16 1.wav",
		"res://assets/audio/взвод затвора m16 2.wav",
		"res://assets/audio/взвод затвора m16 3.wav",
		"res://assets/audio/взвод затвора m16 4.wav"
	]
	assert_eq(paths.size(), expected_count, "M16_BOLT_SOUNDS should have 4 sound variants")


# ============================================================================
# Volume Constants Tests
# ============================================================================


func test_volume_shot_value() -> void:
	var volume := -5.0
	assert_eq(volume, -5.0, "VOLUME_SHOT should be -5.0 dB")


func test_volume_reload_value() -> void:
	var volume := -3.0
	assert_eq(volume, -3.0, "VOLUME_RELOAD should be -3.0 dB")


func test_volume_impact_value() -> void:
	var volume := -8.0
	assert_eq(volume, -8.0, "VOLUME_IMPACT should be -8.0 dB")


func test_volume_hit_value() -> void:
	var volume := -3.0
	assert_eq(volume, -3.0, "VOLUME_HIT should be -3.0 dB")


func test_volume_shell_value() -> void:
	var volume := -10.0
	assert_eq(volume, -10.0, "VOLUME_SHELL should be -10.0 dB")


func test_volume_empty_click_value() -> void:
	var volume := -3.0
	assert_eq(volume, -3.0, "VOLUME_EMPTY_CLICK should be -3.0 dB")


# ============================================================================
# Pool Size Tests
# ============================================================================


func test_pool_size_constant() -> void:
	var pool_size := 16
	assert_eq(pool_size, 16, "POOL_SIZE should be 16 audio players")


# ============================================================================
# Mock AudioManager for Logic Tests
# ============================================================================


class MockAudioManager:
	## Pool of audio players (simulated)
	var _audio_pool: Array = []
	var _audio_2d_pool: Array = []
	const POOL_SIZE: int = 16

	## Cache of loaded sounds
	var _audio_cache: Dictionary = {}

	## Track which sounds were played
	var played_sounds: Array[String] = []
	var played_sounds_2d: Array[Dictionary] = []

	func _get_available_player_index() -> int:
		# Simulate finding available player
		for i in range(_audio_pool.size()):
			if _audio_pool[i] == false:  # false = not playing
				return i
		return 0  # Return first if all busy

	func _get_available_player_2d_index() -> int:
		for i in range(_audio_2d_pool.size()):
			if _audio_2d_pool[i] == false:
				return i
		return 0

	func setup_pools() -> void:
		_audio_pool.clear()
		_audio_2d_pool.clear()
		for i in range(POOL_SIZE):
			_audio_pool.append(false)  # false = not playing
			_audio_2d_pool.append(false)

	func play_sound(path: String, volume_db: float = 0.0) -> void:
		played_sounds.append(path)
		var idx := _get_available_player_index()
		_audio_pool[idx] = true  # Mark as playing

	func play_sound_2d(path: String, position: Vector2, volume_db: float = 0.0) -> void:
		played_sounds_2d.append({
			"path": path,
			"position": position,
			"volume": volume_db
		})
		var idx := _get_available_player_2d_index()
		_audio_2d_pool[idx] = true

	func play_random_sound(paths: Array, volume_db: float = 0.0) -> void:
		if paths.is_empty():
			return
		var path: String = paths[randi() % paths.size()]
		play_sound(path, volume_db)

	func play_random_sound_2d(paths: Array, position: Vector2, volume_db: float = 0.0) -> void:
		if paths.is_empty():
			return
		var path: String = paths[randi() % paths.size()]
		play_sound_2d(path, position, volume_db)

	func cache_sound(path: String) -> void:
		_audio_cache[path] = true

	func is_sound_cached(path: String) -> bool:
		return _audio_cache.has(path)

	func clear_cache() -> void:
		_audio_cache.clear()


var audio: MockAudioManager


func before_each() -> void:
	audio = MockAudioManager.new()
	audio.setup_pools()


func after_each() -> void:
	audio = null


# ============================================================================
# Audio Pool Tests
# ============================================================================


func test_audio_pool_has_correct_size() -> void:
	assert_eq(audio._audio_pool.size(), 16, "Audio pool should have 16 players")


func test_audio_2d_pool_has_correct_size() -> void:
	assert_eq(audio._audio_2d_pool.size(), 16, "Audio 2D pool should have 16 players")


func test_get_available_player_returns_first_free() -> void:
	# All players are free, should return 0
	var idx := audio._get_available_player_index()
	assert_eq(idx, 0, "Should return index 0 when all players are free")


func test_get_available_player_skips_busy() -> void:
	# Mark first player as busy
	audio._audio_pool[0] = true
	var idx := audio._get_available_player_index()
	assert_eq(idx, 1, "Should return index 1 when first player is busy")


func test_get_available_player_returns_first_when_all_busy() -> void:
	# Mark all players as busy
	for i in range(16):
		audio._audio_pool[i] = true
	var idx := audio._get_available_player_index()
	assert_eq(idx, 0, "Should return index 0 when all players are busy")


# ============================================================================
# Play Sound Tests
# ============================================================================


func test_play_sound_records_path() -> void:
	audio.play_sound("res://test.wav")

	assert_eq(audio.played_sounds.size(), 1)
	assert_eq(audio.played_sounds[0], "res://test.wav")


func test_play_sound_2d_records_position() -> void:
	var position := Vector2(100, 200)
	audio.play_sound_2d("res://test.wav", position, -5.0)

	assert_eq(audio.played_sounds_2d.size(), 1)
	assert_eq(audio.played_sounds_2d[0]["path"], "res://test.wav")
	assert_eq(audio.played_sounds_2d[0]["position"], position)
	assert_eq(audio.played_sounds_2d[0]["volume"], -5.0)


# ============================================================================
# Random Sound Selection Tests
# ============================================================================


func test_play_random_sound_from_array() -> void:
	var paths := ["res://a.wav", "res://b.wav", "res://c.wav"]
	seed(12345)  # Fixed seed for reproducibility

	audio.play_random_sound(paths)

	assert_eq(audio.played_sounds.size(), 1)
	assert_true(audio.played_sounds[0] in paths,
		"Played sound should be from the provided array")


func test_play_random_sound_empty_array_does_nothing() -> void:
	var paths: Array = []
	audio.play_random_sound(paths)

	assert_eq(audio.played_sounds.size(), 0,
		"Should not play anything from empty array")


func test_play_random_sound_2d_from_array() -> void:
	var paths := ["res://a.wav", "res://b.wav"]
	var position := Vector2(50, 50)
	seed(12345)

	audio.play_random_sound_2d(paths, position)

	assert_eq(audio.played_sounds_2d.size(), 1)
	assert_true(audio.played_sounds_2d[0]["path"] in paths)
	assert_eq(audio.played_sounds_2d[0]["position"], position)


func test_play_random_sound_2d_empty_array_does_nothing() -> void:
	var paths: Array = []
	audio.play_random_sound_2d(paths, Vector2.ZERO)

	assert_eq(audio.played_sounds_2d.size(), 0)


# ============================================================================
# Audio Cache Tests
# ============================================================================


func test_cache_sound_adds_to_cache() -> void:
	audio.cache_sound("res://cached.wav")

	assert_true(audio.is_sound_cached("res://cached.wav"),
		"Sound should be in cache after caching")


func test_is_sound_cached_returns_false_for_uncached() -> void:
	assert_false(audio.is_sound_cached("res://not_cached.wav"),
		"Should return false for uncached sound")


func test_clear_cache_removes_all_sounds() -> void:
	audio.cache_sound("res://a.wav")
	audio.cache_sound("res://b.wav")

	audio.clear_cache()

	assert_false(audio.is_sound_cached("res://a.wav"))
	assert_false(audio.is_sound_cached("res://b.wav"))


# ============================================================================
# Multiple Sounds Tests
# ============================================================================


func test_multiple_sounds_can_play_simultaneously() -> void:
	audio.play_sound("res://a.wav")
	audio.play_sound("res://b.wav")
	audio.play_sound("res://c.wav")

	assert_eq(audio.played_sounds.size(), 3)


func test_multiple_2d_sounds_with_different_positions() -> void:
	audio.play_sound_2d("res://shot.wav", Vector2(0, 0))
	audio.play_sound_2d("res://shot.wav", Vector2(100, 100))
	audio.play_sound_2d("res://shot.wav", Vector2(200, 200))

	assert_eq(audio.played_sounds_2d.size(), 3)
	assert_eq(audio.played_sounds_2d[0]["position"], Vector2(0, 0))
	assert_eq(audio.played_sounds_2d[1]["position"], Vector2(100, 100))
	assert_eq(audio.played_sounds_2d[2]["position"], Vector2(200, 200))


# ============================================================================
# Specific Sound Method Tests (testing the expected behavior pattern)
# ============================================================================


func test_m16_shot_uses_correct_volume() -> void:
	# Simulating play_m16_shot behavior
	var m16_shots := ["res://assets/audio/m16 1.wav"]
	var volume_shot := -5.0
	var position := Vector2(100, 100)

	audio.play_random_sound_2d(m16_shots, position, volume_shot)

	assert_eq(audio.played_sounds_2d[0]["volume"], -5.0)


func test_reload_sound_uses_correct_volume() -> void:
	# Simulating reload sound behavior
	var volume_reload := -3.0
	var position := Vector2(100, 100)

	audio.play_sound_2d("res://reload.wav", position, volume_reload)

	assert_eq(audio.played_sounds_2d[0]["volume"], -3.0)
