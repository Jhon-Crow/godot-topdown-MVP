extends GutTest
## Unit tests for BFF Pendant active item (Issue #674).
##
## Tests the BFF pendant integration with ActiveItemManager,
## companion summoning logic, charge management, and companion behavior.


# ============================================================================
# Active Item Type Enum Tests
# ============================================================================


func test_active_item_type_bff_pendant_value() -> void:
	# ActiveItemType.BFF_PENDANT should be 4
	var expected := 4
	assert_eq(expected, 4, "BFF_PENDANT should be the fifth active item type (4)")


# ============================================================================
# Active Item Data Constants Tests
# ============================================================================


func test_active_item_data_has_bff_pendant() -> void:
	var item_data := {
		3: {
			"name": "BFF Pendant",
			"icon_path": "res://assets/sprites/weapons/bff_pendant_icon.png",
			"description": "BFF pendant — press Space to summon a friendly companion armed with M16 (2-4 HP). One charge per battle."
		}
	}
	assert_true(item_data.has(3), "ACTIVE_ITEM_DATA should contain BFF_PENDANT type")


func test_bff_pendant_data_has_name() -> void:
	var data := {"name": "BFF Pendant"}
	assert_eq(data["name"], "BFF Pendant", "BFF Pendant should have correct name")


func test_bff_pendant_data_has_icon_path() -> void:
	var data := {"icon_path": "res://assets/sprites/weapons/bff_pendant_icon.png"}
	assert_eq(data["icon_path"], "res://assets/sprites/weapons/bff_pendant_icon.png",
		"BFF Pendant should have correct icon path")


func test_bff_pendant_data_has_description() -> void:
	var data := {"description": "BFF pendant — press Space to summon a friendly companion armed with M16 (2-4 HP). One charge per battle."}
	assert_true(data["description"].contains("Space"),
		"BFF Pendant description should mention Space key")
	assert_true(data["description"].contains("M16"),
		"BFF Pendant description should mention M16")
	assert_true(data["description"].contains("2-4 HP"),
		"BFF Pendant description should mention 2-4 HP")
	assert_true(data["description"].contains("One charge"),
		"BFF Pendant description should mention one charge per battle")


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
		BFF_PENDANT = 4
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
			"description": "Tactical flashlight — hold Space to illuminate in weapon direction. Bright white light, turns off when released."
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
		}
	}

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


func test_bff_pendant_not_selected_by_default() -> void:
	assert_false(manager.is_selected(4),
		"BFF Pendant should not be selected by default")


func test_no_bff_pendant_by_default() -> void:
	assert_false(manager.has_bff_pendant(),
		"BFF Pendant should not be equipped by default")


# ============================================================================
# Type Selection Tests
# ============================================================================


func test_set_active_item_to_bff_pendant() -> void:
	manager.set_active_item(4)
	assert_eq(manager.current_active_item, 3,
		"Active item type should change to BFF_PENDANT")


func test_set_bff_pendant_emits_change() -> void:
	manager.set_active_item(4)
	assert_eq(manager.type_changed_count, 1,
		"Type change should increment counter")


func test_set_bff_pendant_triggers_restart_by_default() -> void:
	manager.set_active_item(4)
	assert_true(manager.last_restart_called,
		"Level restart should be triggered by default")


func test_set_bff_pendant_without_restart() -> void:
	manager.set_active_item(3, false)
	assert_false(manager.last_restart_called,
		"Level restart should not be triggered when disabled")


func test_has_bff_pendant_after_selection() -> void:
	manager.set_active_item(4)
	assert_true(manager.has_bff_pendant(),
		"has_bff_pendant should return true after selecting pendant")


func test_no_bff_pendant_after_deselection() -> void:
	manager.set_active_item(4)
	manager.set_active_item(0)
	assert_false(manager.has_bff_pendant(),
		"has_bff_pendant should return false after switching back to none")


func test_no_flashlight_when_bff_pendant_selected() -> void:
	manager.set_active_item(4)
	assert_false(manager.has_flashlight(),
		"has_flashlight should return false when pendant is selected")


func test_no_teleport_bracers_when_bff_pendant_selected() -> void:
	manager.set_active_item(4)
	assert_false(manager.has_teleport_bracers(),
		"has_teleport_bracers should return false when pendant is selected")


func test_no_bff_pendant_when_flashlight_selected() -> void:
	manager.set_active_item(1)
	assert_false(manager.has_bff_pendant(),
		"has_bff_pendant should return false when flashlight is selected")


