extends GutTest
## Unit tests for GameplayMenu.
##
## Tests ROW_HOVER_BG color, blood amount slider range,
## and weapon hints options using a mock class.


# ============================================================================
# Mock GameplayMenu for Testing
# ============================================================================


class MockGameplayMenu:
	## Semi-transparent background colour drawn over a settings row on hover.
	const ROW_HOVER_BG: Color = Color(1.0, 1.0, 1.0, 0.08)

	## Blood amount range: slider goes from 0 to 100, representing 0% to 100%.
	const BLOOD_SLIDER_MIN: float = 0.0
	const BLOOD_SLIDER_MAX: float = 100.0

	## Weapon hints display modes.
	const WEAPON_HINTS_ALWAYS: int = 0
	const WEAPON_HINTS_FIRST_TIME: int = 1
	const WEAPON_HINTS_NEVER: int = 2

	## Current blood amount (0.0 to 1.0, multiplied by 100 for slider).
	var blood_amount: float = 1.0

	## Current weapon hints mode.
	var weapon_hints_mode: int = WEAPON_HINTS_ALWAYS

	## Current unlock toast notification visibility.
	var unlock_notifications_enabled: bool = true

	## Signal tracking.
	var back_pressed_count: int = 0

	## Set blood amount from slider value (0–100).
	func set_blood_amount_from_slider(value: float) -> void:
		blood_amount = value / 100.0

	## Get blood amount as slider value.
	func get_blood_slider_value() -> float:
		return blood_amount * 100.0

	## Get blood amount display text.
	func get_blood_display_text() -> String:
		return "%d%%" % int(blood_amount * 100.0)

	## Set weapon hints mode.
	func set_weapon_hints(mode: int) -> void:
		if mode >= WEAPON_HINTS_ALWAYS and mode <= WEAPON_HINTS_NEVER:
			weapon_hints_mode = mode

	## Toggle unlock toast notifications.
	func set_unlock_notifications(enabled: bool) -> void:
		unlock_notifications_enabled = enabled

	## Press back.
	func press_back() -> void:
		back_pressed_count += 1


var menu: MockGameplayMenu


func before_each() -> void:
	menu = MockGameplayMenu.new()


func after_each() -> void:
	menu = null


# ============================================================================
# ROW_HOVER_BG Color Tests
# ============================================================================


func test_row_hover_bg_value() -> void:
	assert_eq(menu.ROW_HOVER_BG, Color(1.0, 1.0, 1.0, 0.08),
		"ROW_HOVER_BG should be Color(1.0, 1.0, 1.0, 0.08)")


func test_row_hover_bg_is_white_based() -> void:
	assert_eq(menu.ROW_HOVER_BG.r, 1.0, "ROW_HOVER_BG red should be 1.0")
	assert_eq(menu.ROW_HOVER_BG.g, 1.0, "ROW_HOVER_BG green should be 1.0")
	assert_eq(menu.ROW_HOVER_BG.b, 1.0, "ROW_HOVER_BG blue should be 1.0")


func test_row_hover_bg_is_mostly_transparent() -> void:
	assert_true(menu.ROW_HOVER_BG.a < 0.1,
		"ROW_HOVER_BG alpha should be very low (semi-transparent)")


# ============================================================================
# Blood Amount Slider Range Tests
# ============================================================================


func test_blood_slider_min_is_zero() -> void:
	assert_eq(menu.BLOOD_SLIDER_MIN, 0.0,
		"Blood slider minimum should be 0")


func test_blood_slider_max_is_hundred() -> void:
	assert_eq(menu.BLOOD_SLIDER_MAX, 100.0,
		"Blood slider maximum should be 100")


func test_default_blood_amount() -> void:
	assert_eq(menu.blood_amount, 1.0,
		"Default blood amount should be 1.0 (100%)")


func test_blood_slider_value_at_default() -> void:
	assert_eq(menu.get_blood_slider_value(), 100.0,
		"Default slider value should be 100")


func test_set_blood_amount_from_slider_50() -> void:
	menu.set_blood_amount_from_slider(50.0)

	assert_eq(menu.blood_amount, 0.5,
		"Setting slider to 50 should give blood_amount 0.5")


func test_set_blood_amount_from_slider_0() -> void:
	menu.set_blood_amount_from_slider(0.0)

	assert_eq(menu.blood_amount, 0.0,
		"Setting slider to 0 should give blood_amount 0.0")


func test_blood_display_text_full() -> void:
	assert_eq(menu.get_blood_display_text(), "100%",
		"Default display text should be '100%'")


func test_blood_display_text_half() -> void:
	menu.set_blood_amount_from_slider(50.0)

	assert_eq(menu.get_blood_display_text(), "50%",
		"Display text at 50 should be '50%'")


func test_blood_display_text_zero() -> void:
	menu.set_blood_amount_from_slider(0.0)

	assert_eq(menu.get_blood_display_text(), "0%",
		"Display text at 0 should be '0%'")


# ============================================================================
# Weapon Hints Tests
# ============================================================================


func test_weapon_hints_default_is_always() -> void:
	assert_eq(menu.weapon_hints_mode, MockGameplayMenu.WEAPON_HINTS_ALWAYS,
		"Default weapon hints mode should be Always (0)")


func test_set_weapon_hints_first_time() -> void:
	menu.set_weapon_hints(MockGameplayMenu.WEAPON_HINTS_FIRST_TIME)

	assert_eq(menu.weapon_hints_mode, 1,
		"Should be able to set First Time mode")


func test_set_weapon_hints_never() -> void:
	menu.set_weapon_hints(MockGameplayMenu.WEAPON_HINTS_NEVER)

	assert_eq(menu.weapon_hints_mode, 2,
		"Should be able to set Never mode")


func test_weapon_hints_mode_count() -> void:
	# There are 3 modes: Always (0), First time only (1), Never (2)
	var valid_modes := [
		MockGameplayMenu.WEAPON_HINTS_ALWAYS,
		MockGameplayMenu.WEAPON_HINTS_FIRST_TIME,
		MockGameplayMenu.WEAPON_HINTS_NEVER
	]
	assert_eq(valid_modes.size(), 3,
		"Should have 3 weapon hints modes")


# ============================================================================
# Unlock Notifications Tests
# ============================================================================


func test_unlock_notifications_default_enabled() -> void:
	assert_true(menu.unlock_notifications_enabled,
		"Unlock notifications should be enabled by default")


func test_can_disable_unlock_notifications() -> void:
	menu.set_unlock_notifications(false)

	assert_false(menu.unlock_notifications_enabled,
		"Gameplay menu should allow disabling unlock notifications")


func test_can_reenable_unlock_notifications() -> void:
	menu.set_unlock_notifications(false)
	menu.set_unlock_notifications(true)

	assert_true(menu.unlock_notifications_enabled,
		"Gameplay menu should allow re-enabling unlock notifications")


# ============================================================================
# Back Button Tests
# ============================================================================


func test_back_button() -> void:
	menu.press_back()

	assert_eq(menu.back_pressed_count, 1,
		"Should track back press")
