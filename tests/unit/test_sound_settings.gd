extends GutTest
## Unit tests for SoundSettings autoload (Issue #839).
##
## Tests volume management, persistence logic, and dB conversion
## without requiring the Godot audio bus system.


# ============================================================================
# Mock SoundSettings for Logic Tests
# ============================================================================


class MockSoundSettings:
	## Linear volume for sound effects [0.0, 1.0].
	var effects_volume: float = 1.0

	## Linear volume for music [0.0, 1.0].
	var music_volume: float = 1.0

	## Whether pause-screen music muffling is enabled.
	var music_muffle_enabled: bool = true

	## Track emitted signals
	var settings_changed_count: int = 0

	## Minimum volume in dB (effectively silent).
	const MIN_VOLUME_DB: float = -80.0

	## Maximum volume in dB (full volume).
	const MAX_VOLUME_DB: float = 0.0

	const MAX_EFFECTS_VOLUME: float = 1.0
	const MAX_MUSIC_VOLUME: float = 2.0

	func set_effects_volume(volume: float) -> void:
		volume = clamp(volume, 0.0, MAX_EFFECTS_VOLUME)
		if not is_equal_approx(effects_volume, volume):
			effects_volume = volume
			settings_changed_count += 1

	func get_effects_volume() -> float:
		return effects_volume

	func set_music_volume(volume: float) -> void:
		volume = clamp(volume, 0.0, MAX_MUSIC_VOLUME)
		if not is_equal_approx(music_volume, volume):
			music_volume = volume
			settings_changed_count += 1

	func get_music_volume() -> float:
		return music_volume

	func set_music_muffle_enabled(enabled: bool) -> void:
		if music_muffle_enabled != enabled:
			music_muffle_enabled = enabled
			settings_changed_count += 1

	func is_music_muffle_enabled() -> bool:
		return music_muffle_enabled

	func linear_to_db(linear: float) -> float:
		if linear <= 0.0:
			return MIN_VOLUME_DB
		return 20.0 * log(linear) / log(10.0)


var settings: MockSoundSettings


func before_each() -> void:
	settings = MockSoundSettings.new()


func after_each() -> void:
	settings = null


# ============================================================================
# Default Values Tests
# ============================================================================


func test_default_effects_volume_is_full() -> void:
	assert_eq(settings.get_effects_volume(), 1.0,
		"Default effects volume should be 1.0 (100%)")


func test_default_music_volume_is_full() -> void:
	assert_eq(settings.get_music_volume(), 1.0,
		"Default music volume should be 1.0 (100%)")


func test_default_music_muffle_is_enabled() -> void:
	assert_true(settings.is_music_muffle_enabled(),
		"Music muffle should be enabled by default to preserve existing pause behavior")


# ============================================================================
# Effects Volume Tests
# ============================================================================


func test_set_effects_volume_stores_value() -> void:
	settings.set_effects_volume(0.5)
	assert_eq(settings.get_effects_volume(), 0.5,
		"Effects volume should be stored as 0.5")


func test_set_effects_volume_clamps_above_max() -> void:
	settings.set_effects_volume(1.5)
	assert_eq(settings.get_effects_volume(), 1.0,
		"Effects volume above 1.0 should be clamped to 1.0")


func test_set_effects_volume_clamps_below_min() -> void:
	settings.set_effects_volume(-0.5)
	assert_eq(settings.get_effects_volume(), 0.0,
		"Effects volume below 0.0 should be clamped to 0.0")


func test_set_effects_volume_zero_is_valid() -> void:
	settings.set_effects_volume(0.0)
	assert_eq(settings.get_effects_volume(), 0.0,
		"Effects volume of 0.0 (mute) should be valid")


func test_set_effects_volume_emits_signal_on_change() -> void:
	settings.set_effects_volume(0.75)
	assert_eq(settings.settings_changed_count, 1,
		"settings_changed should be emitted when effects volume changes")


func test_set_effects_volume_no_signal_when_same() -> void:
	settings.set_effects_volume(1.0)  # Already 1.0 by default
	assert_eq(settings.settings_changed_count, 0,
		"settings_changed should NOT be emitted when value does not change")


# ============================================================================
# Music Volume Tests
# ============================================================================


func test_set_music_volume_stores_value() -> void:
	settings.set_music_volume(0.3)
	assert_eq(settings.get_music_volume(), 0.3,
		"Music volume should be stored as 0.3")


func test_set_music_volume_clamps_above_max() -> void:
	settings.set_music_volume(2.5)
	assert_eq(settings.get_music_volume(), settings.MAX_MUSIC_VOLUME,
		"Music volume above 2.0 should be clamped to 2.0")


