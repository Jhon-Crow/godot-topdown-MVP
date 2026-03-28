extends Node
## Autoload singleton for managing condition-based item unlocks.
##
## Tracks which items can be unlocked by completing certain levels at certain grades.
## When a level is completed with a qualifying grade, the corresponding locked item slots
## highlight in gold in the armory. The player must then hold LMB on a gold slot to
## permanently unlock the item (the armory handles the actual unlock call).
##
## Issue #894: добавь систему анлоков (Add an unlock system)

## Rank ordering for comparison (higher index = better rank).
const RANK_ORDER: Array[String] = ["F", "D", "C", "B", "A", "A+", "S"]

## Unlock conditions: maps a level path to a list of unlock entries.
## Each entry has:
##   - "min_rank": The minimum rank required to unlock (e.g., "D" = grade D or higher)
##   - "weapons": List of weapon IDs to unlock
##   - "grenades": List of grenade type ints to unlock
##   - "active_items": List of active item type ints to unlock
## Issue #1000: update unlock system
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
		"grenades": [1],    # GrenadeManager.GrenadeType.FRAG = 1 (Issue #1000 req.1)
		"active_items": []
	},
	"res://scenes/levels/BuildingLevel.tscn:S": {
		"min_rank": "S",
		"weapons": ["silenced_pistol"],  # Issue #1000 req.2
		"grenades": [],
		"active_items": []
	},
	"res://scenes/levels/TestTier.tscn": {
		"min_rank": "D",
		"weapons": ["sniper"],
		"grenades": [],
		"active_items": [1]  # ActiveItemManager.ActiveItemType.FLASHLIGHT = 1
	},
	"res://scenes/levels/CastleLevel.tscn": {
		"min_rank": "F",
		"weapons": ["revolver"],
		"grenades": [],
		"active_items": []  # Teleport moved to Double Corridor (Issue #1000 req.3)
	},
	"res://scenes/levels/RevolverLevel.tscn": {
		"min_rank": "D",
		"weapons": [],
		"grenades": [],
		"active_items": [3]  # ActiveItemManager.ActiveItemType.TELEPORT_BRACERS = 3 (Issue #1000 req.3)
	},
	"res://scenes/levels/CityLevel.tscn": {
		"min_rank": "F",
		"weapons": [],
		"grenades": [],
		"active_items": [8]  # ActiveItemManager.ActiveItemType.TRAJECTORY_GLASSES = 8 (Issue #1692 req.2)
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
		"grenades": [2],    # GrenadeManager.GrenadeType.DEFENSIVE = 2 (F-1 grenade, Issue #1000 req.6)
		"active_items": []
	},
	"res://scenes/levels/DocksLevel.tscn": {
		"min_rank": "D",
		"weapons": ["silenced_pistol"],  # Issue #1000 req.7
		"grenades": [3],    # GrenadeManager.GrenadeType.AGGRESSION_GAS = 3 (Issue #1624 req.4)
		"active_items": []
	},
	"res://scenes/levels/DecadenceLevel.tscn": {
		"min_rank": "F",
		"weapons": ["ak_gl"],  # Issue #1423 req.1: complete Decadence → unlock AK
		"grenades": [],
		"active_items": []
	},
	"res://scenes/levels/FactoryLevel.tscn": {
		"min_rank": "F",
		"weapons": [],
		"grenades": [],
		"active_items": [7]  # ActiveItemManager.ActiveItemType.FORCE_FIELD = 7 (Issue #1589 req.2)
	},
	"res://scenes/levels/LabyrinthLevel.tscn:S": {
		"min_rank": "S",
		"weapons": [],
		"grenades": [],
		"active_items": [16]  # ActiveItemManager.ActiveItemType.RECOIL_COMPENSATOR = 16 (Issue #1423 req.2)
	},
	"res://scenes/levels/RevolverLevel.tscn:A": {
		"min_rank": "A",
		"weapons": [],
		"grenades": [],
		"active_items": [10]  # ActiveItemManager.ActiveItemType.EXTENDED_MAGAZINE = 10 (Issue #1692 req.1)
	},
	"res://scenes/levels/DecadenceLevel.tscn:A+": {
		"min_rank": "A+",
		"weapons": [],
		"grenades": [],
		"active_items": [20]  # ActiveItemManager.ActiveItemType.DASH = 20 (Issue #1624 req.5)
	},
	"res://scenes/levels/Labyrinth2Level.tscn": {
		"min_rank": "F",
		"weapons": [],
		"grenades": [],
		"active_items": [12]  # ActiveItemManager.ActiveItemType.BREACHING_CHARGES = 12 (Issue #1624 req.6)
	},
	"res://scenes/levels/SewerLevel.tscn": {
		"min_rank": "F",
		"weapons": [],
		"grenades": [4],    # GrenadeManager.GrenadeType.DRONE = 4 (Issue #1624 req.7)
		"active_items": []
	},
	"res://scenes/levels/RailwayStationLevel.tscn": {
		"min_rank": "F",
		"weapons": [],
		"grenades": [],
		"active_items": [21]  # ActiveItemManager.ActiveItemType.GRENADE_BAG = 21 (Issue #1624 req.8)
	},
	"res://scenes/levels/WinterForestLevel.tscn": {
		"min_rank": "F",
		"weapons": [],
		"grenades": [],
		"active_items": [4]  # ActiveItemManager.ActiveItemType.BFF_PENDANT = 4 (Issue #1624 req.9)
	}
}

## All-difficulties unlock conditions: unlocks that require completing at least one level on EVERY
## available difficulty (not necessarily the same level — just at least one level per difficulty).
## Each entry has:
##   - "weapons": List of weapon IDs to unlock
##   - "grenades": List of grenade type ints to unlock
##   - "active_items": List of active item type ints to unlock
## Issue #1426: открывать Экспериментальный Образец за прохождение хотя бы одного уровня на всех сложностях
const ALL_DIFFICULTIES_UNLOCK_CONDITIONS: Array[Dictionary] = [
	{
		# Complete at least one level on each difficulty → unlock Experimental Sample (Issue #1426)
		"weapons": [],
		"grenades": [],
		"active_items": [18]  # ActiveItemManager.ActiveItemType.EXPERIMENTAL_SAMPLE = 18
	}
]

