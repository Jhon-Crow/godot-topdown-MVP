extends GutTest
## Unit tests for UnlockManager — condition-based item unlock system.
##
## Tests that unlock conditions are tracked correctly and gold-highlighting
## logic works as expected.  Items are NOT auto-unlocked when conditions are
## met — the player must hold LMB on the gold slot in the armory instead.
## Issue #894: добавь систему анлоков (Add an unlock system)
## Issue #1000: update unlock system


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
		"m16": true,              # No condition — freely available from start
		"shotgun": false,         # Condition: Building D+
		"mini_uzi": false,        # Condition: Labyrinth D+
		"silenced_pistol": false, # Condition: Building S OR Docks D+ (Issue #1000)
		"sniper": false,          # Condition: Polygon D+
		"revolver": false,        # Condition: Castle F+
		"ak_gl": false            # Condition: Beach D+ (Issue #1000)
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
		2: false,  # HOMING_BULLETS — condition: Labyrinth S + Building S + Polygon S + Castle S + Double Corridor S (Issue #1000)
		3: false,  # TELEPORT_BRACERS — condition: Double Corridor D+ (Issue #1000)
		4: true,   # BFF_PENDANT — no condition, freely available from start (Issue #674)
		5: false,  # INVISIBILITY_SUIT — condition: Beach S + Building S (Issue #1000)
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
		1: false, # FRAG — condition: Building D+ (Issue #1000)
		2: false, # DEFENSIVE — condition: Beach S (Issue #1000)
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
			"grenades": [1],    # FRAG = 1
			"active_items": []
		},
		"res://scenes/levels/BuildingLevel.tscn:S": {
			"min_rank": "S",
			"weapons": ["silenced_pistol"],
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
			"active_items": []
		},
		"res://scenes/levels/RevolverLevel.tscn": {
			"min_rank": "D",
			"weapons": [],
			"grenades": [],
			"active_items": [3]  # TELEPORT_BRACERS
		},
		"res://scenes/levels/BeachLevel.tscn": {
			"min_rank": "D",
			"weapons": ["ak_gl"],
			"grenades": [],
			"active_items": []
		},
		"res://scenes/levels/BeachLevel.tscn:S": {
			"min_rank": "S",
			"weapons": [],
			"grenades": [2],    # DEFENSIVE = 2
			"active_items": []
		},
		"res://scenes/levels/DocksLevel.tscn": {
			"min_rank": "D",
			"weapons": ["silenced_pistol"],
			"grenades": [],
			"active_items": []
		}
	}

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

	func _extract_scene_path(condition_key: String) -> String:
		var last_colon: int = condition_key.rfind(":")
		if last_colon > 0 and not condition_key.substr(0, last_colon).ends_with("//"):
			var suffix: String = condition_key.substr(last_colon + 1)
			if suffix in RANK_ORDER:
				return condition_key.substr(0, last_colon)
		return condition_key

	func is_condition_key_met(condition_key: String) -> bool:
		if condition_key not in UNLOCK_CONDITIONS:
			return false
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		var min_rank: String = condition.get("min_rank", "D")
		var scene_path: String = _extract_scene_path(condition_key)
		var best_rank: String = _get_best_rank_any_difficulty(scene_path)
		return _is_rank_sufficient(best_rank, min_rank)

	func is_level_condition_met(level_path: String) -> bool:
		for condition_key in UNLOCK_CONDITIONS:
			if _extract_scene_path(condition_key) == level_path:
				if is_condition_key_met(condition_key):
					return true
		return false

	func is_multi_condition_met(multi_condition: Dictionary) -> bool:
		for level_entry in multi_condition.get("levels", []):
			var path: String = level_entry.get("path", "")
			var min_rank: String = level_entry.get("min_rank", "D")
			var best_rank: String = _get_best_rank_any_difficulty(path)
			if not _is_rank_sufficient(best_rank, min_rank):
				return false
		return true

	func is_weapon_condition_met(weapon_id: String) -> bool:
		for condition_key in UNLOCK_CONDITIONS:
			var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
			if weapon_id in condition.get("weapons", []):
				if is_condition_key_met(condition_key):
					return true
		for multi_condition in MULTI_UNLOCK_CONDITIONS:
			if weapon_id in multi_condition.get("weapons", []):
				if is_multi_condition_met(multi_condition):
					return true
		return false

	func is_active_item_condition_met(item_type: int) -> bool:
		for condition_key in UNLOCK_CONDITIONS:
			var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
			if item_type in condition.get("active_items", []):
				if is_condition_key_met(condition_key):
					return true
		for multi_condition in MULTI_UNLOCK_CONDITIONS:
			if item_type in multi_condition.get("active_items", []):
				if is_multi_condition_met(multi_condition):
					return true
		return false

	func is_grenade_condition_met(grenade_type: int) -> bool:
		for condition_key in UNLOCK_CONDITIONS:
			var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
			if grenade_type in condition.get("grenades", []):
				if is_condition_key_met(condition_key):
					return true
		for multi_condition in MULTI_UNLOCK_CONDITIONS:
			if grenade_type in multi_condition.get("grenades", []):
				if is_multi_condition_met(multi_condition):
					return true
		return false

	func reset_condition_gated_items() -> void:
		for condition_key in UNLOCK_CONDITIONS:
			var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
			if mock_game_manager:
				for weapon_id in condition.get("weapons", []):
					if weapon_id in mock_game_manager.unlocked_weapons:
						mock_game_manager.unlocked_weapons[weapon_id] = false
			if mock_active_item_manager:
				for item_type in condition.get("active_items", []):
					if item_type in mock_active_item_manager.unlocked_active_items:
						mock_active_item_manager.unlocked_active_items[item_type] = false
			if mock_grenade_manager:
				for grenade_type in condition.get("grenades", []):
					if grenade_type in mock_grenade_manager.unlocked_grenades:
						mock_grenade_manager.unlocked_grenades[grenade_type] = false
		for multi_condition in MULTI_UNLOCK_CONDITIONS:
			if mock_active_item_manager:
				for item_type in multi_condition.get("active_items", []):
					if item_type in mock_active_item_manager.unlocked_active_items:
						mock_active_item_manager.unlocked_active_items[item_type] = false

	# reset_and_apply_all_unlocks now only resets (no auto-applying).
	# Items stay locked until the player holds LMB on the gold armory slot.
	func reset_and_apply_all_unlocks() -> void:
		reset_condition_gated_items()

	## Check if any item has its unlock condition met but is not yet unlocked.
	## Used to highlight the Armory button in the pause menu and score screen (Issue #897).
	func has_any_available_unlock() -> bool:
		for condition_key in UNLOCK_CONDITIONS:
			if not is_condition_key_met(condition_key):
				continue
			var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]

			if mock_game_manager:
				for weapon_id in condition.get("weapons", []):
					if not mock_game_manager.is_weapon_unlocked(weapon_id):
						return true

			if mock_active_item_manager:
				for item_type in condition.get("active_items", []):
					if not mock_active_item_manager.is_active_item_unlocked(item_type):
						return true

			if mock_grenade_manager:
				for grenade_type in condition.get("grenades", []):
					if not mock_grenade_manager.is_grenade_unlocked(grenade_type):
						return true

		for multi_condition in MULTI_UNLOCK_CONDITIONS:
			if not is_multi_condition_met(multi_condition):
				continue

			if mock_active_item_manager:
				for item_type in multi_condition.get("active_items", []):
					if not mock_active_item_manager.is_active_item_unlocked(item_type):
						return true

		return false


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
# _extract_scene_path tests
# ============================================================================


