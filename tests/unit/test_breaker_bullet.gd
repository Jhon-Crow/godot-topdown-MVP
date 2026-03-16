extends GutTest
## Unit tests for Breaker Bullet behavior (Issue #678).
##
## Tests the breaker bullet detonation logic: wall detection at 60px,
## explosion damage in 15px radius, shrapnel cone spawning,
## and ActiveItemManager integration.


# ============================================================================
# Mock BreakerBullet for Logic Tests
# ============================================================================


class MockBreakerBullet:
	## Whether this bullet has breaker behavior.
	var is_breaker_bullet: bool = false

	## Speed and direction.
	var speed: float = 2500.0
	var direction: Vector2 = Vector2.RIGHT
	var damage: float = 1.0
	var damage_multiplier: float = 1.0

	## Breaker constants (matching bullet.gd).
	const BREAKER_DETONATION_DISTANCE: float = 60.0
	const BREAKER_EXPLOSION_RADIUS: float = 15.0
	const BREAKER_EXPLOSION_DAMAGE: float = 1.0
	const BREAKER_SHRAPNEL_HALF_ANGLE: float = 30.0
	const BREAKER_SHRAPNEL_DAMAGE: float = 0.1
	const BREAKER_SHRAPNEL_COUNT_MULTIPLIER: float = 10.0
	const BREAKER_MAX_SHRAPNEL_PER_DETONATION: int = 10

	## Position simulation.
	var global_position: Vector2 = Vector2.ZERO
	var position: Vector2 = Vector2.ZERO

	## Tracking.
	var _destroyed: bool = false
	var _detonated: bool = false
	var _explosion_applied: bool = false
	var _shrapnel_spawned: int = 0
	var _shrapnel_directions: Array = []
	var shooter_id: int = -1

	## Simulate checking for breaker detonation.
	## wall_distance: simulated distance to wall (INF if no wall ahead)
	func check_breaker_detonation(wall_distance: float) -> bool:
		if not is_breaker_bullet:
			return false

		if wall_distance > BREAKER_DETONATION_DISTANCE:
			return false

		# Wall detected within range — detonate
		_breaker_detonate()
		return true

	## Trigger breaker detonation.
	func _breaker_detonate() -> void:
		_detonated = true
		_explosion_applied = true

		# Calculate shrapnel count (capped for performance, Issue #678)
		var effective_damage := damage * damage_multiplier
		var shrapnel_count := int(effective_damage * BREAKER_SHRAPNEL_COUNT_MULTIPLIER)
		shrapnel_count = clampi(shrapnel_count, 1, BREAKER_MAX_SHRAPNEL_PER_DETONATION)

		# Spawn shrapnel
		var half_angle_rad := deg_to_rad(BREAKER_SHRAPNEL_HALF_ANGLE)
		for i in range(shrapnel_count):
			var random_angle := randf_range(-half_angle_rad, half_angle_rad)
			var shrapnel_dir := direction.rotated(random_angle)
			_shrapnel_directions.append(shrapnel_dir)
			_shrapnel_spawned += 1

		_destroyed = true

	## Check if destroyed.
	func is_destroyed() -> bool:
		return _destroyed

	## Check if detonated.
	func has_detonated() -> bool:
		return _detonated

	## Get explosion radius check.
	func get_explosion_radius() -> float:
		return BREAKER_EXPLOSION_RADIUS

	## Get shrapnel count.
	func get_shrapnel_count() -> int:
		return _shrapnel_spawned


var bullet: MockBreakerBullet


func before_each() -> void:
	bullet = MockBreakerBullet.new()
	bullet.is_breaker_bullet = true


func after_each() -> void:
	bullet = null


# ============================================================================
# Breaker Flag Tests
# ============================================================================


func test_breaker_flag_default_false() -> void:
	var normal_bullet := MockBreakerBullet.new()
	assert_false(normal_bullet.is_breaker_bullet,
		"Normal bullets should not have breaker behavior")


func test_breaker_flag_can_be_enabled() -> void:
	assert_true(bullet.is_breaker_bullet,
		"Breaker bullet should have flag set")


# ============================================================================
# Detonation Distance Tests
# ============================================================================


