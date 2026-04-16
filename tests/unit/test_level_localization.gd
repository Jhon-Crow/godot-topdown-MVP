extends GutTest

const LevelLocalizationScript := preload("res://scripts/autoload/level_localization.gd")
const BuildingLevelScript := preload("res://scripts/levels/building_level.gd")

var _helper: Node


func before_each() -> void:
	_helper = LevelLocalizationScript.new()
	add_child_autofree(_helper)


func test_level_name_key_uses_known_scene_mapping() -> void:
	assert_eq(_helper.get_level_name_key("res://scenes/levels/SewerLevel.tscn"), "LEVEL_SEWER_NAME")
	assert_eq(_helper.get_level_name_key("res://scenes/levels/TestTier.tscn"), "LEVEL_POLYGON_NAME")
	assert_eq(_helper.get_level_name_key("res://scenes/levels/CastleLevel.tscn"), "LEVEL_CASTLE_NAME")


func test_level_name_falls_back_to_scene_basename_when_mapping_missing() -> void:
	assert_eq(_helper.get_level_display_name("res://scenes/levels/UnknownArena.tscn"), "UnknownArena")


func test_localized_hud_labels_use_translation_keys() -> void:
	assert_eq(_helper.get_enemy_count_text(7), tr("HUD_ENEMIES") % 7)
	assert_eq(_helper.get_ammo_text(12, 30), tr("HUD_AMMO") % [12, 30])
	assert_eq(_helper.get_difficulty_text("Hard"), tr("HUD_DIFFICULTY") % tr("HARD"))


func test_known_level_name_translations_resolve_for_bidirectional_locales() -> void:
	assert_eq(_helper.get_level_display_name("res://scenes/levels/TestTier.tscn"), tr("LEVEL_POLYGON_NAME"))
	assert_eq(_helper.get_level_display_name("res://scenes/levels/CastleLevel.tscn"), tr("LEVEL_CASTLE_NAME"))
	assert_eq(_helper.get_level_display_name("res://scenes/levels/SewerLevel.tscn"), tr("LEVEL_SEWER_NAME"))


func test_owner_reported_level_names_are_all_mapped() -> void:
	var scene_paths := [
		"res://scenes/levels/BuildingLevel.tscn",
		"res://scenes/levels/BeachLevel.tscn",
		"res://scenes/levels/DocksLevel.tscn",
		"res://scenes/levels/FactoryLevel.tscn",
		"res://scenes/levels/Labyrinth2Level.tscn",
		"res://scenes/levels/WinterForestLevel.tscn",
		"res://scenes/levels/RailwayStationLevel.tscn",
		"res://scenes/levels/SewerLevel.tscn",
	]
	for scene_path in scene_paths:
		assert_ne(_helper.get_level_name_key(scene_path), "")


func test_special_difficulties_are_localized_for_hud() -> void:
	assert_eq(_helper.get_localized_difficulty_name("Power Fantasy"), "Power Fantasy")
	assert_eq(_helper.get_localized_difficulty_name("Black Metal"), "Black Metal")
	assert_eq(_helper.get_difficulty_text("Power Fantasy"), tr("HUD_DIFFICULTY") % "Power Fantasy")
	assert_eq(_helper.get_difficulty_text("Black Metal"), tr("HUD_DIFFICULTY") % "Black Metal")
	assert_eq(_helper.get_difficulty_text("Gunslinger"), tr("HUD_DIFFICULTY") % tr("GUNSLINGER"))


func test_magazines_label_uses_translated_mag_prefix() -> void:
	assert_eq(_helper.get_magazines_text([]), "%s: -" % tr("ARMORY_STAT_MAG"))
	assert_eq(_helper.get_magazines_text(["[30]", "25", "10"]), "%s: [30] | 25 | 10" % tr("ARMORY_STAT_MAG"))


func test_active_weapon_prefers_current_weapon_before_inactive_shotgun_child() -> void:
	var player := Node2D.new()
	add_child_autofree(player)
	var shotgun := Node.new()
	shotgun.name = "Shotgun"
	shotgun.set("UsesTubeMagazine", true)
	player.add_child(shotgun)
	var assault_rifle := Node.new()
	assault_rifle.name = "AssaultRifle"
	player.add_child(assault_rifle)
	player.set("CurrentWeapon", assault_rifle)

	assert_eq(_helper.get_active_player_weapon(player), assault_rifle)
	assert_false(_helper.weapon_hides_magazines(_helper.get_active_player_weapon(player)))


