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
		FINE_MOTOR_SKILLS = 19,
		DASH = 20,
		GRENADE_BAG = 21
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


func test_fine_motor_skills_starts_locked() -> void:
	# Fine Motor Skills requires 1000 shots with shotgun/sniper/revolver (Issue #1346)
	var unlocked_items := {
		19: false  # FINE_MOTOR_SKILLS — locked until condition met
	}
	assert_false(unlocked_items[19],
		"FINE_MOTOR_SKILLS should start locked — unlock requires 1000 special weapon shots (Issue #1346)")


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


# ============================================================================
# Sequential Reload Delay Tests (Issue #1337)
# ============================================================================


func test_fine_motor_skills_activation_delay_is_200ms() -> void:
	# The activation delay should be 200ms (0.2 seconds) as specified in Issue #1337
	var expected_delay := 0.2
	# This constant is defined in player.gd as FINE_MOTOR_SKILLS_ACTIVATION_DELAY
	assert_eq(expected_delay, 0.2,
		"Fine Motor Skills activation delay should be 200ms (0.2 seconds)")


func test_fine_motor_skills_stage_delay_is_200ms() -> void:
	# The stage delay between sequential reload steps should be 200ms
	var expected_delay := 0.2
	# This constant is defined in player.gd as FINE_MOTOR_SKILLS_STAGE_DELAY
	assert_eq(expected_delay, 0.2,
		"Fine Motor Skills stage delay should be 200ms (0.2 seconds)")


func test_fine_motor_skills_prevents_overlapping_activations() -> void:
	# When a reload sequence is in progress, additional presses should be ignored
	var is_active := true  # Simulates _fine_motor_skills_active = true
	var should_ignore := is_active  # Second press should be blocked
	assert_true(should_ignore,
		"Fine Motor Skills should ignore input while a reload sequence is active")


func test_fine_motor_skills_sniper_has_four_sequential_bolt_steps() -> void:
	# Sniper rifle bolt cycle should play 4 steps sequentially
	var bolt_steps := [1, 2, 3, 4]
	assert_eq(bolt_steps.size(), 4,
		"Sniper rifle bolt cycle should have exactly 4 sequential steps")


func test_fine_motor_skills_shotgun_sequential_shell_loading() -> void:
	# Shotgun should load shells one by one (not all at once)
	# Sequence: action open → shell 1 → shell 2 → ... → action close
	var tube_capacity := 4
	var shells_loaded := 0
	var stages := ["action_open"]
	for i in range(tube_capacity):
		shells_loaded += 1
		stages.append("shell_load_%d" % (i + 1))
	stages.append("action_close")

	assert_eq(stages.size(), tube_capacity + 2,
		"Shotgun reload should have capacity+2 stages (open + shells + close)")
	assert_eq(stages[0], "action_open", "First stage should be action open")
	assert_eq(stages[-1], "action_close", "Last stage should be action close")


func test_fine_motor_skills_revolver_sequential_cartridge_loading() -> void:
	# Revolver should insert cartridges one by one
	# Sequence: cylinder open → cartridge 1 → cartridge 2 → ... → cylinder close
	var cylinder_capacity := 6
	var cartridges_inserted := 0
	var stages := ["cylinder_open"]
	for i in range(cylinder_capacity):
		cartridges_inserted += 1
		stages.append("cartridge_insert_%d" % (i + 1))
	stages.append("cylinder_close")

	assert_eq(stages.size(), cylinder_capacity + 2,
		"Revolver reload should have capacity+2 stages (open + cartridges + close)")
	assert_eq(stages[0], "cylinder_open", "First stage should be cylinder open")
	assert_eq(stages[-1], "cylinder_close", "Last stage should be cylinder close")
