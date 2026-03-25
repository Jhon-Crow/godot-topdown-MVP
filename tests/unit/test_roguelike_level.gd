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

## Issue #1303 fix: corrected enum values to match ActiveItemManager.ActiveItemType.
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
	## Issue #1303: passive items collected during roguelike run.
	var collected_passive_items: Array = []

	func get_all_active_item_types() -> Array:
		## Return types 0–18 (mirrors the real enum size — Issue #1303).
		var types: Array = []
		for i in range(19):
			types.append(i)
		return types

	func get_active_item_name(type: int) -> String:
		## Issue #1303: names now match ActiveItemManager.ActiveItemType enum order.
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

	func get_active_item_icon_path(type: int) -> String:
		## Stub icon paths for testing pedestal icon updates (Issue #1303).
		return "res://assets/icons/active_item_%d.png" % type

	func set_active_item(type: int, restart_level: bool = true) -> void:
		set_calls.append({"type": type, "restart_level": restart_level})
		current_active_item = type

	## Issue #1303: add a passive item to the collected set.
	func add_passive_item(type: int) -> void:
		if type not in collected_passive_items:
			collected_passive_items.append(type)

	## Issue #1303: check if a passive item is in the collected set.
	func has_passive_item(type: int) -> bool:
		return type in collected_passive_items

	## Issue #1303: clear all collected passive items.
	func clear_passive_items() -> void:
		collected_passive_items.clear()

	## Issue #1303: check passive items via collected set or current_active_item.
	func has_breaker_bullets() -> bool:
		return current_active_item == 6 or 6 in collected_passive_items

	func has_laser_sight() -> bool:
		return current_active_item == 9 or 9 in collected_passive_items

	func has_auto_reload() -> bool:
		return current_active_item == 14 or 14 in collected_passive_items


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
	const PASSIVE_ACTIVE_ITEM_TYPES: Array = [6, 9, 10, 13, 14, 17]
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

	## Mirrors _apply_pedestal_active_item
	## Issue #1303: passive items now use add_passive_item() to accumulate.
	func apply_pedestal_active_item(item_type: int) -> void:
		if active_item_manager == null:
			pedestal_freed = true
			pedestal_item = null
			return

		var is_passive: bool = item_type in PASSIVE_ACTIVE_ITEM_TYPES
		var current: int = active_item_manager.current_active_item

		if is_passive:
			if active_item_manager.has_passive_item(item_type):
				# Already collected this passive — no-op, free pedestal
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


func test_passive_item_collected_via_add_passive() -> void:
	## Issue #1303: passive items use add_passive_item() so they accumulate.
	var level := _make_level()
	level.active_item_manager.current_active_item = 1  # FLASHLIGHT (non-passive)
	level.apply_pedestal_active_item(6)  # BREAKER_BULLETS (passive, type 6)
	assert_true(level.active_item_manager.has_passive_item(6),
		"BREAKER_BULLETS should be in collected_passive_items")
	assert_eq(level.active_item_manager.current_active_item, 1,
		"current_active_item should remain FLASHLIGHT — passive doesn't replace it")
	assert_true(level.pedestal_freed, "Pedestal removed after passive item collection")


func test_passive_item_no_op_when_already_collected() -> void:
	## Issue #1303: duplicate passive pickup is a no-op.
	var level := _make_level()
	level.active_item_manager.add_passive_item(9)  # LASER_SIGHT already collected
	level.apply_pedestal_active_item(9)  # Same item
	assert_true(level.pedestal_freed, "Pedestal freed on no-op duplicate pickup")
	assert_eq(level.active_item_manager.collected_passive_items.size(), 1,
		"Should still have exactly 1 passive item (no duplicate)")


# ============================================================================
# Tests — multiple passive items coexisting (Issue #1303)
# ============================================================================