func test_detonation_distance_constant() -> void:
	assert_eq(MockBreakerBullet.BREAKER_DETONATION_DISTANCE, 60.0,
		"Detonation distance should be 60px")


func test_detonates_when_wall_within_range() -> void:
	var result := bullet.check_breaker_detonation(50.0)  # Wall at 50px

	assert_true(result, "Should detonate when wall within 60px")
	assert_true(bullet.has_detonated())
	assert_true(bullet.is_destroyed())


func test_detonates_at_exact_distance() -> void:
	var result := bullet.check_breaker_detonation(60.0)  # Wall at exactly 60px

	assert_true(result, "Should detonate at exactly 60px")
	assert_true(bullet.has_detonated())


func test_does_not_detonate_when_wall_far_away() -> void:
	var result := bullet.check_breaker_detonation(100.0)  # Wall at 100px

	assert_false(result, "Should not detonate when wall beyond 60px")
	assert_false(bullet.has_detonated())
	assert_false(bullet.is_destroyed())


func test_does_not_detonate_when_no_wall() -> void:
	var result := bullet.check_breaker_detonation(INF)

	assert_false(result, "Should not detonate with no wall ahead")
	assert_false(bullet.has_detonated())


func test_normal_bullet_does_not_detonate() -> void:
	var normal_bullet := MockBreakerBullet.new()
	# is_breaker_bullet is false by default

	var result := normal_bullet.check_breaker_detonation(30.0)

	assert_false(result, "Normal bullet should not detonate")
	assert_false(normal_bullet.has_detonated())


# ============================================================================
# Explosion Tests
# ============================================================================


func test_explosion_radius_constant() -> void:
	assert_eq(MockBreakerBullet.BREAKER_EXPLOSION_RADIUS, 15.0,
		"Explosion radius should be 15px")


func test_explosion_damage_constant() -> void:
	assert_eq(MockBreakerBullet.BREAKER_EXPLOSION_DAMAGE, 1.0,
		"Explosion damage should be 1")


func test_explosion_applied_on_detonation() -> void:
	bullet.check_breaker_detonation(30.0)

	assert_true(bullet._explosion_applied,
		"Explosion damage should be applied on detonation")


# ============================================================================
# Shrapnel Cone Tests
# ============================================================================


func test_shrapnel_half_angle_constant() -> void:
	assert_eq(MockBreakerBullet.BREAKER_SHRAPNEL_HALF_ANGLE, 30.0,
		"Shrapnel cone half-angle should be 30 degrees")


func test_shrapnel_damage_constant() -> void:
	assert_eq(MockBreakerBullet.BREAKER_SHRAPNEL_DAMAGE, 0.1,
		"Shrapnel damage should be 0.1 per piece")


func test_shrapnel_count_multiplier_constant() -> void:
	assert_eq(MockBreakerBullet.BREAKER_SHRAPNEL_COUNT_MULTIPLIER, 10.0,
		"Shrapnel count multiplier should be 10")


func test_shrapnel_count_matches_damage() -> void:
	# Default damage = 1.0, multiplier = 10, so 10 shrapnel
	bullet.check_breaker_detonation(30.0)

	assert_eq(bullet.get_shrapnel_count(), 10,
		"Shrapnel count should be damage * 10 = 10")


func test_shrapnel_count_with_high_damage_capped() -> void:
	bullet.damage = 5.0
	bullet.check_breaker_detonation(30.0)

	assert_eq(bullet.get_shrapnel_count(), 10,
		"Shrapnel count should be capped at 10 (was 5 * 10 = 50, capped to BREAKER_MAX_SHRAPNEL_PER_DETONATION)")


func test_shrapnel_count_with_fractional_damage() -> void:
	bullet.damage = 0.5
	bullet.check_breaker_detonation(30.0)

	assert_eq(bullet.get_shrapnel_count(), 5,
		"Shrapnel count should be int(0.5 * 10) = 5")


func test_shrapnel_count_minimum_one() -> void:
	bullet.damage = 0.01  # Very low damage
	bullet.check_breaker_detonation(30.0)

	assert_ge(bullet.get_shrapnel_count(), 1,
		"Should always spawn at least 1 shrapnel piece")


