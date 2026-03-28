extends Node
## Autoload singleton for managing active item selection.
##
## Tracks which active item is currently selected and provides
## data for the armory UI. Active items are equipment that
## the player activates during gameplay (e.g., flashlight).
## Also holds the LoudspeakerProgress singleton so it survives
## scene reloads (Issue #959).

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
	EXTENDED_MAGAZINE, # Extended magazine - passive: 2.5x magazine size, 5% less total ammo (Issue #1065)
	LOUDSPEAKER,       # Loudspeaker - press Space to emit sound cone that can pacify enemies (Issue #959)
	BREACHING_CHARGES, # Breaching charges - active: place on wall (hold Space near wall, release), press Space to detonate and create a passage (Issue #1043)
	ARMORED_SKIN,      # Armored Skin - passive: +1 HP bonus; when at ≤2 HP and hit, 20 glass shards fly outward (Issue #1045)
	AUTO_RELOAD,       # Auto-reload on kill - passive: magazine is 2.1x smaller, refilled from reserve on each kill (Issue #1067)
	DRILLING_BULLETS,  # Drilling bullets - press Space to give current magazine wall-piercing bullets (Issue #751)
	RECOIL_COMPENSATOR, # Recoil compensator - hold Space to eliminate recoil/spread and boost fire rate 10% (Issue #1073)
	COMBAT_DISPOSITION, # Combat Disposition - passive: +0.77 damage, +1.1 fire rate, x2 speed on start (x4 on Black Metal), no drift; on hit: -6.0 damage, -7.2 fire rate, speed/2 (Issue #1047, #1583, #1623)
	EXPERIMENTAL_SAMPLE, # Experimental Sample - press Space to fire a random active item effect (even unowned). 1–5 charges per battle, randomised on level start (Issue #1127)
	FINE_MOTOR_SKILLS, # Fine Motor Skills - press Space to instantly reload weapon and bring to combat-ready state. Unlimited charges, no cooldown (Issue #1315)
	DASH,              # Dash - press Space to dash in movement direction with damage immunity. 3 charges, cooldown after 3rd dash (Issue #1071)
	GRENADE_BAG,       # Grenade Bag - passive: increases starting grenade count based on selected grenade type (Issue #1590)
	COMBAT_KNIFE       # Combat Knife - press Space for a fan melee attack, deals 7 damage to hit enemies. Unlimited uses (Issue #1587)
}

## Currently selected active item type.
## No active item is selected by default.
var current_active_item: int = ActiveItemType.NONE

## Passive items collected during a roguelike run.
## Multiple passive items can be active simultaneously (Issue #1303).
## This array accumulates passive item type IDs as the player picks them up.
var collected_passive_items: Array = []

