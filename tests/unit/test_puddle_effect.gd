extends GutTest
## Unit tests for puddle_effect.gd and puddle_manager.gd (Issue #1626).
##
## Tests puddle growth constants, visibility helpers, size-variation clamping,
## and the PuddleManager exclusion-zone logic — all using in-process mock
## objects so no scene tree is required.


# ============================================================================
# Mock PuddleEffect
# ============================================================================


class MockPuddleEffect:
	## Scale constants mirrored from puddle_effect.gd.
	const SMALL_SCALE: float = 0.4
	const MEDIUM_SCALE: float = 0.85
	## Each unbounded growth step adds this much scale.
	const GROWTH_STEP: float = 0.45
	const APPEAR_DURATION: float = 16.0
	const GROW_TO_MEDIUM_DURATION: float = 40.0
	const GROW_STEP_DURATION: float = 50.0

	var size_variation: float = 1.0
	var scale: Vector2 = Vector2.ZERO
	var modulate_a: float = 0.0
	var visible: bool = true
	var start_delay_randomise: float = 15.0
	var _current_scale: float = 0.0

	## Simulated ready: sets initial state.
	func ready() -> void:
		scale = Vector2.ZERO
		modulate_a = 0.0
		_current_scale = 0.0

	## Simulates hide_puddle.
	func hide_puddle() -> void:
		visible = false

	## Simulates show_puddle.
	func show_puddle() -> void:
		visible = true

	## Returns the target scale for a given phase (1=small, 2=medium).
	## Phase 3+ uses unbounded steps tracked via _current_scale.
	func target_scale_for_phase(phase: int) -> Vector2:
		match phase:
			1:
				return Vector2.ONE * SMALL_SCALE * size_variation
			2:
				return Vector2.ONE * MEDIUM_SCALE * size_variation
		return Vector2.ZERO

	## Simulates one unbounded growth step (phase 3+).
	func simulate_growth_step() -> Vector2:
		_current_scale += GROWTH_STEP * size_variation
		return Vector2.ONE * _current_scale


# ============================================================================
# Mock PuddleManager
# ============================================================================


class MockPuddleManager:
	## Exclusion zones mirrored from puddle_manager.gd.
	const EXCLUSION_ZONES: Array = [
		# CranePlatform: center (400,500), floor ±200x±150
		[Vector2(185, 335), Vector2(430, 330)],
		# WarehouseA: center (400,1800), floor ±250x±300
		[Vector2(135, 1485), Vector2(530, 630)],
		# WarehouseB: center (4400,2800), floor ±350x±400
		[Vector2(4035, 2385), Vector2(730, 830)],
		# ContainerYardA — Container1 at (3800,400), ±100x±40
		[Vector2(3690, 350), Vector2(220, 100)],
		# ContainerYardA — Container2 at (3800,550), ±100x±40
		[Vector2(3690, 500), Vector2(220, 100)],
		# ContainerYardA — Container3 at (4200,450), ±100x±40
		[Vector2(4090, 400), Vector2(220, 100)],
		# ContainerYardA — Container4 at (4600,380), ±100x±40
		[Vector2(4490, 330), Vector2(220, 100)],
		# ContainerYardB — Container1 at (400,2800), ±100x±40
		[Vector2(290, 2750), Vector2(220, 100)],
		# ContainerYardB — Container2 at (400,2950), ±100x±40
		[Vector2(290, 2900), Vector2(220, 100)],
		# ContainerYardB — Container3 at (400,3100), ±100x±40
		[Vector2(290, 3050), Vector2(220, 100)],
		# LoadingDock — Container1 at (3600,1600), ±100x±40
		[Vector2(3490, 1550), Vector2(220, 100)],
		# LoadingDock — Container2 at (4000,1550), ±100x±40
		[Vector2(3890, 1500), Vector2(220, 100)],
		# LoadingDock — Container3 at (4400,1650), ±100x±40
		[Vector2(4290, 1600), Vector2(220, 100)],
		# LoadingDock — Container4 at (3800,1750), ±100x±40
		[Vector2(3690, 1700), Vector2(220, 100)],
	]

	const SIZE_VARIATION_MIN: float = 0.7
	const SIZE_VARIATION_MAX: float = 1.3

	var spawned_positions: Array[Vector2] = []
	var excluded_positions: Array[Vector2] = []

	## Simulates _is_in_exclusion_zone.
	func is_in_exclusion_zone(point: Vector2) -> bool:
		for zone in EXCLUSION_ZONES:
			var rect := Rect2(zone[0], zone[1])
			if rect.has_point(point):
				return true
		return false

	## Simulates spawning: records whether each position was excluded.
	func simulate_spawn(positions: Array) -> void:
		spawned_positions.clear()
		excluded_positions.clear()
		for pos in positions:
			if is_in_exclusion_zone(pos):
				excluded_positions.append(pos)
			else:
				spawned_positions.append(pos)