func test_active_weapon_fallback_prefers_detachable_weapons_before_shotgun() -> void:
	var player := Node2D.new()
	add_child_autofree(player)
	var shotgun := Node.new()
	shotgun.name = "Shotgun"
	shotgun.set("UsesTubeMagazine", true)
	player.add_child(shotgun)
	var assault_rifle := Node.new()
	assault_rifle.name = "AssaultRifle"
	player.add_child(assault_rifle)

	assert_eq(_helper.get_active_player_weapon(player), assault_rifle)
	assert_false(_helper.weapon_hides_magazines(_helper.get_active_player_weapon(player)))


func test_apply_level_label_populates_top_right_label_text() -> void:
	var label := Label.new()
	add_child_autofree(label)

	_helper.apply_level_label(label, "res://scenes/levels/SewerLevel.tscn")

	assert_eq(label.text, tr("LEVEL_SEWER_NAME"))


func test_apply_level_label_from_node_updates_canvas_ui_label() -> void:
	var level_root := Node.new()
	add_child_autofree(level_root)
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "CanvasLayer"
	level_root.add_child(canvas_layer)
	var ui := Control.new()
	ui.name = "UI"
	canvas_layer.add_child(ui)
	var label := Label.new()
	label.name = "LevelLabel"
	ui.add_child(label)

	_helper.apply_level_label_from_node(level_root, "res://scenes/levels/BuildingLevel.tscn")

	assert_eq(label.text, tr("LEVEL_BUILDING_NAME"))


func test_apply_level_label_from_node_overrides_building_scene_default_text() -> void:
	var level_root := Node.new()
	add_child_autofree(level_root)
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "CanvasLayer"
	level_root.add_child(canvas_layer)
	var ui := Control.new()
	ui.name = "UI"
	canvas_layer.add_child(ui)
	var label := Label.new()
	label.name = "LevelLabel"
	label.text = "BUILDING INTERIOR"
	ui.add_child(label)

	_helper.apply_level_label_from_node(level_root, "res://scenes/levels/BuildingLevel.tscn")

	assert_eq(label.text, tr("LEVEL_BUILDING_NAME"))
	assert_ne(label.text, "BUILDING INTERIOR")


func test_building_scene_placeholder_is_not_english_only() -> void:
	var scene_text := ""
	var file := FileAccess.open("res://scenes/levels/BuildingLevel.tscn", FileAccess.READ)
	assert_not_null(file)
	while file and not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("text = "):
			scene_text = line.trim_prefix("text = ").strip_edges()
			break

	assert_eq(scene_text, "\"LEVEL_BUILDING_NAME\"")
	assert_ne(scene_text, "\"BUILDING INTERIOR\"")


func test_apply_level_label_from_node_creates_missing_level_label() -> void:
	var level_root := Node.new()
	add_child_autofree(level_root)
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "CanvasLayer"
	level_root.add_child(canvas_layer)
	var ui := Control.new()
	ui.name = "UI"
	canvas_layer.add_child(ui)

	_helper.apply_level_label_from_node(level_root, "res://scenes/levels/SewerLevel.tscn")

	var label: Label = ui.get_node_or_null("LevelLabel")
	assert_not_null(label)
	assert_eq(label.text, tr("LEVEL_SEWER_NAME"))


func test_building_locale_change_refreshes_cached_magazine_label() -> void:
	var building := BuildingLevelScript.new()
	add_child_autofree(building)

	var magazine_label := Label.new()
	building.set("_magazines_label", magazine_label)

	building.call("_update_magazines_label", ["[30]", "25", "10"])
	assert_eq(magazine_label.text, "%s: [30] | 25 | 10" % tr("ARMORY_STAT_MAG"))

	magazine_label.text = "MAGS: [30] | 25 | 10"
	building.call("_on_locale_changed", "ru")

	assert_eq(magazine_label.text, "%s: [30] | 25 | 10" % tr("ARMORY_STAT_MAG"))
	assert_ne(magazine_label.text, "MAGS: [30] | 25 | 10")