## Unlocked active items tracking.
## NONE is always unlocked (it's not a real item).
## FLASHLIGHT (Polygon D+), TELEPORT_BRACERS (Double Corridor D+),
## INVISIBILITY_SUIT (Beach S + Building S), HOMING_BULLETS
## (Labyrinth S + Building S + Polygon S + Castle S + Double Corridor S),
## TRAJECTORY_GLASSES (City D+), LASER_SIGHT (400 kills without laser sight equipped),
## FINE_MOTOR_SKILLS (650 shots with shotgun, sniper rifle, or revolver),
## ARMORED_SKIN (100 total deaths), COMBAT_DISPOSITION (complete 1 level without damage),
## RECOIL_COMPENSATOR (Labyrinth S), EXPERIMENTAL_SAMPLE (complete at least one level on every difficulty),
## EXTENDED_MAGAZINE (Building B+), AUTO_RELOAD (any level with silenced pistol),
## DRILLING_BULLETS (50 kills through walls), DASH (Decadence A+),
## BREACHING_CHARGES (Labyrinth Complex any grade), GRENADE_BAG (Railway Station any grade),
## BFF_PENDANT (Winter Forest any grade) have unlock conditions
## (Issue #894, Issue #1000, Issue #1053, Issue #1196, Issue #1346, Issue #1389, Issue #1423, Issue #1426, Issue #1624).
var unlocked_active_items: Dictionary = {
	ActiveItemType.NONE: true,
	ActiveItemType.FLASHLIGHT: false,          # Condition: Polygon D+
	ActiveItemType.HOMING_BULLETS: false,      # Condition: Labyrinth S + Building S + Polygon S + Castle S + Double Corridor S (Issue #1000 req.8)
	ActiveItemType.TELEPORT_BRACERS: false,    # Condition: Double Corridor D+ (Issue #1000 req.3)
	ActiveItemType.BFF_PENDANT: false,         # Condition: complete Winter Forest on any grade (Issue #1624 req.9)
	ActiveItemType.INVISIBILITY_SUIT: false,   # Condition: Beach S + Building S (Issue #1000 req.5)
	ActiveItemType.BREAKER_BULLETS: false,     # Condition: 7 levels completed at rank A or higher (Issue #1589 req.3)
	ActiveItemType.FORCE_FIELD: false,         # Condition: complete Factory on any grade (Issue #1589 req.2)
	ActiveItemType.TRAJECTORY_GLASSES: false,  # Condition: City D+ (Issue #1053 req.1)
	ActiveItemType.LASER_SIGHT: false,         # Condition: 400 kills without laser sight equipped (Issue #1196, updated by Issue #1589)
	ActiveItemType.EXTENDED_MAGAZINE: false,   # Condition: Building B+ (Issue #1624 req.1)
	ActiveItemType.LOUDSPEAKER: true,          # No unlock condition — freely available from start (Issue #959)
	ActiveItemType.BREACHING_CHARGES: false,   # Condition: complete Labyrinth Complex on any grade (Issue #1624 req.6)
	ActiveItemType.ARMORED_SKIN: false,        # Condition: 100 total deaths (Issue #1389)
	ActiveItemType.AUTO_RELOAD: false,         # Condition: complete any level with silenced pistol (Issue #1624 req.2)
	ActiveItemType.DRILLING_BULLETS: false,    # Condition: 50 kills through walls (Issue #1624 req.3)
	ActiveItemType.RECOIL_COMPENSATOR: false,  # Condition: Labyrinth S (Issue #1423 req.2)
	ActiveItemType.COMBAT_DISPOSITION: false,  # Condition: complete 1 level without taking damage (Issue #1389)
	ActiveItemType.EXPERIMENTAL_SAMPLE: false,   # Condition: complete at least one level on every difficulty (Issue #1426)
	ActiveItemType.FINE_MOTOR_SKILLS: false,    # Condition: 300 shots with shotgun, sniper rifle, or revolver (Issue #1346)
	ActiveItemType.DASH: false,                 # Condition: Decadence A+ (Issue #1624 req.5)
	ActiveItemType.GRENADE_BAG: false,          # Condition: complete Railway Station on any grade (Issue #1624 req.8)
	ActiveItemType.COMBAT_KNIFE: false          # Condition: reach melee range 10 times (Issue #1587)
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
	ActiveItemType.EXTENDED_MAGAZINE: {
		"name": "Extended Magazine",
		"icon_path": "res://assets/sprites/weapons/extended_magazine_icon.png",
		"description": "Extended magazine — passive: increases magazine size by 2.5x (including revolver cylinder), but reduces total ammo by 5%."
	},
	ActiveItemType.LOUDSPEAKER: {
		"name": "Loudspeaker",
		"icon_path": "res://assets/sprites/weapons/loudspeaker_icon.png",
		"description": "???",
		"activation_hint": "Press Space to activate"
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
	},
	ActiveItemType.AUTO_RELOAD: {
		"name": "Auto-Reload",
		"icon_path": "res://assets/sprites/weapons/auto_reload_icon.png",
		"description": "Auto-reload — passive: magazine capacity is reduced 2.1x, but the magazine is fully restocked from reserves on each kill."
	},
	ActiveItemType.DRILLING_BULLETS: {
		"name": "Drilling Bullets",
		"icon_path": "res://assets/sprites/weapons/drilling_bullets_icon.png",
		"description": "Drilling bullets — press Space to apply wall-piercing effect to the current magazine. Bullets ignore walls (full damage through walls, no ricochet). One charge per battle.",
		"activation_hint": "Press Space to activate"
	},
	ActiveItemType.RECOIL_COMPENSATOR: {
		"name": "Recoil Compensator",
		"icon_path": "res://assets/sprites/weapons/recoil_compensator_icon.png",
		"description": "Recoil compensator — hold Space to eliminate recoil and spread completely, and increase fire rate by 10%. 15 second depletable charge, unlimited activations while charge lasts.",
		"activation_hint": "Hold Space to activate"
	},
	ActiveItemType.COMBAT_DISPOSITION: {
		"name": "Combat Disposition",
		"icon_path": "res://assets/sprites/weapons/combat_disposition_icon.png",
		"description": "Combat Disposition — passive: +0.77 damage, +1.1 fire rate, x2 speed on start (x4 on Black Metal). Taking damage reduces damage by 6.0, fire rate by 7.2, and halves movement speed."
	},
	ActiveItemType.EXPERIMENTAL_SAMPLE: {
		"name": "Experimental Sample",
		"icon_path": "res://assets/sprites/weapons/experimental_sample_icon.png",
		"description": "Experimental Sample — press Space to trigger a random active item effect (including items not yet unlocked). 1–5 charges per battle, randomised on level start.",
		"activation_hint": "Press Space to trigger random effect"
	},
	ActiveItemType.FINE_MOTOR_SKILLS: {
		"name": "Fine Motor Skills",
		"icon_path": "res://assets/sprites/weapons/fine_motor_skills_icon.png",
		"description": "Fine Motor Skills — press Space to instantly reload weapon and bring it to combat-ready state. Works with all weapons including revolver, shotgun, and sniper rifle. Unlimited charges, no cooldown.",
		"activation_hint": "Press Space to reload"
	},
	ActiveItemType.DASH: {
		"name": "Dash",
		"icon_path": "res://assets/sprites/weapons/dash_icon.png",
		"description": "Dash — press Space to dash in movement direction (Hyper Light Drifter style). Immune to all damage during dash. 3 charges with chain-dash, cooldown after all charges spent.",
		"activation_hint": "Press Space to dash"
	},
	ActiveItemType.GRENADE_BAG: {
		"name": "Grenade Bag",
		"icon_path": "res://assets/sprites/weapons/grenade_bag_icon.png",
		"description": "Grenade Bag — passive: increases starting grenade count based on selected type: 12 flash/stun grenades, 6 frag grenades, 2 gas or F-1 grenades."
	},
	ActiveItemType.COMBAT_KNIFE: {
		"name": "Combat Knife",
		"icon_path": "res://assets/sprites/weapons/combat_knife_icon.png",
		"description": "Combat Knife — press Space for a fan melee attack dealing 7 damage to all enemies in a 120° arc. Unlimited uses, no cooldown between attacks.",
		"activation_hint": "Press Space to slash"
	}
}