# ============================================================================
# Setup / Teardown
# ============================================================================


var puddle: MockPuddleEffect
var manager: MockPuddleManager


func before_each() -> void:
	puddle = MockPuddleEffect.new()
	manager = MockPuddleManager.new()


func after_each() -> void:
	puddle = null
	manager = null


# ============================================================================
# PuddleEffect – initial state
# ============================================================================


func test_puddle_starts_invisible_on_ready() -> void:
	puddle.ready()
	assert_eq(puddle.modulate_a, 0.0,
		"Puddle should start fully transparent")


func test_puddle_starts_at_zero_scale_on_ready() -> void:
	puddle.ready()
	assert_eq(puddle.scale, Vector2.ZERO,
		"Puddle should start at zero scale so it is not visible")


func test_puddle_is_visible_by_default() -> void:
	assert_true(puddle.visible,
		"Puddle node should be visible by default (scale controls appearance)")


# ============================================================================
# PuddleEffect – growth constants
# ============================================================================


func test_small_scale_constant() -> void:
	assert_almost_eq(MockPuddleEffect.SMALL_SCALE, 0.4, 0.001,
		"SMALL_SCALE should be 0.4")


func test_medium_scale_constant() -> void:
	assert_almost_eq(MockPuddleEffect.MEDIUM_SCALE, 0.85, 0.001,
		"MEDIUM_SCALE should be 0.85")


func test_growth_step_positive() -> void:
	assert_true(MockPuddleEffect.GROWTH_STEP > 0.0,
		"GROWTH_STEP must be positive for unbounded growth")


func test_scale_phases_are_ordered() -> void:
	assert_true(
		MockPuddleEffect.SMALL_SCALE < MockPuddleEffect.MEDIUM_SCALE,
		"SMALL_SCALE must be less than MEDIUM_SCALE")


func test_unbounded_growth_increases_scale() -> void:
	# Each step should produce a larger scale than the last.
	puddle.ready()
	var step1 := puddle.simulate_growth_step()
	var step2 := puddle.simulate_growth_step()
	assert_true(step2.x > step1.x,
		"Each growth step should produce a larger scale (unbounded)")


func test_unbounded_growth_no_cap() -> void:
	# After many steps the scale should exceed what old LARGE_SCALE (1.4) was.
	puddle.ready()
	var final_scale := Vector2.ZERO
	for _i in range(10):
		final_scale = puddle.simulate_growth_step()
	assert_true(final_scale.x > 2.0,
		"After 10 growth steps scale should exceed 2.0 (no upper cap)")


# ============================================================================
# PuddleEffect – target scale respects size_variation
# ============================================================================


func test_target_scale_phase1_default_variation() -> void:
	var expected := Vector2.ONE * MockPuddleEffect.SMALL_SCALE
	var actual := puddle.target_scale_for_phase(1)
	assert_almost_eq(actual.x, expected.x, 0.001,
		"Phase-1 target scale X should equal SMALL_SCALE when variation=1")
	assert_almost_eq(actual.y, expected.y, 0.001,
		"Phase-1 target scale Y should equal SMALL_SCALE when variation=1")


func test_target_scale_phase2_default_variation() -> void:
	var expected := Vector2.ONE * MockPuddleEffect.MEDIUM_SCALE
	var actual := puddle.target_scale_for_phase(2)
	assert_almost_eq(actual.x, expected.x, 0.001,
		"Phase-2 target scale should equal MEDIUM_SCALE when variation=1")


func test_target_scale_with_size_variation() -> void:
	puddle.size_variation = 1.2
	var step := puddle.simulate_growth_step()
	var expected_x := MockPuddleEffect.GROWTH_STEP * 1.2
	assert_almost_eq(step.x, expected_x, 0.001,
		"Growth step scale should be multiplied by size_variation")


func test_target_scale_with_small_variation() -> void:
	puddle.size_variation = 0.7
	var actual := puddle.target_scale_for_phase(1)
	var expected_x := MockPuddleEffect.SMALL_SCALE * 0.7
	assert_almost_eq(actual.x, expected_x, 0.001,
		"Phase-1 scale should be reduced by size_variation < 1")


# ============================================================================
# PuddleEffect – hide / show helpers
# ============================================================================


func test_hide_puddle_sets_invisible() -> void:
	puddle.hide_puddle()
	assert_false(puddle.visible,
		"hide_puddle() should make the puddle invisible")


func test_show_puddle_restores_visibility() -> void:
	puddle.hide_puddle()
	puddle.show_puddle()
	assert_true(puddle.visible,
		"show_puddle() should make the puddle visible again")


# ============================================================================
# PuddleEffect – duration constants sanity checks
# ============================================================================


