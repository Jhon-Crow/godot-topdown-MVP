extends GutTest
## Unit tests for the Combat Disposition passive item (Issue #1047, #1583).
##
## Tests the combat disposition item including:
## - Registration as active item type (index 15)
## - Passive behavior: +0.77 damage, +1.1 fire rate, x2 speed on start (x4 on Black Metal)
## - On-hit penalty: -6.0 damage, -7.2 fire rate, speed/2 on first hit
## - ActiveItemManager detection methods
## - No conflict with other items


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
		10: {"name": "Extended Magazine", "icon_path": "res://assets/sprites/weapons/extended_magazine_icon.png", "description": "Extended magazine — passive: 2.5x magazine size, 5% less total ammo."},
		11: {"name": "Loudspeaker", "icon_path": "res://assets/sprites/weapons/loudspeaker_icon.png", "description": "Loudspeaker."},
		12: {"name": "Breaching Charges", "icon_path": "res://assets/sprites/weapons/breaching_charges_icon.png", "description": "Breaching charges."},
		13: {"name": "Armored Skin", "icon_path": "res://assets/sprites/weapons/armored_skin_icon.png", "description": "Armored skin."},
		14: {"name": "Auto-Reload", "icon_path": "res://assets/sprites/weapons/auto_reload_icon.png", "description": "Auto-reload — passive: magazine capacity is reduced 2.1x, but the magazine is fully restocked from reserves on each kill."},
		15: {"name": "Drilling Bullets", "icon_path": "res://assets/sprites/weapons/drilling_bullets_icon.png", "description": "Drilling bullets — press Space to apply wall-piercing effect to the current magazine."},
		16: {"name": "Recoil Compensator", "icon_path": "res://assets/sprites/weapons/recoil_compensator_icon.png", "description": "Recoil compensator — hold Space to eliminate recoil and spread completely, and increase fire rate by 10%."},
		17: {"name": "Combat Disposition", "icon_path": "res://assets/sprites/weapons/combat_disposition_icon.png", "description": "Combat Disposition — passive: +0.77 damage, +1.1 fire rate, x2 speed on start (x4 on Black Metal). Taking damage reduces damage by 6.0, fire rate by 7.2, and halves movement speed."},
		18: {"name": "Experimental Sample", "icon_path": "res://assets/sprites/weapons/experimental_sample_icon.png", "description": "Experimental Sample — press Space to trigger a random active item effect (including items not yet unlocked). 1–5 charges per battle, randomised on level start.", "activation_hint": "Press Space to trigger random effect"}
	}

	## Check if combat disposition is currently equipped (Issue #1047)
	func has_combat_disposition() -> bool:
		return current_active_item == ActiveItemType.COMBAT_DISPOSITION

	## Check if other items are equipped
	func has_flashlight() -> bool:
		return current_active_item == ActiveItemType.FLASHLIGHT

	func has_laser_sight() -> bool:
		return current_active_item == ActiveItemType.LASER_SIGHT

	func has_breaker_bullets() -> bool:
		return current_active_item == ActiveItemType.BREAKER_BULLETS

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


## Simulates the CombatDisposition passive logic from Player.cs
class MockCombatDispositionSystem:
	## Whether combat disposition is active
	var active: bool = false
	## Whether the hit penalty has already been applied (only applied once per run)
	var penalty_applied: bool = false
	## Current damage bonus (starts at +0.77, decreases by 6.0 on first hit)
	var damage_bonus: float = 0.0
	## Current fire rate bonus (starts at +1.1, decreases by 7.2 on first hit)
	var fire_rate_bonus: float = 0.0
	## Current max speed (modified by speed bonus/penalty)
	var max_speed: float = 200.0
	## Base max speed stored before applying the speed bonus
	var base_speed: float = 200.0

	## Initialize with starting bonuses (normal difficulty: x2 speed)
	func init_combat_disposition(is_black_metal: bool = false) -> void:
		active = true
		penalty_applied = false
		damage_bonus = 0.77
		fire_rate_bonus = 1.1
		base_speed = max_speed
		var speed_mult := 4.0 if is_black_metal else 2.0
		max_speed = base_speed * speed_mult

	## Apply hit penalty (called when player takes damage).
	## The penalty is only applied once per run (on the first hit).
	func apply_hit_penalty() -> void:
		if not active:
			return
		if penalty_applied:
			return
		penalty_applied = true
		damage_bonus -= 6.0
		fire_rate_bonus -= 7.2
		max_speed = base_speed / 2.0

	## Get effective damage for a weapon with base damage
	func get_effective_damage(base_damage: float) -> float:
		return base_damage + damage_bonus

	## Get effective fire rate for a weapon with base fire rate
	func get_effective_fire_rate(base_fire_rate: float) -> float:
		return maxf(base_fire_rate + fire_rate_bonus, 0.1)