## Kill-based unlock conditions: unlocks that require accumulating a stat in GameManager.
## Each entry has:
##   - "stat": The GameManager variable to read (e.g. "kills_without_laser_sight")
##   - "min_kills": The minimum value of the stat required
##   - "weapons": List of weapon IDs to unlock
##   - "grenades": List of grenade type ints to unlock
##   - "active_items": List of active item type ints to unlock
## Issue #1196: добавь условие разблокировки предмета Лазерный прицел
## Issue #1346: добавь условие разблокировки предмета Хорошая Мелкая Моторика
## Issue #1389: update unlock conditions
const KILL_UNLOCK_CONDITIONS: Array[Dictionary] = [
	{
		# 400 kills without Laser Sight → unlock Laser Sight (Issue #1196, updated by Issue #1589)
		"stat": "kills_without_laser_sight",
		"min_kills": 400,
		"weapons": [],
		"grenades": [],
		"active_items": [9]  # ActiveItemManager.ActiveItemType.LASER_SIGHT = 9
	},
	{
		# 650 shots with shotgun, sniper rifle, or revolver → unlock Fine Motor Skills (Issue #1346, Issue #1053 req.2)
		"stat": "shots_fired_special_weapons",
		"min_kills": 650,
		"weapons": [],
		"grenades": [],
		"active_items": [19]  # ActiveItemManager.ActiveItemType.FINE_MOTOR_SKILLS = 19
	},
	{
		# 100 total deaths → unlock Armored Skin (Issue #1389)
		"stat": "total_deaths",
		"min_kills": 100,
		"weapons": [],
		"grenades": [],
		"active_items": [13]  # ActiveItemManager.ActiveItemType.ARMORED_SKIN = 13
	},
	{
		# 1 level completed without damage → unlock Combat Disposition (Issue #1389)
		"stat": "no_damage_levels_completed",
		"min_kills": 1,
		"weapons": [],
		"grenades": [],
		"active_items": [17]  # ActiveItemManager.ActiveItemType.COMBAT_DISPOSITION = 17
	},
	{
		# 7 levels completed at rank A or higher → unlock Breaker Bullets (Issue #1589 req.3)
		"stat": "levels_completed_rank_a_or_higher",
		"min_kills": 7,
		"weapons": [],
		"grenades": [],
		"active_items": [6]  # ActiveItemManager.ActiveItemType.BREAKER_BULLETS = 6
	},
	{
		# 50 kills through walls (any weapon) → unlock Drilling Bullets (Issue #1624 req.3)
		"stat": "kills_through_wall",
		"min_kills": 50,
		"weapons": [],
		"grenades": [],
		"active_items": [15]  # ActiveItemManager.ActiveItemType.DRILLING_BULLETS = 15
	},
	{
		# Complete any level with silenced pistol → unlock Auto Reload (Issue #1624 req.2)
		"stat": "levels_completed_with_silenced_pistol",
		"min_kills": 1,
		"weapons": [],
		"grenades": [],
		"active_items": [14]  # ActiveItemManager.ActiveItemType.AUTO_RELOAD = 14
	}
]

## Multi-level unlock conditions: unlocks that require ALL listed levels to be completed at min_rank.
## Each entry has:
##   - "levels": Array of level paths, each with its own "min_rank"
##   - "weapons": List of weapon IDs to unlock
##   - "grenades": List of grenade type ints to unlock
##   - "active_items": List of active item type ints to unlock
## Issue #1000: req.5 and req.8
const MULTI_UNLOCK_CONDITIONS: Array[Dictionary] = [
	{
		# Beach S + Building S → Invisibility (Issue #1000 req.5)
		"levels": [
			{"path": "res://scenes/levels/BeachLevel.tscn", "min_rank": "S"},
			{"path": "res://scenes/levels/BuildingLevel.tscn", "min_rank": "S"}
		],
		"weapons": [],
		"grenades": [],
		"active_items": [5]  # ActiveItemManager.ActiveItemType.INVISIBILITY_SUIT = 5
	},
	{
		# Labyrinth S + Building S + Polygon S + Castle S + Double Corridor S → Homing Bullets (Issue #1000 req.8)
		"levels": [
			{"path": "res://scenes/levels/LabyrinthLevel.tscn", "min_rank": "S"},
			{"path": "res://scenes/levels/BuildingLevel.tscn", "min_rank": "S"},
			{"path": "res://scenes/levels/TestTier.tscn", "min_rank": "S"},
			{"path": "res://scenes/levels/CastleLevel.tscn", "min_rank": "S"},
			{"path": "res://scenes/levels/RevolverLevel.tscn", "min_rank": "S"}
		],
		"weapons": [],
		"grenades": [],
		"active_items": [2]  # ActiveItemManager.ActiveItemType.HOMING_BULLETS = 2
	}
]

## Signal emitted when any item is unlocked via a level condition.
signal items_unlocked_by_condition(level_path: String)

## Signal emitted when a kill-based unlock condition becomes available.
signal items_unlocked_by_kill_condition


func _ready() -> void:
	# Connect to ProgressManager to check conditions whenever progress is updated
	var progress_manager: Node = get_node_or_null("/root/ProgressManager")
	if progress_manager and progress_manager.has_signal("progress_updated"):
		progress_manager.progress_updated.connect(_on_progress_updated)
	# Connect to GameManager to check kill-based conditions whenever a qualifying kill is made
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_signal("kills_without_laser_sight_updated"):
			game_manager.kills_without_laser_sight_updated.connect(_on_kills_without_laser_sight_updated)
		if game_manager.has_signal("shots_fired_special_weapons_updated"):
			game_manager.shots_fired_special_weapons_updated.connect(_on_shots_fired_special_weapons_updated)
		if game_manager.has_signal("total_deaths_updated"):
			game_manager.total_deaths_updated.connect(_on_total_deaths_updated)
		if game_manager.has_signal("no_damage_levels_completed_updated"):
			game_manager.no_damage_levels_completed_updated.connect(_on_no_damage_levels_completed_updated)
		if game_manager.has_signal("levels_completed_rank_a_or_higher_updated"):
			game_manager.levels_completed_rank_a_or_higher_updated.connect(_on_levels_completed_rank_a_or_higher_updated)
		if game_manager.has_signal("kills_through_wall_updated"):
			game_manager.kills_through_wall_updated.connect(_on_kills_through_wall_updated)
		if game_manager.has_signal("levels_completed_with_silenced_pistol_updated"):
			game_manager.levels_completed_with_silenced_pistol_updated.connect(_on_levels_completed_with_silenced_pistol_updated)
	# Reset condition-gated items to locked state first (in case old save data has them incorrectly
	# marked as unlocked), then re-apply earned unlocks from progress. This ensures the unlock
	# state is always consistent with actual level completion progress.
	# Note: deferred so PersistManager has already loaded its saved state before we reset.
	call_deferred("_reset_and_apply_all_unlocks")
	_log("UnlockManager ready")


