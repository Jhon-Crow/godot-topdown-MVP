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
	"res://scenes/levels/BeachLevel.tscn": {
		"min_rank": "D",
		"weapons": ["ak_gl"],  # Issue #1000 req.4
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
		"grenades": [],
		"active_items": []
	}
}

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


func _ready() -> void:
	# Connect to ProgressManager to check conditions whenever progress is updated
	var progress_manager: Node = get_node_or_null("/root/ProgressManager")
	if progress_manager and progress_manager.has_signal("progress_updated"):
		progress_manager.progress_updated.connect(_on_progress_updated)
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
	return result


## Check if a weapon's unlock condition is currently met (for gold highlighting in armory).
## Returns true if the player has earned the right to unlock this weapon
## (condition met), but the weapon may or may not have been unlocked yet
## (use GameManager.is_weapon_unlocked for that).
## @param weapon_id: The weapon ID to check.
## @return: true if any level condition that unlocks this weapon is met.
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


## Check if an active item's unlock condition is currently met (for gold highlighting in armory).
## @param item_type: The active item type to check.
## @return: true if any level condition that unlocks this item is met.
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


## Check if a grenade's unlock condition is currently met (for gold highlighting in armory).
## @param grenade_type: The grenade type to check.
## @return: true if any level condition that unlocks this grenade is met.
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

	_log("Reset condition-gated items to locked state")


## Reset condition-gated items to locked state on startup.
## This removes any incorrectly-saved unlock states (e.g. from old buggy save files).
## Items whose conditions are met will be highlighted in gold in the armory;
## the player must still hold LMB on the gold slot to permanently unlock them.
func _reset_and_apply_all_unlocks() -> void:
	_reset_condition_gated_items()


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
