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
	const LARGE_SCALE: float = 1.4
	const APPEAR_DURATION: float = 8.0
	const GROW_TO_MEDIUM_DURATION: float = 20.0
	const GROW_TO_LARGE_DURATION: float = 25.0

	var size_variation: float = 1.0
	var scale: Vector2 = Vector2.ZERO
	var modulate_a: float = 0.0
	var visible: bool = true
	var start_delay_randomise: float = 10.0

	## Simulated ready: sets initial state.
	func ready() -> void:
		scale = Vector2.ZERO
		modulate_a = 0.0

	## Simulates hide_puddle.
	func hide_puddle() -> void:
		visible = false

	## Simulates show_puddle.
	func show_puddle() -> void:
		visible = true

	## Returns the target scale for a given phase (1=small, 2=medium, 3=large).
	func target_scale_for_phase(phase: int) -> Vector2:
		match phase:
			1:
				return Vector2.ONE * SMALL_SCALE * size_variation
			2:
				return Vector2.ONE * MEDIUM_SCALE * size_variation
			3:
				return Vector2.ONE * LARGE_SCALE * size_variation
		return Vector2.ZERO


# ============================================================================
# Mock PuddleManager
# ============================================================================


class MockPuddleManager:
	## Exclusion zones mirrored from puddle_manager.gd.
	const EXCLUSION_ZONES: Array = [
		[Vector2(130, 1480), Vector2(540, 640)],   # WarehouseA
		[Vector2(4030, 2380), Vector2(740, 840)],   # WarehouseB
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


func test_large_scale_constant() -> void:
	assert_almost_eq(MockPuddleEffect.LARGE_SCALE, 1.4, 0.001,
		"LARGE_SCALE should be 1.4")


func test_scale_phases_are_ordered() -> void:
	assert_true(
		MockPuddleEffect.SMALL_SCALE < MockPuddleEffect.MEDIUM_SCALE,
		"SMALL_SCALE must be less than MEDIUM_SCALE")
	assert_true(
		MockPuddleEffect.MEDIUM_SCALE < MockPuddleEffect.LARGE_SCALE,
		"MEDIUM_SCALE must be less than LARGE_SCALE")


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


func test_target_scale_phase3_default_variation() -> void:
	var expected := Vector2.ONE * MockPuddleEffect.LARGE_SCALE
	var actual := puddle.target_scale_for_phase(3)
	assert_almost_eq(actual.x, expected.x, 0.001,
		"Phase-3 target scale should equal LARGE_SCALE when variation=1")


func test_target_scale_with_size_variation() -> void:
	puddle.size_variation = 1.2
	var actual := puddle.target_scale_for_phase(3)
	var expected_x := MockPuddleEffect.LARGE_SCALE * 1.2
	assert_almost_eq(actual.x, expected_x, 0.001,
		"Phase-3 scale should be multiplied by size_variation")


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


func test_grow_to_large_duration_positive() -> void:
	assert_true(MockPuddleEffect.GROW_TO_LARGE_DURATION > 0.0,
		"GROW_TO_LARGE_DURATION must be positive")


# ============================================================================
# PuddleManager – exclusion zone logic
# ============================================================================


func test_warehouse_a_center_is_excluded() -> void:
	# WarehouseA is at ~(400, 1800); zone rect starts at (130, 1480) size (540, 640)
	var inside_a := Vector2(400, 1800)
	assert_true(manager.is_in_exclusion_zone(inside_a),
		"WarehouseA center should be inside exclusion zone")


func test_warehouse_b_center_is_excluded() -> void:
	# WarehouseB is at ~(4400, 2800); zone rect starts at (4030, 2380) size (740, 840)
	var inside_b := Vector2(4400, 2800)
	assert_true(manager.is_in_exclusion_zone(inside_b),
		"WarehouseB center should be inside exclusion zone")


func test_outdoor_position_not_excluded() -> void:
	var outdoor := Vector2(2500, 2000)
	assert_false(manager.is_in_exclusion_zone(outdoor),
		"Open outdoor position should not be in any exclusion zone")


func test_crane_platform_not_excluded() -> void:
	var crane := Vector2(400, 420)
	assert_false(manager.is_in_exclusion_zone(crane),
		"Crane platform area should not be inside WarehouseA exclusion zone")


func test_loading_dock_not_excluded() -> void:
	var dock := Vector2(4150, 1380)
	assert_false(manager.is_in_exclusion_zone(dock),
		"Loading dock position should not be excluded")


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
		Vector2(280, 420),
		Vector2(1100, 340),
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
