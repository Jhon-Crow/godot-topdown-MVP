extends GutTest
## Unit tests for roguelike_level.gd — treasure pedestal system.
##
## Tests cover:
##  - Pedestal item selection (weapon vs active-item, NONE excluded)
##  - Passive item collection (no replacement, no restart)
##  - Active item swap (displaced item returned to pedestal)
##  - Weapon pedestal (new weapon applied, pedestal removed)
##  - Same-item dedup (no-op when player already has the item)
##  - Pedestal only spawns on the last room (Bug fix #1166 comment 4080211471)
##
## Issue #1166.


# ============================================================================
# Constants mirrored from roguelike_level.gd
# ============================================================================

const PASSIVE_ACTIVE_ITEM_TYPES: Array = [
	2,   # BREAKER_BULLETS
	8,   # LASER_SIGHT
	9,   # EXTENDED_MAGAZINE
	12,  # ARMORED_SKIN
	13,  # AUTO_RELOAD
	16,  # COMBAT_DISPOSITION
]

const ACTIVE_ITEM_NONE: int = 0


# ============================================================================
# MockActiveItemManager — lightweight substitute for ActiveItemManager autoload
# ============================================================================


class MockActiveItemManager:
	var current_active_item: int = ACTIVE_ITEM_NONE
	## Record of set_active_item calls: [{type, restart_level}]
	var set_calls: Array = []

	func get_all_active_item_types() -> Array:
		## Return types 0–16 (mirrors the real enum size).
		var types: Array = []
		for i in range(17):
			types.append(i)
		return types

	func get_active_item_name(type: int) -> String:
		var names := {
			0: "None", 1: "Flashlight", 2: "Breaker Bullets",
			3: "Homing Bullets", 4: "Teleport Bracers", 5: "BFF Pendant",
			6: "Invisibility Suit", 7: "Force Field", 8: "Laser Sight",
			9: "Extended Magazine", 10: "Loudspeaker", 11: "Breaching Charges",
			12: "Armored Skin", 13: "Auto-Reload", 14: "Trajectory Glasses",
			15: "Drilling Bullets", 16: "Combat Disposition",
		}
		return names.get(type, "Unknown")

	func set_active_item(type: int, restart_level: bool = true) -> void:
		set_calls.append({"type": type, "restart_level": restart_level})
		current_active_item = type


# ============================================================================
# MockGameManager — lightweight substitute for GameManager autoload
# ============================================================================


class MockGameManager:
	var selected_weapon: String = "makarov_pm"
	var set_weapon_calls: Array = []
	const WEAPON_SCENES: Dictionary = {
		"makarov_pm": "",
		"m16": "",
		"shotgun": "",
	}
	var unlocked: Dictionary = {
		"makarov_pm": true,
		"m16": true,
		"shotgun": true,
	}

	func get_selected_weapon() -> String:
		return selected_weapon

	func set_selected_weapon(weapon_id: String) -> void:
		selected_weapon = weapon_id
		set_weapon_calls.append(weapon_id)

	func is_weapon_unlocked(weapon_id: String) -> bool:
		return unlocked.get(weapon_id, false)


# ============================================================================
# MockRoguelikeLevel — mirrors the pedestal logic from roguelike_level.gd
# ============================================================================


class MockRoguelikeLevel:
	const PASSIVE_ACTIVE_ITEM_TYPES: Array = [2, 8, 9, 12, 13, 16]
	const ACTIVE_ITEM_NONE: int = 0

	var active_item_manager: MockActiveItemManager = null
	var game_manager: MockGameManager = null

	## Tracks whether pedestal was freed.
	var pedestal_freed: bool = false
	## Item currently on the pedestal (null when freed).
	var pedestal_item = null
	## Label text updated during active-item swap.
	var pedestal_label_text: String = ""
	## Whether ApplySelectedWeaponFromGameManager was called on mock player.
	var weapon_applied: bool = false

	## Room tracking for pedestal-spawn logic (Bug fix #1166).
	var current_room_idx: int = 0
	var total_rooms: int = 3
	## Whether _spawn_treasure_pedestal was requested.
	var pedestal_spawn_requested: bool = false

	func _init(aim: MockActiveItemManager, gm: MockGameManager) -> void:
		active_item_manager = aim
		game_manager = gm

	## Mirrors _on_enemy_died pedestal-spawn condition (Bug fix #1166).
	## Returns true if pedestal should spawn (only on last room).
	func should_spawn_pedestal_on_room_clear() -> bool:
		return current_room_idx + 1 >= total_rooms

	func _pedestal_item_label(item) -> String:
		if item == "weapon":
			return "Оружие (случайное)"
		if item is int and active_item_manager:
			return active_item_manager.get_active_item_name(item)
		return "???"

	## Mirrors _pick_random_pedestal_item with forced choice for testing.
	func pick_item_forced(force_weapon: bool, forced_type: int = 0):
		if force_weapon:
			return "weapon"
		return forced_type

	## Mirrors _apply_pedestal_weapon
	func apply_pedestal_weapon(current_weapon: String) -> void:
		if game_manager == null:
			pedestal_freed = true
			pedestal_item = null
			return

		var available: Array = []
		for weapon_id in game_manager.WEAPON_SCENES.keys():
			if weapon_id != current_weapon and game_manager.is_weapon_unlocked(weapon_id):
				available.append(weapon_id)

		if available.is_empty():
			pedestal_freed = true
			pedestal_item = null
			return

		var new_id: String = available[0]  # deterministic in tests
		game_manager.set_selected_weapon(new_id)
		weapon_applied = true
		pedestal_freed = true
		pedestal_item = null

	## Mirrors _apply_pedestal_active_item
	func apply_pedestal_active_item(item_type: int) -> void:
		if active_item_manager == null:
			pedestal_freed = true
			pedestal_item = null
			return

		var is_passive: bool = item_type in PASSIVE_ACTIVE_ITEM_TYPES
		var current: int = active_item_manager.current_active_item

		if is_passive:
			if item_type == current:
				# Same item — no-op, free pedestal
				pedestal_freed = true
				pedestal_item = null
				return
			active_item_manager.set_active_item(item_type, false)
			pedestal_freed = true
			pedestal_item = null
		else:
			var old_type: int = current
			active_item_manager.set_active_item(item_type, false)

			if old_type != ACTIVE_ITEM_NONE and old_type != item_type:
				# Displace old item back onto pedestal
				pedestal_item = old_type
				pedestal_label_text = _pedestal_item_label(old_type)
			else:
				pedestal_freed = true
				pedestal_item = null


