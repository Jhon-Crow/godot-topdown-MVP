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


func apply_level_label_from_node(owner: Node, scene_path: String) -> void:
	if owner == null:
		return
	var level_label: Label = owner.get_node_or_null("CanvasLayer/UI/LevelLabel")
	apply_level_label(level_label, scene_path)


func get_enemy_count_text(count: int) -> String:
	return tr("HUD_ENEMIES") % count


func get_ammo_text(current_ammo: int, reserve_ammo: int) -> String:
	return tr("HUD_AMMO") % [current_ammo, reserve_ammo]


func get_magazines_text(parts: Array[String]) -> String:
	if parts.is_empty():
		return "%s: -" % tr("ARMORY_STAT_MAG")
	return "%s: %s" % [tr("ARMORY_STAT_MAG"), " | ".join(parts)]


func get_localized_difficulty_name(difficulty_name: String) -> String:
	var key: String = DIFFICULTY_NAME_KEYS.get(difficulty_name, "")
	if key != "":
		return tr(key)
	return difficulty_name


func get_difficulty_text(difficulty_name: String) -> String:
	return tr("HUD_DIFFICULTY") % get_localized_difficulty_name(difficulty_name)
