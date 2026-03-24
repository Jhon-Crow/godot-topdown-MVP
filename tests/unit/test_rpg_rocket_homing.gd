extends GutTest
## Unit tests for RPG rocket weak homing toward the player (Issue #1135).
##
## Tests the homing steering logic in isolation using a MockRpgRocket class
## that mirrors the algorithm in bullet.gd._apply_rpg_homing_steering().


# ============================================================================
# Mock RPG Rocket — mirrors bullet.gd RPG homing logic (Issue #1135)
# ============================================================================


class MockRpgRocket:
	## Turning speed in radians per second (mirrors rpg_homing_steer_speed).
	var rpg_homing_steer_speed: float = 1.2

	## Maximum total turn from original firing direction (mirrors rpg_homing_max_turn_angle).
	var rpg_homing_max_turn_angle: float = deg_to_rad(30.0)

	## Current travel direction (normalized).
	var direction: Vector2 = Vector2.RIGHT

	## Original firing direction (stored at spawn).
	var _rpg_homing_original_direction: Vector2 = Vector2.ZERO

	## Current world position.
	var global_position: Vector2 = Vector2.ZERO

	## Sprite rotation (mirrors direction.angle()).
	var rotation: float = 0.0

	## Call this after setting direction, before the first physics step.
	func init_homing() -> void:
		_rpg_homing_original_direction = direction.normalized()

	## Mirrors _apply_rpg_homing_steering(delta) from bullet.gd.
	## Returns the angle change applied (for assertions).
	func apply_homing_toward(target_pos: Vector2, delta: float) -> float:
		if rpg_homing_steer_speed <= 0.0:
			return 0.0

		var to_target := (target_pos - global_position).normalized()
		var angle_diff := direction.angle_to(to_target)
		var max_steer_this_frame := rpg_homing_steer_speed * delta
		angle_diff = clampf(angle_diff, -max_steer_this_frame, max_steer_this_frame)

		var new_direction := direction.rotated(angle_diff).normalized()
		var angle_from_original := _rpg_homing_original_direction.angle_to(new_direction)
		if absf(angle_from_original) > rpg_homing_max_turn_angle:
			return 0.0

		direction = new_direction
		rotation = direction.angle()
		return angle_diff


# ============================================================================
# Basic Homing Steering Tests
# ============================================================================


func test_homing_steers_toward_target_above() -> void:
	var rocket := MockRpgRocket.new()
	rocket.direction = Vector2.RIGHT
	rocket.global_position = Vector2.ZERO
	rocket.init_homing()

	# Player is up and to the right — rocket should steer upward
	var angle_change := rocket.apply_homing_toward(Vector2(100, -100), 0.016)

	assert_true(rocket.direction.y < 0.0,
		"Rocket should steer upward toward player above")
	assert_true(angle_change != 0.0,
		"Angle change should be non-zero when target is off-axis")


func test_homing_steers_toward_target_below() -> void:
	var rocket := MockRpgRocket.new()
	rocket.direction = Vector2.RIGHT
	rocket.global_position = Vector2.ZERO
	rocket.init_homing()

	var angle_change := rocket.apply_homing_toward(Vector2(100, 100), 0.016)

	assert_true(rocket.direction.y > 0.0,
		"Rocket should steer downward toward player below")
	assert_true(angle_change != 0.0,
		"Angle change should be non-zero")


func test_homing_no_steering_when_on_course() -> void:
	var rocket := MockRpgRocket.new()
	rocket.direction = Vector2.RIGHT
	rocket.global_position = Vector2.ZERO
	rocket.init_homing()

	# Player directly ahead — angle_diff == 0
	var angle_change := rocket.apply_homing_toward(Vector2(500, 0), 0.016)

	assert_almost_eq(angle_change, 0.0, 0.0001,
		"No steering needed when already aimed at player")
	assert_almost_eq(rocket.direction.x, 1.0, 0.001,
		"Direction should remain RIGHT")


func test_homing_disabled_when_steer_speed_zero() -> void:
	var rocket := MockRpgRocket.new()
	rocket.rpg_homing_steer_speed = 0.0
	rocket.direction = Vector2.RIGHT
	rocket.global_position = Vector2.ZERO
	rocket.init_homing()

	var angle_change := rocket.apply_homing_toward(Vector2(100, -200), 0.016)

	assert_eq(angle_change, 0.0,
		"No steering when homing_steer_speed == 0.0")
	assert_eq(rocket.direction, Vector2.RIGHT,
		"Direction unchanged when homing disabled")


