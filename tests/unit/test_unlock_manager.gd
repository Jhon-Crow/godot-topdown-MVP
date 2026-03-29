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

	func get_all_progress() -> Dictionary:
		return _progress.duplicate()

	func fire_progress_updated(level_path: String, difficulty_name: String) -> void:
		progress_updated.emit(level_path, difficulty_name)


class MockGameManager:
	var unlocked_weapons: Dictionary = {
		"makarov_pm": true,
		"m16": false,             # Condition: Beach D+ (Issue #1053 req.3)
		"shotgun": false,         # Condition: Building D+
		"mini_uzi": false,        # Condition: Labyrinth D+
		"silenced_pistol": false, # Condition: Building S OR Docks D+ (Issue #1000)
		"sniper": false,          # Condition: Polygon D+
		"revolver": false,        # Condition: Castle F+
		"ak_gl": false            # Condition: Decadence F+ (Issue #1423 req.1)
	}

	# Kill/stat counters used by KILL_UNLOCK_CONDITIONS
	var kills_without_laser_sight: int = 0       # Condition: 400 → Laser Sight (Issue #1196)
	var shots_fired_special_weapons: int = 0     # Condition: 650 → Fine Motor Skills (Issue #1346)
	var total_deaths: int = 0                    # Condition: 100 → Armored Skin (Issue #1389)
	var no_damage_levels_completed: int = 0      # Condition: 1 → Combat Disposition (Issue #1389)
	var levels_completed_rank_a_or_higher: int = 0  # Condition: 7 → Breaker Bullets (Issue #1589 req.3)
	var kills_through_wall: int = 0              # Condition: 50 → Drilling Bullets (Issue #1624 req.3)
	var levels_completed_with_silenced_pistol: int = 0  # Condition: 1 → Auto Reload (Issue #1624 req.2)

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
		4: false,  # BFF_PENDANT — condition: complete Winter Forest (Issue #1624 req.9)
		5: false,  # INVISIBILITY_SUIT — condition: Beach S + Building S (Issue #1000)
		6: false,  # BREAKER_BULLETS — condition: 7 levels at rank A or higher (Issue #1589 req.3)
		7: false,  # FORCE_FIELD — condition: complete Factory on any grade (Issue #1589 req.2)
		8: false,  # TRAJECTORY_GLASSES — condition: City F+ (Issue #1692 req.2)
		9: false,  # LASER_SIGHT — condition: 400 kills without laser sight equipped (Issue #1196)
		10: false, # EXTENDED_MAGAZINE — condition: Double Corridor A+ (Issue #1692 req.1)
		11: true,  # LOUDSPEAKER — no condition, freely available from start (Issue #959)
		12: false, # BREACHING_CHARGES — condition: complete Labyrinth Complex (Issue #1624 req.6)
		13: false, # ARMORED_SKIN — condition: 100 total deaths (Issue #1389)
		14: false, # AUTO_RELOAD — condition: complete any level with silenced pistol (Issue #1624 req.2)
		15: false, # DRILLING_BULLETS — condition: 50 kills through walls (Issue #1624 req.3)
		16: false, # RECOIL_COMPENSATOR — condition: Labyrinth S (Issue #1423 req.2)
		17: false, # COMBAT_DISPOSITION — condition: complete any level without damage (Issue #1389)
		18: false, # EXPERIMENTAL_SAMPLE — condition: one level on every difficulty (Issue #1426)
		19: false, # FINE_MOTOR_SKILLS — condition: 650 shots with special weapons (Issue #1346)
		20: false, # DASH — condition: Decadence A+ (Issue #1624 req.5)
		21: false  # GRENADE_BAG — condition: complete Railway Station (Issue #1624 req.8)
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
		3: false, # AGGRESSION_GAS — condition: complete Docks D+ (Issue #1624 req.4)
		4: false  # DRONE — condition: complete Sewer on any grade (Issue #1624 req.7)
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
		"res://scenes/levels/CityLevel.tscn": {
			"min_rank": "F",
			"weapons": [],
			"grenades": [],
			"active_items": [8]  # TRAJECTORY_GLASSES (Issue #1692 req.2)
		},
		"res://scenes/levels/BeachLevel.tscn": {
			"min_rank": "D",
			"weapons": ["m16"],  # Issue #1053 req.3: changed from ak_gl to m16
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
			"grenades": [3],    # AGGRESSION_GAS = 3 (Issue #1624 req.4)
			"active_items": []
		},
		"res://scenes/levels/DecadenceLevel.tscn": {
			"min_rank": "F",
			"weapons": ["ak_gl"],  # Issue #1423 req.1
			"grenades": [],
			"active_items": []
		},
		"res://scenes/levels/LabyrinthLevel.tscn:S": {
			"min_rank": "S",
			"weapons": [],
			"grenades": [],
			"active_items": [16]  # RECOIL_COMPENSATOR (Issue #1423 req.2)
		},
		"res://scenes/levels/RevolverLevel.tscn:A": {
			"min_rank": "A",
			"weapons": [],
			"grenades": [],
			"active_items": [10]  # EXTENDED_MAGAZINE (Issue #1692 req.1)
		},
		"res://scenes/levels/DecadenceLevel.tscn:A+": {
			"min_rank": "A+",
			"weapons": [],
			"grenades": [],
			"active_items": [20]  # DASH (Issue #1624 req.5)
		},
		"res://scenes/levels/Labyrinth2Level.tscn": {
			"min_rank": "F",
			"weapons": [],
			"grenades": [],
			"active_items": [12]  # BREACHING_CHARGES (Issue #1624 req.6)
		},
		"res://scenes/levels/SewerLevel.tscn": {
			"min_rank": "F",
			"weapons": [],
			"grenades": [4],    # DRONE = 4 (Issue #1624 req.7)
			"active_items": []
		},
		"res://scenes/levels/RailwayStationLevel.tscn": {
			"min_rank": "F",
			"weapons": [],
			"grenades": [],
			"active_items": [21]  # GRENADE_BAG (Issue #1624 req.8)
		},
		"res://scenes/levels/WinterForestLevel.tscn": {
			"min_rank": "F",
			"weapons": [],
			"grenades": [],
			"active_items": [4]  # BFF_PENDANT (Issue #1624 req.9)
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

	const ALL_DIFFICULTIES_UNLOCK_CONDITIONS: Array[Dictionary] = [
		{
			# Complete at least one level on each difficulty → unlock Experimental Sample (Issue #1426)
			"weapons": [],
			"grenades": [],
			"active_items": [18]  # EXPERIMENTAL_SAMPLE
		}
	]

	const KILL_UNLOCK_CONDITIONS: Array[Dictionary] = [
		{
			# 400 kills without Laser Sight → unlock Laser Sight (Issue #1196, updated by Issue #1589)
			"stat": "kills_without_laser_sight",
			"min_kills": 400,
			"weapons": [],
			"grenades": [],
			"active_items": [9]   # LASER_SIGHT
		},
		{
			# 300 shots with shotgun, sniper rifle, or revolver → unlock Fine Motor Skills (Issue #1346)
			"stat": "shots_fired_special_weapons",
			"min_kills": 300,
			"weapons": [],
			"grenades": [],
			"active_items": [19]  # FINE_MOTOR_SKILLS
		},
		{
			# 100 total deaths → unlock Armored Skin (Issue #1389)
			"stat": "total_deaths",
			"min_kills": 100,
			"weapons": [],
			"grenades": [],
			"active_items": [13]  # ARMORED_SKIN
		},
		{
			# 1 level completed without damage → unlock Combat Disposition (Issue #1389)
			"stat": "no_damage_levels_completed",
			"min_kills": 1,
			"weapons": [],
			"grenades": [],
			"active_items": [17]  # COMBAT_DISPOSITION
		},
		{
			# 7 levels completed at rank A or higher → unlock Breaker Bullets (Issue #1589 req.3)
			"stat": "levels_completed_rank_a_or_higher",
			"min_kills": 7,
			"weapons": [],
			"grenades": [],
			"active_items": [6]   # BREAKER_BULLETS
		},
		{
			# 50 kills through walls → unlock Drilling Bullets (Issue #1624 req.3)
			"stat": "kills_through_wall",
			"min_kills": 50,
			"weapons": [],
			"grenades": [],
			"active_items": [15]  # DRILLING_BULLETS
		},
		{
			# Complete any level with silenced pistol → unlock Auto Reload (Issue #1624 req.2)
			"stat": "levels_completed_with_silenced_pistol",
			"min_kills": 1,
			"weapons": [],
			"grenades": [],
			"active_items": [14]  # AUTO_RELOAD
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

	func _get_all_difficulty_names() -> Array[String]:
		return ["Easy", "Normal", "Hard", "Power Fantasy", "Black Metal", "Gunslinger"]

	func is_all_difficulties_condition_met() -> bool:
		if mock_progress_manager == null:
			return false
		var all_progress: Dictionary = mock_progress_manager.get_all_progress()
		for difficulty_name in _get_all_difficulty_names():
			var found: bool = false
			for key in all_progress:
				if key.ends_with(":" + difficulty_name):
					found = true
					break
			if not found:
				return false
		return true

	func is_kill_condition_met(kill_condition: Dictionary) -> bool:
		if mock_game_manager == null:
			return false
		var stat_name: String = kill_condition.get("stat", "")
		var min_kills: int = kill_condition.get("min_kills", 0)
		var stat_value: int = mock_game_manager.get(stat_name) if stat_name in mock_game_manager else 0
		return stat_value >= min_kills

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
		for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
			if weapon_id in all_diff_condition.get("weapons", []):
				if is_all_difficulties_condition_met():
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
		for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
			if item_type in all_diff_condition.get("active_items", []):
				if is_all_difficulties_condition_met():
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
		for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
			if grenade_type in all_diff_condition.get("grenades", []):
				if is_all_difficulties_condition_met():
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
		for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
			if mock_active_item_manager:
				for item_type in all_diff_condition.get("active_items", []):
					if item_type in mock_active_item_manager.unlocked_active_items:
						mock_active_item_manager.unlocked_active_items[item_type] = false

	# reset_and_apply_all_unlocks snapshots saved unlock state, resets, then restores
	# items that were saved AND whose condition is met (Issue #1052).
	func reset_and_apply_all_unlocks() -> void:
		var saved_weapons: Array[String] = _get_unlocked_condition_gated_weapons()
		var saved_grenades: Array[int] = _get_unlocked_condition_gated_grenades()
		var saved_active_items: Array[int] = _get_unlocked_condition_gated_active_items()
		reset_condition_gated_items()
		_restore_saved_unlocks(saved_weapons, saved_grenades, saved_active_items)

	func _get_unlocked_condition_gated_weapons() -> Array[String]:
		var result: Array[String] = []
		if not mock_game_manager:
			return result
		for condition_key in UNLOCK_CONDITIONS:
			for weapon_id in UNLOCK_CONDITIONS[condition_key].get("weapons", []):
				if weapon_id not in result and mock_game_manager.unlocked_weapons.get(weapon_id, false):
					result.append(weapon_id)
		for multi_condition in MULTI_UNLOCK_CONDITIONS:
			for weapon_id in multi_condition.get("weapons", []):
				if weapon_id not in result and mock_game_manager.unlocked_weapons.get(weapon_id, false):
					result.append(weapon_id)
		return result

	func _get_unlocked_condition_gated_grenades() -> Array[int]:
		var result: Array[int] = []
		if not mock_grenade_manager:
			return result
		for condition_key in UNLOCK_CONDITIONS:
			for grenade_type in UNLOCK_CONDITIONS[condition_key].get("grenades", []):
				if grenade_type not in result and mock_grenade_manager.unlocked_grenades.get(grenade_type, false):
					result.append(grenade_type)
		for multi_condition in MULTI_UNLOCK_CONDITIONS:
			for grenade_type in multi_condition.get("grenades", []):
				if grenade_type not in result and mock_grenade_manager.unlocked_grenades.get(grenade_type, false):
					result.append(grenade_type)
		return result

	func _get_unlocked_condition_gated_active_items() -> Array[int]:
		var result: Array[int] = []
		if not mock_active_item_manager:
			return result
		for condition_key in UNLOCK_CONDITIONS:
			for item_type in UNLOCK_CONDITIONS[condition_key].get("active_items", []):
				if item_type not in result and mock_active_item_manager.unlocked_active_items.get(item_type, false):
					result.append(item_type)
		for multi_condition in MULTI_UNLOCK_CONDITIONS:
			for item_type in multi_condition.get("active_items", []):
				if item_type not in result and mock_active_item_manager.unlocked_active_items.get(item_type, false):
					result.append(item_type)
		for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
			for item_type in all_diff_condition.get("active_items", []):
				if item_type not in result and mock_active_item_manager.unlocked_active_items.get(item_type, false):
					result.append(item_type)
		return result

	func _restore_saved_unlocks(
			weapons: Array[String],
			grenades: Array[int],
			active_items: Array[int]) -> void:
		for weapon_id in weapons:
			if mock_game_manager and is_weapon_condition_met(weapon_id):
				if weapon_id in mock_game_manager.unlocked_weapons:
					mock_game_manager.unlocked_weapons[weapon_id] = true
		for grenade_type in grenades:
			if mock_grenade_manager and is_grenade_condition_met(grenade_type):
				if grenade_type in mock_grenade_manager.unlocked_grenades:
					mock_grenade_manager.unlocked_grenades[grenade_type] = true
		for item_type in active_items:
			if mock_active_item_manager and is_active_item_condition_met(item_type):
				if item_type in mock_active_item_manager.unlocked_active_items:
					mock_active_item_manager.unlocked_active_items[item_type] = true

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

		if is_all_difficulties_condition_met():
			for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
				if mock_active_item_manager:
					for item_type in all_diff_condition.get("active_items", []):
						if not mock_active_item_manager.is_active_item_unlocked(item_type):
							return true

		for kill_condition in KILL_UNLOCK_CONDITIONS:
			if not is_kill_condition_met(kill_condition):
				continue

			if mock_game_manager:
				for weapon_id in kill_condition.get("weapons", []):
					if not mock_game_manager.is_weapon_unlocked(weapon_id):
						return true

			if mock_active_item_manager:
				for item_type in kill_condition.get("active_items", []):
					if not mock_active_item_manager.is_active_item_unlocked(item_type):
						return true

			if mock_grenade_manager:
				for grenade_type in kill_condition.get("grenades", []):
					if not mock_grenade_manager.is_grenade_unlocked(grenade_type):
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


func test_city_f_unlocks_trajectory_glasses() -> void:
	# Issue #1692 req.2: City F+ → Trajectory Glasses (any completion)
	progress_manager.set_rank("res://scenes/levels/CityLevel.tscn", "Normal", "F")
	assert_true(unlock_manager.is_active_item_condition_met(8),
		"Trajectory Glasses condition should be met after City grade F (Issue #1692)")


func test_city_d_also_unlocks_trajectory_glasses() -> void:
	# Issue #1692 req.2: City D+ → Trajectory Glasses (D is higher than F)
	progress_manager.set_rank("res://scenes/levels/CityLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_active_item_condition_met(8),
		"Trajectory Glasses condition should also be met after City grade D (Issue #1692)")


func test_beach_d_unlocks_m16() -> void:
	# Issue #1053 req.3: Beach D+ → M16 (changed from AK+GL)
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Normal", "D")
	assert_true(unlock_manager.is_weapon_condition_met("m16"),
		"M16 condition should be met after Beach grade D (Issue #1053)")


func test_beach_f_does_not_unlock_m16() -> void:
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Normal", "F")
	assert_false(unlock_manager.is_weapon_condition_met("m16"),
		"M16 condition should NOT be met with Beach grade F (requires D+)")


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


# ============================================================================
# New unlock condition tests (Issue #1423)
# ============================================================================


func test_decadence_f_unlocks_ak_gl() -> void:
	# Issue #1423 req.1: Decadence (any completion) → AK + GL
	progress_manager.set_rank("res://scenes/levels/DecadenceLevel.tscn", "Normal", "F")
	assert_true(unlock_manager.is_weapon_condition_met("ak_gl"),
		"AK + GL condition should be met after Decadence grade F (any completion)")


func test_decadence_s_unlocks_ak_gl() -> void:
	# Issue #1423 req.1: Decadence S also satisfies the condition
	progress_manager.set_rank("res://scenes/levels/DecadenceLevel.tscn", "Normal", "S")
	assert_true(unlock_manager.is_weapon_condition_met("ak_gl"),
		"AK + GL condition should be met after Decadence grade S")


func test_ak_gl_not_unlocked_without_decadence() -> void:
	# Issue #1423 req.1: AK + GL should NOT be available before completing Decadence
	assert_false(unlock_manager.is_weapon_condition_met("ak_gl"),
		"AK + GL should NOT be unlocked without completing Decadence")


func test_labyrinth_s_unlocks_recoil_compensator() -> void:
	# Issue #1423 req.2: Labyrinth S → Recoil Compensator (16)
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "S")
	assert_true(unlock_manager.is_active_item_condition_met(16),
		"Recoil Compensator condition should be met after Labyrinth grade S")


func test_labyrinth_a_does_not_unlock_recoil_compensator() -> void:
	# Issue #1423 req.2: S rank required, A is not enough
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "A+")
	assert_false(unlock_manager.is_condition_key_met("res://scenes/levels/LabyrinthLevel.tscn:S"),
		"Labyrinth :S condition should NOT be met with grade A+")


func test_recoil_compensator_not_unlocked_without_labyrinth_s() -> void:
	# Issue #1423 req.2: Recoil Compensator locked until Labyrinth S
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "D")
	assert_false(unlock_manager.is_active_item_condition_met(16),
		"Recoil Compensator should NOT be unlocked with Labyrinth grade D")


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
# New unlock condition tests (Issue #1692)
# ============================================================================


