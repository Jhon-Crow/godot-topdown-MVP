extends GutTest
## Unit tests for Drone scene object (Issue #1397).
##
## Tests the drone visual constants and group membership.


# ============================================================================
# Mock Drone for Logic Tests
# ============================================================================


class MockDrone:
	const DRONE_BODY_SIZE: float = 10.0
	const ROTOR_ARM_LENGTH: float = 12.0
	const ROTOR_RADIUS: float = 4.0
	const ROTOR_SPEED: float = 20.0

	var _is_alive: bool = true
	var _rotor_angle: float = 0.0
	var _groups: Array[String] = []

	func _init() -> void:
		_groups.append("enemies")

	func is_in_group(group: String) -> bool:
		return group in _groups

	func is_alive() -> bool:
		return _is_alive

	func update_rotors(delta: float) -> void:
		_rotor_angle += ROTOR_SPEED * delta


# ============================================================================
# Visual Constants Tests
# ============================================================================


func test_body_size() -> void:
	assert_eq(MockDrone.DRONE_BODY_SIZE, 10.0, "Drone body size should be 10 pixels")


func test_rotor_arm_length() -> void:
	assert_eq(MockDrone.ROTOR_ARM_LENGTH, 12.0, "Rotor arm should be 12 pixels from center")


func test_rotor_radius() -> void:
	assert_eq(MockDrone.ROTOR_RADIUS, 4.0, "Rotor radius should be 4 pixels")


func test_rotor_speed() -> void:
	assert_eq(MockDrone.ROTOR_SPEED, 20.0, "Rotor speed should be 20 rad/s")


# ============================================================================
# Group Tests
# ============================================================================


func test_drone_in_enemies_group() -> void:
	var drone := MockDrone.new()
	assert_true(drone.is_in_group("enemies"), "Drone should be in enemies group")


func test_drone_not_in_other_group() -> void:
	var drone := MockDrone.new()
	assert_false(drone.is_in_group("players"), "Drone should not be in players group")


# ============================================================================
# State Tests
# ============================================================================


func test_alive_by_default() -> void:
	var drone := MockDrone.new()
	assert_true(drone.is_alive(), "Drone should be alive by default")


func test_rotor_angle_starts_at_zero() -> void:
	var drone := MockDrone.new()
	assert_eq(drone._rotor_angle, 0.0, "Rotor angle should start at 0")


func test_rotor_rotation() -> void:
	var drone := MockDrone.new()
	drone.update_rotors(0.5)
	assert_almost_eq(drone._rotor_angle, 10.0, 0.001, "Rotor should rotate by speed * delta")


func test_rotor_continues_rotating() -> void:
	var drone := MockDrone.new()
	drone.update_rotors(1.0)
	drone.update_rotors(1.0)
	assert_almost_eq(drone._rotor_angle, 40.0, 0.001, "Rotor angle should accumulate")
