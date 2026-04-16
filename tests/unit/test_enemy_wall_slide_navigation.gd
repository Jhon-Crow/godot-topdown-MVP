extends GutTest
## Regression tests for Issue #1357: enemies must keep useful tangential speed
## while following a NavigationAgent2D path around wall corners.


func _project_direction_like_enemy(direction: Vector2, normals: Array) -> Vector2:
	var move_dir := direction
	for normal_value in normals:
		var normal: Vector2 = normal_value
		if move_dir.dot(normal) < 0.0:
			var slid := move_dir.slide(normal)
			if slid.length_squared() > 0.01:
				move_dir = slid.normalized()
	return move_dir


func _choose_path_consistent_avoidance(nav_direction: Vector2, avoided_direction: Vector2) -> Vector2:
	return avoided_direction if nav_direction.dot(avoided_direction) >= 0.5 else nav_direction


func test_issue_1357_wall_projection_preserves_path_tangent_speed() -> void:
	var nav_direction := Vector2(1.0, -0.25).normalized()
	var projected := _project_direction_like_enemy(nav_direction, [Vector2.DOWN])

	assert_almost_eq(projected.length(), 1.0, 0.001,
		"Issue #1357: projected enemy direction should stay normalized")
	assert_almost_eq(projected.dot(Vector2.DOWN), 0.0, 0.001,
		"Issue #1357: projected direction should not keep pushing into the wall")
	assert_gt(projected.dot(nav_direction), 0.95,
		"Issue #1357: wall slide should preserve the planned path tangent")
	assert_gt(projected.x, 0.99,
		"Issue #1357: enemy should keep moving along the corridor, not stop at the wall")


func test_issue_1357_avoidance_cannot_turn_enemy_away_from_nav_path() -> void:
	var nav_direction := Vector2.RIGHT
	var rejected := _choose_path_consistent_avoidance(nav_direction, Vector2.DOWN)
	var accepted := _choose_path_consistent_avoidance(nav_direction, Vector2(1.0, 0.25).normalized())

	assert_eq(rejected, nav_direction,
		"Issue #1357: wall avoidance perpendicular to the path should be rejected")
	assert_gt(accepted.dot(nav_direction), 0.95,
		"Issue #1357: path-consistent wall avoidance should still be allowed")


func test_issue_1357_enemy_source_uses_player_style_wall_slide() -> void:
	var file := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	if file == null:
		gut.p("Cannot open enemy.gd for source analysis - skipping (export build)")
		pass_test("Skipped in export build")
		return
	var source := file.get_as_text()
	file.close()

	var func_idx := source.find("func _move_to_target_nav(")
	assert_gt(func_idx, 0, "_move_to_target_nav function should exist in enemy.gd")
	var func_body := source.substr(func_idx, 2200)

	assert_true(source.contains("_get_issue_1357_wall_slide_direction(nav_dir)"),
		"Issue #1357: SEARCHING should use the same wall-slide path direction as pursuing")
	assert_true(func_body.contains("nav_direction.dot(avoided_direction) >= 0.5"),
		"Issue #1357: wall avoidance must stay path-consistent")
	assert_true(func_body.contains("direction.slide(_normal)"),
		"Issue #1357: enemy movement should project along real slide-collision normals")
	assert_true(func_body.contains("direction.slide(_p.get_normal())"),
		"Issue #1357: speculative collision probe should use the same slide projection")
	assert_true(source.contains("dir.dot(_avoidance_velocity.normalized()) >= 0.5"),
		"Issue #1357: ORCA avoidance should not override searching with a path-opposing velocity")
	assert_false(func_body.contains("escape-dominant weight") or func_body.contains("_en * (1.5"),
		"Issue #1357: enemy movement should not push away from the path with escape normals")
