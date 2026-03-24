extends GutTest
## Unit tests for DroneComponent (Issue #1397, #1417).
##
## Tests the drone entity behavior: HP, movement speed, detection range,
## damage/destruction logic, state transitions (SEARCHING→COMBAT),
## combat speed (3×), explosion parameters, drift factor, and beep system.


# ============================================================================
# Mock DroneComponent for Logic Tests
# ============================================================================


class MockDroneComponent:
	const DRONE_HP: int = 2
	const SEARCH_SPEED: float = 150.0
	const COMBAT_SPEED_MULTIPLIER: float = 3.0
	const COMBAT_SPEED: float = SEARCH_SPEED * COMBAT_SPEED_MULTIPLIER
	const HOVER_OFFSET: float = -20.0
	const DETECTION_RANGE: float = 0.0  # Unlimited
	const EXPLOSION_RADIUS: float = 150.0
	const EXPLOSION_DAMAGE: int = 3
	const COLLISION_DISTANCE: float = 24.0
	const DRIFT_FACTOR: float = 0.85
	const BEEP_INTERVAL: float = 0.3
	const BEEP_FREQUENCY: float = 1200.0

	enum DroneState { SEARCHING, COMBAT }

	var _hp: int = DRONE_HP
	var _is_alive: bool = true
	var _state: DroneState = DroneState.SEARCHING
	var _has_exploded: bool = false
	var _current_move_direction: Vector2 = Vector2.ZERO
	var drone_destroyed_count: int = 0
	var drone_hit_count: int = 0
	var combat_activated_count: int = 0

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

	func get_state() -> DroneState:
		return _state

	func is_in_combat() -> bool:
		return _state == DroneState.COMBAT

	func transition_to_combat() -> void:
		_state = DroneState.COMBAT
		combat_activated_count += 1

	func simulate_drift(desired_dir: Vector2) -> Vector2:
		## Simulates the drift calculation from _update_combat
		if _current_move_direction == Vector2.ZERO:
			_current_move_direction = desired_dir
		else:
			_current_move_direction = (_current_move_direction * DRIFT_FACTOR + desired_dir * (1.0 - DRIFT_FACTOR)).normalized()
		return _current_move_direction

	func explode() -> void:
		if _has_exploded or not _is_alive:
			return
		_has_exploded = true
		_is_alive = false
		_hp = 0
		drone_destroyed_count += 1


# ============================================================================
# Constants Tests
# ============================================================================


func test_drone_hp() -> void:
	assert_eq(MockDroneComponent.DRONE_HP, 2, "Drone should have 2 HP")


func test_search_speed() -> void:
	assert_eq(MockDroneComponent.SEARCH_SPEED, 150.0, "Drone search speed should be 150 px/s")


func test_combat_speed_multiplier() -> void:
	assert_eq(MockDroneComponent.COMBAT_SPEED_MULTIPLIER, 3.0, "Combat speed should be 3× search speed")


func test_combat_speed_value() -> void:
	assert_eq(MockDroneComponent.COMBAT_SPEED, 450.0, "Combat speed should be 450 px/s (150 × 3)")


func test_hover_offset_is_negative() -> void:
	assert_lt(MockDroneComponent.HOVER_OFFSET, 0.0, "Hover offset should be negative (above)")


func test_detection_range_unlimited() -> void:
	assert_eq(MockDroneComponent.DETECTION_RANGE, 0.0, "Detection range should be 0 (unlimited)")


func test_explosion_radius_matches_rpg() -> void:
	assert_eq(MockDroneComponent.EXPLOSION_RADIUS, 150.0, "Explosion radius should be 150 px (same as RPG)")


func test_explosion_damage_matches_rpg() -> void:
	assert_eq(MockDroneComponent.EXPLOSION_DAMAGE, 3, "Explosion damage should be 3 HP (same as RPG)")


func test_collision_distance() -> void:
	assert_eq(MockDroneComponent.COLLISION_DISTANCE, 24.0, "Collision distance should be 24 px")


func test_drift_factor_range() -> void:
	assert_gt(MockDroneComponent.DRIFT_FACTOR, 0.0, "Drift factor should be > 0")
	assert_lt(MockDroneComponent.DRIFT_FACTOR, 1.0, "Drift factor should be < 1")


func test_beep_interval() -> void:
	assert_eq(MockDroneComponent.BEEP_INTERVAL, 0.3, "Beep interval should be 0.3s")