## Called when ProgressManager emits progress_updated after a level is completed.
## Checks if any unlock conditions are now satisfied (items turn gold in armory).
## Note: items are NOT auto-unlocked here — the player must hold LMB on the gold
## slot in the armory to actually unlock them.
func _on_progress_updated(level_path: String, difficulty_name: String) -> void:
	# Notify that conditions may have changed so armory can refresh gold highlights.
	# Check single-level conditions (any key whose scene path matches this level).
	for condition_key in UNLOCK_CONDITIONS:
		if _extract_scene_path(condition_key) == level_path and is_condition_key_met(condition_key):
			items_unlocked_by_condition.emit(level_path)
			_log("Condition met for level: %s — items now available to unlock in armory" % level_path)
			break
	# Check multi-level conditions.
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		for level_entry in multi_condition.get("levels", []):
			if level_entry.get("path", "") == level_path:
				if is_multi_condition_met(multi_condition):
					items_unlocked_by_condition.emit(level_path)
					_log("Multi-condition met involving level: %s" % level_path)
				break
	# Check all-difficulties conditions.
	if is_all_difficulties_condition_met():
		items_unlocked_by_condition.emit(level_path)
		_log("All-difficulties condition met — Experimental Sample now available to unlock in armory")


## Called when GameManager emits kills_without_laser_sight_updated.
## Checks if any kill-based unlock conditions are now satisfied (items turn gold in armory).
func _on_kills_without_laser_sight_updated(_new_count: int) -> void:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if is_kill_condition_met(kill_condition):
			items_unlocked_by_kill_condition.emit()
			_log("Kill condition met — items now available to unlock in armory")
			break


## Called when GameManager emits shots_fired_special_weapons_updated.
## Checks if any shot-based unlock conditions (stored in KILL_UNLOCK_CONDITIONS) are now satisfied.
## Issue #1346.
func _on_shots_fired_special_weapons_updated(_new_count: int) -> void:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if kill_condition.get("stat", "") == "shots_fired_special_weapons" and is_kill_condition_met(kill_condition):
			items_unlocked_by_kill_condition.emit()
			_log("Shot condition met — Fine Motor Skills now available to unlock in armory")
			break


## Called when GameManager emits total_deaths_updated.
## Checks if the Armored Skin death-based unlock condition is now satisfied.
## Issue #1389.
func _on_total_deaths_updated(_new_count: int) -> void:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if kill_condition.get("stat", "") == "total_deaths" and is_kill_condition_met(kill_condition):
			items_unlocked_by_kill_condition.emit()
			_log("Death condition met — Armored Skin now available to unlock in armory")
			break


## Called when GameManager emits no_damage_levels_completed_updated.
## Checks if the Combat Disposition no-damage-level condition is now satisfied.
## Issue #1389.
func _on_no_damage_levels_completed_updated(_new_count: int) -> void:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if kill_condition.get("stat", "") == "no_damage_levels_completed" and is_kill_condition_met(kill_condition):
			items_unlocked_by_kill_condition.emit()
			_log("No-damage level condition met — Combat Disposition now available to unlock in armory")
			break


## Called when GameManager emits levels_completed_rank_a_or_higher_updated.
## Checks if the Breaker Bullets rank-A condition is now satisfied.
## Issue #1589.
func _on_levels_completed_rank_a_or_higher_updated(_new_count: int) -> void:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if kill_condition.get("stat", "") == "levels_completed_rank_a_or_higher" and is_kill_condition_met(kill_condition):
			items_unlocked_by_kill_condition.emit()
			_log("Rank-A level condition met — Breaker Bullets now available to unlock in armory")
			break


## Called when GameManager emits kills_through_wall_updated.
## Checks if the Drilling Bullets wall-kill condition is now satisfied.
## Issue #1624.
func _on_kills_through_wall_updated(_new_count: int) -> void:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if kill_condition.get("stat", "") == "kills_through_wall" and is_kill_condition_met(kill_condition):
			items_unlocked_by_kill_condition.emit()
			_log("Wall-kill condition met — Drilling Bullets now available to unlock in armory")
			break


## Called when GameManager emits levels_completed_with_silenced_pistol_updated.
## Checks if the Auto Reload silenced-pistol level condition is now satisfied.
## Issue #1624.
func _on_levels_completed_with_silenced_pistol_updated(_new_count: int) -> void:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if kill_condition.get("stat", "") == "levels_completed_with_silenced_pistol" and is_kill_condition_met(kill_condition):
			items_unlocked_by_kill_condition.emit()
			_log("Silenced-pistol level condition met — Auto Reload now available to unlock in armory")
			break


## Get the best rank for a level across all difficulties.
## @param level_path: The scene file path of the level.
## @return: The best rank string, or "" if never completed.
func _get_best_rank_any_difficulty(level_path: String) -> String:
	var progress_manager: Node = get_node_or_null("/root/ProgressManager")
	if not progress_manager:
		return ""

	var best_rank: String = ""
	for difficulty_name in _get_all_difficulty_names():
		var rank: String = progress_manager.get_best_rank(level_path, difficulty_name)
		if not rank.is_empty() and _is_rank_better(rank, best_rank):
			best_rank = rank

	return best_rank


## Check if a rank meets or exceeds the minimum rank requirement.
## @param rank: The rank to check.
## @param min_rank: The minimum rank required.
## @return: true if rank is >= min_rank.
func _is_rank_sufficient(rank: String, min_rank: String) -> bool:
	if min_rank == "F":
		# F or higher means any completed run counts
		return not rank.is_empty()
	return not _is_rank_better(min_rank, rank)  # min_rank is not better than rank => rank >= min_rank


## Compare two ranks. Returns true if new_rank is strictly better than old_rank.
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


## Extract the actual scene path from a condition key.
## Keys may have a rank suffix like "res://scenes/levels/BuildingLevel.tscn:S".
## Returns the scene path part only.
func _extract_scene_path(condition_key: String) -> String:
	# Strip ":RANK" suffix if present (the suffix won't start with "res://")
	var last_colon: int = condition_key.rfind(":")
	if last_colon > 0 and not condition_key.substr(0, last_colon).ends_with("//"):
		# The suffix is a rank like ":S", ":D", etc. (short, no slashes)
		var suffix: String = condition_key.substr(last_colon + 1)
		if suffix in RANK_ORDER:
			return condition_key.substr(0, last_colon)
	return condition_key


## Check if a specific condition key's unlock condition is currently met (for UI highlighting).
## @param condition_key: The key in UNLOCK_CONDITIONS (may have rank suffix).
## @return: true if the condition has been met (item can be unlocked).
func is_condition_key_met(condition_key: String) -> bool:
	if condition_key not in UNLOCK_CONDITIONS:
		return false
	var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
	var min_rank: String = condition.get("min_rank", "D")
	var scene_path: String = _extract_scene_path(condition_key)
	var best_rank: String = _get_best_rank_any_difficulty(scene_path)
	return _is_rank_sufficient(best_rank, min_rank)


## Check if a specific level's unlock condition is currently met (for UI highlighting).
## Checks all condition keys that match this level path.
## @param level_path: The scene file path of the level.
## @return: true if any condition for this level has been met.
func is_level_condition_met(level_path: String) -> bool:
	for condition_key in UNLOCK_CONDITIONS:
		if _extract_scene_path(condition_key) == level_path:
			if is_condition_key_met(condition_key):
				return true
	return false


