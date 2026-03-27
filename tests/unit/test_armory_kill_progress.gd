extends GutTest
## Unit tests for kill-based unlock progress query methods (Issue #1591).
##
## Tests the get_weapon_kill_condition_progress,
## get_grenade_kill_condition_progress, and
## get_active_item_kill_condition_progress methods added to UnlockManager.
## Also tests the *_counts variants that return current/max numbers.


# ============================================================================
# Mock GameManager for Testing
# ============================================================================


class MockGameManager:
	## Stats tracked by the game (mirrors GameManager public vars).
	var kills_without_laser_sight: int = 0
	var shots_fired_special_weapons: int = 0
	var total_deaths: int = 0
	var no_damage_levels_completed: int = 0


# ============================================================================
# Mock UnlockManager (pure GDScript, no autoload required)
# ============================================================================


class MockUnlockManager:
	## Kill-based unlock conditions (copied from unlock_manager.gd for isolated testing).
	const KILL_UNLOCK_CONDITIONS: Array[Dictionary] = [
		{
			"stat": "kills_without_laser_sight",
			"min_kills": 1000,
			"weapons": [],
			"grenades": [],
			"active_items": [9]  # LASER_SIGHT
		},
		{
			"stat": "shots_fired_special_weapons",
			"min_kills": 650,
			"weapons": [],
			"grenades": [],
			"active_items": [19]  # FINE_MOTOR_SKILLS
		},
		{
			"stat": "total_deaths",
			"min_kills": 100,
			"weapons": [],
			"grenades": [],
			"active_items": [13]  # ARMORED_SKIN
		},
		{
			"stat": "no_damage_levels_completed",
			"min_kills": 1,
			"weapons": [],
			"grenades": [],
			"active_items": [17]  # COMBAT_DISPOSITION
		}
	]

	var _game_manager: MockGameManager = null

	func _init(game_manager: MockGameManager) -> void:
		_game_manager = game_manager

	func get_weapon_kill_condition_progress(weapon_id: String) -> float:
		for kill_condition in KILL_UNLOCK_CONDITIONS:
			if weapon_id in kill_condition.get("weapons", []):
				if not _game_manager:
					return 0.0
				var stat: String = kill_condition.get("stat", "")
				var min_kills: int = kill_condition.get("min_kills", 1)
				var current: int = _game_manager.get(stat) if _game_manager.get(stat) != null else 0
				return clampf(float(current) / float(min_kills), 0.0, 1.0)
		return -1.0

	func get_grenade_kill_condition_progress(grenade_type: int) -> float:
		for kill_condition in KILL_UNLOCK_CONDITIONS:
			if grenade_type in kill_condition.get("grenades", []):
				if not _game_manager:
					return 0.0
				var stat: String = kill_condition.get("stat", "")
				var min_kills: int = kill_condition.get("min_kills", 1)
				var current: int = _game_manager.get(stat) if _game_manager.get(stat) != null else 0
				return clampf(float(current) / float(min_kills), 0.0, 1.0)
		return -1.0

	func get_active_item_kill_condition_progress(item_type: int) -> float:
		for kill_condition in KILL_UNLOCK_CONDITIONS:
			if item_type in kill_condition.get("active_items", []):
				if not _game_manager:
					return 0.0
				var stat: String = kill_condition.get("stat", "")
				var min_kills: int = kill_condition.get("min_kills", 1)
				var current: int = _game_manager.get(stat) if _game_manager.get(stat) != null else 0
				return clampf(float(current) / float(min_kills), 0.0, 1.0)
		return -1.0

	func get_weapon_kill_condition_counts(weapon_id: String) -> Dictionary:
		for kill_condition in KILL_UNLOCK_CONDITIONS:
			if weapon_id in kill_condition.get("weapons", []):
				if not _game_manager:
					return {}
				var stat: String = kill_condition.get("stat", "")
				var min_kills: int = kill_condition.get("min_kills", 1)
				var current: int = _game_manager.get(stat) if _game_manager.get(stat) != null else 0
				return {"current": mini(current, min_kills), "max": min_kills}
		return {}

	func get_grenade_kill_condition_counts(grenade_type: int) -> Dictionary:
		for kill_condition in KILL_UNLOCK_CONDITIONS:
			if grenade_type in kill_condition.get("grenades", []):
				if not _game_manager:
					return {}
				var stat: String = kill_condition.get("stat", "")
				var min_kills: int = kill_condition.get("min_kills", 1)
				var current: int = _game_manager.get(stat) if _game_manager.get(stat) != null else 0
				return {"current": mini(current, min_kills), "max": min_kills}
		return {}

	func get_active_item_kill_condition_counts(item_type: int) -> Dictionary:
		for kill_condition in KILL_UNLOCK_CONDITIONS:
			if item_type in kill_condition.get("active_items", []):
				if not _game_manager:
					return {}
				var stat: String = kill_condition.get("stat", "")
				var min_kills: int = kill_condition.get("min_kills", 1)
				var current: int = _game_manager.get(stat) if _game_manager.get(stat) != null else 0
				return {"current": mini(current, min_kills), "max": min_kills}
		return {}


# ============================================================================
# Test Setup
# ============================================================================


var _game_manager: MockGameManager
var _unlock_manager: MockUnlockManager


func before_each() -> void:
	_game_manager = MockGameManager.new()
	_unlock_manager = MockUnlockManager.new(_game_manager)


# ============================================================================
# Tests: get_active_item_kill_condition_progress
# ============================================================================


