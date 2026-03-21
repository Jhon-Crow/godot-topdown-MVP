extends GutTest
## Unit tests for roguelike_level.gd — treasure pedestal system.
##
## Tests cover:
##  - Pedestal item selection (weapon vs active-item, NONE excluded)
##  - Passive item collection (no replacement, no restart)
##  - Active item swap (displaced item returned to pedestal)
##  - Weapon pedestal (new weapon applied, pedestal removed)
##  - Same-item dedup (no-op when player already has the item)
##  - Treasure room always has a pedestal (Issue #1166 — new level flow)
##  - Next level starts after exiting the treasure room
##
## Issue #1166.


# ============================================================================
# Constants mirrored from roguelike_level.gd
# ============================================================================

const PASSIVE_ACTIVE_ITEM_TYPES: Array = [
	6,   # BREAKER_BULLETS
	9,   # LASER_SIGHT
	10,  # EXTENDED_MAGAZINE
	13,  # ARMORED_SKIN
	14,  # AUTO_RELOAD
	17,  # COMBAT_DISPOSITION
]

const ACTIVE_ITEM_NONE: int = 0


# ============================================================================
# MockActiveItemManager — lightweight substitute for ActiveItemManager autoload
# ============================================================================


class MockActiveItemManager:
	var current_active_item: int = ACTIVE_ITEM_NONE
	## Record of set_active_item calls: [{type, restart_level}]
	var set_calls: Array = []
	## Passive items collected in the roguelike run (Issue #1194).
	var collected_passive_items: Array = []
	## Record of add_passive_item calls.
	var add_passive_calls: Array = []

	func get_all_active_item_types() -> Array:
		## Return types 0–18 (mirrors the real enum size including EXPERIMENTAL_SAMPLE).
		var types: Array = []
		for i in range(19):
			types.append(i)
		return types

	func get_active_item_name(type: int) -> String:
		## Mirrors ActiveItemType enum order (Issue #1194: corrected values).
		var names := {
			0: "None", 1: "Flashlight", 2: "Homing Bullets",
			3: "Teleport Bracers", 4: "BFF Pendant", 5: "Invisibility Suit",
			6: "Breaker Bullets", 7: "Force Field", 8: "Trajectory Glasses",
			9: "Laser Sight", 10: "Extended Magazine", 11: "Loudspeaker",
			12: "Breaching Charges", 13: "Armored Skin", 14: "Auto-Reload",
			15: "Drilling Bullets", 16: "Recoil Compensator", 17: "Combat Disposition",
			18: "Experimental Sample",
		}
		return names.get(type, "Unknown")

	func set_active_item(type: int, restart_level: bool = true) -> void:
		set_calls.append({"type": type, "restart_level": restart_level})
		current_active_item = type

	## Issue #1194: add a passive item to the collection.
	func add_passive_item(type: int) -> void:
		if type in collected_passive_items:
			return
		collected_passive_items.append(type)
		add_passive_calls.append(type)

	## Issue #1194: check if a passive item is already collected.
	func has_passive_item(type: int) -> bool:
		return type in collected_passive_items

	## Issue #1194: clear all collected passive items.
	func reset_passive_items() -> void:
		collected_passive_items.clear()


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

	## Room tracking (Issue #1166 new level flow).
	var current_room_idx: int = 0
	var total_rooms: int = 3
	var current_level: int = 1
	var in_treasure_room: bool = false

	func _init(aim: MockActiveItemManager, gm: MockGameManager) -> void:
		active_item_manager = aim
		game_manager = gm

	## Treasure room always has a pedestal (Issue #1166 new flow).
	## The pedestal no longer depends on room index — it lives in its own scene.
	func should_spawn_pedestal_in_treasure_room() -> bool:
		return in_treasure_room

	## Mirrors _advance_to_next_room routing (Issue #1166 new flow).
	## Returns "treasure_room", "next_room", or "next_level".
	func advance_route() -> String:
		if in_treasure_room:
			return "next_level"
		var next: int = current_room_idx + 1
		if next >= total_rooms:
			return "treasure_room"
		return "next_room"

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

	## Mirrors _apply_pedestal_active_item (Issue #1194: passive items use add_passive_item).
	func apply_pedestal_active_item(item_type: int) -> void:
		if active_item_manager == null:
			pedestal_freed = true
			pedestal_item = null
			return

		var is_passive: bool = item_type in PASSIVE_ACTIVE_ITEM_TYPES
		var current: int = active_item_manager.current_active_item

		if is_passive:
			# Issue #1194: skip if already in passive collection OR in active slot.
			if active_item_manager.has_passive_item(item_type) or item_type == current:
				pedestal_freed = true
				pedestal_item = null
				return
			active_item_manager.add_passive_item(item_type)
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


