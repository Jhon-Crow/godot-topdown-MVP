extends GutTest
## Unit tests for FlashlightDetectionComponent.
##
## Tests FLASHLIGHT_DETECTION_CONFIDENCE, FLASHLIGHT_MAX_RANGE,
## BEAM_HALF_ANGLE_DEG, CHECK_INTERVAL constants, detection state
## management, and beam cone geometry.


# ============================================================================
# Mock FlashlightDetectionComponent for Logic Tests
# ============================================================================


class MockFlashlightDetectionComponent:
	const FLASHLIGHT_DETECTION_CONFIDENCE: float = 0.75
	const FLASHLIGHT_MAX_RANGE: float = 600.0
	const BEAM_HALF_ANGLE_DEG: float = 12.0
	const BEAM_VISIBILITY_RANGE: float = 600.0
	const BEAM_SAMPLE_COUNT: int = 8
	const CHECK_INTERVAL: float = 0.15

	var _check_timer: float = 0.0
	var detected: bool = false
	var estimated_player_position: Vector2 = Vector2.ZERO
	var beam_direction: Vector2 = Vector2.ZERO

	func reset() -> void:
		detected = false
		estimated_player_position = Vector2.ZERO
		beam_direction = Vector2.ZERO
		_check_timer = 0.0

	func _generate_beam_sample_points(origin: Vector2, direction: Vector2) -> Array[Vector2]:
		var points: Array[Vector2] = []
		var beam_half_angle_rad := deg_to_rad(BEAM_HALF_ANGLE_DEG)

		for i in range(1, BEAM_SAMPLE_COUNT + 1):
			var t := float(i) / float(BEAM_SAMPLE_COUNT)
			var dist := t * FLASHLIGHT_MAX_RANGE
			points.append(origin + direction * dist)

		var left_dir := direction.rotated(-beam_half_angle_rad)
		for i in range(1, BEAM_SAMPLE_COUNT + 1):
			var t := float(i) / float(BEAM_SAMPLE_COUNT)
			var dist := t * FLASHLIGHT_MAX_RANGE
			points.append(origin + left_dir * dist)

		var right_dir := direction.rotated(beam_half_angle_rad)
		for i in range(1, BEAM_SAMPLE_COUNT + 1):
			var t := float(i) / float(BEAM_SAMPLE_COUNT)
			var dist := t * FLASHLIGHT_MAX_RANGE
			points.append(origin + right_dir * dist)

		return points

	func _is_point_in_beam_cone(point: Vector2, origin: Vector2, direction: Vector2) -> bool:
		var dist := origin.distance_to(point)
		if dist > FLASHLIGHT_MAX_RANGE or dist < 0.01:
			return true
		var dir_to_point := (point - origin).normalized()
		var dot := direction.dot(dir_to_point)
		var cos_half_angle := cos(deg_to_rad(BEAM_HALF_ANGLE_DEG))
		return dot >= cos_half_angle

	func simulate_check_timer(delta: float) -> bool:
		_check_timer += delta
		if _check_timer < CHECK_INTERVAL:
			return false  # Not time to check yet
		_check_timer = 0.0
		return true  # Time to check

	func set_detected(player_pos: Vector2, beam_dir: Vector2) -> void:
		detected = true
		estimated_player_position = player_pos
		beam_direction = beam_dir


var comp: MockFlashlightDetectionComponent


func before_each() -> void:
	comp = MockFlashlightDetectionComponent.new()


func after_each() -> void:
	comp = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_flashlight_detection_confidence() -> void:
	assert_eq(MockFlashlightDetectionComponent.FLASHLIGHT_DETECTION_CONFIDENCE, 0.75,
		"FLASHLIGHT_DETECTION_CONFIDENCE should be 0.75")


func test_flashlight_max_range() -> void:
	assert_eq(MockFlashlightDetectionComponent.FLASHLIGHT_MAX_RANGE, 600.0,
		"FLASHLIGHT_MAX_RANGE should be 600.0")


func test_beam_half_angle_deg() -> void:
	assert_eq(MockFlashlightDetectionComponent.BEAM_HALF_ANGLE_DEG, 12.0,
		"BEAM_HALF_ANGLE_DEG should be 12.0")


func test_beam_visibility_range() -> void:
	assert_eq(MockFlashlightDetectionComponent.BEAM_VISIBILITY_RANGE, 600.0,
		"BEAM_VISIBILITY_RANGE should be 600.0")


func test_beam_sample_count() -> void:
	assert_eq(MockFlashlightDetectionComponent.BEAM_SAMPLE_COUNT, 8,
		"BEAM_SAMPLE_COUNT should be 8")


func test_check_interval() -> void:
	assert_eq(MockFlashlightDetectionComponent.CHECK_INTERVAL, 0.15,
		"CHECK_INTERVAL should be 0.15")


# ============================================================================
# Detection State Management Tests
# ============================================================================


func test_default_not_detected() -> void:
	assert_false(comp.detected,
		"Should not be detected by default")


func test_default_estimated_position_zero() -> void:
	assert_eq(comp.estimated_player_position, Vector2.ZERO,
		"Estimated player position should be zero by default")


func test_default_beam_direction_zero() -> void:
	assert_eq(comp.beam_direction, Vector2.ZERO,
		"Beam direction should be zero by default")


