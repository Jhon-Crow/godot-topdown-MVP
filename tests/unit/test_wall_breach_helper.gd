extends GutTest
## Unit tests for wall_breach_helper.gd wall breach carving utility.
##
## Tests breach passage width, minimum segment size, and related constants.


# ============================================================================
# Mock WallBreachHelper for Logic Tests
# ============================================================================


class MockWallBreachHelper:
	## Width of the passage carved through a wall (pixels).
	const BREACH_PASSAGE_WIDTH: float = 120.0

	## Minimum segment length to keep after splitting.
	const MIN_SEGMENT_SIZE: float = 8.0

	## Metadata key for dynamic nodes.
	const DYNAMIC_NODE_META: String = "wall_breach_dynamic"

	## Check if a segment is large enough to keep.
	static func is_segment_valid(size: float) -> bool:
		return size >= MIN_SEGMENT_SIZE

	## Calculate left/right segment widths for a horizontal breach.
	## Returns [left_width, right_width].
	static func calculate_horizontal_segments(
		wall_width: float, breach_local_x: float
	) -> Array[float]:
		var half_w: float = wall_width * 0.5
		var half_breach: float = BREACH_PASSAGE_WIDTH * 0.5

		# Clamp breach center
		var bx: float = clampf(breach_local_x,
			-half_w + half_breach, half_w - half_breach)

		var left_end: float = bx - half_breach
		var right_start: float = bx + half_breach

		var left_width: float = left_end + half_w
		var right_width: float = half_w - right_start

		return [left_width, right_width]

	## Check if a wall is too thin to split (shorter than passage width).
	static func is_wall_too_thin(wall_size: float) -> bool:
		return wall_size < BREACH_PASSAGE_WIDTH


# ============================================================================
# Constant Tests
# ============================================================================


func test_breach_passage_width() -> void:
	assert_eq(MockWallBreachHelper.BREACH_PASSAGE_WIDTH, 120.0,
		"BREACH_PASSAGE_WIDTH should be 120.0 pixels")


func test_min_segment_size() -> void:
	assert_eq(MockWallBreachHelper.MIN_SEGMENT_SIZE, 8.0,
		"MIN_SEGMENT_SIZE should be 8.0 pixels")


func test_dynamic_node_meta_key() -> void:
	assert_eq(MockWallBreachHelper.DYNAMIC_NODE_META, "wall_breach_dynamic",
		"DYNAMIC_NODE_META should be 'wall_breach_dynamic'")


# ============================================================================
# Segment Validity Tests
# ============================================================================


func test_segment_valid_at_minimum() -> void:
	assert_true(MockWallBreachHelper.is_segment_valid(8.0),
		"Segment at exactly MIN_SEGMENT_SIZE should be valid")


func test_segment_valid_above_minimum() -> void:
	assert_true(MockWallBreachHelper.is_segment_valid(50.0),
		"Segment above MIN_SEGMENT_SIZE should be valid")


func test_segment_invalid_below_minimum() -> void:
	assert_false(MockWallBreachHelper.is_segment_valid(7.9),
		"Segment below MIN_SEGMENT_SIZE should be invalid")


func test_segment_invalid_at_zero() -> void:
	assert_false(MockWallBreachHelper.is_segment_valid(0.0),
		"Zero-size segment should be invalid")


func test_segment_invalid_negative() -> void:
	assert_false(MockWallBreachHelper.is_segment_valid(-5.0),
		"Negative segment should be invalid")


# ============================================================================
# Thin Wall Detection Tests
# ============================================================================


func test_thin_wall_below_passage_width() -> void:
	assert_true(MockWallBreachHelper.is_wall_too_thin(100.0),
		"Wall shorter than BREACH_PASSAGE_WIDTH should be too thin")


func test_not_thin_at_passage_width() -> void:
	assert_false(MockWallBreachHelper.is_wall_too_thin(120.0),
		"Wall exactly at BREACH_PASSAGE_WIDTH should not be too thin")


func test_not_thin_above_passage_width() -> void:
	assert_false(MockWallBreachHelper.is_wall_too_thin(500.0),
		"Wall larger than BREACH_PASSAGE_WIDTH should not be too thin")


# ============================================================================
# Horizontal Breach Segment Calculation Tests
# ============================================================================


func test_centered_breach_symmetric_segments() -> void:
	# 400px wide wall, breach at center (x=0)
	var segments := MockWallBreachHelper.calculate_horizontal_segments(400.0, 0.0)
	var left_w: float = segments[0]
	var right_w: float = segments[1]

	# half_w=200, half_breach=60, bx=0
	# left_end = 0-60 = -60, left_width = -60+200 = 140
	# right_start = 0+60 = 60, right_width = 200-60 = 140
	assert_almost_eq(left_w, 140.0, 0.01,
		"Left segment should be 140px for centered breach on 400px wall")
	assert_almost_eq(right_w, 140.0, 0.01,
		"Right segment should be 140px for centered breach on 400px wall")


func test_left_edge_breach() -> void:
	# 400px wall, breach at left edge (x=-200)
	# bx will be clamped to -200+60 = -140
	var segments := MockWallBreachHelper.calculate_horizontal_segments(400.0, -200.0)
	var left_w: float = segments[0]
	var right_w: float = segments[1]

	# bx=-140, left_end=-200, left_width=-200+200=0
	# right_start=-80, right_width=200-(-80)=280
	assert_almost_eq(left_w, 0.0, 0.01,
		"Left segment should be 0 for left-edge breach")
	assert_almost_eq(right_w, 280.0, 0.01,
		"Right segment should be 280px for left-edge breach")


func test_right_edge_breach() -> void:
	# 400px wall, breach at right edge (x=200)
	# bx will be clamped to 200-60 = 140
	var segments := MockWallBreachHelper.calculate_horizontal_segments(400.0, 200.0)
	var left_w: float = segments[0]
	var right_w: float = segments[1]

	# bx=140, left_end=80, left_width=80+200=280
	# right_start=200, right_width=200-200=0
	assert_almost_eq(left_w, 280.0, 0.01,
		"Left segment should be 280px for right-edge breach")
	assert_almost_eq(right_w, 0.0, 0.01,
		"Right segment should be 0 for right-edge breach")


func test_segments_sum_equals_wall_minus_passage() -> void:
	var segments := MockWallBreachHelper.calculate_horizontal_segments(400.0, 50.0)
	var left_w: float = segments[0]
	var right_w: float = segments[1]

	assert_almost_eq(left_w + right_w,
		400.0 - MockWallBreachHelper.BREACH_PASSAGE_WIDTH, 0.01,
		"Segment widths should sum to wall_width - BREACH_PASSAGE_WIDTH")