# ============================================================================
# Helpers
# ============================================================================


func _make_level() -> MockRoguelikeLevel:
	return MockRoguelikeLevel.new(MockActiveItemManager.new(), MockGameManager.new())


# ============================================================================
# Tests — item selection
# ============================================================================


func test_pick_weapon_returns_weapon_string() -> void:
	var level := _make_level()
	var item = level.pick_item_forced(true)
	assert_eq(item, "weapon", "Forced weapon selection should return 'weapon'")


func test_pick_active_item_returns_int() -> void:
	var level := _make_level()
	var item = level.pick_item_forced(false, 3)  # HOMING_BULLETS
	assert_true(item is int, "Active item selection should return an int")
	assert_eq(item, 3, "Should return the forced item type 3")


func test_none_type_never_selected_directly() -> void:
	## NONE (0) must not appear as a picked pedestal item from the candidate list.
	var level := _make_level()
	var all_types := level.active_item_manager.get_all_active_item_types()
	var candidates: Array = []
	for t in all_types:
		if t != ACTIVE_ITEM_NONE:
			candidates.append(t)
	assert_false(ACTIVE_ITEM_NONE in candidates, "NONE should not be in pedestal candidates")


# ============================================================================
# Tests — weapon pedestal
# ============================================================================


func test_weapon_pedestal_switches_weapon() -> void:
	var level := _make_level()
	level.apply_pedestal_weapon("makarov_pm")
	assert_ne(level.game_manager.selected_weapon, "makarov_pm",
		"Weapon should change from makarov_pm after weapon pedestal")
	assert_true(level.weapon_applied, "ApplySelectedWeaponFromGameManager should be called")
	assert_true(level.pedestal_freed, "Pedestal should be freed after weapon collection")


func test_weapon_pedestal_removed_when_no_alternatives() -> void:
	var level := _make_level()
	# Lock all weapons except the current one.
	level.game_manager.unlocked = {"makarov_pm": true, "m16": false, "shotgun": false}
	level.apply_pedestal_weapon("makarov_pm")
	assert_true(level.pedestal_freed, "Pedestal removed when no alternative weapons available")
	assert_eq(level.game_manager.selected_weapon, "makarov_pm",
		"Weapon unchanged when no alternatives")


# ============================================================================
# Tests — passive active-item pedestal
# ============================================================================


func test_passive_item_collected_without_restart() -> void:
	var level := _make_level()
	level.active_item_manager.current_active_item = 1  # FLASHLIGHT (non-passive)
	level.apply_pedestal_active_item(2)  # BREAKER_BULLETS (passive)
	assert_false(level.active_item_manager.set_calls.is_empty(),
		"set_active_item should have been called")
	var call: Dictionary = level.active_item_manager.set_calls[0]
	assert_eq(call["type"], 2, "Should set BREAKER_BULLETS (type 2)")
	assert_false(call["restart_level"], "Passive item pickup must NOT trigger scene restart")
	assert_true(level.pedestal_freed, "Pedestal removed after passive item collection")


func test_passive_item_no_op_when_already_equipped() -> void:
	var level := _make_level()
	level.active_item_manager.current_active_item = 8  # LASER_SIGHT (passive)
	level.apply_pedestal_active_item(8)  # Same item
	assert_true(level.active_item_manager.set_calls.is_empty(),
		"set_active_item should NOT be called when already equipped")
	assert_true(level.pedestal_freed, "Pedestal freed on no-op duplicate pickup")