## Check if a multi-level condition is currently met (all levels at required rank).
## @param multi_condition: A dictionary from MULTI_UNLOCK_CONDITIONS.
## @return: true if all levels meet their minimum rank requirement.
func is_multi_condition_met(multi_condition: Dictionary) -> bool:
	for level_entry in multi_condition.get("levels", []):
		var path: String = level_entry.get("path", "")
		var min_rank: String = level_entry.get("min_rank", "D")
		var best_rank: String = _get_best_rank_any_difficulty(path)
		if not _is_rank_sufficient(best_rank, min_rank):
			return false
	return true


## Check if the all-difficulties unlock condition is currently met.
## The condition is met when at least one level has been completed on every available difficulty.
## @return: true if at least one level has been completed on each difficulty.
func is_all_difficulties_condition_met() -> bool:
	var progress_manager: Node = get_node_or_null("/root/ProgressManager")
	if not progress_manager:
		return false
	for difficulty_name in _get_all_difficulty_names():
		var found: bool = false
		for key in progress_manager.get_all_progress():
			# Key format: "level_path:difficulty_name"
			if key.ends_with(":" + difficulty_name):
				found = true
				break
		if not found:
			return false
	return true


## Check if a kill-based unlock condition is currently met.
## @param kill_condition: A dictionary from KILL_UNLOCK_CONDITIONS.
## @return: true if the qualifying kill count meets or exceeds min_kills.
func is_kill_condition_met(kill_condition: Dictionary) -> bool:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if not game_manager:
		return false
	var stat: String = kill_condition.get("stat", "")
	var min_kills: int = kill_condition.get("min_kills", 0)
	if stat.is_empty():
		return false
	var current_kills: int = game_manager.get(stat) if game_manager.get(stat) != null else 0
	return current_kills >= min_kills


## Get all weapon IDs that are unlockable via level conditions (have a condition defined).
## @return: Array of weapon IDs that have unlock conditions.
func get_weapons_with_conditions() -> Array[String]:
	var result: Array[String] = []
	for condition_key in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		for weapon_id in condition.get("weapons", []):
			if weapon_id not in result:
				result.append(weapon_id)
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		for weapon_id in multi_condition.get("weapons", []):
			if weapon_id not in result:
				result.append(weapon_id)
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		for weapon_id in kill_condition.get("weapons", []):
			if weapon_id not in result:
				result.append(weapon_id)
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		for weapon_id in all_diff_condition.get("weapons", []):
			if weapon_id not in result:
				result.append(weapon_id)
	return result


## Get all active item types that are unlockable via level conditions.
## @return: Array of active item type ints that have unlock conditions.
func get_active_items_with_conditions() -> Array[int]:
	var result: Array[int] = []
	for condition_key in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		for item_type in condition.get("active_items", []):
			if item_type not in result:
				result.append(item_type)
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		for item_type in multi_condition.get("active_items", []):
			if item_type not in result:
				result.append(item_type)
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		for item_type in kill_condition.get("active_items", []):
			if item_type not in result:
				result.append(item_type)
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		for item_type in all_diff_condition.get("active_items", []):
			if item_type not in result:
				result.append(item_type)
	return result


## Get all grenade types that are unlockable via level conditions.
## @return: Array of grenade type ints that have unlock conditions.
func get_grenades_with_conditions() -> Array[int]:
	var result: Array[int] = []
	for condition_key in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		for grenade_type in condition.get("grenades", []):
			if grenade_type not in result:
				result.append(grenade_type)
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		for grenade_type in multi_condition.get("grenades", []):
			if grenade_type not in result:
				result.append(grenade_type)
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		for grenade_type in kill_condition.get("grenades", []):
			if grenade_type not in result:
				result.append(grenade_type)
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		for grenade_type in all_diff_condition.get("grenades", []):
			if grenade_type not in result:
				result.append(grenade_type)
	return result


## Check if a weapon's unlock condition is currently met (for gold highlighting in armory).
## Returns true if the player has earned the right to unlock this weapon
## (condition met), but the weapon may or may not have been unlocked yet
## (use GameManager.is_weapon_unlocked for that).
## @param weapon_id: The weapon ID to check.
## @return: true if any level or kill condition that unlocks this weapon is met.
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
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if weapon_id in kill_condition.get("weapons", []):
			if is_kill_condition_met(kill_condition):
				return true
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		if weapon_id in all_diff_condition.get("weapons", []):
			if is_all_difficulties_condition_met():
				return true
	return false


## Check if an active item's unlock condition is currently met (for gold highlighting in armory).
## @param item_type: The active item type to check.
## @return: true if any level or kill condition that unlocks this item is met.
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
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if item_type in kill_condition.get("active_items", []):
			if is_kill_condition_met(kill_condition):
				return true
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		if item_type in all_diff_condition.get("active_items", []):
			if is_all_difficulties_condition_met():
				return true
	return false


## Check if a grenade's unlock condition is currently met (for gold highlighting in armory).
## @param grenade_type: The grenade type to check.
## @return: true if any level or kill condition that unlocks this grenade is met.
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
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if grenade_type in kill_condition.get("grenades", []):
			if is_kill_condition_met(kill_condition):
				return true
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		if grenade_type in all_diff_condition.get("grenades", []):
			if is_all_difficulties_condition_met():
				return true
	return false