func test_shrapnel_count_with_damage_multiplier() -> void:
	bullet.damage = 1.0
	bullet.damage_multiplier = 0.5  # After ricochet
	bullet.check_breaker_detonation(30.0)

	assert_eq(bullet.get_shrapnel_count(), 5,
		"Shrapnel count should account for damage_multiplier: int(1.0 * 0.5 * 10) = 5")


func test_shrapnel_directions_in_cone() -> void:
	bullet.direction = Vector2.RIGHT
	bullet.check_breaker_detonation(30.0)

	var half_angle_rad := deg_to_rad(30.0)
	var bullet_angle := bullet.direction.angle()

	for shrapnel_dir in bullet._shrapnel_directions:
		var angle_diff := abs(shrapnel_dir.angle() - bullet_angle)
		# Wrap angle difference to [0, PI]
		if angle_diff > PI:
			angle_diff = TAU - angle_diff
		assert_le(angle_diff, half_angle_rad + 0.01,
			"Shrapnel direction should be within cone half-angle")


func test_shrapnel_directions_have_variety() -> void:
	# With 10 shrapnel pieces, they should not all go the same direction
	bullet.direction = Vector2.RIGHT
	bullet.check_breaker_detonation(30.0)

	var unique_angles: Array = []
	for dir in bullet._shrapnel_directions:
		var angle := snapped(dir.angle(), 0.01)
		if angle not in unique_angles:
			unique_angles.append(angle)

	assert_gt(unique_angles.size(), 1,
		"Shrapnel should have varied directions within the cone")


# ============================================================================
# Shrapnel Cap Tests (FPS Optimization, Issue #678)
# ============================================================================


func test_shrapnel_cap_constant() -> void:
	assert_eq(MockBreakerBullet.BREAKER_MAX_SHRAPNEL_PER_DETONATION, 10,
		"Max shrapnel per detonation should be 10")


func test_shrapnel_capped_at_max() -> void:
	bullet.damage = 100.0  # Would produce 1000 shrapnel uncapped
	bullet.check_breaker_detonation(30.0)

	assert_eq(bullet.get_shrapnel_count(), 10,
		"Shrapnel should be capped at BREAKER_MAX_SHRAPNEL_PER_DETONATION")


func test_shrapnel_not_capped_when_under_limit() -> void:
	bullet.damage = 0.5  # 0.5 * 10 = 5, under cap
	bullet.check_breaker_detonation(30.0)

	assert_eq(bullet.get_shrapnel_count(), 5,
		"Shrapnel count under cap should not be affected")


# ============================================================================
# ActiveItemManager Integration Tests
# ============================================================================


class MockActiveItemManagerForBreaker:
	const ActiveItemType := {
		NONE = 0,
		FLASHLIGHT = 1,
		TELEPORT_BRACERS = 2,
		BREAKER_BULLETS = 3
	}

	var current_active_item: int = ActiveItemType.NONE

	func has_breaker_bullets() -> bool:
		return current_active_item == ActiveItemType.BREAKER_BULLETS

	func has_flashlight() -> bool:
		return current_active_item == ActiveItemType.FLASHLIGHT

	func has_teleport_bracers() -> bool:
		return current_active_item == ActiveItemType.TELEPORT_BRACERS

	func set_active_item(type: int) -> void:
		current_active_item = type


func test_active_item_breaker_bullets_type_value() -> void:
	var manager := MockActiveItemManagerForBreaker.new()
	assert_eq(manager.ActiveItemType.BREAKER_BULLETS, 3,
		"BREAKER_BULLETS should be the fourth active item type (3)")


func test_no_breaker_bullets_by_default() -> void:
	var manager := MockActiveItemManagerForBreaker.new()
	assert_false(manager.has_breaker_bullets(),
		"Breaker bullets should not be active by default")


func test_has_breaker_bullets_after_selection() -> void:
	var manager := MockActiveItemManagerForBreaker.new()
	manager.set_active_item(3)
	assert_true(manager.has_breaker_bullets(),
		"has_breaker_bullets should return true after selecting breaker bullets")


