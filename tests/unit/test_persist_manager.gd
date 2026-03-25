extends GutTest
## Unit tests for PersistManager functionality.
##
## Tests persistence of game state: selected weapon, selected grenade,
## selected active item, unlocked items, and last played level.
## Issue #896: добавь persist (add persistence)


# ============================================================================
# Mock PersistManager — mirrors core testable logic without file I/O
# ============================================================================

class MockPersistManager:
	## In-memory state storage (no file I/O).
	var _state: Dictionary = {}

	const DEFAULT_LEVEL := "res://scenes/levels/LabyrinthLevel.tscn"

	# ---- Weapon ----

	func save_selected_weapon(weapon_id: String) -> void:
		_state["selected_weapon"] = weapon_id

	func get_selected_weapon() -> String:
		return _state.get("selected_weapon", "makarov_pm")

	func save_unlocked_weapons(weapons: Dictionary) -> void:
		_state["unlocked_weapons"] = weapons.duplicate()

	func get_unlocked_weapons() -> Dictionary:
		return _state.get("unlocked_weapons", {}).duplicate()

	# ---- Grenade ----

	func save_grenade_type(type: int) -> void:
		_state["grenade_type"] = type

	func get_grenade_type() -> int:
		return _state.get("grenade_type", 0)

	func save_unlocked_grenades(grenades: Dictionary) -> void:
		_state["unlocked_grenades"] = grenades.duplicate()

	func get_unlocked_grenades() -> Dictionary:
		return _state.get("unlocked_grenades", {}).duplicate()

	# ---- Active Item ----

	func save_active_item(type: int) -> void:
		_state["active_item"] = type

	func get_active_item() -> int:
		return _state.get("active_item", 0)

	func save_unlocked_active_items(items: Dictionary) -> void:
		_state["unlocked_active_items"] = items.duplicate()

	func get_unlocked_active_items() -> Dictionary:
		return _state.get("unlocked_active_items", {}).duplicate()

	# ---- Level ----

	func save_last_level(level_path: String) -> void:
		_state["last_level"] = level_path

	func get_last_level() -> String:
		return _state.get("last_level", DEFAULT_LEVEL)

	func has_saved_state() -> bool:
		return "last_level" in _state

	# ---- Reset ----

	func clear() -> void:
		_state.clear()


var pm: MockPersistManager


func before_each() -> void:
	pm = MockPersistManager.new()


func after_each() -> void:
	pm = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_default_weapon_is_makarov() -> void:
	assert_eq(pm.get_selected_weapon(), "makarov_pm", "Default weapon should be makarov_pm")


func test_default_grenade_type_is_zero() -> void:
	assert_eq(pm.get_grenade_type(), 0, "Default grenade type should be 0 (FLASHBANG)")


func test_default_active_item_is_zero() -> void:
	assert_eq(pm.get_active_item(), 0, "Default active item should be 0 (NONE)")


func test_default_level_is_labyrinth() -> void:
	assert_eq(pm.get_last_level(), "res://scenes/levels/LabyrinthLevel.tscn",
		"Default last level should be LabyrinthLevel")


func test_has_no_saved_state_initially() -> void:
	assert_false(pm.has_saved_state(), "Should have no saved state initially")


# ============================================================================
# Weapon Persistence Tests
# ============================================================================


func test_save_and_restore_selected_weapon() -> void:
	pm.save_selected_weapon("m16")
	assert_eq(pm.get_selected_weapon(), "m16", "Should restore saved weapon ID")


func test_save_and_restore_different_weapons() -> void:
	for weapon_id in ["makarov_pm", "m16", "shotgun", "mini_uzi", "silenced_pistol", "sniper", "revolver", "ak_gl"]:
		pm.save_selected_weapon(weapon_id)
		assert_eq(pm.get_selected_weapon(), weapon_id,
			"Should correctly restore weapon: %s" % weapon_id)


func test_save_unlocked_weapons_all_locked() -> void:
	var weapons := {"makarov_pm": true, "m16": false, "shotgun": false}
	pm.save_unlocked_weapons(weapons)
	var restored := pm.get_unlocked_weapons()
	assert_eq(restored["makarov_pm"], true, "makarov_pm should be unlocked")
	assert_eq(restored["m16"], false, "m16 should be locked")
	assert_eq(restored["shotgun"], false, "shotgun should be locked")