var manager: MockActiveItemManager


func before_each() -> void:
	manager = MockActiveItemManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# Type Registration Tests
# ============================================================================


func test_combat_disposition_type_value_is_17() -> void:
	assert_eq(manager.ActiveItemType.COMBAT_DISPOSITION, 17,
		"COMBAT_DISPOSITION should have value 17 (after RECOIL_COMPENSATOR=16, DRILLING_BULLETS=15, AUTO_RELOAD=14, EXTENDED_MAGAZINE=10)")


func test_combat_disposition_type_exists_in_data() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.COMBAT_DISPOSITION)
	assert_false(data.is_empty(),
		"COMBAT_DISPOSITION type should have data in ACTIVE_ITEM_DATA")


func test_combat_disposition_has_correct_name() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.COMBAT_DISPOSITION)
	assert_eq(data.get("name", ""), "Combat Disposition",
		"Combat Disposition should have correct name")


func test_combat_disposition_has_icon_path() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.COMBAT_DISPOSITION)
	var icon_path: String = data.get("icon_path", "")
	assert_false(icon_path.is_empty(),
		"Combat Disposition should have an icon path")
	assert_true(icon_path.ends_with(".png"),
		"Combat Disposition icon path should point to a PNG file")
	assert_true(icon_path.contains("combat_disposition"),
		"Icon path should contain 'combat_disposition'")


func test_combat_disposition_has_description() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.COMBAT_DISPOSITION)
	var description: String = data.get("description", "")
	assert_false(description.is_empty(),
		"Combat Disposition should have a description")


func test_combat_disposition_description_mentions_passive() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.COMBAT_DISPOSITION)
	var description: String = data.get("description", "")
	assert_true(description.to_lower().contains("passive"),
		"Description should indicate this is a passive item")


func test_combat_disposition_description_mentions_damage_bonus() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.COMBAT_DISPOSITION)
	var description: String = data.get("description", "")
	assert_true(description.contains("0.77") or description.contains("damage"),
		"Description should mention the +0.77 damage bonus")


func test_combat_disposition_description_mentions_fire_rate_bonus() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.COMBAT_DISPOSITION)
	var description: String = data.get("description", "")
	assert_true(description.contains("fire rate") or description.contains("1"),
		"Description should mention the fire rate bonus")


func test_combat_disposition_description_mentions_hit_penalty() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.COMBAT_DISPOSITION)
	var description: String = data.get("description", "")
	assert_true(description.to_lower().contains("damage") and description.to_lower().contains("reduc"),
		"Description should mention that taking damage reduces the bonuses")


func test_combat_disposition_is_passive_no_activation_hint() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.COMBAT_DISPOSITION)
	assert_false(data.has("activation_hint"),
		"Combat Disposition should NOT have activation_hint (it's passive, no Space key needed)")


# ============================================================================
# has_combat_disposition() Method Tests
# ============================================================================


func test_has_combat_disposition_returns_false_when_none_equipped() -> void:
	assert_false(manager.has_combat_disposition(),
		"has_combat_disposition() should return false when NONE is equipped")


func test_has_combat_disposition_returns_true_when_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.COMBAT_DISPOSITION)
	assert_true(manager.has_combat_disposition(),
		"has_combat_disposition() should return true when COMBAT_DISPOSITION is equipped")


