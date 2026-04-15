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
	assert_eq(_helper.get_difficulty_text("Hard"), tr("HUD_DIFFICULTY") % "Hard")


func test_known_level_name_translations_resolve_for_bidirectional_locales() -> void:
	assert_eq(_helper.get_level_display_name("res://scenes/levels/TestTier.tscn"), tr("LEVEL_POLYGON_NAME"))
	assert_eq(_helper.get_level_display_name("res://scenes/levels/CastleLevel.tscn"), tr("LEVEL_CASTLE_NAME"))
	assert_eq(_helper.get_level_display_name("res://scenes/levels/SewerLevel.tscn"), tr("LEVEL_SEWER_NAME"))


func test_apply_level_label_populates_top_right_label_text() -> void:
	var label := Label.new()
	add_child_autofree(label)

	_helper.apply_level_label(label, "res://scenes/levels/SewerLevel.tscn")

	assert_eq(label.text, tr("LEVEL_SEWER_NAME"))