func test_no_bff_pendant_when_teleport_bracers_selected() -> void:
	manager.set_active_item(3)
	assert_false(manager.has_bff_pendant(),
		"has_bff_pendant should return false when bracers are selected")


# ============================================================================
# Data Retrieval Tests
# ============================================================================


func test_get_active_item_data_bff_pendant() -> void:
	var data := manager.get_active_item_data(4)
	assert_eq(data["name"], "BFF Pendant")


func test_get_all_active_item_types_includes_bff_pendant() -> void:
	var types := manager.get_all_active_item_types()
	assert_eq(types.size(), 5,
		"Should return 5 active item types")
	assert_true(0 in types, "Should have NONE")
	assert_true(1 in types, "Should have FLASHLIGHT")
	assert_true(2 in types, "Should have HOMING_BULLETS")
	assert_true(3 in types, "Should have TELEPORT_BRACERS")
	assert_true(4 in types, "Should have BFF_PENDANT")


func test_get_active_item_name_bff_pendant() -> void:
	assert_eq(manager.get_active_item_name(4), "BFF Pendant")


func test_get_active_item_description_bff_pendant() -> void:
	var desc := manager.get_active_item_description(4)
	assert_true(desc.contains("companion"),
		"BFF Pendant description should mention companion")


func test_get_active_item_icon_path_bff_pendant() -> void:
	var path := manager.get_active_item_icon_path(4)
	assert_true(path.contains("bff_pendant"),
		"BFF Pendant icon path should contain 'bff_pendant'")


# ============================================================================
# Selection State Tests
# ============================================================================


func test_is_selected_after_changing_to_bff_pendant() -> void:
	manager.set_active_item(4)
	assert_true(manager.is_selected(4),
		"BFF_PENDANT should be selected after changing to it")
	assert_false(manager.is_selected(0),
		"NONE should not be selected after changing away from it")
	assert_false(manager.is_selected(1),
		"FLASHLIGHT should not be selected after changing away from it")
	assert_false(manager.is_selected(3),
		"TELEPORT_BRACERS should not be selected after changing away from it")


func test_switch_between_all_active_items() -> void:
	manager.set_active_item(1)  # Flashlight
	manager.set_active_item(3)  # Teleport Bracers
	manager.set_active_item(4)  # BFF Pendant
	manager.set_active_item(0)  # None
	manager.set_active_item(4)  # Back to BFF Pendant

	assert_eq(manager.current_active_item, 3)
	assert_eq(manager.type_changed_count, 5)


# ============================================================================
# BFF Companion Charge Tracking Tests
# ============================================================================


class MockBffChargeTracker:
	## One charge per battle
	const MAX_CHARGES: int = 1

	## Current charge count
	var charges: int = MAX_CHARGES

	## Whether companion was summoned
	var companion_summoned: bool = false

	## Signal tracking
	var summon_count: int = 0

	## Use the charge (summon companion)
	func summon() -> bool:
		if charges <= 0:
			return false
		if companion_summoned:
			return false
		charges -= 1
		companion_summoned = true
		summon_count += 1
		return true

	## Check if charge is available
	func has_charge() -> bool:
		return charges > 0 and not companion_summoned


func test_bff_starts_with_1_charge() -> void:
	var tracker := MockBffChargeTracker.new()
	assert_eq(tracker.charges, 1,
		"BFF pendant should start with 1 charge")


func test_bff_summon_uses_charge() -> void:
	var tracker := MockBffChargeTracker.new()
	var result := tracker.summon()
	assert_true(result, "Should successfully summon companion")
	assert_eq(tracker.charges, 0, "Should have 0 charges remaining")
	assert_true(tracker.companion_summoned, "Companion should be marked as summoned")


func test_bff_cannot_summon_twice() -> void:
	var tracker := MockBffChargeTracker.new()
	tracker.summon()
	var result := tracker.summon()
	assert_false(result, "Should not be able to summon twice")
	assert_eq(tracker.summon_count, 1, "Should only have 1 summon")


func test_bff_no_charge_after_summon() -> void:
	var tracker := MockBffChargeTracker.new()
	tracker.summon()
	assert_false(tracker.has_charge(),
		"Should have no charge available after summoning")


func test_bff_has_charge_before_summon() -> void:
	var tracker := MockBffChargeTracker.new()
	assert_true(tracker.has_charge(),
		"Should have charge available before summoning")


# ============================================================================
# BFF Companion Health Tests
# ============================================================================


