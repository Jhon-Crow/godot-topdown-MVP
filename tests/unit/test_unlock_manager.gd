extends GutTest
## Unit tests for UnlockManager — condition-based item unlock system.
##
## Tests that items are unlocked automatically when level completion
## conditions are met, and that gold highlighting logic is correct.
## Issue #894: добавь систему анлоков (Add an unlock system)


# ============================================================================
# Mock classes
# ============================================================================


class MockProgressManager:
	var _progress: Dictionary = {}

	signal progress_updated(level_path: String, difficulty_name: String)

	func get_best_rank(level_path: String, difficulty_name: String) -> String:
		var key: String = "%s:%s" % [level_path, difficulty_name]
		return _progress.get(key, "")

	func set_rank(level_path: String, difficulty_name: String, rank: String) -> void:
		var key: String = "%s:%s" % [level_path, difficulty_name]
		_progress[key] = rank

	func fire_progress_updated(level_path: String, difficulty_name: String) -> void:
		progress_updated.emit(level_path, difficulty_name)


class MockGameManager:
	var unlocked_weapons: Dictionary = {
		"makarov_pm": true,
		"m16": true,             # No condition — freely available from start
		"shotgun": false,        # Condition: Building D+
		"mini_uzi": false,       # Condition: Labyrinth D+
		"silenced_pistol": true, # No condition — freely available from start
		"sniper": false,         # Condition: Polygon D+
		"revolver": false,       # Condition: Castle F+
		"ak_gl": true            # No condition — freely available from start
	}

	var unlocked_signals: Array = []

	func is_weapon_unlocked(weapon_id: String) -> bool:
		return unlocked_weapons.get(weapon_id, false)

	func unlock_weapon(weapon_id: String) -> void:
		if weapon_id in unlocked_weapons and not unlocked_weapons[weapon_id]:
			unlocked_weapons[weapon_id] = true
			unlocked_signals.append(weapon_id)


class MockActiveItemManager:
	var unlocked_active_items: Dictionary = {
		0: true,   # NONE — always unlocked
		1: false,  # FLASHLIGHT — condition: Polygon D+
		2: true,   # HOMING_BULLETS — no condition, freely available from start
		3: false,  # TELEPORT_BRACERS — condition: Castle F+
		4: true,   # BFF_PENDANT — no condition, freely available from start (Issue #674)
		5: true,   # INVISIBILITY_SUIT — no condition, freely available from start
		6: true,   # BREAKER_BULLETS — no condition, freely available from start
		7: true,   # FORCE_FIELD — no condition, freely available from start
		8: true,   # TRAJECTORY_GLASSES — no condition, freely available from start (Issue #744)
		9: true    # LASER_SIGHT — no condition, freely available from start (Issue #947)
	}

	var unlocked_signals: Array = []

	func is_active_item_unlocked(item_type: int) -> bool:
		return unlocked_active_items.get(item_type, false)

	func unlock_active_item(item_type: int) -> void:
		if item_type in unlocked_active_items and not unlocked_active_items[item_type]:
			unlocked_active_items[item_type] = true
			unlocked_signals.append(item_type)


class MockGrenadeManager:
	var unlocked_grenades: Dictionary = {
		0: true,  # FLASHBANG — always unlocked
		1: true,  # FRAG — no condition, freely available from start
		2: true,  # DEFENSIVE — no condition, freely available from start
		3: true   # AGGRESSION_GAS — no condition, freely available from start
	}

	var unlocked_signals: Array = []

	func is_grenade_unlocked(grenade_type: int) -> bool:
		return unlocked_grenades.get(grenade_type, false)

	func unlock_grenade(grenade_type: int) -> void:
		if grenade_type in unlocked_grenades and not unlocked_grenades[grenade_type]:
			unlocked_grenades[grenade_type] = true
			unlocked_signals.append(grenade_type)


# ============================================================================
# Helper: create UnlockManager with injected mock dependencies
# ============================================================================


