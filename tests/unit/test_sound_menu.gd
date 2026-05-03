extends GutTest
## Unit tests for SoundMenu UI script (Issue #839).
##
## Tests the sound menu logic for updating UI from settings and
## responding to slider changes, using mock objects.


# ============================================================================
# Mock SoundSettings
# ============================================================================


class MockSoundSettings:
	var effects_volume: float = 1.0
	var music_volume: float = 1.0
	var music_muffle_enabled: bool = true
	var settings_changed_count: int = 0

	func set_effects_volume(volume: float) -> void:
		effects_volume = clamp(volume, 0.0, 1.0)
		settings_changed_count += 1

	func get_effects_volume() -> float:
		return effects_volume

	func set_music_volume(volume: float) -> void:
		music_volume = clamp(volume, 0.0, 1.0)
		settings_changed_count += 1

	func get_music_volume() -> float:
		return music_volume

	func set_music_muffle_enabled(enabled: bool) -> void:
		music_muffle_enabled = enabled
		settings_changed_count += 1

	func is_music_muffle_enabled() -> bool:
		return music_muffle_enabled


# ============================================================================
# Mock SoundMenu logic (mirrors sound_menu.gd logic)
# ============================================================================


class MockSoundMenu:
	## Simulated slider values (0..100)
	var effects_slider_value: float = 100.0
	var music_slider_value: float = 100.0
	var music_muffle_button_pressed: bool = true

	## Simulated label texts
	var effects_value_text: String = "100%"
	var music_value_text: String = "100%"

	## Signal tracking
	var back_pressed_count: int = 0

	func update_ui(sound_settings: MockSoundSettings) -> void:
		effects_slider_value = sound_settings.get_effects_volume() * 100.0
		effects_value_text = "%d%%" % int(effects_slider_value)
		music_slider_value = sound_settings.get_music_volume() * 100.0
		music_value_text = "%d%%" % int(music_slider_value)
		music_muffle_button_pressed = sound_settings.is_music_muffle_enabled()

	func on_effects_volume_changed(value: float, sound_settings: MockSoundSettings) -> void:
		sound_settings.set_effects_volume(value / 100.0)
		effects_value_text = "%d%%" % int(value)

	func on_music_volume_changed(value: float, sound_settings: MockSoundSettings) -> void:
		sound_settings.set_music_volume(value / 100.0)
		music_value_text = "%d%%" % int(value)

	func on_music_muffle_toggled(enabled: bool, sound_settings: MockSoundSettings) -> void:
		sound_settings.set_music_muffle_enabled(enabled)

	func on_back_pressed() -> void:
		back_pressed_count += 1


var menu: MockSoundMenu
var sound_settings: MockSoundSettings


func before_each() -> void:
	menu = MockSoundMenu.new()
	sound_settings = MockSoundSettings.new()


func after_each() -> void:
	menu = null
	sound_settings = null


# ============================================================================
# UI Update Tests
# ============================================================================


func test_update_ui_sets_effects_slider_to_100_when_full_volume() -> void:
	sound_settings.effects_volume = 1.0
	menu.update_ui(sound_settings)
	assert_eq(menu.effects_slider_value, 100.0,
		"Effects slider should be 100 when effects volume is 1.0")


func test_update_ui_sets_music_slider_to_100_when_full_volume() -> void:
	sound_settings.music_volume = 1.0
	menu.update_ui(sound_settings)
	assert_eq(menu.music_slider_value, 100.0,
		"Music slider should be 100 when music volume is 1.0")


func test_update_ui_sets_effects_slider_to_50_when_half_volume() -> void:
	sound_settings.effects_volume = 0.5
	menu.update_ui(sound_settings)
	assert_eq(menu.effects_slider_value, 50.0,
		"Effects slider should be 50 when effects volume is 0.5")


func test_update_ui_sets_music_slider_to_0_when_muted() -> void:
	sound_settings.music_volume = 0.0
	menu.update_ui(sound_settings)
	assert_eq(menu.music_slider_value, 0.0,
		"Music slider should be 0 when music volume is 0.0")


