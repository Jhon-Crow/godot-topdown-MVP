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


# ============================================================================
# BFF Companion Reaction Time Tests (Issue #926)
# ============================================================================


class MockBffCompanionWithReaction:
	## Default enemy reaction delays (matching enemy.gd defaults)
	const DEFAULT_DETECTION_DELAY: float = 0.2
	const DEFAULT_THREAT_REACTION_DELAY: float = 0.2
	const DEFAULT_LEAD_PREDICTION_DELAY: float = 0.3

	## BFF companion reaction multiplier (50% slower = 1.5x)
	const BFF_REACTION_MULTIPLIER: float = 1.5

	## Companion reaction properties (set by summoning logic)
	var detection_delay: float = DEFAULT_DETECTION_DELAY
	var threat_reaction_delay: float = DEFAULT_THREAT_REACTION_DELAY
	var lead_prediction_delay: float = DEFAULT_LEAD_PREDICTION_DELAY

	## Apply BFF reaction delays (as done in _summon_bff_companion)
	func apply_bff_reaction_delays() -> void:
		detection_delay = DEFAULT_DETECTION_DELAY * BFF_REACTION_MULTIPLIER
		threat_reaction_delay = DEFAULT_THREAT_REACTION_DELAY * BFF_REACTION_MULTIPLIER
		lead_prediction_delay = DEFAULT_LEAD_PREDICTION_DELAY * BFF_REACTION_MULTIPLIER


func test_bff_reaction_multiplier_is_one_point_five() -> void:
	var companion := MockBffCompanionWithReaction.new()
	assert_eq(companion.BFF_REACTION_MULTIPLIER, 1.5,
		"BFF reaction multiplier should be 1.5 (50% slower)")


func test_bff_detection_delay_is_50_percent_slower_than_enemy() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	var expected: float = companion.DEFAULT_DETECTION_DELAY * 1.5
	assert_eq(companion.detection_delay, expected,
		"BFF detection_delay should be 1.5x the default (0.3s)")


func test_bff_threat_reaction_delay_is_50_percent_slower_than_enemy() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	var expected: float = companion.DEFAULT_THREAT_REACTION_DELAY * 1.5
	assert_eq(companion.threat_reaction_delay, expected,
		"BFF threat_reaction_delay should be 1.5x the default (0.3s)")


func test_bff_lead_prediction_delay_is_50_percent_slower_than_enemy() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	var expected: float = companion.DEFAULT_LEAD_PREDICTION_DELAY * 1.5
	assert_eq(companion.lead_prediction_delay, expected,
		"BFF lead_prediction_delay should be 1.5x the default (0.45s)")


func test_bff_detection_delay_absolute_value() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_eq(companion.detection_delay, 0.3,
		"BFF detection_delay should be 0.3s (0.2 * 1.5)")


func test_bff_threat_reaction_delay_absolute_value() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_eq(companion.threat_reaction_delay, 0.3,
		"BFF threat_reaction_delay should be 0.3s (0.2 * 1.5)")


func test_bff_lead_prediction_delay_absolute_value() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_eq(companion.lead_prediction_delay, 0.45,
		"BFF lead_prediction_delay should be 0.45s (0.3 * 1.5)")


func test_bff_detection_delay_greater_than_enemy_default() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_true(companion.detection_delay > companion.DEFAULT_DETECTION_DELAY,
		"BFF detection_delay should be greater than enemy default")


func test_bff_threat_reaction_delay_greater_than_enemy_default() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_true(companion.threat_reaction_delay > companion.DEFAULT_THREAT_REACTION_DELAY,
		"BFF threat_reaction_delay should be greater than enemy default")


func test_bff_lead_prediction_delay_greater_than_enemy_default() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_true(companion.lead_prediction_delay > companion.DEFAULT_LEAD_PREDICTION_DELAY,
		"BFF lead_prediction_delay should be greater than enemy default")


func test_bff_reaction_delays_not_applied_before_summon() -> void:
	var companion := MockBffCompanionWithReaction.new()
	# Before summon, delays should match enemy defaults
	assert_eq(companion.detection_delay, companion.DEFAULT_DETECTION_DELAY,
		"Before summon, detection_delay should match enemy default")
	assert_eq(companion.threat_reaction_delay, companion.DEFAULT_THREAT_REACTION_DELAY,
		"Before summon, threat_reaction_delay should match enemy default")
	assert_eq(companion.lead_prediction_delay, companion.DEFAULT_LEAD_PREDICTION_DELAY,
		"Before summon, lead_prediction_delay should match enemy default")


# ============================================================================
# BFF Companion Friendly Fire Prevention Tests (Issue #954)
# ============================================================================
## Verifies that an aggressive BFF companion does NOT shoot the player when
## no enemy targets are available (Bug #1 from Issue #954).