func test_extract_scene_path_no_suffix() -> void:
	var path: String = "res://scenes/levels/BuildingLevel.tscn"
	assert_eq(unlock_manager._extract_scene_path(path), path,
		"Path without rank suffix should be returned unchanged")


func test_extract_scene_path_with_s_suffix() -> void:
	var key: String = "res://scenes/levels/BuildingLevel.tscn:S"
	assert_eq(unlock_manager._extract_scene_path(key), "res://scenes/levels/BuildingLevel.tscn",
		"Rank suffix :S should be stripped")


func test_extract_scene_path_with_d_suffix() -> void:
	var key: String = "res://scenes/levels/BeachLevel.tscn:D"
	assert_eq(unlock_manager._extract_scene_path(key), "res://scenes/levels/BeachLevel.tscn",
		"Rank suffix :D should be stripped")


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
	assert_false(unlock_manager.is_condition_key_met("res://scenes/levels/LabyrinthLevel.tscn"),
		"Labyrinth D condition should NOT be met with grade F (requires D or higher)")


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
	assert_true(unlock_manager.is_condition_key_met("res://scenes/levels/BuildingLevel.tscn"),
		"Condition should be met if any difficulty has qualifying rank")


# ============================================================================
# New unlock condition tests (Issue #1000)
# ============================================================================


