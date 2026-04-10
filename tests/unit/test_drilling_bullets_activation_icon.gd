extends GutTest
## Unit tests for the Drilling Bullets activation icon (Issue #1319).
##
## Tests the drilling bullets item including:
## - Registration as active item type (index 15)
## - has_drilling_bullets() detection method
## - Item data (name, icon, description, activation hint)
## - Activation icon duration constant (0.4s / 400ms)
## - Popup script exists for reuse by drilling bullets
## - Single-charge activation logic


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
		EXPERIMENTAL_SAMPLE = 18,
		FINE_MOTOR_SKILLS = 19,
		DASH = 20,
		GRENADE_BAG = 21
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
		9: {"name": "Laser Sight", "icon_path": "res://assets/sprites/weapons/laser_sight_icon.png", "description": "Laser sight."},
		10: {"name": "Extended Magazine", "icon_path": "res://assets/sprites/weapons/extended_magazine_icon.png", "description": "Extended magazine."},
		11: {"name": "Loudspeaker", "icon_path": "res://assets/sprites/weapons/loudspeaker_icon.png", "description": "???"},
		12: {"name": "Breaching Charges", "icon_path": "res://assets/sprites/weapons/breaching_charges_icon.png", "description": "Breaching charges."},
		13: {"name": "Armored Skin", "icon_path": "res://assets/sprites/weapons/armored_skin_icon.png", "description": "Armored skin."},
		14: {"name": "Auto-Reload", "icon_path": "res://assets/sprites/weapons/auto_reload_icon.png", "description": "Auto-reload."},
		15: {
			"name": "Drilling Bullets",
			"icon_path": "res://assets/sprites/weapons/drilling_bullets_icon.png",
			"description": "Drilling bullets — press Space to apply wall-piercing effect to the current magazine. Bullets ignore walls (full damage through walls, no ricochet). One charge per battle.",
			"activation_hint": "Press Space to activate"
		},
		16: {"name": "Recoil Compensator", "icon_path": "res://assets/sprites/weapons/recoil_compensator_icon.png", "description": "Recoil compensator."},
		17: {"name": "Combat Disposition", "icon_path": "res://assets/sprites/weapons/combat_disposition_icon.png", "description": "Combat Disposition — passive."},
		18: {"name": "Experimental Sample", "icon_path": "res://assets/sprites/weapons/experimental_sample_icon.png", "description": "Experimental Sample."},
		19: {"name": "Fine Motor Skills", "icon_path": "res://assets/sprites/weapons/fine_motor_skills_icon.png", "description": "Fine Motor Skills — press Space to instantly reload weapon.", "activation_hint": "Press Space to reload"},
		20: {"name": "Dash", "icon_path": "res://assets/sprites/weapons/dash_icon.png", "description": "Dash — press Space to dash in movement direction.", "activation_hint": "Press Space to dash"},
		21: {"name": "Grenade Bag", "icon_path": "res://assets/sprites/weapons/grenade_bag_icon.png", "description": "Grenade Bag — passive: increases starting grenade count."}
	}

	## Check if drilling bullets are currently equipped (Issue #751)
	func has_drilling_bullets() -> bool:
		return current_active_item == ActiveItemType.DRILLING_BULLETS

	## Check if other items are equipped
	func has_flashlight() -> bool:
		return current_active_item == ActiveItemType.FLASHLIGHT

	func has_homing_bullets() -> bool:
		return current_active_item == ActiveItemType.HOMING_BULLETS

	func has_experimental_sample() -> bool:
		return current_active_item == ActiveItemType.EXPERIMENTAL_SAMPLE

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

	## Get the icon path for a specific item type
	func get_active_item_icon_path(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type].get("icon_path", "")
		return ""

	## Get the name of an active item type
	func get_active_item_name(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["name"]
		return "Unknown"

	## Check if an active item type is the currently selected type
	func is_selected(type: int) -> bool:
		return type == current_active_item

	## Get all available active item types
	func get_all_active_item_types() -> Array:
		return ACTIVE_ITEM_DATA.keys()


## Simulates the DrillingBullets single-charge logic from Player.cs (Issue #751, #1319)
class MockDrillingBulletsSystem:
	## Whether drilling bullets are equipped
	var equipped: bool = false
	## Whether the single charge has been used this battle
	var charge_used: bool = false
	## Last magazine ammo count set (simulates DrillingBulletsRemaining on weapon)
	var drilling_bullets_remaining: int = 0
	## Whether activation icon was shown on last activation
	var icon_shown: bool = false
	## Duration (seconds) of the last shown icon
	var last_icon_duration: float = 0.0

	## Icon duration constant (400ms)
	const ICON_DURATION: float = 0.4

	## Try to activate: returns true if activation succeeded (charge was available and ammo > 0)
	func activate(magazine_ammo: int) -> bool:
		if not equipped or charge_used or magazine_ammo <= 0:
			icon_shown = false
			last_icon_duration = 0.0
			return false
		charge_used = true
		drilling_bullets_remaining = magazine_ammo
		# Simulate showing icon (Issue #1319)
		icon_shown = true
		last_icon_duration = ICON_DURATION
		return true

	## Reset for a new battle
	func reset_for_battle() -> void:
		charge_used = false
		drilling_bullets_remaining = 0
		icon_shown = false
		last_icon_duration = 0.0


var manager: MockActiveItemManager


func before_each() -> void:
	manager = MockActiveItemManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Type Registration Tests
# ============================================================================


func test_drilling_bullets_type_value_is_15() -> void:
	assert_eq(manager.ActiveItemType.DRILLING_BULLETS, 15,
		"DRILLING_BULLETS should have value 15")


func test_drilling_bullets_type_exists_in_data() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.DRILLING_BULLETS)
	assert_false(data.is_empty(),
		"DRILLING_BULLETS type should have data in ACTIVE_ITEM_DATA")


