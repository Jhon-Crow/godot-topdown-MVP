extends GutTest
## Unit tests for the PenetrationHole effect.
##
## Tests the penetration hole configuration, position calculation, and
## direction/size clamping logic using a mock class that mirrors the
## core logic without Godot scene tree dependencies.


# ============================================================================
# Mock PenetrationHole for Testing
# ============================================================================


class MockPenetrationHole:
	## Collision layers this hole affects (default: obstacles layer 3).
	const OBSTACLE_LAYER: int = 4  # Layer 3 in Godot is value 4 (2^2)

	## Direction the bullet was traveling (for collision orientation).
	var bullet_direction: Vector2 = Vector2.RIGHT

	## Width of the hole (based on caliber).
	var trail_width: float = 4.0

	## Length of the hole (based on penetration distance traveled).
	var trail_length: float = 8.0

	## Entry point in global coordinates.
	var _entry_point: Vector2 = Vector2.ZERO

	## Exit point in global coordinates.
	var _exit_point: Vector2 = Vector2.ZERO

	## Whether the hole has been fully configured.
	var _is_configured: bool = false

	## Position of the hole (simulates global_position).
	var position: Vector2 = Vector2.ZERO

	## Rotation of the hole in radians.
	var rotation: float = 0.0

	## Track whether configure was called (for verifying set_from_entry_exit flow).
	var _configure_call_count: int = 0

	## Track the last arguments passed to configure.
	var _last_configure_direction: Vector2 = Vector2.ZERO
	var _last_configure_width: float = 0.0
	var _last_configure_length: float = 0.0

	## Configures the hole with bullet information.
	## @param direction: Direction the bullet was traveling.
	## @param width: Width of the hole (based on caliber).
	## @param length: Length of the hole (penetration distance).
	func configure(direction: Vector2, width: float, length: float) -> void:
		bullet_direction = direction.normalized()
		trail_width = maxf(width, 2.0)  # Minimum width of 2 pixels
		trail_length = maxf(length, 4.0)  # Minimum length of 4 pixels

		# Set rotation for collision shape (centered at hole position)
		rotation = bullet_direction.angle()

		# Track call for testing
		_configure_call_count += 1
		_last_configure_direction = bullet_direction
		_last_configure_width = trail_width
		_last_configure_length = trail_length

	## Sets the hole from entry and exit points.
	## This is the primary method for configuring the hole.
	## @param entry_point: Where the bullet entered the wall (global coords).
	## @param exit_point: Where the bullet exited the wall (global coords).
	func set_from_entry_exit(entry_point: Vector2, exit_point: Vector2) -> void:
		# Store entry/exit points
		_entry_point = entry_point
		_exit_point = exit_point

		# Position collision shape at center of entry and exit
		position = (entry_point + exit_point) / 2.0

		# Calculate direction and length
		var path := exit_point - entry_point
		trail_length = maxf(path.length(), 4.0)  # Minimum length of 4 pixels
		bullet_direction = path.normalized() if trail_length > 4.0 else Vector2.RIGHT

		# Mark as configured
		_is_configured = true

		# Now create/update collision shape
		configure(bullet_direction, trail_width, trail_length)


var hole: MockPenetrationHole


func before_each() -> void:
	hole = MockPenetrationHole.new()


func after_each() -> void:
	hole = null


# ============================================================================
# OBSTACLE_LAYER Constant Tests
# ============================================================================


func test_obstacle_layer_constant_value() -> void:
	assert_eq(MockPenetrationHole.OBSTACLE_LAYER, 4,
		"OBSTACLE_LAYER should be 4 (Layer 3 = 2^2)")


func test_obstacle_layer_is_power_of_two() -> void:
	var layer := MockPenetrationHole.OBSTACLE_LAYER
	# A power of two has exactly one bit set: (n & (n-1)) == 0 for n > 0
	assert_true(layer > 0 and (layer & (layer - 1)) == 0,
		"OBSTACLE_LAYER should be a power of two (valid collision layer bitmask)")


# ============================================================================
# Default Value Tests
# ============================================================================


func test_default_bullet_direction() -> void:
	assert_eq(hole.bullet_direction, Vector2.RIGHT,
		"Default bullet direction should be Vector2.RIGHT")