func test_building_d_unlocks_frag_grenade() -> void:
	# req.1: Building D+ → FRAG grenade
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_grenade_condition_met(1),
		"Frag grenade condition should be met after Building grade D")


func test_building_f_does_not_unlock_frag_grenade() -> void:
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "F")
	assert_false(unlock_manager.is_grenade_condition_met(1),
		"Frag grenade condition should NOT be met with Building grade F")


func test_building_s_unlocks_silenced_pistol() -> void:
	# req.2: Building S → silenced_pistol
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "S")
	assert_true(unlock_manager.is_weapon_condition_met("silenced_pistol"),
		"Silenced pistol condition should be met after Building grade S")


func test_building_a_does_not_unlock_silenced_pistol_via_building() -> void:
	# Building A is not S — silenced_pistol not yet unlocked via building
	# (still locked until Docks D+ or Building S)
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "A")
	assert_false(unlock_manager.is_condition_key_met("res://scenes/levels/BuildingLevel.tscn:S"),
		"Building :S condition should NOT be met with grade A")


func test_teleport_unlocks_after_double_corridor() -> void:
	# req.3: Teleport unlocks after Double Corridor (RevolverLevel), NOT Castle
	progress_manager.set_rank("res://scenes/levels/RevolverLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_active_item_condition_met(3),
		"Teleport Bracers condition should be met after Double Corridor grade D")


func test_teleport_not_unlocked_by_castle_alone() -> void:
	# Completing Castle no longer unlocks Teleport (Issue #1000 req.3)
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")
	assert_false(unlock_manager.is_active_item_condition_met(3),
		"Teleport Bracers should NOT be unlocked by Castle completion alone (moved to Double Corridor)")


func test_beach_d_unlocks_ak_gl() -> void:
	# req.4: Beach D+ → AK+GL
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_weapon_condition_met("ak_gl"),
		"AK+GL condition should be met after Beach grade D")


func test_beach_f_does_not_unlock_ak_gl() -> void:
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Normal", "F")
	assert_false(unlock_manager.is_weapon_condition_met("ak_gl"),
		"AK+GL condition should NOT be met with Beach grade F (requires D+)")


func test_beach_s_and_building_s_unlock_invisibility() -> void:
	# req.5: Beach S + Building S → Invisibility
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Normal", "S")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "S")
	assert_true(unlock_manager.is_active_item_condition_met(5),
		"Invisibility condition should be met after Beach S and Building S")


func test_beach_s_alone_does_not_unlock_invisibility() -> void:
	# req.5: both Beach S AND Building S required
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Normal", "S")
	assert_false(unlock_manager.is_active_item_condition_met(5),
		"Invisibility should NOT unlock with Beach S alone (Building S also required)")


func test_building_s_alone_does_not_unlock_invisibility() -> void:
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "S")
	assert_false(unlock_manager.is_active_item_condition_met(5),
		"Invisibility should NOT unlock with Building S alone (Beach S also required)")


func test_beach_s_unlocks_defensive_grenade() -> void:
	# req.6: Beach S → F-1 grenade (DEFENSIVE = 2)
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Normal", "S")
	assert_true(unlock_manager.is_grenade_condition_met(2),
		"F-1 grenade condition should be met after Beach grade S")


func test_beach_a_does_not_unlock_defensive_grenade() -> void:
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Normal", "A")
	assert_false(unlock_manager.is_condition_key_met("res://scenes/levels/BeachLevel.tscn:S"),
		"Beach :S condition should NOT be met with grade A")


func test_docks_d_unlocks_silenced_pistol() -> void:
	# req.7: Docks D+ → silenced_pistol
	progress_manager.set_rank("res://scenes/levels/DocksLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_weapon_condition_met("silenced_pistol"),
		"Silenced pistol condition should be met after Docks grade D")