## Create a testable UnlockManager subclass that uses mock dependencies.
class TestableUnlockManager extends Node:
	const RANK_ORDER: Array[String] = ["F", "D", "C", "B", "A", "A+", "S"]

	const UNLOCK_CONDITIONS: Dictionary = {
		"res://scenes/levels/LabyrinthLevel.tscn": {
			"min_rank": "D",
			"weapons": ["mini_uzi"],
			"grenades": [],
			"active_items": []
		},
		"res://scenes/levels/BuildingLevel.tscn": {
			"min_rank": "D",
			"weapons": ["shotgun"],
			"grenades": [],
			"active_items": []
		},
		"res://scenes/levels/TestTier.tscn": {
			"min_rank": "D",
			"weapons": ["sniper"],
			"grenades": [],
			"active_items": [1]  # FLASHLIGHT
		},
		"res://scenes/levels/CastleLevel.tscn": {
			"min_rank": "F",
			"weapons": ["revolver"],
			"grenades": [],
			"active_items": [3]  # TELEPORT_BRACERS
		}
	}

	var mock_progress_manager: MockProgressManager
	var mock_game_manager: MockGameManager
	var mock_active_item_manager: MockActiveItemManager
	var mock_grenade_manager: MockGrenadeManager

	func get_node_or_null(path: String) -> Variant:
		match path:
			"/root/ProgressManager":
				return mock_progress_manager
			"/root/GameManager":
				return mock_game_manager
			"/root/ActiveItemManager":
				return mock_active_item_manager
			"/root/GrenadeManager":
				return mock_grenade_manager
		return null

	func _get_best_rank_any_difficulty(level_path: String) -> String:
		if mock_progress_manager == null:
			return ""
		var best_rank: String = ""
		var difficulties: Array[String] = ["Easy", "Normal", "Hard", "Power Fantasy"]
		for difficulty_name in difficulties:
			var rank: String = mock_progress_manager.get_best_rank(level_path, difficulty_name)
			if not rank.is_empty() and _is_rank_better(rank, best_rank):
				best_rank = rank
		return best_rank

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

	func _is_rank_sufficient(rank: String, min_rank: String) -> bool:
		if min_rank == "F":
			return not rank.is_empty()
		return not _is_rank_better(min_rank, rank)

	func is_level_condition_met(level_path: String) -> bool:
		if level_path not in UNLOCK_CONDITIONS:
			return false
		var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
		var min_rank: String = condition.get("min_rank", "D")
		var best_rank: String = _get_best_rank_any_difficulty(level_path)
		return _is_rank_sufficient(best_rank, min_rank)

	func is_weapon_condition_met(weapon_id: String) -> bool:
		for level_path in UNLOCK_CONDITIONS:
			var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
			if weapon_id in condition.get("weapons", []):
				if is_level_condition_met(level_path):
					return true
		return false

	func is_active_item_condition_met(item_type: int) -> bool:
		for level_path in UNLOCK_CONDITIONS:
			var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
			if item_type in condition.get("active_items", []):
				if is_level_condition_met(level_path):
					return true
		return false

	func is_grenade_condition_met(grenade_type: int) -> bool:
		for level_path in UNLOCK_CONDITIONS:
			var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
			if grenade_type in condition.get("grenades", []):
				if is_level_condition_met(level_path):
					return true
		return false

	func check_and_apply_unlocks(level_path: String) -> void:
		if level_path not in UNLOCK_CONDITIONS:
			return
		var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
		var min_rank: String = condition.get("min_rank", "D")
		var best_rank: String = _get_best_rank_any_difficulty(level_path)
		if best_rank.is_empty():
			return
		if not _is_rank_sufficient(best_rank, min_rank):
			return
		for weapon_id in condition.get("weapons", []):
			if mock_game_manager and not mock_game_manager.is_weapon_unlocked(weapon_id):
				mock_game_manager.unlock_weapon(weapon_id)
		for grenade_type in condition.get("grenades", []):
			if mock_grenade_manager and not mock_grenade_manager.is_grenade_unlocked(grenade_type):
				mock_grenade_manager.unlock_grenade(grenade_type)
		for item_type in condition.get("active_items", []):
			if mock_active_item_manager and not mock_active_item_manager.is_active_item_unlocked(item_type):
				mock_active_item_manager.unlock_active_item(item_type)

	func reset_condition_gated_items() -> void:
		for level_path in UNLOCK_CONDITIONS:
			var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
			if mock_game_manager:
				for weapon_id in condition.get("weapons", []):
					if weapon_id in mock_game_manager.unlocked_weapons:
						mock_game_manager.unlocked_weapons[weapon_id] = false
			if mock_active_item_manager:
				for item_type in condition.get("active_items", []):
					if item_type in mock_active_item_manager.unlocked_active_items:
						mock_active_item_manager.unlocked_active_items[item_type] = false

	func reset_and_apply_all_unlocks() -> void:
		reset_condition_gated_items()
		for level_path in UNLOCK_CONDITIONS:
			check_and_apply_unlocks(level_path)