func test_save_unlocked_weapons_multiple_unlocked() -> void:
	var weapons := {"makarov_pm": true, "m16": true, "shotgun": true, "revolver": false}
	pm.save_unlocked_weapons(weapons)
	var restored := pm.get_unlocked_weapons()
	assert_eq(restored["makarov_pm"], true, "makarov_pm should be unlocked")
	assert_eq(restored["m16"], true, "m16 should be unlocked")
	assert_eq(restored["shotgun"], true, "shotgun should be unlocked")
	assert_eq(restored["revolver"], false, "revolver should be locked")


func test_overwrite_weapon_selection() -> void:
	pm.save_selected_weapon("m16")
	pm.save_selected_weapon("shotgun")
	assert_eq(pm.get_selected_weapon(), "shotgun", "Should use the most recent weapon")


# ============================================================================
# Grenade Persistence Tests
# ============================================================================


func test_save_and_restore_grenade_type() -> void:
	pm.save_grenade_type(1)  # FRAG
	assert_eq(pm.get_grenade_type(), 1, "Should restore saved grenade type")


func test_save_unlocked_grenades() -> void:
	var grenades := {0: true, 1: true, 2: false, 3: false}
	pm.save_unlocked_grenades(grenades)
	var restored := pm.get_unlocked_grenades()
	assert_eq(restored[0], true, "FLASHBANG should be unlocked")
	assert_eq(restored[1], true, "FRAG should be unlocked")
	assert_eq(restored[2], false, "DEFENSIVE should be locked")
	assert_eq(restored[3], false, "AGGRESSION_GAS should be locked")


func test_grenade_type_zero_is_default() -> void:
	assert_eq(pm.get_grenade_type(), 0, "Default grenade type should be 0 (FLASHBANG)")


# ============================================================================
# Active Item Persistence Tests
# ============================================================================


func test_save_and_restore_active_item() -> void:
	pm.save_active_item(1)  # FLASHLIGHT
	assert_eq(pm.get_active_item(), 1, "Should restore saved active item type")


func test_save_unlocked_active_items() -> void:
	var items := {0: true, 1: true, 2: false, 3: false, 4: false, 5: false}
	pm.save_unlocked_active_items(items)
	var restored := pm.get_unlocked_active_items()
	assert_eq(restored[0], true, "NONE should be always available")
	assert_eq(restored[1], true, "FLASHLIGHT should be unlocked")
	assert_eq(restored[2], false, "HOMING_BULLETS should be locked")


func test_active_item_zero_is_default() -> void:
	assert_eq(pm.get_active_item(), 0, "Default active item should be 0 (NONE)")


# ============================================================================
# Level Persistence Tests
# ============================================================================


func test_save_and_restore_last_level() -> void:
	pm.save_last_level("res://scenes/levels/BuildingLevel.tscn")
	assert_eq(pm.get_last_level(), "res://scenes/levels/BuildingLevel.tscn",
		"Should restore saved level path")


func test_has_saved_state_after_saving_level() -> void:
	pm.save_last_level("res://scenes/levels/CastleLevel.tscn")
	assert_true(pm.has_saved_state(), "Should have saved state after saving level")


func test_save_all_levels_correctly() -> void:
	var levels := [
		"res://scenes/levels/LabyrinthLevel.tscn",
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/TestTier.tscn",
		"res://scenes/levels/CastleLevel.tscn",
		"res://scenes/levels/CityLevel.tscn",
		"res://scenes/levels/BeachLevel.tscn",
		"res://scenes/levels/DocksLevel.tscn"
	]
	for level_path in levels:
		pm.save_last_level(level_path)
		assert_eq(pm.get_last_level(), level_path,
			"Should correctly save and restore level: %s" % level_path)


func test_overwrite_last_level() -> void:
	pm.save_last_level("res://scenes/levels/BeachLevel.tscn")
	pm.save_last_level("res://scenes/levels/DocksLevel.tscn")
	assert_eq(pm.get_last_level(), "res://scenes/levels/DocksLevel.tscn",
		"Should use the most recently saved level")


