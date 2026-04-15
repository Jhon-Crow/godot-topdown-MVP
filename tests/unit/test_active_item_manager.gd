extends GutTest
## Unit tests for ActiveItemManager autoload.
##
## Tests the active item type management functionality including type selection,
## item data retrieval, type switching behavior, and flashlight integration.


# ============================================================================
# Active Item Type Enum Tests
# ============================================================================


func test_active_item_type_none_value() -> void:
	# ActiveItemType.NONE should be 0
	var expected := 0
	assert_eq(expected, 0, "NONE should be the first active item type (0)")


func test_active_item_type_flashlight_value() -> void:
	# ActiveItemType.FLASHLIGHT should be 1
	var expected := 1
	assert_eq(expected, 1, "FLASHLIGHT should be the second active item type (1)")


func test_active_item_type_homing_bullets_value() -> void:
	# ActiveItemType.HOMING_BULLETS should be 2
	var expected := 2
	assert_eq(expected, 2, "HOMING_BULLETS should be the third active item type (2)")


# ============================================================================
# Active Item Data Constants Tests
# ============================================================================


func test_active_item_data_has_none() -> void:
	var item_data := {
		0: {
			"name": "None",
			"icon_path": "",
			"description": "No active item equipped."
		}
	}
	assert_true(item_data.has(0), "ACTIVE_ITEM_DATA should contain NONE type")


func test_active_item_data_has_flashlight() -> void:
	var item_data := {
		1: {
			"name": "Flashlight",
			"icon_path": "res://assets/sprites/weapons/flashlight_icon.png",
			"description": "Tactical flashlight — hold Space to illuminate in weapon direction and blind enemies caught in the beam. Bright white light, turns off when released."
		}
	}
	assert_true(item_data.has(1), "ACTIVE_ITEM_DATA should contain FLASHLIGHT type")


func test_active_item_data_has_homing_bullets() -> void:
	var item_data := {
		2: {
			"name": "Homing Bullets",
			"icon_path": "res://assets/sprites/weapons/homing_bullets_icon.png",
			"description": "Press Space to activate — bullets steer toward the nearest enemy (up to 110° turn). 6 charges per battle, each lasts 1 second."
		}
	}
	assert_true(item_data.has(2), "ACTIVE_ITEM_DATA should contain HOMING_BULLETS type")


func test_none_data_has_name() -> void:
	var data := {"name": "None"}
	assert_eq(data["name"], "None", "None should have correct name")


func test_flashlight_data_has_name() -> void:
	var data := {"name": "Flashlight"}
	assert_eq(data["name"], "Flashlight", "Flashlight should have correct name")


func test_flashlight_data_has_icon_path() -> void:
	var data := {"icon_path": "res://assets/sprites/weapons/flashlight_icon.png"}
	assert_eq(data["icon_path"], "res://assets/sprites/weapons/flashlight_icon.png",
		"Flashlight should have correct icon path")


func test_flashlight_data_has_description() -> void:
	var data := {"description": "Tactical flashlight — hold Space to illuminate in weapon direction and blind enemies caught in the beam. Bright white light, turns off when released."}
	assert_true(data["description"].contains("Space"),
		"Flashlight description should mention Space key")


func test_flashlight_data_mentions_blinding_enemies() -> void:
	var data := {"description": "Tactical flashlight — hold Space to illuminate in weapon direction and blind enemies caught in the beam. Bright white light, turns off when released."}
	assert_true(data["description"].to_lower().contains("blind enemies"),
		"Flashlight description should mention blinding enemies")


func test_homing_bullets_data_has_name() -> void:
	var data := {"name": "Homing Bullets"}
	assert_eq(data["name"], "Homing Bullets", "Homing Bullets should have correct name")


func test_homing_bullets_data_has_description() -> void:
	var data := {"description": "Press Space to activate — bullets steer toward the nearest enemy (up to 110° turn). 6 charges per battle, each lasts 1 second."}
	assert_true(data["description"].contains("Space"),
		"Homing bullets description should mention Space key")
	assert_true(data["description"].contains("110"),
		"Homing bullets description should mention 110 degree turn")
	assert_true(data["description"].contains("6 charges"),
		"Homing bullets description should mention 6 charges")


# ============================================================================
# Mock ActiveItemManager for Logic Tests
# ============================================================================