## Check if there is any item (weapon, grenade, or active item) whose unlock condition
## is met but which has not yet been unlocked by the player.
## Used to highlight the Armory button in the pause menu and score screen.
## @return: true if at least one item is ready to unlock (condition met, but still locked).
func has_any_available_unlock() -> bool:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")

	for condition_key in UNLOCK_CONDITIONS:
		if not is_condition_key_met(condition_key):
			continue
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]

		# Check condition-gated weapons
		if game_manager:
			for weapon_id in condition.get("weapons", []):
				if game_manager.has_method("is_weapon_unlocked") and not game_manager.is_weapon_unlocked(weapon_id):
					return true

		# Check condition-gated active items
		if active_item_manager:
			for item_type in condition.get("active_items", []):
				if active_item_manager.has_method("is_active_item_unlocked") and not active_item_manager.is_active_item_unlocked(item_type):
					return true

		# Check condition-gated grenades
		if grenade_manager:
			for grenade_type in condition.get("grenades", []):
				if grenade_manager.has_method("is_grenade_unlocked") and not grenade_manager.is_grenade_unlocked(grenade_type):
					return true

	# Check multi-level conditions
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		if not is_multi_condition_met(multi_condition):
			continue

		if game_manager:
			for weapon_id in multi_condition.get("weapons", []):
				if game_manager.has_method("is_weapon_unlocked") and not game_manager.is_weapon_unlocked(weapon_id):
					return true

		if active_item_manager:
			for item_type in multi_condition.get("active_items", []):
				if active_item_manager.has_method("is_active_item_unlocked") and not active_item_manager.is_active_item_unlocked(item_type):
					return true

		if grenade_manager:
			for grenade_type in multi_condition.get("grenades", []):
				if grenade_manager.has_method("is_grenade_unlocked") and not grenade_manager.is_grenade_unlocked(grenade_type):
					return true

	# Check kill-based conditions
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if not is_kill_condition_met(kill_condition):
			continue

		if game_manager:
			for weapon_id in kill_condition.get("weapons", []):
				if game_manager.has_method("is_weapon_unlocked") and not game_manager.is_weapon_unlocked(weapon_id):
					return true

		if active_item_manager:
			for item_type in kill_condition.get("active_items", []):
				if active_item_manager.has_method("is_active_item_unlocked") and not active_item_manager.is_active_item_unlocked(item_type):
					return true

		if grenade_manager:
			for grenade_type in kill_condition.get("grenades", []):
				if grenade_manager.has_method("is_grenade_unlocked") and not grenade_manager.is_grenade_unlocked(grenade_type):
					return true

	# Check all-difficulties conditions
	if is_all_difficulties_condition_met():
		for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
			if game_manager:
				for weapon_id in all_diff_condition.get("weapons", []):
					if game_manager.has_method("is_weapon_unlocked") and not game_manager.is_weapon_unlocked(weapon_id):
						return true

			if active_item_manager:
				for item_type in all_diff_condition.get("active_items", []):
					if active_item_manager.has_method("is_active_item_unlocked") and not active_item_manager.is_active_item_unlocked(item_type):
						return true

			if grenade_manager:
				for grenade_type in all_diff_condition.get("grenades", []):
					if grenade_manager.has_method("is_grenade_unlocked") and not grenade_manager.is_grenade_unlocked(grenade_type):
						return true

	return false


## Reset all condition-gated items to locked state.
## This undoes any incorrect unlock state that may have been loaded from an old save file,
## ensuring only legitimately earned items remain unlocked (via apply_all_earned_unlocks).
func _reset_condition_gated_items() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")

	for condition_key in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]

		# Reset condition-gated weapons
		if game_manager:
			for weapon_id in condition.get("weapons", []):
				if weapon_id in game_manager.unlocked_weapons:
					game_manager.unlocked_weapons[weapon_id] = false

		# Reset condition-gated active items
		if active_item_manager:
			for item_type in condition.get("active_items", []):
				if item_type in active_item_manager.unlocked_active_items:
					active_item_manager.unlocked_active_items[item_type] = false

		# Reset condition-gated grenades
		if grenade_manager:
			for grenade_type in condition.get("grenades", []):
				if grenade_type in grenade_manager.unlocked_grenades:
					grenade_manager.unlocked_grenades[grenade_type] = false

	# Also reset items from multi-level conditions
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		if game_manager:
			for weapon_id in multi_condition.get("weapons", []):
				if weapon_id in game_manager.unlocked_weapons:
					game_manager.unlocked_weapons[weapon_id] = false

		if active_item_manager:
			for item_type in multi_condition.get("active_items", []):
				if item_type in active_item_manager.unlocked_active_items:
					active_item_manager.unlocked_active_items[item_type] = false

		if grenade_manager:
			for grenade_type in multi_condition.get("grenades", []):
				if grenade_type in grenade_manager.unlocked_grenades:
					grenade_manager.unlocked_grenades[grenade_type] = false

	# Also reset items from kill-based conditions
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if game_manager:
			for weapon_id in kill_condition.get("weapons", []):
				if weapon_id in game_manager.unlocked_weapons:
					game_manager.unlocked_weapons[weapon_id] = false

		if active_item_manager:
			for item_type in kill_condition.get("active_items", []):
				if item_type in active_item_manager.unlocked_active_items:
					active_item_manager.unlocked_active_items[item_type] = false

		if grenade_manager:
			for grenade_type in kill_condition.get("grenades", []):
				if grenade_type in grenade_manager.unlocked_grenades:
					grenade_manager.unlocked_grenades[grenade_type] = false

	# Also reset items from all-difficulties conditions
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		if game_manager:
			for weapon_id in all_diff_condition.get("weapons", []):
				if weapon_id in game_manager.unlocked_weapons:
					game_manager.unlocked_weapons[weapon_id] = false

		if active_item_manager:
			for item_type in all_diff_condition.get("active_items", []):
				if item_type in active_item_manager.unlocked_active_items:
					active_item_manager.unlocked_active_items[item_type] = false

		if grenade_manager:
			for grenade_type in all_diff_condition.get("grenades", []):
				if grenade_type in grenade_manager.unlocked_grenades:
					grenade_manager.unlocked_grenades[grenade_type] = false

	_log("Reset condition-gated items to locked state")


## Reset condition-gated items to locked state on startup, then restore items that
## the player legitimately unlocked (i.e., they opened the case by holding LMB).
## PersistManager has already loaded the saved unlock state before this runs (deferred).
## The reset removes any incorrectly-saved states; the restore brings back valid unlocks.
## Issue #1052: items were reverting to locked state after game restart.
func _reset_and_apply_all_unlocks() -> void:
	# Snapshot which condition-gated items PersistManager already restored from the save file.
	var saved_weapons: Array[String] = _get_unlocked_condition_gated_weapons()
	var saved_grenades: Array[int] = _get_unlocked_condition_gated_grenades()
	var saved_active_items: Array[int] = _get_unlocked_condition_gated_active_items()

	# Reset all condition-gated items to locked (removes corrupt / legacy unlock states).
	_reset_condition_gated_items()

	# Re-apply only items that were saved AND whose condition is currently met.
	# Items unlocked without a met condition indicate corrupt data and stay locked.
	_restore_saved_unlocks(saved_weapons, saved_grenades, saved_active_items)


## Collect weapon IDs from all condition tables that are currently marked as unlocked in GameManager.
func _get_unlocked_condition_gated_weapons() -> Array[String]:
	var result: Array[String] = []
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if not game_manager:
		return result
	for condition_key in UNLOCK_CONDITIONS:
		for weapon_id in UNLOCK_CONDITIONS[condition_key].get("weapons", []):
			if weapon_id not in result and game_manager.unlocked_weapons.get(weapon_id, false):
				result.append(weapon_id)
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		for weapon_id in multi_condition.get("weapons", []):
			if weapon_id not in result and game_manager.unlocked_weapons.get(weapon_id, false):
				result.append(weapon_id)
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		for weapon_id in kill_condition.get("weapons", []):
			if weapon_id not in result and game_manager.unlocked_weapons.get(weapon_id, false):
				result.append(weapon_id)
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		for weapon_id in all_diff_condition.get("weapons", []):
			if weapon_id not in result and game_manager.unlocked_weapons.get(weapon_id, false):
				result.append(weapon_id)
	return result


