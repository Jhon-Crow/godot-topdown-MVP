extends GutTest
## Unit tests for the unified unlock progress query methods (Issue #1591).
##
## Tests the new progress functions added to UnlockManager that cover all
## condition types: multi-level rank, all-difficulties, single-level, and
## the unified get_*_unlock_progress aggregators.


# ============================================================================
# Mock ProgressManager for Testing
# ============================================================================


class MockProgressManager:
	## Stores completed level+difficulty entries as "level_path:difficulty_name".
	var _progress: Dictionary = {}

	func get_best_rank(level_path: String, difficulty_name: String) -> String:
		var key: String = level_path + ":" + difficulty_name
		return _progress.get(key, "")

	func get_all_progress() -> Dictionary:
		return _progress

	func set_completion(level_path: String, difficulty_name: String, rank: String) -> void:
		_progress[level_path + ":" + difficulty_name] = rank


# ============================================================================
# Mock UnlockManager with the new functions (pure GDScript, no autoload)
# ============================================================================


class MockUnlockManager:
	const RANK_ORDER: Array[String] = ["F", "D", "C", "B", "A", "A+", "S"]

	## Single-level unlock conditions (subset used for testing).
	const UNLOCK_CONDITIONS: Dictionary = {
		"res://scenes/levels/BuildingLevel.tscn": {
			"min_rank": "D",
			"weapons": ["shotgun"],
			"grenades": [1],
			"active_items": []
		},
		"res://scenes/levels/BuildingLevel.tscn:S": {
			"min_rank": "S",
			"weapons": ["silenced_pistol"],
			"grenades": [],
			"active_items": []
		},
		"res://scenes/levels/CastleLevel.tscn": {
			"min_rank": "F",
			"weapons": ["revolver"],
			"grenades": [],
			"active_items": []
		}
	}

	## Multi-level unlock conditions (subset used for testing).
	const MULTI_UNLOCK_CONDITIONS: Array[Dictionary] = [
		{
			"levels": [
				{"path": "res://scenes/levels/BeachLevel.tscn", "min_rank": "S"},
				{"path": "res://scenes/levels/BuildingLevel.tscn", "min_rank": "S"}
			],
			"weapons": [],
			"grenades": [],
			"active_items": [5]  # INVISIBILITY_SUIT
		},
		{
			"levels": [
				{"path": "res://scenes/levels/LabyrinthLevel.tscn", "min_rank": "S"},
				{"path": "res://scenes/levels/BuildingLevel.tscn", "min_rank": "S"},
				{"path": "res://scenes/levels/TestTier.tscn", "min_rank": "S"},
				{"path": "res://scenes/levels/CastleLevel.tscn", "min_rank": "S"},
				{"path": "res://scenes/levels/RevolverLevel.tscn", "min_rank": "S"}
			],
			"weapons": [],
			"grenades": [],
			"active_items": [2]  # HOMING_BULLETS
		}
	]

	## All-difficulties unlock conditions (subset used for testing).
	const ALL_DIFFICULTIES_UNLOCK_CONDITIONS: Array[Dictionary] = [
		{
			"weapons": [],
			"grenades": [],
			"active_items": [18]  # EXPERIMENTAL_SAMPLE
		}
	]

	## Kill-based conditions (minimal, for the unified progress tests).
	const KILL_UNLOCK_CONDITIONS: Array[Dictionary] = [
		{
			"stat": "kills_without_laser_sight",
			"min_kills": 1000,
			"weapons": [],
			"grenades": [],
			"active_items": [9]  # LASER_SIGHT
		}
	]

	var _progress_manager: MockProgressManager = null

	func _init(progress_manager: MockProgressManager) -> void:
		_progress_manager = progress_manager

	## Internal: extract scene path from condition key.
	func _extract_scene_path(condition_key: String) -> String:
		var last_colon: int = condition_key.rfind(":")
		if last_colon > 0 and not condition_key.substr(0, last_colon).ends_with("//"):
			var suffix: String = condition_key.substr(last_colon + 1)
			if suffix in RANK_ORDER:
				return condition_key.substr(0, last_colon)
		return condition_key

	## Internal: get best rank across all difficulties for a level.
	func _get_best_rank_any_difficulty(level_path: String) -> String:
		if not _progress_manager:
			return ""
		var best_rank: String = ""
		for difficulty_name in ["Easy", "Normal", "Hard", "Power Fantasy", "Black Metal"]:
			var rank: String = _progress_manager.get_best_rank(level_path, difficulty_name)
			if not rank.is_empty() and _is_rank_better(rank, best_rank):
				best_rank = rank
		return best_rank

	## Internal: check if new_rank is strictly better than old_rank.
	func _is_rank_better(new_rank: String, old_rank: String) -> bool:
		if old_rank.is_empty():
			return true
		var new_index: int = RANK_ORDER.find(new_rank)
		var old_index: int = RANK_ORDER.find(old_rank)
		if new_index == -1:
			return false
		if old_index == -1:
			return true
		return new_index > old_index

	## Internal: check if rank meets minimum.
	func _is_rank_sufficient(rank: String, min_rank: String) -> bool:
		if min_rank == "F":
			return not rank.is_empty()
		return not _is_rank_better(min_rank, rank)

	## Check if a single-level condition key is met.
	func is_condition_key_met(condition_key: String) -> bool:
		if condition_key not in UNLOCK_CONDITIONS:
			return false
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		var min_rank: String = condition.get("min_rank", "D")
		var scene_path: String = _extract_scene_path(condition_key)
		var best_rank: String = _get_best_rank_any_difficulty(scene_path)
		return _is_rank_sufficient(best_rank, min_rank)

	## Internal helper: fraction of multi-level condition satisfied.
	func _get_multi_condition_progress(multi_condition: Dictionary) -> float:
		var levels: Array = multi_condition.get("levels", [])
		if levels.is_empty():
			return 0.0
		var completed: int = 0
		for level_entry in levels:
			var path: String = level_entry.get("path", "")
			var min_rank: String = level_entry.get("min_rank", "D")
			var best_rank: String = _get_best_rank_any_difficulty(path)
			if _is_rank_sufficient(best_rank, min_rank):
				completed += 1
		return float(completed) / float(levels.size())

	## Internal helper: fraction of difficulties completed.
	func _get_all_difficulties_progress() -> float:
		if not _progress_manager:
			return 0.0
		var all_difficulties: Array[String] = ["Easy", "Normal", "Hard", "Power Fantasy", "Black Metal"]
		var total: int = all_difficulties.size()
		if total == 0:
			return 0.0
		var completed: int = 0
		for difficulty_name in all_difficulties:
			for key in _progress_manager.get_all_progress():
				if key.ends_with(":" + difficulty_name):
					completed += 1
					break
		return float(completed) / float(total)

	## Multi-level condition progress for active items.
	func get_active_item_multi_condition_progress(item_type: int) -> float:
		for multi_condition in MULTI_UNLOCK_CONDITIONS:
			if item_type in multi_condition.get("active_items", []):
				return _get_multi_condition_progress(multi_condition)
		return -1.0

	## All-difficulties condition progress for active items.
	func get_active_item_all_difficulties_progress(item_type: int) -> float:
		for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
			if item_type in all_diff_condition.get("active_items", []):
				return _get_all_difficulties_progress()
		return -1.0

	## Single-level condition progress for active items (binary: 0.0 or 1.0).
	func get_active_item_single_condition_progress(item_type: int) -> float:
		for condition_key in UNLOCK_CONDITIONS:
			var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
			if item_type in condition.get("active_items", []):
				return 1.0 if is_condition_key_met(condition_key) else 0.0
		return -1.0

	## Single-level condition progress for weapons (binary: 0.0 or 1.0).
	func get_weapon_single_condition_progress(weapon_id: String) -> float:
		for condition_key in UNLOCK_CONDITIONS:
			var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
			if weapon_id in condition.get("weapons", []):
				return 1.0 if is_condition_key_met(condition_key) else 0.0
		return -1.0

	## Kill-based condition progress for active items.
	func get_active_item_kill_condition_progress(item_type: int) -> float:
		for kill_condition in KILL_UNLOCK_CONDITIONS:
			if item_type in kill_condition.get("active_items", []):
				return 0.0  # No GameManager in these tests — returns 0.0
		return -1.0

	## Unified progress aggregator for active items.
	func get_active_item_unlock_progress(item_type: int) -> float:
		var best: float = -1.0
		var p: float
		p = get_active_item_kill_condition_progress(item_type)
		if p >= 0.0:
			best = maxf(best, p)
		p = get_active_item_multi_condition_progress(item_type)
		if p >= 0.0:
			best = maxf(best, p)
		p = get_active_item_all_difficulties_progress(item_type)
		if p >= 0.0:
			best = maxf(best, p)
		p = get_active_item_single_condition_progress(item_type)
		if p >= 0.0:
			best = maxf(best, p)
		return best

	## Unified progress aggregator for weapons.
	func get_weapon_unlock_progress(weapon_id: String) -> float:
		var best: float = -1.0
		var p: float
		p = get_weapon_single_condition_progress(weapon_id)
		if p >= 0.0:
			best = maxf(best, p)
		# No kill/multi/all-diff conditions for weapons in this test fixture.
		return best