func test_double_corridor_a_unlocks_extended_magazine() -> void:
	# Issue #1692 req.1: Double Corridor A+ → Extended Magazine
	progress_manager.set_rank("res://scenes/levels/RevolverLevel.tscn", "Normal", "A")
	assert_true(unlock_manager.is_active_item_condition_met(10),  # EXTENDED_MAGAZINE = 10
		"Extended Magazine condition should be met after Double Corridor grade A (Issue #1692)")


func test_double_corridor_s_unlocks_extended_magazine() -> void:
	# Issue #1692 req.1: Double Corridor S also satisfies the A+ condition
	progress_manager.set_rank("res://scenes/levels/RevolverLevel.tscn", "Normal", "S")
	assert_true(unlock_manager.is_active_item_condition_met(10),  # EXTENDED_MAGAZINE = 10
		"Extended Magazine condition should be met after Double Corridor grade S (Issue #1692)")


func test_double_corridor_b_does_not_unlock_extended_magazine() -> void:
	# Issue #1692 req.1: Double Corridor B is below A, should NOT unlock Extended Magazine
	progress_manager.set_rank("res://scenes/levels/RevolverLevel.tscn", "Normal", "B")
	assert_false(unlock_manager.is_active_item_condition_met(10),  # EXTENDED_MAGAZINE = 10
		"Extended Magazine should NOT be unlocked with Double Corridor grade B (requires A+)")


