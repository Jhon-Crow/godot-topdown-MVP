extends Node
## Autoload singleton for managing item unlock states in the armory.
##
## Tracks which weapons, grenades, and active items are unlocked.
## Persists unlock state to user://unlock_state.cfg.
## Provides API for checking/setting unlock state.
##
## By default (debug mode), only PM pistol and flashbang grenade are unlocked.
## Other items must be unlocked by holding LMB on their case icon.

## Signal emitted when an item is unlocked.
signal item_unlocked(item_type: String, item_id: String)

## Signal emitted when unlock progress changes (for UI feedback).
signal unlock_progress_changed(item_type: String, item_id: String, progress: float)

## Save file path for unlock state persistence.
const SAVE_PATH := "user://unlock_state.cfg"

## Section names in the config file.
const SECTION_WEAPONS := "weapons"
const SECTION_GRENADES := "grenades"
const SECTION_ACTIVE_ITEMS := "active_items"

## Time in seconds required to hold LMB to unlock an item.
const UNLOCK_HOLD_TIME := 1.5

## Default unlocked weapons (only PM pistol by default).
const DEFAULT_UNLOCKED_WEAPONS: Array[String] = ["makarov_pm"]

## Default unlocked grenade types (only flashbang by default).
## Uses GrenadeManager.GrenadeType values.
const DEFAULT_UNLOCKED_GRENADES: Array[int] = [0]  # GrenadeType.FLASHBANG = 0

## Default unlocked active item types.
## Uses ActiveItemManager.ActiveItemType values.
## NONE (0) is always unlocked since it means "no item equipped".
const DEFAULT_UNLOCKED_ACTIVE_ITEMS: Array[int] = [0]  # ActiveItemType.NONE = 0

## In-memory cache of unlocked items.
var _unlocked_weapons: Array[String] = []
var _unlocked_grenades: Array[int] = []
var _unlocked_active_items: Array[int] = []

## Whether unlock restrictions are enabled.
## Set to false to unlock everything (useful for development/testing).
var _restrictions_enabled: bool = true


func _ready() -> void:
	_load_unlock_state()
	_log("[UnlockManager] Ready, weapons: %d, grenades: %d, active_items: %d" % [
		_unlocked_weapons.size(),
		_unlocked_grenades.size(),
		_unlocked_active_items.size()
	])


## Check if a weapon is unlocked.
## @param weapon_id: The weapon identifier (e.g., "makarov_pm", "m16").
## @return: True if the weapon is unlocked.
func is_weapon_unlocked(weapon_id: String) -> bool:
	if not _restrictions_enabled:
		return true
	return weapon_id in _unlocked_weapons


## Check if a grenade type is unlocked.
## @param grenade_type: The grenade type (GrenadeType enum value).
## @return: True if the grenade is unlocked.
func is_grenade_unlocked(grenade_type: int) -> bool:
	if not _restrictions_enabled:
		return true
	return grenade_type in _unlocked_grenades


## Check if an active item type is unlocked.
## @param item_type: The active item type (ActiveItemType enum value).
## @return: True if the active item is unlocked.
func is_active_item_unlocked(item_type: int) -> bool:
	if not _restrictions_enabled:
		return true
	return item_type in _unlocked_active_items


## Unlock a weapon.
## @param weapon_id: The weapon identifier to unlock.
func unlock_weapon(weapon_id: String) -> void:
	if weapon_id in _unlocked_weapons:
		return  # Already unlocked

	_unlocked_weapons.append(weapon_id)
	_save_unlock_state()
	item_unlocked.emit("weapon", weapon_id)
	_log("[UnlockManager] Weapon unlocked: %s" % weapon_id)


## Unlock a grenade type.
## @param grenade_type: The grenade type to unlock.
func unlock_grenade(grenade_type: int) -> void:
	if grenade_type in _unlocked_grenades:
		return  # Already unlocked

	_unlocked_grenades.append(grenade_type)
	_save_unlock_state()
	item_unlocked.emit("grenade", str(grenade_type))
	_log("[UnlockManager] Grenade unlocked: %d" % grenade_type)


## Unlock an active item type.
## @param item_type: The active item type to unlock.
func unlock_active_item(item_type: int) -> void:
	if item_type in _unlocked_active_items:
		return  # Already unlocked

	_unlocked_active_items.append(item_type)
	_save_unlock_state()
	item_unlocked.emit("active_item", str(item_type))
	_log("[UnlockManager] Active item unlocked: %d" % item_type)


