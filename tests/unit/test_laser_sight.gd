extends GutTest
## Unit tests for the Laser Sight active item (Issue #947).
##
## Tests the laser sight item including:
## - Registration as active item type
## - Passive behavior (always on when equipped, no Space key needed)
## - Purple color
## - Works regardless of difficulty
## - ActiveItemManager detection methods


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
		11: {"name": "Loudspeaker", "icon_path": "res://assets/sprites/weapons/loudspeaker_icon.png", "description": "Loudspeaker."},
		12: {"name": "Breaching Charges", "icon_path": "res://assets/sprites/weapons/breaching_charges_icon.png", "description": "Breaching charges."},
		13: {"name": "Armored Skin", "icon_path": "res://assets/sprites/weapons/armored_skin_icon.png", "description": "Armored Skin."},
		14: {"name": "Auto-Reload", "icon_path": "res://assets/sprites/weapons/auto_reload_icon.png", "description": "Auto-reload — passive: magazine capacity is reduced 2.1x, but the magazine is fully restocked from reserves on each kill."},
		15: {"name": "Drilling Bullets", "icon_path": "res://assets/sprites/weapons/drilling_bullets_icon.png", "description": "Drilling bullets — press Space to apply wall-piercing effect to the current magazine."},
		16: {"name": "Recoil Compensator", "icon_path": "res://assets/sprites/weapons/recoil_compensator_icon.png", "description": "Recoil compensator — hold Space to eliminate recoil and spread completely, and increase fire rate by 10%."},
		17: {"name": "Combat Disposition", "icon_path": "res://assets/sprites/weapons/combat_disposition_icon.png", "description": "Combat Disposition — passive: +0.77 damage and +1.1 fire rate on start. Taking damage reduces bonuses."},
		18: {"name": "Experimental Sample", "icon_path": "res://assets/sprites/weapons/experimental_sample_icon.png", "description": "Experimental Sample — press Space to trigger a random active item effect.", "activation_hint": "Press Space to trigger random effect"}
	}

	## Check if laser sight is currently equipped (Issue #947)
	func has_laser_sight() -> bool:
		return current_active_item == ActiveItemType.LASER_SIGHT

	## Get the laser sight color (purple)
	func get_laser_sight_color() -> Color:
		return Color(0.6, 0.0, 1.0, 0.6)  # Purple with some transparency

	## Check if a laser sight should be forced on all weapons
	func should_force_laser_sight() -> bool:
		return current_active_item == ActiveItemType.LASER_SIGHT

	## Check if any other item is equipped
	func has_flashlight() -> bool:
		return current_active_item == ActiveItemType.FLASHLIGHT

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

	## Get the description of an active item type
	func get_active_item_description(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["description"]
		return ""

	## Check if an active item type is the currently selected type
	func is_selected(type: int) -> bool:
		return type == current_active_item

	## Get all available active item types
	func get_all_active_item_types() -> Array:
		return ACTIVE_ITEM_DATA.keys()


var manager: MockActiveItemManager


func before_each() -> void:
	manager = MockActiveItemManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Laser Sight Type Registration Tests
# ============================================================================


func test_laser_sight_type_value_is_9() -> void:
	assert_eq(manager.ActiveItemType.LASER_SIGHT, 9,
		"LASER_SIGHT should have value 9 (after TRAJECTORY_GLASSES which is 8)")


func test_laser_sight_type_exists_in_data() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.LASER_SIGHT)
	assert_false(data.is_empty(),
		"LASER_SIGHT type should have data in ACTIVE_ITEM_DATA")


func test_laser_sight_has_correct_name() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.LASER_SIGHT)
	assert_eq(data.get("name", ""), "Laser Sight",
		"Laser Sight should have correct name")


func test_laser_sight_has_icon_path() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.LASER_SIGHT)
	var icon_path: String = data.get("icon_path", "")
	assert_false(icon_path.is_empty(),
		"Laser Sight should have an icon path")
	assert_true(icon_path.ends_with(".png"),
		"Laser Sight icon path should point to a PNG file")


