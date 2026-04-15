extends GutTest

const LevelLocalizationScript := preload("res://scripts/autoload/level_localization.gd")

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
	assert_eq(_helper.get_localized_difficulty_name("Power Fantasy"), tr("POWER_FANTASY"))
	assert_eq(_helper.get_localized_difficulty_name("Black Metal"), tr("BLACK_METAL"))
	assert_eq(_helper.get_difficulty_text("Power Fantasy"), tr("HUD_DIFFICULTY") % tr("POWER_FANTASY"))
	assert_eq(_helper.get_difficulty_text("Black Metal"), tr("HUD_DIFFICULTY") % tr("BLACK_METAL"))


func test_magazines_label_uses_translated_mag_prefix() -> void:
	assert_eq(_helper.get_magazines_text([]), "%s: -" % tr("ARMORY_STAT_MAG"))
	assert_eq(_helper.get_magazines_text(["[30]", "25", "10"]), "%s: [30] | 25 | 10" % tr("ARMORY_STAT_MAG"))


func test_apply_level_label_populates_top_right_label_text() -> void:
	var label := Label.new()
	add_child_autofree(label)

	_helper.apply_level_label(label, "res://scenes/levels/SewerLevel.tscn")

	assert_eq(label.text, tr("LEVEL_SEWER_NAME"))