func test_default_trail_width() -> void:
	assert_eq(hole.trail_width, 4.0,
		"Default trail width should be 4.0")


func test_default_trail_length() -> void:
	assert_eq(hole.trail_length, 8.0,
		"Default trail length should be 8.0")


func test_default_entry_point() -> void:
	assert_eq(hole._entry_point, Vector2.ZERO,
		"Default entry point should be Vector2.ZERO")


func test_default_exit_point() -> void:
	assert_eq(hole._exit_point, Vector2.ZERO,
		"Default exit point should be Vector2.ZERO")


func test_default_is_configured() -> void:
	assert_false(hole._is_configured,
		"Default _is_configured should be false")


func test_default_position() -> void:
	assert_eq(hole.position, Vector2.ZERO,
		"Default position should be Vector2.ZERO")


func test_default_rotation() -> void:
	assert_eq(hole.rotation, 0.0,
		"Default rotation should be 0.0")


# ============================================================================
# configure() with Normal Values Tests
# ============================================================================


func test_configure_sets_bullet_direction() -> void:
	hole.configure(Vector2.RIGHT, 6.0, 12.0)

	assert_eq(hole.bullet_direction, Vector2.RIGHT,
		"configure should set bullet_direction to normalized direction")


func test_configure_sets_trail_width() -> void:
	hole.configure(Vector2.RIGHT, 6.0, 12.0)

	assert_eq(hole.trail_width, 6.0,
		"configure should set trail_width when above minimum")


func test_configure_sets_trail_length() -> void:
	hole.configure(Vector2.RIGHT, 6.0, 12.0)

	assert_eq(hole.trail_length, 12.0,
		"configure should set trail_length when above minimum")


func test_configure_sets_rotation_for_right_direction() -> void:
	hole.configure(Vector2.RIGHT, 6.0, 12.0)

	assert_almost_eq(hole.rotation, 0.0, 0.001,
		"Rotation for Vector2.RIGHT should be 0 radians")


func test_configure_sets_rotation_for_down_direction() -> void:
	hole.configure(Vector2.DOWN, 6.0, 12.0)

	assert_almost_eq(hole.rotation, PI / 2.0, 0.001,
		"Rotation for Vector2.DOWN should be PI/2 radians")


func test_configure_sets_rotation_for_left_direction() -> void:
	hole.configure(Vector2.LEFT, 6.0, 12.0)

	assert_almost_eq(hole.rotation, PI, 0.001,
		"Rotation for Vector2.LEFT should be PI radians")


func test_configure_sets_rotation_for_up_direction() -> void:
	hole.configure(Vector2.UP, 6.0, 12.0)

	assert_almost_eq(hole.rotation, -PI / 2.0, 0.001,
		"Rotation for Vector2.UP should be -PI/2 radians")


func test_configure_sets_rotation_for_diagonal_direction() -> void:
	hole.configure(Vector2(1.0, 1.0), 6.0, 12.0)

	assert_almost_eq(hole.rotation, PI / 4.0, 0.001,
		"Rotation for (1,1) diagonal should be PI/4 radians")


# ============================================================================
# configure() Direction Normalization Tests
# ============================================================================


func test_configure_normalizes_direction() -> void:
	hole.configure(Vector2(3.0, 4.0), 6.0, 12.0)

	assert_almost_eq(hole.bullet_direction.length(), 1.0, 0.001,
		"bullet_direction should be normalized (length 1.0)")


func test_configure_normalizes_large_direction_vector() -> void:
	hole.configure(Vector2(100.0, 0.0), 6.0, 12.0)

	assert_eq(hole.bullet_direction, Vector2.RIGHT,
		"Large direction vector (100,0) should normalize to Vector2.RIGHT")


func test_configure_normalizes_small_direction_vector() -> void:
	hole.configure(Vector2(0.01, 0.0), 6.0, 12.0)

	assert_almost_eq(hole.bullet_direction.x, 1.0, 0.001,
		"Small direction vector should normalize to unit length")
	assert_almost_eq(hole.bullet_direction.y, 0.0, 0.001,
		"Small direction vector y component should be 0")


func test_configure_normalizes_diagonal_direction() -> void:
	hole.configure(Vector2(5.0, 5.0), 6.0, 12.0)

	var expected := Vector2(5.0, 5.0).normalized()
	assert_almost_eq(hole.bullet_direction.x, expected.x, 0.001,
		"Diagonal direction x should be normalized")
	assert_almost_eq(hole.bullet_direction.y, expected.y, 0.001,
		"Diagonal direction y should be normalized")


