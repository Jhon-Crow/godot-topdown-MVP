extends GutTest
## Unit tests for the Experimental Sample active item (Issue #1127).
##
## Tests the experimental sample item including:
## - Registration as active item type (index 18)
## - Random charge count (1–5) per battle
## - has_experimental_sample() detection method
## - Charge decrement on activation
## - No conflict with other items
## - Item data (name, icon, description, activation hint)


# ============================================================================
# Mock Classes
# ============================================================================


class MockActiveItemManager:
	## Active item types (includes EXPERIMENTAL_SAMPLE = 18)
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
		15: {"name": "Drilling Bullets", "icon_path": "res://assets/sprites/weapons/drilling_bullets_icon.png", "description": "Drilling bullets."},
		16: {"name": "Recoil Compensator", "icon_path": "res://assets/sprites/weapons/recoil_compensator_icon.png", "description": "Recoil compensator."},
		17: {"name": "Combat Disposition", "icon_path": "res://assets/sprites/weapons/combat_disposition_icon.png", "description": "Combat Disposition — passive."},
		18: {
			"name": "Experimental Sample",
			"icon_path": "res://assets/sprites/weapons/experimental_sample_icon.png",
			"description": "Experimental Sample — press Space to trigger a random active item effect (including items not yet unlocked). 1–5 charges per battle, randomised on level start.",
			"activation_hint": "Press Space to trigger random effect"
		},
		19: {"name": "Fine Motor Skills", "icon_path": "res://assets/sprites/weapons/fine_motor_skills_icon.png", "description": "Fine Motor Skills — press Space to instantly reload weapon.", "activation_hint": "Press Space to reload"},
		20: {"name": "Dash", "icon_path": "res://assets/sprites/weapons/dash_icon.png", "description": "Dash — press Space to dash in movement direction.", "activation_hint": "Press Space to dash"},
		21: {"name": "Grenade Bag", "icon_path": "res://assets/sprites/weapons/grenade_bag_icon.png", "description": "Grenade Bag — passive: increases starting grenade count."}
	}

	## Check if experimental sample is currently equipped (Issue #1127)
	func has_experimental_sample() -> bool:
		return current_active_item == ActiveItemType.EXPERIMENTAL_SAMPLE

	## Check if other items are equipped
	func has_flashlight() -> bool:
		return current_active_item == ActiveItemType.FLASHLIGHT

	func has_homing_bullets() -> bool:
		return current_active_item == ActiveItemType.HOMING_BULLETS

	func has_combat_disposition() -> bool:
		return current_active_item == ActiveItemType.COMBAT_DISPOSITION

	func has_laser_sight() -> bool:
		return current_active_item == ActiveItemType.LASER_SIGHT

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


## Simulates the Experimental Sample charge logic from Player.gd
class MockExperimentalSampleSystem:
	const MIN_CHARGES: int = 1
	const MAX_CHARGES: int = 5

	## Whether the experimental sample is equipped
	var equipped: bool = false
	## Remaining charges this battle (1–5, randomised)
	var charges: int = 0
	## The item type that was triggered on the last activation (-1 = none)
	var last_triggered_type: int = -1

	## Equip and randomise the charge count (1–5)
	func equip_with_random_charges(seed_value: int = 0) -> void:
		equipped = true
		# Use a seeded RNG so tests are deterministic
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		charges = rng.randi_range(MIN_CHARGES, MAX_CHARGES)

	## Activate: consume a charge and pick a random effect type (1–17)
	## Returns true if activation succeeded, false if no charges remain.
	func activate(rng: RandomNumberGenerator) -> bool:
		if not equipped or charges <= 0:
			return false
		charges -= 1
		last_triggered_type = rng.randi_range(1, 17)
		return true

	## Simulate multiple activations and collect triggered types
	func activate_n_times(n: int, rng: RandomNumberGenerator) -> Array:
		var types: Array = []
		for _i in range(n):
			if activate(rng):
				types.append(last_triggered_type)
		return types


var manager: MockActiveItemManager


func before_each() -> void:
	manager = MockActiveItemManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Type Registration Tests
# ============================================================================


func test_experimental_sample_type_value_is_18() -> void:
	assert_eq(manager.ActiveItemType.EXPERIMENTAL_SAMPLE, 18,
		"EXPERIMENTAL_SAMPLE should have value 18 (after COMBAT_DISPOSITION=17)")


func test_experimental_sample_type_exists_in_data() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	assert_false(data.is_empty(),
		"EXPERIMENTAL_SAMPLE type should have data in ACTIVE_ITEM_DATA")


func test_experimental_sample_has_correct_name() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	assert_eq(data.get("name", ""), "Experimental Sample",
		"Experimental Sample should have correct name")