func test_extended_magazine_not_unlocked_without_double_corridor() -> void:
	# Issue #1692 req.1: Extended Magazine requires Double Corridor, not Building
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "S")
	assert_false(unlock_manager.is_active_item_condition_met(10),  # EXTENDED_MAGAZINE = 10
		"Extended Magazine should NOT be unlocked by Building completion (moved to Double Corridor in Issue #1692)")


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
	for weapon_id in ["shotgun", "mini_uzi", "sniper", "revolver", "m16", "silenced_pistol", "ak_gl"]:
		assert_false(game_manager.is_weapon_unlocked(weapon_id),
			"%s should be locked by default (has unlock condition)" % weapon_id)


func test_free_weapons_unlocked_by_default() -> void:
	# These weapons have no conditions — they are freely available from the start
	for weapon_id in ["makarov_pm"]:
		assert_true(game_manager.is_weapon_unlocked(weapon_id),
			"%s should be unlocked by default (no unlock condition)" % weapon_id)


func test_condition_locked_grenades_locked_by_default() -> void:
	# FRAG (1) and DEFENSIVE (2) have unlock conditions (Issue #1000)
	assert_false(grenade_manager.is_grenade_unlocked(1),
		"Frag grenade should be locked by default (has unlock condition)")
	assert_false(grenade_manager.is_grenade_unlocked(2),
		"F-1 grenade should be locked by default (has unlock condition)")