func test_has_combat_disposition_returns_false_when_other_item_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.FLASHLIGHT)
	assert_false(manager.has_combat_disposition(),
		"has_combat_disposition() should return false when another item is equipped")


func test_has_combat_disposition_returns_false_when_laser_sight_equipped() -> void:
	manager.set_active_item(manager.ActiveItemType.LASER_SIGHT)
	assert_false(manager.has_combat_disposition(),
		"has_combat_disposition() should return false when Laser Sight is equipped")


func test_has_combat_disposition_returns_false_after_deselection() -> void:
	manager.set_active_item(manager.ActiveItemType.COMBAT_DISPOSITION)
	manager.set_active_item(manager.ActiveItemType.NONE)
	assert_false(manager.has_combat_disposition(),
		"has_combat_disposition() should return false after switching back to None")


# ============================================================================
# Passive Logic Tests (Combat Disposition bonuses)
# ============================================================================


func test_combat_disposition_starts_with_damage_bonus() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	assert_almost_eq(system.damage_bonus, 0.77, 0.001,
		"Combat Disposition should start with +0.77 damage bonus")


func test_combat_disposition_starts_with_fire_rate_bonus() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	assert_almost_eq(system.fire_rate_bonus, 1.1, 0.001,
		"Combat Disposition should start with +1.1 fire rate bonus")


func test_combat_disposition_increases_effective_damage() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	var base_damage := 10.0
	var effective := system.get_effective_damage(base_damage)
	assert_almost_eq(effective, 10.77, 0.001,
		"Combat Disposition should add +0.77 to base damage")


func test_combat_disposition_increases_effective_fire_rate() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	var base_fire_rate := 5.0
	var effective := system.get_effective_fire_rate(base_fire_rate)
	assert_almost_eq(effective, 6.1, 0.001,
		"Combat Disposition should add +1.1 to base fire rate")


func test_combat_disposition_not_active_by_default() -> void:
	var system := MockCombatDispositionSystem.new()
	assert_false(system.active,
		"Combat Disposition system should not be active by default")


func test_combat_disposition_bonuses_zero_before_init() -> void:
	var system := MockCombatDispositionSystem.new()
	assert_almost_eq(system.damage_bonus, 0.0, 0.001,
		"Damage bonus should be 0 before initialization")
	assert_almost_eq(system.fire_rate_bonus, 0.0, 0.001,
		"Fire rate bonus should be 0 before initialization")


# ============================================================================
# On-Hit Penalty Tests
# ============================================================================


func test_combat_disposition_damage_penalty_on_first_hit() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	system.apply_hit_penalty()
	assert_almost_eq(system.damage_bonus, -5.23, 0.001,
		"After 1 hit: damage bonus should be 0.77 - 6.0 = -5.23")


func test_combat_disposition_fire_rate_penalty_on_first_hit() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	system.apply_hit_penalty()
	assert_almost_eq(system.fire_rate_bonus, -6.1, 0.001,
		"After 1 hit: fire rate bonus should be 1.1 - 7.2 = -6.1")


func test_combat_disposition_penalty_not_applied_on_second_hit() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	system.apply_hit_penalty()
	system.apply_hit_penalty()  # second call — should be ignored
	assert_almost_eq(system.damage_bonus, -5.23, 0.001,
		"After 2 hits: penalty applied only once, damage bonus should still be 0.77 - 6.0 = -5.23")


func test_combat_disposition_fire_rate_penalty_not_applied_on_second_hit() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	system.apply_hit_penalty()
	system.apply_hit_penalty()  # second call — should be ignored
	assert_almost_eq(system.fire_rate_bonus, -6.1, 0.001,
		"After 2 hits: penalty applied only once, fire rate bonus should still be 1.1 - 7.2 = -6.1")


func test_combat_disposition_hit_penalty_not_applied_when_inactive() -> void:
	var system := MockCombatDispositionSystem.new()
	# Do NOT call init - system is not active
	system.apply_hit_penalty()
	assert_almost_eq(system.damage_bonus, 0.0, 0.001,
		"Hit penalty should not apply when combat disposition is not active")
	assert_almost_eq(system.fire_rate_bonus, 0.0, 0.001,
		"Fire rate penalty should not apply when combat disposition is not active")


