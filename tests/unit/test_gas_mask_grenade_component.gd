extends GutTest
## Unit tests for GasMaskGrenadeComponent.
##
## Tests max_grenades, throw_cooldown, distance constraints,
## and grenade count tracking for the gas mask enemy grenade system.


# ============================================================================
# Mock GasMaskGrenadeComponent for Logic Tests
# ============================================================================


class MockGasMaskGrenadeComponent:
	var max_grenades: int = 4
	var throw_cooldown: float = 1.0
	var max_throw_distance: float = 900.0
	var min_throw_distance: float = 100.0
	var inaccuracy: float = 0.15
	var throw_delay: float = 0.1

	var grenades_remaining: int = 0
	var _cooldown: float = 0.0
	var _is_throwing: bool = false
	var _enemy_position: Vector2 = Vector2.ZERO

	func initialize() -> void:
		grenades_remaining = max_grenades

	func physics_process(delta: float) -> void:
		if _cooldown > 0.0:
			_cooldown -= delta

	func can_throw(target_position: Vector2) -> bool:
		if grenades_remaining <= 0:
			return false
		if _cooldown > 0.0:
			return false
		if _is_throwing:
			return false
		var distance := _enemy_position.distance_to(target_position)
		if distance < min_throw_distance or distance > max_throw_distance:
			return false
		return true

	func simulate_throw(target_position: Vector2) -> bool:
		if not can_throw(target_position):
			return false
		_is_throwing = true
		_cooldown = throw_cooldown
		grenades_remaining -= 1
		_is_throwing = false
		return true

	func is_throwing() -> bool:
		return _is_throwing

	func has_grenades() -> bool:
		return grenades_remaining > 0


var comp: MockGasMaskGrenadeComponent


func before_each() -> void:
	comp = MockGasMaskGrenadeComponent.new()
	comp.initialize()


func after_each() -> void:
	comp = null


# ============================================================================
# Default Values Tests
# ============================================================================


func test_max_grenades_default() -> void:
	assert_eq(comp.max_grenades, 4,
		"max_grenades should default to 4")


func test_throw_cooldown_default() -> void:
	assert_eq(comp.throw_cooldown, 1.0,
		"throw_cooldown should default to 1.0 seconds")


func test_max_throw_distance_default() -> void:
	assert_eq(comp.max_throw_distance, 900.0,
		"max_throw_distance should default to 900.0 pixels")


func test_min_throw_distance_default() -> void:
	assert_eq(comp.min_throw_distance, 100.0,
		"min_throw_distance should default to 100.0 pixels")


func test_inaccuracy_default() -> void:
	assert_eq(comp.inaccuracy, 0.15,
		"inaccuracy should default to 0.15 radians")


func test_throw_delay_default() -> void:
	assert_eq(comp.throw_delay, 0.1,
		"throw_delay should default to 0.1 seconds")


# ============================================================================
# Grenade Count Tracking Tests
# ============================================================================


func test_initial_grenades_remaining() -> void:
	assert_eq(comp.grenades_remaining, 4,
		"Should start with max_grenades remaining")


func test_has_grenades_when_full() -> void:
	assert_true(comp.has_grenades(),
		"has_grenades should return true when grenades remain")


func test_grenade_count_decreases_on_throw() -> void:
	comp.simulate_throw(Vector2(300, 0))

	assert_eq(comp.grenades_remaining, 3,
		"Grenades remaining should decrease by 1 after throw")


func test_no_grenades_after_all_thrown() -> void:
	for _i in range(4):
		comp.simulate_throw(Vector2(300, 0))
		comp._cooldown = 0.0  # Reset cooldown for next throw

	assert_eq(comp.grenades_remaining, 0,
		"Should have 0 grenades after throwing all 4")
	assert_false(comp.has_grenades(),
		"has_grenades should return false when all grenades thrown")


func test_cannot_throw_with_no_grenades() -> void:
	comp.grenades_remaining = 0

	assert_false(comp.can_throw(Vector2(300, 0)),
		"Should not be able to throw with no grenades")


# ============================================================================
# Distance Constraint Tests
# ============================================================================


func test_cannot_throw_too_close() -> void:
	comp._enemy_position = Vector2.ZERO

	assert_false(comp.can_throw(Vector2(50, 0)),
		"Should not throw at target closer than min_throw_distance (100)")


func test_cannot_throw_too_far() -> void:
	comp._enemy_position = Vector2.ZERO

	assert_false(comp.can_throw(Vector2(1000, 0)),
		"Should not throw at target beyond max_throw_distance (900)")


func test_can_throw_at_min_distance() -> void:
	comp._enemy_position = Vector2.ZERO

	assert_true(comp.can_throw(Vector2(100, 0)),
		"Should be able to throw at exactly min_throw_distance")


func test_can_throw_at_max_distance() -> void:
	comp._enemy_position = Vector2.ZERO

	assert_true(comp.can_throw(Vector2(900, 0)),
		"Should be able to throw at exactly max_throw_distance")


func test_can_throw_at_mid_distance() -> void:
	comp._enemy_position = Vector2.ZERO

	assert_true(comp.can_throw(Vector2(500, 0)),
		"Should be able to throw at mid-range distance")


# ============================================================================
# Cooldown Tests
# ============================================================================


func test_cooldown_blocks_throw() -> void:
	comp.simulate_throw(Vector2(300, 0))

	assert_false(comp.can_throw(Vector2(300, 0)),
		"Should not be able to throw during cooldown")


func test_cooldown_decreases_over_time() -> void:
	comp._cooldown = 1.0
	comp.physics_process(0.5)

	assert_eq(comp._cooldown, 0.5,
		"Cooldown should decrease by delta")


func test_can_throw_after_cooldown_expires() -> void:
	comp.simulate_throw(Vector2(300, 0))
	comp.physics_process(1.0)  # Wait full cooldown

	assert_true(comp.can_throw(Vector2(300, 0)),
		"Should be able to throw after cooldown expires")


func test_cooldown_does_not_go_negative() -> void:
	comp._cooldown = 0.5
	comp.physics_process(1.0)

	assert_true(comp._cooldown <= 0.0,
		"Cooldown should not stay positive after sufficient time")


# ============================================================================
# Throwing State Tests
# ============================================================================


func test_not_throwing_initially() -> void:
	assert_false(comp.is_throwing(),
		"Should not be in throwing state initially")


func test_cannot_throw_while_throwing() -> void:
	comp._is_throwing = true

	assert_false(comp.can_throw(Vector2(300, 0)),
		"Should not be able to throw while already throwing")