func test_laser_sight_has_description() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.LASER_SIGHT)
	var description: String = data.get("description", "")
	assert_false(description.is_empty(),
		"Laser Sight should have a description")
	assert_true(description.contains("laser") or description.contains("Laser"),
		"Description should mention laser")
	assert_true(description.contains("purple") or description.contains("Purple"),
		"Description should mention purple color")


func test_laser_sight_description_mentions_passive() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.LASER_SIGHT)
	var description: String = data.get("description", "")
	assert_true(description.contains("passive") or description.to_lower().contains("passive"),
		"Description should indicate this is a passive item (no activation needed)")


# ============================================================================
# has_laser_sight() Method Tests
# ============================================================================


func test_has_laser_sight_returns_false_when_none_equipped() -> void:
	# Default is NONE
	assert_false(manager.has_laser_sight(),
		"has_laser_sight() should return false when NONE is equipped")


func test_has_laser_sight_returns_true_when_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)
	assert_true(manager.has_laser_sight(),
		"has_laser_sight() should return true when LASER_SIGHT is equipped")


func test_has_laser_sight_returns_false_when_other_item_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.FLASHLIGHT)
	assert_false(manager.has_laser_sight(),
		"has_laser_sight() should return false when another item is equipped")


func test_has_laser_sight_returns_false_when_trajectory_glasses_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.TRAJECTORY_GLASSES)
	assert_false(manager.has_laser_sight(),
		"has_laser_sight() should return false when Trajectory Glasses are equipped")


# ============================================================================
# should_force_laser_sight() Method Tests
# ============================================================================


func test_should_force_laser_sight_returns_false_by_default() -> void:
	assert_false(manager.should_force_laser_sight(),
		"should_force_laser_sight() should return false when no item is equipped")


func test_should_force_laser_sight_returns_true_when_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)
	assert_true(manager.should_force_laser_sight(),
		"should_force_laser_sight() should return true when LASER_SIGHT is equipped")


func test_should_force_laser_sight_returns_false_when_other_item_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.HOMING_BULLETS)
	assert_false(manager.should_force_laser_sight(),
		"should_force_laser_sight() should return false when other items are equipped")


# ============================================================================
# get_laser_sight_color() Method Tests
# ============================================================================


func test_laser_sight_color_is_purple() -> void:
	var color: Color = manager.get_laser_sight_color()
	# Purple: high red and blue, low green
	assert_true(color.r > 0.4, "Laser sight color should have significant red component")
	assert_true(color.b > 0.7, "Laser sight color should have significant blue component")
	assert_true(color.g < 0.3, "Laser sight color should have low green component for purple")


func test_laser_sight_color_has_transparency() -> void:
	var color: Color = manager.get_laser_sight_color()
	assert_true(color.a < 1.0, "Laser sight color should have some transparency (like power fantasy laser)")
	assert_true(color.a > 0.0, "Laser sight color should not be fully transparent")


# ============================================================================
# Passive Behavior Tests (no activation needed)
# ============================================================================


func test_laser_sight_is_passive_no_activation_method() -> void:
	# Laser sight should NOT require activation via Space key.
	# It's a passive item - always on when equipped.
	# We verify the type doesn't have an activation_hint in the data.
	var data := manager.get_active_item_data(manager.ActiveItemType.LASER_SIGHT)
	assert_false(data.has("activation_hint"),
		"Laser Sight should NOT have activation_hint (it's passive, no Space key needed)")


# ============================================================================
# All Items Count Tests
# ============================================================================


func test_total_active_items_includes_laser_sight() -> void:
	var all_types := manager.get_all_active_item_types()
	assert_true(manager.ActiveItemType.LASER_SIGHT in all_types,
		"All active item types should include LASER_SIGHT")


func test_active_item_count_is_eighteen() -> void:
	# NONE + 18 items = 19 total (EXPERIMENTAL_SAMPLE added by Issue #1127)
	var all_types := manager.get_all_active_item_types()
	assert_eq(all_types.size(), 19,
		"Should have 19 active item types total (NONE + 18 items including LASER_SIGHT, EXTENDED_MAGAZINE, LOUDSPEAKER, BREACHING_CHARGES, ARMORED_SKIN, AUTO_RELOAD, DRILLING_BULLETS, RECOIL_COMPENSATOR, COMBAT_DISPOSITION, and EXPERIMENTAL_SAMPLE)")