## Collect grenade types from all condition tables that are currently marked as unlocked.
func _get_unlocked_condition_gated_grenades() -> Array[int]:
	var result: Array[int] = []
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	if not grenade_manager:
		return result
	for condition_key in UNLOCK_CONDITIONS:
		for grenade_type in UNLOCK_CONDITIONS[condition_key].get("grenades", []):
			if grenade_type not in result and grenade_manager.unlocked_grenades.get(grenade_type, false):
				result.append(grenade_type)
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		for grenade_type in multi_condition.get("grenades", []):
			if grenade_type not in result and grenade_manager.unlocked_grenades.get(grenade_type, false):
				result.append(grenade_type)
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		for grenade_type in kill_condition.get("grenades", []):
			if grenade_type not in result and grenade_manager.unlocked_grenades.get(grenade_type, false):
				result.append(grenade_type)
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		for grenade_type in all_diff_condition.get("grenades", []):
			if grenade_type not in result and grenade_manager.unlocked_grenades.get(grenade_type, false):
				result.append(grenade_type)
	return result


## Collect active item types from all condition tables that are currently marked as unlocked.
func _get_unlocked_condition_gated_active_items() -> Array[int]:
	var result: Array[int] = []
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if not active_item_manager:
		return result
	for condition_key in UNLOCK_CONDITIONS:
		for item_type in UNLOCK_CONDITIONS[condition_key].get("active_items", []):
			if item_type not in result and active_item_manager.unlocked_active_items.get(item_type, false):
				result.append(item_type)
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		for item_type in multi_condition.get("active_items", []):
			if item_type not in result and active_item_manager.unlocked_active_items.get(item_type, false):
				result.append(item_type)
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		for item_type in kill_condition.get("active_items", []):
			if item_type not in result and active_item_manager.unlocked_active_items.get(item_type, false):
				result.append(item_type)
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		for item_type in all_diff_condition.get("active_items", []):
			if item_type not in result and active_item_manager.unlocked_active_items.get(item_type, false):
				result.append(item_type)
	return result


## Restore saved unlock state for condition-gated items after a reset.
## Only items whose unlock condition is currently met are restored; others stay locked.
func _restore_saved_unlocks(
		weapons: Array[String],
		grenades: Array[int],
		active_items: Array[int]) -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")

	for weapon_id in weapons:
		if game_manager and is_weapon_condition_met(weapon_id):
			if weapon_id in game_manager.unlocked_weapons:
				game_manager.unlocked_weapons[weapon_id] = true
				_log("Restored saved unlock for weapon: %s" % weapon_id)
		else:
			_log("Skipped restore for weapon '%s' (condition not met — treating as corrupt save)" % weapon_id)

	for grenade_type in grenades:
		if grenade_manager and is_grenade_condition_met(grenade_type):
			if grenade_type in grenade_manager.unlocked_grenades:
				grenade_manager.unlocked_grenades[grenade_type] = true
				_log("Restored saved unlock for grenade type: %d" % grenade_type)
		else:
			_log("Skipped restore for grenade type %d (condition not met — treating as corrupt save)" % grenade_type)

	for item_type in active_items:
		if active_item_manager and is_active_item_condition_met(item_type):
			if item_type in active_item_manager.unlocked_active_items:
				active_item_manager.unlocked_active_items[item_type] = true
				_log("Restored saved unlock for active item type: %d" % item_type)
		else:
			_log("Skipped restore for active item type %d (condition not met — treating as corrupt save)" % item_type)


## Return a human-readable description of the unlock condition for a weapon.
## Used by the armory tooltip to show locked-item unlock requirements.
## @param weapon_id: The weapon ID to look up.
## @return: A string describing how to unlock this weapon, or "" if not found.
func get_weapon_unlock_description(weapon_id: String) -> String:
	for condition_key in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		if weapon_id in condition.get("weapons", []):
			return _build_single_level_description(condition_key, condition)
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		if weapon_id in multi_condition.get("weapons", []):
			return _build_multi_level_description(multi_condition)
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if weapon_id in kill_condition.get("weapons", []):
			return _build_kill_condition_description(kill_condition)
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		if weapon_id in all_diff_condition.get("weapons", []):
			return "Complete at least one level on every difficulty"
	return ""


## Return a human-readable description of the unlock condition for a grenade type.
## @param grenade_type: The grenade type int to look up.
## @return: A string describing how to unlock this grenade, or "" if not found.
func get_grenade_unlock_description(grenade_type: int) -> String:
	for condition_key in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		if grenade_type in condition.get("grenades", []):
			return _build_single_level_description(condition_key, condition)
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		if grenade_type in multi_condition.get("grenades", []):
			return _build_multi_level_description(multi_condition)
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if grenade_type in kill_condition.get("grenades", []):
			return _build_kill_condition_description(kill_condition)
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		if grenade_type in all_diff_condition.get("grenades", []):
			return "Complete at least one level on every difficulty"
	return ""


## Return a human-readable description of the unlock condition for an active item type.
## @param item_type: The active item type int to look up.
## @return: A string describing how to unlock this item, or "" if not found.
func get_active_item_unlock_description(item_type: int) -> String:
	for condition_key in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		if item_type in condition.get("active_items", []):
			return _build_single_level_description(condition_key, condition)
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		if item_type in multi_condition.get("active_items", []):
			return _build_multi_level_description(multi_condition)
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if item_type in kill_condition.get("active_items", []):
			return _build_kill_condition_description(kill_condition)
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		if item_type in all_diff_condition.get("active_items", []):
			return "Complete at least one level on every difficulty"
	return ""


## Level scene path to display name mapping (mirrors UnlockTableMenu.LEVEL_NAMES).
const _LEVEL_NAMES: Dictionary = {
	"res://scenes/levels/LabyrinthLevel.tscn": "Labyrinth",
	"res://scenes/levels/BuildingLevel.tscn": "Building",
	"res://scenes/levels/TestTier.tscn": "Polygon",
	"res://scenes/levels/CastleLevel.tscn": "Castle",
	"res://scenes/levels/RevolverLevel.tscn": "Double Corridor",
	"res://scenes/levels/BeachLevel.tscn": "Beach",
	"res://scenes/levels/DocksLevel.tscn": "Docks",
	"res://scenes/levels/CityLevel.tscn": "City",
	"res://scenes/levels/FactoryLevel.tscn": "Factory",
	"res://scenes/levels/DecadenceLevel.tscn": "Decadence",
	"res://scenes/levels/Labyrinth2Level.tscn": "Labyrinth Complex",
	"res://scenes/levels/SewerLevel.tscn": "Sewer",
	"res://scenes/levels/RailwayStationLevel.tscn": "Railway Station",
	"res://scenes/levels/WinterForestLevel.tscn": "Winter Forest"
}