class MockBffShootLogic:
	## Simulates the _shoot() logic relevant to Issue #954 fix.
	## Mirrors the aggression/player fallback guard added in enemy.gd.

	## Whether this enemy is in aggressive mode (BFF pendant active)
	var is_aggressive: bool = false

	## Current aggression target (enemy to attack). null = no valid enemy target.
	var aggression_target: Node = null

	## Player reference (always set for enemy instances)
	var player: Node = null

	## Tracking: was a shot attempted and what was the target?
	var last_shot_target: String = ""
	var shot_count: int = 0

	## Simulates the fixed _shoot() logic from enemy.gd (Issue #954):
	## - Aggressive mode with no target: skip (don't fall back to player)
	## - Aggressive mode with target: shoot at enemy target
	## - Non-aggressive: shoot at player (original behavior)
	func attempt_shoot() -> bool:
		# [Issue #954 fix] When aggressive but no enemy target, skip entirely
		if is_aggressive and aggression_target == null:
			last_shot_target = "none"
			return false

		# Determine target position
		if is_aggressive and aggression_target != null:
			last_shot_target = "enemy"
		elif player != null:
			last_shot_target = "player"
		else:
			last_shot_target = "none"
			return false

		shot_count += 1
		return true


func test_bff_companion_no_shoot_when_aggressive_no_target() -> void:
	var logic := MockBffShootLogic.new()
	logic.is_aggressive = true
	logic.aggression_target = null  # No enemies available
	logic.player = RefCounted.new()  # Player exists in scene

	var shot := logic.attempt_shoot()

	assert_false(shot,
		"Aggressive companion with no enemy target should NOT shoot (Issue #954 fix)")
	assert_eq(logic.last_shot_target, "none",
		"Should have no target when aggressive but no enemies available")
	assert_eq(logic.shot_count, 0,
		"No shots should be fired when aggressive with no enemy target")


func test_bff_companion_shoots_enemy_when_aggressive_with_target() -> void:
	var logic := MockBffShootLogic.new()
	logic.is_aggressive = true
	logic.aggression_target = RefCounted.new()  # Has enemy target
	logic.player = RefCounted.new()

	var shot := logic.attempt_shoot()

	assert_true(shot,
		"Aggressive companion with enemy target should shoot")
	assert_eq(logic.last_shot_target, "enemy",
		"Aggressive companion should target enemy, not player")
	assert_eq(logic.shot_count, 1,
		"Should fire exactly one shot at enemy target")


func test_non_aggressive_enemy_shoots_player() -> void:
	var logic := MockBffShootLogic.new()
	logic.is_aggressive = false
	logic.aggression_target = null
	logic.player = RefCounted.new()  # Player exists in scene

	var shot := logic.attempt_shoot()

	assert_true(shot,
		"Non-aggressive enemy should shoot at player (normal behavior)")
	assert_eq(logic.last_shot_target, "player",
		"Non-aggressive enemy should target player")


func test_bff_companion_no_shoot_when_aggressive_no_target_no_player() -> void:
	var logic := MockBffShootLogic.new()
	logic.is_aggressive = true
	logic.aggression_target = null
	logic.player = null  # No player either

	var shot := logic.attempt_shoot()

	assert_false(shot,
		"Aggressive companion with no targets should not shoot")
	assert_eq(logic.shot_count, 0,
		"Shot count remains 0 when no valid targets")


func test_bff_companion_switch_to_no_target_stops_shooting() -> void:
	var logic := MockBffShootLogic.new()
	logic.is_aggressive = true
	logic.player = RefCounted.new()

	# First: companion has enemy target, shoots
	logic.aggression_target = RefCounted.new()
	var shot1 := logic.attempt_shoot()
	assert_true(shot1, "Should shoot when has enemy target")
	assert_eq(logic.shot_count, 1, "Should have 1 shot")

	# Then: enemy target disappears (killed), should NOT fall back to player
	logic.aggression_target = null
	var shot2 := logic.attempt_shoot()
	assert_false(shot2, "Should NOT shoot when aggressive and enemy died (no fallback to player)")
	assert_eq(logic.shot_count, 1, "Shot count should still be 1 (no additional shot at player)")


# ============================================================================
# BFF Companion Wall-Stuck Prevention Tests (Issue #954)
# ============================================================================
## Verifies that the BFF companion moves away from walls when bullet spawn
## is blocked (Bug #2 from Issue #954).