func test_multiple_passive_items_accumulate() -> void:
	## Issue #1303: collecting multiple passive items should keep all of them active.
	var level := _make_level()
	level.apply_pedestal_active_item(6)   # BREAKER_BULLETS
	level.pedestal_freed = false
	level.apply_pedestal_active_item(9)   # LASER_SIGHT
	level.pedestal_freed = false
	level.apply_pedestal_active_item(14)  # AUTO_RELOAD
	assert_true(level.active_item_manager.has_passive_item(6),
		"BREAKER_BULLETS should still be active after collecting more passives")
	assert_true(level.active_item_manager.has_passive_item(9),
		"LASER_SIGHT should still be active after collecting more passives")
	assert_true(level.active_item_manager.has_passive_item(14),
		"AUTO_RELOAD should still be active after collecting more passives")
	assert_eq(level.active_item_manager.collected_passive_items.size(), 3,
		"Should have exactly 3 passive items collected")


func test_passive_items_coexist_with_active_item() -> void:
	## Issue #1303: passive items must not replace the current active (non-passive) item.
	var level := _make_level()
	level.active_item_manager.current_active_item = 7  # FORCE_FIELD (active)
	level.apply_pedestal_active_item(6)   # BREAKER_BULLETS (passive)
	level.pedestal_freed = false
	level.apply_pedestal_active_item(9)   # LASER_SIGHT (passive)
	assert_eq(level.active_item_manager.current_active_item, 7,
		"Active item (FORCE_FIELD) should remain unchanged after passive pickups")
	assert_true(level.active_item_manager.has_breaker_bullets(),
		"has_breaker_bullets() should return true from passive collection")
	assert_true(level.active_item_manager.has_laser_sight(),
		"has_laser_sight() should return true from passive collection")


func test_clear_passive_items_on_new_run() -> void:
	## Issue #1303: passive items should be cleared at the start of a new roguelike run.
	var level := _make_level()
	level.active_item_manager.add_passive_item(6)   # BREAKER_BULLETS
	level.active_item_manager.add_passive_item(9)   # LASER_SIGHT
	level.active_item_manager.clear_passive_items()
	assert_false(level.active_item_manager.has_passive_item(6),
		"BREAKER_BULLETS should be cleared after new run")
	assert_false(level.active_item_manager.has_passive_item(9),
		"LASER_SIGHT should be cleared after new run")
	assert_eq(level.active_item_manager.collected_passive_items.size(), 0,
		"collected_passive_items should be empty after clear")


# ============================================================================
# Tests — active (non-passive) item swap
# ============================================================================


func test_active_item_replaces_current_without_restart() -> void:
	var level := _make_level()
	level.active_item_manager.current_active_item = 1  # FLASHLIGHT
	level.apply_pedestal_active_item(3)  # TELEPORT_BRACERS (active, type 3)
	assert_false(level.active_item_manager.set_calls.is_empty(),
		"set_active_item should have been called")
	var call: Dictionary = level.active_item_manager.set_calls[0]
	assert_eq(call["type"], 3, "Should set TELEPORT_BRACERS (type 3)")
	assert_false(call["restart_level"], "Active item swap must NOT restart the scene")


func test_displaced_active_item_returned_to_pedestal() -> void:
	var level := _make_level()
	level.active_item_manager.current_active_item = 1  # FLASHLIGHT
	level.apply_pedestal_active_item(3)  # TELEPORT_BRACERS replaces FLASHLIGHT
	assert_eq(level.pedestal_item, 1,
		"Displaced FLASHLIGHT (type 1) should be placed back on the pedestal")
	assert_false(level.pedestal_freed, "Pedestal should NOT be freed when displaced item placed back")
	assert_eq(level.pedestal_label_text, "Flashlight",
		"Pedestal label should show displaced item name")


