extends GutTest
## Unit tests for the levels_menu.gd roguelike exit fix (Issue #1324).
##
## Bug: When a roguelike run is active and the player opens the pause menu and
## selects a level via the Levels submenu, roguelike_active was not reset.
## This left roguelike_active = true in the next scene, which caused the pause
## menu in that scene to disable the armory button (armory unavailable after roguelike).
##
## Fix: levels_menu.gd now calls GameManager.roguelike_reset_session() before
## loading the level when roguelike_active is true.
##
## Issue #1324: fix рогалик (after exiting the roguelike, armory is still unavailable)


# ============================================================================
# Minimal mock GameManager — only the fields and methods used by the fix
# ============================================================================


class MockGameManager:
	var roguelike_active: bool = false
	var reset_session_called: bool = false

	func roguelike_reset_session() -> void:
		reset_session_called = true
		roguelike_active = false

	## Dynamic property getter to support game_manager.get("roguelike_active")
	## which is used by pause_menu.gd and the fix in levels_menu.gd.
	func get(property: StringName):
		if property == "roguelike_active":
			return roguelike_active
		return null


# ============================================================================
# Helper — simulate the relevant part of _on_level_selected logic
# ============================================================================


## Simulate the roguelike-reset block that the fix added to _on_level_selected.
## Returns true if reset was triggered, false if it was skipped.
func _simulate_level_selected_reset(mock_gm: MockGameManager) -> bool:
	# Mirrors the fix in scripts/ui/levels_menu.gd:
	#   if game_manager and game_manager.get("roguelike_active") == true:
	#       if game_manager.has_method("roguelike_reset_session"):
	#           game_manager.roguelike_reset_session()
	if mock_gm and mock_gm.get("roguelike_active") == true:
		if mock_gm.has_method("roguelike_reset_session"):
			mock_gm.roguelike_reset_session()
			return true
	return false


# ============================================================================
# Tests
# ============================================================================


func test_roguelike_active_is_reset_when_level_selected_during_run() -> void:
	## Issue #1324 regression: roguelike_active must be cleared so the armory
	## button is re-enabled in the next scene's pause menu.
	var gm := MockGameManager.new()
	gm.roguelike_active = true

	_simulate_level_selected_reset(gm)

	assert_false(gm.roguelike_active,
		"roguelike_active must be false after selecting a level during a roguelike run")


func test_roguelike_reset_session_is_called_when_active() -> void:
	var gm := MockGameManager.new()
	gm.roguelike_active = true

	_simulate_level_selected_reset(gm)

	assert_true(gm.reset_session_called,
		"roguelike_reset_session() must be called when selecting a level while roguelike_active is true")


func test_roguelike_reset_not_called_when_not_in_run() -> void:
	## Ensure normal (non-roguelike) level selection is unaffected.
	var gm := MockGameManager.new()
	gm.roguelike_active = false  # Not in a run

	_simulate_level_selected_reset(gm)

	assert_false(gm.reset_session_called,
		"roguelike_reset_session() must NOT be called when roguelike_active is false")


func test_roguelike_active_remains_false_when_not_in_run() -> void:
	var gm := MockGameManager.new()
	gm.roguelike_active = false

	_simulate_level_selected_reset(gm)

	assert_false(gm.roguelike_active,
		"roguelike_active must remain false when level is selected outside a roguelike run")


func test_levels_menu_script_contains_roguelike_reset_fix() -> void:
	## Source-level guard: verify the fix is present in levels_menu.gd so a
	## future refactor cannot silently remove it.
	var file := FileAccess.open("res://scripts/ui/levels_menu.gd", FileAccess.READ)
	if file == null:
		fail_test("Could not open scripts/ui/levels_menu.gd for reading")
		return

	var source: String = file.get_as_text()
	file.close()

	assert_true(
		"roguelike_reset_session" in source,
		"levels_menu.gd must call roguelike_reset_session() (Issue #1324 fix)")
	assert_true(
		"roguelike_active" in source,
		"levels_menu.gd must check roguelike_active before resetting (Issue #1324 fix)")