# ============================================================================
# Test setup
# ============================================================================


var progress_manager: MockProgressManager
var game_manager: MockGameManager
var active_item_manager: MockActiveItemManager
var grenade_manager: MockGrenadeManager
var unlock_manager: TestableUnlockManager


func before_each() -> void:
	progress_manager = MockProgressManager.new()
	game_manager = MockGameManager.new()
	active_item_manager = MockActiveItemManager.new()
	grenade_manager = MockGrenadeManager.new()

	unlock_manager = TestableUnlockManager.new()
	unlock_manager.mock_progress_manager = progress_manager
	unlock_manager.mock_game_manager = game_manager
	unlock_manager.mock_active_item_manager = active_item_manager
	unlock_manager.mock_grenade_manager = grenade_manager


func after_each() -> void:
	unlock_manager = null
	progress_manager = null
	game_manager = null
	active_item_manager = null
	grenade_manager = null


# ============================================================================
# Rank comparison tests
# ============================================================================


func test_rank_order_f_is_worst() -> void:
	assert_false(unlock_manager._is_rank_better("F", "D"),
		"F should not be better than D")


func test_rank_order_s_is_best() -> void:
	assert_true(unlock_manager._is_rank_better("S", "A+"),
		"S should be better than A+")


func test_rank_order_d_better_than_empty() -> void:
	assert_true(unlock_manager._is_rank_better("D", ""),
		"D should be better than empty (not yet completed)")


func test_rank_sufficient_d_for_d_minimum() -> void:
	assert_true(unlock_manager._is_rank_sufficient("D", "D"),
		"D should satisfy D minimum requirement")


func test_rank_sufficient_b_for_d_minimum() -> void:
	assert_true(unlock_manager._is_rank_sufficient("B", "D"),
		"B should satisfy D minimum requirement")


func test_rank_insufficient_f_for_d_minimum() -> void:
	assert_false(unlock_manager._is_rank_sufficient("F", "D"),
		"F should NOT satisfy D minimum requirement")


func test_rank_sufficient_f_for_f_minimum() -> void:
	assert_true(unlock_manager._is_rank_sufficient("F", "F"),
		"F should satisfy F minimum requirement (any completion)")


func test_rank_sufficient_s_for_f_minimum() -> void:
	assert_true(unlock_manager._is_rank_sufficient("S", "F"),
		"S should satisfy F minimum requirement")


func test_rank_insufficient_empty_for_f_minimum() -> void:
	assert_false(unlock_manager._is_rank_sufficient("", "F"),
		"Empty rank should NOT satisfy F minimum (level not completed)")


# ============================================================================
# Condition met check tests
# ============================================================================