## Loudspeaker progression tracker (Issue #959).
## Stored here (autoload) so it persists across scene reloads.
var loudspeaker_progress: LoudspeakerProgress = LoudspeakerProgress.new()

## Whether the player's active items are currently jammed by a Radio Jammer enemy (Issue #1036).
## NOTE: This flag is no longer the source of truth for jam state.
## is_active_item_jammed() queries the scene tree directly to avoid physics-process race conditions.
var _is_jammed: bool = false

## Jam radius used by Radio Jammer enemies (pixels). Must match RadioWaveEffect.jammer_radius.
const JAMMER_RADIUS: float = 1000.0

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


## Add a passive item to the collected set (roguelike mode).
## Passive items accumulate and coexist with each other and with the active item.
## @param type: The passive item type to add.
func add_passive_item(type: int) -> void:
	if type in collected_passive_items:
		return  # Already collected
	collected_passive_items.append(type)
	FileLogger.info("[ActiveItemManager] Passive item added: %s (total passives: %d)" % [
		get_active_item_name(type), collected_passive_items.size()
	])
	active_item_changed.emit(type)


## Check if a passive item is in the collected set.
## @param type: The item type to check.
## @return: true if the item is in collected_passive_items.
func has_passive_item(type: int) -> bool:
	return type in collected_passive_items


## Clear all collected passive items (called on roguelike run start).
func clear_passive_items() -> void:
	collected_passive_items.clear()
	FileLogger.info("[ActiveItemManager] Passive items cleared for new run")


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
## Also checks collected passive items for roguelike mode (Issue #1303).
func has_breaker_bullets() -> bool:
	return current_active_item == ActiveItemType.BREAKER_BULLETS or ActiveItemType.BREAKER_BULLETS in collected_passive_items


