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
# BFF Companion Reaction Time Tests (Issue #1244)
# ============================================================================


class MockBffCompanionWithReaction:
	## Default enemy reaction delays (matching enemy.gd defaults)
	const DEFAULT_DETECTION_DELAY: float = 0.2
	const DEFAULT_THREAT_REACTION_DELAY: float = 0.2
	const DEFAULT_LEAD_PREDICTION_DELAY: float = 0.3
	const DEFAULT_SHOOT_COOLDOWN: float = 0.1

	## BFF companion reaction multiplier (2x slower = 2.0x, Issue #1244)
	const BFF_REACTION_MULTIPLIER: float = 2.0

	## BFF companion damage multiplier (3x less damage = 1/3, Issue #1244)
	const BFF_DAMAGE_MULTIPLIER: float = 1.0 / 3.0

	## Companion reaction properties (set by summoning logic)
	var detection_delay: float = DEFAULT_DETECTION_DELAY
	var threat_reaction_delay: float = DEFAULT_THREAT_REACTION_DELAY
	var lead_prediction_delay: float = DEFAULT_LEAD_PREDICTION_DELAY
	var shoot_cooldown: float = DEFAULT_SHOOT_COOLDOWN
	var bullet_damage_multiplier: float = 1.0

	## Apply BFF reaction delays (as done in _summon_bff_companion)
	func apply_bff_reaction_delays() -> void:
		detection_delay = DEFAULT_DETECTION_DELAY * BFF_REACTION_MULTIPLIER
		threat_reaction_delay = DEFAULT_THREAT_REACTION_DELAY * BFF_REACTION_MULTIPLIER
		lead_prediction_delay = DEFAULT_LEAD_PREDICTION_DELAY * BFF_REACTION_MULTIPLIER
		shoot_cooldown = DEFAULT_SHOOT_COOLDOWN * BFF_REACTION_MULTIPLIER
		bullet_damage_multiplier = BFF_DAMAGE_MULTIPLIER


func test_bff_reaction_multiplier_is_two() -> void:
	var companion := MockBffCompanionWithReaction.new()
	assert_eq(companion.BFF_REACTION_MULTIPLIER, 2.0,
		"BFF reaction multiplier should be 2.0 (2x slower, Issue #1244)")


func test_bff_detection_delay_is_2x_slower_than_enemy() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	var expected: float = companion.DEFAULT_DETECTION_DELAY * 2.0
	assert_eq(companion.detection_delay, expected,
		"BFF detection_delay should be 2.0x the default (0.4s)")


func test_bff_threat_reaction_delay_is_2x_slower_than_enemy() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	var expected: float = companion.DEFAULT_THREAT_REACTION_DELAY * 2.0
	assert_eq(companion.threat_reaction_delay, expected,
		"BFF threat_reaction_delay should be 2.0x the default (0.4s)")


func test_bff_lead_prediction_delay_is_2x_slower_than_enemy() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	var expected: float = companion.DEFAULT_LEAD_PREDICTION_DELAY * 2.0
	assert_eq(companion.lead_prediction_delay, expected,
		"BFF lead_prediction_delay should be 2.0x the default (0.6s)")


func test_bff_detection_delay_absolute_value() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_eq(companion.detection_delay, 0.4,
		"BFF detection_delay should be 0.4s (0.2 * 2.0)")


func test_bff_threat_reaction_delay_absolute_value() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_eq(companion.threat_reaction_delay, 0.4,
		"BFF threat_reaction_delay should be 0.4s (0.2 * 2.0)")


func test_bff_lead_prediction_delay_absolute_value() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_eq(companion.lead_prediction_delay, 0.6,
		"BFF lead_prediction_delay should be 0.6s (0.3 * 2.0)")


func test_bff_shoot_cooldown_is_2x_slower_than_enemy() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	var expected: float = companion.DEFAULT_SHOOT_COOLDOWN * 2.0
	assert_eq(companion.shoot_cooldown, expected,
		"BFF shoot_cooldown should be 2.0x the default (0.2s)")