func test_condition_not_met_when_no_progress() -> void:
	# No progress set
	assert_false(unlock_manager.is_level_condition_met("res://scenes/levels/LabyrinthLevel.tscn"),
		"Condition should not be met with no progress")


func test_labyrinth_condition_met_with_d_rank() -> void:
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_level_condition_met("res://scenes/levels/LabyrinthLevel.tscn"),
		"Labyrinth condition should be met with grade D")


func test_labyrinth_condition_met_with_s_rank() -> void:
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "S")
	assert_true(unlock_manager.is_level_condition_met("res://scenes/levels/LabyrinthLevel.tscn"),
		"Labyrinth condition should be met with grade S")


func test_labyrinth_condition_not_met_with_f_rank() -> void:
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "F")
	assert_false(unlock_manager.is_level_condition_met("res://scenes/levels/LabyrinthLevel.tscn"),
		"Labyrinth condition should NOT be met with grade F (requires D or higher)")


func test_castle_condition_met_with_f_rank() -> void:
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")
	assert_true(unlock_manager.is_level_condition_met("res://scenes/levels/CastleLevel.tscn"),
		"Castle condition should be met with grade F (any completion)")


func test_castle_condition_met_with_d_rank() -> void:
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_level_condition_met("res://scenes/levels/CastleLevel.tscn"),
		"Castle condition should be met with grade D")


func test_condition_met_on_any_difficulty() -> void:
	# Set rank only on Hard difficulty (not Normal)
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Hard", "D")
	assert_true(unlock_manager.is_level_condition_met("res://scenes/levels/BuildingLevel.tscn"),
		"Condition should be met if any difficulty has qualifying rank")


# ============================================================================
# Weapon condition met tests
# ============================================================================


func test_uzi_condition_met_after_labyrinth_d() -> void:
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_weapon_condition_met("mini_uzi"),
		"Uzi condition should be met after Labyrinth grade D")


func test_uzi_condition_not_met_with_f() -> void:
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "F")
	assert_false(unlock_manager.is_weapon_condition_met("mini_uzi"),
		"Uzi condition should NOT be met with Labyrinth grade F")


func test_shotgun_condition_met_after_building_d() -> void:
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_weapon_condition_met("shotgun"),
		"Shotgun condition should be met after Building grade D")


func test_sniper_condition_met_after_polygon_d() -> void:
	progress_manager.set_rank("res://scenes/levels/TestTier.tscn", "Normal", "D")
	assert_true(unlock_manager.is_weapon_condition_met("sniper"),
		"Sniper condition should be met after Polygon (TestTier) grade D")


func test_revolver_condition_met_after_castle_f() -> void:
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")
	assert_true(unlock_manager.is_weapon_condition_met("revolver"),
		"Revolver condition should be met after Castle grade F")


func test_m16_has_no_condition() -> void:
	# M16 has no defined unlock condition (available by default or manually)
	assert_false(unlock_manager.is_weapon_condition_met("m16"),
		"M16 has no unlock condition defined")


# ============================================================================
# Active item condition met tests
# ============================================================================


func test_flashlight_condition_met_after_polygon_d() -> void:
	progress_manager.set_rank("res://scenes/levels/TestTier.tscn", "Normal", "D")
	assert_true(unlock_manager.is_active_item_condition_met(1),  # FLASHLIGHT = 1
		"Flashlight condition should be met after Polygon (TestTier) grade D")


func test_teleport_condition_met_after_castle_f() -> void:
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")
	assert_true(unlock_manager.is_active_item_condition_met(3),  # TELEPORT_BRACERS = 3
		"Teleport Bracers condition should be met after Castle grade F")


func test_homing_bullets_has_no_condition() -> void:
	# Homing Bullets has no defined condition
	assert_false(unlock_manager.is_active_item_condition_met(2),  # HOMING_BULLETS = 2
		"Homing Bullets has no unlock condition defined")