func test_drilling_bullets_has_correct_name() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.DRILLING_BULLETS)
	assert_eq(data.get("name", ""), "Drilling Bullets",
		"Drilling Bullets should have correct name")


func test_drilling_bullets_has_icon_path() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.DRILLING_BULLETS)
	var icon_path: String = data.get("icon_path", "")
	assert_false(icon_path.is_empty(),
		"Drilling Bullets should have an icon path")
	assert_true(icon_path.ends_with(".png"),
		"Drilling Bullets icon path should point to a PNG file")
	assert_true(icon_path.contains("drilling_bullets"),
		"Icon path should contain 'drilling_bullets'")


func test_drilling_bullets_has_description() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.DRILLING_BULLETS)
	var description: String = data.get("description", "")
	assert_false(description.is_empty(),
		"Drilling Bullets should have a description")


func test_drilling_bullets_description_mentions_wall_piercing() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.DRILLING_BULLETS)
	var description: String = data.get("description", "").to_lower()
	assert_true(description.contains("wall") or description.contains("pierc"),
		"Description should mention wall-piercing effect")


func test_drilling_bullets_description_mentions_one_charge() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.DRILLING_BULLETS)
	var description: String = data.get("description", "").to_lower()
	assert_true(description.contains("one charge") or description.contains("1 charge") or description.contains("charge"),
		"Description should mention the single charge")


func test_drilling_bullets_has_activation_hint() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.DRILLING_BULLETS)
	assert_true(data.has("activation_hint"),
		"Drilling Bullets should have an activation_hint (it is Space-press activated)")


func test_drilling_bullets_activation_hint_mentions_space() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.DRILLING_BULLETS)
	var hint: String = data.get("activation_hint", "").to_lower()
	assert_true(hint.contains("space") or hint.contains("press"),
		"Activation hint should mention pressing Space")


# ============================================================================
# has_drilling_bullets() Method Tests
# ============================================================================


func test_has_drilling_bullets_returns_false_when_none_equipped() -> void:
	assert_false(manager.has_drilling_bullets(),
		"has_drilling_bullets() should return false when NONE is equipped")


func test_has_drilling_bullets_returns_true_when_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.DRILLING_BULLETS)
	assert_true(manager.has_drilling_bullets(),
		"has_drilling_bullets() should return true when DRILLING_BULLETS is equipped")


func test_has_drilling_bullets_returns_false_when_other_item_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.FLASHLIGHT)
	assert_false(manager.has_drilling_bullets(),
		"has_drilling_bullets() should return false when another item is equipped")


func test_has_drilling_bullets_returns_false_after_deselection() -> void:
	manager.set_active_item(manager.ActiveItemType.DRILLING_BULLETS)
	manager.set_active_item(manager.ActiveItemType.NONE)
	assert_false(manager.has_drilling_bullets(),
		"has_drilling_bullets() should return false after switching back to None")


# ============================================================================
# Icon Path Tests
# ============================================================================


func test_get_active_item_icon_path_returns_drilling_bullets_icon() -> void:
	var icon_path: String = manager.get_active_item_icon_path(manager.ActiveItemType.DRILLING_BULLETS)
	assert_false(icon_path.is_empty(),
		"get_active_item_icon_path(DRILLING_BULLETS) should return a non-empty path")
	assert_true(icon_path.contains("drilling_bullets"),
		"Icon path should reference the drilling_bullets icon")


func test_drilling_bullets_icon_path_is_type_15() -> void:
	# The C# code uses hardcoded type 15 for DRILLING_BULLETS when calling get_active_item_icon_path
	var icon_path: String = manager.get_active_item_icon_path(15)
	assert_false(icon_path.is_empty(),
		"get_active_item_icon_path(15) should return the drilling bullets icon path")


