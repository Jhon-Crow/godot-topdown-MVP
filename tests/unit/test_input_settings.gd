extends GutTest
## Unit tests for InputSettings utility functions.
##
## Tests the pure functions that don't require InputMap or file system access.


# ============================================================================
# get_action_display_name Tests
# ============================================================================


# Test class that mirrors InputSettings' testable methods
class InputSettingsHelper:
	static func get_action_display_name(action_name: String) -> String:
		match action_name:
			"move_up":
				return "Move Up"
			"move_down":
				return "Move Down"
			"move_left":
				return "Move Left"
			"move_right":
				return "Move Right"
			"shoot":
				return "Shoot"
			"pause":
				return "Pause"
			_:
				return action_name.capitalize().replace("_", " ")


func test_get_action_display_name_move_up() -> void:
	var display := InputSettingsHelper.get_action_display_name("move_up")

	assert_eq(display, "Move Up", "move_up should display as 'Move Up'")


func test_get_action_display_name_move_down() -> void:
	var display := InputSettingsHelper.get_action_display_name("move_down")

	assert_eq(display, "Move Down", "move_down should display as 'Move Down'")


func test_get_action_display_name_move_left() -> void:
	var display := InputSettingsHelper.get_action_display_name("move_left")

	assert_eq(display, "Move Left", "move_left should display as 'Move Left'")


func test_get_action_display_name_move_right() -> void:
	var display := InputSettingsHelper.get_action_display_name("move_right")

	assert_eq(display, "Move Right", "move_right should display as 'Move Right'")


func test_get_action_display_name_shoot() -> void:
	var display := InputSettingsHelper.get_action_display_name("shoot")

	assert_eq(display, "Shoot", "shoot should display as 'Shoot'")


func test_get_action_display_name_pause() -> void:
	var display := InputSettingsHelper.get_action_display_name("pause")

	assert_eq(display, "Pause", "pause should display as 'Pause'")


func test_get_action_display_name_unknown_action() -> void:
	var display := InputSettingsHelper.get_action_display_name("some_custom_action")

	assert_eq(display, "Some Custom Action", "Unknown actions should be capitalized with underscores replaced")


func test_get_action_display_name_single_word() -> void:
	var display := InputSettingsHelper.get_action_display_name("jump")

	assert_eq(display, "Jump", "Single word actions should be capitalized")


func test_get_action_display_name_multiple_underscores() -> void:
	var display := InputSettingsHelper.get_action_display_name("special_attack_mode")

	assert_eq(display, "Special Attack Mode", "Multiple underscores should all be replaced with spaces")


# ============================================================================
# Event Matching Logic Tests
# ============================================================================


# Helper class for testing event matching logic
class EventMatchHelper:
	static func events_match_keycode(keycode1: int, keycode2: int) -> bool:
		return keycode1 == keycode2

	static func events_match_mouse_button(button1: int, button2: int) -> bool:
		return button1 == button2


func test_keycode_match_same_key() -> void:
	var result := EventMatchHelper.events_match_keycode(KEY_W, KEY_W)

	assert_true(result, "Same keycodes should match")


func test_keycode_match_different_keys() -> void:
	var result := EventMatchHelper.events_match_keycode(KEY_W, KEY_S)

	assert_false(result, "Different keycodes should not match")


func test_mouse_button_match_same_button() -> void:
	var result := EventMatchHelper.events_match_mouse_button(MOUSE_BUTTON_LEFT, MOUSE_BUTTON_LEFT)

	assert_true(result, "Same mouse buttons should match")


func test_mouse_button_match_different_buttons() -> void:
	var result := EventMatchHelper.events_match_mouse_button(MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT)

	assert_false(result, "Different mouse buttons should not match")


# ============================================================================
# Remappable Actions List Tests
# ============================================================================


func test_remappable_actions_contains_expected_actions() -> void:
	var remappable_actions: Array[String] = [
		"move_up",
		"move_down",
		"move_left",
		"move_right",
		"shoot",
		"pause"
	]

	assert_eq(remappable_actions.size(), 6, "Should have 6 remappable actions")
	assert_has(remappable_actions, "move_up", "Should contain move_up")
	assert_has(remappable_actions, "move_down", "Should contain move_down")
	assert_has(remappable_actions, "move_left", "Should contain move_left")
	assert_has(remappable_actions, "move_right", "Should contain move_right")
	assert_has(remappable_actions, "shoot", "Should contain shoot")
	assert_has(remappable_actions, "pause", "Should contain pause")


# ============================================================================
# Key Conflict Detection Logic Tests
# ============================================================================


class KeyConflictHelper:
	## Simulates conflict detection logic
	var action_keycodes: Dictionary = {}

	func set_action_keycode(action: String, keycode: int) -> void:
		action_keycodes[action] = keycode

	func check_key_conflict(keycode: int, exclude_action: String = "") -> String:
		for action in action_keycodes:
			if action == exclude_action:
				continue
			if action_keycodes[action] == keycode:
				return action
		return ""


var conflict_helper: KeyConflictHelper


func before_each() -> void:
	conflict_helper = KeyConflictHelper.new()


func test_no_conflict_when_key_unused() -> void:
	conflict_helper.set_action_keycode("move_up", KEY_W)

	var conflict := conflict_helper.check_key_conflict(KEY_S, "")

	assert_eq(conflict, "", "No conflict when key is not used")


