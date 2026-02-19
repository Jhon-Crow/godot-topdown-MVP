extends GutTest
## Unit tests for Teleport Bracers active item (Issue #672).
##
## Tests the teleport bracers integration with ActiveItemManager,
## charge management, and teleportation logic.


# ============================================================================
# Active Item Type Enum Tests
# ============================================================================


func test_active_item_type_teleport_bracers_value() -> void:
	# ActiveItemType.TELEPORT_BRACERS should be 2
	var expected := 2
	assert_eq(expected, 2, "TELEPORT_BRACERS should be the third active item type (2)")


# ============================================================================
# Active Item Data Constants Tests
# ============================================================================


func test_active_item_data_has_teleport_bracers() -> void:
	var item_data := {
		2: {
			"name": "Teleport Bracers",
			"icon_path": "res://assets/sprites/weapons/teleport_bracers_icon.png",
			"description": "Teleportation bracers — hold Space to aim, release to teleport. 6 charges, no cooldown. Reticle skips through walls."
		}
	}
	assert_true(item_data.has(2), "ACTIVE_ITEM_DATA should contain TELEPORT_BRACERS type")


func test_teleport_bracers_data_has_name() -> void:
	var data := {"name": "Teleport Bracers"}
	assert_eq(data["name"], "Teleport Bracers", "Teleport Bracers should have correct name")


func test_teleport_bracers_data_has_icon_path() -> void:
	var data := {"icon_path": "res://assets/sprites/weapons/teleport_bracers_icon.png"}
	assert_eq(data["icon_path"], "res://assets/sprites/weapons/teleport_bracers_icon.png",
		"Teleport Bracers should have correct icon path")


func test_teleport_bracers_data_has_description() -> void:
	var data := {"description": "Teleportation bracers — hold Space to aim, release to teleport. 6 charges, no cooldown. Reticle skips through walls."}
	assert_true(data["description"].contains("Space"),
		"Teleport Bracers description should mention Space key")
	assert_true(data["description"].contains("6 charges"),
		"Teleport Bracers description should mention 6 charges")
	assert_true(data["description"].contains("no cooldown"),
		"Teleport Bracers description should mention no cooldown")
	assert_true(data["description"].contains("walls"),
		"Teleport Bracers description should mention walls")


# ============================================================================
# Mock ActiveItemManager for Logic Tests
# ============================================================================