func test_combat_disposition_effective_damage_after_hit() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	system.apply_hit_penalty()
	var base_damage := 10.0
	var effective := system.get_effective_damage(base_damage)
	# 10.0 + (0.77 - 6.0) = 10.0 - 5.23 = 4.77
	assert_almost_eq(effective, 4.77, 0.001,
		"After 1 hit: effective damage should decrease")


func test_combat_disposition_effective_fire_rate_floored_above_minimum() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	# Apply penalty (only first call has effect)
	system.apply_hit_penalty()
	# After penalty: fire_rate_bonus = 1.1 - 7.2 = -6.1
	# With a low base rate of 0.1, effective = max(0.1 + (-6.1), 0.1) = max(-6.0, 0.1) = 0.1
	var base_fire_rate := 0.1
	var effective := system.get_effective_fire_rate(base_fire_rate)
	assert_true(effective >= 0.1,
		"Effective fire rate should never go below minimum 0.1 (to prevent division by zero)")


# ============================================================================
# Penalty Applied Once Tests
# ============================================================================


func test_combat_disposition_penalty_not_applied_before_first_hit() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	assert_false(system.penalty_applied,
		"penalty_applied should be false before any hit is taken")


func test_combat_disposition_penalty_applied_after_first_hit() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	system.apply_hit_penalty()
	assert_true(system.penalty_applied,
		"penalty_applied should be true after the first hit")


func test_combat_disposition_penalty_flag_remains_true_after_multiple_hits() -> void:
	var system := MockCombatDispositionSystem.new()
	system.init_combat_disposition()
	system.apply_hit_penalty()
	system.apply_hit_penalty()
	system.apply_hit_penalty()
	assert_true(system.penalty_applied,
		"penalty_applied should remain true after multiple hits")
	# Bonuses should only have been reduced once
	assert_almost_eq(system.damage_bonus, -5.23, 0.001,
		"Damage bonus should only decrease once regardless of hit count")
	assert_almost_eq(system.fire_rate_bonus, -6.1, 0.001,
		"Fire rate bonus should only decrease once regardless of hit count")


func test_combat_disposition_penalty_not_applied_when_inactive() -> void:
	var system := MockCombatDispositionSystem.new()
	# Not initialized — inactive
	system.apply_hit_penalty()
	assert_false(system.penalty_applied,
		"penalty_applied should remain false when system is not active")


# ============================================================================
# Mutual Exclusion Tests
# ============================================================================


func test_combat_disposition_does_not_conflict_with_flashlight() -> void:
	manager.set_active_item(manager.ActiveItemType.COMBAT_DISPOSITION)
	assert_false(manager.has_flashlight(),
		"Flashlight should not be active when Combat Disposition is selected")
	assert_true(manager.has_combat_disposition(),
		"Combat Disposition should be active")


func test_flashlight_does_not_conflict_with_combat_disposition() -> void:
	manager.set_active_item(manager.ActiveItemType.FLASHLIGHT)
	assert_true(manager.has_flashlight(),
		"Flashlight should be active")
	assert_false(manager.has_combat_disposition(),
		"Combat Disposition should not be active when Flashlight is selected")


func test_combat_disposition_does_not_conflict_with_breaker_bullets() -> void:
	manager.set_active_item(manager.ActiveItemType.COMBAT_DISPOSITION)
	assert_false(manager.has_breaker_bullets(),
		"Breaker Bullets should not be active when Combat Disposition is selected")
	assert_true(manager.has_combat_disposition(),
		"Combat Disposition should be active")


func test_combat_disposition_does_not_conflict_with_laser_sight() -> void:
	manager.set_active_item(manager.ActiveItemType.COMBAT_DISPOSITION)
	assert_false(manager.has_laser_sight(),
		"Laser Sight should not be active when Combat Disposition is selected")
	assert_true(manager.has_combat_disposition(),
		"Combat Disposition should be active")