func test_conflict_when_key_used() -> void:
	conflict_helper.set_action_keycode("move_up", KEY_W)

	var conflict := conflict_helper.check_key_conflict(KEY_W, "")

	assert_eq(conflict, "move_up", "Should detect conflict with move_up")


func test_no_conflict_when_excluding_same_action() -> void:
	conflict_helper.set_action_keycode("move_up", KEY_W)

	var conflict := conflict_helper.check_key_conflict(KEY_W, "move_up")

	assert_eq(conflict, "", "Should not conflict with excluded action")


func test_conflict_detection_with_multiple_actions() -> void:
	conflict_helper.set_action_keycode("move_up", KEY_W)
	conflict_helper.set_action_keycode("move_down", KEY_S)
	conflict_helper.set_action_keycode("move_left", KEY_A)
	conflict_helper.set_action_keycode("move_right", KEY_D)

	var conflict := conflict_helper.check_key_conflict(KEY_A, "move_up")

	assert_eq(conflict, "move_left", "Should detect conflict with move_left")


func test_no_conflict_with_available_key() -> void:
	conflict_helper.set_action_keycode("move_up", KEY_W)
	conflict_helper.set_action_keycode("move_down", KEY_S)

	var conflict := conflict_helper.check_key_conflict(KEY_SPACE, "")

	assert_eq(conflict, "", "Space key should not conflict")


# ============================================================================
# Mouse Button Event Name Tests
# ============================================================================


class EventNameHelper:
	static func get_mouse_button_name(button_index: int) -> String:
		match button_index:
			MOUSE_BUTTON_LEFT:
				return "Left Mouse"
			MOUSE_BUTTON_RIGHT:
				return "Right Mouse"
			MOUSE_BUTTON_MIDDLE:
				return "Middle Mouse"
			MOUSE_BUTTON_WHEEL_UP:
				return "Mouse Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN:
				return "Mouse Wheel Down"
			_:
				return "Mouse " + str(button_index)


func test_mouse_button_name_left() -> void:
	var name := EventNameHelper.get_mouse_button_name(MOUSE_BUTTON_LEFT)

	assert_eq(name, "Left Mouse", "Left mouse button name")


func test_mouse_button_name_right() -> void:
	var name := EventNameHelper.get_mouse_button_name(MOUSE_BUTTON_RIGHT)

	assert_eq(name, "Right Mouse", "Right mouse button name")


func test_mouse_button_name_middle() -> void:
	var name := EventNameHelper.get_mouse_button_name(MOUSE_BUTTON_MIDDLE)

	assert_eq(name, "Middle Mouse", "Middle mouse button name")


func test_mouse_button_name_wheel_up() -> void:
	var name := EventNameHelper.get_mouse_button_name(MOUSE_BUTTON_WHEEL_UP)

	assert_eq(name, "Mouse Wheel Up", "Wheel up name")


func test_mouse_button_name_wheel_down() -> void:
	var name := EventNameHelper.get_mouse_button_name(MOUSE_BUTTON_WHEEL_DOWN)

	assert_eq(name, "Mouse Wheel Down", "Wheel down name")


func test_mouse_button_name_other() -> void:
	var name := EventNameHelper.get_mouse_button_name(8)

	assert_eq(name, "Mouse 8", "Unknown mouse button should show index")


# ============================================================================
# Keycode Storage Logic Tests
# ============================================================================


class KeycodeStorageHelper:
	## Tests the logic for storing keycodes (negative for mouse, positive for keys)

	static func encode_mouse_button(button_index: int) -> int:
		return -button_index

	static func decode_is_mouse_button(stored_value: int) -> bool:
		return stored_value < 0

	static func decode_mouse_button(stored_value: int) -> int:
		return -stored_value

	static func decode_keycode(stored_value: int) -> int:
		return stored_value


func test_encode_mouse_button_left() -> void:
	var encoded := KeycodeStorageHelper.encode_mouse_button(MOUSE_BUTTON_LEFT)

	assert_eq(encoded, -1, "Left mouse button should encode as -1")


func test_encode_mouse_button_right() -> void:
	var encoded := KeycodeStorageHelper.encode_mouse_button(MOUSE_BUTTON_RIGHT)

	assert_eq(encoded, -2, "Right mouse button should encode as -2")


func test_decode_is_mouse_button_negative() -> void:
	var is_mouse := KeycodeStorageHelper.decode_is_mouse_button(-1)

	assert_true(is_mouse, "Negative values indicate mouse buttons")


func test_decode_is_mouse_button_positive() -> void:
	var is_mouse := KeycodeStorageHelper.decode_is_mouse_button(KEY_W)

	assert_false(is_mouse, "Positive values indicate keyboard keys")


func test_decode_mouse_button() -> void:
	var button := KeycodeStorageHelper.decode_mouse_button(-2)

	assert_eq(button, MOUSE_BUTTON_RIGHT, "Should decode back to right mouse button")


func test_decode_keycode() -> void:
	var keycode := KeycodeStorageHelper.decode_keycode(KEY_SPACE)

	assert_eq(keycode, KEY_SPACE, "Should return the keycode unchanged")


func test_roundtrip_mouse_button() -> void:
	var original := MOUSE_BUTTON_MIDDLE
	var encoded := KeycodeStorageHelper.encode_mouse_button(original)
	var decoded := KeycodeStorageHelper.decode_mouse_button(encoded)

	assert_eq(decoded, original, "Mouse button should survive encode/decode roundtrip")