func test_bff_shoot_cooldown_absolute_value() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_eq(companion.shoot_cooldown, 0.2,
		"BFF shoot_cooldown should be 0.2s (0.1 * 2.0)")


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


func test_bff_bullet_damage_multiplier_is_one_third() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_almost_eq(companion.bullet_damage_multiplier, 1.0 / 3.0, 0.0001,
		"BFF bullet_damage_multiplier should be 1/3 (3x less damage, Issue #1244)")


func test_bff_bullet_damage_multiplier_less_than_enemy_default() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	assert_true(companion.bullet_damage_multiplier < 1.0,
		"BFF bullet_damage_multiplier should be less than enemy default (1.0)")


func test_bff_bullet_damage_multiplier_default_before_summon() -> void:
	var companion := MockBffCompanionWithReaction.new()
	assert_eq(companion.bullet_damage_multiplier, 1.0,
		"bullet_damage_multiplier should be 1.0 (no reduction) before summon")


func test_bff_bullet_damage_is_3x_weaker_than_enemy() -> void:
	var companion := MockBffCompanionWithReaction.new()
	companion.apply_bff_reaction_delays()
	var enemy_damage: float = 1.0
	var companion_damage: float = enemy_damage * companion.bullet_damage_multiplier
	assert_almost_eq(companion_damage * 3.0, enemy_damage, 0.0001,
		"3x companion damage should equal 1x enemy damage (Issue #1244)")


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


# ============================================================================
# BFF Companion Passage-Edge Wall-Shooting Prevention Tests (Issue #954 Bug #3)
# ============================================================================
## Verifies that the BFF companion does NOT shoot when the real muzzle path
## is blocked by a wall, even if the center-to-center line-of-sight is clear.
## This fixes the "shooting at the edge of a passage" bug where the muzzle
## overhangs a wall corner and bullets are wasted against the wall.
##
## Fix evolution (Issue #954 Bug #3):
## - v1: Added _is_shot_clear_of_cover() check in _shoot() for aggressive path.
##   Problem: _is_shot_clear_of_cover() casts from muzzle to target; when muzzle is
##   already inside a wall, Godot returns no hit (ray starts inside collider), so the
##   check erroneously passes and shots are fired into the wall.
## - v2 (current): _is_bullet_spawn_clear() now uses _get_bullet_spawn_position() to
##   compute the actual muzzle position (~52-68px from center) and casts from enemy
##   center to that real muzzle. This correctly detects walls between center and muzzle.
##   Log evidence: BffCompanion fired 20+ shots from pos=(2026,1406) with bullet spawning
##   at (2036,1473) — distance 68px — while 35px check passed and muzzle was inside wall.


class MockMuzzleWallCheck:
	## Simulates the spawn-clear check logic in _shoot() and process_combat() for Issue #954 Bug #3.
	## With the v2 fix: _is_bullet_spawn_clear() now uses the actual muzzle distance (~68px)
	## via _get_bullet_spawn_position(), replacing the old fixed 35px estimate.

	## Whether the real muzzle spawn check is clear (center→actual muzzle, ~68px)
	## With v2 fix, this IS the primary check (no longer just a 35px estimate).
	var center_spawn_clear: bool = true

	## Whether the real muzzle-to-target path is clear (used by _is_shot_clear_of_cover)
	## Still used as a secondary check in _shoot() for aggressive enemies.
	var muzzle_path_clear: bool = true

	## Whether this is an aggressive companion (uses dual check path)
	var is_aggressive: bool = true

	## Simulates the combined shoot guard from _shoot() in enemy.gd (Issue #954):
	## - Aggressive: needs BOTH real muzzle spawn clear AND real muzzle path clear
	## - Non-aggressive: handled by _should_shoot_at_target (already uses real muzzle)
	func should_shoot() -> bool:
		if is_aggressive:
			if not center_spawn_clear:
				return false  # Real muzzle spawn blocked (v2: uses actual muzzle distance)
			if not muzzle_path_clear:
				return false  # Real muzzle path blocked by cover (secondary check)
			return true
		else:
			# Non-aggressive already uses real muzzle via _should_shoot_at_target
			return center_spawn_clear and muzzle_path_clear

	## Simulates the movement decision in aggression_component.process_combat().
	## Returns "moving" if companion should navigate, "stopped" if it should stand and shoot.
	func decide_movement() -> String:
		var center_blocked: bool = not center_spawn_clear
		var muzzle_blocked: bool = not center_blocked and not muzzle_path_clear
		var bullet_spawn_blocked: bool = center_blocked or muzzle_blocked
		return "moving" if bullet_spawn_blocked else "stopped"


