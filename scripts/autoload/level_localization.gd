extends Node
## Shared helpers for level HUD localization.

const LEVEL_NAME_KEYS: Dictionary = {
	"res://scenes/levels/LabyrinthLevel.tscn": "LEVEL_LABYRINTH_NAME",
	"res://scenes/levels/BuildingLevel.tscn": "LEVEL_BUILDING_NAME",
	"res://scenes/levels/TestTier.tscn": "LEVEL_POLYGON_NAME",
	"res://scenes/levels/CastleLevel.tscn": "LEVEL_CASTLE_NAME",
	"res://scenes/levels/RevolverLevel.tscn": "LEVEL_DOUBLE_CORRIDOR_NAME",
	"res://scenes/levels/BeachLevel.tscn": "LEVEL_BEACH_NAME",
	"res://scenes/levels/DocksLevel.tscn": "LEVEL_DOCKS_NAME",
	"res://scenes/levels/CityLevel.tscn": "LEVEL_CITY_NAME",
	"res://scenes/levels/FactoryLevel.tscn": "LEVEL_FACTORY_NAME",
	"res://scenes/levels/DecadenceLevel.tscn": "LEVEL_DECADENCE_NAME",
	"res://scenes/levels/Labyrinth2Level.tscn": "LEVEL_LABYRINTH_COMPLEX_NAME",
	"res://scenes/levels/SewerLevel.tscn": "LEVEL_SEWER_NAME",
	"res://scenes/levels/WinterForestLevel.tscn": "LEVEL_WINTER_FOREST_NAME",
	"res://scenes/levels/RailwayStationLevel.tscn": "LEVEL_RAILWAY_STATION_NAME",
}

const DIFFICULTY_NAME_KEYS: Dictionary = {
	"Easy": "EASY",
	"Normal": "NORMAL",
	"Hard": "HARD",
	"Gunslinger": "GUNSLINGER",
}


func get_level_name_key(scene_path: String) -> String:
	return LEVEL_NAME_KEYS.get(scene_path, "")


func get_level_display_name(scene_path: String) -> String:
	var name_key: String = get_level_name_key(scene_path)
	if name_key != "":
		return tr(name_key)
	return scene_path.get_file().get_basename()


func apply_level_label(label: Label, scene_path: String) -> void:
	if label == null:
		return
	label.text = get_level_display_name(scene_path)


func ensure_level_label(owner: Node) -> Label:
	if owner == null:
		return null
	var ui: Control = owner.get_node_or_null("CanvasLayer/UI")
	if ui == null:
		return null
	var level_label: Label = ui.get_node_or_null("LevelLabel")
	if level_label != null:
		return level_label

	level_label = Label.new()
	level_label.name = "LevelLabel"
	level_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	level_label.anchor_left = 1.0
	level_label.anchor_right = 1.0
	level_label.offset_left = -250.0
	level_label.offset_top = 10.0
	level_label.offset_right = -10.0
	level_label.offset_bottom = 40.0
	level_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ui.add_child(level_label)
	ui.move_child(level_label, 0)
	return level_label


func apply_level_label_from_node(owner: Node, scene_path: String) -> void:
	if owner == null:
		return
	var level_label: Label = ensure_level_label(owner)
	apply_level_label(level_label, scene_path)


func get_enemy_count_text(count: int) -> String:
	return tr("HUD_ENEMIES") % count


func get_ammo_text(current_ammo: int, reserve_ammo: int) -> String:
	return tr("HUD_AMMO") % [current_ammo, reserve_ammo]


func get_magazines_text(parts: Array[String]) -> String:
	if parts.is_empty():
		return "%s: -" % tr("ARMORY_STAT_MAG")
	return "%s: %s" % [tr("ARMORY_STAT_MAG"), " | ".join(parts)]


func get_active_player_weapon(player: Node) -> Node:
	if player == null:
		return null

	var current_weapon = player.get("CurrentWeapon")
	if current_weapon != null and is_instance_valid(current_weapon):
		return current_weapon

	var selected_weapon_node_name := get_selected_weapon_node_name()
	if selected_weapon_node_name != "":
		var selected_weapon := player.get_node_or_null(selected_weapon_node_name)
		if selected_weapon != null:
			return selected_weapon

	var weapon_names: Array[String] = [
		"AssaultRifle",
		"AKGL",
		"MiniUzi",
		"SilencedPistol",
		"SniperRifle",
		"MakarovPM",
		"Shotgun",
		"Revolver",
	]
	for weapon_name in weapon_names:
		var weapon := player.get_node_or_null(weapon_name)
		if weapon != null:
			return weapon
	return null


func get_selected_weapon_node_name() -> String:
	var game_manager := get_node_or_null("/root/GameManager")
	if game_manager == null or not game_manager.has_method("get_selected_weapon"):
		return ""
	match game_manager.get_selected_weapon():
		"m16":
			return "AssaultRifle"
		"ak_gl":
			return "AKGL"
		"mini_uzi":
			return "MiniUzi"
		"silenced_pistol":
			return "SilencedPistol"
		"sniper":
			return "SniperRifle"
		"shotgun":
			return "Shotgun"
		"revolver":
			return "Revolver"
		"makarov_pm":
			return "MakarovPM"
		_:
			return ""


func weapon_hides_magazines(weapon: Node) -> bool:
	if weapon == null:
		return false
	if weapon.get("UsesTubeMagazine") == true:
		return true
	return weapon.has_signal("CylinderStateChanged")


func get_localized_difficulty_name(difficulty_name: String) -> String:
	var key: String = DIFFICULTY_NAME_KEYS.get(difficulty_name, "")
	if key != "":
		return tr(key)
	return difficulty_name


func get_difficulty_text(difficulty_name: String) -> String:
	return tr("HUD_DIFFICULTY") % get_localized_difficulty_name(difficulty_name)