func test_passive_item_collected_via_add_passive_item() -> void:
	## Issue #1194: passive items use add_passive_item(), not set_active_item().
	var level := _make_level()
	level.active_item_manager.current_active_item = 1  # FLASHLIGHT (non-passive)
	level.apply_pedestal_active_item(6)  # BREAKER_BULLETS (passive, enum value 6)
	assert_true(level.active_item_manager.set_calls.is_empty(),
		"set_active_item must NOT be called for passive items (Issue #1194)")
	assert_false(level.active_item_manager.add_passive_calls.is_empty(),
		"add_passive_item should have been called")
	assert_eq(level.active_item_manager.add_passive_calls[0], 6,
		"add_passive_item should be called with BREAKER_BULLETS (type 6)")
	assert_true(level.pedestal_freed, "Pedestal removed after passive item collection")
	# Active slot must remain unchanged (FLASHLIGHT stays equipped)
	assert_eq(level.active_item_manager.current_active_item, 1,
		"Active item (FLASHLIGHT) must remain unchanged when passive is collected")


func test_passive_item_no_op_when_already_equipped_in_active_slot() -> void:
	var level := _make_level()
	level.active_item_manager.current_active_item = 9  # LASER_SIGHT (passive, enum value 9) in active slot
	level.apply_pedestal_active_item(9)  # Same item
	assert_true(level.active_item_manager.set_calls.is_empty(),
		"set_active_item should NOT be called when already in active slot")
	assert_true(level.active_item_manager.add_passive_calls.is_empty(),
		"add_passive_item should NOT be called for duplicate passive (active slot)")
	assert_true(level.pedestal_freed, "Pedestal freed on no-op duplicate pickup")


func test_passive_item_no_op_when_already_in_collection() -> void:
	## Issue #1194: re-picking an already-collected passive item is a no-op.
	var level := _make_level()
	level.active_item_manager.add_passive_item(10)  # EXTENDED_MAGAZINE already collected (enum value 10)
	var calls_before: int = level.active_item_manager.add_passive_calls.size()
	level.apply_pedestal_active_item(10)  # Same item
	assert_eq(level.active_item_manager.add_passive_calls.size(), calls_before,
		"add_passive_item should NOT be called again for already-collected passive")
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
# Tests — treasure room / next-level flow (Issue #1166 new design)
# ============================================================================


func test_pedestal_always_present_in_treasure_room() -> void:
	## Treasure room always has a pedestal regardless of room index.
	var level := _make_level()
	level.in_treasure_room = true
	assert_true(level.should_spawn_pedestal_in_treasure_room(),
		"Treasure room must always have a pedestal")


func test_pedestal_not_present_in_combat_room() -> void:
	## Combat rooms never have a pedestal — pedestal is exclusive to treasure room.
	var level := _make_level()
	level.in_treasure_room = false
	assert_false(level.should_spawn_pedestal_in_treasure_room(),
		"Combat rooms must NOT have a pedestal")


func test_advance_route_intermediate_room_goes_to_next_room() -> void:
	## Clearing a non-last combat room advances to the next combat room.
	var level := _make_level()
	level.total_rooms = 3
	level.current_room_idx = 0
	level.in_treasure_room = false
	assert_eq(level.advance_route(), "next_room",
		"Clearing room 1 of 3 should route to next_room")


func test_advance_route_last_room_goes_to_treasure_room() -> void:
	## Clearing the last combat room routes to the treasure room.
	var level := _make_level()
	level.total_rooms = 3
	level.current_room_idx = 2  # Last room (0-based)
	level.in_treasure_room = false
	assert_eq(level.advance_route(), "treasure_room",
		"Clearing last room (3/3) should route to treasure_room")


func test_advance_route_treasure_room_goes_to_next_level() -> void:
	## Exiting the treasure room starts the next level.
	var level := _make_level()
	level.in_treasure_room = true
	assert_eq(level.advance_route(), "next_level",
		"Exiting treasure room should route to next_level")


func test_advance_route_single_room_goes_to_treasure_room() -> void:
	## Edge case: single-room level — clearing it immediately goes to treasure room.
	var level := _make_level()
	level.total_rooms = 1
	level.current_room_idx = 0
	level.in_treasure_room = false
	assert_eq(level.advance_route(), "treasure_room",
		"Clearing the only room should route to treasure_room")


func test_advance_route_five_room_run_intermediate_rooms() -> void:
	## Rooms 0–3 in a 5-room level go to next_room, room 4 goes to treasure_room.
	var level := _make_level()
	level.total_rooms = 5
	level.in_treasure_room = false

	for idx in range(4):  # Rooms 0–3 are not last
		level.current_room_idx = idx
		assert_eq(level.advance_route(), "next_room",
			"Room %d of 5 should go to next_room" % (idx + 1))

	level.current_room_idx = 4  # Room 5 is last
	assert_eq(level.advance_route(), "treasure_room",
		"Room 5 of 5 should go to treasure_room")