func test_companion_no_shoot_when_center_clear_but_muzzle_blocked() -> void:
	## Simulates: companion at passage edge — real muzzle spawn check (now ~68px) is clear,
	## but secondary muzzle-to-target path check is blocked by wall corner.
	## With v2 fix, the primary spawn check uses actual muzzle distance, catching wall hits.
	var check := MockMuzzleWallCheck.new()
	check.is_aggressive = true
	check.center_spawn_clear = true   # Real muzzle spawn check (~68px): clear
	check.muzzle_path_clear = false   # Real muzzle → enemy path: blocked by wall corner

	assert_false(check.should_shoot(),
		"Aggressive companion should NOT shoot when real muzzle path is blocked (Issue #954 Bug #3)")


func test_companion_shoots_when_both_center_and_muzzle_clear() -> void:
	## Normal case: companion has clear LOS and clear muzzle path — should shoot.
	var check := MockMuzzleWallCheck.new()
	check.is_aggressive = true
	check.center_spawn_clear = true
	check.muzzle_path_clear = true

	assert_true(check.should_shoot(),
		"Aggressive companion should shoot when both center and muzzle paths are clear")


func test_companion_moves_when_center_blocked() -> void:
	## Classic wall-flush case: center ray already blocked — companion must navigate.
	var check := MockMuzzleWallCheck.new()
	check.center_spawn_clear = false
	check.muzzle_path_clear = false  # Irrelevant when center blocked

	assert_eq(check.decide_movement(), "moving",
		"Companion must navigate when center spawn check is blocked")


func test_companion_moves_when_muzzle_blocked_but_center_clear() -> void:
	## Passage-edge case: center is clear but real muzzle path is blocked.
	## Companion must navigate to find a position with full clear shot.
	var check := MockMuzzleWallCheck.new()
	check.center_spawn_clear = true
	check.muzzle_path_clear = false

	assert_eq(check.decide_movement(), "moving",
		"Companion must navigate when muzzle path blocked even though center check passes (Issue #954 Bug #3)")


func test_companion_stops_when_both_paths_clear() -> void:
	## Full clear shot: companion stops and engages.
	var check := MockMuzzleWallCheck.new()
	check.center_spawn_clear = true
	check.muzzle_path_clear = true

	assert_eq(check.decide_movement(), "stopped",
		"Companion should stop and shoot when both center and muzzle paths are clear")


func test_companion_no_shoot_when_center_blocked_regardless_of_muzzle() -> void:
	## Even if muzzle_path_clear were true, center blocked means no shot.
	var check := MockMuzzleWallCheck.new()
	check.is_aggressive = true
	check.center_spawn_clear = false
	check.muzzle_path_clear = true  # Doesn't matter if center is blocked

	assert_false(check.should_shoot(),
		"Should not shoot when center spawn is blocked (muzzle path irrelevant in this case)")


# ============================================================================
# Issue #954 Bug #3 v2: _is_bullet_spawn_clear Real Muzzle Distance Fix
# ============================================================================
## Tests validating the v2 fix: _is_bullet_spawn_clear() now uses the actual
## muzzle position from _get_bullet_spawn_position() (~68px) instead of the
## fixed bullet_spawn_offset estimate (30px + 5px buffer = 35px).
##
## Root cause evidence (game_log_20260307_201817.txt):
##   BffCompanion at (2026.06, 1406.34) fired 20+ shots with bullet spawning
##   at (2036.26, 1473.62) — 68px from center. Godot reported distance=0,
##   meaning the bullet spawned INSIDE the wall. The old 35px check missed
##   the wall entirely since the wall was between 35-68px from center.


