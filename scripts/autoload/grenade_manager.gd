extends Node
## Autoload singleton for managing grenade type selection.
##
## Tracks which grenade type is currently selected and provides
## the grenade scene for the player to use. Handles level restart
## when grenade type changes.

## Grenade types available in the game.
enum GrenadeType {
	FLASHBANG,  # Default: Stun grenade (blinds and stuns enemies)
	FRAG        # Offensive: Fragmentation grenade (explodes on impact, releases shrapnel)
}

## Currently selected grenade type.
## Flashbang is selected by default.
var current_grenade_type: int = GrenadeType.FLASHBANG

## Grenade type data for UI and selection.
const GRENADE_DATA: Dictionary = {
	GrenadeType.FLASHBANG: {
		"name": "Flashbang",
		"icon_path": "res://assets/sprites/weapons/flashbang.png",
		"scene_path": "res://scenes/projectiles/FlashbangGrenade.tscn",
		"description": "Stun grenade - blinds enemies for 12s, stuns for 6s. 4 second fuse timer."
	},
	GrenadeType.FRAG: {
		"name": "Frag Grenade",
		"icon_path": "res://assets/sprites/weapons/frag_grenade.png",
		"scene_path": "res://scenes/projectiles/FragGrenade.tscn",
		"description": "Offensive grenade - explodes on impact, releases 4 shrapnel pieces. Smaller radius."
	}
}

## Signal emitted when grenade type changes.
signal grenade_type_changed(new_type: int)

## Cached grenade scenes.
var _grenade_scenes: Dictionary = {}


func _ready() -> void:
	# Preload grenade scenes
	for type in GRENADE_DATA:
		var scene_path: String = GRENADE_DATA[type]["scene_path"]
		if ResourceLoader.exists(scene_path):
			_grenade_scenes[type] = load(scene_path)
			FileLogger.info("[GrenadeManager] Loaded grenade scene: %s" % scene_path)
		else:
			FileLogger.info("[GrenadeManager] WARNING: Grenade scene not found: %s" % scene_path)


## Get the currently selected grenade scene.
func get_current_grenade_scene() -> PackedScene:
	if current_grenade_type in _grenade_scenes:
		return _grenade_scenes[current_grenade_type]

	# Fallback to flashbang
	if GrenadeType.FLASHBANG in _grenade_scenes:
		return _grenade_scenes[GrenadeType.FLASHBANG]

	return null


## Get the grenade scene for a specific type.
func get_grenade_scene(type: int) -> PackedScene:
	if type in _grenade_scenes:
		return _grenade_scenes[type]
	return null


## Set the current grenade type.
## If the type changes, emits signal and optionally restarts the level.
## @param type: The new grenade type to select.
## @param restart_level: Whether to restart the level on change (default true).
func set_grenade_type(type: int, restart_level: bool = true) -> void:
	if type == current_grenade_type:
		return  # No change

	if type not in GRENADE_DATA:
		FileLogger.info("[GrenadeManager] Invalid grenade type: %d" % type)
		return

	var old_type := current_grenade_type
	current_grenade_type = type

	FileLogger.info("[GrenadeManager] Grenade type changed from %s to %s" % [
		GRENADE_DATA[old_type]["name"],
		GRENADE_DATA[type]["name"]
	])

	grenade_type_changed.emit(type)

	# Restart level if requested (per issue requirement)
	if restart_level:
		_restart_current_level()


## Restart the current level.
func _restart_current_level() -> void:
	FileLogger.info("[GrenadeManager] Restarting level due to grenade type change")

	# IMPORTANT: Unpause the game before restarting
	# This prevents the game from getting stuck in paused state when
	# changing grenades from the armory menu while the game is paused
	get_tree().paused = false

	# Restore hidden cursor for gameplay (confined and hidden)
	Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)

	# Use GameManager to restart if available
	var game_manager: Node = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("restart_scene"):
		game_manager.restart_scene()
	else:
		# Fallback: reload current scene directly
		get_tree().reload_current_scene()


## Get grenade data for a specific type.
func get_grenade_data(type: int) -> Dictionary:
	if type in GRENADE_DATA:
		return GRENADE_DATA[type]
	return {}


## Get all available grenade types.
func get_all_grenade_types() -> Array:
	return GRENADE_DATA.keys()


## Get the name of a grenade type.
func get_grenade_name(type: int) -> String:
	if type in GRENADE_DATA:
		return GRENADE_DATA[type]["name"]
	return "Unknown"


## Get the description of a grenade type.
func get_grenade_description(type: int) -> String:
	if type in GRENADE_DATA:
		return GRENADE_DATA[type]["description"]
	return ""


## Get the icon path of a grenade type.
func get_grenade_icon_path(type: int) -> String:
	if type in GRENADE_DATA:
		return GRENADE_DATA[type]["icon_path"]
	return ""


## Check if a grenade type is the currently selected type.
func is_selected(type: int) -> bool:
	return type == current_grenade_type
