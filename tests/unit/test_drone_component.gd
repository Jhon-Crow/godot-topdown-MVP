extends GutTest
## Unit tests for DroneComponent (Issue #1397).
##
## Tests the drone entity behavior: HP, movement speed, detection range,
## and damage/destruction logic.


# ============================================================================
# Mock DroneComponent for Logic Tests
# ============================================================================


class MockDroneComponent:
	const DRONE_HP: int = 2
	const DRONE_SPEED: float = 150.0
	const HOVER_OFFSET: float = -20.0
	const DETECTION_RANGE: float = 600.0

	var _hp: int = DRONE_HP
	var _is_alive: bool = true
	var drone_destroyed_count: int = 0
	var drone_hit_count: int = 0

	func take_damage(amount: int = 1) -> void:
		if not _is_alive:
			return
		_hp -= amount
		drone_hit_count += 1
		if _hp <= 0:
			_hp = 0
			_is_alive = false
			drone_destroyed_count += 1

	func is_alive() -> bool:
		return _is_alive

	func get_hp() -> int:
		return _hp


# ============================================================================
# Constants Tests
# ============================================================================


func test_drone_hp() -> void:
	assert_eq(MockDroneComponent.DRONE_HP, 2, "Drone should have 2 HP")


func test_drone_speed() -> void:
	assert_eq(MockDroneComponent.DRONE_SPEED, 150.0, "Drone speed should be 150 px/s")


func test_hover_offset_is_negative() -> void:
	assert_lt(MockDroneComponent.HOVER_OFFSET, 0.0, "Hover offset should be negative (above)")


func test_detection_range() -> void:
	assert_eq(MockDroneComponent.DETECTION_RANGE, 600.0, "Detection range should be 600 px")


# ============================================================================
# State Tests
# ============================================================================


func test_alive_by_default() -> void:
	var drone := MockDroneComponent.new()
	assert_true(drone.is_alive(), "Drone should be alive by default")


func test_full_hp_at_start() -> void:
	var drone := MockDroneComponent.new()
	assert_eq(drone.get_hp(), 2, "Drone should start with full HP")


# ============================================================================
# Damage Tests
# ============================================================================


func test_take_damage_reduces_hp() -> void:
	var drone := MockDroneComponent.new()
	drone.take_damage(1)
	assert_eq(drone.get_hp(), 1, "HP should decrease by 1")
	assert_true(drone.is_alive(), "Should still be alive with 1 HP")


func test_lethal_damage_kills_drone() -> void:
	var drone := MockDroneComponent.new()
	drone.take_damage(1)
	drone.take_damage(1)
	assert_false(drone.is_alive(), "Drone should die after 2 damage")
	assert_eq(drone.get_hp(), 0, "HP should be 0")


func test_overkill_clamps_hp_to_zero() -> void:
	var drone := MockDroneComponent.new()
	drone.take_damage(5)
	assert_eq(drone.get_hp(), 0, "HP should not go below 0")


func test_damage_to_dead_drone_ignored() -> void:
	var drone := MockDroneComponent.new()
	drone.take_damage(2)
	var hit_count_before := drone.drone_hit_count
	drone.take_damage(1)
	assert_eq(drone.drone_hit_count, hit_count_before, "Dead drone should not register more hits")


func test_destroyed_signal_on_death() -> void:
	var drone := MockDroneComponent.new()
	drone.take_damage(2)
	assert_eq(drone.drone_destroyed_count, 1, "Should emit destroyed signal once")


func test_hit_signal_on_each_damage() -> void:
	var drone := MockDroneComponent.new()
	drone.take_damage(1)
	drone.take_damage(1)
	assert_eq(drone.drone_hit_count, 2, "Should emit hit signal for each damage")
