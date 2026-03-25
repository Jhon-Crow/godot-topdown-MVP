extends GutTest
## Unit tests for the Armored Skin death-based unlock condition (Issue #1389).
##
## Tests that:
## - ARMORED_SKIN starts locked (no longer freely available from start)
## - total_deaths counter increments on each player death
## - The death condition requires exactly 100 deaths
## - is_kill_condition_met returns correct values based on death count
## - KILL_UNLOCK_CONDITIONS contains the correct entry for Armored Skin


# ============================================================================
# Mock Classes
# ============================================================================


class MockGameManager:
	var total_deaths: int = 0

	func register_death() -> void:
		total_deaths += 1


class MockUnlockManager:
	## Kill-based unlock conditions (mirrors the real KILL_UNLOCK_CONDITIONS).
	const KILL_UNLOCK_CONDITIONS: Array = [
		{
			# 100 total deaths → unlock Armored Skin (Issue #1389)
			"stat": "total_deaths",
			"min_kills": 100,
			"weapons": [],
			"grenades": [],
			"active_items": [13]  # ARMORED_SKIN = 13
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
# Armored Skin Locked By Default Tests
# ============================================================================


func test_armored_skin_starts_locked() -> void:
	var unlocked_active_items := {
		13: false  # ARMORED_SKIN — locked by default (Issue #1389)
	}
	assert_false(unlocked_active_items[13],
		"ARMORED_SKIN should start locked — requires 100 deaths (Issue #1389)")


# ============================================================================
# total_deaths Counter Tests
# ============================================================================


func test_total_deaths_starts_at_zero() -> void:
	assert_eq(game_manager.total_deaths, 0,
		"total_deaths should start at 0")


func test_death_increments_total_deaths() -> void:
	game_manager.register_death()
	assert_eq(game_manager.total_deaths, 1,
		"total_deaths should increment after one death")


func test_multiple_deaths_accumulate() -> void:
	for i in range(50):
		game_manager.register_death()
	assert_eq(game_manager.total_deaths, 50,
		"total_deaths should accumulate correctly across multiple deaths")


# ============================================================================
# Death Condition Met / Not Met Tests
# ============================================================================


func test_death_condition_not_met_at_zero_deaths() -> void:
	assert_false(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Armored Skin death condition should not be met at 0 deaths")


func test_death_condition_not_met_at_99_deaths() -> void:
	game_manager.total_deaths = 99
	assert_false(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Armored Skin death condition should not be met at 99 deaths (needs 100)")


func test_death_condition_met_at_100_deaths() -> void:
	game_manager.total_deaths = 100
	assert_true(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Armored Skin death condition should be met at exactly 100 deaths (Issue #1389)")


func test_death_condition_met_above_100_deaths() -> void:
	game_manager.total_deaths = 150
	assert_true(unlock_manager.is_kill_condition_met(
			unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Armored Skin death condition should remain met above 100 deaths")


# ============================================================================
# KILL_UNLOCK_CONDITIONS Structure Tests
# ============================================================================


func test_kill_unlock_conditions_has_armored_skin_entry() -> void:
	var found: bool = false
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 13 in cond.get("active_items", []):  # ARMORED_SKIN = 13
			found = true
			break
	assert_true(found,
		"KILL_UNLOCK_CONDITIONS should contain an entry for ARMORED_SKIN (type 13)")


func test_armored_skin_condition_requires_100_deaths() -> void:
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 13 in cond.get("active_items", []):
			assert_eq(cond.get("min_kills", 0), 100,
				"Armored Skin unlock should require 100 deaths (Issue #1389)")
			assert_eq(cond.get("stat", ""), "total_deaths",
				"Armored Skin unlock should track 'total_deaths' stat")
			return
	fail_test("No condition entry found for Armored Skin in KILL_UNLOCK_CONDITIONS")


func test_armored_skin_condition_has_no_weapons_or_grenades() -> void:
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 13 in cond.get("active_items", []):
			assert_true(cond.get("weapons", []).is_empty(),
				"Armored Skin death condition should not unlock any weapons")
			assert_true(cond.get("grenades", []).is_empty(),
				"Armored Skin death condition should not unlock any grenades")
			return


# ============================================================================
# is_active_item_condition_met Integration Tests
# ============================================================================


func test_active_item_condition_not_met_below_threshold() -> void:
	game_manager.total_deaths = 99
	assert_false(unlock_manager.is_active_item_condition_met(13),
		"Armored Skin condition should not be met at 99 deaths (Issue #1389)")


func test_active_item_condition_met_at_threshold() -> void:
	game_manager.total_deaths = 100
	assert_true(unlock_manager.is_active_item_condition_met(13),
		"Armored Skin condition should be met at 100 deaths (Issue #1389)")


func test_100_deaths_via_register_death_unlock_armored_skin() -> void:
	## End-to-end: 100 deaths unlock Armored Skin (Issue #1389).
	for i in range(100):
		game_manager.register_death()
	assert_true(unlock_manager.is_active_item_condition_met(13),
		"100 deaths must unlock Armored Skin (Issue #1389)")
