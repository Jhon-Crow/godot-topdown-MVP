extends GutTest
## Regression checks for Issue #1927 scene-reload crashes.
##
## The crash path is teardown-sensitive C# / engine behavior, so these tests
## guard the ownership contract in source: scene-owned weapon overlays must not
## be explicitly queue-freed while GameManager.reload_current_scene() is already
## tearing down the current scene.


func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	return file.get_as_text()


func test_game_manager_exposes_scene_reload_guard() -> void:
	var source := _read_text_file("res://scripts/autoload/game_manager.gd")

	assert_true(source.contains("func is_reloading_scene() -> bool:"),
		"GameManager should expose its scene reload guard to teardown-sensitive C# nodes")
	assert_true(source.contains("return _reloading"),
		"GameManager.is_reloading_scene() should return the existing reload guard")


func test_asvk_scope_overlay_is_not_queue_freed_during_scene_reload() -> void:
	var source := _read_text_file("res://Scripts/Weapons/SniperRifle.cs")

	assert_true(source.contains("bool isSceneReloading = IsSceneReloadInProgress();"),
		"ASVK _ExitTree should check whether GameManager is reloading the scene")
	assert_true(source.contains("DeactivateScope(queueFreeOverlay: !isSceneReloading, emitSignal: !isSceneReloading);"),
		"ASVK should not queue-free scene-owned scope overlay or emit teardown signals during scene reload")
	assert_true(source.contains("private void RemoveScopeOverlay(bool queueFreeOverlay = true)"),
		"Scope overlay removal should make explicit queue-free optional")
	assert_true(source.contains("if (queueFreeOverlay)"),
		"Scope overlay removal should only QueueFree when the caller owns the teardown")
	assert_true(source.contains("private bool IsSceneReloadInProgress()"),
		"ASVK should have a dedicated reload guard helper")


func test_revolver_hud_is_not_queue_freed_from_revolver_exit_tree() -> void:
	var source := _read_text_file("res://Scripts/Weapons/Revolver.cs")

	assert_false(source.contains("_cylinderUI.QueueFree();"),
		"Revolver must not queue-free the level-owned cylinder HUD during scene reload")


## Verifies that level scripts which load Revolver/SniperRifle scenes also
## include the duplicate-weapon protection check. Without it, C# Player._Ready()
## already instantiates the selected weapon via ApplySelectedWeaponFromGameManager;
## then the level's _setup_selected_weapon() instantiates a SECOND copy
## (Godot auto-renames it "Revolver2"/"SniperRifle2"), and EquipWeapon() removes
## the first one from the tree. The orphaned first instance still has deferred
## setup queued (Revolver: SetupCylinderHUD; SniperRifle: scope overlay) which
## fires after RemoveChild and hard-crashes the engine. This is the user-reported
## scenario from Issue #1927: "вылетает при выборе ASVK или револьвера".
func _assert_level_has_duplicate_weapon_guard(level_path: String, level_name: String) -> void:
	var source := _read_text_file(level_path)
	assert_true(
		source.contains("\"revolver\": \"Revolver\""),
		"%s weapon_names dict must include revolver to prevent duplicate Revolver instantiation (Issue #1927)" % level_name
	)
	assert_true(
		source.contains("\"sniper\": \"SniperRifle\""),
		"%s weapon_names dict must include sniper to prevent duplicate SniperRifle instantiation (Issue #1927)" % level_name
	)
	assert_true(
		source.contains("_player.get(\"CurrentWeapon\") == existing_weapon") \
			or source.contains("_player.get(\"CurrentWeapon\") == existing"),
		"%s must early-return when the C# Player has already equipped the selected weapon (Issue #1927)" % level_name
	)


func test_decadence_level_guards_against_duplicate_weapon_instantiation() -> void:
	_assert_level_has_duplicate_weapon_guard(
		"res://scripts/levels/decadence_level.gd", "decadence_level"
	)


func test_sewer_level_guards_against_duplicate_weapon_instantiation() -> void:
	_assert_level_has_duplicate_weapon_guard(
		"res://scripts/levels/sewer_level.gd", "sewer_level"
	)


func test_city_level_guards_against_duplicate_weapon_instantiation() -> void:
	_assert_level_has_duplicate_weapon_guard(
		"res://scripts/levels/city_level.gd", "city_level"
	)