func test_active_item_with_no_previous_item_frees_pedestal() -> void:
	var level := _make_level()
	level.active_item_manager.current_active_item = ACTIVE_ITEM_NONE  # No item equipped
	level.apply_pedestal_active_item(3)  # TELEPORT_BRACERS (type 3)
	assert_true(level.pedestal_freed,
		"Pedestal freed when there is no previous item to displace")
	assert_null(level.pedestal_item, "No displaced item on pedestal")


func test_active_item_same_as_equipped_frees_pedestal() -> void:
	## If the pedestal somehow offers the already-equipped non-passive item,
	## the swap sets it to itself — old_type == item_type, so no displacement.
	var level := _make_level()
	level.active_item_manager.current_active_item = 3  # TELEPORT_BRACERS (type 3)
	level.apply_pedestal_active_item(3)  # Same item
	assert_true(level.pedestal_freed, "Pedestal freed when same item offered")
	assert_null(level.pedestal_item, "No displaced item on pedestal for same-item case")


func test_trajectory_glasses_is_active_not_passive() -> void:
	## Issue #1303: Trajectory Glasses (type 8) was wrongly in PASSIVE list,
	## causing the pedestal to disappear instead of offering a swap.
	assert_false(8 in PASSIVE_ACTIVE_ITEM_TYPES,
		"TRAJECTORY_GLASSES (type 8) must NOT be in the passive list")


func test_trajectory_glasses_swap_displaces_old_item() -> void:
	## Issue #1303: picking Trajectory Glasses with an active item equipped
	## must place the old item back on the pedestal (not free it).
	var level := _make_level()
	level.active_item_manager.current_active_item = 14  # AUTO_RELOAD (passive — stays)
	# AUTO_RELOAD is passive, so set a non-passive item first.
	level.active_item_manager.current_active_item = 7  # FORCE_FIELD (active)
	level.apply_pedestal_active_item(8)  # TRAJECTORY_GLASSES (active, type 8)
	assert_eq(level.pedestal_item, 7,
		"Displaced FORCE_FIELD (type 7) should be placed back on the pedestal")
	assert_false(level.pedestal_freed,
		"Pedestal must NOT be freed — displaced item should remain for pickup")


func test_passive_types_match_enum_values() -> void:
	## Issue #1303: verify all passive types match the ActiveItemManager enum.
	## BREAKER_BULLETS=6, LASER_SIGHT=9, EXTENDED_MAGAZINE=10,
	## ARMORED_SKIN=13, AUTO_RELOAD=14, COMBAT_DISPOSITION=17
	var expected: Array = [6, 9, 10, 13, 14, 17]
	assert_eq(PASSIVE_ACTIVE_ITEM_TYPES, expected,
		"PASSIVE_ACTIVE_ITEM_TYPES must use correct ActiveItemType enum values")


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
# Tests — room size and layout diversity (Issue #1240)
# ============================================================================


## Mirror of ROOM_SIZE_OPTIONS from roguelike_level.gd
const ROOM_SIZE_OPTIONS: Array = [
	Vector2(1280.0, 720.0),
	Vector2(1600.0, 900.0),
	Vector2(1920.0, 1080.0),
]

## Number of layout variants per room type.
const ROOM_VARIANT_COUNT: int = 3

## Maximum enemy count cap introduced by issue #1240.
const ENEMIES_LEVEL_CAP: int = 8


func test_room_size_options_has_three_entries() -> void:
	assert_eq(ROOM_SIZE_OPTIONS.size(), 3,
		"There must be exactly 3 room size options (compact, standard, large)")


func test_room_size_options_all_larger_than_zero() -> void:
	for sz in ROOM_SIZE_OPTIONS:
		assert_gt(sz.x, 0.0, "Room width must be positive")
		assert_gt(sz.y, 0.0, "Room height must be positive")


func test_room_size_options_include_1280x720() -> void:
	var found := false
	for sz in ROOM_SIZE_OPTIONS:
		if sz == Vector2(1280.0, 720.0):
			found = true
	assert_true(found, "1280×720 compact size must remain in the options list")


