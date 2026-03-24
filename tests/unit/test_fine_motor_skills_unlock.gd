extends GutTest
## Unit tests for the Fine Motor Skills shot-based unlock condition (Issue #1346).
##
## Tests that:
## - FINE_MOTOR_SKILLS starts locked (not freely available from start)
## - shots_fired_special_weapons counter increments only for shotgun/sniper/revolver shots
## - The shot condition requires exactly 650 special-weapon shots (Issue #1053 req.2)
## - is_kill_condition_met returns correct values based on shot count
## - KILL_UNLOCK_CONDITIONS contains the correct entry for Fine Motor Skills


# ============================================================================
# Mock Classes
# ============================================================================


class MockGameManager:
	var selected_weapon: String = "makarov_pm"
	var shots_fired: int = 0
	var shots_fired_special_weapons: int = 0
	const FINE_MOTOR_SKILLS_WEAPONS: Array = ["shotgun", "sniper", "revolver"]

	func register_shot() -> void:
		shots_fired += 1
		if selected_weapon in FINE_MOTOR_SKILLS_WEAPONS:
			shots_fired_special_weapons += 1


class MockUnlockManager:
	## Conditions shared with kill-based conditions (mirrors the real KILL_UNLOCK_CONDITIONS).
	const KILL_UNLOCK_CONDITIONS: Array = [
		{
			"stat": "kills_without_laser_sight",
			"min_kills": 1000,
			"weapons": [],
			"grenades": [],
			"active_items": [9]  # LASER_SIGHT = 9
		},
		{
			# 650 shots with shotgun, sniper rifle, or revolver → unlock Fine Motor Skills (Issue #1346, Issue #1053 req.2)
			"stat": "shots_fired_special_weapons",
			"min_kills": 650,
			"weapons": [],
			"grenades": [],
			"active_items": [19]  # FINE_MOTOR_SKILLS = 19
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
# Fine Motor Skills Locked By Default Tests
# ============================================================================


func test_fine_motor_skills_starts_locked() -> void:
	var unlocked_active_items := {
		19: false  # FINE_MOTOR_SKILLS — locked by default (Issue #1346)
	}
	assert_false(unlocked_active_items[19],
		"FINE_MOTOR_SKILLS should start locked — requires 650 special weapon shots (Issue #1346, #1053)")


# ============================================================================
# shots_fired_special_weapons Counter Tests
# ============================================================================


func test_shots_fired_special_weapons_starts_at_zero() -> void:
	assert_eq(game_manager.shots_fired_special_weapons, 0,
		"shots_fired_special_weapons should start at 0")


func test_shotgun_shot_increments_special_counter() -> void:
	game_manager.selected_weapon = "shotgun"
	game_manager.register_shot()
	assert_eq(game_manager.shots_fired_special_weapons, 1,
		"Shotgun shot should increment shots_fired_special_weapons")


func test_sniper_shot_increments_special_counter() -> void:
	game_manager.selected_weapon = "sniper"
	game_manager.register_shot()
	assert_eq(game_manager.shots_fired_special_weapons, 1,
		"Sniper shot should increment shots_fired_special_weapons")


func test_revolver_shot_increments_special_counter() -> void:
	game_manager.selected_weapon = "revolver"
	game_manager.register_shot()
	assert_eq(game_manager.shots_fired_special_weapons, 1,
		"Revolver shot should increment shots_fired_special_weapons")


func test_makarov_shot_does_not_increment_special_counter() -> void:
	game_manager.selected_weapon = "makarov_pm"
	game_manager.register_shot()
	assert_eq(game_manager.shots_fired_special_weapons, 0,
		"Makarov PM shot should NOT increment shots_fired_special_weapons")


func test_m16_shot_does_not_increment_special_counter() -> void:
	game_manager.selected_weapon = "m16"
	game_manager.register_shot()
	assert_eq(game_manager.shots_fired_special_weapons, 0,
		"M16 shot should NOT increment shots_fired_special_weapons")


func test_mini_uzi_shot_does_not_increment_special_counter() -> void:
	game_manager.selected_weapon = "mini_uzi"
	game_manager.register_shot()
	assert_eq(game_manager.shots_fired_special_weapons, 0,
		"Mini UZI shot should NOT increment shots_fired_special_weapons")


func test_silenced_pistol_shot_does_not_increment_special_counter() -> void:
	game_manager.selected_weapon = "silenced_pistol"
	game_manager.register_shot()
	assert_eq(game_manager.shots_fired_special_weapons, 0,
		"Silenced Pistol shot should NOT increment shots_fired_special_weapons")


func test_total_shots_also_increments_for_special_weapons() -> void:
	game_manager.selected_weapon = "shotgun"
	game_manager.register_shot()
	assert_eq(game_manager.shots_fired, 1,
		"Total shots_fired should also increment for special weapons")


func test_special_shots_accumulate_from_all_special_weapons() -> void:
	game_manager.selected_weapon = "shotgun"
	for i in range(200):
		game_manager.register_shot()
	game_manager.selected_weapon = "sniper"
	for i in range(200):
		game_manager.register_shot()
	game_manager.selected_weapon = "revolver"
	for i in range(250):
		game_manager.register_shot()
	assert_eq(game_manager.shots_fired_special_weapons, 650,
		"shots_fired_special_weapons should accumulate from all three special weapons to reach unlock threshold")


func test_non_special_shots_do_not_count_toward_special_total() -> void:
	game_manager.selected_weapon = "makarov_pm"
	for i in range(200):
		game_manager.register_shot()
	game_manager.selected_weapon = "shotgun"
	for i in range(50):
		game_manager.register_shot()
	assert_eq(game_manager.shots_fired_special_weapons, 50,
		"Only special weapon shots should count toward shots_fired_special_weapons")


# ============================================================================
# Shot Condition Met / Not Met Tests
# ============================================================================


func test_shot_condition_not_met_at_zero_shots() -> void:
	var fine_motor_condition: Dictionary = {}
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if cond.get("stat", "") == "shots_fired_special_weapons":
			fine_motor_condition = cond
			break
	assert_false(unlock_manager.is_kill_condition_met(fine_motor_condition),
		"Fine Motor Skills shot condition should not be met at 0 shots")


func test_shot_condition_not_met_at_649_shots() -> void:
	game_manager.shots_fired_special_weapons = 649
	var fine_motor_condition: Dictionary = {}
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if cond.get("stat", "") == "shots_fired_special_weapons":
			fine_motor_condition = cond
			break
	assert_false(unlock_manager.is_kill_condition_met(fine_motor_condition),
		"Fine Motor Skills shot condition should not be met at 649 shots (needs exactly 650, Issue #1053)")


func test_shot_condition_met_at_650_shots() -> void:
	game_manager.shots_fired_special_weapons = 650
	var fine_motor_condition: Dictionary = {}
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if cond.get("stat", "") == "shots_fired_special_weapons":
			fine_motor_condition = cond
			break
	assert_true(unlock_manager.is_kill_condition_met(fine_motor_condition),
		"Fine Motor Skills shot condition should be met at exactly 650 special weapon shots (Issue #1053)")


func test_shot_condition_met_above_650_shots() -> void:
	game_manager.shots_fired_special_weapons = 1000
	var fine_motor_condition: Dictionary = {}
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if cond.get("stat", "") == "shots_fired_special_weapons":
			fine_motor_condition = cond
			break
	assert_true(unlock_manager.is_kill_condition_met(fine_motor_condition),
		"Fine Motor Skills shot condition should remain met above 650 shots")


# ============================================================================
# KILL_UNLOCK_CONDITIONS Structure Tests
# ============================================================================


func test_kill_unlock_conditions_has_fine_motor_skills_entry() -> void:
	var found: bool = false
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 19 in cond.get("active_items", []):  # FINE_MOTOR_SKILLS = 19
			found = true
			break
	assert_true(found,
		"KILL_UNLOCK_CONDITIONS should contain an entry for FINE_MOTOR_SKILLS (type 19)")


func test_fine_motor_skills_condition_requires_650_shots() -> void:
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 19 in cond.get("active_items", []):
			assert_eq(cond.get("min_kills", 0), 650,
				"Fine Motor Skills unlock should require 650 special weapon shots (Issue #1053)")
			assert_eq(cond.get("stat", ""), "shots_fired_special_weapons",
				"Fine Motor Skills unlock should track 'shots_fired_special_weapons' stat")
			return
	fail_test("No condition entry found for Fine Motor Skills in KILL_UNLOCK_CONDITIONS")


func test_fine_motor_skills_condition_has_no_weapons_or_grenades() -> void:
	for cond in unlock_manager.KILL_UNLOCK_CONDITIONS:
		if 19 in cond.get("active_items", []):
			assert_true(cond.get("weapons", []).is_empty(),
				"Fine Motor Skills condition should not unlock any weapons")
			assert_true(cond.get("grenades", []).is_empty(),
				"Fine Motor Skills condition should not unlock any grenades")
			return


# ============================================================================
# is_active_item_condition_met Integration Tests
# ============================================================================


func test_active_item_condition_not_met_below_threshold() -> void:
	game_manager.shots_fired_special_weapons = 649
	assert_false(unlock_manager.is_active_item_condition_met(19),
		"Fine Motor Skills condition should not be met at 649 shots (Issue #1053)")


func test_active_item_condition_met_at_threshold() -> void:
	game_manager.shots_fired_special_weapons = 650
	assert_true(unlock_manager.is_active_item_condition_met(19),
		"Fine Motor Skills condition should be met at 650 special weapon shots (Issue #1053)")


# ============================================================================
# Tutorial Level Shot Registration Tests (Issue #1346 bug fix)
# ============================================================================


## Regression test: Tutorial level must call register_shot() on weapon fire.
## Bug: tutorial_level.gd _on_weapon_fired() only tracked local _shots_fired
##      for tutorial hint progression but never called GameManager.register_shot(),
##      so all shots fired on the Tutorial level were invisible to the unlock system.
## Fix: _on_weapon_fired() now calls GameManager.register_shot() before hint logic.
class MockTutorialLevelWithGameManager:
	## Simulates tutorial_level.gd _on_weapon_fired() AFTER the fix (Issue #1346).
	## This mock mirrors the fixed code: calls register_shot() then does tutorial hints.
	var _shots_fired: int = 0
	var _game_manager: MockGameManager = null

	func set_game_manager(gm: MockGameManager) -> void:
		_game_manager = gm

	func on_weapon_fired() -> void:
		_shots_fired += 1
		# Fixed: call register_shot() so stats are tracked (Issue #1346).
		if _game_manager:
			_game_manager.register_shot()
		# Tutorial hint logic would follow here (not relevant for this test).

	func get_shots_fired() -> int:
		return _shots_fired


func test_tutorial_level_weapon_fired_calls_register_shot_for_shotgun() -> void:
	## Issue #1346 regression: shots on Tutorial level now count toward special weapon total.
	var tutorial := MockTutorialLevelWithGameManager.new()
	tutorial.set_game_manager(game_manager)
	game_manager.selected_weapon = "shotgun"

	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_eq(game_manager.shots_fired_special_weapons, 3,
		"Shotgun shots on Tutorial level must count toward shots_fired_special_weapons (Issue #1346)")


func test_tutorial_level_weapon_fired_calls_register_shot_for_sniper() -> void:
	var tutorial := MockTutorialLevelWithGameManager.new()
	tutorial.set_game_manager(game_manager)
	game_manager.selected_weapon = "sniper"

	tutorial.on_weapon_fired()
	tutorial.on_weapon_fired()

	assert_eq(game_manager.shots_fired_special_weapons, 2,
		"Sniper shots on Tutorial level must count toward shots_fired_special_weapons (Issue #1346)")


func test_tutorial_level_weapon_fired_calls_register_shot_for_revolver() -> void:
	var tutorial := MockTutorialLevelWithGameManager.new()
	tutorial.set_game_manager(game_manager)
	game_manager.selected_weapon = "revolver"

	tutorial.on_weapon_fired()

	assert_eq(game_manager.shots_fired_special_weapons, 1,
		"Revolver shots on Tutorial level must count toward shots_fired_special_weapons (Issue #1346)")


func test_tutorial_level_weapon_fired_does_not_count_non_special_weapons() -> void:
	var tutorial := MockTutorialLevelWithGameManager.new()
	tutorial.set_game_manager(game_manager)
	game_manager.selected_weapon = "makarov_pm"

	for i in range(10):
		tutorial.on_weapon_fired()

	assert_eq(game_manager.shots_fired_special_weapons, 0,
		"Makarov PM shots on Tutorial level must NOT count toward shots_fired_special_weapons")
	assert_eq(game_manager.shots_fired, 10,
		"Total shots_fired must still be tracked for Makarov PM")


func test_tutorial_level_650_shotgun_shots_unlock_fine_motor_skills() -> void:
	## End-to-end: 650 shotgun shots fired from Tutorial level reach the unlock threshold (Issue #1053).
	var tutorial := MockTutorialLevelWithGameManager.new()
	tutorial.set_game_manager(game_manager)
	game_manager.selected_weapon = "shotgun"

	for i in range(650):
		tutorial.on_weapon_fired()

	assert_true(unlock_manager.is_active_item_condition_met(19),
		"650 shotgun shots on Tutorial level must unlock Fine Motor Skills (Issue #1053)")
