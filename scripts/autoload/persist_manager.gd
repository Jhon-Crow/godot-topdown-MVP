extends Node
## PersistManager - Saves and restores player's game state between sessions.
##
## Persists: last selected level, selected weapon, selected grenade,
## selected active item, and which items have been unlocked.
## Uses ConfigFile (same pattern as DifficultyManager / ExperimentalSettings).
##
## Save file: user://game_state.cfg
## Must be loaded AFTER GameManager, GrenadeManager, and ActiveItemManager.
## Issue #896: добавь persist (add persistence)

## Save file path.
const SAVE_PATH := "user://game_state.cfg"

## Section names.
const SECTION_GAME := "game"
const SECTION_UNLOCKED_WEAPONS := "unlocked_weapons"
const SECTION_GRENADE := "grenade"
const SECTION_UNLOCKED_GRENADES := "unlocked_grenades"
const SECTION_ACTIVE_ITEM := "active_item"
const SECTION_UNLOCKED_ACTIVE_ITEMS := "unlocked_active_items"
const SECTION_LOUDSPEAKER := "loudspeaker_progress"  # Issue #959
const SECTION_KILL_STATS := "kill_stats"  # Issue #1196

## Key names.
const KEY_SELECTED_WEAPON := "selected_weapon"
const KEY_LAST_LEVEL := "last_level"
const KEY_CURRENT_GRENADE_TYPE := "current_type"
const KEY_CURRENT_ACTIVE_ITEM := "current_type"
const KEY_KILLS_WITHOUT_LASER_SIGHT := "kills_without_laser_sight"  # Issue #1196
const KEY_SHOTS_FIRED_SPECIAL_WEAPONS := "shots_fired_special_weapons"  # Issue #1346

## Default level to load when no saved state exists.
const DEFAULT_LEVEL := "res://scenes/levels/LabyrinthLevel.tscn"

## Signal emitted when state is saved.
signal state_saved

## Signal emitted when state is loaded.
signal state_loaded


func _ready() -> void:
	_load_state()
	_connect_signals()
	# Deferred so the main scene is fully ready before we potentially change it
	call_deferred("_navigate_to_last_level")
	_log_to_file("PersistManager ready")


## Navigate to the last played level if saved state exists.
## Called deferred so the default main scene finishes loading first.
func _navigate_to_last_level() -> void:
	if not has_saved_state():
		_log_to_file("No saved level — starting at default level")
		return

	var last_level := get_last_level()
	var current_scene: Node = get_tree().current_scene
	var current_path: String = ""
	if current_scene and current_scene.scene_file_path:
		current_path = current_scene.scene_file_path

	# Only navigate if the last level is different from current
	if last_level != current_path and last_level != "" and ResourceLoader.exists(last_level):
		_log_to_file("Navigating to last played level: %s" % last_level)
		# Issue #997: Use SceneLoader for background loading with loading screen
		var scene_loader: Node = get_node_or_null("/root/SceneLoader")
		if scene_loader and scene_loader.has_method("load_level"):
			scene_loader.load_level(last_level)
		else:
			get_tree().change_scene_to_file(last_level)
	else:
		_log_to_file("Already at last played level: %s" % current_path)


## Connect to manager signals to auto-save on changes.
func _connect_signals() -> void:
	# GameManager signals
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		if game_manager.has_signal("weapon_selected"):
			game_manager.weapon_selected.connect(_on_weapon_selected)
		if game_manager.has_signal("weapon_unlocked"):
			game_manager.weapon_unlocked.connect(_on_weapon_unlocked)
		if game_manager.has_signal("kills_without_laser_sight_updated"):
			game_manager.kills_without_laser_sight_updated.connect(_on_kills_without_laser_sight_updated)
		if game_manager.has_signal("shots_fired_special_weapons_updated"):
			game_manager.shots_fired_special_weapons_updated.connect(_on_shots_fired_special_weapons_updated)

	# GrenadeManager signals
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	if grenade_manager:
		if grenade_manager.has_signal("grenade_type_changed"):
			grenade_manager.grenade_type_changed.connect(_on_grenade_type_changed)
		if grenade_manager.has_signal("grenade_unlocked"):
			grenade_manager.grenade_unlocked.connect(_on_grenade_unlocked)

	# ActiveItemManager signals
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager:
		if active_item_manager.has_signal("active_item_changed"):
			active_item_manager.active_item_changed.connect(_on_active_item_changed)
		if active_item_manager.has_signal("active_item_unlocked"):
			active_item_manager.active_item_unlocked.connect(_on_active_item_unlocked)