## Check if force field is currently equipped (Issue #676).
func has_force_field() -> bool:
	return current_active_item == ActiveItemType.FORCE_FIELD


## Check if trajectory glasses are currently equipped (Issue #744).
func has_trajectory_glasses() -> bool:
	return current_active_item == ActiveItemType.TRAJECTORY_GLASSES


## Check if laser sight is currently equipped (Issue #947).
## Also checks collected passive items for roguelike mode (Issue #1303).
func has_laser_sight() -> bool:
	return current_active_item == ActiveItemType.LASER_SIGHT or ActiveItemType.LASER_SIGHT in collected_passive_items


## Check if extended magazine is currently equipped (Issue #1065).
## Also checks collected passive items for roguelike mode (Issue #1303).
func has_extended_magazine() -> bool:
	return current_active_item == ActiveItemType.EXTENDED_MAGAZINE or ActiveItemType.EXTENDED_MAGAZINE in collected_passive_items


## Get the magazine size multiplier from extended magazine item (Issue #1065).
## Returns 2.5 when extended magazine is equipped, 1.0 otherwise.
## Also checks collected passive items for roguelike mode (Issue #1303).
func get_magazine_size_multiplier() -> float:
	if has_extended_magazine():
		return 2.5
	return 1.0


## Get the total ammo multiplier from extended magazine item (Issue #1065).
## Returns 0.95 when extended magazine is equipped, 1.0 otherwise.
## Also checks collected passive items for roguelike mode (Issue #1303).
func get_total_ammo_multiplier() -> float:
	if has_extended_magazine():
		return 0.95
	return 1.0


## Check if loudspeaker is currently equipped (Issue #959).
func has_loudspeaker() -> bool:
	return current_active_item == ActiveItemType.LOUDSPEAKER


## Check if breaching charges are currently equipped (Issue #1043).
func has_breaching_charges() -> bool:
	return current_active_item == ActiveItemType.BREACHING_CHARGES


## Check if armored skin is currently equipped (Issue #1045).
## Also checks collected passive items for roguelike mode (Issue #1303).
func has_armored_skin() -> bool:
	return current_active_item == ActiveItemType.ARMORED_SKIN or ActiveItemType.ARMORED_SKIN in collected_passive_items


## Check if drilling bullets are currently equipped (Issue #751).
func has_drilling_bullets() -> bool:
	return current_active_item == ActiveItemType.DRILLING_BULLETS


## Check if recoil compensator is currently equipped (Issue #1073).
func has_recoil_compensator() -> bool:
	return current_active_item == ActiveItemType.RECOIL_COMPENSATOR


## Check if combat disposition is currently equipped (Issue #1047).
## Also checks collected passive items for roguelike mode (Issue #1303).
func has_combat_disposition() -> bool:
	return current_active_item == ActiveItemType.COMBAT_DISPOSITION or ActiveItemType.COMBAT_DISPOSITION in collected_passive_items


## Check if experimental sample is currently equipped (Issue #1127).
func has_experimental_sample() -> bool:
	return current_active_item == ActiveItemType.EXPERIMENTAL_SAMPLE


## Check if fine motor skills is currently equipped (Issue #1315).
func has_fine_motor_skills() -> bool:
	return current_active_item == ActiveItemType.FINE_MOTOR_SKILLS


## Check if dash is currently equipped (Issue #1071).
func has_dash() -> bool:
	return current_active_item == ActiveItemType.DASH


## Check if grenade bag is currently equipped (Issue #1590).
## Also checks collected passive items for roguelike mode (Issue #1303).
func has_grenade_bag() -> bool:
	return current_active_item == ActiveItemType.GRENADE_BAG or ActiveItemType.GRENADE_BAG in collected_passive_items


## Check if combat knife is currently equipped (Issue #1587).
func has_combat_knife() -> bool:
	return current_active_item == ActiveItemType.COMBAT_KNIFE