func test_experimental_sample_has_icon_path() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	var icon_path: String = data.get("icon_path", "")
	assert_false(icon_path.is_empty(),
		"Experimental Sample should have an icon path")
	assert_true(icon_path.ends_with(".png"),
		"Experimental Sample icon path should point to a PNG file")
	assert_true(icon_path.contains("experimental_sample"),
		"Icon path should contain 'experimental_sample'")


func test_experimental_sample_has_description() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	var description: String = data.get("description", "")
	assert_false(description.is_empty(),
		"Experimental Sample should have a description")


func test_experimental_sample_description_mentions_random() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	var description: String = data.get("description", "")
	assert_true(description.to_lower().contains("random"),
		"Description should mention that the effect is random")


func test_experimental_sample_description_mentions_charges() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	var description: String = data.get("description", "")
	assert_true(description.contains("charge") or description.contains("1") or description.contains("5"),
		"Description should mention the charge count (1–5)")


func test_experimental_sample_has_activation_hint() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	assert_true(data.has("activation_hint"),
		"Experimental Sample should have an activation_hint (it is Space-press activated)")


func test_experimental_sample_activation_hint_mentions_space() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	var hint: String = data.get("activation_hint", "")
	assert_true(hint.to_lower().contains("space") or hint.to_lower().contains("press"),
		"Activation hint should mention pressing Space")


# ============================================================================
# has_experimental_sample() Method Tests
# ============================================================================


func test_has_experimental_sample_returns_false_when_none_equipped() -> void:
	assert_false(manager.has_experimental_sample(),
		"has_experimental_sample() should return false when NONE is equipped")


func test_has_experimental_sample_returns_true_when_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	assert_true(manager.has_experimental_sample(),
		"has_experimental_sample() should return true when EXPERIMENTAL_SAMPLE is equipped")


func test_has_experimental_sample_returns_false_when_other_item_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.FLASHLIGHT)
	assert_false(manager.has_experimental_sample(),
		"has_experimental_sample() should return false when another item is equipped")


func test_has_experimental_sample_returns_false_when_homing_bullets_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.HOMING_BULLETS)
	assert_false(manager.has_experimental_sample(),
		"has_experimental_sample() should return false when Homing Bullets is equipped")