func test_appear_duration_positive() -> void:
	assert_true(MockPuddleEffect.APPEAR_DURATION > 0.0,
		"APPEAR_DURATION must be positive")


func test_grow_to_medium_duration_positive() -> void:
	assert_true(MockPuddleEffect.GROW_TO_MEDIUM_DURATION > 0.0,
		"GROW_TO_MEDIUM_DURATION must be positive")


func test_grow_step_duration_positive() -> void:
	assert_true(MockPuddleEffect.GROW_STEP_DURATION > 0.0,
		"GROW_STEP_DURATION must be positive")


func test_grow_durations_are_slower_than_original() -> void:
	# Durations should be at least 2x the original values to confirm half speed.
	assert_true(MockPuddleEffect.APPEAR_DURATION >= 16.0,
		"APPEAR_DURATION should be at least 16 s (half speed vs original 8 s)")
	assert_true(MockPuddleEffect.GROW_TO_MEDIUM_DURATION >= 40.0,
		"GROW_TO_MEDIUM_DURATION should be at least 40 s (half speed vs original 20 s)")
	assert_true(MockPuddleEffect.GROW_STEP_DURATION >= 50.0,
		"GROW_STEP_DURATION should be at least 50 s (half speed vs original 25 s)")


# ============================================================================
# PuddleManager – exclusion zone logic
# ============================================================================


func test_warehouse_a_center_is_excluded() -> void:
	# WarehouseA is at center (400, 1800)
	var inside_a := Vector2(400, 1800)
	assert_true(manager.is_in_exclusion_zone(inside_a),
		"WarehouseA center should be inside exclusion zone")


func test_warehouse_b_center_is_excluded() -> void:
	# WarehouseB is at center (4400, 2800)
	var inside_b := Vector2(4400, 2800)
	assert_true(manager.is_in_exclusion_zone(inside_b),
		"WarehouseB center should be inside exclusion zone")


func test_crane_platform_center_is_excluded() -> void:
	# CranePlatform is at center (400, 500)
	var crane_center := Vector2(400, 500)
	assert_true(manager.is_in_exclusion_zone(crane_center),
		"CranePlatform center should be inside exclusion zone")


func test_container_yard_a_container_is_excluded() -> void:
	# Container1 in ContainerYardA is at (3800, 400)
	var on_container := Vector2(3800, 400)
	assert_true(manager.is_in_exclusion_zone(on_container),
		"Position on ContainerYardA container should be excluded")


func test_outdoor_position_not_excluded() -> void:
	var outdoor := Vector2(2500, 2000)
	assert_false(manager.is_in_exclusion_zone(outdoor),
		"Open outdoor position should not be in any exclusion zone")


func test_position_outside_crane_not_excluded() -> void:
	# Position clearly outside the CranePlatform zone
	var outside_crane := Vector2(750, 350)
	assert_false(manager.is_in_exclusion_zone(outside_crane),
		"Position outside CranePlatform should not be excluded")


func test_loading_dock_open_area_not_excluded() -> void:
	var dock := Vector2(4150, 1380)
	assert_false(manager.is_in_exclusion_zone(dock),
		"Loading dock open area position should not be excluded")


func test_spawn_skips_excluded_positions() -> void:
	var positions: Array = [
		Vector2(400, 1800),   # inside WarehouseA
		Vector2(2500, 1000),  # outdoor
		Vector2(4400, 2800),  # inside WarehouseB
		Vector2(1500, 400),   # outdoor
	]
	manager.simulate_spawn(positions)

	assert_eq(manager.excluded_positions.size(), 2,
		"Exactly 2 positions (both warehouses) should be excluded")
	assert_eq(manager.spawned_positions.size(), 2,
		"Exactly 2 outdoor positions should be spawned")


func test_all_outdoor_positions_allowed() -> void:
	var outdoor_positions: Array = [
		Vector2(1200, 340),
		Vector2(1700, 390),
		Vector2(3750, 1480),
		Vector2(2500, 3400),
	]
	manager.simulate_spawn(outdoor_positions)

	assert_eq(manager.excluded_positions.size(), 0,
		"No outdoor positions should be excluded")
	assert_eq(manager.spawned_positions.size(), outdoor_positions.size(),
		"All outdoor positions should be spawned")


# ============================================================================
# PuddleManager – size variation range
# ============================================================================


func test_size_variation_min_less_than_max() -> void:
	assert_true(
		MockPuddleManager.SIZE_VARIATION_MIN < MockPuddleManager.SIZE_VARIATION_MAX,
		"SIZE_VARIATION_MIN must be less than SIZE_VARIATION_MAX")


func test_size_variation_min_is_reasonable() -> void:
	assert_true(MockPuddleManager.SIZE_VARIATION_MIN >= 0.5,
		"SIZE_VARIATION_MIN should be >= 0.5 to avoid invisible puddles")


