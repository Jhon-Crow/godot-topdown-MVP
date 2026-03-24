extends GutTest
## Unit tests for the Extended Magazine active item (Issue #1065).
##
## Tests the extended magazine item including:
## - Registration as active item type (value 10)
## - has_extended_magazine() detection method
## - get_magazine_size_multiplier() returns 2.5 when equipped, 1.0 otherwise
## - get_total_ammo_multiplier() returns 0.95 when equipped, 1.0 otherwise
## - Passive behavior (no activation needed)


# ============================================================================
# Mock Classes
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
		EXPERIMENTAL_SAMPLE = 18
	}

	## Currently selected active item type
	var current_active_item: int = ActiveItemType.NONE

	## Active item data
	const ACTIVE_ITEM_DATA: Dictionary = {
		0: {"name": "None", "icon_path": "", "description": "No active item equipped."},
		1: {"name": "Flashlight", "icon_path": "res://assets/sprites/weapons/flashlight_icon.png", "description": "Tactical flashlight."},
		2: {"name": "Homing Bullets", "icon_path": "res://assets/sprites/weapons/homing_bullets_icon.png", "description": "Homing bullets."},
		3: {"name": "Teleport Bracers", "icon_path": "res://assets/sprites/weapons/teleport_bracers_icon.png", "description": "Teleportation bracers."},
		4: {"name": "BFF Pendant", "icon_path": "res://assets/sprites/weapons/bff_pendant_icon.png", "description": "BFF pendant."},
		5: {"name": "Invisibility", "icon_path": "res://assets/sprites/weapons/invisibility_suit_icon.png", "description": "Invisibility suit."},
		6: {"name": "Breaker Bullets", "icon_path": "res://assets/sprites/weapons/breaker_bullets_icon.png", "description": "Breaker bullets."},
		7: {"name": "Force Field", "icon_path": "res://assets/sprites/weapons/force_field_icon.png", "description": "Force field."},
		8: {"name": "Trajectory Glasses", "icon_path": "res://assets/sprites/weapons/trajectory_glasses_icon.png", "description": "Trajectory glasses."},
		9: {"name": "Laser Sight", "icon_path": "res://assets/sprites/weapons/laser_sight_icon.png", "description": "Laser sight — passive: adds a purple laser sight to all weapons regardless of difficulty."},
		10: {"name": "Extended Magazine", "icon_path": "res://assets/sprites/weapons/extended_magazine_icon.png", "description": "Extended magazine — passive: increases magazine size by 2.5x (including revolver cylinder), but reduces total ammo by 5%."},
		11: {"name": "Loudspeaker", "icon_path": "res://assets/sprites/weapons/loudspeaker_icon.png", "description": "Loudspeaker — press Space to emit sound cone."},
		12: {"name": "Breaching Charges", "icon_path": "res://assets/sprites/weapons/breaching_charges_icon.png", "description": "Breaching charges — hold Space near a wall to place a charge."},
		13: {"name": "Armored Skin", "icon_path": "res://assets/sprites/weapons/armored_skin_icon.png", "description": "Armored Skin — passive: +1 HP."},
		14: {"name": "Auto-Reload", "icon_path": "res://assets/sprites/weapons/auto_reload_icon.png", "description": "Auto-reload — passive: magazine capacity is reduced 2.1x, but refilled on kill."},
		15: {"name": "Drilling Bullets", "icon_path": "res://assets/sprites/weapons/drilling_bullets_icon.png", "description": "Drilling bullets — press Space to apply wall-piercing effect to the current magazine."},
		16: {"name": "Recoil Compensator", "icon_path": "res://assets/sprites/weapons/recoil_compensator_icon.png", "description": "Recoil compensator — hold Space to eliminate recoil and spread completely, and increase fire rate by 10%."},
		17: {"name": "Combat Disposition", "icon_path": "res://assets/sprites/weapons/combat_disposition_icon.png", "description": "Combat Disposition — passive: +0.77 damage and +1.1 fire rate on start. Taking damage reduces bonuses."},
		18: {"name": "Experimental Sample", "icon_path": "res://assets/sprites/weapons/experimental_sample_icon.png", "description": "Experimental Sample — press Space to trigger a random active item effect.", "activation_hint": "Press Space to trigger random effect"}
	}

	## Check if extended magazine is currently equipped (Issue #1065)
	func has_extended_magazine() -> bool:
		return current_active_item == ActiveItemType.EXTENDED_MAGAZINE

	## Get the magazine size multiplier (Issue #1065)
	func get_magazine_size_multiplier() -> float:
		if current_active_item == ActiveItemType.EXTENDED_MAGAZINE:
			return 2.5
		return 1.0

	## Get the total ammo multiplier (Issue #1065)
	func get_total_ammo_multiplier() -> float:
		if current_active_item == ActiveItemType.EXTENDED_MAGAZINE:
			return 0.95
		return 1.0

	## Set the current active item type
	func set_active_item(type: int, restart_level: bool = true) -> void:
		if type not in ACTIVE_ITEM_DATA:
			return
		current_active_item = type

	## Get active item data for a specific type
	func get_active_item_data(type: int) -> Dictionary:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]
		return {}

	## Get the name of an active item type
	func get_active_item_name(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["name"]
		return "Unknown"

	## Get all available active item types
	func get_all_active_item_types() -> Array:
		return ACTIVE_ITEM_DATA.keys()

	## Check if any other item is equipped
	func has_laser_sight() -> bool:
		return current_active_item == ActiveItemType.LASER_SIGHT

	func has_breaker_bullets() -> bool:
		return current_active_item == ActiveItemType.BREAKER_BULLETS


var manager: MockActiveItemManager


func before_each() -> void:
	manager = MockActiveItemManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Extended Magazine Type Registration Tests
# ============================================================================


func test_extended_magazine_type_value_is_10() -> void:
	assert_eq(manager.ActiveItemType.EXTENDED_MAGAZINE, 10,
		"EXTENDED_MAGAZINE should have value 10 (after LASER_SIGHT which is 9)")


func test_extended_magazine_type_exists_in_data() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXTENDED_MAGAZINE)
	assert_false(data.is_empty(),
		"EXTENDED_MAGAZINE type should have data in ACTIVE_ITEM_DATA")