## Build a description string for a single-level UNLOCK_CONDITIONS entry.
func _build_single_level_description(condition_key: String, condition: Dictionary) -> String:
	var scene_path: String = _extract_scene_path(condition_key)
	var level_name: String = _LEVEL_NAMES.get(scene_path, scene_path.get_file().get_basename())
	var min_rank: String = condition.get("min_rank", "D")
	if min_rank == "F":
		return "Complete %s" % level_name
	return "Complete %s at rank %s or higher" % [level_name, min_rank]


## Build a description string for a MULTI_UNLOCK_CONDITIONS entry.
func _build_multi_level_description(multi_condition: Dictionary) -> String:
	var parts: Array[String] = []
	for level_entry in multi_condition.get("levels", []):
		var path: String = level_entry.get("path", "")
		var min_rank: String = level_entry.get("min_rank", "S")
		var level_name: String = _LEVEL_NAMES.get(path, path.get_file().get_basename())
		parts.append("%s %s" % [level_name, min_rank])
	return "Complete: " + " + ".join(parts)


## Build a description string for a KILL_UNLOCK_CONDITIONS entry.
func _build_kill_condition_description(kill_condition: Dictionary) -> String:
	var stat: String = kill_condition.get("stat", "")
	var min_kills: int = kill_condition.get("min_kills", 0)
	if stat == "shots_fired_special_weapons":
		return "Fire %d shots with shotgun, ASVK, or revolver" % min_kills
	if stat == "total_deaths":
		return "Die %d times" % min_kills
	if stat == "no_damage_levels_completed":
		return "Complete %d level(s) without taking damage" % min_kills
	if stat == "levels_completed_rank_a_or_higher":
		return "Complete %d level(s) at rank A or higher" % min_kills
	if stat == "kills_through_wall":
		return "Get %d kills through walls" % min_kills
	if stat == "levels_completed_with_silenced_pistol":
		return "Complete any level with the silenced pistol"
	return "Get %d kills without Laser Sight" % min_kills


## Get the kill-based unlock condition progress for a weapon (0.0–1.0).
## Returns -1.0 if no kill-based condition applies (e.g., level-based unlock).
## Returns a value in [0.0, 1.0] clamped to the condition's min_kills threshold.
## Issue #1591: used by the armory to show progress bar animation.
func get_weapon_kill_condition_progress(weapon_id: String) -> float:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if weapon_id in kill_condition.get("weapons", []):
			var game_manager: Node = get_node_or_null("/root/GameManager")
			if not game_manager:
				return 0.0
			var stat: String = kill_condition.get("stat", "")
			var min_kills: int = kill_condition.get("min_kills", 1)
			var current: int = game_manager.get(stat) if game_manager.get(stat) != null else 0
			return clampf(float(current) / float(min_kills), 0.0, 1.0)
	return -1.0


## Get the kill-based unlock condition progress for a grenade type (0.0–1.0).
## Returns -1.0 if no kill-based condition applies.
## Issue #1591: used by the armory to show progress bar animation.
func get_grenade_kill_condition_progress(grenade_type: int) -> float:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if grenade_type in kill_condition.get("grenades", []):
			var game_manager: Node = get_node_or_null("/root/GameManager")
			if not game_manager:
				return 0.0
			var stat: String = kill_condition.get("stat", "")
			var min_kills: int = kill_condition.get("min_kills", 1)
			var current: int = game_manager.get(stat) if game_manager.get(stat) != null else 0
			return clampf(float(current) / float(min_kills), 0.0, 1.0)
	return -1.0


## Get the kill-based unlock condition progress for an active item type (0.0–1.0).
## Returns -1.0 if no kill-based condition applies.
## Issue #1591: used by the armory to show progress bar animation.
func get_active_item_kill_condition_progress(item_type: int) -> float:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if item_type in kill_condition.get("active_items", []):
			var game_manager: Node = get_node_or_null("/root/GameManager")
			if not game_manager:
				return 0.0
			var stat: String = kill_condition.get("stat", "")
			var min_kills: int = kill_condition.get("min_kills", 1)
			var current: int = game_manager.get(stat) if game_manager.get(stat) != null else 0
			return clampf(float(current) / float(min_kills), 0.0, 1.0)
	return -1.0


## Get the kill-based unlock condition current and max counts for a weapon.
## Returns {"current": int, "max": int} if a kill condition applies, or {} otherwise.
## Issue #1591: used by the armory tooltip to show progress numbers.
func get_weapon_kill_condition_counts(weapon_id: String) -> Dictionary:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if weapon_id in kill_condition.get("weapons", []):
			var game_manager: Node = get_node_or_null("/root/GameManager")
			if not game_manager:
				return {}
			var stat: String = kill_condition.get("stat", "")
			var min_kills: int = kill_condition.get("min_kills", 1)
			var current: int = game_manager.get(stat) if game_manager.get(stat) != null else 0
			return {"current": mini(current, min_kills), "max": min_kills}
	return {}


## Get the kill-based unlock condition current and max counts for a grenade type.
## Returns {"current": int, "max": int} if a kill condition applies, or {} otherwise.
## Issue #1591: used by the armory tooltip to show progress numbers.
func get_grenade_kill_condition_counts(grenade_type: int) -> Dictionary:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if grenade_type in kill_condition.get("grenades", []):
			var game_manager: Node = get_node_or_null("/root/GameManager")
			if not game_manager:
				return {}
			var stat: String = kill_condition.get("stat", "")
			var min_kills: int = kill_condition.get("min_kills", 1)
			var current: int = game_manager.get(stat) if game_manager.get(stat) != null else 0
			return {"current": mini(current, min_kills), "max": min_kills}
	return {}


## Get the kill-based unlock condition current and max counts for an active item type.
## Returns {"current": int, "max": int} if a kill condition applies, or {} otherwise.
## Issue #1591: used by the armory tooltip to show progress numbers.
func get_active_item_kill_condition_counts(item_type: int) -> Dictionary:
	for kill_condition in KILL_UNLOCK_CONDITIONS:
		if item_type in kill_condition.get("active_items", []):
			var game_manager: Node = get_node_or_null("/root/GameManager")
			if not game_manager:
				return {}
			var stat: String = kill_condition.get("stat", "")
			var min_kills: int = kill_condition.get("min_kills", 1)
			var current: int = game_manager.get(stat) if game_manager.get(stat) != null else 0
			return {"current": mini(current, min_kills), "max": min_kills}
	return {}


## Get the fraction of levels satisfied in a multi-level condition (0.0–1.0).
## Internal helper for get_*_multi_condition_progress.
## Issue #1591: used by armory to show progress bar for multi-level conditions.
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