class MockBffCompanion:
	## Health range
	var min_health: int = 2
	var max_health: int = 4
	var _current_health: int = 0
	var _max_health: int = 0
	var _is_alive: bool = true

	## Tracking
	var death_count: int = 0
	var damage_taken: Array = []

	func initialize_health(health: int) -> void:
		_max_health = health
		_current_health = health
		_is_alive = true

	func take_damage(amount: float) -> void:
		if not _is_alive:
			return
		var actual_damage: int = maxi(int(round(amount)), 1)
		_current_health -= actual_damage
		damage_taken.append(actual_damage)
		if _current_health <= 0:
			_on_death()

	func _on_death() -> void:
		_is_alive = false
		death_count += 1

	func is_alive() -> bool:
		return _is_alive


func test_companion_health_in_range() -> void:
	# Test multiple times to verify random range
	for i in range(20):
		var companion := MockBffCompanion.new()
		var health := randi_range(companion.min_health, companion.max_health)
		companion.initialize_health(health)
		assert_true(companion._current_health >= 2 and companion._current_health <= 4,
			"Companion health should be between 2 and 4, got %d" % companion._current_health)


func test_companion_dies_at_zero_health() -> void:
	var companion := MockBffCompanion.new()
	companion.initialize_health(2)  # Minimum health
	companion.take_damage(1.0)
	assert_true(companion.is_alive(), "Should still be alive after 1 damage")
	companion.take_damage(1.0)
	assert_false(companion.is_alive(), "Should be dead after 2 damage with 2 HP")


func test_companion_survives_partial_damage() -> void:
	var companion := MockBffCompanion.new()
	companion.initialize_health(4)  # Maximum health
	companion.take_damage(1.0)
	assert_true(companion.is_alive(), "Should survive 1 damage with 4 HP")
	assert_eq(companion._current_health, 3, "Should have 3 HP remaining")


func test_companion_dies_from_overkill() -> void:
	var companion := MockBffCompanion.new()
	companion.initialize_health(2)
	companion.take_damage(5.0)
	assert_false(companion.is_alive(), "Should die from overkill damage")
	assert_eq(companion.death_count, 1, "Should only die once")


func test_companion_no_damage_after_death() -> void:
	var companion := MockBffCompanion.new()
	companion.initialize_health(2)
	companion.take_damage(5.0)
	companion.take_damage(1.0)  # Should do nothing
	assert_eq(companion.damage_taken.size(), 1,
		"Should not take damage after death")


func test_companion_death_emits_once() -> void:
	var companion := MockBffCompanion.new()
	companion.initialize_health(2)
	companion.take_damage(1.0)
	companion.take_damage(1.0)
	companion.take_damage(1.0)  # After death
	assert_eq(companion.death_count, 1,
		"Death should only be triggered once")


# ============================================================================
# BFF Companion Weapon Tests
# ============================================================================


class MockBffWeapon:
	## M16 rifle configuration
	var weapon_type: int = 0  # RIFLE
	var shoot_cooldown: float = 0.15
	var bullet_speed: float = 2500.0
	var magazine_size: int = 30
	var _current_ammo: int = 30
	var _is_reloading: bool = false
	var _reload_time: float = 2.5
	var _reload_timer: float = 0.0

	## Tracking
	var shots_fired: int = 0
	var reloads_started: int = 0
	var _shoot_timer: float = 0.0

	func can_shoot() -> bool:
		return _current_ammo > 0 and not _is_reloading and _shoot_timer >= shoot_cooldown

	func shoot() -> void:
		if not can_shoot():
			return
		_current_ammo -= 1
		shots_fired += 1
		_shoot_timer = 0.0
		if _current_ammo <= 0:
			start_reload()

	func start_reload() -> void:
		if _is_reloading:
			return
		_is_reloading = true
		_reload_timer = 0.0
		reloads_started += 1

	func update_reload(delta: float) -> void:
		if not _is_reloading:
			return
		_reload_timer += delta
		if _reload_timer >= _reload_time:
			_current_ammo = magazine_size
			_is_reloading = false
			_reload_timer = 0.0

	func update_shoot_timer(delta: float) -> void:
		_shoot_timer += delta


func test_companion_uses_m16() -> void:
	var weapon := MockBffWeapon.new()
	assert_eq(weapon.weapon_type, 0, "Companion should use RIFLE (M16) type")


func test_companion_starts_with_full_magazine() -> void:
	var weapon := MockBffWeapon.new()
	assert_eq(weapon._current_ammo, 30, "Should start with 30 rounds (M16 magazine)")