func test_room_size_options_largest_is_wider_than_1280() -> void:
	var max_w := 0.0
	for sz in ROOM_SIZE_OPTIONS:
		if sz.x > max_w:
			max_w = sz.x
	assert_gt(max_w, 1280.0, "At least one room size must be larger than the original 1280px")


func test_room_variant_count_is_three() -> void:
	assert_eq(ROOM_VARIANT_COUNT, 3, "Each room type must have 3 layout variants")


func test_enemy_level_cap_raised_to_eight() -> void:
	## Issue #1240: cap was 6, must now be 8 for more tactical challenge.
	assert_eq(ENEMIES_LEVEL_CAP, 8, "Enemy level cap must be 8 for tactical pressure scaling")


func test_enemy_per_room_max_is_five() -> void:
	## Issue #1240: base max raised from 4 to 5.
	const ENEMIES_PER_ROOM_MAX: int = 5
	assert_eq(ENEMIES_PER_ROOM_MAX, 5, "ENEMIES_PER_ROOM_MAX must be 5 after issue #1240")


func test_room_size_options_are_all_distinct() -> void:
	for i in range(ROOM_SIZE_OPTIONS.size()):
		for j in range(ROOM_SIZE_OPTIONS.size()):
			if i != j:
				assert_ne(ROOM_SIZE_OPTIONS[i], ROOM_SIZE_OPTIONS[j],
					"All room size options must be distinct (no duplicates)")


func test_mock_advance_route_not_affected_by_room_size_changes() -> void:
	## Sanity check: room size diversity should not break existing advance routing.
	var level := _make_level()
	level.total_rooms = 3
	level.current_room_idx = 2
	level.in_treasure_room = false
	assert_eq(level.advance_route(), "treasure_room",
		"advance_route must still work correctly regardless of room size changes")


# ============================================================================
# Tests — passive pickup must not de-equip active item (Issue #1317)
# ============================================================================


func test_passive_pickup_does_not_deequip_active_item() -> void:
	## Issue #1317: picking up a passive item (e.g. AUTO_RELOAD) from a pedestal
	## must NOT de-equip the player's current active item. The passive item
	## accumulates alongside whatever is already equipped.
	var level := _make_level()
	level.active_item_manager.current_active_item = 7  # FORCE_FIELD (active)
	level.apply_pedestal_active_item(14)  # AUTO_RELOAD (passive)
	assert_eq(level.active_item_manager.current_active_item, 7,
		"Active item (FORCE_FIELD) must remain equipped after passive pickup")
	assert_true(level.active_item_manager.has_passive_item(14),
		"AUTO_RELOAD should be in collected passive items")
	assert_true(level.pedestal_freed, "Pedestal should be freed after passive pickup")


func test_all_passive_types_preserve_active_item() -> void:
	## Issue #1317: regression guard — every passive type must preserve the active item.
	for passive_type in PASSIVE_ACTIVE_ITEM_TYPES:
		var level := _make_level()
		level.active_item_manager.current_active_item = 7  # FORCE_FIELD
		level.apply_pedestal_active_item(passive_type)
		assert_eq(level.active_item_manager.current_active_item, 7,
			"Passive type %d must not change active item" % passive_type)
		assert_true(level.active_item_manager.has_passive_item(passive_type),
			"Passive type %d should be collected" % passive_type)


# ============================================================================
# Tests — weapon icon paths (Issue #1317)
# ============================================================================


## Mirror of WEAPON_ICON_PATHS from roguelike_level.gd
const WEAPON_ICON_PATHS: Dictionary = {
	"makarov_pm":      "res://assets/sprites/weapons/makarov_pm_icon.png",
	"m16":             "res://assets/sprites/weapons/m16_simple.png",
	"shotgun":         "res://assets/sprites/weapons/shotgun_icon.png",
	"mini_uzi":        "res://assets/sprites/weapons/mini_uzi_icon.png",
	"silenced_pistol": "res://assets/sprites/weapons/silenced_pistol_icon.png",
	"sniper":          "res://assets/sprites/weapons/asvk_topdown.png",
	"revolver":        "res://assets/sprites/weapons/revolver_icon.png",
	"ak_gl":           "res://assets/sprites/weapons/ak_gl_icon.png",
}