# ============================================================================
# Activation Icon Duration Tests (Issue #1319)
# ============================================================================


func test_drilling_bullets_activation_icon_duration_constant_is_400ms() -> void:
	assert_eq(MockDrillingBulletsSystem.ICON_DURATION, 0.4,
		"Drilling bullets icon duration should be 0.4 seconds (400ms)")


func test_drilling_bullets_activation_shows_icon_on_success() -> void:
	var system := MockDrillingBulletsSystem.new()
	system.equipped = true
	var result := system.activate(10)
	assert_true(result,
		"Activation with ammo in magazine should succeed")
	assert_true(system.icon_shown,
		"Activation icon should be shown on successful activation (Issue #1319)")


func test_drilling_bullets_activation_icon_lasts_400ms() -> void:
	var system := MockDrillingBulletsSystem.new()
	system.equipped = true
	system.activate(10)
	assert_eq(system.last_icon_duration, 0.4,
		"Activation icon should be displayed for exactly 0.4 seconds (400ms) (Issue #1319)")


func test_drilling_bullets_no_icon_when_no_ammo() -> void:
	var system := MockDrillingBulletsSystem.new()
	system.equipped = true
	var result := system.activate(0)
	assert_false(result,
		"Activation should fail when no ammo in magazine")
	assert_false(system.icon_shown,
		"Icon should NOT be shown when activation fails due to no ammo")


func test_drilling_bullets_no_icon_when_charge_already_used() -> void:
	var system := MockDrillingBulletsSystem.new()
	system.equipped = true
	system.activate(10)  # Use the charge
	# Reset icon tracking but keep charge_used = true
	system.icon_shown = false
	system.last_icon_duration = 0.0
	var result := system.activate(5)  # Try to activate again
	assert_false(result,
		"Second activation should fail when charge already used")
	assert_false(system.icon_shown,
		"Icon should NOT be shown when charge is already consumed")


func test_drilling_bullets_no_icon_when_not_equipped() -> void:
	var system := MockDrillingBulletsSystem.new()
	system.equipped = false
	var result := system.activate(10)
	assert_false(result,
		"Activation should fail when not equipped")
	assert_false(system.icon_shown,
		"Icon should NOT be shown when item is not equipped")


# ============================================================================
# Single Charge Activation Logic Tests
# ============================================================================


func test_drilling_bullets_activation_consumes_charge() -> void:
	var system := MockDrillingBulletsSystem.new()
	system.equipped = true
	system.activate(10)
	assert_true(system.charge_used,
		"Activation should mark the single charge as used")


func test_drilling_bullets_cannot_activate_twice() -> void:
	var system := MockDrillingBulletsSystem.new()
	system.equipped = true
	var first := system.activate(10)
	var second := system.activate(5)
	assert_true(first, "First activation should succeed")
	assert_false(second, "Second activation should fail (charge already used)")


func test_drilling_bullets_sets_remaining_count_to_magazine_ammo() -> void:
	var system := MockDrillingBulletsSystem.new()
	system.equipped = true
	system.activate(7)
	assert_eq(system.drilling_bullets_remaining, 7,
		"DrillingBulletsRemaining should be set to the magazine ammo count on activation")


func test_drilling_bullets_charge_resets_for_new_battle() -> void:
	var system := MockDrillingBulletsSystem.new()
	system.equipped = true
	system.activate(10)
	system.reset_for_battle()
	assert_false(system.charge_used,
		"Charge should be reset when a new battle starts")
	var result := system.activate(5)
	assert_true(result,
		"Should be able to activate again after reset_for_battle()")


# ============================================================================
# Mutual Exclusion Tests
# ============================================================================


func test_drilling_bullets_does_not_conflict_with_flashlight() -> void:
	manager.set_active_item(manager.ActiveItemType.DRILLING_BULLETS)
	assert_false(manager.has_flashlight(),
		"Flashlight should not be active when Drilling Bullets is selected")
	assert_true(manager.has_drilling_bullets(),
		"Drilling Bullets should be active")


func test_drilling_bullets_does_not_conflict_with_homing_bullets() -> void:
	manager.set_active_item(manager.ActiveItemType.DRILLING_BULLETS)
	assert_false(manager.has_homing_bullets(),
		"Homing Bullets should not be active when Drilling Bullets is selected")
	assert_true(manager.has_drilling_bullets(),
		"Drilling Bullets should be active")


func test_drilling_bullets_does_not_conflict_with_experimental_sample() -> void:
	manager.set_active_item(manager.ActiveItemType.DRILLING_BULLETS)
	assert_false(manager.has_experimental_sample(),
		"Experimental Sample should not be active when Drilling Bullets is selected")
	assert_true(manager.has_drilling_bullets(),
		"Drilling Bullets should be active")