## Get the grenade count granted by the Grenade Bag item (Issue #1590).
## Returns count based on the currently selected grenade type:
##   FLASHBANG  → 12 grenades
##   FRAG       → 6 grenades
##   AGGRESSION_GAS → 2 grenades
##   DEFENSIVE (F-1) → 2 grenades
## Returns 0 when Grenade Bag is not equipped.
func get_grenade_bag_count() -> int:
	if not has_grenade_bag():
		return 0
	var grenade_manager: Node = get_node_or_null("/root/GrenadeManager")
	if grenade_manager == null:
		return 6  # Fallback default
	var grenade_type: int = grenade_manager.get("current_grenade_type")
	# GrenadeType enum: FLASHBANG=0, FRAG=1, DEFENSIVE=2, AGGRESSION_GAS=3
	match grenade_type:
		0:  # FLASHBANG
			return 12
		1:  # FRAG
			return 6
		2:  # DEFENSIVE (F-1)
			return 2
		3:  # AGGRESSION_GAS
			return 2
		_:
			return 6  # Fallback for unknown types


## Get the laser sight color (purple).
## Used by weapons to show purple laser when laser sight item is equipped.
func get_laser_sight_color() -> Color:
	return Color(0.6, 0.0, 1.0, 0.6)  # Purple with some transparency


## Check if a laser sight should be forced on all weapons.
## Returns true when laser sight active item is equipped (Issue #947).
## Also checks collected passive items for roguelike mode (Issue #1303).
func should_force_laser_sight() -> bool:
	return has_laser_sight()


## Check if any laser sight is currently active on the player's weapon, from any source.
## This includes: the Laser Sight active item (purple), Power Fantasy blue laser (difficulty),
## or a weapon-level built-in laser sight (e.g. AssaultRifle's red laser).
## Used by Issue #1196 to determine if kills should NOT count toward the Laser Sight unlock.
func has_any_laser_sight_active() -> bool:
	# 1. Active item laser sight (purple)
	if has_laser_sight():
		return true
	# 2. Power Fantasy blue laser sight (difficulty-based)
	var difficulty_manager: Node = get_node_or_null("/root/DifficultyManager")
	if difficulty_manager and difficulty_manager.has_method("should_force_blue_laser_sight"):
		if difficulty_manager.should_force_blue_laser_sight():
			return true
	# 3. Weapon-level built-in laser sight (e.g. AssaultRifle's red laser).
	# Check if the player's current weapon has a visible "LaserSight" Line2D node.
	var players := get_tree().get_nodes_in_group("player") if get_tree() else []
	for player in players:
		if not is_instance_valid(player):
			continue
		for child in player.get_children():
			# Check GDScript weapon with a laser_sight_enabled property or "has_laser_sight"
			if child.has_method("get_laser_sight_enabled"):
				if child.get_laser_sight_enabled():
					return true
			# Check for a Line2D node named "LaserSight" that is visible
			var laser_node: Node = child.get_node_or_null("LaserSight")
			if laser_node and laser_node.visible:
				return true
			# Check C# weapon: LaserSightEnabled exported property
			if child.get("LaserSightEnabled") != null and child.get("LaserSightEnabled"):
				return true
	return false


## Notify loudspeaker progression that a level was completed (Issue #959).
## @param had_kills: Whether the player killed any enemies (pacifists don't count as kills).
## Should be called from every level script when the level is completed.
func notify_level_completed(had_kills: bool) -> void:
	if current_active_item == ActiveItemType.LOUDSPEAKER:
		loudspeaker_progress.on_level_completed(had_kills)
		FileLogger.info("[ActiveItemManager] Loudspeaker level completed (had_kills=%s). New level: %d" % [
			had_kills, loudspeaker_progress.current_level
		])
		# Reset used_this_level so the next map's first activation is tracked fresh.
		loudspeaker_progress.reset_for_new_level()


## Reset loudspeaker progression (called from PersistManager.clear_all_saves) (Issue #959).
func reset_loudspeaker_progress() -> void:
	loudspeaker_progress = LoudspeakerProgress.new()
	FileLogger.info("[ActiveItemManager] Loudspeaker progress reset")


## Check if auto-reload is currently equipped (Issue #1067).
## Also checks collected passive items for roguelike mode (Issue #1303).
func has_auto_reload() -> bool:
	return current_active_item == ActiveItemType.AUTO_RELOAD or ActiveItemType.AUTO_RELOAD in collected_passive_items


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


## Set whether the player's active items are jammed by a Radio Jammer enemy (Issue #1036).
## Kept for backward compatibility — the flag is now advisory only.
## @param jammed: true to jam active items, false to restore them.
func set_jammed(jammed: bool) -> void:
	_is_jammed = jammed