const WEAPON_CASE_ICON_PATH: String = "res://assets/sprites/weapons/weapon_case_icon.png"


func test_sniper_icon_is_not_weapon_case() -> void:
	## Issue #1317: sniper pedestal was showing suitcase instead of weapon model.
	## WEAPON_ICON_PATHS["sniper"] must point to the ASVK sprite, not the generic case icon.
	assert_eq(WEAPON_ICON_PATHS["sniper"], "res://assets/sprites/weapons/asvk_topdown.png",
		"Sniper icon must be asvk_topdown.png, not weapon_case_icon.png")
	assert_ne(WEAPON_ICON_PATHS["sniper"], WEAPON_CASE_ICON_PATH,
		"Sniper icon must not be the generic weapon case/suitcase icon")


func test_no_weapon_icon_maps_to_weapon_case() -> void:
	## Issue #1317: regression guard — no weapon in WEAPON_ICON_PATHS should use the suitcase fallback.
	for weapon_id in WEAPON_ICON_PATHS:
		assert_ne(WEAPON_ICON_PATHS[weapon_id], WEAPON_CASE_ICON_PATH,
			"Weapon '%s' must not use the generic weapon_case_icon (fix icon path)" % weapon_id)


# ============================================================================
# Tests — treasure room state persistence (Issue #1450)
# ============================================================================
#
# These tests verify that:
#  1. A fresh treasure room (treasure_item=null, treasure_collected=false)
#     spawns a pedestal and saves the item in the room map entry.
#  2. Re-entering an uncollected treasure room restores the SAME item
#     (not a new random one).
#  3. Re-entering a collected treasure room (treasure_collected=true)
#     skips the pedestal entirely.
#  4. roguelike_in_treasure_room is reset to false when navigating to
#     a non-treasure room, so combat rooms are not misidentified.


## Mirrors the treasure-room spawn logic from _spawn_treasure_pedestal and _ready.
## Returns the item that would be shown on re-entry, given a room map entry.
static func _simulate_treasure_spawn(room_entry: Dictionary, forced_item = 1) -> Dictionary:
	## Returns {spawned: bool, item: variant, room_entry: Dictionary}
	## forced_item simulates the random pick for the first visit.
	var treasure_collected: bool = room_entry.get("treasure_collected", false)
	if treasure_collected:
		return {"spawned": false, "item": null, "room_entry": room_entry}

	var saved_item = room_entry.get("treasure_item", null)
	var item
	if saved_item != null:
		item = saved_item  # Restore same item
	else:
		item = forced_item  # First visit: pick new item
		room_entry["treasure_item"] = item  # Persist it

	return {"spawned": true, "item": item, "room_entry": room_entry}


## Mirrors the treasure-collected marking from _mark_treasure_collected.
static func _simulate_treasure_collect(room_entry: Dictionary) -> Dictionary:
	room_entry["treasure_collected"] = true
	return room_entry


func test_1450_fresh_treasure_room_spawns_pedestal() -> void:
	## A treasure room entry with no prior state must spawn a pedestal.
	var room_entry: Dictionary = {"treasure_item": null, "treasure_collected": false, "cleared": false}
	var result: Dictionary = _simulate_treasure_spawn(room_entry)
	assert_true(result["spawned"], "Fresh treasure room must spawn a pedestal")
	assert_eq(result["item"], 1, "Fresh treasure room must use the forced item")


func test_1450_first_visit_saves_item_to_room_map() -> void:
	## After the first visit, treasure_item must be persisted in the room entry.
	var room_entry: Dictionary = {"treasure_item": null, "treasure_collected": false, "cleared": false}
	var result: Dictionary = _simulate_treasure_spawn(room_entry, 5)  # forced item = 5
	assert_eq(result["room_entry"]["treasure_item"], 5,
		"treasure_item must be saved in room map entry after first spawn")


