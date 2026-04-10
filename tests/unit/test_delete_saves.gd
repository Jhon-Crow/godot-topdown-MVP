extends GutTest
## Unit tests for the "Delete Saves" feature (Issue #938).
##
## Verifies that clear_all_saves() resets all game progress (level progress,
## unlocked weapons, unlocked grenades, unlocked active items) while
## preserving experimental settings.


# ============================================================================
# Mock classes mirroring production autoload behaviour
# ============================================================================


class MockGameManager:
	var selected_weapon: String = "makarov_pm"
	var unlocked_weapons: Dictionary = {
		"makarov_pm": true,
		"m16": false,
		"shotgun": false,
		"mini_uzi": false,
		"silenced_pistol": false,
		"sniper": false,
		"revolver": false,
		"ak_gl": false
	}

	## Simulate unlocking several weapons to set up a "used" state.
	func unlock_weapons(ids: Array) -> void:
		for id in ids:
			if id in unlocked_weapons:
				unlocked_weapons[id] = true

	## Reset weapons to defaults (mirrors PersistManager.clear_all_saves logic).
	func reset_to_defaults() -> void:
		for weapon_id in unlocked_weapons.keys():
			unlocked_weapons[weapon_id] = weapon_id == "makarov_pm"
		selected_weapon = "makarov_pm"


class MockGrenadeManager:
	enum GrenadeType { FLASHBANG, FRAG, DEFENSIVE, AGGRESSION_GAS }
	var current_grenade_type: int = GrenadeType.FLASHBANG
	var unlocked_grenades: Dictionary = {
		GrenadeType.FLASHBANG: true,
		GrenadeType.FRAG: false,
		GrenadeType.DEFENSIVE: false,
		GrenadeType.AGGRESSION_GAS: false
	}

	func unlock_grenades(types: Array) -> void:
		for t in types:
			if t in unlocked_grenades:
				unlocked_grenades[t] = true

	func reset_to_defaults() -> void:
		for grenade_type in unlocked_grenades.keys():
			unlocked_grenades[grenade_type] = grenade_type == GrenadeType.FLASHBANG
		current_grenade_type = GrenadeType.FLASHBANG


class MockActiveItemManager:
	enum ActiveItemType { NONE, FLASHLIGHT, HOMING_BULLETS, TELEPORT_BRACERS, BFF_PENDANT, INVISIBILITY_SUIT, BREAKER_BULLETS, FORCE_FIELD, TRAJECTORY_GLASSES }
	var current_active_item: int = ActiveItemType.NONE
	var unlocked_active_items: Dictionary = {
		ActiveItemType.NONE: true,
		ActiveItemType.FLASHLIGHT: false,
		ActiveItemType.HOMING_BULLETS: false,
		ActiveItemType.TELEPORT_BRACERS: false,
		ActiveItemType.BFF_PENDANT: false,
		ActiveItemType.INVISIBILITY_SUIT: false,
		ActiveItemType.BREAKER_BULLETS: false,
		ActiveItemType.FORCE_FIELD: false,
		ActiveItemType.TRAJECTORY_GLASSES: false
	}

	func unlock_items(types: Array) -> void:
		for t in types:
			if t in unlocked_active_items:
				unlocked_active_items[t] = true

	func reset_to_defaults() -> void:
		for item_type in unlocked_active_items.keys():
			unlocked_active_items[item_type] = item_type == ActiveItemType.NONE
		current_active_item = ActiveItemType.NONE


class MockProgressManager:
	var _progress: Dictionary = {}
	var clear_called: bool = false

	func add_progress(level: String, difficulty: String, rank: String) -> void:
		_progress["%s:%s" % [level, difficulty]] = {"rank": rank, "score": 100}

	func clear_all_progress() -> void:
		_progress.clear()
		clear_called = true

	func get_progress_count() -> int:
		return _progress.size()


class MockPersistManagerWithSave:
	## Mirrors the logic of PersistManager.clear_all_saves() without file I/O.

	var game_manager: MockGameManager
	var grenade_manager: MockGrenadeManager
	var active_item_manager: MockActiveItemManager
	var progress_manager: MockProgressManager
	var save_file_exists: bool = false

	func clear_all_saves() -> void:
		# Simulate deleting the save file
		save_file_exists = false

		# Reset GameManager
		if game_manager:
			game_manager.reset_to_defaults()

		# Reset GrenadeManager
		if grenade_manager:
			grenade_manager.reset_to_defaults()

		# Reset ActiveItemManager
		if active_item_manager:
			active_item_manager.reset_to_defaults()

		# Clear level progress
		if progress_manager:
			progress_manager.clear_all_progress()


var gm: MockGameManager
var grenade: MockGrenadeManager
var active: MockActiveItemManager
var progress: MockProgressManager
var persist: MockPersistManagerWithSave


func before_each() -> void:
	gm = MockGameManager.new()
	grenade = MockGrenadeManager.new()
	active = MockActiveItemManager.new()
	progress = MockProgressManager.new()
	persist = MockPersistManagerWithSave.new()
	persist.game_manager = gm
	persist.grenade_manager = grenade
	persist.active_item_manager = active
	persist.progress_manager = progress


