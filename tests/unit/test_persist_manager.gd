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
# Startup Guard Tests (Issue #1456)
# ============================================================================
# These tests use a MockStartupGuard that mirrors the _navigation_ready /
# _startup_navigation_target / _on_tree_changed logic without requiring a
# live SceneTree.  They document the exact scenarios that caused the three
# previous fix attempts to fail.
# ============================================================================

class MockStartupGuard:
	## Mirrors the startup-guard fields in PersistManager.
	var navigation_ready: bool = false
	var startup_navigation_target: String = ""

	## Saved level (represents the last entry in game_state.cfg).
	var saved_level: String = "res://scenes/levels/LabyrinthLevel.tscn"

	const DEFAULT_LEVEL := "res://scenes/levels/LabyrinthLevel.tscn"

	## Simulate _navigate_to_last_level() when a non-default level is saved.
	## @param saved: the level path from the save file.
	## @param current: the scene that is currently active (LabyrinthLevel at startup).
	func start_navigation(saved: String, current: String) -> void:
		if saved == current or saved == "":
			navigation_ready = true
			return
		startup_navigation_target = saved

	## Simulate _navigate_to_last_level() when no save file exists (first launch).
	func start_navigation_no_save() -> void:
		navigation_ready = true

	## Simulate _on_tree_changed(current_scene.scene_file_path).
	## Returns true if an auto-save was performed, false if the guard blocked it.
	func on_tree_changed(incoming_path: String) -> bool:
		if incoming_path == "" or incoming_path == saved_level:
			return false  # same scene or empty — no save needed

		if not navigation_ready:
			if startup_navigation_target == "":
				return false  # guard active but no target — ignore
			if incoming_path != startup_navigation_target:
				return false  # still waiting — ignore LabyrinthLevel events
			# Arrived at target — lift the guard
			navigation_ready = true
			startup_navigation_target = ""

		# Guard is lifted — auto-save
		saved_level = incoming_path
		return true


var guard: MockStartupGuard


func before_each_guard() -> void:
	guard = MockStartupGuard.new()


func after_each_guard() -> void:
	guard = null


## Scenario: background-loader fires tree_changed while still on LabyrinthLevel.
## The guard must block the save to prevent overwriting BeachLevel with LabyrinthLevel.
func test_startup_guard_blocks_labyrinth_overwrite_during_background_load() -> void:
	var g := MockStartupGuard.new()
	g.saved_level = "res://scenes/levels/BeachLevel.tscn"
	g.start_navigation("res://scenes/levels/BeachLevel.tscn",
			"res://scenes/levels/LabyrinthLevel.tscn")

	# SceneLoader background loading fires tree_changed, current_scene is still Labyrinth
	var saved := g.on_tree_changed("res://scenes/levels/LabyrinthLevel.tscn")
	assert_false(saved, "Guard should block save of LabyrinthLevel during background load")
	assert_eq(g.saved_level, "res://scenes/levels/BeachLevel.tscn",
		"Saved level must not be overwritten during startup navigation")


## Scenario: current_scene actually changes to BeachLevel — guard should lift and save.
func test_startup_guard_lifts_when_target_scene_arrives() -> void:
	var g := MockStartupGuard.new()
	g.saved_level = "res://scenes/levels/BeachLevel.tscn"
	g.start_navigation("res://scenes/levels/BeachLevel.tscn",
			"res://scenes/levels/LabyrinthLevel.tscn")

	# First: intermediate Labyrinth event — blocked
	var blocked := g.on_tree_changed("res://scenes/levels/LabyrinthLevel.tscn")
	assert_false(blocked, "Intermediate Labyrinth event should be blocked")

	# Then: target arrives
	var saved := g.on_tree_changed("res://scenes/levels/BeachLevel.tscn")
	assert_true(saved, "Guard should lift and save when target scene arrives")
	assert_true(g.navigation_ready, "navigation_ready should be true after target arrives")
	assert_eq(g.startup_navigation_target, "", "startup_navigation_target should be cleared")
	assert_eq(g.saved_level, "res://scenes/levels/BeachLevel.tscn",
		"Saved level should remain BeachLevel after guard lifts")