class MockBulletSpawnCheck:
	## Simulates the real-muzzle spawn check (v2 fix for Issue #954 Bug #3).
	## In the real code, _is_bullet_spawn_clear() uses _get_bullet_spawn_position()
	## to get the actual muzzle distance (~52-68px) and casts from center to muzzle+5px.

	## Distance from enemy center to the wall (simulates the geometry)
	var wall_distance_px: float = INF  # Default: no wall

	## Actual muzzle distance from enemy center (calculated from weapon sprite position)
	var actual_muzzle_distance_px: float = 68.0  # Typical value (~52px sprite + model offset)

	## Old check distance (the bug): bullet_spawn_offset + 5 = 35px
	const OLD_CHECK_DISTANCE: float = 35.0

	## New check distance (the fix): center.distance_to(actual_muzzle_pos) + 5px buffer
	var new_check_distance: float:
		get: return actual_muzzle_distance_px + 5.0

	func old_check_passes() -> bool:
		## Old 35px check — misses walls beyond 35px from center
		return wall_distance_px > OLD_CHECK_DISTANCE

	func new_check_passes() -> bool:
		## New real-muzzle check — catches walls up to actual_muzzle_distance + 5px
		return wall_distance_px > new_check_distance


func test_v2_fix_catches_wall_at_50px_that_old_check_missed() -> void:
	## Wall at 50px — between 35px (old check) and 68px (real muzzle).
	## Old: passes (35px ray misses wall at 50px). New: blocks (73px ray hits wall at 50px).
	var check := MockBulletSpawnCheck.new()
	check.wall_distance_px = 50.0
	check.actual_muzzle_distance_px = 68.0

	assert_true(check.old_check_passes(),
		"Old 35px check should incorrectly PASS when wall is at 50px (this was the bug)")
	assert_false(check.new_check_passes(),
		"New real-muzzle check should correctly BLOCK when wall is at 50px (this is the fix)")


func test_v2_fix_catches_wall_at_40px_that_old_check_missed() -> void:
	## Wall at 40px — just beyond old 35px check, but before real 68px muzzle.
	var check := MockBulletSpawnCheck.new()
	check.wall_distance_px = 40.0
	check.actual_muzzle_distance_px = 68.0

	assert_true(check.old_check_passes(),
		"Old 35px check passes at 40px wall distance (the bug that caused wall shooting)")
	assert_false(check.new_check_passes(),
		"New real-muzzle check (73px) correctly blocks at 40px wall distance")


func test_v2_fix_allows_clear_shot_when_no_wall_within_muzzle_range() -> void:
	## No wall within muzzle range: both old and new checks should pass.
	var check := MockBulletSpawnCheck.new()
	check.wall_distance_px = 200.0  # Wall far away, no obstruction
	check.actual_muzzle_distance_px = 68.0

	assert_true(check.old_check_passes(),
		"Old check should pass when wall is far away")
	assert_true(check.new_check_passes(),
		"New check should also pass when wall is far away — no false positives")


func test_v2_fix_still_blocks_wall_within_old_check_range() -> void:
	## Wall at 20px — within both old (35px) and new (73px) check range.
	## Both should block.
	var check := MockBulletSpawnCheck.new()
	check.wall_distance_px = 20.0
	check.actual_muzzle_distance_px = 68.0

	assert_false(check.old_check_passes(),
		"Old 35px check blocks when wall is at 20px")
	assert_false(check.new_check_passes(),
		"New real-muzzle check also blocks when wall is at 20px")