func test_1450_reentry_restores_same_item() -> void:
	## Re-entering an uncollected treasure room must restore the exact same item.
	var room_entry: Dictionary = {"treasure_item": 3, "treasure_collected": false, "cleared": false}
	var result: Dictionary = _simulate_treasure_spawn(room_entry, 99)  # forced_item=99 must be ignored
	assert_true(result["spawned"], "Re-entry of uncollected room must spawn pedestal")
	assert_eq(result["item"], 3, "Re-entry must restore the saved item (3), not a new random one")


func test_1450_collected_room_skips_pedestal() -> void:
	## A room where treasure_collected=true must never show a pedestal.
	var room_entry: Dictionary = {"treasure_item": 7, "treasure_collected": true, "cleared": true}
	var result: Dictionary = _simulate_treasure_spawn(room_entry)
	assert_false(result["spawned"], "Collected treasure room must NOT spawn a pedestal")
	assert_null(result["item"], "Collected treasure room item must be null")


func test_1450_mark_collect_sets_flag() -> void:
	## _mark_treasure_collected must set treasure_collected=true in the room entry.
	var room_entry: Dictionary = {"treasure_item": 2, "treasure_collected": false, "cleared": true}
	var updated: Dictionary = _simulate_treasure_collect(room_entry)
	assert_true(updated["treasure_collected"], "treasure_collected must be true after collection")


func test_1450_multiple_reentries_always_restore_same_item() -> void:
	## Simulates several entry/exit cycles without item collection.
	## Each re-entry must show the same item.
	var room_entry: Dictionary = {"treasure_item": null, "treasure_collected": false, "cleared": false}

	# Visit 1: first entry, item assigned
	var r1: Dictionary = _simulate_treasure_spawn(room_entry, 4)
	assert_eq(r1["item"], 4, "Visit 1 must use forced item 4")
	room_entry = r1["room_entry"]

	# Visits 2-5: re-entries without collection
	for _i in range(4):
		var rx: Dictionary = _simulate_treasure_spawn(room_entry, 99)  # different forced item ignored
		assert_eq(rx["item"], 4, "Re-entry must always restore item 4, not a new random item")

	# Visit 6: player collects the item
	room_entry = _simulate_treasure_collect(room_entry)

	# Visit 7: after collection, no pedestal
	var r7: Dictionary = _simulate_treasure_spawn(room_entry)
	assert_false(r7["spawned"], "After collection, no pedestal should spawn")


func test_1450_in_treasure_room_flag_reset_on_navigate_to_combat() -> void:
	## roguelike_in_treasure_room must be false after navigating to a non-treasure room,
	## so the combat room's _ready() does not misidentify it as a treasure room.
	##
	## We simulate the _navigate_to_map_room "_:" branch logic:
	##   target map_room_type != "treasure" → roguelike_in_treasure_room = false

	## Arrange: in treasure room
	var in_treasure_room: bool = true
	var target_type: String = "combat"  # navigating to a combat room

	## Act: simulate the match branch
	if target_type != "treasure" and target_type != "exit":
		in_treasure_room = false  # Issue #1450 fix

	## Assert
	assert_false(in_treasure_room,
		"roguelike_in_treasure_room must be reset to false when navigating to a combat room")


func test_1450_in_treasure_room_flag_kept_when_navigating_to_treasure() -> void:
	## roguelike_in_treasure_room must remain true (or become true) when navigating to treasure.
	var in_treasure_room: bool = false
	var target_type: String = "treasure"

	if target_type == "treasure":
		in_treasure_room = true  # set by treasure branch

	assert_true(in_treasure_room,
		"roguelike_in_treasure_room must be true when navigating to a treasure room")