## Scenario: after startup guard lifts, subsequent scene changes are auto-saved normally.
func test_startup_guard_allows_auto_save_after_subsequent_level_change() -> void:
	var g := MockStartupGuard.new()
	g.saved_level = "res://scenes/levels/BeachLevel.tscn"
	g.start_navigation("res://scenes/levels/BeachLevel.tscn",
			"res://scenes/levels/LabyrinthLevel.tscn")

	# Target arrives — lifts guard
	g.on_tree_changed("res://scenes/levels/BeachLevel.tscn")
	assert_true(g.navigation_ready, "Guard should be lifted")

	# Player navigates to CastleLevel via LevelsMenu
	var saved := g.on_tree_changed("res://scenes/levels/CastleLevel.tscn")
	assert_true(saved, "Should auto-save subsequent level changes after guard is lifted")
	assert_eq(g.saved_level, "res://scenes/levels/CastleLevel.tscn",
		"CastleLevel should be the new saved level")


## Scenario: no save file exists (first launch) — guard should be ready immediately.
func test_startup_guard_ready_immediately_when_no_saved_state() -> void:
	var g := MockStartupGuard.new()
	g.start_navigation_no_save()

	assert_true(g.navigation_ready,
		"navigation_ready should be true immediately on first launch")
	assert_eq(g.startup_navigation_target, "",
		"startup_navigation_target should be empty on first launch")


## Scenario: saved level == current scene at startup (LabyrinthLevel saved, starts on Labyrinth).
func test_startup_guard_ready_immediately_when_already_at_saved_level() -> void:
	var g := MockStartupGuard.new()
	g.saved_level = "res://scenes/levels/LabyrinthLevel.tscn"
	g.start_navigation("res://scenes/levels/LabyrinthLevel.tscn",
			"res://scenes/levels/LabyrinthLevel.tscn")

	assert_true(g.navigation_ready,
		"navigation_ready should be true immediately when already at saved level")
	assert_eq(g.startup_navigation_target, "",
		"startup_navigation_target should be empty when no navigation needed")


# ============================================================================
# clear_all_saves Active Item Reset Tests (Issue #1691)
# ============================================================================
# Verifies that the clear_all_saves() reset logic preserves items that are
# unconditionally unlocked (e.g. LOUDSPEAKER) and only resets condition-gated
# items (items listed in UnlockManager's condition tables).
# ============================================================================

class MockClearAllSavesHelper:
	## Simulates the reset logic from persist_manager.clear_all_saves().
	## condition_gated: items that have an unlock condition (should be reset to false).
	## item_defaults: the starting unlock state from ActiveItemManager (the defaults).
	func reset_active_items(item_defaults: Dictionary, condition_gated: Array) -> Dictionary:
		var result: Dictionary = item_defaults.duplicate()
		for item_type in result.keys():
			if item_type in condition_gated:
				result[item_type] = false
			# else: unconditionally-unlocked items keep their default value
		return result


func test_clear_all_saves_preserves_loudspeaker_unlock_state() -> void:
	## LOUDSPEAKER (type 11) has no unlock condition — should stay true after clear.
	## Regression test for Issue #1691: clear_all_saves() was resetting LOUDSPEAKER to false.
	var helper := MockClearAllSavesHelper.new()
	const NONE := 0
	const LOUDSPEAKER := 11
	const FLASHLIGHT := 1
	const TELEPORT_BRACERS := 3

	# Simulate ActiveItemManager defaults: NONE and LOUDSPEAKER are true, others false
	var item_defaults := {
		NONE: true,
		FLASHLIGHT: false,
		TELEPORT_BRACERS: false,
		LOUDSPEAKER: true,  # No unlock condition — freely available from start (Issue #1691)
	}

	# Condition-gated items (from UnlockManager): FLASHLIGHT and TELEPORT_BRACERS require conditions
	var condition_gated := [FLASHLIGHT, TELEPORT_BRACERS]

	var result := helper.reset_active_items(item_defaults, condition_gated)

	assert_true(result[NONE], "NONE should remain unlocked after clear")
	assert_true(result[LOUDSPEAKER],
		"LOUDSPEAKER must remain unlocked after clear_all_saves (Issue #1691) — it has no unlock condition")
	assert_false(result[FLASHLIGHT], "FLASHLIGHT should be reset to locked (has condition)")
	assert_false(result[TELEPORT_BRACERS], "TELEPORT_BRACERS should be reset to locked (has condition)")