# ============================================================================
# Difficulty Independence Tests
# ============================================================================


class MockDifficultyManager:
	## Difficulty levels
	enum Difficulty {EASY = 0, NORMAL = 1, HARD = 2, POWER_FANTASY = 3}

	var current_difficulty: int = Difficulty.NORMAL

	func is_power_fantasy_mode() -> bool:
		return current_difficulty == Difficulty.POWER_FANTASY

	func should_force_blue_laser_sight() -> bool:
		return current_difficulty == Difficulty.POWER_FANTASY

	func get_power_fantasy_laser_color() -> Color:
		return Color(0.0, 0.5, 1.0, 0.6)


func test_laser_sight_works_in_normal_mode() -> void:
	var difficulty := MockDifficultyManager.new()
	difficulty.current_difficulty = MockDifficultyManager.Difficulty.NORMAL
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)

	# Regardless of difficulty, laser sight should be forced
	assert_false(difficulty.should_force_blue_laser_sight(),
		"Power Fantasy blue laser should NOT be forced in Normal mode")
	assert_true(manager.should_force_laser_sight(),
		"Laser sight item should force purple laser in ANY difficulty including Normal")


func test_laser_sight_works_in_hard_mode() -> void:
	var difficulty := MockDifficultyManager.new()
	difficulty.current_difficulty = MockDifficultyManager.Difficulty.HARD
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)

	assert_false(difficulty.should_force_blue_laser_sight(),
		"Power Fantasy blue laser should NOT be forced in Hard mode")
	assert_true(manager.should_force_laser_sight(),
		"Laser sight item should force purple laser in ANY difficulty including Hard")


func test_laser_sight_works_in_easy_mode() -> void:
	var difficulty := MockDifficultyManager.new()
	difficulty.current_difficulty = MockDifficultyManager.Difficulty.EASY
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)

	assert_false(difficulty.should_force_blue_laser_sight(),
		"Power Fantasy blue laser should NOT be forced in Easy mode")
	assert_true(manager.should_force_laser_sight(),
		"Laser sight item should force purple laser in ANY difficulty including Easy")


func test_laser_sight_works_independently_in_power_fantasy_mode() -> void:
	var difficulty := MockDifficultyManager.new()
	difficulty.current_difficulty = MockDifficultyManager.Difficulty.POWER_FANTASY
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)

	assert_true(difficulty.should_force_blue_laser_sight(),
		"Power Fantasy blue laser SHOULD be forced in Power Fantasy mode")
	assert_true(manager.should_force_laser_sight(),
		"Laser sight item should also force purple laser in Power Fantasy mode")


func test_purple_overrides_blue_when_laser_sight_active() -> void:
	# When both power fantasy AND laser sight active item are selected,
	# the purple color should be the final color (active item check runs after power fantasy).
	var difficulty := MockDifficultyManager.new()
	difficulty.current_difficulty = MockDifficultyManager.Difficulty.POWER_FANTASY
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)

	# Simulate the weapon init logic: first check difficulty, then active item
	var final_color := difficulty.get_power_fantasy_laser_color()  # Blue from PF mode
	if manager.should_force_laser_sight():
		final_color = manager.get_laser_sight_color()  # Purple overrides blue

	# Final color should be purple (from laser sight item)
	assert_true(final_color.b > final_color.g,
		"Final laser color should be more blue+red (purple) than green when laser sight item is equipped")
	assert_true(final_color.r > 0.4,
		"Final laser color should have red component (purple, not blue)")


func test_no_laser_when_laser_sight_not_equipped() -> void:
	# In Normal mode with no laser sight item, there should be no forced laser
	var difficulty := MockDifficultyManager.new()
	difficulty.current_difficulty = MockDifficultyManager.Difficulty.NORMAL
	# manager default: NONE equipped

	assert_false(difficulty.should_force_blue_laser_sight(),
		"Blue laser should not be forced without Power Fantasy mode")
	assert_false(manager.should_force_laser_sight(),
		"Purple laser should not be forced without laser sight item equipped")