# ============================================================================
# Auto-unlock on progress update tests
# ============================================================================


func test_unlocks_uzi_when_labyrinth_completed_with_d() -> void:
	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should be locked before completing Labyrinth")

	# Simulate completing Labyrinth with grade D
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "D")
	unlock_manager.check_and_apply_unlocks("res://scenes/levels/LabyrinthLevel.tscn")

	assert_true(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should be unlocked after Labyrinth grade D")


func test_does_not_unlock_uzi_when_labyrinth_completed_with_f() -> void:
	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should be locked before completing Labyrinth")

	# Simulate completing Labyrinth with grade F (below requirement)
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "F")
	unlock_manager.check_and_apply_unlocks("res://scenes/levels/LabyrinthLevel.tscn")

	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should NOT be unlocked with Labyrinth grade F")


func test_unlocks_shotgun_when_building_completed_with_d() -> void:
	assert_false(game_manager.is_weapon_unlocked("shotgun"),
		"Shotgun should be locked before completing Building")

	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	unlock_manager.check_and_apply_unlocks("res://scenes/levels/BuildingLevel.tscn")

	assert_true(game_manager.is_weapon_unlocked("shotgun"),
		"Shotgun should be unlocked after Building grade D")


func test_unlocks_sniper_and_flashlight_when_polygon_completed_with_d() -> void:
	assert_false(game_manager.is_weapon_unlocked("sniper"),
		"Sniper should be locked before Polygon")
	assert_false(active_item_manager.is_active_item_unlocked(1),
		"Flashlight should be locked before Polygon")

	progress_manager.set_rank("res://scenes/levels/TestTier.tscn", "Normal", "D")
	unlock_manager.check_and_apply_unlocks("res://scenes/levels/TestTier.tscn")

	assert_true(game_manager.is_weapon_unlocked("sniper"),
		"Sniper should be unlocked after Polygon grade D")
	assert_true(active_item_manager.is_active_item_unlocked(1),
		"Flashlight should be unlocked after Polygon grade D")


func test_unlocks_revolver_and_teleport_when_castle_completed_with_f() -> void:
	assert_false(game_manager.is_weapon_unlocked("revolver"),
		"Revolver should be locked before Castle")
	assert_false(active_item_manager.is_active_item_unlocked(3),
		"Teleport Bracers should be locked before Castle")

	# F rank is sufficient for Castle (any completion)
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")
	unlock_manager.check_and_apply_unlocks("res://scenes/levels/CastleLevel.tscn")

	assert_true(game_manager.is_weapon_unlocked("revolver"),
		"Revolver should be unlocked after Castle grade F")
	assert_true(active_item_manager.is_active_item_unlocked(3),
		"Teleport Bracers should be unlocked after Castle grade F")


func test_does_not_double_unlock() -> void:
	# Manually unlock revolver first
	game_manager.unlocked_weapons["revolver"] = true

	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")
	unlock_manager.check_and_apply_unlocks("res://scenes/levels/CastleLevel.tscn")

	# No duplicate signal should be emitted
	assert_eq(game_manager.unlocked_signals.size(), 0,
		"Should not emit unlock signal for already unlocked weapon")