func test_clear_all_saves_resets_condition_gated_items() -> void:
	## Condition-gated items that were previously unlocked should become locked after clear.
	var helper := MockClearAllSavesHelper.new()
	const NONE := 0
	const LOUDSPEAKER := 11
	const FLASHLIGHT := 1
	const LASER_SIGHT := 9

	# Simulate a save state where the player had unlocked FLASHLIGHT and LASER_SIGHT
	var item_state := {
		NONE: true,
		LOUDSPEAKER: true,
		FLASHLIGHT: true,   # was unlocked (earned)
		LASER_SIGHT: true,  # was unlocked (earned)
	}

	var condition_gated := [FLASHLIGHT, LASER_SIGHT]

	var result := helper.reset_active_items(item_state, condition_gated)

	assert_true(result[NONE], "NONE should remain unlocked")
	assert_true(result[LOUDSPEAKER], "LOUDSPEAKER should remain unlocked (no condition)")
	assert_false(result[FLASHLIGHT], "FLASHLIGHT should be reset — condition-gated")
	assert_false(result[LASER_SIGHT], "LASER_SIGHT should be reset — condition-gated")


# ============================================================================
# clear_all_saves Difficulty Reset Tests (Issue #1734)
# ============================================================================
# Verifies that clear_all_saves() also resets the DifficultyManager so that
# is_first_launch() returns true on the next startup, causing the difficulty
# selection screen to appear — matching a full "reset to first-launch state".
# ============================================================================

class MockDifficultyManagerForClear:
	## Tracks whether the settings file has been deleted (i.e. reset was called).
	var _reset_called: bool = false
	var current_difficulty: int = 0  # 0 = NORMAL

	func reset_to_default() -> void:
		current_difficulty = 0
		_reset_called = true

	func is_first_launch() -> bool:
		return _reset_called


func test_clear_all_saves_resets_difficulty_to_enable_first_launch_screen() -> void:
	## After clear_all_saves(), the DifficultyManager must be reset so that
	## is_first_launch() returns true and the difficulty screen appears on next boot.
	## Regression test for Issue #1734: difficulty_settings.cfg was not deleted on save clear.
	var difficulty_mock := MockDifficultyManagerForClear.new()
	# Simulate: difficulty was set by the player (Power Fantasy)
	difficulty_mock.current_difficulty = 3  # POWER_FANTASY
	difficulty_mock._reset_called = false

	# Simulate what clear_all_saves() does:
	difficulty_mock.reset_to_default()

	assert_true(difficulty_mock.is_first_launch(),
		"is_first_launch() must return true after clear_all_saves() resets DifficultyManager (Issue #1734)")
	assert_eq(difficulty_mock.current_difficulty, 0,
		"Difficulty must be reset to NORMAL (0) after clear_all_saves()")


# ============================================================================
# First-Launch Difficulty Menu in _navigate_to_last_level (Issue #1734)
# ============================================================================
# Verifies that PersistManager (not main.gd, which is never the startup scene)
# is responsible for showing the first-launch difficulty picker. The project's
# run/main_scene is LabyrinthLevel.tscn, so main.gd._ready() is never called
# at startup — the check must live in an autoload.
# ============================================================================

