extends Node
## Autoload singleton for managing active item selection.
##
## Tracks which active item is currently selected and provides
## data for the armory UI. Active items are equipment that
## the player activates during gameplay (e.g., flashlight).

## Active item types available in the game.
enum ActiveItemType {
	NONE,              # No active item equipped
	FLASHLIGHT,        # Tactical flashlight - illuminates in weapon direction
	HOMING_BULLETS,    # Homing bullets - press Space to make bullets steer toward nearest enemy
	TELEPORT_BRACERS,  # Teleportation bracers - hold Space to aim, release to teleport
	BFF_PENDANT,       # BFF pendant - press Space to summon a friendly companion with M16
	INVISIBILITY_SUIT, # Invisibility cloak - press Space to become invisible (Issue #673)
	BREAKER_BULLETS,   # Breaker bullets - passive: bullets explode 60px before wall, spawning shrapnel cone (Issue #678)
	FORCE_FIELD,       # Force field - hold Space to activate glowing shield that reflects projectiles (Issue #676)
	TRAJECTORY_GLASSES, # Trajectory glasses - press Space to show ricochet trajectories for 10 seconds (Issue #744)
	LASER_SIGHT,       # Laser sight - passive: purple laser sight on all weapons regardless of difficulty (Issue #947)
	BREACHING_CHARGES, # Breaching charges - active: place on wall (hold Space near wall, release), press Space to detonate and create a passage (Issue #1043)
	ARMORED_SKIN       # Armored Skin - passive: +1 HP bonus; when at ≤2 HP and hit, 20 glass shards fly outward (Issue #1045)
}

## Currently selected active item type.
## No active item is selected by default.
var current_active_item: int = ActiveItemType.NONE

## Unlocked active items tracking.
## NONE is always unlocked (it's not a real item).
## FLASHLIGHT (Polygon D+), TELEPORT_BRACERS (Double Corridor D+),
## INVISIBILITY_SUIT (Beach S + Building S), and HOMING_BULLETS
## (Labyrinth S + Building S + Polygon S + Castle S + Double Corridor S)
## have unlock conditions (Issue #894, Issue #1000).
var unlocked_active_items: Dictionary = {
	ActiveItemType.NONE: true,
	ActiveItemType.FLASHLIGHT: false,          # Condition: Polygon D+
	ActiveItemType.HOMING_BULLETS: false,      # Condition: Labyrinth S + Building S + Polygon S + Castle S + Double Corridor S (Issue #1000 req.8)
	ActiveItemType.TELEPORT_BRACERS: false,    # Condition: Double Corridor D+ (Issue #1000 req.3)
	ActiveItemType.BFF_PENDANT: true,          # No unlock condition — freely available from start (Issue #674)
	ActiveItemType.INVISIBILITY_SUIT: false,   # Condition: Beach S + Building S (Issue #1000 req.5)
	ActiveItemType.BREAKER_BULLETS: true,      # No unlock condition — freely available from start
	ActiveItemType.FORCE_FIELD: true,          # No unlock condition — freely available from start
	ActiveItemType.TRAJECTORY_GLASSES: true,   # No unlock condition — freely available from start (Issue #744)
	ActiveItemType.LASER_SIGHT: true,          # No unlock condition — freely available from start (Issue #947)
	ActiveItemType.BREACHING_CHARGES: true,    # No unlock condition — freely available from start (Issue #1043)
	ActiveItemType.ARMORED_SKIN: true          # No unlock condition — freely available from start (Issue #1045)
}

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
		"description": "Tactical flashlight — hold Space to illuminate in weapon direction. Bright white light, turns off when released.",
		"activation_hint": "Hold Space to activate"
	},
	ActiveItemType.HOMING_BULLETS: {
		"name": "Homing Bullets",
		"icon_path": "res://assets/sprites/weapons/homing_bullets_icon.png",
		"description": "Press Space to activate — bullets steer toward the nearest enemy (up to 110° turn). 2 charges per battle, each lasts 1.2 seconds."
	},
	ActiveItemType.TELEPORT_BRACERS: {
		"name": "Teleport Bracers",
		"icon_path": "res://assets/sprites/weapons/teleport_bracers_icon.png",
		"description": "Teleportation bracers — hold Space to aim, release to teleport. 6 charges, no cooldown. Reticle skips through walls.",
		"activation_hint": "Hold Space to aim, release to teleport"
	},
	ActiveItemType.BFF_PENDANT: {
		"name": "BFF Pendant",
		"icon_path": "res://assets/sprites/weapons/bff_pendant_icon.png",
		"description": "BFF pendant — press Space to summon a friendly companion armed with M16 (2-4 HP). One charge per battle.",
		"activation_hint": "Press Space to summon"
	},
	ActiveItemType.INVISIBILITY_SUIT: {
		"name": "Invisibility",
		"icon_path": "res://assets/sprites/weapons/invisibility_suit_icon.png",
		"description": "Invisibility suit — press Space to cloak (Predator-style ripple). Enemies cannot see you for 4 seconds. 2 charges per battle.",
		"activation_hint": "Press Space to activate"
	},
	ActiveItemType.BREAKER_BULLETS: {
		"name": "Breaker Bullets",
		"icon_path": "res://assets/sprites/weapons/breaker_bullets_icon.png",
		"description": "Breaker bullets — passive: bullets explode 60px before hitting a wall, dealing 1 damage in a 15px radius and releasing shrapnel in a forward cone."
	},
	ActiveItemType.FORCE_FIELD: {
		"name": "Force Field",
		"icon_path": "res://assets/sprites/weapons/force_field_icon.png",
		"description": "Force field — hold Space to activate glowing shield. 100% projectile reflection, grenades bounce without detonating. 8 second depletable charge.",
		"activation_hint": "Hold Space to activate"
	},
	ActiveItemType.TRAJECTORY_GLASSES: {
		"name": "Trajectory Glasses",
		"icon_path": "res://assets/sprites/weapons/trajectory_glasses_icon.png",
		"description": "Trajectory glasses — press Space to see ricochet trajectories for 10 seconds. Green laser shows valid ricochets, red shows impossible angles. 2 charges per battle. Passive: ricochet chance is increased by 30% at angles where ricochet is possible (green ray).",
		"activation_hint": "Press Space to activate"
	},
	ActiveItemType.LASER_SIGHT: {
		"name": "Laser Sight",
		"icon_path": "res://assets/sprites/weapons/laser_sight_icon.png",
		"description": "Laser sight — passive: adds a purple laser sight to all weapons regardless of difficulty."
	},
	ActiveItemType.BREACHING_CHARGES: {
		"name": "Breaching Charges",
		"icon_path": "res://assets/sprites/weapons/breaching_charges_icon.png",
		"description": "Breaching charges — hold Space near a wall to place a charge, release to attach it. Press Space to detonate: blasts open a passage in the wall. 2 charges per battle. Enemies on the other side are stunned and blinded for 3 seconds.",
		"activation_hint": "Hold Space near wall to place, press Space to detonate"
	},
	ActiveItemType.ARMORED_SKIN: {
		"name": "Armored Skin",
		"icon_path": "res://assets/sprites/weapons/armored_skin_icon.png",
		"description": "Armored Skin — passive: +1 HP. When at 2 HP or less and hit, 20 glass shards explode outward in all directions."
	}
}