func test_configure_normalizes_negative_direction() -> void:
	hole.configure(Vector2(-10.0, -10.0), 6.0, 12.0)

	assert_almost_eq(hole.bullet_direction.length(), 1.0, 0.001,
		"Negative direction should still be normalized")
	assert_true(hole.bullet_direction.x < 0.0,
		"Normalized negative direction should retain negative x")
	assert_true(hole.bullet_direction.y < 0.0,
		"Normalized negative direction should retain negative y")


# ============================================================================
# configure() Minimum Clamping Tests
# ============================================================================


func test_configure_clamps_width_below_minimum() -> void:
	hole.configure(Vector2.RIGHT, 1.0, 12.0)

	assert_eq(hole.trail_width, 2.0,
		"Width below 2.0 should be clamped to minimum 2.0")


func test_configure_clamps_width_at_zero() -> void:
	hole.configure(Vector2.RIGHT, 0.0, 12.0)

	assert_eq(hole.trail_width, 2.0,
		"Width of 0.0 should be clamped to minimum 2.0")


func test_configure_clamps_width_negative() -> void:
	hole.configure(Vector2.RIGHT, -5.0, 12.0)

	assert_eq(hole.trail_width, 2.0,
		"Negative width should be clamped to minimum 2.0")


func test_configure_preserves_width_at_minimum() -> void:
	hole.configure(Vector2.RIGHT, 2.0, 12.0)

	assert_eq(hole.trail_width, 2.0,
		"Width exactly at minimum (2.0) should be preserved")


func test_configure_preserves_width_above_minimum() -> void:
	hole.configure(Vector2.RIGHT, 10.0, 12.0)

	assert_eq(hole.trail_width, 10.0,
		"Width above minimum should be preserved as-is")


func test_configure_clamps_length_below_minimum() -> void:
	hole.configure(Vector2.RIGHT, 6.0, 2.0)

	assert_eq(hole.trail_length, 4.0,
		"Length below 4.0 should be clamped to minimum 4.0")


func test_configure_clamps_length_at_zero() -> void:
	hole.configure(Vector2.RIGHT, 6.0, 0.0)

	assert_eq(hole.trail_length, 4.0,
		"Length of 0.0 should be clamped to minimum 4.0")


func test_configure_clamps_length_negative() -> void:
	hole.configure(Vector2.RIGHT, 6.0, -10.0)

	assert_eq(hole.trail_length, 4.0,
		"Negative length should be clamped to minimum 4.0")


func test_configure_preserves_length_at_minimum() -> void:
	hole.configure(Vector2.RIGHT, 6.0, 4.0)

	assert_eq(hole.trail_length, 4.0,
		"Length exactly at minimum (4.0) should be preserved")


func test_configure_preserves_length_above_minimum() -> void:
	hole.configure(Vector2.RIGHT, 6.0, 50.0)

	assert_eq(hole.trail_length, 50.0,
		"Length above minimum should be preserved as-is")


func test_configure_clamps_both_width_and_length() -> void:
	hole.configure(Vector2.RIGHT, 0.5, 1.0)

	assert_eq(hole.trail_width, 2.0,
		"Both width should be clamped when below minimum")
	assert_eq(hole.trail_length, 4.0,
		"Both length should be clamped when below minimum")


# ============================================================================
# set_from_entry_exit() Position Calculation (Midpoint) Tests
# ============================================================================


func test_set_from_entry_exit_position_is_midpoint() -> void:
	var entry := Vector2(10.0, 20.0)
	var exit := Vector2(30.0, 40.0)
	hole.set_from_entry_exit(entry, exit)

	var expected_midpoint := Vector2(20.0, 30.0)
	assert_eq(hole.position, expected_midpoint,
		"Position should be midpoint of entry and exit")