class MockPersistManagerFirstLaunch:
	## Whether DifficultyManager reported first launch.
	var _is_first_launch: bool = false
	## Whether the first-launch difficulty menu was shown.
	var first_launch_menu_shown: bool = false
	## Whether normal level navigation was performed.
	var navigation_performed: bool = false
	## Whether navigation was deferred until after difficulty selection.
	var navigation_deferred: bool = false
	## Whether the tree would be paused while waiting for the choice (Issue #1812).
	var tree_paused: bool = false
	## Whether quick restart was requested after the choice (Issue #1812).
	var restart_requested: bool = false
	## Whether GameManager is available for quick restart.
	var has_game_manager: bool = true

	func simulate_navigate_to_last_level() -> void:
		if _is_first_launch:
			first_launch_menu_shown = true
			navigation_deferred = true
			tree_paused = true
			return
		navigation_performed = true

	func simulate_difficulty_selected() -> void:
		first_launch_menu_shown = false
		navigation_deferred = false
		tree_paused = false
		if has_game_manager:
			restart_requested = true
		else:
			navigation_performed = true


func test_first_launch_shows_difficulty_menu_not_level() -> void:
	## On first launch, _navigate_to_last_level() must show the difficulty picker
	## and NOT immediately navigate to the last level (Issue #1734 root cause #2:
	## main.gd is never the startup scene, so PersistManager must handle this).
	var mock := MockPersistManagerFirstLaunch.new()
	mock._is_first_launch = true

	mock.simulate_navigate_to_last_level()

	assert_true(mock.first_launch_menu_shown,
		"Difficulty menu must be shown on first launch by PersistManager (Issue #1734)")
	assert_false(mock.navigation_performed,
		"Level navigation must NOT happen before a difficulty is chosen (Issue #1734)")
	assert_true(mock.navigation_deferred,
		"Navigation must be deferred until difficulty is selected (Issue #1734)")


func test_non_first_launch_skips_difficulty_menu() -> void:
	## On subsequent launches (difficulty_settings.cfg exists), the picker must
	## NOT appear and level navigation must proceed immediately.
	var mock := MockPersistManagerFirstLaunch.new()
	mock._is_first_launch = false

	mock.simulate_navigate_to_last_level()

	assert_false(mock.first_launch_menu_shown,
		"Difficulty menu must NOT be shown when not a first launch (Issue #1734)")
	assert_true(mock.navigation_performed,
		"Level navigation must proceed immediately on non-first launch (Issue #1734)")


func test_navigation_resumes_after_difficulty_selected() -> void:
	## After the player picks a difficulty in first-launch mode, level navigation
	## must resume (Issue #1734).
	var mock := MockPersistManagerFirstLaunch.new()
	mock._is_first_launch = true
	mock.simulate_navigate_to_last_level()
	assert_false(mock.navigation_performed, "Navigation must be deferred initially")

	mock.simulate_difficulty_selected()

	assert_true(mock.navigation_performed,
		"Level navigation must resume after difficulty is selected (Issue #1734)")


func test_first_launch_menu_closed_after_difficulty_selected() -> void:
	## The first-launch menu must be hidden/freed after the player picks a difficulty.
	var mock := MockPersistManagerFirstLaunch.new()
	mock._is_first_launch = true
	mock.simulate_navigate_to_last_level()
	assert_true(mock.first_launch_menu_shown, "Menu must be visible before selection")

	mock.simulate_difficulty_selected()

	assert_false(mock.first_launch_menu_shown,
		"First-launch menu must be closed after difficulty is selected (Issue #1734)")


func test_first_launch_pauses_tree_until_difficulty_selected() -> void:
	var mock := MockPersistManagerFirstLaunch.new()
	mock._is_first_launch = true

	mock.simulate_navigate_to_last_level()

	assert_true(mock.tree_paused,
		"Game tree must be paused while first-launch difficulty selection is open (Issue #1812)")

	mock.simulate_difficulty_selected()

	assert_false(mock.tree_paused,
		"Game tree must be unpaused after first-launch difficulty selection completes (Issue #1812)")


func test_first_launch_selection_requests_quick_restart_when_game_manager_exists() -> void:
	var mock := MockPersistManagerFirstLaunch.new()
	mock._is_first_launch = true
	mock.has_game_manager = true

	mock.simulate_navigate_to_last_level()
	mock.simulate_difficulty_selected()

	assert_true(mock.restart_requested,
		"First-launch difficulty selection must trigger quick restart when GameManager is available (Issue #1812)")
	assert_false(mock.navigation_performed,
		"Fallback navigation should not run when quick restart is available (Issue #1812)")