func test_unlocks_on_easy_difficulty() -> void:
	# Completing on Easy should also count
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	unlock_manager.check_and_apply_unlocks("res://scenes/levels/LabyrinthLevel.tscn")

	assert_true(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should be unlocked even on Easy difficulty")


func test_unlocks_when_better_rank_achieved_later() -> void:
	# First, get F on Labyrinth (not enough)
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "F")
	unlock_manager.check_and_apply_unlocks("res://scenes/levels/LabyrinthLevel.tscn")
	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should still be locked with F rank")

	# Then, get D on Labyrinth (enough)
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "D")
	unlock_manager.check_and_apply_unlocks("res://scenes/levels/LabyrinthLevel.tscn")
	assert_true(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should be unlocked once D rank is achieved")


# ============================================================================
# Default unlock state verification
# ============================================================================


func test_pm_is_unlocked_by_default() -> void:
	assert_true(game_manager.is_weapon_unlocked("makarov_pm"),
		"PM pistol should be unlocked by default")


func test_flashbang_is_unlocked_by_default() -> void:
	assert_true(grenade_manager.is_grenade_unlocked(0),  # FLASHBANG = 0
		"Flashbang grenade should be unlocked by default")


func test_condition_locked_weapons_locked_by_default() -> void:
	# These weapons have explicit unlock conditions and must start locked
	for weapon_id in ["shotgun", "mini_uzi", "sniper", "revolver"]:
		assert_false(game_manager.is_weapon_unlocked(weapon_id),
			"%s should be locked by default (has unlock condition)" % weapon_id)


func test_free_weapons_unlocked_by_default() -> void:
	# These weapons have no conditions — they are freely available from the start
	# Issue #894: "all unspecified items can be opened from the start"
	for weapon_id in ["m16", "silenced_pistol", "ak_gl"]:
		assert_true(game_manager.is_weapon_unlocked(weapon_id),
			"%s should be unlocked by default (no unlock condition)" % weapon_id)


# ============================================================================
# Reset condition-gated items tests (Issue #894 bug fix)
# ============================================================================


func test_reset_condition_gated_resets_weapons_to_locked() -> void:
	# Simulate corrupt save: condition-gated weapons were incorrectly marked as unlocked
	game_manager.unlocked_weapons["mini_uzi"] = true
	game_manager.unlocked_weapons["shotgun"] = true
	game_manager.unlocked_weapons["sniper"] = true
	game_manager.unlocked_weapons["revolver"] = true

	# Reset should lock them back
	unlock_manager.reset_condition_gated_items()

	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"mini_uzi should be re-locked after reset (conditions not met)")
	assert_false(game_manager.is_weapon_unlocked("shotgun"),
		"shotgun should be re-locked after reset (conditions not met)")
	assert_false(game_manager.is_weapon_unlocked("sniper"),
		"sniper should be re-locked after reset (conditions not met)")
	assert_false(game_manager.is_weapon_unlocked("revolver"),
		"revolver should be re-locked after reset (conditions not met)")


func test_reset_does_not_affect_free_weapons() -> void:
	# Free weapons (no conditions) should NOT be reset
	unlock_manager.reset_condition_gated_items()

	assert_true(game_manager.is_weapon_unlocked("m16"),
		"m16 should remain unlocked after reset (no condition)")
	assert_true(game_manager.is_weapon_unlocked("silenced_pistol"),
		"silenced_pistol should remain unlocked after reset (no condition)")
	assert_true(game_manager.is_weapon_unlocked("ak_gl"),
		"ak_gl should remain unlocked after reset (no condition)")
	assert_true(game_manager.is_weapon_unlocked("makarov_pm"),
		"makarov_pm should remain unlocked after reset (always available)")


func test_reset_and_apply_unlocks_correctly_after_condition_is_met() -> void:
	# Simulate corrupt save: revolver incorrectly unlocked
	game_manager.unlocked_weapons["revolver"] = true

	# Set Castle progress to F (meets condition)
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")

	# Reset and re-apply: revolver should end up unlocked (condition is met)
	unlock_manager.reset_and_apply_all_unlocks()

	assert_true(game_manager.is_weapon_unlocked("revolver"),
		"Revolver should be re-unlocked since Castle F condition is met")


func test_reset_and_apply_removes_invalid_unlocks() -> void:
	# Simulate corrupt save: mini_uzi incorrectly unlocked (no Labyrinth progress)
	game_manager.unlocked_weapons["mini_uzi"] = true

	# No Labyrinth progress set — condition not met
	unlock_manager.reset_and_apply_all_unlocks()

	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"mini_uzi should be locked after reset (Labyrinth condition not met)")