## Save the last selected level path.
## Called from LevelsMenu when a level is chosen.
## @param level_path: The scene file path of the selected level.
func save_last_level(level_path: String) -> void:
	_save_state_with_level(level_path)
	_log_to_file("Last level saved: %s" % level_path)


## Get the saved last level path, or the default if none saved.
## @return: Scene file path of the last played level.
func get_last_level() -> String:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		return config.get_value(SECTION_GAME, KEY_LAST_LEVEL, DEFAULT_LEVEL)
	return DEFAULT_LEVEL


## Check whether a saved game state exists.
## @return: true if a save file with a last_level entry exists.
func has_saved_state() -> bool:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return false
	return config.has_section_key(SECTION_GAME, KEY_LAST_LEVEL)


# ============================================================================
# Signal Handlers — auto-save on any state change
# ============================================================================

func _on_weapon_selected(_weapon_id: String) -> void:
	_save_state()


func _on_weapon_unlocked(_weapon_id: String) -> void:
	_save_state()


func _on_grenade_type_changed(_new_type: int) -> void:
	_save_state()


func _on_grenade_unlocked(_grenade_type: int) -> void:
	_save_state()


func _on_active_item_changed(_new_type: int) -> void:
	_save_state()


func _on_active_item_unlocked(_item_type: int) -> void:
	_save_state()


func _on_kills_without_laser_sight_updated(_new_count: int) -> void:
	_save_state()


func _on_shots_fired_special_weapons_updated(_new_count: int) -> void:
	_save_state()


# ============================================================================
# Save / Load
# ============================================================================

## Save all relevant game state to file, keeping the existing last_level.
func _save_state() -> void:
	# Preserve existing last_level from the save file
	var existing_config := ConfigFile.new()
	var existing_last_level: String = DEFAULT_LEVEL
	if existing_config.load(SAVE_PATH) == OK:
		existing_last_level = existing_config.get_value(SECTION_GAME, KEY_LAST_LEVEL, DEFAULT_LEVEL)

	_save_state_with_level(existing_last_level)


## Save all relevant game state to file with a specific level path.
## @param level_path: The level path to record as the last played level.
func _save_state_with_level(level_path: String) -> void:
	var config := ConfigFile.new()

	config.set_value(SECTION_GAME, KEY_LAST_LEVEL, level_path)

	# Save selected weapon and kill stats
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("get_selected_weapon"):
		config.set_value(SECTION_GAME, KEY_SELECTED_WEAPON, game_manager.get_selected_weapon())

		# Save unlocked weapons
		if game_manager.has_method("get_unlocked_weapons"):
			var unlocked: Dictionary = game_manager.get_unlocked_weapons()
			for weapon_id in unlocked:
				config.set_value(SECTION_UNLOCKED_WEAPONS, weapon_id, unlocked[weapon_id])

		# Save kill stats (Issue #1196)
		config.set_value(SECTION_KILL_STATS, KEY_KILLS_WITHOUT_LASER_SIGHT,
				game_manager.get("kills_without_laser_sight") if game_manager.get("kills_without_laser_sight") != null else 0)
		# Save shot stats (Issue #1346)
		config.set_value(SECTION_KILL_STATS, KEY_SHOTS_FIRED_SPECIAL_WEAPONS,
				game_manager.get("shots_fired_special_weapons") if game_manager.get("shots_fired_special_weapons") != null else 0)

	# Save selected grenade type
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	if grenade_manager:
		config.set_value(SECTION_GRENADE, KEY_CURRENT_GRENADE_TYPE, grenade_manager.current_grenade_type)

		# Save unlocked grenades
		if grenade_manager.has_method("get_unlocked_grenades"):
			var unlocked_grenades: Dictionary = grenade_manager.get_unlocked_grenades()
			for grenade_type in unlocked_grenades:
				config.set_value(SECTION_UNLOCKED_GRENADES, str(grenade_type), unlocked_grenades[grenade_type])

	# Save selected active item type
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager:
		config.set_value(SECTION_ACTIVE_ITEM, KEY_CURRENT_ACTIVE_ITEM, active_item_manager.current_active_item)

		# Save unlocked active items
		if active_item_manager.has_method("get_unlocked_active_items"):
			var unlocked_items: Dictionary = active_item_manager.get_unlocked_active_items()
			for item_type in unlocked_items:
				config.set_value(SECTION_UNLOCKED_ACTIVE_ITEMS, str(item_type), unlocked_items[item_type])

		# Save loudspeaker progress (Issue #959)
		if active_item_manager.get("loudspeaker_progress") != null:
			var lp: LoudspeakerProgress = active_item_manager.loudspeaker_progress
			var lp_data: Dictionary = lp.to_dict()
			for key in lp_data:
				config.set_value(SECTION_LOUDSPEAKER, key, lp_data[key])

	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("PersistManager: Failed to save state: " + str(error))
	else:
		state_saved.emit()
		_log_to_file("State saved to %s" % SAVE_PATH)