func test_building_debug_ui_refresh_updates_all_existing_hud_labels() -> void:
	var building := BuildingLevelScript.new()
	add_child_autofree(building)
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "CanvasLayer"
	building.add_child(canvas_layer)
	var ui := Control.new()
	ui.name = "UI"
	canvas_layer.add_child(ui)
	var level_label := Label.new()
	level_label.name = "LevelLabel"
	level_label.text = "Building Level"
	ui.add_child(level_label)
	var enemy_label := Label.new()
	enemy_label.name = "EnemyCountLabel"
	enemy_label.text = "Enemies: 10"
	ui.add_child(enemy_label)
	var ammo_label := Label.new()
	ammo_label.name = "AmmoLabel"
	ammo_label.text = "AMMO: 30/30"
	ui.add_child(ammo_label)

	building.set("_enemy_count_label", enemy_label)
	building.set("_ammo_label", ammo_label)
	building.set("_current_enemy_count", 10)
	building.call("_update_ammo_label_magazine", 30, 30)
	building.set("_last_magazine_ammo_counts", [30, 30, 30])

	building.call("_setup_debug_ui")

	var difficulty_label: Label = ui.get_node_or_null("DifficultyLabel")
	var magazines_label: Label = ui.get_node_or_null("MagazinesLabel")
	assert_not_null(difficulty_label)
	assert_not_null(magazines_label)
	assert_eq(level_label.text, tr("LEVEL_BUILDING_NAME"))
	assert_eq(enemy_label.text, tr("HUD_ENEMIES") % 10)
	assert_eq(ammo_label.text, tr("HUD_AMMO") % [30, 30])
	assert_eq(difficulty_label.text, tr("HUD_DIFFICULTY") % tr("NORMAL"))
	assert_eq(magazines_label.text, "%s: [30] | 30 | 30" % tr("ARMORY_STAT_MAG"))
	assert_ne(level_label.text, "Building Level")
	assert_ne(enemy_label.text, "Enemies: 10")
	assert_ne(ammo_label.text, "AMMO: 30/30")


func test_building_magazines_label_uses_current_weapon_before_inactive_shotgun_child() -> void:
	var building := BuildingLevelScript.new()
	add_child_autofree(building)
	var magazine_label := Label.new()
	building.set("_magazines_label", magazine_label)

	var player := Node2D.new()
	var shotgun := Node.new()
	shotgun.name = "Shotgun"
	shotgun.set("UsesTubeMagazine", true)
	player.add_child(shotgun)
	var assault_rifle := Node.new()
	assault_rifle.name = "AssaultRifle"
	assault_rifle.set("CurrentAmmo", 30)
	assault_rifle.set("ReserveAmmo", 30)
	player.add_child(assault_rifle)
	player.set("CurrentWeapon", assault_rifle)
	building.set("_player", player)
	building.add_child(player)

	building.call("_update_magazines_label", [30, 30])

	assert_true(magazine_label.visible)
	assert_eq(magazine_label.text, "%s: [30] | 30" % tr("ARMORY_STAT_MAG"))


func test_level_init_fallback_localizes_building_hud_source() -> void:
	var file := FileAccess.open("res://Scripts/Components/LevelInitFallback.cs", FileAccess.READ)
	assert_not_null(file)
	var source := file.get_as_text()

	assert_string_contains(source, "TranslationServer.Translate")
	assert_string_contains(source, "locale_changed")
	assert_string_contains(source, "OnLocaleChanged")
	assert_string_contains(source, "HUD_ENEMIES")
	assert_string_contains(source, "HUD_AMMO")
	assert_string_contains(source, "HUD_DIFFICULTY")
	assert_string_contains(source, "ARMORY_STAT_MAG")
	assert_string_contains(source, "GodotPercentFormat")
	assert_false(source.contains("string.Format(Tr(key), args)"))
	assert_false(source.contains("\"Enemies: "))
	assert_false(source.contains("\"AMMO: "))
	assert_false(source.contains("\"MAGS: "))
	assert_false(source.contains("\"Difficulty: "))
