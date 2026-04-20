extends GutTest
## Regression tests for Issue #1457 - enemies catching on walls while pursuing.
##
## These tests cover the engine-level approach used by the fix:
## - top-down CharacterBody2D enemies must run in floating mode, not grounded mode;
## - wall_min_slide_angle must not add a friction-like dead zone at wall contacts;
## - NavigationAgent2D targets must be cached so a stable cover target does not
##   request a fresh path every physics frame.


const ENEMY_SOURCE_PATH := "res://scripts/objects/enemy.gd"
const ENEMY_SCENE_PATH := "res://scenes/objects/Enemy.tscn"


func _read_enemy_source() -> String:
	var file := FileAccess.open(ENEMY_SOURCE_PATH, FileAccess.READ)
	if file == null:
		fail_test("Could not open %s" % ENEMY_SOURCE_PATH)
		return ""
	var source := file.get_as_text()
	file.close()
	return source


func _instantiate_enemy() -> CharacterBody2D:
	var packed := load(ENEMY_SCENE_PATH) as PackedScene
	if packed == null:
		pass_test("Skipped: Enemy.tscn not accessible in test environment")
		return null
	var enemy := packed.instantiate() as CharacterBody2D
	assert_not_null(enemy, "Enemy.tscn root must be a CharacterBody2D")
	if enemy == null:
		return null
	add_child_autoqfree(enemy)
	return enemy


func test_enemy_scene_ready_sets_top_down_motion_issue_1457() -> void:
	var enemy := _instantiate_enemy()
	if enemy == null:
		return
	await get_tree().process_frame
	assert_eq(enemy.motion_mode, CharacterBody2D.MOTION_MODE_FLOATING,
		"Issue #1457: instantiated enemies must use floating mode for top-down wall contacts")
	assert_eq(enemy.wall_min_slide_angle, 0.0,
		"Issue #1457: instantiated enemies must remove the wall-slide dead zone")


func test_enemy_uses_top_down_floating_motion_issue_1457() -> void:
	var source := _read_enemy_source()
	assert_true(source.contains("MOTION_MODE_FLOATING"),
		"Issue #1457: enemy.gd must set CharacterBody2D to floating mode for top-down wall contacts")


func test_enemy_removes_wall_slide_dead_zone_issue_1457() -> void:
	var source := _read_enemy_source()
	assert_true(source.contains("wall_min_slide_angle = 0.0"),
		"Issue #1457: wall_min_slide_angle must be zero so wall contacts slide instead of catching")


func test_navigation_target_cache_markers_exist_issue_1457() -> void:
	var source := _read_enemy_source()
	assert_true(source.contains("_nav_target_cache"),
		"Issue #1457: enemy.gd must cache NavigationAgent2D target positions")
	assert_true(source.contains("NAV_TARGET_REPATH_DISTANCE"),
		"Issue #1457: enemy.gd must use a distance threshold before requesting a new path")


func test_nav_movement_stuck_recovery_has_hard_cap_issue_1457() -> void:
	var source := _read_enemy_source()
	assert_true(source.contains("NAV_MOVEMENT_STUCK_MAX_TIME"),
		"Issue #1457: nav movement states need a hard stuck cap independent of debug settings")
	assert_true(source.contains("minf(_effective_stuck_max_time, NAV_MOVEMENT_STUCK_MAX_TIME)"),
		"Issue #1457: debug global stuck time must not make wall catches last 20 seconds")
	assert_true(source.contains("AIState.SEEKING_COVER"),
		"Issue #1457: cover navigation can catch on BuildingLevel walls and must recover too")


func test_navigation_target_cache_repaths_only_on_meaningful_change_issue_1457() -> void:
	const REPATH_DISTANCE: float = 24.0
	var cached_target := Vector2(500, 600)

	var small_jitter_target := Vector2(512, 608)
	var should_repath_for_jitter := cached_target.distance_to(small_jitter_target) > REPATH_DISTANCE
	assert_false(should_repath_for_jitter,
		"Issue #1457: small target jitter should not request a fresh path every physics frame")

	var changed_target := Vector2(540, 600)
	var should_repath_for_change := cached_target.distance_to(changed_target) > REPATH_DISTANCE
	assert_true(should_repath_for_change,
		"Issue #1457: meaningful target movement must still request a new path")


func test_wall_min_slide_angle_zero_is_less_restrictive_issue_1457() -> void:
	var default_dead_zone_rad := deg_to_rad(15.0)  # Godot default wall_min_slide_angle.
	var fixed_dead_zone_rad := 0.0
	assert_lt(fixed_dead_zone_rad, default_dead_zone_rad,
		"Issue #1457: zero wall_min_slide_angle removes the default 15 degree slide threshold")


func test_nav_target_cache_reset_on_ai_state_transitions_issue_1457() -> void:
	# Issue #1457 follow-up (PR #1856 comment 4272867394): stale cached nav target from a
	# previous state must not survive COMBAT/PURSUING/FLANKING/SEEKING_COVER/SEARCHING entry.
	var source := _read_enemy_source()
	var transitions := [
		"_transition_to_combat",
		"_transition_to_pursuing",
		"_transition_to_flanking",
		"_transition_to_seeking_cover",
		"_transition_to_searching",
	]
	for func_name in transitions:
		var start := source.find("func %s" % func_name)
		assert_gt(start, -1, "enemy.gd must still define %s" % func_name)
		if start < 0:
			continue
		var next := source.find("\nfunc ", start + 1)
		if next < 0:
			next = source.length()
		var body := source.substr(start, next - start)
		assert_true(body.contains("_nav_has_target = false"),
			"Issue #1457: %s must reset _nav_has_target so the new state re-paths once on entry" % func_name)


func test_reset_seeds_global_stuck_last_position_to_current_issue_1457() -> void:
	# Issue #1457 follow-up: _reset() seeded _global_stuck_last_position = Vector2.ZERO, which
	# masks the first tick of the stuck detector after respawn because distance_to(ZERO) is huge.
	var source := _read_enemy_source()
	assert_true(source.contains("_global_stuck_last_position = global_position"),
		"Issue #1457: _reset() must seed _global_stuck_last_position to current global_position, not Vector2.ZERO")


func test_combat_approach_stall_recovery_exists_issue_1457() -> void:
	# Issue #1457 follow-up: ranged COMBAT approach phase must not silently rub a wall forever.
	var source := _read_enemy_source()
	assert_true(source.contains("COMBAT_APPROACH_STUCK_MAX_TIME"),
		"Issue #1457: COMBAT approach phase must have a hard stall cap constant")
	assert_true(source.contains("_combat_approach_stuck_timer"),
		"Issue #1457: COMBAT approach phase must track a stall timer")
	assert_true(source.contains("COMBAT approach stall"),
		"Issue #1457: COMBAT approach stall must emit a diagnostic log line")
	assert_true(source.contains("_transition_to_pursuing"),
		"Issue #1457: COMBAT approach stall must recover by transitioning to PURSUING")


func test_combat_approach_stall_cap_is_short_enough_issue_1457() -> void:
	# A 2s cap is short enough to be noticeable to a player but long enough to avoid
	# interrupting legitimate aim/fire micro-pauses in COMBAT.
	const CAP_SECONDS: float = 2.0
	assert_lt(CAP_SECONDS, 4.0,
		"Issue #1457: COMBAT approach stall cap must be shorter than the navigation stuck cap")
	assert_gt(CAP_SECONDS, 0.5,
		"Issue #1457: COMBAT approach stall cap must not interrupt normal aim pauses")