## Accumulator used to throttle periodic jammer diagnostics logs (seconds).
var _jammer_log_timer: float = 0.0

## Interval between periodic jammer diagnostics logs (seconds).
const JAMMER_LOG_INTERVAL: float = 2.0

## Log a periodic diagnostic about jammer state (called from radio_wave_effect _physics_process).
## Throttled to once per JAMMER_LOG_INTERVAL to avoid log spam.
func log_jammer_diagnostics(delta: float) -> void:
	_jammer_log_timer += delta
	if _jammer_log_timer < JAMMER_LOG_INTERVAL:
		return
	_jammer_log_timer = 0.0
	var players := get_tree().get_nodes_in_group("player")
	var jammers := get_tree().get_nodes_in_group("radio_jammers")
	if jammers.is_empty():
		return  # No jammers — silent when no jammers present
	var player_pos_str := "N/A"
	if not players.is_empty() and is_instance_valid(players[0]):
		player_pos_str = "(%.0f,%.0f)" % [players[0].global_position.x, players[0].global_position.y]
	for jammer in jammers:
		if not is_instance_valid(jammer):
			continue
		var alive := "(alive)" if (not jammer.has_method("is_alive") or jammer.is_alive()) else "(dead)"
		var dist_str := "dist=N/A"
		if not players.is_empty() and is_instance_valid(players[0]):
			dist_str = "dist=%.1f" % jammer.global_position.distance_to(players[0].global_position)
		FileLogger.info("[ActiveItemManager.Jammer] Periodic: jammer='%s' %s player=%s %s radius=%.0f" % [
			jammer.name, alive, player_pos_str, dist_str, JAMMER_RADIUS
		])


## Check whether the player's active items are currently jammed (Issue #1036).
## Directly queries the scene tree for living Radio Jammer enemies within JAMMER_RADIUS
## of the player to avoid physics-process race conditions (root cause of bug reported
## in comment on 2026-03-17: player could use active item even while inside jammer range).
## Returns true when at least one living Radio Jammer enemy is within JAMMER_RADIUS.
func is_active_item_jammed() -> bool:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return false
	var player: Node = players[0]
	if not is_instance_valid(player):
		return false
	var jammers := get_tree().get_nodes_in_group("radio_jammers")
	if jammers.is_empty():
		return false
	var player_pos: Vector2 = player.global_position
	for jammer in jammers:
		if not is_instance_valid(jammer):
			continue
		if jammer.has_method("is_alive") and not jammer.is_alive():
			continue
		if jammer.global_position.distance_to(player_pos) <= JAMMER_RADIUS:
			return true
	return false


## Check whether the player's active items are currently jammed, with detailed logging.
## Called only when the player actually presses Space (flashlight_toggle action),
## so logging doesn't flood the log file.
func is_active_item_jammed_verbose() -> bool:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		FileLogger.info("[ActiveItemManager.Jammer] VERBOSE: No player in 'player' group")
		return false
	var player: Node = players[0]
	if not is_instance_valid(player):
		FileLogger.info("[ActiveItemManager.Jammer] VERBOSE: Player invalid")
		return false
	var player_pos: Vector2 = player.global_position
	var jammers := get_tree().get_nodes_in_group("radio_jammers")
	FileLogger.info("[ActiveItemManager.Jammer] VERBOSE: %d jammer(s) in group, player=(%.0f,%.0f)" % [
		jammers.size(), player_pos.x, player_pos.y
	])
	for jammer in jammers:
		if not is_instance_valid(jammer):
			FileLogger.info("[ActiveItemManager.Jammer] VERBOSE: Jammer instance invalid — skip")
			continue
		var alive: bool = not jammer.has_method("is_alive") or jammer.is_alive()
		var dist: float = jammer.global_position.distance_to(player_pos)
		FileLogger.info("[ActiveItemManager.Jammer] VERBOSE: jammer='%s' alive=%s pos=(%.0f,%.0f) dist=%.1f radius=%.1f => %s" % [
			jammer.name, str(alive),
			jammer.global_position.x, jammer.global_position.y,
			dist, JAMMER_RADIUS,
			"JAMMED" if (alive and dist <= JAMMER_RADIUS) else "clear"
		])
		if alive and dist <= JAMMER_RADIUS:
			return true
	return false