## Unlock all items (cheat/debug function).
func unlock_all() -> void:
	# Unlock all weapons from FIREARMS constant in armory_menu.gd
	var all_weapons: Array[String] = [
		"makarov_pm", "m16", "shotgun", "mini_uzi", "silenced_pistol",
		"sniper", "revolver", "ak_gl", "smg"
	]
	for weapon_id in all_weapons:
		if weapon_id not in _unlocked_weapons:
			_unlocked_weapons.append(weapon_id)

	# Unlock all grenade types (0-3)
	for i in range(4):
		if i not in _unlocked_grenades:
			_unlocked_grenades.append(i)

	# Unlock all active item types (0-5)
	for i in range(6):
		if i not in _unlocked_active_items:
			_unlocked_active_items.append(i)

	_save_unlock_state()
	_log("[UnlockManager] All items unlocked")


## Reset to default unlock state (only PM and flashbang).
func reset_to_default() -> void:
	_unlocked_weapons = DEFAULT_UNLOCKED_WEAPONS.duplicate()
	_unlocked_grenades = DEFAULT_UNLOCKED_GRENADES.duplicate()
	_unlocked_active_items = DEFAULT_UNLOCKED_ACTIVE_ITEMS.duplicate()
	_save_unlock_state()
	_log("[UnlockManager] Reset to default unlock state")


## Enable or disable unlock restrictions.
## @param enabled: True to enforce unlock restrictions, false to unlock everything.
func set_restrictions_enabled(enabled: bool) -> void:
	_restrictions_enabled = enabled
	_log("[UnlockManager] Restrictions %s" % ("enabled" if enabled else "disabled"))


## Check if unlock restrictions are enabled.
func are_restrictions_enabled() -> bool:
	return _restrictions_enabled


## Get the hold time required to unlock an item.
func get_unlock_hold_time() -> float:
	return UNLOCK_HOLD_TIME


## Save unlock state to file.
func _save_unlock_state() -> void:
	var config := ConfigFile.new()

	# Save weapons as comma-separated string
	config.set_value(SECTION_WEAPONS, "unlocked", ",".join(_unlocked_weapons))

	# Save grenades as comma-separated string of ints
	var grenade_strings: Array[String] = []
	for g in _unlocked_grenades:
		grenade_strings.append(str(g))
	config.set_value(SECTION_GRENADES, "unlocked", ",".join(grenade_strings))

	# Save active items as comma-separated string of ints
	var item_strings: Array[String] = []
	for i in _unlocked_active_items:
		item_strings.append(str(i))
	config.set_value(SECTION_ACTIVE_ITEMS, "unlocked", ",".join(item_strings))

	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("[UnlockManager] Failed to save unlock state: " + str(error))


## Load unlock state from file.
func _load_unlock_state() -> void:
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)

	if error != OK:
		# File doesn't exist or failed to load - use defaults
		_unlocked_weapons = DEFAULT_UNLOCKED_WEAPONS.duplicate()
		_unlocked_grenades = DEFAULT_UNLOCKED_GRENADES.duplicate()
		_unlocked_active_items = DEFAULT_UNLOCKED_ACTIVE_ITEMS.duplicate()
		_save_unlock_state()
		return

	# Load weapons
	var weapons_str: String = config.get_value(SECTION_WEAPONS, "unlocked", "")
	if weapons_str.is_empty():
		_unlocked_weapons = DEFAULT_UNLOCKED_WEAPONS.duplicate()
	else:
		_unlocked_weapons = []
		for weapon_id in weapons_str.split(","):
			var trimmed := weapon_id.strip_edges()
			if not trimmed.is_empty():
				_unlocked_weapons.append(trimmed)

	# Load grenades
	var grenades_str: String = config.get_value(SECTION_GRENADES, "unlocked", "")
	if grenades_str.is_empty():
		_unlocked_grenades = DEFAULT_UNLOCKED_GRENADES.duplicate()
	else:
		_unlocked_grenades = []
		for g_str in grenades_str.split(","):
			var trimmed := g_str.strip_edges()
			if not trimmed.is_empty() and trimmed.is_valid_int():
				_unlocked_grenades.append(int(trimmed))

	# Load active items
	var items_str: String = config.get_value(SECTION_ACTIVE_ITEMS, "unlocked", "")
	if items_str.is_empty():
		_unlocked_active_items = DEFAULT_UNLOCKED_ACTIVE_ITEMS.duplicate()
	else:
		_unlocked_active_items = []
		for i_str in items_str.split(","):
			var trimmed := i_str.strip_edges()
			if not trimmed.is_empty() and trimmed.is_valid_int():
				_unlocked_active_items.append(int(trimmed))


## Log a message to the file logger if available.
func _log(message: String) -> void:
	var file_logger: Node = get_node_or_null("/root/FileLogger")
	if file_logger and file_logger.has_method("log_info"):
		file_logger.log_info(message)
	else:
		print(message)