func test_all_five_s_unlock_homing_bullets() -> void:
	# req.8: Labyrinth S + Building S + Polygon S + Castle S + Double Corridor S → Homing Bullets
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "S")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "S")
	progress_manager.set_rank("res://scenes/levels/TestTier.tscn", "Normal", "S")
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "S")
	progress_manager.set_rank("res://scenes/levels/RevolverLevel.tscn", "Normal", "S")
	assert_true(unlock_manager.is_active_item_condition_met(2),
		"Homing Bullets condition should be met after all 5 levels at S rank")


func test_four_of_five_s_does_not_unlock_homing_bullets() -> void:
	# All 5 required — missing Double Corridor S
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "S")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "S")
	progress_manager.set_rank("res://scenes/levels/TestTier.tscn", "Normal", "S")
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "S")
	# RevolverLevel not yet completed at S
	assert_false(unlock_manager.is_active_item_condition_met(2),
		"Homing Bullets should NOT unlock with only 4 of 5 levels at S rank")


# ============================================================================
# Weapon condition met tests (existing)
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
	# M16 has no defined unlock condition (available by default)
	assert_false(unlock_manager.is_weapon_condition_met("m16"),
		"M16 has no unlock condition defined")


# ============================================================================
# Active item condition met tests (existing)
# ============================================================================


func test_flashlight_condition_met_after_polygon_d() -> void:
	progress_manager.set_rank("res://scenes/levels/TestTier.tscn", "Normal", "D")
	assert_true(unlock_manager.is_active_item_condition_met(1),  # FLASHLIGHT = 1
		"Flashlight condition should be met after Polygon (TestTier) grade D")


func test_teleport_condition_met_after_double_corridor_d() -> void:
	progress_manager.set_rank("res://scenes/levels/RevolverLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_active_item_condition_met(3),  # TELEPORT_BRACERS = 3
		"Teleport Bracers condition should be met after Double Corridor (RevolverLevel) grade D")


# ============================================================================
# Condition tracking tests (items are NOT auto-unlocked — player uses LMB)
# ============================================================================


func test_uzi_condition_not_met_with_no_progress() -> void:
	# No progress at all
	assert_false(unlock_manager.is_weapon_condition_met("mini_uzi"),
		"Uzi condition should NOT be met with no Labyrinth progress")
	# And item remains locked — no auto-unlock happens
	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should stay locked — player must use LMB to unlock")


func test_uzi_condition_met_after_labyrinth_d_but_still_locked() -> void:
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "D")
	# Condition is now met (gold in armory)
	assert_true(unlock_manager.is_weapon_condition_met("mini_uzi"),
		"Uzi condition should be met after Labyrinth D")
	# But item is still locked — no auto-unlock
	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should still be locked until player holds LMB on the gold slot")


func test_condition_not_met_for_labyrinth_with_f_rank() -> void:
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "F")
	assert_false(unlock_manager.is_weapon_condition_met("mini_uzi"),
		"Uzi condition should NOT be met with Labyrinth grade F (requires D+)")
	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should stay locked")


func test_shotgun_condition_met_after_building_d_but_still_locked() -> void:
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_weapon_condition_met("shotgun"),
		"Shotgun condition should be met after Building D")
	assert_false(game_manager.is_weapon_unlocked("shotgun"),
		"Shotgun should still be locked — player must hold LMB to unlock")


func test_sniper_and_flashlight_condition_met_after_polygon_d() -> void:
	progress_manager.set_rank("res://scenes/levels/TestTier.tscn", "Normal", "D")
	assert_true(unlock_manager.is_weapon_condition_met("sniper"),
		"Sniper condition should be met after Polygon D")
	assert_true(unlock_manager.is_active_item_condition_met(1),
		"Flashlight condition should be met after Polygon D")
	# Neither item auto-unlocks
	assert_false(game_manager.is_weapon_unlocked("sniper"),
		"Sniper should stay locked until LMB hold")
	assert_false(active_item_manager.is_active_item_unlocked(1),
		"Flashlight should stay locked until LMB hold")


func test_revolver_condition_met_after_castle_f() -> void:
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")
	assert_true(unlock_manager.is_weapon_condition_met("revolver"),
		"Revolver condition should be met after Castle F")
	assert_false(game_manager.is_weapon_unlocked("revolver"),
		"Revolver should stay locked until LMB hold")