## Load all game state from file and apply to managers.
func _load_state() -> void:
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)
	if error != OK:
		_log_to_file("No saved state found (this is normal on first run)")
		return

	_log_to_file("Loading saved state from %s" % SAVE_PATH)

	# Restore selected weapon and unlocked weapons
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		# Restore unlocked weapons first (so selected weapon can be valid)
		if config.has_section(SECTION_UNLOCKED_WEAPONS):
			for weapon_id in config.get_section_keys(SECTION_UNLOCKED_WEAPONS):
				var is_unlocked: bool = config.get_value(SECTION_UNLOCKED_WEAPONS, weapon_id, false)
				if is_unlocked and weapon_id in game_manager.unlocked_weapons:
					game_manager.unlocked_weapons[weapon_id] = true
					_log_to_file("Restored unlocked weapon: %s" % weapon_id)

		# Restore kill stats (Issue #1196)
		if config.has_section_key(SECTION_KILL_STATS, KEY_KILLS_WITHOUT_LASER_SIGHT):
			var saved_kills: int = config.get_value(SECTION_KILL_STATS, KEY_KILLS_WITHOUT_LASER_SIGHT, 0)
			game_manager.kills_without_laser_sight = saved_kills
			_log_to_file("Restored kills_without_laser_sight: %d" % saved_kills)
		# Restore shot stats (Issue #1346)
		if config.has_section_key(SECTION_KILL_STATS, KEY_SHOTS_FIRED_SPECIAL_WEAPONS):
			var saved_shots: int = config.get_value(SECTION_KILL_STATS, KEY_SHOTS_FIRED_SPECIAL_WEAPONS, 0)
			game_manager.shots_fired_special_weapons = saved_shots
			_log_to_file("Restored shots_fired_special_weapons: %d" % saved_shots)

		# Restore selected weapon
		if config.has_section_key(SECTION_GAME, KEY_SELECTED_WEAPON):
			var saved_weapon: String = config.get_value(SECTION_GAME, KEY_SELECTED_WEAPON, "makarov_pm")
			if game_manager.has_method("set_selected_weapon"):
				# Only restore if weapon is unlocked
				if game_manager.is_weapon_unlocked(saved_weapon):
					game_manager.set_selected_weapon(saved_weapon)
					_log_to_file("Restored selected weapon: %s" % saved_weapon)
				else:
					_log_to_file("Saved weapon '%s' is not unlocked, keeping default" % saved_weapon)

	# Restore grenade type and unlocked grenades
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	if grenade_manager:
		# Restore unlocked grenades first
		if config.has_section(SECTION_UNLOCKED_GRENADES):
			for key in config.get_section_keys(SECTION_UNLOCKED_GRENADES):
				var grenade_type: int = int(key)
				var is_unlocked: bool = config.get_value(SECTION_UNLOCKED_GRENADES, key, false)
				if is_unlocked and grenade_type in grenade_manager.unlocked_grenades:
					grenade_manager.unlocked_grenades[grenade_type] = true
					_log_to_file("Restored unlocked grenade type: %d" % grenade_type)

		# Restore selected grenade type (without restarting level)
		if config.has_section_key(SECTION_GRENADE, KEY_CURRENT_GRENADE_TYPE):
			var saved_grenade_type: int = config.get_value(SECTION_GRENADE, KEY_CURRENT_GRENADE_TYPE, 0)
			if grenade_manager.has_method("set_grenade_type"):
				# Only restore if grenade is unlocked
				if grenade_manager.is_grenade_unlocked(saved_grenade_type):
					grenade_manager.set_grenade_type(saved_grenade_type, false)
					_log_to_file("Restored selected grenade type: %d" % saved_grenade_type)
				else:
					_log_to_file("Saved grenade type %d is not unlocked, keeping default" % saved_grenade_type)

	# Restore active item type and unlocked active items
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager:
		# Restore unlocked active items first
		if config.has_section(SECTION_UNLOCKED_ACTIVE_ITEMS):
			for key in config.get_section_keys(SECTION_UNLOCKED_ACTIVE_ITEMS):
				var item_type: int = int(key)
				var is_unlocked: bool = config.get_value(SECTION_UNLOCKED_ACTIVE_ITEMS, key, false)
				if is_unlocked and item_type in active_item_manager.unlocked_active_items:
					active_item_manager.unlocked_active_items[item_type] = true
					_log_to_file("Restored unlocked active item type: %d" % item_type)

		# Restore selected active item (without restarting level)
		if config.has_section_key(SECTION_ACTIVE_ITEM, KEY_CURRENT_ACTIVE_ITEM):
			var saved_item_type: int = config.get_value(SECTION_ACTIVE_ITEM, KEY_CURRENT_ACTIVE_ITEM, 0)
			if active_item_manager.has_method("set_active_item"):
				# Only restore if item is unlocked
				if active_item_manager.is_active_item_unlocked(saved_item_type):
					active_item_manager.set_active_item(saved_item_type, false)
					_log_to_file("Restored selected active item type: %d" % saved_item_type)
				else:
					_log_to_file("Saved active item type %d is not unlocked, keeping default" % saved_item_type)

	# Restore loudspeaker progress (Issue #959)
	var active_item_manager_lp: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager_lp and active_item_manager_lp.get("loudspeaker_progress") != null:
		if config.has_section(SECTION_LOUDSPEAKER):
			var lp_data: Dictionary = {}
			for key in config.get_section_keys(SECTION_LOUDSPEAKER):
				lp_data[key] = config.get_value(SECTION_LOUDSPEAKER, key)
			active_item_manager_lp.loudspeaker_progress.from_dict(lp_data)
			_log_to_file("Loudspeaker progress restored: level %d, levels_completed=%d" % [
				active_item_manager_lp.loudspeaker_progress.current_level,
				active_item_manager_lp.loudspeaker_progress.levels_completed_with_loudspeaker
			])

	state_loaded.emit()
	_log_to_file("State loaded successfully")