func test_condition_locked_active_items_locked_by_default() -> void:
	# FLASHLIGHT (1), HOMING_BULLETS (2), TELEPORT_BRACERS (3), INVISIBILITY_SUIT (5),
	# BREAKER_BULLETS (6), FORCE_FIELD (7), TRAJECTORY_GLASSES (8), LASER_SIGHT (9),
	# ARMORED_SKIN (13), RECOIL_COMPENSATOR (16), COMBAT_DISPOSITION (17), FINE_MOTOR_SKILLS (19)
	assert_false(active_item_manager.is_active_item_unlocked(1),
		"Flashlight should be locked by default")
	assert_false(active_item_manager.is_active_item_unlocked(2),
		"Homing Bullets should be locked by default (Issue #1000)")
	assert_false(active_item_manager.is_active_item_unlocked(3),
		"Teleport Bracers should be locked by default")
	assert_false(active_item_manager.is_active_item_unlocked(5),
		"Invisibility should be locked by default (Issue #1000)")
	assert_false(active_item_manager.is_active_item_unlocked(6),
		"Breaker Bullets should be locked by default — requires 7 A-rank levels (Issue #1589 req.3)")
	assert_false(active_item_manager.is_active_item_unlocked(7),
		"Force Field should be locked by default — requires Factory completion (Issue #1589 req.2)")
	assert_false(active_item_manager.is_active_item_unlocked(8),
		"Trajectory Glasses should be locked by default (Issue #1053)")
	assert_false(active_item_manager.is_active_item_unlocked(9),
		"Laser Sight should be locked by default — requires 400 kills without it (Issue #1196)")
	assert_false(active_item_manager.is_active_item_unlocked(13),
		"Armored Skin should be locked by default — requires 100 deaths (Issue #1389)")
	assert_false(active_item_manager.is_active_item_unlocked(16),
		"Recoil Compensator should be locked by default (Issue #1423)")
	assert_false(active_item_manager.is_active_item_unlocked(17),
		"Combat Disposition should be locked by default — requires no-damage level completion (Issue #1389)")
	assert_false(active_item_manager.is_active_item_unlocked(19),
		"Fine Motor Skills should be locked by default — requires 300 shots with special weapons (Issue #1346)")