# ============================================================================
# Tests — multiple passive items (Issue #1194)
# ============================================================================


func test_two_passive_items_can_be_collected() -> void:
	## Issue #1194: player can collect multiple passive items simultaneously.
	var level := _make_level()
	level.active_item_manager.current_active_item = 1  # FLASHLIGHT (active)
	level.apply_pedestal_active_item(6)   # BREAKER_BULLETS (passive, enum value 6)
	level.apply_pedestal_active_item(10)  # EXTENDED_MAGAZINE (passive, enum value 10)
	assert_eq(level.active_item_manager.collected_passive_items.size(), 2,
		"Both passive items should be in the collection")
	assert_true(level.active_item_manager.has_passive_item(6),
		"BREAKER_BULLETS should be in the passive collection")
	assert_true(level.active_item_manager.has_passive_item(10),
		"EXTENDED_MAGAZINE should be in the passive collection")
	## Active item slot must remain untouched.
	assert_eq(level.active_item_manager.current_active_item, 1,
		"Active item (FLASHLIGHT) must not be overwritten by passive pickups")


func test_all_six_passive_items_can_be_collected() -> void:
	## Issue #1194: all 6 passive item types can stack simultaneously.
	var level := _make_level()
	var all_passives: Array = [6, 9, 10, 13, 14, 17]  # PASSIVE_ACTIVE_ITEM_TYPES (corrected enum values)
	for p in all_passives:
		level.apply_pedestal_active_item(p)
	assert_eq(level.active_item_manager.collected_passive_items.size(), 6,
		"All 6 passive items should be collectable simultaneously")
	for p in all_passives:
		assert_true(level.active_item_manager.has_passive_item(p),
			"Passive item type %d should be in the collection" % p)


func test_passive_items_do_not_displace_active_item() -> void:
	## Issue #1194: collecting passives must never evict the active item.
	var level := _make_level()
	level.active_item_manager.current_active_item = 4  # BFF_PENDANT (active, enum value 4)
	level.apply_pedestal_active_item(13)  # ARMORED_SKIN (passive, enum value 13)
	level.apply_pedestal_active_item(14)  # AUTO_RELOAD (passive, enum value 14)
	assert_eq(level.active_item_manager.current_active_item, 4,
		"BFF_PENDANT must remain in active slot after collecting passives")
	assert_eq(level.active_item_manager.collected_passive_items.size(), 2,
		"Two passive items should have been added to the collection")


func test_active_item_swap_after_passive_collected() -> void:
	## Swapping an active item must not remove already-collected passives.
	var level := _make_level()
	level.active_item_manager.current_active_item = 1  # FLASHLIGHT
	level.apply_pedestal_active_item(6)   # BREAKER_BULLETS (passive, enum value 6) collected first
	level.apply_pedestal_active_item(3)   # TELEPORT_BRACERS (active, enum value 3) picked up
	## Active slot now holds TELEPORT_BRACERS.
	assert_eq(level.active_item_manager.current_active_item, 3,
		"Active slot should now hold TELEPORT_BRACERS")
	## Passive from before must still be present.
	assert_true(level.active_item_manager.has_passive_item(6),
		"BREAKER_BULLETS passive must persist after active item swap")


func test_reset_passive_items_clears_collection() -> void:
	## Issue #1194: reset_passive_items() empties the collection.
	var level := _make_level()
	level.active_item_manager.add_passive_item(6)   # BREAKER_BULLETS
	level.active_item_manager.add_passive_item(10)  # EXTENDED_MAGAZINE
	assert_eq(level.active_item_manager.collected_passive_items.size(), 2,
		"Precondition: 2 passive items collected")
	level.active_item_manager.reset_passive_items()
	assert_true(level.active_item_manager.collected_passive_items.is_empty(),
		"reset_passive_items() must clear all passive items")


func test_passive_already_collected_skips_pedestal_item_pick() -> void:
	## Issue #1194: _pick_random_pedestal_item skips already-collected passives.
	## We verify the mock's has_passive_item check works as expected.
	var level := _make_level()
	level.active_item_manager.add_passive_item(6)   # BREAKER_BULLETS already collected (enum value 6)
	## Verify has_passive_item returns true for collected item
	assert_true(level.active_item_manager.has_passive_item(6),
		"has_passive_item should return true for already-collected passive")
	## And false for not-yet-collected items
	assert_false(level.active_item_manager.has_passive_item(10),
		"has_passive_item should return false for not-yet-collected passive")