class MockActiveItemManager:
	## Active item types
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

	## Currently selected active item type
	var current_active_item: int = ActiveItemType.NONE

	## Active item type data
	const ACTIVE_ITEM_DATA: Dictionary = {
		0: {
			"name": "None",
			"icon_path": "",
			"description": "No active item equipped."
		},
		1: {
			"name": "Flashlight",
			"icon_path": "res://assets/sprites/weapons/flashlight_icon.png",
			"description": "Tactical flashlight — hold Space to illuminate in weapon direction and blind enemies caught in the beam. Bright white light, turns off when released."
		},
		2: {
			"name": "Homing Bullets",
			"icon_path": "res://assets/sprites/weapons/homing_bullets_icon.png",
			"description": "Press Space to activate — bullets steer toward the nearest enemy (up to 110° turn). 6 charges per battle, each lasts 1 second."
		},
		3: {
			"name": "Teleport Bracers",
			"icon_path": "res://assets/sprites/weapons/teleport_bracers_icon.png",
			"description": "Teleportation bracers — hold Space to aim, release to teleport. 6 charges, no cooldown. Reticle skips through walls."
		},
		4: {
			"name": "BFF Pendant",
			"icon_path": "res://assets/sprites/weapons/bff_pendant_icon.png",
			"description": "BFF pendant — press Space to summon a friendly companion armed with M16 (2-4 HP). One charge per battle."
		},
		5: {
			"name": "Invisibility",
			"icon_path": "res://assets/sprites/weapons/invisibility_suit_icon.png",
			"description": "Invisibility suit — press Space to cloak (Predator-style ripple). Enemies cannot see you for 4 seconds. 2 charges per battle."
		},
		6: {
			"name": "Breaker Bullets",
			"icon_path": "res://assets/sprites/weapons/breaker_bullets_icon.png",
			"description": "Breaker bullets — passive: bullets explode 60px before hitting a wall, dealing 1 damage in a 15px radius and releasing shrapnel in a forward cone."
		},
		7: {
			"name": "Force Field",
			"icon_path": "res://assets/sprites/weapons/force_field_icon.png",
			"description": "Force field — hold Space to activate glowing shield. 100% projectile reflection, grenades bounce without detonating. 8 second depletable charge."
		},
		8: {
			"name": "Trajectory Glasses",
			"icon_path": "res://assets/sprites/weapons/trajectory_glasses_icon.png",
			"description": "Trajectory glasses — press Space to see ricochet trajectories for 10 seconds. Green laser shows valid ricochets, red shows impossible angles. 2 charges per battle. Passive: ricochet chance is increased by 30% at angles where ricochet is possible (green ray)."
		},
		9: {
			"name": "Laser Sight",
			"icon_path": "res://assets/sprites/weapons/laser_sight_icon.png",
			"description": "Laser sight — passive: adds a purple laser sight to all weapons regardless of difficulty."
		},
		10: {
			"name": "Extended Magazine",
			"icon_path": "res://assets/sprites/weapons/extended_magazine_icon.png",
			"description": "Extended magazine — passive: increases magazine size by 2.5x (including revolver cylinder), but reduces total ammo by 5%."
		},
		11: {
			"name": "Loudspeaker",
			"icon_path": "res://assets/sprites/weapons/loudspeaker_icon.png",
			"description": "???"
		},
		12: {
			"name": "Breaching Charges",
			"icon_path": "res://assets/sprites/weapons/breaching_charges_icon.png",
			"description": "Breaching charges — place on a wall to create a passage."
		},
		13: {
			"name": "Armored Skin",
			"icon_path": "res://assets/sprites/weapons/armored_skin_icon.png",
			"description": "Armored Skin — passive: +1 HP. When at 2 HP or less and hit, 20 glass shards explode outward in all directions."
		},
		14: {
			"name": "Auto-Reload",
			"icon_path": "res://assets/sprites/weapons/auto_reload_icon.png",
			"description": "Auto-reload — passive: magazine capacity is reduced 2.1x, but the magazine is fully restocked from reserves on each kill."
		},
		15: {
			"name": "Drilling Bullets",
			"icon_path": "res://assets/sprites/weapons/drilling_bullets_icon.png",
			"description": "Drilling bullets — press Space to apply wall-piercing effect to the current magazine. Bullets ignore walls (full damage through walls, no ricochet). One charge per battle."
		},
		16: {
			"name": "Recoil Compensator",
			"icon_path": "res://assets/sprites/weapons/recoil_compensator_icon.png",
			"description": "Recoil compensator — hold Space to eliminate recoil and spread completely, and increase fire rate by 10%. 15 second depletable charge, unlimited activations while charge lasts.",
			"activation_hint": "Hold Space to activate"
		},
		17: {
			"name": "Combat Disposition",
			"icon_path": "res://assets/sprites/weapons/combat_disposition_icon.png",
			"description": "Combat Disposition — passive: +0.7 damage and +1 fire rate on start. Taking damage reduces damage by 3.0 and fire rate by 3.6."
		},
		18: {
			"name": "Experimental Sample",
			"icon_path": "res://assets/sprites/weapons/experimental_sample_icon.png",
			"description": "Experimental Sample — press Space to trigger a random active item effect (including items not yet unlocked). 1–5 charges per battle, randomised on level start.",
			"activation_hint": "Press Space to trigger random effect"
		},
		19: {
			"name": "Fine Motor Skills",
			"icon_path": "res://assets/sprites/weapons/fine_motor_skills_icon.png",
			"description": "Fine Motor Skills — press Space to instantly reload weapon and bring it to combat-ready state. Works with all weapons including revolver, shotgun, and sniper rifle. Unlimited charges, no cooldown.",
			"activation_hint": "Press Space to reload"
		},
		20: {
			"name": "Dash",
			"icon_path": "res://assets/sprites/weapons/dash_icon.png",
			"description": "Dash — press Space to dash in movement direction with damage immunity. 3 charges, cooldown after 3rd dash.",
			"activation_hint": "Press Space to dash"
		},
		21: {
			"name": "Grenade Bag",
			"icon_path": "res://assets/sprites/weapons/grenade_bag_icon.png",
			"description": "Grenade Bag — passive: increases starting grenade count based on selected type: 12 flash/stun grenades, 6 frag grenades, 2 gas or F-1 grenades."
		}
	}

	## Unlocked active items tracking
	var unlocked_active_items: Dictionary = {
		0: true,   # NONE
		1: false,  # FLASHLIGHT
		2: false,  # HOMING_BULLETS
		3: false,  # TELEPORT_BRACERS
		4: false,  # BFF_PENDANT
		5: false,  # INVISIBILITY_SUIT
		6: false,  # BREAKER_BULLETS
		7: false,  # FORCE_FIELD
		8: false,  # TRAJECTORY_GLASSES
		9: false,  # LASER_SIGHT
		10: false, # EXTENDED_MAGAZINE
		11: true,  # LOUDSPEAKER — no unlock condition, freely available from start (Issue #1691)
		12: false, # BREACHING_CHARGES
		13: false, # ARMORED_SKIN
		14: false, # AUTO_RELOAD
		15: false, # DRILLING_BULLETS
		16: false, # RECOIL_COMPENSATOR
		17: false, # COMBAT_DISPOSITION
		18: false, # EXPERIMENTAL_SAMPLE
		19: false, # FINE_MOTOR_SKILLS
		20: false, # DASH
		21: false  # GRENADE_BAG
	}

	## Check if an active item type is unlocked (Issue #1691)
	func is_active_item_unlocked(item_type: int) -> bool:
		return unlocked_active_items.get(item_type, false)

	## Signal tracking
	var type_changed_count: int = 0
	var last_restart_called: bool = false

	## Set the current active item type
	func set_active_item(type: int, restart_level: bool = true) -> void:
		if type == current_active_item:
			return

		if type not in ACTIVE_ITEM_DATA:
			return

		current_active_item = type
		type_changed_count += 1

		if restart_level:
			last_restart_called = true

	## Get active item data for a specific type
	func get_active_item_data(type: int) -> Dictionary:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]
		return {}

	## Get all available active item types
	func get_all_active_item_types() -> Array:
		return ACTIVE_ITEM_DATA.keys()

	## Get the name of an active item type
	func get_active_item_name(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["name"]
		return "Unknown"

	## Get the description of an active item type
	func get_active_item_description(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["description"]
		return ""

	## Get the icon path of an active item type
	func get_active_item_icon_path(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["icon_path"]
		return ""

	## Check if an active item type is the currently selected type
	func is_selected(type: int) -> bool:
		return type == current_active_item

	## Check if a flashlight is currently equipped
	func has_flashlight() -> bool:
		return current_active_item == ActiveItemType.FLASHLIGHT

	## Check if homing bullets are currently equipped
	func has_homing_bullets() -> bool:
		return current_active_item == ActiveItemType.HOMING_BULLETS

	## Check if teleport bracers are currently equipped
	func has_teleport_bracers() -> bool:
		return current_active_item == ActiveItemType.TELEPORT_BRACERS

	## Check if BFF pendant is currently equipped
	func has_bff_pendant() -> bool:
		return current_active_item == ActiveItemType.BFF_PENDANT

	## Check if invisibility suit is currently equipped
	func has_invisibility_suit() -> bool:
		return current_active_item == ActiveItemType.INVISIBILITY_SUIT

	## Check if breaker bullets are currently equipped
	func has_breaker_bullets() -> bool:
		return current_active_item == ActiveItemType.BREAKER_BULLETS

	## Check if force field is currently equipped
	func has_force_field() -> bool:
		return current_active_item == ActiveItemType.FORCE_FIELD

	## Check if trajectory glasses are currently equipped
	func has_trajectory_glasses() -> bool:
		return current_active_item == ActiveItemType.TRAJECTORY_GLASSES

	## Check if laser sight is currently equipped
	func has_laser_sight() -> bool:
		return current_active_item == ActiveItemType.LASER_SIGHT

	## Check if armored skin is currently equipped (Issue #1045)
	func has_armored_skin() -> bool:
		return current_active_item == ActiveItemType.ARMORED_SKIN

	## Check if auto-reload is currently equipped (Issue #1067)
	func has_auto_reload() -> bool:
		return current_active_item == ActiveItemType.AUTO_RELOAD

	## Check if drilling bullets are currently equipped (Issue #751)
	func has_drilling_bullets() -> bool:
		return current_active_item == ActiveItemType.DRILLING_BULLETS

	## Check if recoil compensator is currently equipped
	func has_recoil_compensator() -> bool:
		return current_active_item == ActiveItemType.RECOIL_COMPENSATOR

	## Check if combat disposition is currently equipped
	func has_combat_disposition() -> bool:
		return current_active_item == ActiveItemType.COMBAT_DISPOSITION


var manager: MockActiveItemManager


func before_each() -> void:
	manager = MockActiveItemManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Default State Tests
# ============================================================================


func test_default_active_item_is_none() -> void:
	assert_eq(manager.current_active_item, 0,
		"Default active item should be NONE (0)")


func test_none_is_selected_by_default() -> void:
	assert_true(manager.is_selected(0),
		"None should be selected by default")


func test_flashlight_is_not_selected_by_default() -> void:
	assert_false(manager.is_selected(1),
		"Flashlight should not be selected by default")


func test_no_flashlight_by_default() -> void:
	assert_false(manager.has_flashlight(),
		"Flashlight should not be equipped by default")


# ============================================================================
# Type Selection Tests
# ============================================================================


func test_set_active_item_to_flashlight() -> void:
	manager.set_active_item(1)
	assert_eq(manager.current_active_item, 1,
		"Active item type should change to FLASHLIGHT")


func test_set_active_item_emits_change() -> void:
	manager.set_active_item(1)
	assert_eq(manager.type_changed_count, 1,
		"Type change should increment counter")


func test_set_same_active_item_does_not_emit_change() -> void:
	manager.set_active_item(0)  # Already NONE
	assert_eq(manager.type_changed_count, 0,
		"Setting same type should not emit change")


func test_set_active_item_triggers_restart_by_default() -> void:
	manager.set_active_item(1)
	assert_true(manager.last_restart_called,
		"Level restart should be triggered by default")


func test_set_active_item_without_restart() -> void:
	manager.set_active_item(1, false)
	assert_false(manager.last_restart_called,
		"Level restart should not be triggered when disabled")


func test_set_invalid_active_item_does_nothing() -> void:
	manager.set_active_item(999)
	assert_eq(manager.current_active_item, 0,
		"Invalid type should not change current type")
	assert_eq(manager.type_changed_count, 0,
		"Invalid type should not emit change")


func test_has_flashlight_after_selection() -> void:
	manager.set_active_item(1)
	assert_true(manager.has_flashlight(),
		"has_flashlight should return true after selecting flashlight")


func test_no_flashlight_after_deselection() -> void:
	manager.set_active_item(1)
	manager.set_active_item(0)
	assert_false(manager.has_flashlight(),
		"has_flashlight should return false after switching back to none")


func test_set_active_item_to_homing_bullets() -> void:
	manager.set_active_item(2)
	assert_eq(manager.current_active_item, 2,
		"Active item type should change to HOMING_BULLETS")


func test_has_homing_bullets_after_selection() -> void:
	manager.set_active_item(2)
	assert_true(manager.has_homing_bullets(),
		"has_homing_bullets should return true after selecting homing bullets")


func test_no_homing_bullets_by_default() -> void:
	assert_false(manager.has_homing_bullets(),
		"has_homing_bullets should return false by default")


func test_no_homing_bullets_after_deselection() -> void:
	manager.set_active_item(2)
	manager.set_active_item(0)
	assert_false(manager.has_homing_bullets(),
		"has_homing_bullets should return false after switching back to none")


func test_flashlight_and_homing_mutually_exclusive() -> void:
	manager.set_active_item(1)
	assert_true(manager.has_flashlight(), "Should have flashlight")
	assert_false(manager.has_homing_bullets(), "Should NOT have homing bullets")

	manager.set_active_item(2)
	assert_false(manager.has_flashlight(), "Should NOT have flashlight after switching")
	assert_true(manager.has_homing_bullets(), "Should have homing bullets")


# ============================================================================
# Data Retrieval Tests
# ============================================================================


func test_get_active_item_data_none() -> void:
	var data := manager.get_active_item_data(0)
	assert_eq(data["name"], "None")


func test_get_active_item_data_flashlight() -> void:
	var data := manager.get_active_item_data(1)
	assert_eq(data["name"], "Flashlight")


func test_get_active_item_data_invalid_returns_empty() -> void:
	var data := manager.get_active_item_data(999)
	assert_true(data.is_empty(),
		"Invalid type should return empty dictionary")


func test_get_all_active_item_types() -> void:
	var types := manager.get_all_active_item_types()
	assert_eq(types.size(), 22,
		"Should return 22 active item types (NONE + 21 items including Extended Magazine, Drilling Bullets, Recoil Compensator, Combat Disposition, Experimental Sample, Fine Motor Skills, Dash, and Grenade Bag)")
	assert_true(0 in types)
	assert_true(1 in types)
	assert_true(2 in types)
	assert_true(3 in types)
	assert_true(4 in types)
	assert_true(5 in types)
	assert_true(6 in types)
	assert_true(7 in types)
	assert_true(8 in types)
	assert_true(9 in types)
	assert_true(10 in types)  # EXTENDED_MAGAZINE (Issue #1065)
	assert_true(11 in types)  # LOUDSPEAKER (Issue #959)
	assert_true(12 in types)  # BREACHING_CHARGES (Issue #1043)
	assert_true(13 in types)  # ARMORED_SKIN (Issue #1045)
	assert_true(14 in types)  # AUTO_RELOAD (Issue #1067)
	assert_true(15 in types)  # DRILLING_BULLETS (Issue #751)
	assert_true(16 in types)  # RECOIL_COMPENSATOR (Issue #1073)
	assert_true(17 in types)  # COMBAT_DISPOSITION (Issue #1047)
	assert_true(18 in types)  # EXPERIMENTAL_SAMPLE (Issue #1127)
	assert_true(19 in types)  # FINE_MOTOR_SKILLS (Issue #1315)
	assert_true(20 in types)  # DASH (Issue #1071)
	assert_true(21 in types)  # GRENADE_BAG (Issue #1590)


func test_get_active_item_name_none() -> void:
	assert_eq(manager.get_active_item_name(0), "None")


func test_get_active_item_name_flashlight() -> void:
	assert_eq(manager.get_active_item_name(1), "Flashlight")


func test_get_active_item_name_homing_bullets() -> void:
	assert_eq(manager.get_active_item_name(2), "Homing Bullets")


func test_get_active_item_name_invalid() -> void:
	assert_eq(manager.get_active_item_name(999), "Unknown")


func test_get_active_item_description_flashlight() -> void:
	var desc := manager.get_active_item_description(1)
	assert_true(desc.contains("Space"),
		"Flashlight description should mention Space key")


func test_get_active_item_description_none() -> void:
	var desc := manager.get_active_item_description(0)
	assert_true(desc.contains("No active item"),
		"None description should indicate no active item")


func test_get_active_item_description_homing_bullets() -> void:
	var desc := manager.get_active_item_description(2)
	assert_true(desc.contains("Space"),
		"Homing bullets description should mention Space key")


func test_get_active_item_description_invalid() -> void:
	assert_eq(manager.get_active_item_description(999), "")


func test_loudspeaker_description_is_mystery() -> void:
	# Issue #1691: Loudspeaker description should be ??? (mystery)
	var desc := manager.get_active_item_description(11)
	assert_eq(desc, "???",
		"Loudspeaker description should be '???' (Issue #1691)")


func test_loudspeaker_is_unlocked_from_start() -> void:
	# Issue #1691: Loudspeaker should be unlocked (open) from the start
	assert_true(manager.is_active_item_unlocked(11),
		"Loudspeaker should be unlocked from the start (Issue #1691)")


func test_loudspeaker_is_not_default_selected() -> void:
	# Issue #1691: Loudspeaker should be open but not taken (not selected by default)
	assert_false(manager.is_selected(11),
		"Loudspeaker should not be selected by default (Issue #1691)")


func test_get_active_item_icon_path_flashlight() -> void:
	var path := manager.get_active_item_icon_path(1)
	assert_true(path.contains("flashlight"),
		"Flashlight icon path should contain 'flashlight'")


func test_get_active_item_icon_path_none() -> void:
	var path := manager.get_active_item_icon_path(0)
	assert_eq(path, "",
		"None icon path should be empty")


func test_get_active_item_icon_path_invalid() -> void:
	assert_eq(manager.get_active_item_icon_path(999), "")


# ============================================================================
# Selection State Tests
# ============================================================================


func test_is_selected_after_changing_type() -> void:
	manager.set_active_item(1)
	assert_true(manager.is_selected(1),
		"FLASHLIGHT should be selected after changing to it")
	assert_false(manager.is_selected(0),
		"NONE should not be selected after changing away from it")


func test_multiple_type_changes() -> void:
	manager.set_active_item(1)
	manager.set_active_item(0)
	manager.set_active_item(1)

	assert_eq(manager.current_active_item, 1)
	assert_eq(manager.type_changed_count, 3)


# ============================================================================
# Flashlight Effect Tests
# ============================================================================


class MockFlashlightEffect:
	## Whether the flashlight is on.
	var _is_on: bool = false
	## Count of sound plays for testing.
	var sound_play_count: int = 0

	func turn_on() -> void:
		if _is_on:
			return
		_is_on = true
		sound_play_count += 1

	func turn_off() -> void:
		if not _is_on:
			return
		_is_on = false
		sound_play_count += 1

	func is_on() -> bool:
		return _is_on


func test_flashlight_effect_starts_off() -> void:
	var effect := MockFlashlightEffect.new()
	assert_false(effect.is_on(),
		"Flashlight should start turned off")


func test_flashlight_effect_turn_on() -> void:
	var effect := MockFlashlightEffect.new()
	effect.turn_on()
	assert_true(effect.is_on(),
		"Flashlight should be on after turn_on()")


func test_flashlight_effect_turn_off() -> void:
	var effect := MockFlashlightEffect.new()
	effect.turn_on()
	effect.turn_off()
	assert_false(effect.is_on(),
		"Flashlight should be off after turn_off()")


func test_flashlight_effect_toggle_sequence() -> void:
	var effect := MockFlashlightEffect.new()
	assert_false(effect.is_on(), "Should start off")

	effect.turn_on()
	assert_true(effect.is_on(), "Should be on after first turn_on")

	effect.turn_off()
	assert_false(effect.is_on(), "Should be off after turn_off")

	effect.turn_on()
	assert_true(effect.is_on(), "Should be on again after second turn_on")


func test_flashlight_double_turn_on() -> void:
	var effect := MockFlashlightEffect.new()
	effect.turn_on()
	effect.turn_on()  # Idempotent
	assert_true(effect.is_on(),
		"Double turn_on should keep flashlight on")


func test_flashlight_double_turn_off() -> void:
	var effect := MockFlashlightEffect.new()
	effect.turn_off()
	effect.turn_off()  # Idempotent
	assert_false(effect.is_on(),
		"Double turn_off should keep flashlight off")


func test_flashlight_sound_plays_on_toggle() -> void:
	var effect := MockFlashlightEffect.new()
	assert_eq(effect.sound_play_count, 0, "No sounds initially")

	effect.turn_on()
	assert_eq(effect.sound_play_count, 1, "Sound should play on turn_on")

	effect.turn_off()
	assert_eq(effect.sound_play_count, 2, "Sound should play on turn_off")


func test_flashlight_no_sound_on_idempotent_calls() -> void:
	var effect := MockFlashlightEffect.new()
	effect.turn_on()
	effect.turn_on()  # Already on, should not play sound
	assert_eq(effect.sound_play_count, 1,
		"Idempotent turn_on should not play extra sound")

	effect.turn_off()
	effect.turn_off()  # Already off, should not play sound
	assert_eq(effect.sound_play_count, 2,
		"Idempotent turn_off should not play extra sound")


# ============================================================================
# Armory Integration Tests (Active Items in Menu)
# ============================================================================


class MockArmoryWithActiveItems:
	## Active item data
	const ACTIVE_ITEMS: Dictionary = {
		0: {"name": "None", "description": "No active item equipped."},
		1: {"name": "Flashlight", "description": "Tactical flashlight"},
		2: {"name": "Homing Bullets", "description": "Homing bullets active item"},
		3: {"name": "Teleport Bracers", "description": "Teleportation bracers"},
		4: {"name": "BFF Pendant", "description": "BFF pendant — summon companion"},
		5: {"name": "Invisibility", "description": "Invisibility suit"},
		6: {"name": "Breaker Bullets", "description": "Breaker bullets — passive"},
		7: {"name": "Force Field", "description": "Force field — hold Space to activate"},
		8: {"name": "Trajectory Glasses", "description": "Trajectory glasses — ricochet visualization"},
		9: {"name": "Laser Sight", "description": "Laser sight — passive"},
		10: {"name": "Extended Magazine", "description": "Extended magazine — passive: 2.5x magazine size"},
		11: {"name": "Loudspeaker", "description": "???"},
		12: {"name": "Breaching Charges", "description": "Breaching charges — place on wall to create a passage"},
		13: {"name": "Armored Skin", "description": "Armored Skin — passive: +1 HP. When at 2 HP or less and hit, 20 glass shards explode outward."},
		14: {"name": "Auto-Reload", "description": "Auto-reload — passive: magazine reduced 2.1x, refilled on kill"},
		15: {"name": "Drilling Bullets", "description": "Drilling bullets — press Space to apply wall-piercing effect to the current magazine."},
		16: {"name": "Recoil Compensator", "description": "Recoil compensator — hold Space to eliminate recoil and spread completely, and increase fire rate by 10%. 15 second depletable charge, unlimited activations while charge lasts."},
		17: {"name": "Combat Disposition", "description": "Combat Disposition — passive: +0.7 damage and +1 fire rate on start. Taking damage reduces bonuses."}
	}

	## Applied active item type
	var applied_active_item: int = 0

	## Pending active item type
	var pending_active_item: int = 0

	## Tracking
	var active_item_changed_count: int = 0
	var apply_count: int = 0

	## Select an active item (sets pending, does NOT apply immediately)
	func select_active_item(item_type: int) -> bool:
		if item_type not in ACTIVE_ITEMS:
			return false
		pending_active_item = item_type
		return true

	## Check for pending changes
	func has_pending_changes() -> bool:
		return pending_active_item != applied_active_item

	## Apply pending changes
	func apply() -> bool:
		if not has_pending_changes():
			return false
		if pending_active_item != applied_active_item:
			active_item_changed_count += 1
		applied_active_item = pending_active_item
		apply_count += 1
		return true


func test_armory_active_item_default_is_none() -> void:
	var armory := MockArmoryWithActiveItems.new()
	assert_eq(armory.applied_active_item, 0,
		"Default active item should be None")


func test_armory_select_active_item_sets_pending() -> void:
	var armory := MockArmoryWithActiveItems.new()
	var result := armory.select_active_item(1)
	assert_true(result, "Should select flashlight")
	assert_eq(armory.pending_active_item, 1, "Pending should be flashlight")
	assert_eq(armory.applied_active_item, 0, "Applied should still be None")


func test_armory_select_invalid_active_item() -> void:
	var armory := MockArmoryWithActiveItems.new()
	var result := armory.select_active_item(99)
	assert_false(result, "Should not select invalid active item")
	assert_eq(armory.pending_active_item, 0, "Pending should remain None")


func test_armory_apply_active_item_change() -> void:
	var armory := MockArmoryWithActiveItems.new()
	armory.select_active_item(1)
	var result := armory.apply()
	assert_true(result, "Apply should succeed")
	assert_eq(armory.applied_active_item, 1, "Applied should be flashlight")
	assert_eq(armory.active_item_changed_count, 1, "Change count should be 1")


func test_armory_no_pending_changes_when_same() -> void:
	var armory := MockArmoryWithActiveItems.new()
	armory.select_active_item(0)  # Same as default
	assert_false(armory.has_pending_changes(),
		"No pending changes when selecting same item")


func test_armory_switch_active_items() -> void:
	var armory := MockArmoryWithActiveItems.new()
	armory.select_active_item(1)
	armory.select_active_item(0)
	assert_eq(armory.pending_active_item, 0,
		"Latest pending should be None")
	assert_false(armory.has_pending_changes(),
		"Should have no pending changes after switching back")


# ============================================================================
# Breaker Bullets Tests (Issue #678)
# ============================================================================


func test_active_item_type_breaker_bullets_value() -> void:
	# ActiveItemType.BREAKER_BULLETS should be 6
	var expected := 6
	assert_eq(expected, 6, "BREAKER_BULLETS should be the seventh active item type (6)")


func test_active_item_data_has_breaker_bullets() -> void:
	var data := manager.get_active_item_data(6)
	assert_false(data.is_empty(), "ACTIVE_ITEM_DATA should contain BREAKER_BULLETS type")
	assert_eq(data["name"], "Breaker Bullets", "Breaker Bullets should have correct name")


func test_breaker_bullets_data_has_icon_path() -> void:
	var data := manager.get_active_item_data(6)
	assert_true(data["icon_path"].contains("breaker_bullets"),
		"Breaker Bullets icon path should contain 'breaker_bullets'")


func test_breaker_bullets_data_has_description() -> void:
	var data := manager.get_active_item_data(6)
	assert_true(data["description"].contains("passive"),
		"Breaker Bullets description should mention passive behavior")


func test_no_breaker_bullets_by_default() -> void:
	assert_false(manager.has_breaker_bullets(),
		"Breaker bullets should not be equipped by default")


func test_has_breaker_bullets_after_selection() -> void:
	manager.set_active_item(6)
	assert_true(manager.has_breaker_bullets(),
		"has_breaker_bullets should return true after selecting breaker bullets")


func test_no_breaker_bullets_after_deselection() -> void:
	manager.set_active_item(6)
	manager.set_active_item(0)
	assert_false(manager.has_breaker_bullets(),
		"has_breaker_bullets should return false after switching back to none")


func test_breaker_bullets_does_not_conflict_with_flashlight() -> void:
	manager.set_active_item(6)
	assert_false(manager.has_flashlight(),
		"Flashlight should not be active when breaker bullets are selected")
	assert_true(manager.has_breaker_bullets(),
		"Breaker bullets should be active")


func test_flashlight_does_not_conflict_with_breaker_bullets() -> void:
	manager.set_active_item(1)
	assert_true(manager.has_flashlight(),
		"Flashlight should be active")
	assert_false(manager.has_breaker_bullets(),
		"Breaker bullets should not be active when flashlight is selected")


func test_set_active_item_to_breaker_bullets() -> void:
	manager.set_active_item(6)
	assert_eq(manager.current_active_item, 6,
		"Active item type should change to BREAKER_BULLETS")


func test_armory_select_breaker_bullets() -> void:
	var armory := MockArmoryWithActiveItems.new()
	var result := armory.select_active_item(6)
	assert_true(result, "Should select breaker bullets")
	assert_eq(armory.pending_active_item, 6, "Pending should be breaker bullets")


# ============================================================================
# Force Field Tests (Issue #676)
# ============================================================================


func test_active_item_type_force_field_value() -> void:
	# ActiveItemType.FORCE_FIELD should be 7 (shifted by 1 due to BFF_PENDANT at 4)
	var expected := 7
	assert_eq(expected, 7, "FORCE_FIELD should be the eighth active item type (7)")


func test_active_item_data_has_force_field() -> void:
	var data := manager.get_active_item_data(7)
	assert_false(data.is_empty(), "ACTIVE_ITEM_DATA should contain FORCE_FIELD type")
	assert_eq(data["name"], "Force Field", "Force Field should have correct name")


func test_force_field_data_has_icon_path() -> void:
	var data := manager.get_active_item_data(7)
	assert_true(data["icon_path"].contains("force_field"),
		"Force Field icon path should contain 'force_field'")


func test_force_field_data_has_description() -> void:
	var data := manager.get_active_item_data(7)
	assert_true(data["description"].contains("Space"),
		"Force Field description should mention Space key")
	assert_true(data["description"].contains("100%"),
		"Force Field description should mention 100% reflection")


func test_no_force_field_by_default() -> void:
	assert_false(manager.has_force_field(),
		"Force field should not be equipped by default")


func test_has_force_field_after_selection() -> void:
	manager.set_active_item(7)
	assert_true(manager.has_force_field(),
		"has_force_field should return true after selecting force field")


func test_no_force_field_after_deselection() -> void:
	manager.set_active_item(7)
	manager.set_active_item(0)
	assert_false(manager.has_force_field(),
		"has_force_field should return false after switching back to none")


func test_force_field_does_not_conflict_with_flashlight() -> void:
	manager.set_active_item(7)
	assert_false(manager.has_flashlight(),
		"Flashlight should not be active when force field is selected")
	assert_true(manager.has_force_field(),
		"Force field should be active")


func test_flashlight_does_not_conflict_with_force_field() -> void:
	manager.set_active_item(1)
	assert_true(manager.has_flashlight(),
		"Flashlight should be active")
	assert_false(manager.has_force_field(),
		"Force field should not be active when flashlight is selected")


func test_set_active_item_to_force_field() -> void:
	manager.set_active_item(7)
	assert_eq(manager.current_active_item, 7,
		"Active item type should change to FORCE_FIELD")


func test_armory_select_force_field() -> void:
	var armory := MockArmoryWithActiveItems.new()
	var result := armory.select_active_item(7)
	assert_true(result, "Should select force field")
	assert_eq(armory.pending_active_item, 7, "Pending should be force field")


# ============================================================================
# Trajectory Glasses Tests (Issue #744)
# ============================================================================


func test_active_item_type_trajectory_glasses_value() -> void:
	# ActiveItemType.TRAJECTORY_GLASSES should be 8 (shifted by 1 due to BFF_PENDANT at 4)
	var expected := 8
	assert_eq(expected, 8, "TRAJECTORY_GLASSES should be the ninth active item type (8)")


func test_active_item_data_has_trajectory_glasses() -> void:
	var data := manager.get_active_item_data(8)
	assert_false(data.is_empty(), "ACTIVE_ITEM_DATA should contain TRAJECTORY_GLASSES type")
	assert_eq(data["name"], "Trajectory Glasses", "Trajectory Glasses should have correct name")


func test_trajectory_glasses_data_has_icon_path() -> void:
	var data := manager.get_active_item_data(8)
	assert_true(data["icon_path"].contains("trajectory_glasses"),
		"Trajectory Glasses icon path should contain 'trajectory_glasses'")


func test_trajectory_glasses_data_has_description() -> void:
	var data := manager.get_active_item_data(8)
	assert_true(data["description"].contains("ricochet"),
		"Trajectory Glasses description should mention ricochet")
	assert_true(data["description"].contains("10 seconds"),
		"Trajectory Glasses description should mention 10 seconds duration")
	assert_true(data["description"].contains("2 charges"),
		"Trajectory Glasses description should mention 2 charges")
	assert_true(data["description"].contains("30%"),
		"Trajectory Glasses description should mention 30% passive ricochet boost (Issue #1028)")
	assert_true(data["description"].contains("passive"),
		"Trajectory Glasses description should mention passive behavior (Issue #1028)")


func test_no_trajectory_glasses_by_default() -> void:
	assert_false(manager.has_trajectory_glasses(),
		"Trajectory glasses should not be equipped by default")


func test_has_trajectory_glasses_after_selection() -> void:
	manager.set_active_item(8)
	assert_true(manager.has_trajectory_glasses(),
		"has_trajectory_glasses should return true after selecting trajectory glasses")


func test_no_trajectory_glasses_after_deselection() -> void:
	manager.set_active_item(8)
	manager.set_active_item(0)
	assert_false(manager.has_trajectory_glasses(),
		"has_trajectory_glasses should return false after switching back to none")


func test_trajectory_glasses_does_not_conflict_with_flashlight() -> void:
	manager.set_active_item(8)
	assert_false(manager.has_flashlight(),
		"Flashlight should not be active when trajectory glasses are selected")
	assert_true(manager.has_trajectory_glasses(),
		"Trajectory glasses should be active")


func test_trajectory_glasses_does_not_conflict_with_breaker_bullets() -> void:
	manager.set_active_item(8)
	assert_false(manager.has_breaker_bullets(),
		"Breaker bullets should not be active when trajectory glasses are selected")
	assert_true(manager.has_trajectory_glasses(),
		"Trajectory glasses should be active")


func test_set_active_item_to_trajectory_glasses() -> void:
	manager.set_active_item(8)
	assert_eq(manager.current_active_item, 8,
		"Active item type should change to TRAJECTORY_GLASSES")


func test_armory_select_trajectory_glasses() -> void:
	var armory := MockArmoryWithActiveItems.new()
	var result := armory.select_active_item(8)
	assert_true(result, "Should select trajectory glasses")
	assert_eq(armory.pending_active_item, 8, "Pending should be trajectory glasses")


# ============================================================================
# Trajectory Glasses Passive Ricochet Boost Tests (Issue #1028)
# ============================================================================


func test_trajectory_glasses_data_has_no_separate_ricochet_points_item() -> void:
	# Issue #1028: RICOCHET_POINTS was a separate item that was removed.
	# Its effect is now part of Trajectory Glasses.
	# Index 10 is EXTENDED_MAGAZINE (Issue #1065). Index 11 is LOUDSPEAKER (Issue #959).
	# Index 12 is BREACHING_CHARGES (Issue #1043). Index 13 is ARMORED_SKIN (Issue #1045).
	# Index 14 is AUTO_RELOAD (Issue #1067). Index 15 is DRILLING_BULLETS (Issue #751). Index 16 is RECOIL_COMPENSATOR (Issue #1073). Index 17 is COMBAT_DISPOSITION (Issue #1047).
	var data := manager.get_active_item_data(10)
	assert_false(data.is_empty(),
		"Index 10 should be EXTENDED_MAGAZINE (Issue #1065) — RICOCHET_POINTS was removed (Issue #1028)")
	assert_eq(data.get("name", ""), "Extended Magazine",
		"Item at index 10 should be Extended Magazine (Issue #1065)")
	var armored_data := manager.get_active_item_data(13)
	assert_false(armored_data.is_empty(),
		"Index 13 is now ARMORED_SKIN (Issue #1045), not RICOCHET_POINTS")
	assert_ne(armored_data.get("name", ""), "Ricochet Points",
		"RICOCHET_POINTS should not exist — removed in Issue #1028")
	var auto_reload_data := manager.get_active_item_data(14)
	assert_false(auto_reload_data.is_empty(),
		"Index 14 should be AUTO_RELOAD (Issue #1067)")
	assert_eq(auto_reload_data.get("name", ""), "Auto-Reload",
		"Item at index 14 should be Auto-Reload (Issue #1067)")
	var drilling_data := manager.get_active_item_data(15)
	assert_false(drilling_data.is_empty(),
		"Index 15 should be Drilling Bullets (Issue #751)")
	assert_eq(drilling_data.get("name", ""), "Drilling Bullets",
		"Item at index 15 should be Drilling Bullets (Issue #751)")
	var recoil_data := manager.get_active_item_data(16)
	assert_false(recoil_data.is_empty(),
		"Index 16 should be RECOIL_COMPENSATOR (Issue #1073)")
	assert_eq(recoil_data.get("name", ""), "Recoil Compensator",
		"Item at index 16 should be Recoil Compensator (Issue #1073)")
	var combat_data := manager.get_active_item_data(17)
	assert_false(combat_data.is_empty(),
		"Index 17 should be COMBAT_DISPOSITION (Issue #1047)")
	assert_eq(combat_data.get("name", ""), "Combat Disposition",
		"Item at index 17 should be Combat Disposition (Issue #1047)")


func test_trajectory_glasses_description_mentions_passive_boost() -> void:
	# Issue #1028: Trajectory Glasses should mention the 30% passive ricochet boost.
	var data := manager.get_active_item_data(8)
	assert_true(data["description"].contains("30%"),
		"Trajectory Glasses description should mention 30% passive ricochet boost (Issue #1028)")
	assert_true(data["description"].contains("passive"),
		"Trajectory Glasses description should mention passive (Issue #1028)")


# ============================================================================
# Auto-Reload Tests (Issue #1067)
# ============================================================================


func test_active_item_type_auto_reload_value() -> void:
	# ActiveItemType.AUTO_RELOAD should be 14 (after EXTENDED_MAGAZINE=10, LOUDSPEAKER=11, BREACHING_CHARGES=12, ARMORED_SKIN=13)
	assert_eq(14, 14, "AUTO_RELOAD should be the fifteenth active item type (14)")


func test_active_item_data_has_auto_reload() -> void:
	var data := manager.get_active_item_data(14)
	assert_false(data.is_empty(), "ACTIVE_ITEM_DATA should contain AUTO_RELOAD type")
	assert_eq(data["name"], "Auto-Reload", "Auto-Reload should have correct name")


func test_auto_reload_data_has_icon_path() -> void:
	var data := manager.get_active_item_data(14)
	assert_true(data["icon_path"].contains("auto_reload"),
		"Auto-Reload icon path should contain 'auto_reload'")


func test_auto_reload_data_has_description() -> void:
	var data := manager.get_active_item_data(14)
	assert_true(data["description"].contains("passive"),
		"Auto-Reload description should mention passive behavior")
	assert_true(data["description"].contains("2.1"),
		"Auto-Reload description should mention 2.1x magazine reduction")
	assert_true(data["description"].contains("kill"),
		"Auto-Reload description should mention kill-based refill")


func test_no_auto_reload_by_default() -> void:
	assert_false(manager.has_auto_reload(),
		"Auto-reload should not be equipped by default")


func test_has_auto_reload_after_selection() -> void:
	manager.set_active_item(14)
	assert_true(manager.has_auto_reload(),
		"has_auto_reload should return true after selecting auto-reload")


func test_no_auto_reload_after_deselection() -> void:
	manager.set_active_item(14)
	manager.set_active_item(0)
	assert_false(manager.has_auto_reload(),
		"has_auto_reload should return false after switching back to none")


func test_auto_reload_does_not_conflict_with_flashlight() -> void:
	manager.set_active_item(14)
	assert_false(manager.has_flashlight(),
		"Flashlight should not be active when auto-reload is selected")
	assert_true(manager.has_auto_reload(),
		"Auto-reload should be active")


func test_auto_reload_does_not_conflict_with_breaker_bullets() -> void:
	manager.set_active_item(14)
	assert_false(manager.has_breaker_bullets(),
		"Breaker bullets should not be active when auto-reload is selected")
	assert_true(manager.has_auto_reload(),
		"Auto-reload should be active")


func test_set_active_item_to_auto_reload() -> void:
	manager.set_active_item(14)
	assert_eq(manager.current_active_item, 14,
		"Active item type should change to AUTO_RELOAD")


func test_armory_select_auto_reload() -> void:
	var armory := MockArmoryWithActiveItems.new()
	var result := armory.select_active_item(14)
	assert_true(result, "Should select auto-reload")
	assert_eq(armory.pending_active_item, 14, "Pending should be auto-reload")
