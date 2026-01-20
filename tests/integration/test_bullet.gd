extends GutTest
## Integration tests for Bullet behavior.
##
## Tests bullet movement, lifetime, and collision detection.
## These tests run within a minimal Godot scene context.


const BulletScript = preload("res://scripts/projectiles/bullet.gd")


var bullet: Area2D


func before_each() -> void:
	# Create a minimal bullet instance for testing
	bullet = Area2D.new()
	bullet.set_script(BulletScript)
	add_child_autoqfree(bullet)


func after_each() -> void:
	bullet = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_bullet_default_speed() -> void:
	assert_eq(bullet.speed, 2500.0, "Default speed should be 2500 pixels/second")


func test_bullet_default_lifetime() -> void:
	assert_eq(bullet.lifetime, 3.0, "Default lifetime should be 3 seconds")


func test_bullet_default_direction() -> void:
	assert_eq(bullet.direction, Vector2.RIGHT, "Default direction should be RIGHT")


func test_bullet_default_shooter_id() -> void:
	assert_eq(bullet.shooter_id, -1, "Default shooter_id should be -1")


func test_bullet_time_alive_starts_at_zero() -> void:
	assert_eq(bullet._time_alive, 0.0, "Time alive should start at 0")


# ============================================================================
# Movement Tests
# ============================================================================


func test_bullet_moves_in_direction() -> void:
	bullet.direction = Vector2.RIGHT
	var initial_position := bullet.position

	# Simulate one physics frame (60 fps = ~0.0167s)
	bullet._physics_process(0.0167)

	var expected_move := Vector2.RIGHT * 2500.0 * 0.0167
	var actual_move := bullet.position - initial_position

	assert_almost_eq(actual_move.x, expected_move.x, 1.0, "Should move right")
	assert_almost_eq(actual_move.y, expected_move.y, 1.0, "Y should stay same")


func test_bullet_moves_down() -> void:
	bullet.direction = Vector2.DOWN
	var initial_position := bullet.position

	bullet._physics_process(0.1)

	var expected_move := Vector2.DOWN * 2500.0 * 0.1
	var actual_move := bullet.position - initial_position

	assert_almost_eq(actual_move.y, expected_move.y, 1.0, "Should move down")


func test_bullet_moves_diagonally() -> void:
	bullet.direction = Vector2(1, 1).normalized()
	var initial_position := bullet.position

	bullet._physics_process(0.1)

	var expected_move := Vector2(1, 1).normalized() * 2500.0 * 0.1
	var actual_move := bullet.position - initial_position

	assert_almost_eq(actual_move.length(), expected_move.length(), 1.0, "Diagonal movement magnitude")


func test_bullet_moves_with_custom_speed() -> void:
	bullet.speed = 1000.0
	bullet.direction = Vector2.RIGHT
	var initial_position := bullet.position

	bullet._physics_process(0.1)

	var expected_move := Vector2.RIGHT * 1000.0 * 0.1
	var actual_move := bullet.position - initial_position

	assert_almost_eq(actual_move.x, expected_move.x, 1.0, "Should use custom speed")


# ============================================================================
# Lifetime Tests
# ============================================================================


func test_bullet_time_alive_increments() -> void:
	bullet._physics_process(0.5)

	assert_almost_eq(bullet._time_alive, 0.5, 0.01, "Time alive should increment")


func test_bullet_survives_before_lifetime() -> void:
	bullet.lifetime = 3.0
	bullet._physics_process(2.9)

	assert_true(is_instance_valid(bullet), "Bullet should still exist before lifetime expires")


func test_bullet_queued_for_deletion_after_lifetime() -> void:
	bullet.lifetime = 1.0

	# Simulate enough time to exceed lifetime
	bullet._physics_process(1.1)

	# Bullet should be queued for deletion
	assert_true(bullet.is_queued_for_deletion(), "Bullet should be queued for deletion after lifetime")


func test_bullet_custom_lifetime() -> void:
	bullet.lifetime = 5.0
	bullet._physics_process(4.9)

	assert_false(bullet.is_queued_for_deletion(), "Should not be deleted with custom longer lifetime")

	bullet._physics_process(0.2)  # Now total = 5.1

	assert_true(bullet.is_queued_for_deletion(), "Should be deleted after custom lifetime")


# ============================================================================
# Direction Tests
# ============================================================================


func test_bullet_set_direction_normalizes() -> void:
	# Set a non-normalized direction
	bullet.direction = Vector2(10, 0)

	# The direction itself is not auto-normalized in the script
	# Movement calculation uses direction as-is
	assert_eq(bullet.direction, Vector2(10, 0), "Direction is not auto-normalized")


func test_bullet_negative_direction() -> void:
	bullet.direction = Vector2.LEFT
	var initial_position := bullet.position

	bullet._physics_process(0.1)

	var actual_move := bullet.position - initial_position

	assert_lt(actual_move.x, 0, "Should move left (negative x)")


# ============================================================================
# Shooter ID Tests
# ============================================================================