## Clear all game saves and reset to first-launch state (Issue #938).
## Deletes the save file, resets weapon/grenade/active item state in managers,
## and clears all level progress.
## Note: ExperimentalSettings are intentionally NOT reset.
func clear_all_saves() -> void:
	# Delete the save file
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

	# Reset GameManager weapons and kill stats to defaults
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager:
		for weapon_id in game_manager.unlocked_weapons.keys():
			game_manager.unlocked_weapons[weapon_id] = weapon_id == "makarov_pm"
		game_manager.selected_weapon = "makarov_pm"
		game_manager.kills_without_laser_sight = 0  # Issue #1196
		game_manager.shots_fired_special_weapons = 0  # Issue #1346

	# Reset GrenadeManager to defaults
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	if grenade_manager:
		for grenade_type in grenade_manager.unlocked_grenades.keys():
			grenade_manager.unlocked_grenades[grenade_type] = grenade_type == grenade_manager.GrenadeType.FLASHBANG
		grenade_manager.current_grenade_type = grenade_manager.GrenadeType.FLASHBANG

	# Reset ActiveItemManager to defaults
	var active_item_manager: Node = get_node_or_null("/root/ActiveItemManager")
	if active_item_manager:
		for item_type in active_item_manager.unlocked_active_items.keys():
			active_item_manager.unlocked_active_items[item_type] = item_type == active_item_manager.ActiveItemType.NONE
		active_item_manager.current_active_item = active_item_manager.ActiveItemType.NONE
		# Reset loudspeaker progress (Issue #959)
		if active_item_manager.has_method("reset_loudspeaker_progress"):
			active_item_manager.reset_loudspeaker_progress()

	# Clear level progress
	var progress_manager: Node = get_node_or_null("/root/ProgressManager")
	if progress_manager and progress_manager.has_method("clear_all_progress"):
		progress_manager.clear_all_progress()

	_log_to_file("All saves cleared — game reset to first-launch state")


## Log a message to the file logger if available.
func _log_to_file(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info("[PersistManager] " + message)
	else:
		print("[PersistManager] " + message)
