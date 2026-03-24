extends GutTest
## Unit tests for WeaponHintsSettings autoload.
##
## Tests the HintMode enum, should_show_hints logic, weapon tracking,
## and reset functionality.


# ============================================================================
# Mock WeaponHintsSettings
# ============================================================================


class MockWeaponHintsSettings:
	## Signal emitted when settings change.
	signal settings_changed

	## Signal emitted when a weapon is marked as seen.
	signal weapon_seen(weapon_id: String)

	## Hint display mode enum.
	enum HintMode {
		ALWAYS = 0,
		FIRST_TIME_ONLY = 1,
		NEVER = 2
	}

	## Current hint display mode.
	var hint_mode: HintMode = HintMode.ALWAYS

	## Dictionary tracking which weapons have been seen.
	var weapons_seen: Dictionary = {}

	func set_hint_mode(mode: HintMode) -> void:
		if hint_mode != mode:
			hint_mode = mode
			settings_changed.emit()

	func get_hint_mode() -> HintMode:
		return hint_mode

	func should_show_hints(weapon_id: String) -> bool:
		match hint_mode:
			HintMode.ALWAYS:
				return true
			HintMode.FIRST_TIME_ONLY:
				return not weapons_seen.get(weapon_id, false)
			HintMode.NEVER:
				return false
		return false

	func mark_weapon_seen(weapon_id: String) -> void:
		if not weapons_seen.get(weapon_id, false):
			weapons_seen[weapon_id] = true
			weapon_seen.emit(weapon_id)

	func is_weapon_seen(weapon_id: String) -> bool:
		return weapons_seen.get(weapon_id, false)

	func reset_weapons_seen() -> void:
		weapons_seen.clear()
		settings_changed.emit()


var settings: MockWeaponHintsSettings


func before_each() -> void:
	settings = MockWeaponHintsSettings.new()


func after_each() -> void:
	settings = null


# ============================================================================
# HintMode Enum Value Tests
# ============================================================================


func test_hint_mode_always_is_zero() -> void:
	assert_eq(MockWeaponHintsSettings.HintMode.ALWAYS, 0,
		"HintMode.ALWAYS should be 0")


func test_hint_mode_first_time_only_is_one() -> void:
	assert_eq(MockWeaponHintsSettings.HintMode.FIRST_TIME_ONLY, 1,
		"HintMode.FIRST_TIME_ONLY should be 1")


func test_hint_mode_never_is_two() -> void:
	assert_eq(MockWeaponHintsSettings.HintMode.NEVER, 2,
		"HintMode.NEVER should be 2")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_default_hint_mode_is_always() -> void:
	assert_eq(settings.get_hint_mode(), MockWeaponHintsSettings.HintMode.ALWAYS,
		"Default hint mode should be ALWAYS")


func test_default_weapons_seen_is_empty() -> void:
	assert_eq(settings.weapons_seen.size(), 0,
		"Default weapons_seen should be empty")


# ============================================================================
# should_show_hints Tests - ALWAYS Mode
# ============================================================================


func test_always_mode_shows_hints_for_unseen_weapon() -> void:
	assert_true(settings.should_show_hints("rifle"),
		"ALWAYS mode should show hints for unseen weapon")


func test_always_mode_shows_hints_for_seen_weapon() -> void:
	settings.mark_weapon_seen("rifle")

	assert_true(settings.should_show_hints("rifle"),
		"ALWAYS mode should show hints even for seen weapon")


# ============================================================================
# should_show_hints Tests - FIRST_TIME_ONLY Mode
# ============================================================================


func test_first_time_mode_shows_hints_for_unseen_weapon() -> void:
	settings.set_hint_mode(MockWeaponHintsSettings.HintMode.FIRST_TIME_ONLY)

	assert_true(settings.should_show_hints("shotgun"),
		"FIRST_TIME_ONLY mode should show hints for unseen weapon")


func test_first_time_mode_hides_hints_for_seen_weapon() -> void:
	settings.set_hint_mode(MockWeaponHintsSettings.HintMode.FIRST_TIME_ONLY)
	settings.mark_weapon_seen("shotgun")

	assert_false(settings.should_show_hints("shotgun"),
		"FIRST_TIME_ONLY mode should hide hints for seen weapon")


