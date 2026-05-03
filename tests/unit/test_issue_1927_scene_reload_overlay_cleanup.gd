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


func test_player_defers_game_manager_weapon_replacement_from_ready() -> void:
	var source := _read_text_file("res://Scripts/Characters/Player.cs")

	assert_true(source.contains("CallDeferred(MethodName.ApplySelectedWeaponFromGameManager);"),
		"Player._Ready should defer selected-weapon replacement until scene startup is stable (Issue #1927)")
	assert_false(source.contains("\n        ApplySelectedWeaponFromGameManager();\n\n        // Store base positions"),
		"Player._Ready must not synchronously remove/free the scene-placed weapon during startup (Issue #1927)")


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


## Session 6: ensure file_logger flushes on every write during the startup
## window so a hard crash mid-reload still produces a usable log file.
func test_file_logger_flushes_immediately_during_startup_window() -> void:
	var source := _read_text_file("res://scripts/autoload/file_logger.gd")

	assert_true(source.contains("var _immediate_flush: bool = true"),
		"FileLogger should arm immediate-flush mode at startup (Issue #1927)")
	assert_true(source.contains("const IMMEDIATE_FLUSH_WINDOW_MSEC"),
		"FileLogger should declare a bounded immediate-flush window (Issue #1927)")
	assert_true(source.contains("func force_immediate_flush_window() -> void:"),
		"FileLogger should expose force_immediate_flush_window() so risky paths can re-arm it (Issue #1927)")
	assert_true(source.contains("func flush_now() -> void:"),
		"FileLogger should expose flush_now() for one-shot checkpoints (Issue #1927)")


func test_game_manager_arms_log_flush_before_scene_reload() -> void:
	var source := _read_text_file("res://scripts/autoload/game_manager.gd")

	assert_true(source.contains("force_immediate_flush_window"),
		"GameManager.restart_scene() should arm the file-logger immediate-flush window before reload (Issue #1927)")


## Session 6: deferred Revolver.SetupCylinderHUD must bail out if this revolver
## was already removed from the tree before the deferred call ran, otherwise
## touching the parent chain crashes natively.
func test_revolver_setup_cylinder_hud_guards_against_orphan_state() -> void:
	var source := _read_text_file("res://Scripts/Weapons/Revolver.cs")

	assert_true(source.contains("if (!IsInsideTree())"),
		"Revolver.SetupCylinderHUD should bail out when it is no longer inside the tree (Issue #1927)")


## Session 6: deferred Player.ApplySelectedWeaponFromGameManager must bail out
## if the player itself was removed before the deferred call ran.
func test_player_apply_selected_weapon_guards_against_orphan_state() -> void:
	var source := _read_text_file("res://Scripts/Characters/Player.cs")

	assert_true(
		source.contains("ApplySelectedWeaponFromGameManager entered (deferred)"),
		"Player.ApplySelectedWeaponFromGameManager should record a trace entry so deferred-call execution is observable (Issue #1927)"
	)


## Session 6: build_info.cfg must record the PR head SHA, not the synthetic
## merge commit produced by pull_request_target. Otherwise every uploaded log
## reports a Build commit value that does not exist on the PR branch.
func test_build_workflow_records_pr_head_sha() -> void:
	var source := _read_text_file("res://.github/workflows/build-windows.yml")

	assert_true(
		source.contains("github.event.pull_request.head.sha || github.sha"),
		"build-windows.yml should prefer pull_request.head.sha over github.sha so build_info.cfg matches the actual built code (Issue #1927)"
	)


## Session 7: the latest reporter logs stop immediately after ImpactEffects
## starts scene-change cleanup. ASVK and revolver both fire high-caliber rounds
## that commonly leave active pooled dust/light effects in the outgoing scene.
## Those pooled nodes belong to the autoload pool and must be reparented back
## before reload_current_scene() frees the old scene.
func test_impact_effects_restores_active_pooled_nodes_during_scene_reload() -> void:
	var source := _read_text_file("res://scripts/autoload/impact_effects_manager.gd")

	assert_true(
		source.contains("var _active_dust_effects: Array[GPUParticles2D] = []"),
		"ImpactEffects should track dust nodes checked out from the autoload pool (Issue #1927)"
	)
	assert_true(
		source.contains("_restore_active_pooled_effects_for_scene_reload()"),
		"ImpactEffects scene-change handler should restore pooled nodes before clearing stale references (Issue #1927)"
	)
	assert_true(
		source.contains("effect.reparent(self, false)"),
		"Active pooled dust effects must be moved back to the autoload during scene reload (Issue #1927)"
	)
	assert_true(
		source.contains("light.reparent(self, false)"),
		"Active pooled explosion lights must be moved back to the autoload during scene reload (Issue #1927)"
	)
	assert_true(
		source.contains("[trace] ImpactEffects scene change begin"),
		"ImpactEffects scene-change cleanup should emit trace lines for owner crash logs (Issue #1927)"
	)