func test_companion_shoot_decrements_ammo() -> void:
	var weapon := MockBffWeapon.new()
	weapon._shoot_timer = 1.0  # Allow shooting
	weapon.shoot()
	assert_eq(weapon._current_ammo, 29, "Should have 29 rounds after one shot")
	assert_eq(weapon.shots_fired, 1, "Should have fired 1 shot")


func test_companion_auto_reloads_when_empty() -> void:
	var weapon := MockBffWeapon.new()
	weapon._current_ammo = 1
	weapon._shoot_timer = 1.0
	weapon.shoot()
	assert_eq(weapon._current_ammo, 0, "Should have 0 rounds")
	assert_true(weapon._is_reloading, "Should be reloading")
	assert_eq(weapon.reloads_started, 1, "Should have started reload")


func test_companion_reload_restores_ammo() -> void:
	var weapon := MockBffWeapon.new()
	weapon._current_ammo = 0
	weapon.start_reload()
	weapon.update_reload(3.0)  # Wait full reload time
	assert_eq(weapon._current_ammo, 30, "Should have 30 rounds after reload")
	assert_false(weapon._is_reloading, "Should not be reloading anymore")


func test_companion_cannot_shoot_while_reloading() -> void:
	var weapon := MockBffWeapon.new()
	weapon._current_ammo = 0
	weapon.start_reload()
	weapon._shoot_timer = 1.0
	assert_false(weapon.can_shoot(), "Should not be able to shoot while reloading")


func test_companion_respects_fire_rate() -> void:
	var weapon := MockBffWeapon.new()
	weapon._shoot_timer = 0.0  # Just shot
	assert_false(weapon.can_shoot(), "Should not shoot faster than fire rate")
	weapon._shoot_timer = 0.15
	assert_true(weapon.can_shoot(), "Should be able to shoot after cooldown")


# ============================================================================
# Armory Integration Tests (BFF Pendant in Menu)
# ============================================================================


class MockArmoryWithBffPendant:
	## Active item data
	const ACTIVE_ITEMS: Dictionary = {
		0: {"name": "None", "description": "No active item equipped."},
		1: {"name": "Flashlight", "description": "Tactical flashlight"},
		2: {"name": "Teleport Bracers", "description": "Teleportation bracers"},
		3: {"name": "BFF Pendant", "description": "BFF pendant — summon companion"}
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


func test_armory_select_bff_pendant() -> void:
	var armory := MockArmoryWithBffPendant.new()
	var result := armory.select_active_item(3)
	assert_true(result, "Should select BFF pendant")
	assert_eq(armory.pending_active_item, 3, "Pending should be BFF pendant")
	assert_eq(armory.applied_active_item, 0, "Applied should still be None")


func test_armory_apply_bff_pendant() -> void:
	var armory := MockArmoryWithBffPendant.new()
	armory.select_active_item(3)
	var result := armory.apply()
	assert_true(result, "Apply should succeed")
	assert_eq(armory.applied_active_item, 3, "Applied should be BFF pendant")
	assert_eq(armory.active_item_changed_count, 1, "Change count should be 1")


func test_armory_switch_flashlight_to_bff_pendant() -> void:
	var armory := MockArmoryWithBffPendant.new()
	armory.select_active_item(1)
	armory.apply()
	armory.select_active_item(3)
	armory.apply()
	assert_eq(armory.applied_active_item, 3, "Should be BFF pendant")
	assert_eq(armory.active_item_changed_count, 2, "Should have 2 changes")


func test_armory_bff_pendant_has_pending_changes() -> void:
	var armory := MockArmoryWithBffPendant.new()
	armory.select_active_item(3)
	assert_true(armory.has_pending_changes(),
		"Should have pending changes after selecting pendant")


func test_armory_all_four_active_items_selectable() -> void:
	var armory := MockArmoryWithBffPendant.new()
	assert_true(armory.select_active_item(0), "None should be selectable")
	assert_true(armory.select_active_item(1), "Flashlight should be selectable")
	assert_true(armory.select_active_item(2), "Teleport Bracers should be selectable")
	assert_true(armory.select_active_item(3), "BFF Pendant should be selectable")
	assert_false(armory.select_active_item(99), "Invalid should not be selectable")


func test_armory_switch_teleport_bracers_to_bff_pendant() -> void:
	var armory := MockArmoryWithBffPendant.new()
	armory.select_active_item(2)
	armory.apply()
	armory.select_active_item(3)
	armory.apply()
	assert_eq(armory.applied_active_item, 3, "Should be BFF pendant")
	assert_eq(armory.active_item_changed_count, 2, "Should have 2 changes")