func test_set_music_volume_accepts_200_percent() -> void:
	settings.set_music_volume(2.0)
	assert_eq(settings.get_music_volume(), 2.0,
		"Music volume should support 2.0 (200%%)")


func test_set_music_volume_clamps_below_min() -> void:
	settings.set_music_volume(-1.0)
	assert_eq(settings.get_music_volume(), 0.0,
		"Music volume below 0.0 should be clamped to 0.0")


func test_set_music_volume_emits_signal_on_change() -> void:
	settings.set_music_volume(0.5)
	assert_eq(settings.settings_changed_count, 1,
		"settings_changed should be emitted when music volume changes")


func test_set_music_volume_no_signal_when_same() -> void:
	settings.set_music_volume(1.0)  # Already 1.0 by default
	assert_eq(settings.settings_changed_count, 0,
		"settings_changed should NOT be emitted when value does not change")


func test_set_music_muffle_enabled_stores_value() -> void:
	settings.set_music_muffle_enabled(false)
	assert_false(settings.is_music_muffle_enabled(),
		"Music muffle setting should store false when disabled")


func test_set_music_muffle_enabled_emits_signal_on_change() -> void:
	settings.set_music_muffle_enabled(false)
	assert_eq(settings.settings_changed_count, 1,
		"settings_changed should be emitted when music muffle setting changes")


func test_set_music_muffle_enabled_no_signal_when_same() -> void:
	settings.set_music_muffle_enabled(true)  # Already true by default
	assert_eq(settings.settings_changed_count, 0,
		"settings_changed should NOT be emitted when music muffle setting does not change")


# ============================================================================
# Independent Volume Tests
# ============================================================================


func test_effects_and_music_volumes_are_independent() -> void:
	settings.set_effects_volume(0.3)
	settings.set_music_volume(0.8)

	assert_eq(settings.get_effects_volume(), 0.3,
		"Effects volume should remain 0.3")
	assert_eq(settings.get_music_volume(), 0.8,
		"Music volume should be 0.8")


func test_multiple_changes_emit_signal_each_time() -> void:
	settings.set_effects_volume(0.5)
	settings.set_effects_volume(0.7)
	settings.set_music_volume(0.4)

	assert_eq(settings.settings_changed_count, 3,
		"settings_changed should be emitted 3 times for 3 different changes")


# ============================================================================
# dB Conversion Tests
# ============================================================================


func test_linear_to_db_full_volume_is_zero_db() -> void:
	var db := settings.linear_to_db(1.0)
	assert_almost_eq(db, 0.0, 0.01,
		"Full volume (1.0) should convert to 0.0 dB")


func test_linear_to_db_double_volume_is_plus_6db() -> void:
	var db := settings.linear_to_db(2.0)
	assert_almost_eq(db, 6.02, 0.1,
		"200%% volume should convert to approximately +6 dB")


func test_linear_to_db_zero_volume_is_silence() -> void:
	var db := settings.linear_to_db(0.0)
	assert_eq(db, settings.MIN_VOLUME_DB,
		"Zero volume should convert to MIN_VOLUME_DB (-80 dB)")


func test_linear_to_db_half_volume_is_approximately_minus_6db() -> void:
	# 0.5 linear ≈ -6 dB
	var db := settings.linear_to_db(0.5)
	assert_almost_eq(db, -6.02, 0.1,
		"50%% volume should convert to approximately -6 dB")


func test_linear_to_db_quarter_volume_is_approximately_minus_12db() -> void:
	# 0.25 linear ≈ -12 dB
	var db := settings.linear_to_db(0.25)
	assert_almost_eq(db, -12.04, 0.1,
		"25%% volume should convert to approximately -12 dB")


func test_linear_to_db_negative_input_returns_silence() -> void:
	var db := settings.linear_to_db(-0.5)
	assert_eq(db, settings.MIN_VOLUME_DB,
		"Negative linear volume should return MIN_VOLUME_DB")


# ============================================================================
# Volume Range Tests
# ============================================================================


func test_effects_volume_accepts_all_valid_percentages() -> void:
	for i in range(0, 101, 10):
		settings.set_effects_volume(i / 100.0)
		assert_almost_eq(settings.get_effects_volume(), i / 100.0, 0.001,
			"Effects volume %d%% should be accepted" % i)


func test_music_volume_accepts_all_valid_percentages() -> void:
	for i in range(0, 201, 10):
		settings.set_music_volume(i / 100.0)
		assert_almost_eq(settings.get_music_volume(), i / 100.0, 0.001,
			"Music volume %d%% should be accepted" % i)
