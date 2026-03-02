extends Node
## Autoload singleton for managing condition-based item unlocks.
##
## Tracks which items can be unlocked by completing certain levels at certain grades.
## When a level is completed with a qualifying grade, the corresponding items are
## automatically unlocked and saved.
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
		"active_items": [1]  # ActiveItemManager.ActiveItemType.FLASHLIGHT = 1
	},
	"res://scenes/levels/CastleLevel.tscn": {
		"min_rank": "F",
		"weapons": ["revolver"],
		"grenades": [],
		"active_items": [3]  # ActiveItemManager.ActiveItemType.TELEPORT_BRACERS = 3
	}
}

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
## Checks if any unlock conditions are now satisfied and unlocks items.
func _on_progress_updated(level_path: String, difficulty_name: String) -> void:
	_check_and_apply_unlocks(level_path)


## Check unlock conditions for a given level path and apply any earned unlocks.
## @param level_path: The scene file path of the completed level.
func _check_and_apply_unlocks(level_path: String) -> void:
	if level_path not in UNLOCK_CONDITIONS:
		return

	var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
	var min_rank: String = condition.get("min_rank", "D")

	# Get the best rank achieved on this level across all difficulties
	var best_rank: String = _get_best_rank_any_difficulty(level_path)
	if best_rank.is_empty():
		return

	# Check if the best rank meets the minimum requirement
	if not _is_rank_sufficient(best_rank, min_rank):
		return

	# Apply all unlocks for this condition
	var any_unlocked: bool = false

	for weapon_id in condition.get("weapons", []):
		if _unlock_weapon(weapon_id):
			any_unlocked = true

	for grenade_type in condition.get("grenades", []):
		if _unlock_grenade(grenade_type):
			any_unlocked = true

	for item_type in condition.get("active_items", []):
		if _unlock_active_item(item_type):
			any_unlocked = true

	if any_unlocked:
		items_unlocked_by_condition.emit(level_path)
		_log("Unlocked items for level: %s (rank: %s)" % [level_path, best_rank])


## Get the best rank for a level across all difficulties.
## @param level_path: The scene file path of the level.
## @return: The best rank string, or "" if never completed.
func _get_best_rank_any_difficulty(level_path: String) -> String:
	var progress_manager: Node = get_node_or_null("/root/ProgressManager")
	if not progress_manager:
		return ""

	var best_rank: String = ""
	var difficulties: Array[String] = ["Easy", "Normal", "Hard", "Power Fantasy"]
	for difficulty_name in difficulties:
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


## Unlock a weapon by ID.
## @return: true if the weapon was newly unlocked.
func _unlock_weapon(weapon_id: String) -> bool:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if not game_manager:
		return false
	if game_manager.is_weapon_unlocked(weapon_id):
		return false  # Already unlocked
	game_manager.unlock_weapon(weapon_id)
	_log("Weapon unlocked: %s" % weapon_id)
	return true


## Unlock a grenade by type.
## @return: true if the grenade was newly unlocked.
func _unlock_grenade(grenade_type: int) -> bool:
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	if not grenade_manager:
		return false
	if grenade_manager.is_grenade_unlocked(grenade_type):
		return false  # Already unlocked
	grenade_manager.unlock_grenade(grenade_type)
	_log("Grenade unlocked: type %d" % grenade_type)
	return true


## Unlock an active item by type.
## @return: true if the item was newly unlocked.
func _unlock_active_item(item_type: int) -> bool:
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if not active_item_manager:
		return false
	if active_item_manager.is_active_item_unlocked(item_type):
		return false  # Already unlocked
	active_item_manager.unlock_active_item(item_type)
	_log("Active item unlocked: type %d" % item_type)
	return true


## Check if a specific level's unlock condition is currently met (for UI highlighting).
## @param level_path: The scene file path of the level.
## @return: true if the condition has been met (item can be unlocked).
func is_level_condition_met(level_path: String) -> bool:
	if level_path not in UNLOCK_CONDITIONS:
		return false
	var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
	var min_rank: String = condition.get("min_rank", "D")
	var best_rank: String = _get_best_rank_any_difficulty(level_path)
	return _is_rank_sufficient(best_rank, min_rank)


## Get all weapon IDs that are unlockable via level conditions (have a condition defined).
## @return: Array of weapon IDs that have unlock conditions.
func get_weapons_with_conditions() -> Array[String]:
	var result: Array[String] = []
	for level_path in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
		for weapon_id in condition.get("weapons", []):
			if weapon_id not in result:
				result.append(weapon_id)
	return result


## Get all active item types that are unlockable via level conditions.
## @return: Array of active item type ints that have unlock conditions.
func get_active_items_with_conditions() -> Array[int]:
	var result: Array[int] = []
	for level_path in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
		for item_type in condition.get("active_items", []):
			if item_type not in result:
				result.append(item_type)
	return result


## Get all grenade types that are unlockable via level conditions.
## @return: Array of grenade type ints that have unlock conditions.
func get_grenades_with_conditions() -> Array[int]:
	var result: Array[int] = []
	for level_path in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
		for grenade_type in condition.get("grenades", []):
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
	for level_path in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
		if weapon_id in condition.get("weapons", []):
			if is_level_condition_met(level_path):
				return true
	return false


## Check if an active item's unlock condition is currently met (for gold highlighting in armory).
## @param item_type: The active item type to check.
## @return: true if any level condition that unlocks this item is met.
func is_active_item_condition_met(item_type: int) -> bool:
	for level_path in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
		if item_type in condition.get("active_items", []):
			if is_level_condition_met(level_path):
				return true
	return false


## Check if a grenade's unlock condition is currently met (for gold highlighting in armory).
## @param grenade_type: The grenade type to check.
## @return: true if any level condition that unlocks this grenade is met.
func is_grenade_condition_met(grenade_type: int) -> bool:
	for level_path in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[level_path]
		if grenade_type in condition.get("grenades", []):
			if is_level_condition_met(level_path):
				return true
	return false


## Reset all condition-gated items to locked state.
## This undoes any incorrect unlock state that may have been loaded from an old save file,
## ensuring only legitimately earned items remain unlocked (via apply_all_earned_unlocks).
func _reset_condition_gated_items() -> void:
	var game_manager: Node = get_node_or_null("/root/GameManager")
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")

	for level_path in UNLOCK_CONDITIONS:
		var condition: Dictionary = UNLOCK_CONDITIONS[level_path]

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

	_log("Reset condition-gated items to locked state")


## Reset condition-gated items to locked, then re-apply all earned unlocks from progress.
## Called deferred at startup to validate that saved unlock states match actual progress.
func _reset_and_apply_all_unlocks() -> void:
	_reset_condition_gated_items()
	apply_all_earned_unlocks()


## Re-check and apply all unlock conditions based on current progress.
## Call this on startup to ensure all earned unlocks are applied.
func apply_all_earned_unlocks() -> void:
	for level_path in UNLOCK_CONDITIONS:
		_check_and_apply_unlocks(level_path)
	_log("Applied all earned unlocks from progress")


## Log a message to the file logger if available.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[UnlockManager] " + message)
	else:
		print("[UnlockManager] " + message)