func test_extended_magazine_has_correct_name() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXTENDED_MAGAZINE)
	assert_eq(data.get("name", ""), "Extended Magazine",
		"Extended Magazine should have correct name")


func test_extended_magazine_has_icon_path() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var icon_path: String = data.get("icon_path", "")
	assert_false(icon_path.is_empty(),
		"Extended Magazine should have an icon path")
	assert_true(icon_path.ends_with(".png"),
		"Extended Magazine icon path should point to a PNG file")
	assert_true(icon_path.contains("extended_magazine"),
		"Extended Magazine icon path should contain 'extended_magazine'")


func test_extended_magazine_has_description() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var description: String = data.get("description", "")
	assert_false(description.is_empty(),
		"Extended Magazine should have a description")


func test_extended_magazine_description_mentions_magazine() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var description: String = data.get("description", "")
	assert_true(description.to_lower().contains("magazine"),
		"Description should mention magazine")


func test_extended_magazine_description_mentions_2_5x() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var description: String = data.get("description", "")
	assert_true(description.contains("2.5") or description.contains("2,5"),
		"Description should mention the 2.5x multiplier")


func test_extended_magazine_description_mentions_ammo_reduction() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var description: String = data.get("description", "")
	assert_true(description.contains("5%") or description.to_lower().contains("ammo"),
		"Description should mention the 5% ammo reduction or 'ammo'")


func test_extended_magazine_description_mentions_revolver() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var description: String = data.get("description", "")
	assert_true(description.to_lower().contains("revolver"),
		"Description should mention revolver (cylinder is also affected)")


func test_extended_magazine_is_passive_no_activation_hint() -> void:
	# Extended magazine is a passive item — no Space key activation needed.
	var data := manager.get_active_item_data(manager.ActiveItemType.EXTENDED_MAGAZINE)
	assert_false(data.has("activation_hint"),
		"Extended Magazine should NOT have activation_hint (it's a passive item)")


# ============================================================================
# has_extended_magazine() Method Tests
# ============================================================================


func test_has_extended_magazine_returns_false_by_default() -> void:
	assert_false(manager.has_extended_magazine(),
		"has_extended_magazine() should return false when NONE is equipped")


func test_has_extended_magazine_returns_true_when_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.EXTENDED_MAGAZINE)
	assert_true(manager.has_extended_magazine(),
		"has_extended_magazine() should return true when EXTENDED_MAGAZINE is equipped")


func test_has_extended_magazine_returns_false_when_other_item_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.FLASHLIGHT)
	assert_false(manager.has_extended_magazine(),
		"has_extended_magazine() should return false when Flashlight is equipped")


func test_has_extended_magazine_returns_false_when_laser_sight_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)
	assert_false(manager.has_extended_magazine(),
		"has_extended_magazine() should return false when Laser Sight is equipped")


func test_has_extended_magazine_returns_false_when_breaker_bullets_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.BREAKER_BULLETS)
	assert_false(manager.has_extended_magazine(),
		"has_extended_magazine() should return false when Breaker Bullets are equipped")


# ============================================================================
# get_magazine_size_multiplier() Tests
# ============================================================================


func test_magazine_size_multiplier_is_1_by_default() -> void:
	var multiplier: float = manager.get_magazine_size_multiplier()
	assert_eq(multiplier, 1.0,
		"Magazine size multiplier should be 1.0 when no item is equipped")


func test_magazine_size_multiplier_is_2_5_when_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var multiplier: float = manager.get_magazine_size_multiplier()
	assert_eq(multiplier, 2.5,
		"Magazine size multiplier should be 2.5 when Extended Magazine is equipped")


func test_magazine_size_multiplier_is_1_when_other_item_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)
	var multiplier: float = manager.get_magazine_size_multiplier()
	assert_eq(multiplier, 1.0,
		"Magazine size multiplier should be 1.0 when Laser Sight is equipped (not Extended Magazine)")