func test_beep_frequency() -> void:
	assert_eq(MockDroneComponent.BEEP_FREQUENCY, 1200.0, "Beep frequency should be 1200 Hz")


# ============================================================================
# State Tests
# ============================================================================


func test_alive_by_default() -> void:
	var drone := MockDroneComponent.new()
	assert_true(drone.is_alive(), "Drone should be alive by default")


func test_full_hp_at_start() -> void:
	var drone := MockDroneComponent.new()
	assert_eq(drone.get_hp(), 2, "Drone should start with full HP")


func test_starts_in_searching_state() -> void:
	var drone := MockDroneComponent.new()
	assert_eq(drone.get_state(), MockDroneComponent.DroneState.SEARCHING, "Drone should start in SEARCHING state")


func test_not_in_combat_initially() -> void:
	var drone := MockDroneComponent.new()
	assert_false(drone.is_in_combat(), "Drone should not be in combat initially")


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


# ============================================================================
# Combat State Transition Tests (Issue #1417)
# ============================================================================


func test_transition_to_combat() -> void:
	var drone := MockDroneComponent.new()
	drone.transition_to_combat()
	assert_eq(drone.get_state(), MockDroneComponent.DroneState.COMBAT, "Should be in COMBAT state after transition")


func test_is_in_combat_after_transition() -> void:
	var drone := MockDroneComponent.new()
	drone.transition_to_combat()
	assert_true(drone.is_in_combat(), "is_in_combat() should return true after transition")


func test_combat_activated_signal_emitted() -> void:
	var drone := MockDroneComponent.new()
	drone.transition_to_combat()
	assert_eq(drone.combat_activated_count, 1, "combat_activated should fire once")


# ============================================================================
# Drift/Inertia Tests (Issue #1417)
# ============================================================================


func test_drift_initial_direction_set() -> void:
	var drone := MockDroneComponent.new()
	var result := drone.simulate_drift(Vector2.RIGHT)
	assert_eq(result, Vector2.RIGHT, "First drift step should adopt desired direction directly")


func test_drift_resists_direction_change() -> void:
	var drone := MockDroneComponent.new()
	# Set initial direction to RIGHT
	drone.simulate_drift(Vector2.RIGHT)
	# Now desire to go UP — drift should resist full change
	var result := drone.simulate_drift(Vector2.UP)
	# Result should still have positive X component (drifting right)
	assert_gt(result.x, 0.0, "Drift should maintain some rightward momentum")
	# But should also have some upward component
	assert_lt(result.y, 0.0, "Drift should start turning upward")


func test_drift_preserves_momentum() -> void:
	var drone := MockDroneComponent.new()
	drone.simulate_drift(Vector2.RIGHT)
	# Turn 90 degrees — with DRIFT_FACTOR=0.85, drone keeps most of original direction
	var result := drone.simulate_drift(Vector2.UP)
	# The X component should dominate (85% of original RIGHT vs 15% of new UP)
	assert_gt(abs(result.x), abs(result.y), "Drift should preserve majority of previous direction")


func test_drift_gradual_turn() -> void:
	var drone := MockDroneComponent.new()
	drone.simulate_drift(Vector2.RIGHT)
	# Simulate multiple frames of turning UP
	var result: Vector2
	for i in range(20):
		result = drone.simulate_drift(Vector2.UP)
	# After many frames, should have mostly turned UP
	assert_lt(result.y, -0.5, "After many frames, drift should mostly follow desired direction")


# ============================================================================
# Explosion Tests (Issue #1417)
# ============================================================================


func test_explode_kills_drone() -> void:
	var drone := MockDroneComponent.new()
	drone.explode()
	assert_false(drone.is_alive(), "Drone should be dead after explosion")
	assert_eq(drone.get_hp(), 0, "HP should be 0 after explosion")


func test_explode_emits_destroyed() -> void:
	var drone := MockDroneComponent.new()
	drone.explode()
	assert_eq(drone.drone_destroyed_count, 1, "Should emit destroyed signal on explosion")


func test_double_explosion_prevented() -> void:
	var drone := MockDroneComponent.new()
	drone.explode()
	drone.explode()
	assert_eq(drone.drone_destroyed_count, 1, "Should not double-explode")


func test_dead_drone_cannot_explode() -> void:
	var drone := MockDroneComponent.new()
	drone.take_damage(2)  # Kill via damage
	var count_before := drone.drone_destroyed_count
	drone.explode()  # Try to explode dead drone
	assert_eq(drone.drone_destroyed_count, count_before, "Dead drone should not explode")