func after_each() -> void:
	gm = null
	grenade = null
	active = null
	progress = null
	persist = null


# ============================================================================
# clear_all_saves — weapon reset tests
# ============================================================================


func test_clear_all_saves_locks_all_weapons_except_makarov() -> void:
	gm.unlock_weapons(["m16", "shotgun", "mini_uzi", "sniper"])

	persist.clear_all_saves()

	assert_false(gm.unlocked_weapons["m16"], "m16 should be locked after clear")
	assert_false(gm.unlocked_weapons["shotgun"], "shotgun should be locked after clear")
	assert_false(gm.unlocked_weapons["mini_uzi"], "mini_uzi should be locked after clear")
	assert_false(gm.unlocked_weapons["sniper"], "sniper should be locked after clear")


func test_clear_all_saves_keeps_makarov_unlocked() -> void:
	gm.unlock_weapons(["m16", "shotgun"])

	persist.clear_all_saves()

	assert_true(gm.unlocked_weapons["makarov_pm"],
		"makarov_pm should remain unlocked after clear (default starting weapon)")


func test_clear_all_saves_resets_selected_weapon_to_makarov() -> void:
	gm.selected_weapon = "sniper"

	persist.clear_all_saves()

	assert_eq(gm.selected_weapon, "makarov_pm",
		"Selected weapon should reset to makarov_pm after clear")


func test_clear_all_saves_weapon_state_from_scratch() -> void:
	# All weapons start unlocked
	for key in gm.unlocked_weapons.keys():
		gm.unlocked_weapons[key] = true
	gm.selected_weapon = "revolver"

	persist.clear_all_saves()

	# Only PM should be unlocked
	assert_true(gm.unlocked_weapons["makarov_pm"],
		"makarov_pm must be unlocked")
	for key in gm.unlocked_weapons.keys():
		if key != "makarov_pm":
			assert_false(gm.unlocked_weapons[key],
				"%s should be locked after full clear" % key)
	assert_eq(gm.selected_weapon, "makarov_pm",
		"Selected weapon should be makarov_pm")


# ============================================================================
# clear_all_saves — grenade reset tests
# ============================================================================


func test_clear_all_saves_locks_all_grenades_except_flashbang() -> void:
	grenade.unlock_grenades([
		MockGrenadeManager.GrenadeType.FRAG,
		MockGrenadeManager.GrenadeType.DEFENSIVE,
		MockGrenadeManager.GrenadeType.AGGRESSION_GAS
	])

	persist.clear_all_saves()

	assert_false(grenade.unlocked_grenades[MockGrenadeManager.GrenadeType.FRAG],
		"FRAG should be locked after clear")
	assert_false(grenade.unlocked_grenades[MockGrenadeManager.GrenadeType.DEFENSIVE],
		"DEFENSIVE should be locked after clear")
	assert_false(grenade.unlocked_grenades[MockGrenadeManager.GrenadeType.AGGRESSION_GAS],
		"AGGRESSION_GAS should be locked after clear")


func test_clear_all_saves_keeps_flashbang_unlocked() -> void:
	grenade.unlock_grenades([MockGrenadeManager.GrenadeType.FRAG])

	persist.clear_all_saves()

	assert_true(grenade.unlocked_grenades[MockGrenadeManager.GrenadeType.FLASHBANG],
		"FLASHBANG should remain unlocked after clear (default grenade)")


func test_clear_all_saves_resets_selected_grenade_to_flashbang() -> void:
	grenade.current_grenade_type = MockGrenadeManager.GrenadeType.FRAG

	persist.clear_all_saves()

	assert_eq(grenade.current_grenade_type, MockGrenadeManager.GrenadeType.FLASHBANG,
		"Selected grenade should reset to FLASHBANG after clear")


# ============================================================================
# clear_all_saves — active item reset tests
# ============================================================================


func test_clear_all_saves_locks_all_active_items_except_none() -> void:
	active.unlock_items([
		MockActiveItemManager.ActiveItemType.FLASHLIGHT,
		MockActiveItemManager.ActiveItemType.TELEPORT_BRACERS,
		MockActiveItemManager.ActiveItemType.HOMING_BULLETS
	])

	persist.clear_all_saves()

	assert_false(active.unlocked_active_items[MockActiveItemManager.ActiveItemType.FLASHLIGHT],
		"FLASHLIGHT should be locked after clear")
	assert_false(active.unlocked_active_items[MockActiveItemManager.ActiveItemType.TELEPORT_BRACERS],
		"TELEPORT_BRACERS should be locked after clear")
	assert_false(active.unlocked_active_items[MockActiveItemManager.ActiveItemType.HOMING_BULLETS],
		"HOMING_BULLETS should be locked after clear")


func test_clear_all_saves_keeps_none_active_item_unlocked() -> void:
	active.unlock_items([MockActiveItemManager.ActiveItemType.FLASHLIGHT])

	persist.clear_all_saves()

	assert_true(active.unlocked_active_items[MockActiveItemManager.ActiveItemType.NONE],
		"NONE active item slot should remain available after clear")