func test_condition_met_on_easy_difficulty() -> void:
	# Completing on Easy should also mark condition as met
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	assert_true(unlock_manager.is_weapon_condition_met("mini_uzi"),
		"Uzi condition should be met even on Easy difficulty")
	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi should still need player LMB to unlock")


func test_condition_not_met_then_met_after_better_rank() -> void:
	# F rank on Labyrinth (not enough)
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "F")
	assert_false(unlock_manager.is_weapon_condition_met("mini_uzi"),
		"Uzi condition should NOT be met with F rank")

	# Now achieve D rank
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_weapon_condition_met("mini_uzi"),
		"Uzi condition should now be met with D rank")
	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"Uzi still locked — player must open it with LMB")


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
	for weapon_id in ["shotgun", "mini_uzi", "sniper", "revolver", "ak_gl", "silenced_pistol"]:
		assert_false(game_manager.is_weapon_unlocked(weapon_id),
			"%s should be locked by default (has unlock condition)" % weapon_id)


func test_free_weapons_unlocked_by_default() -> void:
	# These weapons have no conditions — they are freely available from the start
	for weapon_id in ["m16", "makarov_pm"]:
		assert_true(game_manager.is_weapon_unlocked(weapon_id),
			"%s should be unlocked by default (no unlock condition)" % weapon_id)


func test_condition_locked_grenades_locked_by_default() -> void:
	# FRAG (1) and DEFENSIVE (2) have unlock conditions (Issue #1000)
	assert_false(grenade_manager.is_grenade_unlocked(1),
		"Frag grenade should be locked by default (has unlock condition)")
	assert_false(grenade_manager.is_grenade_unlocked(2),
		"F-1 grenade should be locked by default (has unlock condition)")


func test_condition_locked_active_items_locked_by_default() -> void:
	# FLASHLIGHT (1), HOMING_BULLETS (2), TELEPORT_BRACERS (3), INVISIBILITY_SUIT (5)
	assert_false(active_item_manager.is_active_item_unlocked(1),
		"Flashlight should be locked by default")
	assert_false(active_item_manager.is_active_item_unlocked(2),
		"Homing Bullets should be locked by default (Issue #1000)")
	assert_false(active_item_manager.is_active_item_unlocked(3),
		"Teleport Bracers should be locked by default")
	assert_false(active_item_manager.is_active_item_unlocked(5),
		"Invisibility should be locked by default (Issue #1000)")


# ============================================================================
# Reset condition-gated items tests (Issue #894 bug fix)
# ============================================================================


func test_reset_condition_gated_resets_weapons_to_locked() -> void:
	# Simulate corrupt save: condition-gated weapons were incorrectly marked as unlocked
	game_manager.unlocked_weapons["mini_uzi"] = true
	game_manager.unlocked_weapons["shotgun"] = true
	game_manager.unlocked_weapons["sniper"] = true
	game_manager.unlocked_weapons["revolver"] = true
	game_manager.unlocked_weapons["ak_gl"] = true
	game_manager.unlocked_weapons["silenced_pistol"] = true

	# Reset should lock them back
	unlock_manager.reset_condition_gated_items()

	for weapon_id in ["mini_uzi", "shotgun", "sniper", "revolver", "ak_gl", "silenced_pistol"]:
		assert_false(game_manager.is_weapon_unlocked(weapon_id),
			"%s should be re-locked after reset" % weapon_id)


func test_reset_does_not_affect_free_weapons() -> void:
	# Free weapons (no conditions) should NOT be reset
	unlock_manager.reset_condition_gated_items()

	assert_true(game_manager.is_weapon_unlocked("m16"),
		"m16 should remain unlocked after reset (no condition)")
	assert_true(game_manager.is_weapon_unlocked("makarov_pm"),
		"makarov_pm should remain unlocked after reset (always available)")


func test_reset_condition_gated_resets_grenades_to_locked() -> void:
	# Simulate corrupt save: condition-gated grenades incorrectly marked as unlocked
	grenade_manager.unlocked_grenades[1] = true  # FRAG
	grenade_manager.unlocked_grenades[2] = true  # DEFENSIVE

	unlock_manager.reset_condition_gated_items()

	assert_false(grenade_manager.is_grenade_unlocked(1),
		"Frag grenade should be re-locked after reset")
	assert_false(grenade_manager.is_grenade_unlocked(2),
		"F-1 grenade should be re-locked after reset")


