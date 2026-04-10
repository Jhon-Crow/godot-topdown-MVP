extends GutTest
## Unit tests for the Recoil Compensator active item (Issue #1073).
##
## Tests active item registration, charge system, spread suppression,
## screen shake suppression, fire rate boost, and integration with
## the ActiveItemManager mock.


# ============================================================================
# Mock ActiveItemManager (mirrors test_active_item_manager.gd pattern)
# ============================================================================


class MockActiveItemManager:
	## Active item type constants
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
		LOUDSPEAKER = 10,
		BREACHING_CHARGES = 11,
		ARMORED_SKIN = 12,
		AUTO_RELOAD = 13,
		DRILLING_BULLETS = 14,
		RECOIL_COMPENSATOR = 15
	}

	var current_active_item: int = ActiveItemType.NONE

	const ACTIVE_ITEM_DATA: Dictionary = {
		0: {"name": "None", "icon_path": "", "description": "No active item equipped."},
		1: {"name": "Flashlight", "icon_path": "res://assets/sprites/weapons/flashlight_icon.png",
			"description": "Tactical flashlight — hold Space to illuminate in weapon direction. Bright white light, turns off when released.",
			"activation_hint": "Hold Space to activate"},
		2: {"name": "Homing Bullets", "icon_path": "res://assets/sprites/weapons/homing_bullets_icon.png",
			"description": "Press Space to activate — bullets steer toward the nearest enemy (up to 110° turn). 2 charges per battle, each lasts 1.2 seconds."},
		3: {"name": "Teleport Bracers", "icon_path": "res://assets/sprites/weapons/teleport_bracers_icon.png",
			"description": "Teleportation bracers — hold Space to aim, release to teleport. 6 charges, no cooldown. Reticle skips through walls.",
			"activation_hint": "Hold Space to aim, release to teleport"},
		4: {"name": "BFF Pendant", "icon_path": "res://assets/sprites/weapons/bff_pendant_icon.png",
			"description": "BFF pendant — press Space to summon a friendly companion armed with M16 (2-4 HP). One charge per battle.",
			"activation_hint": "Press Space to summon"},
		5: {"name": "Invisibility", "icon_path": "res://assets/sprites/weapons/invisibility_suit_icon.png",
			"description": "Invisibility suit — press Space to cloak (Predator-style ripple). Enemies cannot see you for 4 seconds. 2 charges per battle.",
			"activation_hint": "Press Space to activate"},
		6: {"name": "Breaker Bullets", "icon_path": "res://assets/sprites/weapons/breaker_bullets_icon.png",
			"description": "Breaker bullets — passive: bullets explode 60px before hitting a wall, dealing 1 damage in a 15px radius and releasing shrapnel in a forward cone."},
		7: {"name": "Force Field", "icon_path": "res://assets/sprites/weapons/force_field_icon.png",
			"description": "Force field — hold Space to activate glowing shield. 100% projectile reflection, grenades bounce without detonating. 8 second depletable charge.",
			"activation_hint": "Hold Space to activate"},
		8: {"name": "Trajectory Glasses", "icon_path": "res://assets/sprites/weapons/trajectory_glasses_icon.png",
			"description": "Trajectory glasses — press Space to see ricochet trajectories for 10 seconds. Green laser shows valid ricochets, red shows impossible angles. 2 charges per battle. Passive: ricochet chance is increased by 30% at angles where ricochet is possible (green ray).",
			"activation_hint": "Press Space to activate"},
		9: {"name": "Laser Sight", "icon_path": "res://assets/sprites/weapons/laser_sight_icon.png",
			"description": "Laser sight — passive: adds a purple laser sight to all weapons regardless of difficulty."},
		10: {"name": "Loudspeaker", "icon_path": "res://assets/sprites/weapons/loudspeaker_icon.png",
			"description": "???",
			"activation_hint": "Press Space to activate"},
		11: {"name": "Breaching Charges", "icon_path": "res://assets/sprites/weapons/breaching_charges_icon.png",
			"description": "Breaching charges — hold Space near a wall to place a charge, release to attach it. Press Space to detonate.",
			"activation_hint": "Hold Space near wall to place, press Space to detonate"},
		12: {"name": "Armored Skin", "icon_path": "res://assets/sprites/weapons/armored_skin_icon.png",
			"description": "Armored Skin — passive: +1 HP. When at 2 HP or less and hit, 20 glass shards explode outward in all directions."},
		13: {"name": "Auto-Reload", "icon_path": "res://assets/sprites/weapons/auto_reload_icon.png",
			"description": "Auto-reload — passive: magazine capacity is reduced 2.1x, but the magazine is fully restocked from reserves on each kill."},
		14: {"name": "Drilling Bullets", "icon_path": "res://assets/sprites/weapons/drilling_bullets_icon.png",
			"description": "Drilling bullets — press Space to apply wall-piercing effect to the current magazine. Bullets ignore walls (full damage through walls, no ricochet). One charge per battle."},
		15: {"name": "Recoil Compensator", "icon_path": "res://assets/sprites/weapons/recoil_compensator_icon.png",
			"description": "Recoil compensator — hold Space to eliminate recoil and spread completely, and increase fire rate by 10%. 15 second depletable charge, unlimited activations while charge lasts.",
			"activation_hint": "Hold Space to activate"}
	}

	func set_active_item(type: int, restart_level: bool = true) -> void:
		if type == current_active_item:
			return
		if type not in ACTIVE_ITEM_DATA:
			return
		current_active_item = type

	func get_active_item_data(type: int) -> Dictionary:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]
		return {}

	func get_all_active_item_types() -> Array:
		return ACTIVE_ITEM_DATA.keys()

	func get_active_item_name(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["name"]
		return "Unknown"

	func get_active_item_description(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["description"]
		return ""

	func get_active_item_icon_path(type: int) -> String:
		if type in ACTIVE_ITEM_DATA:
			return ACTIVE_ITEM_DATA[type]["icon_path"]
		return ""

	func is_selected(type: int) -> bool:
		return type == current_active_item

	func has_recoil_compensator() -> bool:
		return current_active_item == ActiveItemType.RECOIL_COMPENSATOR

	func has_flashlight() -> bool:
		return current_active_item == ActiveItemType.FLASHLIGHT

	func has_force_field() -> bool:
		return current_active_item == ActiveItemType.FORCE_FIELD


var manager: MockActiveItemManager


func before_each() -> void:
	manager = MockActiveItemManager.new()


func after_each() -> void:
	manager = null


# ============================================================================
# ActiveItemType Enum Value Tests
# ============================================================================


func test_recoil_compensator_type_value_is_15() -> void:
	assert_eq(MockActiveItemManager.ActiveItemType.RECOIL_COMPENSATOR, 15,
		"RECOIL_COMPENSATOR should be active item type 15 (after DRILLING_BULLETS=14) (Issue #1073)")


func test_recoil_compensator_type_is_distinct_from_laser_sight() -> void:
	assert_ne(MockActiveItemManager.ActiveItemType.RECOIL_COMPENSATOR,
		MockActiveItemManager.ActiveItemType.LASER_SIGHT,
		"RECOIL_COMPENSATOR (15) must differ from LASER_SIGHT (9)")


# ============================================================================
# ACTIVE_ITEM_DATA Registration Tests
# ============================================================================


func test_active_item_data_has_recoil_compensator() -> void:
	var data := manager.get_active_item_data(14)
	assert_false(data.is_empty(),
		"ACTIVE_ITEM_DATA should contain RECOIL_COMPENSATOR (type 14)")


func test_recoil_compensator_name() -> void:
	var data := manager.get_active_item_data(14)
	assert_eq(data["name"], "Recoil Compensator",
		"Recoil Compensator should have correct name")


func test_recoil_compensator_icon_path_contains_recoil() -> void:
	var data := manager.get_active_item_data(14)
	assert_true(data["icon_path"].contains("recoil_compensator"),
		"Recoil Compensator icon path should contain 'recoil_compensator'")


func test_recoil_compensator_description_mentions_space() -> void:
	var data := manager.get_active_item_data(14)
	assert_true(data["description"].contains("Space"),
		"Recoil Compensator description should mention Space key activation")


func test_recoil_compensator_description_mentions_15_seconds() -> void:
	var data := manager.get_active_item_data(14)
	assert_true(data["description"].contains("15"),
		"Recoil Compensator description should mention 15 second charge (Issue #1073)")


func test_recoil_compensator_description_mentions_recoil() -> void:
	var data := manager.get_active_item_data(14)
	assert_true(data["description"].contains("recoil"),
		"Recoil Compensator description should mention recoil suppression")


func test_recoil_compensator_description_mentions_fire_rate_boost() -> void:
	var data := manager.get_active_item_data(14)
	assert_true(data["description"].contains("10%"),
		"Recoil Compensator description should mention 10% fire rate boost (Issue #1073)")


func test_recoil_compensator_has_activation_hint() -> void:
	var data := manager.get_active_item_data(14)
	assert_true(data.has("activation_hint"),
		"Recoil Compensator should have an activation_hint key")
	assert_true(data["activation_hint"].contains("Space"),
		"Recoil Compensator activation hint should mention Space")


func test_get_active_item_name_recoil_compensator() -> void:
	assert_eq(manager.get_active_item_name(14), "Recoil Compensator",
		"get_active_item_name(14) should return 'Recoil Compensator'")


func test_get_active_item_description_recoil_compensator_not_empty() -> void:
	var desc := manager.get_active_item_description(14)
	assert_false(desc.is_empty(),
		"get_active_item_description(14) should not be empty")


func test_get_active_item_icon_path_recoil_compensator_not_empty() -> void:
	var path := manager.get_active_item_icon_path(14)
	assert_false(path.is_empty(),
		"get_active_item_icon_path(14) should not be empty")


func test_get_all_active_item_types_includes_recoil_compensator() -> void:
	var types := manager.get_all_active_item_types()
	assert_true(14 in types,
		"get_all_active_item_types() should include RECOIL_COMPENSATOR (14)")


func test_get_all_active_item_types_count_is_15() -> void:
	var types := manager.get_all_active_item_types()
	assert_eq(types.size(), 15,
		"There should be 15 active item types (0-14) including RECOIL_COMPENSATOR")


# ============================================================================
# Selection and has_recoil_compensator Tests
# ============================================================================


func test_no_recoil_compensator_by_default() -> void:
	assert_false(manager.has_recoil_compensator(),
		"Recoil compensator should not be equipped by default")


func test_has_recoil_compensator_after_selection() -> void:
	manager.set_active_item(14)
	assert_true(manager.has_recoil_compensator(),
		"has_recoil_compensator() should return true after selecting it")


func test_no_recoil_compensator_after_deselection() -> void:
	manager.set_active_item(14)
	manager.set_active_item(0)
	assert_false(manager.has_recoil_compensator(),
		"has_recoil_compensator() should return false after switching back to none")


func test_recoil_compensator_is_selected_after_setting() -> void:
	manager.set_active_item(14)
	assert_true(manager.is_selected(14),
		"is_selected(14) should be true after selecting recoil compensator")


func test_recoil_compensator_does_not_conflict_with_flashlight() -> void:
	manager.set_active_item(14)
	assert_false(manager.has_flashlight(),
		"Flashlight should not be active when recoil compensator is selected")
	assert_true(manager.has_recoil_compensator(),
		"Recoil compensator should be active")


func test_flashlight_does_not_conflict_with_recoil_compensator() -> void:
	manager.set_active_item(1)
	assert_true(manager.has_flashlight(),
		"Flashlight should be active")
	assert_false(manager.has_recoil_compensator(),
		"Recoil compensator should not be active when flashlight is selected")


func test_recoil_compensator_does_not_conflict_with_force_field() -> void:
	manager.set_active_item(14)
	assert_false(manager.has_force_field(),
		"Force field should not be active when recoil compensator is selected")
	assert_true(manager.has_recoil_compensator(),
		"Recoil compensator should be active")


func test_set_active_item_to_recoil_compensator() -> void:
	manager.set_active_item(14)
	assert_eq(manager.current_active_item, 14,
		"current_active_item should be 14 (RECOIL_COMPENSATOR) after selection")


# ============================================================================
# Charge System Logic Tests
# ============================================================================


class MockRecoilCompensator:
	## Maximum charge duration in seconds.
	const MAX_CHARGE: float = 15.0
	## Fire rate multiplier when active.
	const FIRE_RATE_BOOST: float = 1.1

	## Whether the compensator is equipped.
	var equipped: bool = false
	## Whether the compensator is currently active.
	var is_active: bool = false
	## Remaining charge in seconds.
	var charge: float = 0.0
	## Shoot cooldown timer.
	var shoot_cooldown: float = 0.0

	func initialize() -> void:
		equipped = true
		charge = MAX_CHARGE

	func update(delta: float, space_held: bool) -> void:
		if not equipped:
			return

		if shoot_cooldown > 0.0:
			shoot_cooldown -= delta

		if space_held and charge > 0.0:
			if not is_active:
				is_active = true
			charge -= delta
			if charge <= 0.0:
				charge = 0.0
				is_active = false
		else:
			is_active = false

	## Returns spread for current state (0 when active, INITIAL_SPREAD otherwise).
	func get_spread(initial_spread: float) -> float:
		if is_active:
			return 0.0
		return initial_spread

	## Returns whether screen shake should be suppressed.
	func suppress_screen_shake() -> bool:
		return is_active

	## Records a shot and applies cooldown.
	func record_shot(fire_rate: float) -> void:
		if is_active and fire_rate > 0.0:
			shoot_cooldown = 1.0 / (fire_rate * FIRE_RATE_BOOST)

	## Returns whether a shot is allowed.
	func can_shoot_auto() -> bool:
		return is_active and shoot_cooldown <= 0.0


var compensator: MockRecoilCompensator


func before_each_compensator() -> void:
	compensator = MockRecoilCompensator.new()
	compensator.initialize()


func test_compensator_initializes_with_full_charge() -> void:
	before_each_compensator()
	assert_eq(compensator.charge, MockRecoilCompensator.MAX_CHARGE,
		"Compensator should start with full 15 second charge")


func test_compensator_max_charge_is_15_seconds() -> void:
	assert_eq(MockRecoilCompensator.MAX_CHARGE, 15.0,
		"Max charge should be 15 seconds (Issue #1073)")


func test_compensator_inactive_by_default() -> void:
	before_each_compensator()
	assert_false(compensator.is_active,
		"Compensator should be inactive when not holding Space")


func test_compensator_activates_when_space_held() -> void:
	before_each_compensator()
	compensator.update(0.016, true)
	assert_true(compensator.is_active,
		"Compensator should activate when Space is held")


func test_compensator_deactivates_when_space_released() -> void:
	before_each_compensator()
	compensator.update(0.016, true)
	assert_true(compensator.is_active, "Should be active while holding Space")
	compensator.update(0.016, false)
	assert_false(compensator.is_active,
		"Compensator should deactivate when Space is released")


func test_compensator_charge_depletes_while_active() -> void:
	before_each_compensator()
	var initial_charge := compensator.charge
	compensator.update(1.0, true)  # Hold for 1 second
	assert_true(compensator.charge < initial_charge,
		"Charge should decrease while compensator is active")
	assert_almost_eq(compensator.charge, initial_charge - 1.0, 0.001,
		"Charge should decrease by delta (1 second per second)")


func test_compensator_charge_does_not_deplete_when_inactive() -> void:
	before_each_compensator()
	var initial_charge := compensator.charge
	compensator.update(1.0, false)  # Space not held
	assert_eq(compensator.charge, initial_charge,
		"Charge should not decrease when Space is not held")


func test_compensator_deactivates_when_charge_depletes() -> void:
	before_each_compensator()
	# Deplete all charge
	compensator.update(15.0, true)
	assert_false(compensator.is_active,
		"Compensator should deactivate when charge is fully depleted")
	assert_eq(compensator.charge, 0.0,
		"Charge should be exactly 0 after full depletion")


func test_compensator_does_not_activate_with_zero_charge() -> void:
	before_each_compensator()
	compensator.charge = 0.0
	compensator.update(0.016, true)
	assert_false(compensator.is_active,
		"Compensator should not activate when charge is 0")


func test_compensator_charge_depletes_exactly_to_zero_not_below() -> void:
	before_each_compensator()
	# Hold for more than max charge time
	compensator.update(20.0, true)
	assert_true(compensator.charge >= 0.0,
		"Charge should not go below 0")
	assert_eq(compensator.charge, 0.0,
		"Charge should be clamped to 0 after full depletion")


func test_compensator_allows_multiple_activations_while_charge_remains() -> void:
	before_each_compensator()
	# First activation — use 5 seconds
	compensator.update(5.0, true)
	assert_true(compensator.is_active or compensator.charge < 15.0,
		"Charge should have decreased after 5 seconds")

	# Release Space
	compensator.update(0.016, false)
	assert_false(compensator.is_active,
		"Should be inactive after releasing Space")

	# Second activation — still has charge
	compensator.update(0.016, true)
	assert_true(compensator.is_active,
		"Compensator should activate again since charge remains")


# ============================================================================
# Spread Suppression Tests
# ============================================================================


func test_spread_is_zero_when_compensator_active() -> void:
	before_each_compensator()
	const INITIAL_SPREAD: float = 0.5
	compensator.update(0.016, true)  # Activate
	var spread := compensator.get_spread(INITIAL_SPREAD)
	assert_eq(spread, 0.0,
		"Spread should be 0.0 when recoil compensator is active (Issue #1073)")


func test_spread_is_normal_when_compensator_inactive() -> void:
	before_each_compensator()
	const INITIAL_SPREAD: float = 0.5
	# Space not held
	compensator.update(0.016, false)
	var spread := compensator.get_spread(INITIAL_SPREAD)
	assert_eq(spread, INITIAL_SPREAD,
		"Spread should be normal INITIAL_SPREAD when compensator is inactive")


func test_spread_restores_after_compensator_deactivates() -> void:
	before_each_compensator()
	const INITIAL_SPREAD: float = 0.5
	# Activate
	compensator.update(0.016, true)
	assert_eq(compensator.get_spread(INITIAL_SPREAD), 0.0, "Spread should be 0 when active")
	# Deactivate
	compensator.update(0.016, false)
	assert_eq(compensator.get_spread(INITIAL_SPREAD), INITIAL_SPREAD,
		"Spread should restore to normal after deactivation")


# ============================================================================
# Screen Shake Suppression Tests
# ============================================================================


func test_screen_shake_suppressed_when_compensator_active() -> void:
	before_each_compensator()
	compensator.update(0.016, true)  # Activate
	assert_true(compensator.suppress_screen_shake(),
		"Screen shake should be suppressed when recoil compensator is active (Issue #1073)")


func test_screen_shake_not_suppressed_when_compensator_inactive() -> void:
	before_each_compensator()
	compensator.update(0.016, false)  # Not active
	assert_false(compensator.suppress_screen_shake(),
		"Screen shake should not be suppressed when compensator is inactive")


func test_screen_shake_resumes_after_compensator_deactivates() -> void:
	before_each_compensator()
	compensator.update(0.016, true)
	assert_true(compensator.suppress_screen_shake(), "Should suppress while active")
	compensator.update(0.016, false)
	assert_false(compensator.suppress_screen_shake(),
		"Should not suppress after deactivation")


func test_screen_shake_not_suppressed_when_charge_empty() -> void:
	before_each_compensator()
	compensator.update(15.0, true)  # Deplete charge
	assert_false(compensator.suppress_screen_shake(),
		"Screen shake should not be suppressed after charge depletion")


# ============================================================================
# Fire Rate Boost Tests
# ============================================================================


func test_fire_rate_boost_constant_is_1_1() -> void:
	assert_almost_eq(MockRecoilCompensator.FIRE_RATE_BOOST, 1.1, 0.001,
		"Fire rate boost should be 1.1 (10% increase, Issue #1073)")


func test_shoot_cooldown_applied_when_compensator_active() -> void:
	before_each_compensator()
	compensator.update(0.016, true)  # Activate
	var fire_rate := 10.0
	compensator.record_shot(fire_rate)
	assert_true(compensator.shoot_cooldown > 0.0,
		"Shoot cooldown should be set after firing with compensator active")


func test_shoot_cooldown_is_correct_duration() -> void:
	before_each_compensator()
	compensator.update(0.016, true)  # Activate
	var fire_rate := 10.0
	compensator.record_shot(fire_rate)
	var expected_cooldown := 1.0 / (fire_rate * MockRecoilCompensator.FIRE_RATE_BOOST)
	assert_almost_eq(compensator.shoot_cooldown, expected_cooldown, 0.001,
		"Shoot cooldown should equal 1/(fire_rate * 1.1) for 10% boost (Issue #1073)")


func test_shoot_cooldown_decreases_with_delta() -> void:
	before_each_compensator()
	compensator.update(0.016, true)
	var fire_rate := 10.0
	compensator.record_shot(fire_rate)
	var cooldown_before := compensator.shoot_cooldown
	compensator.update(0.05, true)
	assert_true(compensator.shoot_cooldown < cooldown_before,
		"Shoot cooldown should decrease over time")


func test_auto_fire_allowed_after_cooldown_expires() -> void:
	before_each_compensator()
	compensator.update(0.016, true)
	var fire_rate := 10.0
	compensator.record_shot(fire_rate)
	# Advance time past cooldown
	compensator.update(1.0 / (fire_rate * MockRecoilCompensator.FIRE_RATE_BOOST) + 0.01, true)
	assert_true(compensator.can_shoot_auto(),
		"Should be able to auto-fire after cooldown expires")


func test_auto_fire_not_allowed_during_cooldown() -> void:
	before_each_compensator()
	compensator.update(0.016, true)
	var fire_rate := 10.0
	compensator.record_shot(fire_rate)
	# Very small delta — cooldown not expired
	compensator.update(0.001, true)
	assert_false(compensator.can_shoot_auto(),
		"Should not be able to auto-fire during cooldown")


func test_10_percent_boost_means_faster_cooldown_than_normal() -> void:
	# 10% boost means shots per second increased by 10%, so interval is shorter
	var fire_rate := 10.0
	var normal_interval := 1.0 / fire_rate
	var boosted_interval := 1.0 / (fire_rate * MockRecoilCompensator.FIRE_RATE_BOOST)
	assert_true(boosted_interval < normal_interval,
		"Boosted fire rate interval should be shorter than normal (Issue #1073)")


func test_fire_rate_boost_is_exactly_10_percent() -> void:
	# With 10% boost: boosted_rate = fire_rate * 1.1
	# Interval ratio = normal/boosted = 1.1 (boosted is 10/11 of normal duration)
	var fire_rate := 10.0
	var normal_interval := 1.0 / fire_rate
	var boosted_interval := 1.0 / (fire_rate * MockRecoilCompensator.FIRE_RATE_BOOST)
	var ratio := normal_interval / boosted_interval
	assert_almost_eq(ratio, 1.1, 0.001,
		"Fire rate boost ratio should be exactly 1.1 (10% increase, Issue #1073)")


# ============================================================================
# Unlocked State Tests
# ============================================================================


class MockActiveItemManagerWithUnlocks:
	const RECOIL_COMPENSATOR: int = 14

	## Unlocked states — recoil compensator is freely available from start
	var unlocked_items: Dictionary = {
		0: true,   # NONE
		1: false,  # FLASHLIGHT
		2: false,  # HOMING_BULLETS
		3: false,  # TELEPORT_BRACERS
		4: true,   # BFF_PENDANT
		5: false,  # INVISIBILITY_SUIT
		6: true,   # BREAKER_BULLETS
		7: true,   # FORCE_FIELD
		8: true,   # TRAJECTORY_GLASSES
		9: true,   # LASER_SIGHT
		10: true,  # LOUDSPEAKER
		11: true,  # BREACHING_CHARGES
		12: true,  # ARMORED_SKIN
		13: true,  # AUTO_RELOAD
		14: true   # RECOIL_COMPENSATOR
	}

	func is_active_item_unlocked(item_type: int) -> bool:
		return unlocked_items.get(item_type, false)


func test_recoil_compensator_is_unlocked_by_default() -> void:
	var mgr := MockActiveItemManagerWithUnlocks.new()
	assert_true(mgr.is_active_item_unlocked(14),
		"Recoil compensator should be freely available from start (Issue #1073)")


func test_unlocked_items_dictionary_contains_recoil_compensator() -> void:
	var mgr := MockActiveItemManagerWithUnlocks.new()
	assert_true(14 in mgr.unlocked_items,
		"Unlocked items dictionary should have a key for RECOIL_COMPENSATOR (14)")
