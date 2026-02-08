extends Node
## Autoload singleton for managing active item selection.
##
## Tracks which active item is currently selected and provides
## data for the armory UI. Active items are equipment that
## the player activates during gameplay (e.g., flashlight).

## Active item types available in the game.
enum ActiveItemType {
	NONE,           # No active item equipped
	FLASHLIGHT,     # Tactical flashlight - illuminates in weapon direction
	HOMING_BULLETS  # Homing bullets - press Space to make bullets steer toward nearest enemy
}

## Currently selected active item type.
## No active item is selected by default.
var current_active_item: int = ActiveItemType.NONE

## Active item data for UI and selection.
const ACTIVE_ITEM_DATA: Dictionary = {
	ActiveItemType.NONE: {
		"name": "None",
		"icon_path": "",
		"description": "No active item equipped."
	},
	ActiveItemType.FLASHLIGHT: {
		"name": "Flashlight",
		"icon_path": "res://assets/sprites/weapons/flashlight_icon.png",
		"description": "Tactical flashlight — hold Space to illuminate in weapon direction. Bright white light, turns off when released."
	},
	ActiveItemType.HOMING_BULLETS: {
		"name": "Homing Bullets",
		"icon_path": "res://assets/sprites/weapons/homing_bullets_icon.png",
		"description": "Press Space to activate — bullets steer toward the nearest enemy (up to 110° turn). 6 charges per battle, each lasts 1 second."
	}
}

## Signal emitted when active item type changes.
signal active_item_changed(new_type: int)


## Set the current active item type.
## @param type: The new active item type to select.
## @param restart_level: Whether to restart the level on change (default true).
func set_active_item(type: int, restart_level: bool = true) -> void:
	if type == current_active_item:
		return  # No change

	if type not in ACTIVE_ITEM_DATA:
		FileLogger.info("[ActiveItemManager] Invalid active item type: %d" % type)
		return

	var old_type := current_active_item
	current_active_item = type

	FileLogger.info("[ActiveItemManager] Active item changed from %s to %s" % [
		ACTIVE_ITEM_DATA[old_type]["name"],
		ACTIVE_ITEM_DATA[type]["name"]
	])

	active_item_changed.emit(type)

	if restart_level:
		_restart_current_level()


## Restart the current level.
func _restart_current_level() -> void:
	FileLogger.info("[ActiveItemManager] Restarting level due to active item change")
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("restart_scene"):
		game_manager.restart_scene()
	else:
		get_tree().reload_current_scene()


## Get active item data for a specific type.
func get_active_item_data(type: int) -> Dictionary:
	if type in ACTIVE_ITEM_DATA:
		return ACTIVE_ITEM_DATA[type]
	return {}


## Get all available active item types.
func get_all_active_item_types() -> Array:
	return ACTIVE_ITEM_DATA.keys()


## Get the name of an active item type.
func get_active_item_name(type: int) -> String:
	if type in ACTIVE_ITEM_DATA:
		return ACTIVE_ITEM_DATA[type]["name"]
	return "Unknown"


## Get the description of an active item type.
func get_active_item_description(type: int) -> String:
	if type in ACTIVE_ITEM_DATA:
		return ACTIVE_ITEM_DATA[type]["description"]
	return ""


## Get the icon path of an active item type.
func get_active_item_icon_path(type: int) -> String:
	if type in ACTIVE_ITEM_DATA:
		return ACTIVE_ITEM_DATA[type]["icon_path"]
	return ""


## Check if an active item type is the currently selected type.
func is_selected(type: int) -> bool:
	return type == current_active_item


## Check if a flashlight is currently equipped.
func has_flashlight() -> bool:
	return current_active_item == ActiveItemType.FLASHLIGHT


## Check if homing bullets are currently equipped.
func has_homing_bullets() -> bool:
	return current_active_item == ActiveItemType.HOMING_BULLETS