func test_no_kill_condition_returns_negative_one_for_weapon() -> void:
	# makarov_pm has a level condition, not a kill condition
	var result: float = _unlock_manager.get_weapon_kill_condition_progress("makarov_pm")
	assert_eq(result, -1.0, "Should return -1.0 for items with no kill condition")


func test_laser_sight_zero_kills_returns_zero_progress() -> void:
	_game_manager.kills_without_laser_sight = 0
	var result: float = _unlock_manager.get_active_item_kill_condition_progress(9)
	assert_eq(result, 0.0, "0 kills should give 0.0 progress")


func test_laser_sight_half_kills_returns_half_progress() -> void:
	_game_manager.kills_without_laser_sight = 500
	var result: float = _unlock_manager.get_active_item_kill_condition_progress(9)
	assert_almost_eq(result, 0.5, 0.001, "500/1000 kills should give 0.5 progress")


func test_laser_sight_full_kills_returns_one() -> void:
	_game_manager.kills_without_laser_sight = 1000
	var result: float = _unlock_manager.get_active_item_kill_condition_progress(9)
	assert_eq(result, 1.0, "1000/1000 kills should give 1.0 progress")


func test_laser_sight_over_max_clamped_to_one() -> void:
	_game_manager.kills_without_laser_sight = 9999
	var result: float = _unlock_manager.get_active_item_kill_condition_progress(9)
	assert_eq(result, 1.0, "Exceeding max kills should be clamped to 1.0")


func test_fine_motor_skills_progress() -> void:
	_game_manager.shots_fired_special_weapons = 325  # half of 650
	var result: float = _unlock_manager.get_active_item_kill_condition_progress(19)
	assert_almost_eq(result, 0.5, 0.001, "325/650 shots should give 0.5 progress")


func test_armored_skin_progress() -> void:
	_game_manager.total_deaths = 25  # 25% of 100
	var result: float = _unlock_manager.get_active_item_kill_condition_progress(13)
	assert_almost_eq(result, 0.25, 0.001, "25/100 deaths should give 0.25 progress")


func test_combat_disposition_zero_no_damage_levels() -> void:
	_game_manager.no_damage_levels_completed = 0
	var result: float = _unlock_manager.get_active_item_kill_condition_progress(17)
	assert_eq(result, 0.0, "0 no-damage levels should give 0.0 progress")


func test_combat_disposition_one_no_damage_level_completes() -> void:
	_game_manager.no_damage_levels_completed = 1
	var result: float = _unlock_manager.get_active_item_kill_condition_progress(17)
	assert_eq(result, 1.0, "1/1 no-damage level should give 1.0 progress")


func test_item_with_no_kill_condition_returns_negative_one() -> void:
	# Active item type 1 (FLASHLIGHT) has a level condition, not a kill condition
	var result: float = _unlock_manager.get_active_item_kill_condition_progress(1)
	assert_eq(result, -1.0, "Should return -1.0 for items without kill conditions")


func test_grenade_with_no_kill_condition_returns_negative_one() -> void:
	# Grenade type 1 (FRAG) has a level condition
	var result: float = _unlock_manager.get_grenade_kill_condition_progress(1)
	assert_eq(result, -1.0, "Should return -1.0 for grenades without kill conditions")


# ============================================================================
# Tests: get_active_item_kill_condition_counts
# ============================================================================


func test_counts_laser_sight_at_zero() -> void:
	_game_manager.kills_without_laser_sight = 0
	var counts: Dictionary = _unlock_manager.get_active_item_kill_condition_counts(9)
	assert_eq(counts["current"], 0, "Current should be 0")
	assert_eq(counts["max"], 1000, "Max should be 1000")


func test_counts_laser_sight_midway() -> void:
	_game_manager.kills_without_laser_sight = 756
	var counts: Dictionary = _unlock_manager.get_active_item_kill_condition_counts(9)
	assert_eq(counts["current"], 756, "Current should be 756")
	assert_eq(counts["max"], 1000, "Max should be 1000")


func test_counts_capped_at_max_when_over() -> void:
	_game_manager.kills_without_laser_sight = 5000
	var counts: Dictionary = _unlock_manager.get_active_item_kill_condition_counts(9)
	assert_eq(counts["current"], 1000, "Current should be capped at max=1000")
	assert_eq(counts["max"], 1000, "Max should be 1000")


func test_counts_empty_for_level_condition_item() -> void:
	# Flashlight (type 1) has a level condition, not kill condition
	var counts: Dictionary = _unlock_manager.get_active_item_kill_condition_counts(1)
	assert_true(counts.is_empty(), "Should return empty dict for non-kill-condition items")


func test_counts_weapon_with_no_kill_condition_is_empty() -> void:
	var counts: Dictionary = _unlock_manager.get_weapon_kill_condition_counts("makarov_pm")
	assert_true(counts.is_empty(), "makarov_pm has no kill condition — should return empty")


func test_counts_grenade_with_no_kill_condition_is_empty() -> void:
	var counts: Dictionary = _unlock_manager.get_grenade_kill_condition_counts(1)
	assert_true(counts.is_empty(), "Frag grenade has no kill condition — should return empty")


func test_fine_motor_skills_counts() -> void:
	_game_manager.shots_fired_special_weapons = 450
	var counts: Dictionary = _unlock_manager.get_active_item_kill_condition_counts(19)
	assert_eq(counts["current"], 450, "Current should be 450")
	assert_eq(counts["max"], 650, "Max should be 650")