func test_has_experimental_sample_returns_false_after_deselection() -> void:
	manager.set_active_item(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	manager.set_active_item(manager.ActiveItemType.NONE)
	assert_false(manager.has_experimental_sample(),
		"has_experimental_sample() should return false after switching back to None")


# ============================================================================
# Charge System Tests
# ============================================================================


func test_experimental_sample_charges_are_within_valid_range() -> void:
	# Run multiple seeds to verify the range is always 1–5
	for seed_value in range(20):
		var system := MockExperimentalSampleSystem.new()
		system.equip_with_random_charges(seed_value)
		assert_true(system.charges >= MockExperimentalSampleSystem.MIN_CHARGES,
			"Charges should be >= 1 (seed=%d, charges=%d)" % [seed_value, system.charges])
		assert_true(system.charges <= MockExperimentalSampleSystem.MAX_CHARGES,
			"Charges should be <= 5 (seed=%d, charges=%d)" % [seed_value, system.charges])


func test_experimental_sample_min_charges_constant_is_1() -> void:
	assert_eq(MockExperimentalSampleSystem.MIN_CHARGES, 1,
		"EXPERIMENTAL_SAMPLE_MIN_CHARGES should be 1")


func test_experimental_sample_max_charges_constant_is_5() -> void:
	assert_eq(MockExperimentalSampleSystem.MAX_CHARGES, 5,
		"EXPERIMENTAL_SAMPLE_MAX_CHARGES should be 5")


func test_experimental_sample_activation_decrements_charges() -> void:
	var system := MockExperimentalSampleSystem.new()
	system.equip_with_random_charges(42)
	var initial_charges := system.charges
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	system.activate(rng)
	assert_eq(system.charges, initial_charges - 1,
		"Each activation should decrement charges by 1")


func test_experimental_sample_cannot_activate_without_charges() -> void:
	var system := MockExperimentalSampleSystem.new()
	system.equipped = true
	system.charges = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var result := system.activate(rng)
	assert_false(result,
		"Activation should fail when no charges remain")


func test_experimental_sample_cannot_activate_when_not_equipped() -> void:
	var system := MockExperimentalSampleSystem.new()
	system.equipped = false
	system.charges = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var result := system.activate(rng)
	assert_false(result,
		"Activation should fail when not equipped")


func test_experimental_sample_charges_reach_zero_after_all_used() -> void:
	var system := MockExperimentalSampleSystem.new()
	system.equipped = true
	system.charges = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for _i in range(3):
		system.activate(rng)
	assert_eq(system.charges, 0,
		"Charges should reach 0 after all are used")


func test_experimental_sample_activation_count_matches_charges() -> void:
	var system := MockExperimentalSampleSystem.new()
	system.equipped = true
	system.charges = 4
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var triggered := system.activate_n_times(10, rng)
	# Should only trigger 4 times (matching the charge count)
	assert_eq(triggered.size(), 4,
		"Should only activate as many times as there are charges")


# ============================================================================
# Random Effect Type Tests
# ============================================================================


func test_experimental_sample_triggers_valid_item_types() -> void:
	# Each activation must produce a type in range 1–17 (all existing items except NONE and EXPERIMENTAL_SAMPLE)
	var system := MockExperimentalSampleSystem.new()
	system.equipped = true
	system.charges = 50
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var types := system.activate_n_times(50, rng)
	for t in types:
		assert_true(t >= 1 and t <= 17,
			"Triggered type %d must be in range 1–17" % t)


func test_experimental_sample_never_triggers_none_type() -> void:
	var system := MockExperimentalSampleSystem.new()
	system.equipped = true
	system.charges = 100
	var rng := RandomNumberGenerator.new()
	rng.seed = 7777
	var types := system.activate_n_times(100, rng)
	for t in types:
		assert_ne(t, 0,
			"Triggered type should never be NONE (0)")


func test_experimental_sample_never_triggers_itself() -> void:
	var system := MockExperimentalSampleSystem.new()
	system.equipped = true
	system.charges = 100
	var rng := RandomNumberGenerator.new()
	rng.seed = 9999
	var types := system.activate_n_times(100, rng)
	for t in types:
		assert_ne(t, 18,
			"Triggered type should never be EXPERIMENTAL_SAMPLE (18) itself")


func test_experimental_sample_random_types_cover_full_range() -> void:
	# With enough activations, all item types 1–17 should appear at least once
	var system := MockExperimentalSampleSystem.new()
	system.equipped = true
	system.charges = 10000
	var rng := RandomNumberGenerator.new()
	rng.seed = 2025
	var types := system.activate_n_times(10000, rng)
	var unique_types := {}
	for t in types:
		unique_types[t] = true
	for expected_type in range(1, 18):
		assert_true(expected_type in unique_types,
			"Item type %d should appear at least once in 10,000 activations" % expected_type)


# ============================================================================
# Mutual Exclusion Tests
# ============================================================================


func test_experimental_sample_does_not_conflict_with_flashlight() -> void:
	manager.set_active_item(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	assert_false(manager.has_flashlight(),
		"Flashlight should not be active when Experimental Sample is selected")
	assert_true(manager.has_experimental_sample(),
		"Experimental Sample should be active")


func test_flashlight_does_not_conflict_with_experimental_sample() -> void:
	manager.set_active_item(manager.ActiveItemType.FLASHLIGHT)
	assert_true(manager.has_flashlight(),
		"Flashlight should be active")
	assert_false(manager.has_experimental_sample(),
		"Experimental Sample should not be active when Flashlight is selected")


func test_experimental_sample_does_not_conflict_with_combat_disposition() -> void:
	manager.set_active_item(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	assert_false(manager.has_combat_disposition(),
		"Combat Disposition should not be active when Experimental Sample is selected")
	assert_true(manager.has_experimental_sample(),
		"Experimental Sample should be active")


func test_experimental_sample_does_not_conflict_with_laser_sight() -> void:
	manager.set_active_item(manager.ActiveItemType.EXPERIMENTAL_SAMPLE)
	assert_false(manager.has_laser_sight(),
		"Laser Sight should not be active when Experimental Sample is selected")
	assert_true(manager.has_experimental_sample(),
		"Experimental Sample should be active")


# ============================================================================
# All Items Count Tests
# ============================================================================


func test_total_active_items_includes_experimental_sample() -> void:
	var all_types := manager.get_all_active_item_types()
	assert_true(manager.ActiveItemType.EXPERIMENTAL_SAMPLE in all_types,
		"All active item types should include EXPERIMENTAL_SAMPLE")


func test_active_item_count_is_nineteen() -> void:
	# NONE + 21 items = 22 total (FINE_MOTOR_SKILLS, DASH, GRENADE_BAG added by Issues #1315, #1071, #1590)
	var all_types := manager.get_all_active_item_types()
	assert_eq(all_types.size(), 22,
		"Should have 22 active item types total (NONE + 21 items including EXPERIMENTAL_SAMPLE, FINE_MOTOR_SKILLS, DASH, and GRENADE_BAG)")


func test_experimental_sample_is_last_item_type() -> void:
	# EXPERIMENTAL_SAMPLE=18 should be the highest enum value
	var all_types := manager.get_all_active_item_types()
	var max_type := 0
	for t in all_types:
		if t > max_type:
			max_type = t
	assert_eq(max_type, manager.ActiveItemType.EXPERIMENTAL_SAMPLE,
		"EXPERIMENTAL_SAMPLE should have the highest type value (18)")