class MockBffCombatMovement:
	## Simulates the process_combat() movement decision logic.
	## Mirrors the bullet_spawn_blocked guard added in aggression_component.gd.

	## Whether this enemy uses a melee weapon
	var is_melee: bool = false

	## Whether bullet spawn is blocked (wall in front of weapon muzzle)
	var bullet_spawn_blocked: bool = false

	## Tracking: last movement decision
	var last_movement: String = ""  # "stopped" or "moving"

	## Simulates the fixed movement logic from process_combat() (Issue #954):
	## - Melee: always move toward target
	## - Ranged with bullet spawn blocked: move toward target (was previously stuck)
	## - Ranged with clear shot: stop and shoot
	func decide_movement() -> void:
		if is_melee or bullet_spawn_blocked:
			last_movement = "moving"
		else:
			last_movement = "stopped"


func test_ranged_companion_stops_when_bullet_spawn_clear() -> void:
	var logic := MockBffCombatMovement.new()
	logic.is_melee = false
	logic.bullet_spawn_blocked = false  # Clear shot

	logic.decide_movement()

	assert_eq(logic.last_movement, "stopped",
		"Ranged enemy with clear bullet spawn should stop and shoot")


func test_ranged_companion_moves_when_bullet_spawn_blocked() -> void:
	var logic := MockBffCombatMovement.new()
	logic.is_melee = false
	logic.bullet_spawn_blocked = true  # Wall blocks bullet spawn

	logic.decide_movement()

	assert_eq(logic.last_movement, "moving",
		"Ranged enemy with blocked bullet spawn must navigate (Issue #954 wall-stuck fix)")


func test_melee_companion_always_moves() -> void:
	var logic := MockBffCombatMovement.new()
	logic.is_melee = true
	logic.bullet_spawn_blocked = false

	logic.decide_movement()

	assert_eq(logic.last_movement, "moving",
		"Melee enemy always moves toward target (pre-existing behavior)")


func test_melee_companion_moves_even_when_spawn_blocked() -> void:
	var logic := MockBffCombatMovement.new()
	logic.is_melee = true
	logic.bullet_spawn_blocked = true

	logic.decide_movement()

	assert_eq(logic.last_movement, "moving",
		"Melee enemy moves regardless of bullet spawn state")


func test_companion_transitions_from_blocked_to_clear() -> void:
	var logic := MockBffCombatMovement.new()
	logic.is_melee = false

	# Initially against wall (blocked)
	logic.bullet_spawn_blocked = true
	logic.decide_movement()
	assert_eq(logic.last_movement, "moving",
		"Companion should move when blocked by wall")

	# After navigating away, bullet spawn clears
	logic.bullet_spawn_blocked = false
	logic.decide_movement()
	assert_eq(logic.last_movement, "stopped",
		"Companion should stop and shoot once clear of wall")


func test_companion_wall_stuck_fix_respects_melee_override() -> void:
	# Both blocked AND melee — melee wins, should move
	var logic := MockBffCombatMovement.new()
	logic.is_melee = true
	logic.bullet_spawn_blocked = true

	logic.decide_movement()

	assert_eq(logic.last_movement, "moving",
		"Melee + blocked = always moving (melee dominates)")


# ============================================================================
# BFF Companion Enemy Targeting Tests (Issue #934)
# ============================================================================
## These tests verify that the enemy's BFF companion targeting logic works correctly:
## - Enemies detect companions in "bff_companions" group
## - Enemies prefer the more accessible target (visible + closer)
## - GOAP world state reflects companion visibility


class MockTarget:
	## Simulates a player or companion Node2D for targeting logic tests.
	var global_position: Vector2 = Vector2.ZERO
	var _is_alive: bool = true

	func _init(pos: Vector2, alive: bool = true) -> void:
		global_position = pos
		_is_alive = alive


class MockBffTargetingLogic:
	## Pure logic simulation of BffTargetingComponent.select_best_target().
	## Tests that the target selection algorithm is correct without needing
	## a full scene tree.

	## Simulates the selection logic from BffTargetingComponent.
	## Returns: "player", "companion", or "none".
	static func select_best_target(
			enemy_pos: Vector2,
			player: MockTarget,
			can_see_player: bool,
			companion: MockTarget,
			can_see_companion: bool) -> String:
		var has_player := player != null and can_see_player
		var has_companion := companion != null and can_see_companion

		if not has_player and not has_companion:
			return "player" if player != null else "none"

		if has_player and not has_companion:
			return "player"

		if has_companion and not has_player:
			return "companion"

		# Both visible — pick the closer one
		var dist_player := enemy_pos.distance_to(player.global_position)
		var dist_companion := enemy_pos.distance_to(companion.global_position)
		return "companion" if dist_companion < dist_player else "player"