# ============================================================================
# All Items Count Tests
# ============================================================================


func test_total_active_items_includes_combat_disposition() -> void:
	var all_types := manager.get_all_active_item_types()
	assert_true(manager.ActiveItemType.COMBAT_DISPOSITION in all_types,
		"All active item types should include COMBAT_DISPOSITION")


func test_active_item_count_is_nineteen() -> void:
	# NONE + 18 items = 19 total (including Extended Magazine, Drilling Bullets, Recoil Compensator, Auto-Reload, Combat Disposition and Experimental Sample)
	var all_types := manager.get_all_active_item_types()
	assert_eq(all_types.size(), 19,
		"Should have 19 active item types total (NONE + 18 items including EXTENDED_MAGAZINE, DRILLING_BULLETS, RECOIL_COMPENSATOR, AUTO_RELOAD, COMBAT_DISPOSITION and EXPERIMENTAL_SAMPLE)")


# ============================================================================
# Speed Bonus Tests (Issue #1583)
# ============================================================================


func test_combat_disposition_doubles_speed_on_init_normal_difficulty() -> void:
	var system := MockCombatDispositionSystem.new()
	system.max_speed = 200.0
	system.init_combat_disposition(false)
	assert_almost_eq(system.max_speed, 400.0, 0.001,
		"Normal difficulty: Combat Disposition should double movement speed (200 -> 400)")


func test_combat_disposition_quadruples_speed_on_init_black_metal() -> void:
	var system := MockCombatDispositionSystem.new()
	system.max_speed = 200.0
	system.init_combat_disposition(true)
	assert_almost_eq(system.max_speed, 800.0, 0.001,
		"Black Metal difficulty: Combat Disposition should multiply movement speed by 4 (200 -> 800)")


func test_combat_disposition_speed_bonus_stores_base_speed() -> void:
	var system := MockCombatDispositionSystem.new()
	system.max_speed = 250.0
	system.init_combat_disposition(false)
	assert_almost_eq(system.base_speed, 250.0, 0.001,
		"Base speed should be stored before applying the speed bonus")


func test_combat_disposition_speed_penalty_halves_base_speed_on_first_hit() -> void:
	var system := MockCombatDispositionSystem.new()
	system.max_speed = 200.0
	system.init_combat_disposition(false)
	system.apply_hit_penalty()
	assert_almost_eq(system.max_speed, 100.0, 0.001,
		"After first hit: speed should be base_speed / 2 = 100 (not halved from the boosted value)")


func test_combat_disposition_speed_penalty_not_applied_on_second_hit() -> void:
	var system := MockCombatDispositionSystem.new()
	system.max_speed = 200.0
	system.init_combat_disposition(false)
	system.apply_hit_penalty()
	system.apply_hit_penalty()  # second call — should be ignored
	assert_almost_eq(system.max_speed, 100.0, 0.001,
		"After 2 hits: speed penalty applied only once, max_speed should remain 100")


func test_combat_disposition_speed_penalty_not_applied_when_inactive() -> void:
	var system := MockCombatDispositionSystem.new()
	system.max_speed = 200.0
	# Do NOT call init — system is not active
	system.apply_hit_penalty()
	assert_almost_eq(system.max_speed, 200.0, 0.001,
		"Speed should not change when combat disposition is not active")


func test_combat_disposition_black_metal_speed_penalty_halves_base_speed() -> void:
	var system := MockCombatDispositionSystem.new()
	system.max_speed = 200.0
	system.init_combat_disposition(true)  # Black Metal: 200 * 4 = 800
	system.apply_hit_penalty()
	# penalty = base_speed / 2 = 200 / 2 = 100
	assert_almost_eq(system.max_speed, 100.0, 0.001,
		"Black Metal after first hit: speed should be base_speed / 2 = 100")


func test_combat_disposition_description_mentions_speed() -> void:
	var data := manager.get_active_item_data(manager.ActiveItemType.COMBAT_DISPOSITION)
	var description: String = data.get("description", "")
	assert_true(description.to_lower().contains("speed"),
		"Description should mention movement speed")