func test_update_ui_sets_effects_label_text() -> void:
	sound_settings.effects_volume = 0.75
	menu.update_ui(sound_settings)
	assert_eq(menu.effects_value_text, "75%",
		"Effects label should show '75%%' when slider is 75")


func test_update_ui_sets_music_label_text() -> void:
	sound_settings.music_volume = 0.3
	menu.update_ui(sound_settings)
	assert_eq(menu.music_value_text, "30%",
		"Music label should show '30%%' when slider is 30")


func test_update_ui_sets_music_muffle_toggle() -> void:
	sound_settings.music_muffle_enabled = false
	menu.update_ui(sound_settings)
	assert_false(menu.music_muffle_button_pressed,
		"Music muffle toggle should reflect SoundSettings")


# ============================================================================
# Slider Change Tests
# ============================================================================


func test_on_effects_volume_changed_updates_settings() -> void:
	menu.on_effects_volume_changed(75.0, sound_settings)
	assert_almost_eq(sound_settings.get_effects_volume(), 0.75, 0.001,
		"SoundSettings effects volume should be 0.75 when slider is at 75")


func test_on_music_volume_changed_updates_settings() -> void:
	menu.on_music_volume_changed(40.0, sound_settings)
	assert_almost_eq(sound_settings.get_music_volume(), 0.40, 0.001,
		"SoundSettings music volume should be 0.40 when slider is at 40")


func test_on_effects_volume_changed_updates_label() -> void:
	menu.on_effects_volume_changed(60.0, sound_settings)
	assert_eq(menu.effects_value_text, "60%",
		"Effects label should show '60%%' after slider change to 60")


func test_on_music_volume_changed_updates_label() -> void:
	menu.on_music_volume_changed(25.0, sound_settings)
	assert_eq(menu.music_value_text, "25%",
		"Music label should show '25%%' after slider change to 25")


func test_on_effects_volume_changed_mutes_to_zero() -> void:
	menu.on_effects_volume_changed(0.0, sound_settings)
	assert_eq(sound_settings.get_effects_volume(), 0.0,
		"Effects volume should be muted (0.0) when slider is at 0")
	assert_eq(menu.effects_value_text, "0%",
		"Effects label should show '0%%' when muted")


func test_on_music_volume_changed_mutes_to_zero() -> void:
	menu.on_music_volume_changed(0.0, sound_settings)
	assert_eq(sound_settings.get_music_volume(), 0.0,
		"Music volume should be muted (0.0) when slider is at 0")
	assert_eq(menu.music_value_text, "0%",
		"Music label should show '0%%' when muted")


func test_on_music_muffle_toggled_updates_settings() -> void:
	menu.on_music_muffle_toggled(false, sound_settings)
	assert_false(sound_settings.is_music_muffle_enabled(),
		"SoundSettings music muffle should be disabled when toggle is off")


# ============================================================================
# Back Button Tests
# ============================================================================


func test_on_back_pressed_emits_back_signal() -> void:
	menu.on_back_pressed()
	assert_eq(menu.back_pressed_count, 1,
		"back_pressed signal should be emitted when back button is pressed")


func test_on_back_pressed_can_be_called_multiple_times() -> void:
	menu.on_back_pressed()
	menu.on_back_pressed()
	assert_eq(menu.back_pressed_count, 2,
		"back_pressed signal should be emitted each time back button is pressed")


# ============================================================================
# Volume Conversion Consistency Tests
# ============================================================================


func test_slider_to_settings_and_back_roundtrip() -> void:
	# Set via slider change
	menu.on_effects_volume_changed(80.0, sound_settings)
	# Read back via update_ui
	menu.update_ui(sound_settings)
	assert_eq(menu.effects_slider_value, 80.0,
		"Round-trip: slider->settings->slider should preserve value of 80")


func test_different_effects_and_music_volumes_displayed_correctly() -> void:
	menu.on_effects_volume_changed(60.0, sound_settings)
	menu.on_music_volume_changed(40.0, sound_settings)
	assert_eq(menu.effects_value_text, "60%",
		"Effects label should show 60%%")
	assert_eq(menu.music_value_text, "40%",
		"Music label should show 40%%")