# ============================================================================
# Reset condition-gated items tests (Issue #894 bug fix)
# ============================================================================


func test_reset_condition_gated_resets_weapons_to_locked() -> void:
	# Simulate corrupt save: condition-gated weapons were incorrectly marked as unlocked
	game_manager.unlocked_weapons["mini_uzi"] = true
	game_manager.unlocked_weapons["shotgun"] = true
	game_manager.unlocked_weapons["sniper"] = true
	game_manager.unlocked_weapons["revolver"] = true
	game_manager.unlocked_weapons["m16"] = true
	game_manager.unlocked_weapons["silenced_pistol"] = true
	game_manager.unlocked_weapons["ak_gl"] = true

	# Reset should lock them back
	unlock_manager.reset_condition_gated_items()

	for weapon_id in ["mini_uzi", "shotgun", "sniper", "revolver", "m16", "silenced_pistol", "ak_gl"]:
		assert_false(game_manager.is_weapon_unlocked(weapon_id),
			"%s should be re-locked after reset" % weapon_id)


func test_reset_does_not_affect_free_weapons() -> void:
	# Free weapons (no conditions) should NOT be reset
	unlock_manager.reset_condition_gated_items()

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


func test_reset_and_apply_removes_invalid_unlocks_condition_not_met() -> void:
	# Simulate corrupt save: mini_uzi incorrectly unlocked (no Labyrinth progress)
	game_manager.unlocked_weapons["mini_uzi"] = true

	# No Labyrinth progress set — condition not met
	unlock_manager.reset_and_apply_all_unlocks()

	assert_false(game_manager.is_weapon_unlocked("mini_uzi"),
		"mini_uzi should be locked after reset (Labyrinth condition not met — corrupt save)")
	assert_false(unlock_manager.is_weapon_condition_met("mini_uzi"),
		"mini_uzi condition is also not met — slot stays plain locked (no gold)")