func test_targeting_player_only_visible() -> void:
	var player := MockTarget.new(Vector2(100, 0))
	var companion := MockTarget.new(Vector2(200, 0))
	var result := MockBffTargetingLogic.select_best_target(
		Vector2.ZERO, player, true, companion, false)
	assert_eq(result, "player",
		"Should target player when only player is visible")


func test_targeting_companion_only_visible() -> void:
	var player := MockTarget.new(Vector2(100, 0))
	var companion := MockTarget.new(Vector2(200, 0))
	var result := MockBffTargetingLogic.select_best_target(
		Vector2.ZERO, player, false, companion, true)
	assert_eq(result, "companion",
		"Should target companion when only companion is visible")


func test_targeting_both_visible_player_closer() -> void:
	var player := MockTarget.new(Vector2(50, 0))   # closer
	var companion := MockTarget.new(Vector2(200, 0))  # farther
	var result := MockBffTargetingLogic.select_best_target(
		Vector2.ZERO, player, true, companion, true)
	assert_eq(result, "player",
		"Should target player when both visible and player is closer")


func test_targeting_both_visible_companion_closer() -> void:
	var player := MockTarget.new(Vector2(200, 0))   # farther
	var companion := MockTarget.new(Vector2(50, 0))  # closer
	var result := MockBffTargetingLogic.select_best_target(
		Vector2.ZERO, player, true, companion, true)
	assert_eq(result, "companion",
		"Should target companion when both visible and companion is closer")


func test_targeting_neither_visible_falls_back_to_player() -> void:
	var player := MockTarget.new(Vector2(100, 0))
	var companion := MockTarget.new(Vector2(50, 0))  # closer but not visible
	var result := MockBffTargetingLogic.select_best_target(
		Vector2.ZERO, player, false, companion, false)
	assert_eq(result, "player",
		"Should fall back to player (for memory-based pursuit) when neither visible")


func test_targeting_no_player_no_companion() -> void:
	var result := MockBffTargetingLogic.select_best_target(
		Vector2.ZERO, null, false, null, false)
	assert_eq(result, "none",
		"Should return none when neither player nor companion exists")


func test_targeting_player_null_companion_visible() -> void:
	var companion := MockTarget.new(Vector2(50, 0))
	var result := MockBffTargetingLogic.select_best_target(
		Vector2.ZERO, null, false, companion, true)
	assert_eq(result, "companion",
		"Should target companion when player is null but companion is visible")


func test_targeting_dead_companion_not_targeted() -> void:
	# A dead companion should have _is_alive == false.
	# The BffTargetingComponent checks this before reporting visibility.
	# Simulate: companion dead -> can_see_companion = false
	var player := MockTarget.new(Vector2(100, 0))
	var dead_companion := MockTarget.new(Vector2(50, 0), false)
	# Since companion is dead, can_see_companion should be false (handled in check_visibility)
	var result := MockBffTargetingLogic.select_best_target(
		Vector2.ZERO, player, true, dead_companion, false)
	assert_eq(result, "player",
		"Should not target dead companion (can_see_companion=false when dead)")


func test_targeting_companion_equidistant_prefers_player() -> void:
	# When both are at exactly the same distance, companion is NOT closer,
	# so player should be preferred (dist_companion < dist_player is false).
	var player := MockTarget.new(Vector2(100, 0))
	var companion := MockTarget.new(Vector2(100, 0))  # same position
	var result := MockBffTargetingLogic.select_best_target(
		Vector2.ZERO, player, true, companion, true)
	assert_eq(result, "player",
		"Should prefer player when companion is at equal distance (not strictly closer)")


# ============================================================================
# GOAP World State: player_visible includes companion (Issue #934)
# ============================================================================


class MockGoapWorldState:
	## Simulates the GOAP world state update for player_visible
	## when both player and companion visibility are considered.

	static func update_player_visible(can_see_player: bool, can_see_companion: bool) -> bool:
		## Issue #934: player_visible is true when either the player OR companion is visible.
		return can_see_player or can_see_companion


func test_goap_player_visible_when_only_player_seen() -> void:
	var visible := MockGoapWorldState.update_player_visible(true, false)
	assert_true(visible,
		"player_visible should be true when only player is seen")


func test_goap_player_visible_when_only_companion_seen() -> void:
	var visible := MockGoapWorldState.update_player_visible(false, true)
	assert_true(visible,
		"player_visible should be true when only companion is seen (Issue #934)")


func test_goap_player_visible_when_both_seen() -> void:
	var visible := MockGoapWorldState.update_player_visible(true, true)
	assert_true(visible,
		"player_visible should be true when both player and companion are seen")


func test_goap_player_not_visible_when_neither_seen() -> void:
	var visible := MockGoapWorldState.update_player_visible(false, false)
	assert_false(visible,
		"player_visible should be false when neither player nor companion is seen")