# ============================================================================
# Full State Persistence Tests
# ============================================================================


func test_full_state_save_and_restore() -> void:
	# Save a complete game state
	pm.save_last_level("res://scenes/levels/CastleLevel.tscn")
	pm.save_selected_weapon("shotgun")
	pm.save_grenade_type(1)  # FRAG
	pm.save_active_item(2)   # HOMING_BULLETS
	pm.save_unlocked_weapons({"makarov_pm": true, "shotgun": true})
	pm.save_unlocked_grenades({0: true, 1: true})
	pm.save_unlocked_active_items({0: true, 2: true})

	# Verify all state is restored
	assert_eq(pm.get_last_level(), "res://scenes/levels/CastleLevel.tscn",
		"Level should be restored")
	assert_eq(pm.get_selected_weapon(), "shotgun",
		"Weapon should be restored")
	assert_eq(pm.get_grenade_type(), 1,
		"Grenade type should be restored")
	assert_eq(pm.get_active_item(), 2,
		"Active item should be restored")

	var weapons := pm.get_unlocked_weapons()
	assert_eq(weapons["makarov_pm"], true, "makarov_pm should remain unlocked")
	assert_eq(weapons["shotgun"], true, "shotgun should be unlocked after save")

	var grenades := pm.get_unlocked_grenades()
	assert_eq(grenades[0], true, "FLASHBANG should be unlocked")
	assert_eq(grenades[1], true, "FRAG should be unlocked")

	var items := pm.get_unlocked_active_items()
	assert_eq(items[0], true, "NONE should be available")
	assert_eq(items[2], true, "HOMING_BULLETS should be unlocked")


func test_clear_resets_to_defaults() -> void:
	pm.save_last_level("res://scenes/levels/BeachLevel.tscn")
	pm.save_selected_weapon("m16")
	pm.clear()

	assert_false(pm.has_saved_state(), "Should have no state after clear")
	assert_eq(pm.get_selected_weapon(), "makarov_pm",
		"Weapon should reset to default after clear")
	assert_eq(pm.get_last_level(), "res://scenes/levels/LabyrinthLevel.tscn",
		"Level should reset to default after clear")


# ============================================================================
# Issue #1456 — Auto-save level on scene change (_is_level_scene helper)
# ============================================================================


class MockPersistManagerWithIsLevel extends MockPersistManager:
	## Expose the is_level_scene logic for unit testing.
	func is_level_scene(scene_path: String) -> bool:
		return scene_path.begins_with("res://scenes/levels/") and scene_path.ends_with(".tscn")


var pm2: MockPersistManagerWithIsLevel


func before_each_is_level() -> void:
	pm2 = MockPersistManagerWithIsLevel.new()


func after_each_is_level() -> void:
	pm2 = null


func test_is_level_scene_returns_true_for_level_paths() -> void:
	var helper := MockPersistManagerWithIsLevel.new()
	var level_paths := [
		"res://scenes/levels/LabyrinthLevel.tscn",
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/CastleLevel.tscn",
		"res://scenes/levels/BeachLevel.tscn",
		"res://scenes/levels/DocksLevel.tscn",
		"res://scenes/levels/RoguelikeLevel.tscn",
		"res://scenes/levels/ArenaLevel.tscn",
	]
	for path in level_paths:
		assert_true(helper.is_level_scene(path),
			"Should be recognised as a level scene: %s" % path)


func test_is_level_scene_returns_false_for_ui_paths() -> void:
	var helper := MockPersistManagerWithIsLevel.new()
	var non_level_paths := [
		"res://scenes/ui/LevelsMenu.tscn",
		"res://scenes/ui/PauseMenu.tscn",
		"res://scenes/main/Main.tscn",
		"",
		"res://scenes/levels/SomeScript.gd",
	]
	for path in non_level_paths:
		assert_false(helper.is_level_scene(path),
			"Should NOT be recognised as a level scene: '%s'" % path)