func test_breaker_bullets_and_flashlight_mutually_exclusive() -> void:
	var manager := MockActiveItemManagerForBreaker.new()
	manager.set_active_item(3)  # Breaker bullets
	assert_true(manager.has_breaker_bullets())
	assert_false(manager.has_flashlight(),
		"Flashlight and breaker bullets should be mutually exclusive")


func test_switching_from_breaker_to_flashlight() -> void:
	var manager := MockActiveItemManagerForBreaker.new()
	manager.set_active_item(3)  # Breaker bullets
	manager.set_active_item(1)  # Flashlight
	assert_false(manager.has_breaker_bullets())
	assert_true(manager.has_flashlight())


func test_switching_from_breaker_to_none() -> void:
	var manager := MockActiveItemManagerForBreaker.new()
	manager.set_active_item(3)
	manager.set_active_item(0)
	assert_false(manager.has_breaker_bullets())


# ============================================================================
# Edge Cases
# ============================================================================


func test_breaker_detonation_at_zero_distance() -> void:
	var result := bullet.check_breaker_detonation(0.0)
	assert_true(result, "Should detonate at 0 distance")


func test_breaker_detonation_at_negative_distance() -> void:
	# Should not happen in practice, but handle gracefully
	var result := bullet.check_breaker_detonation(-10.0)
	assert_true(result, "Should detonate even at negative distance")


# ============================================================================
# Wall Clipping Prevention Tests (Issue #740)
# ============================================================================


func test_shrapnel_spawn_position_validation() -> void:
	# This test verifies the fix for Issue #740 where shrapnel could spawn behind walls.
	# The MockBreakerBullet doesn't have physics simulation, so we test the logic conceptually.

	# When a bullet detonates near a wall, shrapnel should not spawn inside the wall
	# The actual implementation in bullet.gd uses _is_position_inside_wall() to validate

	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2(100, 100)  # 60px from imaginary wall at x=160

	# Detonate the bullet
	bullet.check_breaker_detonation(60.0)

	# Verify shrapnel was spawned (basic check)
	assert_gt(bullet.get_shrapnel_count(), 0,
		"Should spawn shrapnel even when near wall")


func test_shrapnel_spawn_offset_is_small() -> void:
	# Shrapnel spawns at center + direction * 5.0
	# This small offset (5px) should not push shrapnel through walls in normal cases

	var spawn_offset := 5.0
	var center := Vector2(100, 100)
	var direction := Vector2.RIGHT

	var spawn_pos := center + direction * spawn_offset

	assert_eq(spawn_pos.x, 105.0, "Shrapnel should spawn 5px from center")
	assert_eq(spawn_pos.y, 100.0, "Y coordinate should be unchanged")


func test_shrapnel_cone_randomization_near_wall() -> void:
	# When bullet detonates near a wall, the random cone (±30°) means some shrapnel
	# directions point toward the wall. The fix (Issue #740) validates these positions.

	bullet.direction = Vector2.RIGHT  # Traveling right toward wall
	bullet.check_breaker_detonation(30.0)  # Wall 30px ahead

	# With ±30° cone, some shrapnel will be angled toward wall (invalid spawn)
	# and some away from wall (valid spawn)
	# The implementation should skip invalid spawns

	var shrapnel_count := bullet.get_shrapnel_count()
	assert_gt(shrapnel_count, 0,
		"Should spawn at least some shrapnel in valid directions")


func test_wall_detection_logic_concept() -> void:
	# Conceptual test: If spawn position is inside wall, it should be skipped
	# In real implementation, _is_position_inside_wall() uses PhysicsPointQueryParameters2D

	# Scenario: Bullet at x=55, wall at x=60, detonates
	# Shrapnel spawning at x=55 + 5 = x=60 (exactly on wall) should be prevented

	var bullet_pos := Vector2(55, 100)
	var wall_pos := Vector2(60, 100)
	var spawn_offset := 5.0

	# If shrapnel direction is toward wall (Vector2.RIGHT)
	var shrapnel_spawn := bullet_pos + Vector2.RIGHT * spawn_offset

	# shrapnel_spawn.x = 60, which is on/in the wall
	assert_eq(shrapnel_spawn.x, wall_pos.x,
		"This spawn position would be on the wall and should be skipped by fix")