func test_homing_per_frame_turn_is_limited() -> void:
	var rocket := MockRpgRocket.new()
	rocket.rpg_homing_steer_speed = 1.2
	rocket.direction = Vector2.RIGHT
	rocket.global_position = Vector2.ZERO
	rocket.init_homing()

	# Player is 90° away — large angle difference
	var angle_change := rocket.apply_homing_toward(Vector2(0, -500), 0.016)

	# Max possible turn this frame = 1.2 * 0.016 = 0.0192 radians
	assert_true(absf(angle_change) <= 1.2 * 0.016 + 0.0001,
		"Per-frame turn must not exceed homing_steer_speed * delta")


func test_homing_max_turn_angle_not_exceeded() -> void:
	var rocket := MockRpgRocket.new()
	rocket.rpg_homing_steer_speed = 50.0  # Fast steering to hit the limit quickly
	rocket.rpg_homing_max_turn_angle = deg_to_rad(30.0)
	rocket.direction = Vector2.RIGHT
	rocket.global_position = Vector2.ZERO
	rocket.init_homing()

	# Player is directly behind (180°) — far beyond the 30° limit
	for _i in range(200):
		rocket.apply_homing_toward(Vector2(-500, 0), 0.016)

	var angle_from_original := absf(rocket._rpg_homing_original_direction.angle_to(rocket.direction))
	assert_true(angle_from_original <= deg_to_rad(30.0) + 0.01,
		"Total turn must not exceed rpg_homing_max_turn_angle (30°), got: %.1f°" % rad_to_deg(angle_from_original))


func test_homing_updates_rotation() -> void:
	var rocket := MockRpgRocket.new()
	rocket.direction = Vector2.RIGHT
	rocket.rotation = 0.0
	rocket.global_position = Vector2.ZERO
	rocket.init_homing()

	rocket.apply_homing_toward(Vector2(100, -100), 0.016)

	assert_true(rocket.rotation != 0.0,
		"Sprite rotation should update when direction changes")
	assert_almost_eq(rocket.rotation, rocket.direction.angle(), 0.001,
		"Rotation should equal direction.angle()")


func test_homing_default_steer_speed_is_subtle() -> void:
	## The default steer speed should produce only a small angular change per frame
	## at 60 fps, confirming the "very weak" requirement from the issue.
	var rocket := MockRpgRocket.new()
	# Default rpg_homing_steer_speed = 1.2 rad/s; at 60 fps delta ≈ 0.0167 s
	var max_turn_per_frame := rocket.rpg_homing_steer_speed * (1.0 / 60.0)
	assert_true(max_turn_per_frame < deg_to_rad(2.0),
		"Default steering produces < 2° per frame at 60 fps (subtle effect)")


func test_homing_default_max_angle_is_30_degrees() -> void:
	var rocket := MockRpgRocket.new()
	assert_almost_eq(rocket.rpg_homing_max_turn_angle, deg_to_rad(30.0), 0.001,
		"Default max turn angle should be 30 degrees (keeps effect subtle)")


func test_homing_stores_original_direction_correctly() -> void:
	var rocket := MockRpgRocket.new()
	rocket.direction = Vector2(0.707, -0.707)  # 45° up-right
	rocket.init_homing()

	assert_almost_eq(rocket._rpg_homing_original_direction.x, rocket.direction.normalized().x, 0.001,
		"Original direction X should be stored at init")
	assert_almost_eq(rocket._rpg_homing_original_direction.y, rocket.direction.normalized().y, 0.001,
		"Original direction Y should be stored at init")


func test_homing_does_not_overshoot_target() -> void:
	## After many frames the rocket should converge toward the target without
	## oscillating past it (angle_diff shrinks each frame, never grows).
	var rocket := MockRpgRocket.new()
	rocket.rpg_homing_steer_speed = 3.0  # Faster to see convergence within test
	rocket.rpg_homing_max_turn_angle = deg_to_rad(30.0)
	rocket.direction = Vector2.RIGHT
	rocket.global_position = Vector2.ZERO
	rocket.init_homing()

	var target := Vector2(300, -100)  # ~18° above axis — within 30° limit

	var prev_angle_to_target := rocket.direction.angle_to((target - rocket.global_position).normalized())

	# Simulate several frames; the angle to target should decrease (or stay ~0)
	for _i in range(30):
		rocket.apply_homing_toward(target, 0.016)
		var current_angle := absf(rocket.direction.angle_to((target - rocket.global_position).normalized()))
		assert_true(current_angle <= absf(prev_angle_to_target) + 0.0001,
			"Angle to target should decrease (or stay same) each frame — no oscillation")
		prev_angle_to_target = current_angle