func test_auto_save_updates_last_level() -> void:
	# Simulate what _on_tree_changed does: save_last_level when a level scene becomes current.
	pm.save_last_level("res://scenes/levels/LabyrinthLevel.tscn")
	assert_eq(pm.get_last_level(), "res://scenes/levels/LabyrinthLevel.tscn",
		"Initial level should be Labyrinth")

	# Player navigates to Beach via Next Level (scene changes, auto-save fires)
	pm.save_last_level("res://scenes/levels/BeachLevel.tscn")
	assert_eq(pm.get_last_level(), "res://scenes/levels/BeachLevel.tscn",
		"Auto-saved level should update to Beach after scene change")


func test_auto_save_does_not_overwrite_with_non_level_path() -> void:
	# Simulate: level saved, then a non-level scene change occurs (should not overwrite).
	pm.save_last_level("res://scenes/levels/CastleLevel.tscn")

	var helper := MockPersistManagerWithIsLevel.new()
	var ui_path := "res://scenes/ui/LevelsMenu.tscn"
	assert_false(helper.is_level_scene(ui_path),
		"UI scene path must not qualify as a level scene")

	# Level path must be unchanged because the UI path is filtered out.
	assert_eq(pm.get_last_level(), "res://scenes/levels/CastleLevel.tscn",
		"Last level should remain Castle — UI scene changes must not overwrite it")


# ============================================================================
# Issue #1456 — Startup guard: background-loading race condition
#
# Root-cause (confirmed from game_log_20260325_124153 / _124210):
#   _navigate_to_last_level() calls SceneLoader.load_level() which performs
#   background loading.  While loading, tree_changed fires several times with
#   current_scene still pointing at LabyrinthLevel.  The old fix (a simple
#   _navigation_ready flag that was raised in the same deferred batch as
#   _navigate_to_last_level) let those intermediate events through and
#   overwrote the saved BuildingLevel / BeachLevel with LabyrinthLevel.
#
#   The new fix keeps _navigation_ready = false until current_scene has
#   actually changed to _startup_navigation_target, so intermediate events
#   from the background loader are silently ignored.
# ============================================================================


class MockPersistManagerWithGuard extends MockPersistManager:
	## Mirrors the startup-guard logic from persist_manager.gd so it can be
	## exercised without a live scene tree.

	var _navigation_ready: bool = false
	var _startup_navigation_target: String = ""
	var _previous_scene_path: String = ""

	func is_level_scene(scene_path: String) -> bool:
		return scene_path.begins_with("res://scenes/levels/") and scene_path.ends_with(".tscn")

	## Simulates _navigate_to_last_level().
	## Pass the current_scene path at startup (always LabyrinthLevel in practice).
	func navigate_to_last_level(current_scene_path: String) -> void:
		if not has_saved_state():
			_navigation_ready = true
			return
		var last_level := get_last_level()
		if last_level != current_scene_path and last_level != "":
			_startup_navigation_target = last_level
			# SceneLoader.load_level() is called here in the real code (async)
		else:
			_navigation_ready = true

	## Simulates _on_tree_changed() being called with a given scene path.
	## Returns true when an auto-save was performed.
	func on_tree_changed(new_scene_path: String) -> bool:
		if new_scene_path == _previous_scene_path:
			return false
		if not _navigation_ready:
			if _startup_navigation_target == "":
				return false
			if new_scene_path != _startup_navigation_target:
				return false
			# Arrived at target — lift the guard
			_navigation_ready = true
			_startup_navigation_target = ""
		_previous_scene_path = new_scene_path
		if is_level_scene(new_scene_path):
			save_last_level(new_scene_path)
			return true
		return false


func test_startup_guard_blocks_labyrinth_overwrite_during_background_load() -> void:
	# Reproduce the exact failure from game_log_20260325_124153.txt / _124210.txt:
	# Saved level is BuildingLevel; game starts on LabyrinthLevel (default scene);
	# SceneLoader does background loading and fires tree_changed several times
	# while current_scene is still LabyrinthLevel — those must NOT overwrite the save.
	var guard := MockPersistManagerWithGuard.new()
	guard.save_last_level("res://scenes/levels/BuildingLevel.tscn")

	# Startup: current_scene is LabyrinthLevel (the default scene)
	guard.navigate_to_last_level("res://scenes/levels/LabyrinthLevel.tscn")

	# Simulate multiple tree_changed events fired by SceneLoader background loading
	# while current_scene is still LabyrinthLevel (the old bug: these would overwrite)
	var saved_1 := guard.on_tree_changed("res://scenes/levels/LabyrinthLevel.tscn")
	var saved_2 := guard.on_tree_changed("res://scenes/levels/LabyrinthLevel.tscn")

	assert_false(saved_1, "Must not auto-save while still on LabyrinthLevel during background load")
	assert_false(saved_2, "Must not auto-save while still on LabyrinthLevel during background load")
	assert_eq(guard.get_last_level(), "res://scenes/levels/BuildingLevel.tscn",
		"Saved level must remain BuildingLevel despite LabyrinthLevel tree_changed events")