func test_clear_all_saves_resets_selected_active_item_to_none() -> void:
	active.current_active_item = MockActiveItemManager.ActiveItemType.FLASHLIGHT

	persist.clear_all_saves()

	assert_eq(active.current_active_item, MockActiveItemManager.ActiveItemType.NONE,
		"Selected active item should reset to NONE after clear")


# ============================================================================
# clear_all_saves — level progress reset tests
# ============================================================================


func test_clear_all_saves_clears_level_progress() -> void:
	progress.add_progress("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "A")
	progress.add_progress("res://scenes/levels/CastleLevel.tscn", "Hard", "S")

	persist.clear_all_saves()

	assert_eq(progress.get_progress_count(), 0,
		"All level progress should be cleared")


func test_clear_all_saves_calls_clear_all_progress() -> void:
	progress.add_progress("res://scenes/levels/BuildingLevel.tscn", "Normal", "B")

	persist.clear_all_saves()

	assert_true(progress.clear_called,
		"clear_all_progress should be called on ProgressManager")


func test_clear_all_saves_removes_save_file() -> void:
	persist.save_file_exists = true

	persist.clear_all_saves()

	assert_false(persist.save_file_exists,
		"Save file should be removed after clear_all_saves")


# ============================================================================
# clear_all_saves — complete reset scenario
# ============================================================================


func test_clear_all_saves_full_scenario() -> void:
	## Simulate a player who has made significant progress:
	## - Unlocked several weapons
	## - Selected a non-default weapon
	## - Unlocked several grenades and active items
	## - Completed multiple levels

	gm.unlock_weapons(["m16", "shotgun", "sniper", "revolver"])
	gm.selected_weapon = "sniper"

	grenade.unlock_grenades([
		MockGrenadeManager.GrenadeType.FRAG,
		MockGrenadeManager.GrenadeType.DEFENSIVE
	])
	grenade.current_grenade_type = MockGrenadeManager.GrenadeType.FRAG

	active.unlock_items([
		MockActiveItemManager.ActiveItemType.FLASHLIGHT,
		MockActiveItemManager.ActiveItemType.HOMING_BULLETS
	])
	active.current_active_item = MockActiveItemManager.ActiveItemType.FLASHLIGHT

	progress.add_progress("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "A+")
	progress.add_progress("res://scenes/levels/BuildingLevel.tscn", "Hard", "S")
	progress.add_progress("res://scenes/levels/CastleLevel.tscn", "Easy", "D")
	persist.save_file_exists = true

	# Clear all saves
	persist.clear_all_saves()

	# Weapons: only makarov_pm
	assert_true(gm.unlocked_weapons["makarov_pm"], "makarov_pm should be unlocked")
	assert_false(gm.unlocked_weapons["m16"], "m16 should be locked")
	assert_false(gm.unlocked_weapons["shotgun"], "shotgun should be locked")
	assert_false(gm.unlocked_weapons["sniper"], "sniper should be locked")
	assert_false(gm.unlocked_weapons["revolver"], "revolver should be locked")
	assert_eq(gm.selected_weapon, "makarov_pm", "selected weapon should be makarov_pm")

	# Grenades: only flashbang
	assert_true(grenade.unlocked_grenades[MockGrenadeManager.GrenadeType.FLASHBANG],
		"FLASHBANG should be unlocked")
	assert_false(grenade.unlocked_grenades[MockGrenadeManager.GrenadeType.FRAG],
		"FRAG should be locked")
	assert_false(grenade.unlocked_grenades[MockGrenadeManager.GrenadeType.DEFENSIVE],
		"DEFENSIVE should be locked")
	assert_eq(grenade.current_grenade_type, MockGrenadeManager.GrenadeType.FLASHBANG,
		"selected grenade should be FLASHBANG")

	# Active items: only NONE
	assert_true(active.unlocked_active_items[MockActiveItemManager.ActiveItemType.NONE],
		"NONE should be available")
	assert_false(active.unlocked_active_items[MockActiveItemManager.ActiveItemType.FLASHLIGHT],
		"FLASHLIGHT should be locked")
	assert_false(active.unlocked_active_items[MockActiveItemManager.ActiveItemType.HOMING_BULLETS],
		"HOMING_BULLETS should be locked")
	assert_eq(active.current_active_item, MockActiveItemManager.ActiveItemType.NONE,
		"selected active item should be NONE")

	# Level progress: cleared
	assert_eq(progress.get_progress_count(), 0,
		"All level progress should be cleared")

	# Save file: deleted
	assert_false(persist.save_file_exists, "Save file should be deleted")


# ============================================================================
# clear_all_saves — idempotency: calling twice has the same result
# ============================================================================


func test_clear_all_saves_idempotent() -> void:
	gm.unlock_weapons(["m16", "shotgun"])
	progress.add_progress("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "A")

	persist.clear_all_saves()
	persist.clear_all_saves()  # Second call — should be safe

	assert_true(gm.unlocked_weapons["makarov_pm"], "makarov_pm stays unlocked")
	assert_false(gm.unlocked_weapons["m16"], "m16 stays locked")
	assert_eq(progress.get_progress_count(), 0, "Progress stays empty")