func test_reset_and_apply_removes_invalid_unlocks() -> void:
	# Alias kept for compatibility — same scenario as above.
	test_reset_and_apply_removes_invalid_unlocks_condition_not_met()


# ============================================================================
# Issue #1052: Saved unlocks must survive reset on game restart
# ============================================================================


func test_saved_weapon_unlock_survives_restart_when_condition_met() -> void:
	# Player earned the condition AND held LMB (item now saved as unlocked).
	# Simulate: PersistManager already restored this from save file.
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Normal", "F")
	game_manager.unlocked_weapons["revolver"] = true  # saved state

	# Simulate game restart: _reset_and_apply_all_unlocks fires deferred.
	unlock_manager.reset_and_apply_all_unlocks()

	assert_true(game_manager.is_weapon_unlocked("revolver"),
		"Revolver should remain unlocked after restart — player already opened the case (Issue #1052)")


func test_saved_grenade_unlock_survives_restart_when_condition_met() -> void:
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	grenade_manager.unlocked_grenades[1] = true  # FRAG, saved state

	unlock_manager.reset_and_apply_all_unlocks()

	assert_true(grenade_manager.is_grenade_unlocked(1),
		"Frag grenade should remain unlocked after restart — player already opened the case (Issue #1052)")


func test_saved_active_item_unlock_survives_restart_when_condition_met() -> void:
	progress_manager.set_rank("res://scenes/levels/TestTier.tscn", "Normal", "D")
	active_item_manager.unlocked_active_items[1] = true  # FLASHLIGHT, saved state

	unlock_manager.reset_and_apply_all_unlocks()

	assert_true(active_item_manager.is_active_item_unlocked(1),
		"Flashlight should remain unlocked after restart — player already opened the case (Issue #1052)")


func test_corrupt_save_weapon_stays_locked_when_condition_not_met() -> void:
	# Corrupt save: revolver unlocked but Castle was never completed.
	# No progress set — condition not met.
	game_manager.unlocked_weapons["revolver"] = true

	unlock_manager.reset_and_apply_all_unlocks()

	assert_false(game_manager.is_weapon_unlocked("revolver"),
		"Revolver should be locked — condition not met, treating save as corrupt (Issue #1052)")


func test_multi_condition_item_survives_restart_when_conditions_met() -> void:
	# INVISIBILITY_SUIT requires Beach S + Building S.
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Normal", "S")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "S")
	active_item_manager.unlocked_active_items[5] = true  # INVISIBILITY_SUIT, saved state

	unlock_manager.reset_and_apply_all_unlocks()

	assert_true(active_item_manager.is_active_item_unlocked(5),
		"Invisibility should remain unlocked after restart — player already opened the case (Issue #1052)")


func test_multi_condition_item_stays_locked_when_condition_not_met() -> void:
	# Corrupt save: INVISIBILITY_SUIT saved as unlocked but conditions not met.
	active_item_manager.unlocked_active_items[5] = true

	unlock_manager.reset_and_apply_all_unlocks()

	assert_false(active_item_manager.is_active_item_unlocked(5),
		"Invisibility should be locked — multi-conditions not met, treating save as corrupt (Issue #1052)")


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


# ============================================================================
# All-difficulties condition tests (Issue #1426 — Experimental Sample)
# ============================================================================


func test_all_difficulties_condition_not_met_when_no_progress() -> void:
	assert_false(unlock_manager.is_all_difficulties_condition_met(),
		"All-difficulties condition should not be met when no levels completed")


func test_all_difficulties_condition_not_met_when_only_some_difficulties() -> void:
	# Only Easy and Normal — missing Hard, Power Fantasy, Black Metal
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	assert_false(unlock_manager.is_all_difficulties_condition_met(),
		"All-difficulties condition should not be met when only 2 of 5 difficulties have progress")