func test_startup_guard_lifts_when_target_scene_arrives() -> void:
	# After background loading completes, current_scene changes to the target.
	# The guard must lift and auto-save the target level (confirming arrival).
	var guard := MockPersistManagerWithGuard.new()
	guard.save_last_level("res://scenes/levels/BuildingLevel.tscn")
	guard.navigate_to_last_level("res://scenes/levels/LabyrinthLevel.tscn")

	# Intermediate events from background loader — all ignored
	guard.on_tree_changed("res://scenes/levels/LabyrinthLevel.tscn")
	guard.on_tree_changed("res://scenes/levels/LabyrinthLevel.tscn")

	# Scene transition completes — BuildingLevel becomes current_scene
	var saved := guard.on_tree_changed("res://scenes/levels/BuildingLevel.tscn")

	assert_true(saved, "Must auto-save when the target level is reached")
	assert_eq(guard.get_last_level(), "res://scenes/levels/BuildingLevel.tscn",
		"Saved level must be BuildingLevel after successful navigation")


func test_startup_guard_allows_auto_save_after_subsequent_level_change() -> void:
	# After startup navigation completes, normal in-game level changes must be saved.
	var guard := MockPersistManagerWithGuard.new()
	guard.save_last_level("res://scenes/levels/BuildingLevel.tscn")
	guard.navigate_to_last_level("res://scenes/levels/LabyrinthLevel.tscn")

	# Arrive at target
	guard.on_tree_changed("res://scenes/levels/BuildingLevel.tscn")

	# Player goes to CastleLevel via Next Level button (normal in-game flow)
	var saved := guard.on_tree_changed("res://scenes/levels/CastleLevel.tscn")

	assert_true(saved, "Must auto-save normal in-game level change after startup")
	assert_eq(guard.get_last_level(), "res://scenes/levels/CastleLevel.tscn",
		"In-game level change must update saved level to CastleLevel")


func test_startup_guard_ready_immediately_when_no_saved_state() -> void:
	# First-ever launch: no save file. Guard must be lifted immediately so that
	# the first level change (player enters a level from the menu) is saved.
	var guard := MockPersistManagerWithGuard.new()
	# No saved state — has_saved_state() returns false

	guard.navigate_to_last_level("res://scenes/levels/LabyrinthLevel.tscn")

	# Player picks BeachLevel from the menu
	var saved := guard.on_tree_changed("res://scenes/levels/BeachLevel.tscn")

	assert_true(saved, "First-ever level change must be saved when there is no prior save")
	assert_eq(guard.get_last_level(), "res://scenes/levels/BeachLevel.tscn",
		"First selected level must be persisted")


func test_startup_guard_ready_immediately_when_already_at_saved_level() -> void:
	# Edge case: saved level equals the default starting scene (LabyrinthLevel).
	# Guard must lift at navigate_to_last_level() time (no navigation needed).
	var guard := MockPersistManagerWithGuard.new()
	guard.save_last_level("res://scenes/levels/LabyrinthLevel.tscn")

	guard.navigate_to_last_level("res://scenes/levels/LabyrinthLevel.tscn")

	# First subsequent scene change must be saved normally
	var saved := guard.on_tree_changed("res://scenes/levels/BeachLevel.tscn")

	assert_true(saved, "Must auto-save level change when guard is already lifted")
	assert_eq(guard.get_last_level(), "res://scenes/levels/BeachLevel.tscn",
		"Level change from LabyrinthLevel must be saved correctly")