# ============================================================================
# Test Setup
# ============================================================================


var _progress_manager: MockProgressManager
var _unlock_manager: MockUnlockManager


func before_each() -> void:
	_progress_manager = MockProgressManager.new()
	_unlock_manager = MockUnlockManager.new(_progress_manager)


# ============================================================================
# Tests: _get_multi_condition_progress (via get_active_item_multi_condition_progress)
# ============================================================================


func test_multi_condition_no_levels_done_returns_zero() -> void:
	# Invisibility requires Beach S + Building S — nothing done yet
	var result: float = _unlock_manager.get_active_item_multi_condition_progress(5)
	assert_almost_eq(result, 0.0, 0.001, "0/2 levels done should give 0.0")


func test_multi_condition_half_levels_done() -> void:
	# Complete Beach at S — 1 of 2 levels for Invisibility
	_progress_manager.set_completion("res://scenes/levels/BeachLevel.tscn", "Normal", "S")
	var result: float = _unlock_manager.get_active_item_multi_condition_progress(5)
	assert_almost_eq(result, 0.5, 0.001, "1/2 levels done should give 0.5")


func test_multi_condition_all_levels_done_returns_one() -> void:
	# Complete both levels at S — Invisibility fully earned
	_progress_manager.set_completion("res://scenes/levels/BeachLevel.tscn", "Normal", "S")
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Normal", "S")
	var result: float = _unlock_manager.get_active_item_multi_condition_progress(5)
	assert_almost_eq(result, 1.0, 0.001, "2/2 levels done should give 1.0")