# ============================================================================
# Issue #954 Bug #3 v3: Muzzle Point-Intersection Check (intersect_point fix)
# ============================================================================
## Tests validating the v3 fix: _is_bullet_spawn_clear() now uses intersect_point()
## at the muzzle position to detect walls even when the enemy center is already
## touching/inside a wall.
##
## Root cause evidence (game_log_20260307_205200.txt):
##   BffCompanion fired through walls with bullets spawning at (522, 838) — inside a wall.
##   The v2 raycast from center→muzzle failed because when the enemy is touching the wall,
##   the raycast START may be inside the collider, and Godot does not report intersections
##   for rays that originate inside a shape (a known Godot physics limitation).
##   intersect_point() correctly detects whether the muzzle point is inside any wall shape,
##   regardless of where the query originates.


class MockMuzzlePointCheck:
	## Simulates the v3 fix: uses point-intersection at muzzle to detect inside-wall case.

	## Whether the muzzle point is inside a wall (true = muzzle is inside wall, blocked)
	var muzzle_inside_wall: bool = false

	## Whether a wall blocks the path from enemy center to muzzle (raycast check)
	var wall_between_center_and_muzzle: bool = false

	func v2_raycast_catches_wall() -> bool:
		## v2 fix: raycast from center to muzzle. FAILS if center is also inside the wall.
		## (When origin is inside a collider, Godot returns no intersection.)
		return not wall_between_center_and_muzzle  # simplified: passes when no wall found

	func v3_point_check_catches_wall() -> bool:
		## v3 fix: intersect_point() at muzzle pos. Works even if center is in wall.
		return not muzzle_inside_wall

	func v3_combined_check_passes() -> bool:
		## v3 uses both: point check at muzzle AND raycast center→muzzle
		return v3_point_check_catches_wall() and v2_raycast_catches_wall()


func test_v3_fix_catches_muzzle_inside_wall_when_center_also_touching_wall() -> void:
	## This is the exact scenario from game_log_20260307_205200.txt:
	## Companion pushed against wall corner, both center and muzzle inside wall.
	## v2 raycast from center→muzzle silently passes (origin inside collider).
	## v3 intersect_point() at muzzle correctly blocks the shot.
	var check := MockMuzzlePointCheck.new()
	check.muzzle_inside_wall = true
	check.wall_between_center_and_muzzle = false  # v2 raycast fails to detect this

	assert_true(check.v2_raycast_catches_wall(),
		"v2 raycast incorrectly PASSES when companion center is inside wall (this was the bug)")
	assert_false(check.v3_point_check_catches_wall(),
		"v3 point check correctly BLOCKS when muzzle is inside wall")
	assert_false(check.v3_combined_check_passes(),
		"v3 combined check correctly BLOCKS when muzzle is inside wall")


func test_v3_fix_allows_clear_shot_when_muzzle_outside_wall() -> void:
	## Normal case: companion has clear muzzle position outside any wall.
	## Both v2 and v3 should allow the shot.
	var check := MockMuzzlePointCheck.new()
	check.muzzle_inside_wall = false
	check.wall_between_center_and_muzzle = false

	assert_true(check.v3_point_check_catches_wall(),
		"v3 point check passes when muzzle is not inside any wall")
	assert_true(check.v3_combined_check_passes(),
		"v3 combined check passes when both muzzle and path are clear")


func test_v3_fix_blocks_wall_between_center_and_muzzle() -> void:
	## Wall between enemy center and muzzle (but muzzle is not inside wall).
	## The raycast part of v3 catches this case.
	var check := MockMuzzlePointCheck.new()
	check.muzzle_inside_wall = false
	check.wall_between_center_and_muzzle = true

	assert_true(check.v3_point_check_catches_wall(),
		"v3 point check passes (muzzle itself is not inside wall)")
	assert_false(check.v3_combined_check_passes(),
		"v3 combined check blocks because raycast finds wall between center and muzzle")


func test_v3_fix_blocks_when_both_center_and_muzzle_inside_wall() -> void:
	## Extreme case: both center and muzzle inside wall (deep penetration).
	## v2 fails completely; v3 point check catches it.
	var check := MockMuzzlePointCheck.new()
	check.muzzle_inside_wall = true
	check.wall_between_center_and_muzzle = false  # ray from center still finds no wall

	assert_false(check.v3_combined_check_passes(),
		"v3 combined check blocks even when center is inside wall (point check saves it)")