## Signal emitted when active item type changes.
signal active_item_changed(new_type: int)

## Signal emitted when an active item is unlocked.
signal active_item_unlocked(item_type: int)


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


## Check if teleport bracers are currently equipped.
func has_teleport_bracers() -> bool:
	return current_active_item == ActiveItemType.TELEPORT_BRACERS


## Check if BFF pendant is currently equipped.
func has_bff_pendant() -> bool:
	return current_active_item == ActiveItemType.BFF_PENDANT


## Check if an invisibility suit is currently equipped (Issue #673).
func has_invisibility_suit() -> bool:
	return current_active_item == ActiveItemType.INVISIBILITY_SUIT


## Check if breaker bullets are currently equipped (Issue #678).
func has_breaker_bullets() -> bool:
	return current_active_item == ActiveItemType.BREAKER_BULLETS


## Check if force field is currently equipped (Issue #676).
func has_force_field() -> bool:
	return current_active_item == ActiveItemType.FORCE_FIELD


## Check if trajectory glasses are currently equipped (Issue #744).
func has_trajectory_glasses() -> bool:
	return current_active_item == ActiveItemType.TRAJECTORY_GLASSES


## Check if laser sight is currently equipped (Issue #947).
func has_laser_sight() -> bool:
	return current_active_item == ActiveItemType.LASER_SIGHT


## Check if breaching charges are currently equipped (Issue #1043).
func has_breaching_charges() -> bool:
	return current_active_item == ActiveItemType.BREACHING_CHARGES


## Check if armored skin is currently equipped (Issue #1045).
func has_armored_skin() -> bool:
	return current_active_item == ActiveItemType.ARMORED_SKIN


## Get the laser sight color (purple).
## Used by weapons to show purple laser when laser sight item is equipped.
func get_laser_sight_color() -> Color:
	return Color(0.6, 0.0, 1.0, 0.6)  # Purple with some transparency


## Check if a laser sight should be forced on all weapons.
## Returns true when laser sight active item is equipped (Issue #947).
func should_force_laser_sight() -> bool:
	return current_active_item == ActiveItemType.LASER_SIGHT


## Check if an active item type is unlocked.
## @param item_type: The active item type to check.
## @return: true if the item is unlocked, false otherwise.
## Note: If all_weapons_unlocked is enabled in ExperimentalSettings, all items return true.
func is_active_item_unlocked(item_type: int) -> bool:
	# Check if all weapons are unlocked via experimental setting (Issue #882)
	var experimental_settings: Node = get_node_or_null("/root/ExperimentalSettings")
	if experimental_settings and experimental_settings.has_method("is_all_weapons_unlocked"):
		if experimental_settings.is_all_weapons_unlocked():
			return true
	return unlocked_active_items.get(item_type, false)


## Unlock an active item type.
## @param item_type: The active item type to unlock.
func unlock_active_item(item_type: int) -> void:
	if item_type in unlocked_active_items:
		if not unlocked_active_items[item_type]:
			unlocked_active_items[item_type] = true
			active_item_unlocked.emit(item_type)
			FileLogger.info("[ActiveItemManager] Active item unlocked: %s" % get_active_item_name(item_type))


## Get all unlocked active items.
## @return: Dictionary of item_type -> bool pairs.
func get_unlocked_active_items() -> Dictionary:
	return unlocked_active_items