func test_multi_condition_five_levels_partial() -> void:
	# Homing Bullets requires 5 levels at S — complete 2
	_progress_manager.set_completion("res://scenes/levels/LabyrinthLevel.tscn", "Hard", "S")
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Hard", "S")
	var result: float = _unlock_manager.get_active_item_multi_condition_progress(2)
	assert_almost_eq(result, 0.4, 0.001, "2/5 levels done should give 0.4")


func test_multi_condition_below_required_rank_not_counted() -> void:
	# Beach completed at A, but condition requires S — should NOT count
	_progress_manager.set_completion("res://scenes/levels/BeachLevel.tscn", "Normal", "A")
	var result: float = _unlock_manager.get_active_item_multi_condition_progress(5)
	assert_almost_eq(result, 0.0, 0.001, "A rank is below S — should not count for S condition")


func test_multi_condition_no_condition_returns_negative_one() -> void:
	# Laser Sight (type 9) has a kill condition, not a multi condition
	var result: float = _unlock_manager.get_active_item_multi_condition_progress(9)
	assert_eq(result, -1.0, "Items without multi-level conditions should return -1.0")


# ============================================================================
# Tests: _get_all_difficulties_progress (via get_active_item_all_difficulties_progress)
# ============================================================================


func test_all_difficulties_none_done_returns_zero() -> void:
	var result: float = _unlock_manager.get_active_item_all_difficulties_progress(18)
	assert_almost_eq(result, 0.0, 0.001, "0 difficulties done should give 0.0")


func test_all_difficulties_one_of_five_done() -> void:
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Easy", "D")
	var result: float = _unlock_manager.get_active_item_all_difficulties_progress(18)
	assert_almost_eq(result, 0.2, 0.001, "1/5 difficulties done should give 0.2")


func test_all_difficulties_three_of_five_done() -> void:
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Easy", "D")
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Normal", "C")
	_progress_manager.set_completion("res://scenes/levels/CastleLevel.tscn", "Hard", "B")
	var result: float = _unlock_manager.get_active_item_all_difficulties_progress(18)
	assert_almost_eq(result, 0.6, 0.001, "3/5 difficulties done should give 0.6")