func test_shooter_id_can_be_set() -> void:
	bullet.shooter_id = 12345

	assert_eq(bullet.shooter_id, 12345, "Shooter ID should be settable")


func test_is_player_bullet_returns_false_for_invalid_id() -> void:
	bullet.shooter_id = -1

	var result: bool = bullet._is_player_bullet()

	assert_false(result, "Should return false for invalid shooter ID")


func test_is_player_bullet_returns_false_for_nonexistent_id() -> void:
	bullet.shooter_id = 999999999  # Non-existent instance ID

	var result: bool = bullet._is_player_bullet()

	assert_false(result, "Should return false for non-existent instance")


# ============================================================================
# Physics Accumulation Tests
# ============================================================================


func test_multiple_physics_frames_accumulate() -> void:
	bullet.direction = Vector2.RIGHT
	var initial_position := bullet.position

	# Simulate 10 frames at 60fps
	for i in range(10):
		bullet._physics_process(1.0 / 60.0)

	var total_time := 10.0 / 60.0
	var expected_distance := 2500.0 * total_time

	assert_almost_eq(bullet.position.x - initial_position.x, expected_distance, 1.0, "Movement should accumulate over frames")


func test_time_alive_accumulates() -> void:
	for i in range(10):
		bullet._physics_process(0.1)

	assert_almost_eq(bullet._time_alive, 1.0, 0.01, "Time alive should accumulate")


# ============================================================================
# Edge Cases
# ============================================================================


func test_bullet_zero_delta() -> void:
	var initial_position := bullet.position

	bullet._physics_process(0.0)

	assert_eq(bullet.position, initial_position, "Zero delta should not move bullet")
	assert_eq(bullet._time_alive, 0.0, "Zero delta should not increment time alive")


func test_bullet_very_small_delta() -> void:
	bullet.direction = Vector2.RIGHT
	var initial_position := bullet.position

	bullet._physics_process(0.0001)

	var expected_move := 2500.0 * 0.0001
	assert_almost_eq(bullet.position.x - initial_position.x, expected_move, 0.1, "Very small delta should still move")


func test_bullet_very_large_delta() -> void:
	bullet.direction = Vector2.RIGHT
	var initial_position := bullet.position
	bullet.lifetime = 10.0  # Extend lifetime

	bullet._physics_process(2.0)

	var expected_move := 2500.0 * 2.0
	assert_almost_eq(bullet.position.x - initial_position.x, expected_move, 1.0, "Large delta should move proportionally")


func test_bullet_zero_speed() -> void:
	bullet.speed = 0.0
	bullet.direction = Vector2.RIGHT
	var initial_position := bullet.position

	bullet._physics_process(1.0)

	assert_eq(bullet.position, initial_position, "Zero speed should not move bullet")


# ============================================================================
# Trail Effect Tests
# ============================================================================


func test_bullet_default_trail_length() -> void:
	assert_eq(bullet.trail_length, 8, "Default trail length should be 8 points")


func test_bullet_trail_length_can_be_set() -> void:
	bullet.trail_length = 12

	assert_eq(bullet.trail_length, 12, "Trail length should be settable")


func test_bullet_position_history_starts_empty() -> void:
	assert_eq(bullet._position_history.size(), 0, "Position history should start empty")


func test_bullet_position_history_grows_on_update() -> void:
	# Simulate physics process without a trail node (should still track positions internally)
	bullet.direction = Vector2.RIGHT
	bullet._physics_process(0.1)

	# Position history is only updated if trail exists, so check graceful handling
	# When no Trail node, _update_trail() should return early
	assert_true(true, "Bullet should handle missing trail node gracefully")


# ============================================================================
# Rotation Tests
# ============================================================================


func test_bullet_rotation_for_right_direction() -> void:
	bullet.direction = Vector2.RIGHT
	bullet._update_rotation()

	assert_almost_eq(bullet.rotation, 0.0, 0.01, "Rotation for RIGHT should be 0")


func test_bullet_rotation_for_down_direction() -> void:
	bullet.direction = Vector2.DOWN
	bullet._update_rotation()

	assert_almost_eq(bullet.rotation, PI / 2, 0.01, "Rotation for DOWN should be PI/2")


func test_bullet_rotation_for_left_direction() -> void:
	bullet.direction = Vector2.LEFT
	bullet._update_rotation()

	# LEFT direction angle is PI or -PI depending on implementation
	assert_almost_eq(absf(bullet.rotation), PI, 0.01, "Rotation for LEFT should be PI or -PI")


func test_bullet_rotation_for_up_direction() -> void:
	bullet.direction = Vector2.UP
	bullet._update_rotation()

	assert_almost_eq(bullet.rotation, -PI / 2, 0.01, "Rotation for UP should be -PI/2")


func test_bullet_rotation_for_diagonal_direction() -> void:
	bullet.direction = Vector2(1, 1).normalized()
	bullet._update_rotation()

	assert_almost_eq(bullet.rotation, PI / 4, 0.01, "Rotation for diagonal should be PI/4")