## Get the fraction of difficulties on which at least one level has been completed (0.0–1.0).
## Internal helper for get_*_all_difficulties_progress.
## Issue #1591: used by armory to show progress bar for all-difficulties conditions.
func _get_all_difficulties_progress() -> float:
	var progress_manager: Node = get_node_or_null("/root/ProgressManager")
	if not progress_manager:
		return 0.0
	var all_difficulties: Array[String] = _get_all_difficulty_names()
	var total: int = all_difficulties.size()
	if total == 0:
		return 0.0
	var completed: int = 0
	for difficulty_name in all_difficulties:
		for key in progress_manager.get_all_progress():
			if key.ends_with(":" + difficulty_name):
				completed += 1
				break
	return float(completed) / float(total)


## Get the multi-level condition progress for a weapon (0.0–1.0).
## Returns -1.0 if no multi-level condition applies.
## Issue #1591: used by armory to show progress bar animation.
func get_weapon_multi_condition_progress(weapon_id: String) -> float:
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		if weapon_id in multi_condition.get("weapons", []):
			return _get_multi_condition_progress(multi_condition)
	return -1.0


## Get the multi-level condition progress for a grenade type (0.0–1.0).
## Returns -1.0 if no multi-level condition applies.
## Issue #1591: used by armory to show progress bar animation.
func get_grenade_multi_condition_progress(grenade_type: int) -> float:
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		if grenade_type in multi_condition.get("grenades", []):
			return _get_multi_condition_progress(multi_condition)
	return -1.0


## Get the multi-level condition progress for an active item type (0.0–1.0).
## Returns -1.0 if no multi-level condition applies.
## Issue #1591: used by armory to show progress bar animation.
func get_active_item_multi_condition_progress(item_type: int) -> float:
	for multi_condition in MULTI_UNLOCK_CONDITIONS:
		if item_type in multi_condition.get("active_items", []):
			return _get_multi_condition_progress(multi_condition)
	return -1.0


## Get the all-difficulties condition progress for a weapon (0.0–1.0).
## Returns -1.0 if no all-difficulties condition applies.
## Issue #1591: used by armory to show progress bar animation.
func get_weapon_all_difficulties_progress(weapon_id: String) -> float:
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		if weapon_id in all_diff_condition.get("weapons", []):
			return _get_all_difficulties_progress()
	return -1.0


## Get the all-difficulties condition progress for a grenade type (0.0–1.0).
## Returns -1.0 if no all-difficulties condition applies.
## Issue #1591: used by armory to show progress bar animation.
func get_grenade_all_difficulties_progress(grenade_type: int) -> float:
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		if grenade_type in all_diff_condition.get("grenades", []):
			return _get_all_difficulties_progress()
	return -1.0


## Get the all-difficulties condition progress for an active item type (0.0–1.0).
## Returns -1.0 if no all-difficulties condition applies.
## Issue #1591: used by armory to show progress bar animation.
func get_active_item_all_difficulties_progress(item_type: int) -> float:
	for all_diff_condition in ALL_DIFFICULTIES_UNLOCK_CONDITIONS:
		if item_type in all_diff_condition.get("active_items", []):
			return _get_all_difficulties_progress()
	return -1.0


## Get the single-level condition progress for a weapon (0.0 or 1.0, binary).
## Returns -1.0 if no single-level condition applies.
## Issue #1591: used by armory to show progress bar animation.
func get_weapon_single_condition_progress(weapon_id: String) -> float:
	for condition_key in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		if weapon_id in condition.get("weapons", []):
			return 1.0 if is_condition_key_met(condition_key) else 0.0
	return -1.0


## Get the single-level condition progress for a grenade type (0.0 or 1.0, binary).
## Returns -1.0 if no single-level condition applies.
## Issue #1591: used by armory to show progress bar animation.
func get_grenade_single_condition_progress(grenade_type: int) -> float:
	for condition_key in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		if grenade_type in condition.get("grenades", []):
			return 1.0 if is_condition_key_met(condition_key) else 0.0
	return -1.0


## Get the single-level condition progress for an active item type (0.0 or 1.0, binary).
## Returns -1.0 if no single-level condition applies.
## Issue #1591: used by armory to show progress bar animation.
func get_active_item_single_condition_progress(item_type: int) -> float:
	for condition_key in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[condition_key]
		if item_type in condition.get("active_items", []):
			return 1.0 if is_condition_key_met(condition_key) else 0.0
	return -1.0


## Get the best unlock condition progress for a weapon across all condition types (0.0–1.0).
## Returns -1.0 if this weapon has no quantifiable unlock condition at all.
## Issue #1591: unified function used by armory to show progress bar animation for all types.
func get_weapon_unlock_progress(weapon_id: String) -> float:
	var best: float = -1.0
	var p: float
	p = get_weapon_kill_condition_progress(weapon_id)
	if p >= 0.0:
		best = maxf(best, p)
	p = get_weapon_multi_condition_progress(weapon_id)
	if p >= 0.0:
		best = maxf(best, p)
	p = get_weapon_all_difficulties_progress(weapon_id)
	if p >= 0.0:
		best = maxf(best, p)
	p = get_weapon_single_condition_progress(weapon_id)
	if p >= 0.0:
		best = maxf(best, p)
	return best


## Get the best unlock condition progress for a grenade across all condition types (0.0–1.0).
## Returns -1.0 if this grenade has no quantifiable unlock condition at all.
## Issue #1591: unified function used by armory to show progress bar animation for all types.
func get_grenade_unlock_progress(grenade_type: int) -> float:
	var best: float = -1.0
	var p: float
	p = get_grenade_kill_condition_progress(grenade_type)
	if p >= 0.0:
		best = maxf(best, p)
	p = get_grenade_multi_condition_progress(grenade_type)
	if p >= 0.0:
		best = maxf(best, p)
	p = get_grenade_all_difficulties_progress(grenade_type)
	if p >= 0.0:
		best = maxf(best, p)
	p = get_grenade_single_condition_progress(grenade_type)
	if p >= 0.0:
		best = maxf(best, p)
	return best


## Get the best unlock condition progress for an active item across all condition types (0.0–1.0).
## Returns -1.0 if this item has no quantifiable unlock condition at all.
## Issue #1591: unified function used by armory to show progress bar animation for all types.
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


## Get all available difficulty names from DifficultyManager (with static fallback).
## Uses DifficultyManager as the single source of truth so new difficulties are
## automatically picked up without needing to update this file.
func _get_all_difficulty_names() -> Array[String]:
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.has_method("get_all_difficulty_names"):
		return difficulty_manager.get_all_difficulty_names()
	# Static fallback — must stay in sync with DifficultyManager.Difficulty enum.
	return ["Easy", "Normal", "Hard", "Power Fantasy", "Black Metal"]


## Log a message to the file logger if available.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[UnlockManager] " + message)
	else:
		print("[UnlockManager] " + message)