func test_all_difficulties_condition_met_when_all_six_difficulties_have_progress() -> void:
	# Complete one level on each of the 6 difficulties (can be different levels)
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Hard", "F")
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Power Fantasy", "C")
	progress_manager.set_rank("res://scenes/levels/DocksLevel.tscn", "Black Metal", "D")
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Gunslinger", "D")
	assert_true(unlock_manager.is_all_difficulties_condition_met(),
		"All-difficulties condition should be met when at least one level completed on each difficulty")


func test_all_difficulties_condition_met_with_same_level_on_all_difficulties() -> void:
	# Same level completed on every difficulty (including Gunslinger - Issue #1732)
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "S")
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Normal", "A")
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Hard", "B")
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Power Fantasy", "C")
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Black Metal", "D")
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Gunslinger", "D")
	assert_true(unlock_manager.is_all_difficulties_condition_met(),
		"All-difficulties condition should be met when same level completed on all difficulties")


func test_experimental_sample_active_item_condition_met_when_all_difficulties_complete() -> void:
	# Complete one level on each difficulty (including Gunslinger) — EXPERIMENTAL_SAMPLE (type 18) condition should be met
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Hard", "F")
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Power Fantasy", "C")
	progress_manager.set_rank("res://scenes/levels/DocksLevel.tscn", "Black Metal", "D")
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Gunslinger", "D")
	assert_true(unlock_manager.is_active_item_condition_met(18),
		"EXPERIMENTAL_SAMPLE condition should be met when all difficulties have progress (Issue #1426)")


func test_experimental_sample_condition_not_met_before_all_difficulties() -> void:
	# Only 4 difficulties — condition not met yet (missing Black Metal and Gunslinger)
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Hard", "F")
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Power Fantasy", "C")
	# Missing Black Metal and Gunslinger
	assert_false(unlock_manager.is_active_item_condition_met(18),
		"EXPERIMENTAL_SAMPLE condition should NOT be met when Black Metal difficulty is missing (Issue #1426)")


func test_has_available_unlock_when_all_difficulties_condition_met() -> void:
	# Complete one level on each difficulty (including Gunslinger) — Experimental Sample should appear as available
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Hard", "F")
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Power Fantasy", "C")
	progress_manager.set_rank("res://scenes/levels/DocksLevel.tscn", "Black Metal", "D")
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Gunslinger", "D")
	assert_true(unlock_manager.has_any_available_unlock(),
		"has_any_available_unlock should return true when Experimental Sample is unlockable (Issue #1426)")


func test_experimental_sample_stays_unlocked_after_restart_when_condition_met() -> void:
	# Simulate saved state: all difficulties done (including Gunslinger) and EXPERIMENTAL_SAMPLE (18) already unlocked
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Hard", "F")
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Power Fantasy", "C")
	progress_manager.set_rank("res://scenes/levels/DocksLevel.tscn", "Black Metal", "D")
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Gunslinger", "D")
	active_item_manager.unlocked_active_items[18] = true  # Saved as unlocked

	unlock_manager.reset_and_apply_all_unlocks()

	assert_true(active_item_manager.is_active_item_unlocked(18),
		"EXPERIMENTAL_SAMPLE should remain unlocked after restart when all-difficulties condition is met (Issue #1426)")


func test_experimental_sample_stays_locked_after_restart_when_condition_not_met() -> void:
	# Corrupt save: EXPERIMENTAL_SAMPLE saved as unlocked but not all difficulties are done
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	active_item_manager.unlocked_active_items[18] = true  # Corrupt save

	unlock_manager.reset_and_apply_all_unlocks()

	assert_false(active_item_manager.is_active_item_unlocked(18),
		"EXPERIMENTAL_SAMPLE should be locked — all-difficulties condition not met, treating save as corrupt (Issue #1426)")


func test_experimental_sample_condition_not_met_when_gunslinger_missing() -> void:
	# Issue #1732: Gunslinger difficulty must be counted for Experimental Sample unlock
	# Having all 5 original difficulties but missing Gunslinger should NOT meet the condition
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Hard", "F")
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Power Fantasy", "C")
	progress_manager.set_rank("res://scenes/levels/DocksLevel.tscn", "Black Metal", "D")
	# Missing Gunslinger
	assert_false(unlock_manager.is_all_difficulties_condition_met(),
		"All-difficulties condition should NOT be met when Gunslinger is missing (Issue #1732)")
	assert_false(unlock_manager.is_active_item_condition_met(18),
		"EXPERIMENTAL_SAMPLE should NOT unlock when Gunslinger difficulty is missing (Issue #1732)")