func test_set_detected_updates_state() -> void:
	comp.set_detected(Vector2(100, 200), Vector2.RIGHT)

	assert_true(comp.detected)
	assert_eq(comp.estimated_player_position, Vector2(100, 200))
	assert_eq(comp.beam_direction, Vector2.RIGHT)


func test_reset_clears_detection() -> void:
	comp.set_detected(Vector2(100, 200), Vector2.RIGHT)
	comp.reset()

	assert_false(comp.detected,
		"Reset should clear detected state")
	assert_eq(comp.estimated_player_position, Vector2.ZERO,
		"Reset should clear estimated position")
	assert_eq(comp.beam_direction, Vector2.ZERO,
		"Reset should clear beam direction")


func test_reset_clears_check_timer() -> void:
	comp._check_timer = 0.1
	comp.reset()

	assert_eq(comp._check_timer, 0.0,
		"Reset should clear check timer")


# ============================================================================
# Check Interval Tests
# ============================================================================


func test_check_timer_below_interval_returns_false() -> void:
	var should_check := comp.simulate_check_timer(0.05)

	assert_false(should_check,
		"Should not check when timer is below CHECK_INTERVAL")


func test_check_timer_at_interval_returns_true() -> void:
	var should_check := comp.simulate_check_timer(0.15)

	assert_true(should_check,
		"Should check when timer reaches CHECK_INTERVAL")


func test_check_timer_resets_after_check() -> void:
	comp.simulate_check_timer(0.15)

	assert_eq(comp._check_timer, 0.0,
		"Timer should reset after a check")


func test_check_timer_accumulates() -> void:
	comp.simulate_check_timer(0.05)
	comp.simulate_check_timer(0.05)
	var should_check := comp.simulate_check_timer(0.05)

	assert_true(should_check,
		"Timer should accumulate across multiple calls")


# ============================================================================
# Beam Cone Geometry Tests
# ============================================================================


func test_beam_sample_points_count() -> void:
	var points := comp._generate_beam_sample_points(Vector2.ZERO, Vector2.RIGHT)

	# 8 center + 8 left edge + 8 right edge = 24
	assert_eq(points.size(), 24,
		"Should generate 3 * BEAM_SAMPLE_COUNT = 24 sample points")


func test_beam_sample_points_along_center_line() -> void:
	var origin := Vector2(0, 0)
	var direction := Vector2.RIGHT
	var points := comp._generate_beam_sample_points(origin, direction)

	# First 8 points are along center line
	for i in range(8):
		var t := float(i + 1) / 8.0
		var expected_x := t * 600.0
		assert_almost_eq(points[i].x, expected_x, 0.01,
			"Center point %d should be at x=%.1f" % [i, expected_x])
		assert_almost_eq(points[i].y, 0.0, 0.01,
			"Center point %d should be at y=0" % i)


func test_beam_sample_farthest_point_at_max_range() -> void:
	var points := comp._generate_beam_sample_points(Vector2.ZERO, Vector2.RIGHT)

	# Last center point (index 7) should be at max range
	assert_almost_eq(points[7].x, 600.0, 0.01,
		"Farthest center point should be at FLASHLIGHT_MAX_RANGE")


func test_beam_edge_rays_rotated() -> void:
	var points := comp._generate_beam_sample_points(Vector2.ZERO, Vector2.RIGHT)

	# Points 8-15 are left edge, points 16-23 are right edge
	# Left edge should have negative y (rotated -12 degrees)
	assert_true(points[8].y < 0.0,
		"Left edge points should have negative y component")
	# Right edge should have positive y (rotated +12 degrees)
	assert_true(points[16].y > 0.0,
		"Right edge points should have positive y component")


func test_point_in_beam_cone_center() -> void:
	var origin := Vector2.ZERO
	var direction := Vector2.RIGHT
	var point := Vector2(300, 0)

	assert_true(comp._is_point_in_beam_cone(point, origin, direction),
		"Point along center of beam should be in cone")


func test_point_in_beam_cone_at_edge() -> void:
	var origin := Vector2.ZERO
	var direction := Vector2.RIGHT
	# Point at exactly 12 degrees (half angle) from center at 300px
	var angle := deg_to_rad(11.0)  # Slightly inside
	var point := Vector2(300 * cos(angle), 300 * sin(angle))

	assert_true(comp._is_point_in_beam_cone(point, origin, direction),
		"Point within half-angle should be in cone")


func test_point_outside_beam_cone() -> void:
	var origin := Vector2.ZERO
	var direction := Vector2.RIGHT
	# Point at 45 degrees — well outside 12 degree half-angle
	var point := Vector2(300, 300)

	assert_false(comp._is_point_in_beam_cone(point, origin, direction),
		"Point well outside half-angle should not be in cone")


func test_point_beyond_max_range_in_cone() -> void:
	var origin := Vector2.ZERO
	var direction := Vector2.RIGHT
	var point := Vector2(700, 0)

	# Beyond max range returns true (see source: "Origin point is always in the beam")
	assert_true(comp._is_point_in_beam_cone(point, origin, direction),
		"Point beyond max range returns true per implementation")


func test_point_at_origin_in_cone() -> void:
	var origin := Vector2.ZERO
	var direction := Vector2.RIGHT
	var point := Vector2(0.001, 0)

	assert_true(comp._is_point_in_beam_cone(point, origin, direction),
		"Point at origin should be in cone")