# ============================================================================
# get_total_ammo_multiplier() Tests
# ============================================================================


func test_total_ammo_multiplier_is_1_by_default() -> void:
	var multiplier: float = manager.get_total_ammo_multiplier()
	assert_eq(multiplier, 1.0,
		"Total ammo multiplier should be 1.0 when no item is equipped")


func test_total_ammo_multiplier_is_0_95_when_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var multiplier: float = manager.get_total_ammo_multiplier()
	assert_eq(multiplier, 0.95,
		"Total ammo multiplier should be 0.95 (5% reduction) when Extended Magazine is equipped")


func test_total_ammo_multiplier_is_1_when_other_item_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.BREAKER_BULLETS)
	var multiplier: float = manager.get_total_ammo_multiplier()
	assert_eq(multiplier, 1.0,
		"Total ammo multiplier should be 1.0 when Breaker Bullets are equipped")


# ============================================================================
# Magazine Size Calculation Tests
# ============================================================================


func test_magazine_size_calculation_30_bullets() -> void:
	# Standard assault rifle: 30 rounds -> 2.5x = 75 rounds
	manager.set_active_item(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var base_size := 30
	var multiplier: float = manager.get_magazine_size_multiplier()
	var new_size: int = int(round(base_size * multiplier))
	assert_eq(new_size, 75,
		"30-round magazine * 2.5 should be 75 rounds")


func test_magazine_size_calculation_revolver_5_cylinder() -> void:
	# RSh-12 revolver: 5-round cylinder -> 2.5x = 12-13 rounds (rounds to 13)
	manager.set_active_item(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var base_size := 5
	var multiplier: float = manager.get_magazine_size_multiplier()
	var new_size: int = int(round(base_size * multiplier))
	assert_eq(new_size, 13,
		"5-round revolver cylinder * 2.5 should be 13 rounds (rounded)")


func test_total_ammo_reduction_calculation_90_bullets() -> void:
	# Normal difficulty: 90 total ammo -> 0.95x = 85 (floor)
	manager.set_active_item(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var base_ammo := 90
	var multiplier: float = manager.get_total_ammo_multiplier()
	var new_ammo: int = int(base_ammo * multiplier)
	assert_eq(new_ammo, 85,
		"90 total ammo * 0.95 should be 85 (floor division)")


func test_total_ammo_reduction_calculation_60_bullets() -> void:
	# Hard difficulty: 60 total ammo -> 0.95x = 57
	manager.set_active_item(manager.ActiveItemType.EXTENDED_MAGAZINE)
	var base_ammo := 60
	var multiplier: float = manager.get_total_ammo_multiplier()
	var new_ammo: int = int(base_ammo * multiplier)
	assert_eq(new_ammo, 57,
		"60 total ammo * 0.95 should be 57")


# ============================================================================
# All Items Count Tests
# ============================================================================


func test_total_active_items_includes_extended_magazine() -> void:
	var all_types := manager.get_all_active_item_types()
	assert_true(manager.ActiveItemType.EXTENDED_MAGAZINE in all_types,
		"All active item types should include EXTENDED_MAGAZINE")


func test_active_item_count_is_eighteen() -> void:
	# NONE + 18 items = 19 total (after adding EXTENDED_MAGAZINE + Loudspeaker + Breaching Charges + Armored Skin + Auto-Reload + Drilling Bullets + Recoil Compensator + Combat Disposition + Experimental Sample)
	var all_types := manager.get_all_active_item_types()
	assert_eq(all_types.size(), 19,
		"Should have 19 active item types total (NONE + 18 items including EXTENDED_MAGAZINE, DRILLING_BULLETS, RECOIL_COMPENSATOR, COMBAT_DISPOSITION, and EXPERIMENTAL_SAMPLE)")


# ============================================================================
# Interaction with Other Items Tests
# ============================================================================


func test_equipping_extended_magazine_disables_has_laser_sight() -> void:
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)
	assert_true(manager.has_laser_sight(), "Laser Sight should be active before switch")

	manager.set_active_item(manager.ActiveItemType.EXTENDED_MAGAZINE)
	assert_false(manager.has_laser_sight(),
		"Laser Sight should be inactive after switching to Extended Magazine")
	assert_true(manager.has_extended_magazine(),
		"Extended Magazine should now be active")


func test_equipping_other_item_disables_extended_magazine() -> void:
	manager.set_active_item(manager.ActiveItemType.EXTENDED_MAGAZINE)
	assert_true(manager.has_extended_magazine(), "Extended Magazine should be active")

	manager.set_active_item(manager.ActiveItemType.BREAKER_BULLETS)
	assert_false(manager.has_extended_magazine(),
		"Extended Magazine should be inactive after switching to Breaker Bullets")
	assert_eq(manager.get_magazine_size_multiplier(), 1.0,
		"Magazine size multiplier should revert to 1.0 after switching away from Extended Magazine")
	assert_eq(manager.get_total_ammo_multiplier(), 1.0,
		"Total ammo multiplier should revert to 1.0 after switching away from Extended Magazine")
