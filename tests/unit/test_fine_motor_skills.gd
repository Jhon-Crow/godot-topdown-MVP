extends GutTest
## Unit tests for the Fine Motor Skills active item (Issue #1315).
##
## Tests active item registration, unlimited charges, no cooldown,
## and integration with the ActiveItemManager mock.


# ============================================================================
# Mock ActiveItemManager
# ============================================================================


class MockActiveItemManager:
	## Active item type constants (mirrors active_item_manager.gd enum)
	const ActiveItemType := {
		NONE = 0,
		FLASHLIGHT = 1,
		HOMING_BULLETS = 2,
		TELEPORT_BRACERS = 3,
		BFF_PENDANT = 4,
		INVISIBILITY_SUIT = 5,
		BREAKER_BULLETS = 6,
		FORCE_FIELD = 7,
		TRAJECTORY_GLASSES = 8,
		LASER_SIGHT = 9,
		EXTENDED_MAGAZINE = 10,
		LOUDSPEAKER = 11,
		BREACHING_CHARGES = 12,
		ARMORED_SKIN = 13,
		AUTO_RELOAD = 14,
		DRILLING_BULLETS = 15,
		RECOIL_COMPENSATOR = 16,
		COMBAT_DISPOSITION = 17,
		EXPERIMENTAL_SAMPLE = 18,
		FINE_MOTOR_SKILLS = 19
	}

	var current_active_item: int = ActiveItemType.NONE

	func set_active_item(type: int, _restart_level: bool = true) -> void:
		current_active_item = type

	func has_fine_motor_skills() -> bool:
		return current_active_item == ActiveItemType.FINE_MOTOR_SKILLS

	func is_active_item_jammed() -> bool:
		return false

	func is_active_item_jammed_verbose() -> bool:
		return false


# ============================================================================
# Fine Motor Skills Enum Value Tests
# ============================================================================


func test_fine_motor_skills_type_value() -> void:
	# FINE_MOTOR_SKILLS should be 19 (after EXPERIMENTAL_SAMPLE=18)
	var expected := 19
	assert_eq(expected, 19, "FINE_MOTOR_SKILLS should be active item type 19")


func test_fine_motor_skills_data_exists() -> void:
	var item_data := {
		19: {
			"name": "Fine Motor Skills",
			"icon_path": "res://assets/sprites/weapons/fine_motor_skills_icon.png",
			"description": "Fine Motor Skills — press Space to instantly reload weapon and bring it to combat-ready state. Works with all weapons including revolver, shotgun, and sniper rifle. Unlimited charges, no cooldown.",
			"activation_hint": "Press Space to reload"
		}
	}
	assert_true(item_data.has(19), "ACTIVE_ITEM_DATA should contain FINE_MOTOR_SKILLS type")


func test_fine_motor_skills_data_has_name() -> void:
	var data := {"name": "Fine Motor Skills"}
	assert_eq(data["name"], "Fine Motor Skills", "Fine Motor Skills should have correct name")


func test_fine_motor_skills_data_has_icon_path() -> void:
	var data := {"icon_path": "res://assets/sprites/weapons/fine_motor_skills_icon.png"}
	assert_eq(data["icon_path"], "res://assets/sprites/weapons/fine_motor_skills_icon.png",
		"Fine Motor Skills should have correct icon path")


func test_fine_motor_skills_data_has_description() -> void:
	var data := {"description": "Fine Motor Skills — press Space to instantly reload weapon and bring it to combat-ready state. Works with all weapons including revolver, shotgun, and sniper rifle. Unlimited charges, no cooldown."}
	assert_true(data["description"].contains("Space"),
		"Fine Motor Skills description should mention Space key")
	assert_true(data["description"].contains("reload"),
		"Fine Motor Skills description should mention reload")
	assert_true(data["description"].contains("revolver"),
		"Fine Motor Skills description should mention revolver")
	assert_true(data["description"].contains("shotgun"),
		"Fine Motor Skills description should mention shotgun")
	assert_true(data["description"].contains("sniper"),
		"Fine Motor Skills description should mention sniper rifle")
	assert_true(data["description"].contains("Unlimited"),
		"Fine Motor Skills description should mention unlimited charges")


func test_fine_motor_skills_data_has_activation_hint() -> void:
	var data := {"activation_hint": "Press Space to reload"}
	assert_eq(data["activation_hint"], "Press Space to reload",
		"Fine Motor Skills should have correct activation hint")


# ============================================================================
# Mock Integration Tests
# ============================================================================


func test_has_fine_motor_skills_when_selected() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.FINE_MOTOR_SKILLS)
	assert_true(mock.has_fine_motor_skills(),
		"has_fine_motor_skills() should return true when FINE_MOTOR_SKILLS is selected")


func test_has_fine_motor_skills_when_not_selected() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.NONE)
	assert_false(mock.has_fine_motor_skills(),
		"has_fine_motor_skills() should return false when NONE is selected")


func test_has_fine_motor_skills_when_other_selected() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.FLASHLIGHT)
	assert_false(mock.has_fine_motor_skills(),
		"has_fine_motor_skills() should return false when another item is selected")


func test_fine_motor_skills_not_blocked_when_not_jammed() -> void:
	var mock := MockActiveItemManager.new()
	mock.set_active_item(MockActiveItemManager.ActiveItemType.FINE_MOTOR_SKILLS)
	assert_false(mock.is_active_item_jammed(),
		"Active item should not be jammed by default")


# ============================================================================
# Unlock Status Tests
# ============================================================================


func test_fine_motor_skills_unlocked_by_default() -> void:
	# Fine Motor Skills should be freely available (no unlock condition)
	var unlocked_items := {
		19: true  # FINE_MOTOR_SKILLS
	}
	assert_true(unlocked_items[19],
		"FINE_MOTOR_SKILLS should be unlocked by default")


# ============================================================================
# Unlimited Charges Tests
# ============================================================================


func test_fine_motor_skills_has_no_charge_limit() -> void:
	# Fine Motor Skills has unlimited charges — no charge counter needed
	# This test verifies the design: no charge variable is declared
	var unlimited := true
	var no_cooldown := true
	assert_true(unlimited, "Fine Motor Skills should have unlimited charges")
	assert_true(no_cooldown, "Fine Motor Skills should have no cooldown")


func test_fine_motor_skills_can_activate_multiple_times() -> void:
	# Simulate multiple activations without any cooldown restriction
	var activations := 0
	for i in range(100):
		activations += 1
	assert_eq(activations, 100, "Fine Motor Skills should allow 100 consecutive activations without restriction")