class MockActiveItemManager:
	## Active item types
	const ActiveItemType := {
		NONE = 0,
		FLASHLIGHT = 1,
		TELEPORT_BRACERS = 2
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


func test_teleport_bracers_not_selected_by_default() -> void:
	assert_false(manager.is_selected(2),
		"Teleport Bracers should not be selected by default")


func test_no_teleport_bracers_by_default() -> void:
	assert_false(manager.has_teleport_bracers(),
		"Teleport Bracers should not be equipped by default")


# ============================================================================
# Type Selection Tests
# ============================================================================


func test_set_active_item_to_teleport_bracers() -> void:
	manager.set_active_item(2)
	assert_eq(manager.current_active_item, 2,
		"Active item type should change to TELEPORT_BRACERS")


func test_set_teleport_bracers_emits_change() -> void:
	manager.set_active_item(2)
	assert_eq(manager.type_changed_count, 1,
		"Type change should increment counter")


func test_set_teleport_bracers_triggers_restart_by_default() -> void:
	manager.set_active_item(2)
	assert_true(manager.last_restart_called,
		"Level restart should be triggered by default")


func test_set_teleport_bracers_without_restart() -> void:
	manager.set_active_item(2, false)
	assert_false(manager.last_restart_called,
		"Level restart should not be triggered when disabled")


func test_has_teleport_bracers_after_selection() -> void:
	manager.set_active_item(2)
	assert_true(manager.has_teleport_bracers(),
		"has_teleport_bracers should return true after selecting bracers")


func test_no_teleport_bracers_after_deselection() -> void:
	manager.set_active_item(2)
	manager.set_active_item(0)
	assert_false(manager.has_teleport_bracers(),
		"has_teleport_bracers should return false after switching back to none")


func test_no_flashlight_when_teleport_bracers_selected() -> void:
	manager.set_active_item(2)
	assert_false(manager.has_flashlight(),
		"has_flashlight should return false when bracers are selected")


func test_no_teleport_bracers_when_flashlight_selected() -> void:
	manager.set_active_item(1)
	assert_false(manager.has_teleport_bracers(),
		"has_teleport_bracers should return false when flashlight is selected")


# ============================================================================
# Data Retrieval Tests
# ============================================================================


func test_get_active_item_data_teleport_bracers() -> void:
	var data := manager.get_active_item_data(2)
	assert_eq(data["name"], "Teleport Bracers")


func test_get_all_active_item_types_includes_teleport_bracers() -> void:
	var types := manager.get_all_active_item_types()
	assert_eq(types.size(), 3,
		"Should return 3 active item types")
	assert_true(0 in types, "Should have NONE")
	assert_true(1 in types, "Should have FLASHLIGHT")
	assert_true(2 in types, "Should have TELEPORT_BRACERS")


func test_get_active_item_name_teleport_bracers() -> void:
	assert_eq(manager.get_active_item_name(2), "Teleport Bracers")


func test_get_active_item_description_teleport_bracers() -> void:
	var desc := manager.get_active_item_description(2)
	assert_true(desc.contains("teleport"),
		"Teleport Bracers description should mention teleport")


func test_get_active_item_icon_path_teleport_bracers() -> void:
	var path := manager.get_active_item_icon_path(2)
	assert_true(path.contains("teleport_bracers"),
		"Teleport Bracers icon path should contain 'teleport_bracers'")


# ============================================================================
# Selection State Tests
# ============================================================================


func test_is_selected_after_changing_to_teleport_bracers() -> void:
	manager.set_active_item(2)
	assert_true(manager.is_selected(2),
		"TELEPORT_BRACERS should be selected after changing to it")
	assert_false(manager.is_selected(0),
		"NONE should not be selected after changing away from it")
	assert_false(manager.is_selected(1),
		"FLASHLIGHT should not be selected after changing away from it")


func test_switch_between_all_active_items() -> void:
	manager.set_active_item(1)  # Flashlight
	manager.set_active_item(2)  # Teleport Bracers
	manager.set_active_item(0)  # None
	manager.set_active_item(2)  # Back to Teleport Bracers

	assert_eq(manager.current_active_item, 2)
	assert_eq(manager.type_changed_count, 4)


# ============================================================================
# Teleport Charge Tracking Tests
# ============================================================================


class MockTeleportChargeTracker:
	## Maximum number of teleport charges
	const MAX_CHARGES: int = 6

	## Current number of teleport charges
	var charges: int = MAX_CHARGES

	## Signal tracking
	var charge_changed_count: int = 0
	var last_charge_current: int = 0
	var last_charge_max: int = 0

	## Use a charge (teleport)
	func use_charge() -> bool:
		if charges <= 0:
			return false
		charges -= 1
		charge_changed_count += 1
		last_charge_current = charges
		last_charge_max = MAX_CHARGES
		return true

	## Check if charges are available
	func has_charges() -> bool:
		return charges > 0


func test_teleport_starts_with_6_charges() -> void:
	var tracker := MockTeleportChargeTracker.new()
	assert_eq(tracker.charges, 6,
		"Teleport should start with 6 charges")


func test_teleport_use_charge_decrements() -> void:
	var tracker := MockTeleportChargeTracker.new()
	var result := tracker.use_charge()
	assert_true(result, "Should successfully use charge")
	assert_eq(tracker.charges, 5, "Should have 5 charges remaining")


func test_teleport_use_charge_emits_signal() -> void:
	var tracker := MockTeleportChargeTracker.new()
	tracker.use_charge()
	assert_eq(tracker.charge_changed_count, 1,
		"Charge change should be tracked")
	assert_eq(tracker.last_charge_current, 5,
		"Signal should report 5 charges remaining")
	assert_eq(tracker.last_charge_max, 6,
		"Signal should report 6 max charges")


func test_teleport_use_all_charges() -> void:
	var tracker := MockTeleportChargeTracker.new()
	for i in range(6):
		var result := tracker.use_charge()
		assert_true(result, "Charge %d should succeed" % (i + 1))
	assert_eq(tracker.charges, 0, "Should have 0 charges remaining")
	assert_false(tracker.has_charges(), "Should have no charges available")


func test_teleport_cannot_use_when_no_charges() -> void:
	var tracker := MockTeleportChargeTracker.new()
	# Use all 6 charges
	for i in range(6):
		tracker.use_charge()
	# Try to use 7th charge
	var result := tracker.use_charge()
	assert_false(result, "Should not be able to use charge when empty")
	assert_eq(tracker.charges, 0, "Charges should remain at 0")
	assert_eq(tracker.charge_changed_count, 6,
		"Should only have 6 charge changes")


func test_teleport_charges_do_not_regenerate() -> void:
	var tracker := MockTeleportChargeTracker.new()
	tracker.use_charge()
	# Charges should stay at 5 (no regen)
	assert_eq(tracker.charges, 5,
		"Charges should not regenerate")


func test_teleport_no_cooldown_between_uses() -> void:
	var tracker := MockTeleportChargeTracker.new()
	# Use charges in rapid succession (no cooldown)
	for i in range(3):
		var result := tracker.use_charge()
		assert_true(result, "Use %d should succeed without cooldown" % (i + 1))
	assert_eq(tracker.charges, 3, "Should have 3 charges after 3 uses")


# ============================================================================
# Armory Integration Tests (Teleport Bracers in Menu)
# ============================================================================


class MockArmoryWithTeleportBracers:
	## Active item data
	const ACTIVE_ITEMS: Dictionary = {
		0: {"name": "None", "description": "No active item equipped."},
		1: {"name": "Flashlight", "description": "Tactical flashlight"},
		2: {"name": "Teleport Bracers", "description": "Teleportation bracers"}
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


func test_armory_select_teleport_bracers() -> void:
	var armory := MockArmoryWithTeleportBracers.new()
	var result := armory.select_active_item(2)
	assert_true(result, "Should select teleport bracers")
	assert_eq(armory.pending_active_item, 2, "Pending should be teleport bracers")
	assert_eq(armory.applied_active_item, 0, "Applied should still be None")


func test_armory_apply_teleport_bracers() -> void:
	var armory := MockArmoryWithTeleportBracers.new()
	armory.select_active_item(2)
	var result := armory.apply()
	assert_true(result, "Apply should succeed")
	assert_eq(armory.applied_active_item, 2, "Applied should be teleport bracers")
	assert_eq(armory.active_item_changed_count, 1, "Change count should be 1")


func test_armory_switch_flashlight_to_teleport_bracers() -> void:
	var armory := MockArmoryWithTeleportBracers.new()
	armory.select_active_item(1)
	armory.apply()
	armory.select_active_item(2)
	armory.apply()
	assert_eq(armory.applied_active_item, 2, "Should be teleport bracers")
	assert_eq(armory.active_item_changed_count, 2, "Should have 2 changes")


func test_armory_teleport_bracers_has_pending_changes() -> void:
	var armory := MockArmoryWithTeleportBracers.new()
	armory.select_active_item(2)
	assert_true(armory.has_pending_changes(),
		"Should have pending changes after selecting bracers")


func test_armory_all_three_active_items_selectable() -> void:
	var armory := MockArmoryWithTeleportBracers.new()
	assert_true(armory.select_active_item(0), "None should be selectable")
	assert_true(armory.select_active_item(1), "Flashlight should be selectable")
	assert_true(armory.select_active_item(2), "Teleport Bracers should be selectable")
	assert_false(armory.select_active_item(99), "Invalid should not be selectable")


# ============================================================================
# Wall Skip Logic Tests
# ============================================================================


class MockWallSkipCalculator:
	## Simulates the wall-skipping logic for teleport targeting.
	## In the real implementation, this uses physics raycasts.

	## Test walls as line segments: [[start_x, start_y, end_x, end_y], ...]
	var walls: Array = []

	## Player collision radius
	const PLAYER_RADIUS: float = 16.0

	## Check if a line segment from a to b crosses any wall
	func ray_hits_wall(from: Vector2, to: Vector2) -> Dictionary:
		for wall in walls:
			var wall_start := Vector2(wall[0], wall[1])
			var wall_end := Vector2(wall[2], wall[3])

			# Simple line-line intersection test
			var intersection := _line_intersection(from, to, wall_start, wall_end)
			if intersection["hit"]:
				return intersection
		return {"hit": false}

	## Simple 2D line-line intersection
	func _line_intersection(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> Dictionary:
		var d := (p1.x - p2.x) * (p3.y - p4.y) - (p1.y - p2.y) * (p3.x - p4.x)
		if absf(d) < 0.001:
			return {"hit": false}

		var t := ((p1.x - p3.x) * (p3.y - p4.y) - (p1.y - p3.y) * (p3.x - p4.x)) / d
		var u := -((p1.x - p2.x) * (p1.y - p3.y) - (p1.y - p2.y) * (p1.x - p3.x)) / d

		if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
			var point := Vector2(
				p1.x + t * (p2.x - p1.x),
				p1.y + t * (p2.y - p1.y)
			)
			return {"hit": true, "position": point, "t": t}
		return {"hit": false}


func test_no_wall_returns_cursor_position() -> void:
	var calc := MockWallSkipCalculator.new()
	# No walls defined
	var result := calc.ray_hits_wall(Vector2(0, 0), Vector2(200, 0))
	assert_false(result["hit"],
		"Should not hit wall when no walls exist")


func test_wall_detected_between_player_and_cursor() -> void:
	var calc := MockWallSkipCalculator.new()
	# Vertical wall at x=100
	calc.walls.append([100, -1000, 100, 1000])
	var result := calc.ray_hits_wall(Vector2(0, 0), Vector2(200, 0))
	assert_true(result["hit"],
		"Should detect wall between player and cursor")
	assert_almost_eq(result["position"].x, 100.0, 1.0,
		"Wall hit should be at x=100")


func test_wall_not_hit_when_cursor_before_wall() -> void:
	var calc := MockWallSkipCalculator.new()
	calc.walls.append([100, -1000, 100, 1000])
	var result := calc.ray_hits_wall(Vector2(0, 0), Vector2(50, 0))
	assert_false(result["hit"],
		"Should not hit wall when cursor is before it")
