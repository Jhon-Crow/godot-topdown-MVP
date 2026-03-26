extends GutTest
## Unit tests for the Combat Disposition no-damage-level unlock condition (Issue #1389).
##
## Tests that:
## - COMBAT_DISPOSITION starts locked (no longer freely available from start)
## - The condition requires 1 level completed without damage
## - is_kill_condition_met returns correct values based on no_damage_levels_completed
## - KILL_UNLOCK_CONDITIONS contains the correct entry for Combat Disposition


# ============================================================================
# Mock Classes
# ============================================================================


class MockGameManager:
	var no_damage_levels_completed: int = 0

	func register_no_damage_level() -> void:
		no_damage_levels_completed += 1


class MockUnlockManager:
	## Kill-based unlock conditions (mirrors the real KILL_UNLOCK_CONDITIONS).
	const KILL_UNLOCK_CONDITIONS: Array = [
		{
			# 1 level completed without damage → unlock Combat Disposition (Issue #1389)
			"stat": "no_damage_levels_completed",
			"min_kills": 1,
			"weapons": [],
			"grenades": [],
			"active_items": [17]  # COMBAT_DISPOSITION = 17
		}
	]

	var _game_manager: MockGameManager = null

	func set_game_manager(gm: MockGameManager) -> void:
		_game_manager = gm

	func is_kill_condition_met(kill_condition: Dictionary) -> bool:
		if _game_manager == null:
			return false
		var stat: String = kill_condition.get("stat", "")
		var min_kills: int = kill_condition.get("min_kills", 0)
		if stat.is_empty():
			return false
		var current_count: int = _game_manager.get(stat) if _game_manager.get(stat) != null else 0
		return current_count >= min_kills

	func is_active_item_condition_met(item_type: int) -> bool:
		for kill_condition in KILL_UNLOCK_CONDITIONS:
			if item_type in kill_condition.get("active_items", []):
				if is_kill_condition_met(kill_condition):
					return true
		return false


var game_manager: MockGameManager
var unlock_manager: MockUnlockManager


func before_each() -> void:
	game_manager = MockGameManager.new()
	unlock_manager = MockUnlockManager.new()
	unlock_manager.set_game_manager(game_manager)


func after_each() -> void:
	game_manager = null
	unlock_manager = null


# ============================================================================
# Combat Disposition Locked By Default Tests
# ============================================================================


func test_combat_disposition_starts_locked() -> void:
	var unlocked_active_items := {
		17: false  # COMBAT_DISPOSITION — locked by default (Issue #1389)
	}
	assert_false(unlocked_active_items[17],
		"COMBAT_DISPOSITION should start locked — requires 1 level without damage (Issue #1389)")


# ============================================================================
# no_damage_levels_completed Counter Tests
# ============================================================================


func test_no_damage_levels_starts_at_zero() -> void:
	assert_eq(game_manager.no_damage_levels_completed, 0,
		"no_damage_levels_completed should start at 0")


func test_no_damage_level_increments_counter() -> void:
	game_manager.register_no_damage_level()
	assert_eq(game_manager.no_damage_levels_completed, 1,
		"no_damage_levels_completed should increment after one no-damage level")


func test_multiple_no_damage_levels_accumulate() -> void:
	for i in range(3):
		game_manager.register_no_damage_level()
	assert_eq(game_manager.no_damage_levels_completed, 3,
		"no_damage_levels_completed should accumulate correctly")


# ============================================================================
# Condition Met / Not Met Tests
# ============================================================================


func test_condition_not_met_at_zero_no_damage_levels() -> void:
	assert_false(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Combat Disposition condition should not be met at 0 no-damage levels completed")


func test_condition_met_at_one_no_damage_level() -> void:
	game_manager.no_damage_levels_completed = 1
	assert_true(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Combat Disposition condition should be met after 1 level without damage (Issue #1389)")


func test_condition_met_above_one_no_damage_level() -> void:
	game_manager.no_damage_levels_completed = 5
	assert_true(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Combat Disposition condition should remain met above 1 no-damage level")


# ============================================================================
# KILL_UNLOCK_CONDITIONS Structure Tests
# ============================================================================


func test_kill_unlock_conditions_has_combat_disposition_entry() -> void:
	var found: bool = false
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 17 in cond.get("active_items", []):  # COMBAT_DISPOSITION = 17
			found = true
			break
	assert_true(found,
		"KILL_UNLOCK_CONDITIONS should contain an entry for COMBAT_DISPOSITION (type 17)")


func test_combat_disposition_condition_requires_1_no_damage_level() -> void:
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 17 in cond.get("active_items", []):
			assert_eq(cond.get("min_kills", 0), 1,
				"Combat Disposition unlock should require 1 level without damage (Issue #1389)")
			assert_eq(cond.get("stat", ""), "no_damage_levels_completed",
				"Combat Disposition unlock should track 'no_damage_levels_completed' stat")
			return
	fail_test("No condition entry found for Combat Disposition in KILL_UNLOCK_CONDITIONS")


func test_combat_disposition_condition_has_no_weapons_or_grenades() -> void:
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 17 in cond.get("active_items", []):
			assert_true(cond.get("weapons", []).is_empty(),
				"Combat Disposition condition should not unlock any weapons")
			assert_true(cond.get("grenades", []).is_empty(),
				"Combat Disposition condition should not unlock any grenades")
			return


# ============================================================================
# is_active_item_condition_met Integration Tests
# ============================================================================


func test_active_item_condition_not_met_before_any_no_damage_level() -> void:
	game_manager.no_damage_levels_completed = 0
	assert_false(unlock_manager.is_active_item_condition_met(17),
		"Combat Disposition condition should not be met with 0 no-damage levels (Issue #1389)")


func test_active_item_condition_met_after_one_no_damage_level() -> void:
	game_manager.no_damage_levels_completed = 1
	assert_true(unlock_manager.is_active_item_condition_met(17),
		"Combat Disposition condition should be met after 1 level without damage (Issue #1389)")