func test_experimental_sample_condition_met_when_gunslinger_included() -> void:
	# Issue #1732: Adding a Gunslinger run satisfies the all-difficulties condition
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Easy", "D")
	progress_manager.set_rank("res://scenes/levels/BuildingLevel.tscn", "Normal", "D")
	progress_manager.set_rank("res://scenes/levels/CastleLevel.tscn", "Hard", "F")
	progress_manager.set_rank("res://scenes/levels/BeachLevel.tscn", "Power Fantasy", "C")
	progress_manager.set_rank("res://scenes/levels/DocksLevel.tscn", "Black Metal", "D")
	progress_manager.set_rank("res://scenes/levels/LabyrinthLevel.tscn", "Gunslinger", "F")
	assert_true(unlock_manager.is_all_difficulties_condition_met(),
		"All-difficulties condition should be met once Gunslinger is also completed (Issue #1732)")
	assert_true(unlock_manager.is_active_item_condition_met(18),
		"EXPERIMENTAL_SAMPLE should unlock once Gunslinger difficulty is completed (Issue #1732)")


# ============================================================================
# Kill-based unlock condition tests (Issue #1622 — fix armory button glow)
# ============================================================================


func test_laser_sight_condition_not_met_with_partial_kills() -> void:
	# Issue #1622: partial progress should NOT cause armory button to glow
	game_manager.kills_without_laser_sight = 200  # Only 200 of required 400
	assert_false(unlock_manager.is_kill_condition_met(unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Laser Sight condition should NOT be met with only 200/400 kills (partial progress)")
	assert_false(unlock_manager.has_any_available_unlock(),
		"has_any_available_unlock should return false with partial kill progress — armory button must NOT glow")


func test_laser_sight_condition_met_at_threshold() -> void:
	game_manager.kills_without_laser_sight = 400  # Exactly at threshold
	assert_true(unlock_manager.is_kill_condition_met(unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Laser Sight condition should be met at exactly 400 kills")
	assert_true(unlock_manager.has_any_available_unlock(),
		"has_any_available_unlock should return true when Laser Sight condition is met and item is still locked")


func test_laser_sight_condition_met_above_threshold() -> void:
	game_manager.kills_without_laser_sight = 600  # Above threshold
	assert_true(unlock_manager.is_kill_condition_met(unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Laser Sight condition should be met with 600 kills (above threshold)")


func test_laser_sight_no_available_unlock_when_already_unlocked() -> void:
	# Condition met AND item already unlocked — should NOT show as available to unlock
	game_manager.kills_without_laser_sight = 400
	active_item_manager.unlocked_active_items[9] = true  # LASER_SIGHT already unlocked by player
	assert_true(unlock_manager.is_kill_condition_met(unlock_manager.KILL_UNLOCK_CONDITIONS[0]),
		"Kill condition is met with 400 kills")
	assert_false(unlock_manager.has_any_available_unlock(),
		"has_any_available_unlock should return false when Laser Sight condition is met but item is already unlocked")


func test_fine_motor_skills_condition_not_met_with_partial_shots() -> void:
	# Issue #1622: partial progress (shots) should NOT glow armory button
	game_manager.shots_fired_special_weapons = 150  # Only 150 of required 300
	assert_false(unlock_manager.is_kill_condition_met(unlock_manager.KILL_UNLOCK_CONDITIONS[1]),
		"Fine Motor Skills condition should NOT be met with only 150/300 shots")
	assert_false(unlock_manager.has_any_available_unlock(),
		"has_any_available_unlock should return false with partial shot progress")


func test_fine_motor_skills_condition_met_at_threshold() -> void:
	game_manager.shots_fired_special_weapons = 300  # At threshold
	assert_true(unlock_manager.is_kill_condition_met(unlock_manager.KILL_UNLOCK_CONDITIONS[1]),
		"Fine Motor Skills condition should be met at exactly 300 shots")
	assert_true(unlock_manager.has_any_available_unlock(),
		"has_any_available_unlock should return true when Fine Motor Skills condition is met and item is locked")


func test_breaker_bullets_condition_not_met_below_threshold() -> void:
	# Issue #1622: 6 out of 7 required A-rank levels → partial progress, no glow
	game_manager.levels_completed_rank_a_or_higher = 6
	assert_false(unlock_manager.is_kill_condition_met(unlock_manager.KILL_UNLOCK_CONDITIONS[4]),
		"Breaker Bullets condition should NOT be met with only 6/7 A-rank levels")
	assert_false(unlock_manager.has_any_available_unlock(),
		"has_any_available_unlock should return false with 6/7 A-rank levels")


func test_breaker_bullets_condition_met_at_threshold() -> void:
	game_manager.levels_completed_rank_a_or_higher = 7  # At threshold
	assert_true(unlock_manager.is_kill_condition_met(unlock_manager.KILL_UNLOCK_CONDITIONS[4]),
		"Breaker Bullets condition should be met at exactly 7 A-rank levels")
	assert_true(unlock_manager.has_any_available_unlock(),
		"has_any_available_unlock should return true when Breaker Bullets condition is met")


func test_no_available_unlock_with_zero_kill_stats() -> void:
	# Issue #1622: fresh save — all kill stats at 0, no level progress → button must NOT glow
	assert_false(unlock_manager.has_any_available_unlock(),
		"has_any_available_unlock must return false with all kill stats at 0 and no level progress")
