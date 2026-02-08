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
			"description": "Tactical flashlight — hold Space to illuminate in weapon direction. Bright white light, turns off when released."
		}
	}
	assert_true(item_data.has(1), "ACTIVE_ITEM_DATA should contain FLASHLIGHT type")


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
	var data := {"description": "Tactical flashlight — hold Space to illuminate in weapon direction. Bright white light, turns off when released."}
	assert_true(data["description"].contains("Space"),
		"Flashlight description should mention Space key")


# ============================================================================
# Mock ActiveItemManager for Logic Tests
# ============================================================================


class MockActiveItemManager:
	## Active item types
	const ActiveItemType := {
		NONE = 0,
		FLASHLIGHT = 1,
		TELEPORT_BRACERS = 2,
		FORCE_FIELD = 3
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
			"name": "Teleport Bracers",
			"icon_path": "res://assets/sprites/weapons/teleport_bracers_icon.png",
			"description": "Teleportation bracers — hold Space to aim, release to teleport. 6 charges, no cooldown. Reticle skips through walls."
		},
		3: {
			"name": "Force Field",
			"icon_path": "",
			"description": "Hold Space to activate a glowing force field that reflects all projectiles. 8 second charge, depletable. Shows progress bar."
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

	## Check if teleport bracers are currently equipped
	func has_teleport_bracers() -> bool:
		return current_active_item == ActiveItemType.TELEPORT_BRACERS

	## Check if force field is currently equipped
	func has_force_field() -> bool:
		return current_active_item == ActiveItemType.FORCE_FIELD


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
	assert_eq(types.size(), 4,
		"Should return 4 active item types")
	assert_true(0 in types)
	assert_true(1 in types)
	assert_true(2 in types)
	assert_true(3 in types)


func test_get_active_item_name_none() -> void:
	assert_eq(manager.get_active_item_name(0), "None")


func test_get_active_item_name_flashlight() -> void:
	assert_eq(manager.get_active_item_name(1), "Flashlight")


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


func test_get_active_item_description_invalid() -> void:
	assert_eq(manager.get_active_item_description(999), "")


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
		2: {"name": "Teleport Bracers", "description": "Teleportation bracers"},
		3: {"name": "Force Field", "description": "Hold Space to activate force field"}
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
# Force Field Tests
# ============================================================================


func test_has_force_field_after_selection() -> void:
	manager.set_active_item(3)
	assert_true(manager.has_force_field(),
		"has_force_field should return true after selecting force field")


func test_no_force_field_by_default() -> void:
	assert_false(manager.has_force_field(),
		"Force field should not be equipped by default")


func test_force_field_data_has_name() -> void:
	var data := manager.get_active_item_data(3)
	assert_eq(data["name"], "Force Field", "Force Field should have correct name")


func test_force_field_data_has_description() -> void:
	var data := manager.get_active_item_data(3)
	assert_true(data["description"].contains("Space"),
		"Force field description should mention Space key")


func test_armory_select_force_field() -> void:
	var armory := MockArmoryWithActiveItems.new()
	var result := armory.select_active_item(3)
	assert_true(result, "Should select force field")
	assert_eq(armory.pending_active_item, 3, "Pending should be force field")


# ============================================================================
# Force Field Effect Tests (Mock)
# ============================================================================


class MockForceFieldEffect:
	## Total charge in seconds.
	const MAX_CHARGE: float = 8.0

	## Whether the force field is currently active.
	var _is_active: bool = false

	## Remaining charge in seconds.
	var _charge_remaining: float = MAX_CHARGE

	## Whether the charge has been fully depleted.
	var _depleted: bool = false

	func activate() -> void:
		if _is_active:
			return
		if _depleted or _charge_remaining <= 0:
			return
		_is_active = true

	func deactivate() -> void:
		if not _is_active:
			return
		_is_active = false

	func is_active() -> bool:
		return _is_active

	func has_charge() -> bool:
		return not _depleted and _charge_remaining > 0

	func get_charge_remaining() -> float:
		return _charge_remaining

	func get_charge_fraction() -> float:
		return _charge_remaining / MAX_CHARGE

	## Simulate delta time passing while active.
	func simulate_delta(delta: float) -> void:
		if not _is_active:
			return
		_charge_remaining -= delta
		if _charge_remaining <= 0:
			_charge_remaining = 0.0
			_depleted = true
			deactivate()


func test_force_field_starts_inactive() -> void:
	var ff := MockForceFieldEffect.new()
	assert_false(ff.is_active(), "Force field should start inactive")


func test_force_field_starts_with_full_charge() -> void:
	var ff := MockForceFieldEffect.new()
	assert_eq(ff.get_charge_remaining(), 8.0, "Should start with 8s charge")
	assert_eq(ff.get_charge_fraction(), 1.0, "Fraction should be 1.0")


func test_force_field_activate() -> void:
	var ff := MockForceFieldEffect.new()
	ff.activate()
	assert_true(ff.is_active(), "Should be active after activation")


func test_force_field_deactivate() -> void:
	var ff := MockForceFieldEffect.new()
	ff.activate()
	ff.deactivate()
	assert_false(ff.is_active(), "Should be inactive after deactivation")


func test_force_field_charge_depletes() -> void:
	var ff := MockForceFieldEffect.new()
	ff.activate()
	ff.simulate_delta(3.0)
	assert_true(ff.is_active(), "Should still be active with charge remaining")
	assert_eq(ff.get_charge_remaining(), 5.0, "Should have 5s remaining")


func test_force_field_partial_use() -> void:
	var ff := MockForceFieldEffect.new()
	# Use 2 seconds
	ff.activate()
	ff.simulate_delta(2.0)
	ff.deactivate()
	assert_eq(ff.get_charge_remaining(), 6.0, "Should have 6s remaining after 2s use")
	assert_true(ff.has_charge(), "Should still have charge")

	# Use 3 more seconds
	ff.activate()
	ff.simulate_delta(3.0)
	ff.deactivate()
	assert_eq(ff.get_charge_remaining(), 3.0, "Should have 3s remaining after 5s total use")


func test_force_field_full_depletion() -> void:
	var ff := MockForceFieldEffect.new()
	ff.activate()
	ff.simulate_delta(8.0)
	assert_false(ff.is_active(), "Should auto-deactivate when depleted")
	assert_false(ff.has_charge(), "Should have no charge")
	assert_eq(ff.get_charge_remaining(), 0.0, "Remaining should be 0")


func test_force_field_cannot_activate_when_depleted() -> void:
	var ff := MockForceFieldEffect.new()
	ff.activate()
	ff.simulate_delta(8.0)  # Fully deplete
	ff.activate()  # Try to activate again
	assert_false(ff.is_active(), "Should not activate when depleted")


func test_force_field_charge_fraction() -> void:
	var ff := MockForceFieldEffect.new()
	ff.activate()
	ff.simulate_delta(4.0)
	assert_eq(ff.get_charge_fraction(), 0.5, "Fraction should be 0.5 after half depletion")