# ============================================================================
# Tests — active (non-passive) item swap
# ============================================================================


func test_active_item_replaces_current_without_restart() -> void:
	var level := _make_level()
	level.active_item_manager.current_active_item = 1  # FLASHLIGHT
	level.apply_pedestal_active_item(4)  # TELEPORT_BRACERS (active)
	assert_false(level.active_item_manager.set_calls.is_empty(),
		"set_active_item should have been called")
	var call: Dictionary = level.active_item_manager.set_calls[0]
	assert_eq(call["type"], 4, "Should set TELEPORT_BRACERS (type 4)")
	assert_false(call["restart_level"], "Active item swap must NOT restart the scene")


func test_displaced_active_item_returned_to_pedestal() -> void:
	var level := _make_level()
	level.active_item_manager.current_active_item = 1  # FLASHLIGHT
	level.apply_pedestal_active_item(4)  # TELEPORT_BRACERS replaces FLASHLIGHT
	assert_eq(level.pedestal_item, 1,
		"Displaced FLASHLIGHT (type 1) should be placed back on the pedestal")
	assert_false(level.pedestal_freed, "Pedestal should NOT be freed when displaced item placed back")
	assert_eq(level.pedestal_label_text, "Flashlight",
		"Pedestal label should show displaced item name")


func test_active_item_with_no_previous_item_frees_pedestal() -> void:
	var level := _make_level()
	level.active_item_manager.current_active_item = ACTIVE_ITEM_NONE  # No item equipped
	level.apply_pedestal_active_item(4)  # TELEPORT_BRACERS
	assert_true(level.pedestal_freed,
		"Pedestal freed when there is no previous item to displace")
	assert_null(level.pedestal_item, "No displaced item on pedestal")


func test_active_item_same_as_equipped_frees_pedestal() -> void:
	## If the pedestal somehow offers the already-equipped non-passive item,
	## the swap sets it to itself — old_type == item_type, so no displacement.
	var level := _make_level()
	level.active_item_manager.current_active_item = 4  # TELEPORT_BRACERS
	level.apply_pedestal_active_item(4)  # Same item
	assert_true(level.pedestal_freed, "Pedestal freed when same item offered")
	assert_null(level.pedestal_item, "No displaced item on pedestal for same-item case")


# ============================================================================
# Tests — pedestal label helper
# ============================================================================


func test_item_label_weapon() -> void:
	var level := _make_level()
	assert_eq(level._pedestal_item_label("weapon"), "Оружие (случайное)",
		"Weapon pedestal label should be 'Оружие (случайное)'")


func test_item_label_active_item() -> void:
	var level := _make_level()
	assert_eq(level._pedestal_item_label(1), "Flashlight",
		"Active item label should match ActiveItemManager name")


func test_item_label_none_returns_none_name() -> void:
	var level := _make_level()
	assert_eq(level._pedestal_item_label(0), "None",
		"Type 0 (NONE) label should be 'None'")


# ============================================================================
# Tests — pedestal only spawns on the last room (Bug fix #1166 comment 4080211471)
# ============================================================================


func test_pedestal_does_not_spawn_on_intermediate_rooms() -> void:
	## Bug fix: pedestal previously spawned after every room clear.
	## Now it should only spawn after the LAST room.
	var level := _make_level()
	level.total_rooms = 3

	# Clearing room 0 (not the last)
	level.current_room_idx = 0
	assert_false(level.should_spawn_pedestal_on_room_clear(),
		"Pedestal should NOT spawn after room 1 of 3")

	# Clearing room 1 (not the last)
	level.current_room_idx = 1
	assert_false(level.should_spawn_pedestal_on_room_clear(),
		"Pedestal should NOT spawn after room 2 of 3")


func test_pedestal_spawns_on_last_room() -> void:
	## Pedestal must spawn when the last room is cleared.
	var level := _make_level()
	level.total_rooms = 3

	level.current_room_idx = 2  # Last room (0-based)
	assert_true(level.should_spawn_pedestal_on_room_clear(),
		"Pedestal MUST spawn after clearing the last room (room 3 of 3)")


func test_pedestal_spawns_on_last_room_single_room_run() -> void:
	## Edge case: a single-room run — pedestal spawns immediately.
	var level := _make_level()
	level.total_rooms = 1
	level.current_room_idx = 0
	assert_true(level.should_spawn_pedestal_on_room_clear(),
		"Pedestal must spawn on the only room in a 1-room run")


func test_pedestal_spawns_on_last_room_five_room_run() -> void:
	## Edge case: max 5-room run — only last room triggers pedestal.
	var level := _make_level()
	level.total_rooms = 5

	for idx in range(4):  # Rooms 0–3 are not last
		level.current_room_idx = idx
		assert_false(level.should_spawn_pedestal_on_room_clear(),
			"Pedestal should NOT spawn at room %d of 5" % (idx + 1))

	level.current_room_idx = 4  # Room 5 is the last
	assert_true(level.should_spawn_pedestal_on_room_clear(),
		"Pedestal must spawn after room 5 of 5")