func test_size_variation_max_is_reasonable() -> void:
	assert_true(MockPuddleManager.SIZE_VARIATION_MAX <= 2.0,
		"SIZE_VARIATION_MAX should be <= 2.0 to avoid excessively large puddles")


# ============================================================================
# PuddleManager – white rectangle regression and merge shader approach
#
# Architecture: PuddleManager is a plain Node2D. It creates an internal
# CanvasGroup child (_puddle_group) and places all puddle Sprite2Ds inside it.
# A puddle_merge.gdshader is loaded from a .tres resource and attached to that
# CanvasGroup child — this clamps composited alpha so overlapping puddles look
# merged rather than stacked (the "unrealistic darkening at junctions" fix).
#
# The shader reads only TEXTURE (the CanvasGroup's own composited buffer),
# not hint_screen_texture, so it is safe on the gl_compatibility renderer
# and cannot draw a white bounding rectangle.
# ============================================================================


func test_puddle_manager_scene_uses_node2d_not_canvas_group() -> void:
	var f := FileAccess.open("res://scenes/levels/DocksLevel.tscn", FileAccess.READ)
	assert_not_null(f, "DocksLevel.tscn must be readable")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	assert_true(src.contains("[node name=\"PuddleManager\" type=\"Node2D\""),
		"PuddleManager root node must be Node2D in DocksLevel.tscn")
	assert_false(src.contains("[node name=\"PuddleManager\" type=\"CanvasGroup\""),
		"PuddleManager root node must not be CanvasGroup in DocksLevel.tscn")


func test_puddle_manager_script_extends_node2d() -> void:
	var f := FileAccess.open("res://scripts/levels/puddle_manager.gd", FileAccess.READ)
	assert_not_null(f, "puddle_manager.gd must be readable")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	assert_true(src.begins_with("extends Node2D"),
		"PuddleManager must extend Node2D (not CanvasGroup) to avoid white bounding quad")
	assert_false(src.contains("extends CanvasGroup"),
		"PuddleManager must not extend CanvasGroup")


func test_puddle_manager_uses_canvas_group_child_for_merge() -> void:
	var f := FileAccess.open("res://scripts/levels/puddle_manager.gd", FileAccess.READ)
	assert_not_null(f, "puddle_manager.gd must be readable")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	assert_true(src.contains("CanvasGroup.new()"),
		"PuddleManager must create an internal CanvasGroup child for alpha-clamp compositing")
	assert_true(src.contains("PUDDLE_MERGE_MATERIAL_PATH"),
		"PuddleManager must load the merge material resource for the CanvasGroup child")


func test_merge_shader_file_exists() -> void:
	var f := FileAccess.open("res://scripts/shaders/puddle_merge.gdshader", FileAccess.READ)
	assert_not_null(f, "puddle_merge.gdshader must exist for alpha-clamp compositing")
	if f != null:
		f.close()


func test_merge_shader_reads_canvas_group_texture_not_screen() -> void:
	var f := FileAccess.open("res://scripts/shaders/puddle_merge.gdshader", FileAccess.READ)
	assert_not_null(f, "puddle_merge.gdshader must be readable")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	assert_true(src.contains("texture(TEXTURE, UV)"),
		"Merge shader must read TEXTURE (CanvasGroup composite), not SCREEN_TEXTURE")
	assert_false(src.contains("hint_screen_texture"),
		"Merge shader must not use hint_screen_texture — it caused white-square bug on gl_compatibility")


func test_merge_shader_clamps_alpha_to_max() -> void:
	var f := FileAccess.open("res://scripts/shaders/puddle_merge.gdshader", FileAccess.READ)
	assert_not_null(f, "puddle_merge.gdshader must be readable")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	assert_true(src.contains("max_alpha"),
		"Merge shader must declare a max_alpha uniform to clamp overlapping puddle opacity")
	assert_true(src.contains("min(c.a, max_alpha)"),
		"Merge shader must clamp the composited alpha using min(c.a, max_alpha)")


func test_merge_shader_early_outs_for_fully_transparent_pixels() -> void:
	var f := FileAccess.open("res://scripts/shaders/puddle_merge.gdshader", FileAccess.READ)
	assert_not_null(f, "puddle_merge.gdshader must be readable")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	assert_true(src.contains("c.a < 0.001"),
		"Merge shader must early-out for transparent pixels so the CanvasGroup bounding quad is invisible")


func test_merge_material_resource_exists() -> void:
	var f := FileAccess.open("res://resources/materials/puddle_merge_material.tres", FileAccess.READ)
	assert_not_null(f, "puddle_merge_material.tres must exist for runtime material loading")
	if f != null:
		f.close()
