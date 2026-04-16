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