func test_all_difficulties_all_five_done_returns_one() -> void:
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Easy", "D")
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Hard", "D")
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Power Fantasy", "D")
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Black Metal", "D")
	var result: float = _unlock_manager.get_active_item_all_difficulties_progress(18)
	assert_almost_eq(result, 1.0, 0.001, "5/5 difficulties done should give 1.0")


func test_all_difficulties_no_condition_returns_negative_one() -> void:
	# Active item 5 (INVISIBILITY_SUIT) has a multi-level condition, not all-difficulties
	var result: float = _unlock_manager.get_active_item_all_difficulties_progress(5)
	assert_eq(result, -1.0, "Items without all-difficulties conditions should return -1.0")


# ============================================================================
# Tests: get_weapon_single_condition_progress / get_active_item_single_condition_progress
# ============================================================================


func test_single_condition_weapon_not_met_returns_zero() -> void:
	# Shotgun requires Building D — nothing completed
	var result: float = _unlock_manager.get_weapon_single_condition_progress("shotgun")
	assert_eq(result, 0.0, "Unmet single-level condition should return 0.0")


func test_single_condition_weapon_met_returns_one() -> void:
	# Complete Building at D rank
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	var result: float = _unlock_manager.get_weapon_single_condition_progress("shotgun")
	assert_eq(result, 1.0, "Met single-level condition should return 1.0")


func test_single_condition_weapon_below_min_rank_returns_zero() -> void:
	# Silenced pistol requires Building S — completed at A
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Normal", "A")
	var result: float = _unlock_manager.get_weapon_single_condition_progress("silenced_pistol")
	assert_eq(result, 0.0, "Below-rank completion should return 0.0")


func test_single_condition_min_rank_f_any_completion_counts() -> void:
	# Revolver requires Castle F — any completion counts
	_progress_manager.set_completion("res://scenes/levels/CastleLevel.tscn", "Easy", "F")
	var result: float = _unlock_manager.get_weapon_single_condition_progress("revolver")
	assert_eq(result, 1.0, "Any rank completion for min_rank=F should return 1.0")


func test_single_condition_no_condition_returns_negative_one() -> void:
	# Makarov has no condition in our test UNLOCK_CONDITIONS
	var result: float = _unlock_manager.get_weapon_single_condition_progress("makarov_pm")
	assert_eq(result, -1.0, "Weapons without single-level conditions should return -1.0")


# ============================================================================
# Tests: get_active_item_unlock_progress (unified aggregator)
# ============================================================================


func test_unified_laser_sight_kill_condition_with_zero_kills() -> void:
	# Laser Sight (9) has a kill condition; no GameManager so returns 0.0 from kill path
	var result: float = _unlock_manager.get_active_item_unlock_progress(9)
	assert_almost_eq(result, 0.0, 0.001, "Laser Sight with 0 kills should give 0.0 via unified")


func test_unified_invisibility_multi_condition_partial() -> void:
	# Invisibility (5) via multi-condition: 1/2 levels done → 0.5
	_progress_manager.set_completion("res://scenes/levels/BeachLevel.tscn", "Normal", "S")
	var result: float = _unlock_manager.get_active_item_unlock_progress(5)
	assert_almost_eq(result, 0.5, 0.001, "Unified should return 0.5 for 1/2 multi-level progress")


func test_unified_experimental_sample_all_difficulties_partial() -> void:
	# Experimental Sample (18) via all-difficulties: 2/5 done → 0.4
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Easy", "D")
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	var result: float = _unlock_manager.get_active_item_unlock_progress(18)
	assert_almost_eq(result, 0.4, 0.001, "Unified should return 0.4 for 2/5 all-difficulties progress")


func test_unified_item_no_condition_returns_negative_one() -> void:
	# Active item type 99 has no conditions at all
	var result: float = _unlock_manager.get_active_item_unlock_progress(99)
	assert_eq(result, -1.0, "Items with no conditions at all should return -1.0")


func test_unified_weapon_single_condition_not_met() -> void:
	var result: float = _unlock_manager.get_weapon_unlock_progress("shotgun")
	assert_eq(result, 0.0, "Weapon with unmet single-level condition should return 0.0")


func test_unified_weapon_single_condition_met() -> void:
	_progress_manager.set_completion("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	var result: float = _unlock_manager.get_weapon_unlock_progress("shotgun")
	assert_eq(result, 1.0, "Weapon with met single-level condition should return 1.0 via unified")