func test_reset_condition_gated_resets_active_items_to_locked() -> void:
	# Simulate corrupt save
	active_item_manager.unlocked_active_items[5] = true  # INVISIBILITY_SUIT
	active_item_manager.unlocked_active_items[2] = true  # HOMING_BULLETS

	unlock_manager.reset_condition_gated_items()

	assert_false(active_item_manager.is_active_item_unlocked(5),
		"Invisibility should be re-locked after reset")
	assert_false(active_item_manager.is_active_item_unlocked(2),
		"Homing Bullets should be re-locked after reset")


func test_reset_and_apply_removes_invalid_unlocks_condition_met() -> void:
	# Simulate corrupt save: revolver incorrectly unlocked
	game_manager.unlocked_weapons["revolver"] = true

	# Set Castle progress to F (condition met)
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")

	# reset_and_apply now ONLY resets — no auto-applying.
	# Revolver ends up locked; the player must use LMB in the armory.
	unlock_manager.reset_and_apply_all_unlocks()

	assert_false(game_manager.is_weapon_unlocked("revolver"),
		"Revolver should be locked after reset — player must hold LMB to unlock")
	# But the condition IS met (gold slot shows in armory)
	assert_true(unlock_manager.is_weapon_condition_met("revolver"),
		"Revolver condition IS met — the slot will show gold in the armory")


func test_reset_and_apply_removes_invalid_unlocks() -> void:
	# Simulate corrupt save: mini_uzi incorrectly unlocked (no Labyrinth progress)
	game_manager.unlocked_weapons["mini_uzi"] = true

	# No Labyrinth progress set — condition not met
	unlock_manager.reset_and_apply_all_unlocks()

	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"mini_uzi should be locked after reset (Labyrinth condition not met)")
	assert_false(unlock_manager.is_weapon_condition_met("mini_uzi"),
		"mini_uzi condition is also not met — slot stays plain locked (no gold)")


# ============================================================================
# has_any_available_unlock() tests (Issue #897 — armory button highlight)
# ============================================================================


func test_no_available_unlocks_when_no_progress() -> void:
	# No level progress at all — no conditions met, no items available
	assert_false(unlock_manager.has_any_available_unlock(),
		"Should return false when no level progress (no conditions met)")


func test_no_available_unlocks_when_all_locked_but_condition_not_met() -> void:
	# Items are locked but condition is not met (e.g. rank F when D required)
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "F")
	assert_false(unlock_manager.has_any_available_unlock(),
		"Should return false when condition not met (F rank for D requirement)")


func test_has_available_unlock_when_weapon_condition_met() -> void:
	# Labyrinth D+ unlocks mini_uzi — condition met, item still locked
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.has_any_available_unlock(),
		"Should return true when mini_uzi condition is met but item is locked")


func test_no_available_unlocks_when_weapon_already_unlocked() -> void:
	# Labyrinth D+ unlocks mini_uzi — condition met, item already unlocked
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "D")
	game_manager.unlocked_weapons["mini_uzi"] = true

	assert_false(unlock_manager.has_any_available_unlock(),
		"Should return false when mini_uzi condition is met and item is already unlocked")


func test_has_available_unlock_when_grenade_condition_met() -> void:
	# Building D+ unlocks frag grenade — condition met, item still locked
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.has_any_available_unlock(),
		"Should return true when frag grenade condition is met but item is locked")


func test_has_available_unlock_when_multi_condition_met() -> void:
	# Beach S + Building S → Invisibility
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Normal", "S")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "S")
	assert_true(unlock_manager.has_any_available_unlock(),
		"Should return true when multi-condition (invisibility) is met but item is locked")


func test_has_available_unlock_after_new_level_completion() -> void:
	# Player completes Castle level — revolver becomes available
	assert_false(unlock_manager.has_any_available_unlock(),
		"No available unlocks before Castle completion")

	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")

	assert_true(unlock_manager.has_any_available_unlock(),
		"After Castle F completion: revolver is available to unlock")