func test_first_time_mode_shows_hints_for_different_unseen_weapon() -> void:
	settings.set_hint_mode(MockWeaponHintsSettings.HintMode.FIRST_TIME_ONLY)
	settings.mark_weapon_seen("shotgun")

	assert_true(settings.should_show_hints("pistol"),
		"FIRST_TIME_ONLY mode should show hints for different unseen weapon")


# ============================================================================
# should_show_hints Tests - NEVER Mode
# ============================================================================


func test_never_mode_hides_hints_for_unseen_weapon() -> void:
	settings.set_hint_mode(MockWeaponHintsSettings.HintMode.NEVER)

	assert_false(settings.should_show_hints("rifle"),
		"NEVER mode should hide hints for unseen weapon")


func test_never_mode_hides_hints_for_seen_weapon() -> void:
	settings.set_hint_mode(MockWeaponHintsSettings.HintMode.NEVER)
	settings.mark_weapon_seen("rifle")

	assert_false(settings.should_show_hints("rifle"),
		"NEVER mode should hide hints even for seen weapon")


# ============================================================================
# mark_weapon_seen / is_weapon_seen Tests
# ============================================================================


func test_mark_weapon_seen() -> void:
	settings.mark_weapon_seen("rifle")

	assert_true(settings.is_weapon_seen("rifle"),
		"Weapon should be marked as seen")


func test_unseen_weapon_returns_false() -> void:
	assert_false(settings.is_weapon_seen("unknown_weapon"),
		"Unseen weapon should return false")


func test_mark_multiple_weapons_seen() -> void:
	settings.mark_weapon_seen("rifle")
	settings.mark_weapon_seen("shotgun")
	settings.mark_weapon_seen("pistol")

	assert_true(settings.is_weapon_seen("rifle"), "Rifle should be seen")
	assert_true(settings.is_weapon_seen("shotgun"), "Shotgun should be seen")
	assert_true(settings.is_weapon_seen("pistol"), "Pistol should be seen")
	assert_false(settings.is_weapon_seen("smg"), "SMG should not be seen")


func test_mark_weapon_seen_emits_signal() -> void:
	var seen_weapon := ""
	settings.weapon_seen.connect(func(w): seen_weapon = w)

	settings.mark_weapon_seen("rifle")

	assert_eq(seen_weapon, "rifle",
		"weapon_seen signal should emit with weapon_id")


func test_mark_already_seen_weapon_does_not_emit_signal() -> void:
	settings.mark_weapon_seen("rifle")

	var signal_count := 0
	settings.weapon_seen.connect(func(_w): signal_count += 1)

	settings.mark_weapon_seen("rifle")  # Already seen

	assert_eq(signal_count, 0,
		"Marking already-seen weapon should not emit signal")


# ============================================================================
# reset_weapons_seen Tests
# ============================================================================


func test_reset_weapons_seen_clears_all() -> void:
	settings.mark_weapon_seen("rifle")
	settings.mark_weapon_seen("shotgun")

	settings.reset_weapons_seen()

	assert_false(settings.is_weapon_seen("rifle"), "Rifle should no longer be seen")
	assert_false(settings.is_weapon_seen("shotgun"), "Shotgun should no longer be seen")
	assert_eq(settings.weapons_seen.size(), 0, "weapons_seen should be empty")


func test_reset_weapons_seen_emits_settings_changed() -> void:
	var signal_count := 0
	settings.settings_changed.connect(func(): signal_count += 1)

	settings.reset_weapons_seen()

	assert_eq(signal_count, 1,
		"reset_weapons_seen should emit settings_changed signal")


func test_reset_then_first_time_mode_shows_hints_again() -> void:
	settings.set_hint_mode(MockWeaponHintsSettings.HintMode.FIRST_TIME_ONLY)
	settings.mark_weapon_seen("rifle")

	assert_false(settings.should_show_hints("rifle"), "Seen weapon should not show hints")

	settings.reset_weapons_seen()

	assert_true(settings.should_show_hints("rifle"),
		"After reset, weapon should show hints again in FIRST_TIME_ONLY mode")