func test_set_from_entry_exit_position_horizontal() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(100.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_eq(hole.position, Vector2(50.0, 0.0),
		"Horizontal midpoint should be at x=50")


func test_set_from_entry_exit_position_vertical() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(0.0, 60.0)
	hole.set_from_entry_exit(entry, exit)

	assert_eq(hole.position, Vector2(0.0, 30.0),
		"Vertical midpoint should be at y=30")


func test_set_from_entry_exit_position_negative_coords() -> void:
	var entry := Vector2(-20.0, -40.0)
	var exit := Vector2(-10.0, -20.0)
	hole.set_from_entry_exit(entry, exit)

	assert_eq(hole.position, Vector2(-15.0, -30.0),
		"Midpoint with negative coordinates should be calculated correctly")


func test_set_from_entry_exit_position_mixed_signs() -> void:
	var entry := Vector2(-50.0, 30.0)
	var exit := Vector2(50.0, -30.0)
	hole.set_from_entry_exit(entry, exit)

	assert_eq(hole.position, Vector2(0.0, 0.0),
		"Midpoint of symmetric negative/positive should be origin")


func test_set_from_entry_exit_position_large_distance() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(1000.0, 1000.0)
	hole.set_from_entry_exit(entry, exit)

	assert_eq(hole.position, Vector2(500.0, 500.0),
		"Midpoint of large distance should be calculated correctly")


# ============================================================================
# set_from_entry_exit() Length Calculation Tests
# ============================================================================


func test_set_from_entry_exit_length_horizontal() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(24.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.trail_length, 24.0, 0.01,
		"Trail length should be distance between entry and exit (24.0)")


func test_set_from_entry_exit_length_vertical() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(0.0, 48.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.trail_length, 48.0, 0.01,
		"Vertical trail length should be 48.0")


func test_set_from_entry_exit_length_diagonal() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(30.0, 40.0)
	hole.set_from_entry_exit(entry, exit)

	# Distance = sqrt(30^2 + 40^2) = sqrt(900 + 1600) = sqrt(2500) = 50
	assert_almost_eq(hole.trail_length, 50.0, 0.01,
		"Diagonal trail length should be 50.0 (3-4-5 triangle scaled)")


func test_set_from_entry_exit_length_clamps_to_minimum() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(1.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_eq(hole.trail_length, 4.0,
		"Trail length below 4.0 should be clamped to minimum 4.0")


func test_set_from_entry_exit_length_at_exact_minimum() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(4.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.trail_length, 4.0, 0.01,
		"Trail length exactly at minimum boundary should be 4.0")


func test_set_from_entry_exit_length_just_above_minimum() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(5.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.trail_length, 5.0, 0.01,
		"Trail length just above minimum should be preserved")


# ============================================================================
# set_from_entry_exit() Direction Calculation Tests
# ============================================================================


func test_set_from_entry_exit_direction_right() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(20.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.bullet_direction.x, 1.0, 0.001,
		"Direction x should be 1.0 for rightward penetration")
	assert_almost_eq(hole.bullet_direction.y, 0.0, 0.001,
		"Direction y should be 0.0 for rightward penetration")


func test_set_from_entry_exit_direction_left() -> void:
	var entry := Vector2(20.0, 0.0)
	var exit := Vector2(0.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.bullet_direction.x, -1.0, 0.001,
		"Direction x should be -1.0 for leftward penetration")
	assert_almost_eq(hole.bullet_direction.y, 0.0, 0.001,
		"Direction y should be 0.0 for leftward penetration")


func test_set_from_entry_exit_direction_down() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(0.0, 20.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.bullet_direction.x, 0.0, 0.001,
		"Direction x should be 0.0 for downward penetration")
	assert_almost_eq(hole.bullet_direction.y, 1.0, 0.001,
		"Direction y should be 1.0 for downward penetration")


func test_set_from_entry_exit_direction_up() -> void:
	var entry := Vector2(0.0, 20.0)
	var exit := Vector2(0.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.bullet_direction.x, 0.0, 0.001,
		"Direction x should be 0.0 for upward penetration")
	assert_almost_eq(hole.bullet_direction.y, -1.0, 0.001,
		"Direction y should be -1.0 for upward penetration")


func test_set_from_entry_exit_direction_diagonal() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(10.0, 10.0)
	hole.set_from_entry_exit(entry, exit)

	var expected := Vector2(10.0, 10.0).normalized()
	assert_almost_eq(hole.bullet_direction.x, expected.x, 0.001,
		"Diagonal direction x should be normalized")
	assert_almost_eq(hole.bullet_direction.y, expected.y, 0.001,
		"Diagonal direction y should be normalized")


func test_set_from_entry_exit_direction_is_normalized() -> void:
	var entry := Vector2(10.0, 20.0)
	var exit := Vector2(60.0, 80.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.bullet_direction.length(), 1.0, 0.001,
		"bullet_direction should always be normalized after set_from_entry_exit")


# ============================================================================
# set_from_entry_exit() with Same Entry/Exit (Zero Distance) Tests
# ============================================================================


func test_set_from_entry_exit_same_point_position() -> void:
	var point := Vector2(50.0, 100.0)
	hole.set_from_entry_exit(point, point)

	assert_eq(hole.position, point,
		"Position should be the point itself when entry equals exit")


func test_set_from_entry_exit_same_point_length_clamped() -> void:
	var point := Vector2(50.0, 100.0)
	hole.set_from_entry_exit(point, point)

	assert_eq(hole.trail_length, 4.0,
		"Trail length should be clamped to minimum 4.0 when entry equals exit")


func test_set_from_entry_exit_same_point_direction_defaults_to_right() -> void:
	var point := Vector2(50.0, 100.0)
	hole.set_from_entry_exit(point, point)

	# When trail_length <= 4.0 (after clamping from zero distance),
	# direction defaults to Vector2.RIGHT
	assert_eq(hole.bullet_direction, Vector2.RIGHT,
		"Direction should default to Vector2.RIGHT when entry equals exit")


func test_set_from_entry_exit_same_point_is_configured() -> void:
	var point := Vector2(50.0, 100.0)
	hole.set_from_entry_exit(point, point)

	assert_true(hole._is_configured,
		"Hole should be marked as configured even with same entry/exit")


func test_set_from_entry_exit_same_point_at_origin() -> void:
	hole.set_from_entry_exit(Vector2.ZERO, Vector2.ZERO)

	assert_eq(hole.position, Vector2.ZERO,
		"Position should be origin when both points are origin")
	assert_eq(hole.trail_length, 4.0,
		"Length should be clamped to minimum at origin")
	assert_eq(hole.bullet_direction, Vector2.RIGHT,
		"Direction should default to RIGHT at origin")


func test_set_from_entry_exit_near_zero_distance_below_minimum() -> void:
	# Points very close together but not identical, distance < 4.0
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(2.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_eq(hole.trail_length, 4.0,
		"Trail length below 4.0 should be clamped to minimum")
	# Distance is 2.0, which after maxf becomes 4.0. Since 4.0 is NOT > 4.0,
	# direction should default to Vector2.RIGHT
	assert_eq(hole.bullet_direction, Vector2.RIGHT,
		"Direction should default to RIGHT when distance is clamped to exactly 4.0")


# ============================================================================
# set_from_entry_exit() State and Flow Tests
# ============================================================================


func test_set_from_entry_exit_stores_entry_point() -> void:
	var entry := Vector2(10.0, 20.0)
	var exit := Vector2(50.0, 60.0)
	hole.set_from_entry_exit(entry, exit)

	assert_eq(hole._entry_point, entry,
		"Entry point should be stored")


func test_set_from_entry_exit_stores_exit_point() -> void:
	var entry := Vector2(10.0, 20.0)
	var exit := Vector2(50.0, 60.0)
	hole.set_from_entry_exit(entry, exit)

	assert_eq(hole._exit_point, exit,
		"Exit point should be stored")


func test_set_from_entry_exit_sets_is_configured_true() -> void:
	hole.set_from_entry_exit(Vector2(0.0, 0.0), Vector2(20.0, 0.0))

	assert_true(hole._is_configured,
		"_is_configured should be true after set_from_entry_exit")


func test_set_from_entry_exit_calls_configure() -> void:
	hole.set_from_entry_exit(Vector2(0.0, 0.0), Vector2(20.0, 0.0))

	assert_eq(hole._configure_call_count, 1,
		"set_from_entry_exit should call configure exactly once")


func test_set_from_entry_exit_passes_correct_direction_to_configure() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(20.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole._last_configure_direction.x, 1.0, 0.001,
		"configure should receive the correct direction x")
	assert_almost_eq(hole._last_configure_direction.y, 0.0, 0.001,
		"configure should receive the correct direction y")


func test_set_from_entry_exit_passes_trail_width_to_configure() -> void:
	hole.trail_width = 8.0
	hole.set_from_entry_exit(Vector2(0.0, 0.0), Vector2(20.0, 0.0))

	assert_eq(hole._last_configure_width, 8.0,
		"configure should receive the current trail_width")


func test_set_from_entry_exit_passes_trail_length_to_configure() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(30.0, 40.0)
	hole.set_from_entry_exit(entry, exit)

	# Distance is 50.0 (3-4-5 triangle)
	assert_almost_eq(hole._last_configure_length, 50.0, 0.01,
		"configure should receive the calculated trail_length")


# ============================================================================
# set_from_entry_exit() Rotation Consistency Tests
# ============================================================================


func test_set_from_entry_exit_rotation_matches_direction() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(20.0, 0.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.rotation, 0.0, 0.001,
		"Rotation should be 0 for rightward direction")


func test_set_from_entry_exit_rotation_for_45_degrees() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(20.0, 20.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.rotation, PI / 4.0, 0.001,
		"Rotation should be PI/4 for 45-degree direction")


func test_set_from_entry_exit_rotation_for_downward() -> void:
	var entry := Vector2(0.0, 0.0)
	var exit := Vector2(0.0, 20.0)
	hole.set_from_entry_exit(entry, exit)

	assert_almost_eq(hole.rotation, PI / 2.0, 0.001,
		"Rotation should be PI/2 for downward direction")


# ============================================================================
# Multiple configure() Calls Tests
# ============================================================================


func test_configure_can_be_called_multiple_times() -> void:
	hole.configure(Vector2.RIGHT, 6.0, 12.0)
	hole.configure(Vector2.DOWN, 8.0, 24.0)

	assert_almost_eq(hole.bullet_direction.x, 0.0, 0.001,
		"Direction x should reflect last configure call")
	assert_almost_eq(hole.bullet_direction.y, 1.0, 0.001,
		"Direction y should reflect last configure call")
	assert_eq(hole.trail_width, 8.0,
		"Width should reflect last configure call")
	assert_eq(hole.trail_length, 24.0,
		"Length should reflect last configure call")


func test_configure_overwrites_previous_values() -> void:
	hole.configure(Vector2.RIGHT, 100.0, 200.0)
	hole.configure(Vector2.LEFT, 3.0, 5.0)

	assert_almost_eq(hole.bullet_direction.x, -1.0, 0.001,
		"Direction should be overwritten by second configure call")
	assert_eq(hole.trail_width, 3.0,
		"Width should be overwritten by second configure call")
	assert_eq(hole.trail_length, 5.0,
		"Length should be overwritten by second configure call")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_configure_with_very_large_values() -> void:
	hole.configure(Vector2.RIGHT, 1000.0, 5000.0)

	assert_eq(hole.trail_width, 1000.0,
		"Very large width should be accepted")
	assert_eq(hole.trail_length, 5000.0,
		"Very large length should be accepted")


func test_configure_width_just_below_minimum() -> void:
	hole.configure(Vector2.RIGHT, 1.999, 12.0)

	assert_eq(hole.trail_width, 2.0,
		"Width of 1.999 should be clamped to minimum 2.0")


func test_configure_length_just_below_minimum() -> void:
	hole.configure(Vector2.RIGHT, 6.0, 3.999)

	assert_eq(hole.trail_length, 4.0,
		"Length of 3.999 should be clamped to minimum 4.0")


func test_set_from_entry_exit_very_close_points() -> void:
	# Points extremely close together, distance = 0.001
	var entry := Vector2(100.0, 100.0)
	var exit := Vector2(100.001, 100.0)
	hole.set_from_entry_exit(entry, exit)

	assert_eq(hole.trail_length, 4.0,
		"Very close points should result in minimum trail length")
	assert_almost_eq(hole.position.x, 100.0005, 0.001,
		"Position should be midpoint even for very close points")


func test_set_from_entry_exit_preserves_existing_trail_width() -> void:
	# Trail width is set before set_from_entry_exit; it should carry through
	hole.trail_width = 10.0
	hole.set_from_entry_exit(Vector2(0.0, 0.0), Vector2(20.0, 0.0))

	assert_eq(hole.trail_width, 10.0,
		"set_from_entry_exit should preserve the existing trail_width")
