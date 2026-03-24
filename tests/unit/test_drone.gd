extends GutTest
## Unit tests for Drone scene object (Issue #1397, #1417).
##
## Tests the drone visual constants, group membership, and combat visuals.


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
	var _led_color: Color = Color(0.2, 0.8, 0.2, 0.9)  # Green = searching
	var _is_combat: bool = false

	func _init() -> void:
		_groups.append("enemies")

	func is_in_group(group: String) -> bool:
		return group in _groups

	func is_alive() -> bool:
		return _is_alive

	func update_rotors(delta: float) -> void:
		var speed_mult: float = 3.0 if _is_combat else 1.0
		_rotor_angle += ROTOR_SPEED * delta * speed_mult

	func activate_combat() -> void:
		_is_combat = true
		_led_color = Color(1.0, 0.1, 0.05, 0.95)  # Red = combat


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


# ============================================================================
# Combat Visual Tests (Issue #1417)
# ============================================================================


func test_led_starts_green() -> void:
	var drone := MockDrone.new()
	assert_almost_eq(drone._led_color.g, 0.8, 0.01, "LED should start green (searching)")
	assert_lt(drone._led_color.r, 0.5, "LED should not be red when searching")


func test_led_turns_red_in_combat() -> void:
	var drone := MockDrone.new()
	drone.activate_combat()
	assert_gt(drone._led_color.r, 0.9, "LED should be red in combat")
	assert_lt(drone._led_color.g, 0.2, "LED green component should be low in combat")


func test_rotors_spin_faster_in_combat() -> void:
	var drone_search := MockDrone.new()
	var drone_combat := MockDrone.new()
	drone_combat.activate_combat()

	drone_search.update_rotors(1.0)
	drone_combat.update_rotors(1.0)

	assert_gt(drone_combat._rotor_angle, drone_search._rotor_angle, "Rotors should spin faster in combat")
	assert_almost_eq(drone_combat._rotor_angle, drone_search._rotor_angle * 3.0, 0.001, "Combat rotors should be 3× faster")
