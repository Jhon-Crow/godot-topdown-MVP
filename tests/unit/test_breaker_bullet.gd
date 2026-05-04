extends GutTest
## Unit tests for Breaker Bullet behavior (Issue #678, #1634).
##
## Tests the breaker bullet detonation logic: wall detection at 95px,
## cone sector enemy detection (Issue #1634), explosion damage in 15px radius,
## shrapnel cone spawning, and ActiveItemManager integration.


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
	const BREAKER_DETONATION_DISTANCE: float = 95.0
	const BREAKER_EXPLOSION_RADIUS: float = 15.0
	const BREAKER_EXPLOSION_DAMAGE: float = 1.0
	## Widened to 45° (Issue #1634) for broader proximity fuse coverage.
	const BREAKER_SHRAPNEL_HALF_ANGLE: float = 45.0
	const BREAKER_SHRAPNEL_DAMAGE: float = 0.1
	const BREAKER_SHRAPNEL_COUNT_MULTIPLIER: float = 10.0
	const BREAKER_MAX_SHRAPNEL_PER_DETONATION: int = 10
	## Minimum travel distance before enemy-cone fuse arms (Issue #1634 arming fix).
	const BREAKER_ARMING_DISTANCE: float = 40.0

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

	## Simulate checking for breaker detonation by wall distance only.
	## wall_distance: simulated distance to wall (INF if no wall ahead)
	func check_breaker_detonation(wall_distance: float) -> bool:
		if not is_breaker_bullet:
			return false

		if wall_distance > BREAKER_DETONATION_DISTANCE:
			return false

		# Wall detected within range — detonate
		_breaker_detonate()
		return true

	## Simulate cone sector check: returns true and detonates if enemy_pos is
	## within the shrapnel cone sector (distance <= BREAKER_DETONATION_DISTANCE
	## AND angle from direction <= BREAKER_SHRAPNEL_HALF_ANGLE)
	## AND line of sight is not blocked (has_line_of_sight = true, default)
	## AND distance_traveled >= BREAKER_ARMING_DISTANCE (Issue #1634 arming fix).
	## Pass Vector2.INF (or a position outside range/cone) to simulate no enemy.
	## Pass has_line_of_sight=false to simulate a wall between bullet and enemy.
	## Pass distance_traveled < BREAKER_ARMING_DISTANCE to simulate unarmed fuse.
	func check_enemy_in_shrapnel_cone(enemy_pos: Vector2, has_line_of_sight: bool = true, distance_traveled: float = BREAKER_ARMING_DISTANCE) -> bool:
		if not is_breaker_bullet:
			return false
		# Arming distance guard: cone fuse only triggers after bullet travels BREAKER_ARMING_DISTANCE
		if distance_traveled < BREAKER_ARMING_DISTANCE:
			return false
		if _is_target_in_shrapnel_cone(enemy_pos, has_line_of_sight):
			_breaker_detonate()
			return true
		return false

	## Simulate the RPG rocket cone fuse check added in Issue #1955.
	func check_rpg_rocket_in_shrapnel_cone(rocket_pos: Vector2, has_line_of_sight: bool = true, distance_traveled: float = BREAKER_ARMING_DISTANCE) -> bool:
		if not is_breaker_bullet:
			return false
		if distance_traveled < BREAKER_ARMING_DISTANCE:
			return false
		if _is_target_in_shrapnel_cone(rocket_pos, has_line_of_sight):
			_breaker_detonate()
			return true
		return false

	func _is_target_in_shrapnel_cone(target_pos: Vector2, has_line_of_sight: bool = true) -> bool:
		var cos_half_angle := cos(deg_to_rad(BREAKER_SHRAPNEL_HALF_ANGLE))
		var to_target := target_pos - global_position
		var dist := to_target.length()
		if dist > BREAKER_DETONATION_DISTANCE:
			return false
		if dist <= 0.0:
			return false
		if (to_target / dist).dot(direction) < cos_half_angle:
			return false
		# Only detonate if there is no wall blocking line of sight (Issue #1634 fix)
		if not has_line_of_sight:
			return false
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
	assert_eq(MockBreakerBullet.BREAKER_DETONATION_DISTANCE, 95.0,
		"Detonation distance should be 95px")


func test_detonates_when_wall_within_range() -> void:
	var result := bullet.check_breaker_detonation(50.0)  # Wall at 50px

	assert_true(result, "Should detonate when wall within 95px")
	assert_true(bullet.has_detonated())
	assert_true(bullet.is_destroyed())


func test_detonates_at_exact_distance() -> void:
	var result := bullet.check_breaker_detonation(95.0)  # Wall at exactly 95px

	assert_true(result, "Should detonate at exactly 95px")
	assert_true(bullet.has_detonated())


func test_does_not_detonate_when_wall_far_away() -> void:
	var result := bullet.check_breaker_detonation(150.0)  # Wall at 150px

	assert_false(result, "Should not detonate when wall beyond 95px")
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
	assert_eq(MockBreakerBullet.BREAKER_SHRAPNEL_HALF_ANGLE, 45.0,
		"Shrapnel cone half-angle should be 45 degrees (widened in Issue #1634)")


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

	var half_angle_rad := deg_to_rad(45.0)  # Widened to 45° (Issue #1634)
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
	bullet.global_position = Vector2(100, 100)  # 95px from imaginary wall at x=195

	# Detonate the bullet
	bullet.check_breaker_detonation(95.0)

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
	# When bullet detonates near a wall, the random cone (±45°, widened in Issue #1634) means some
	# shrapnel directions point toward the wall. The fix (Issue #740) validates these positions.

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


# ============================================================================
# Cone Sector Enemy Detection Tests (Issue #1634)
# ============================================================================


func test_detonates_when_enemy_directly_ahead_in_cone() -> void:
	# Enemy at 50px directly ahead (within detonation distance and in cone centre)
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var enemy_pos := Vector2(50.0, 0.0)

	var result := bullet.check_enemy_in_shrapnel_cone(enemy_pos)

	assert_true(result, "Should detonate when enemy is directly ahead within range")
	assert_true(bullet.has_detonated())


func test_detonates_when_enemy_at_cone_edge_angle() -> void:
	# Enemy at exactly 45° from bullet direction, within detonation distance (cone widened to 45°)
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var dist := 80.0
	var angle_rad := deg_to_rad(45.0)  # Exactly at cone boundary (45° after Issue #1634 widening)
	var enemy_pos := Vector2(dist * cos(angle_rad), dist * sin(angle_rad))

	var result := bullet.check_enemy_in_shrapnel_cone(enemy_pos)

	assert_true(result, "Should detonate when enemy is at the cone's edge angle (45°)")
	assert_true(bullet.has_detonated())


func test_does_not_detonate_when_enemy_outside_cone_angle() -> void:
	# Enemy at 60° from bullet direction (beyond ±45° half-angle, widened in Issue #1634)
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var dist := 50.0
	var angle_rad := deg_to_rad(60.0)  # Outside cone (cone is now ±45°)
	var enemy_pos := Vector2(dist * cos(angle_rad), dist * sin(angle_rad))

	var result := bullet.check_enemy_in_shrapnel_cone(enemy_pos)

	assert_false(result, "Should NOT detonate when enemy is outside cone angle (60° > 45° half-angle)")
	assert_false(bullet.has_detonated())


func test_does_not_detonate_when_enemy_in_cone_but_too_far() -> void:
	# Enemy at 0° (directly ahead) but beyond BREAKER_DETONATION_DISTANCE
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var enemy_pos := Vector2(150.0, 0.0)  # 150px > 95px

	var result := bullet.check_enemy_in_shrapnel_cone(enemy_pos)

	assert_false(result, "Should NOT detonate when enemy is in cone angle but beyond range")
	assert_false(bullet.has_detonated())


func test_does_not_detonate_when_enemy_behind_bullet() -> void:
	# Enemy directly behind the bullet (180°)
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var enemy_pos := Vector2(-50.0, 0.0)

	var result := bullet.check_enemy_in_shrapnel_cone(enemy_pos)

	assert_false(result, "Should NOT detonate when enemy is behind the bullet")
	assert_false(bullet.has_detonated())


func test_detonates_when_enemy_in_cone_at_exact_detonation_distance() -> void:
	# Enemy exactly at BREAKER_DETONATION_DISTANCE (95px) directly ahead
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var enemy_pos := Vector2(95.0, 0.0)

	var result := bullet.check_enemy_in_shrapnel_cone(enemy_pos)

	assert_true(result, "Should detonate when enemy is at exactly 95px directly ahead")
	assert_true(bullet.has_detonated())


func test_cone_check_uses_bullet_direction_not_just_right() -> void:
	# Bullet moving upward — enemy directly above should trigger, enemy to the right should not
	bullet.direction = Vector2.UP
	bullet.global_position = Vector2.ZERO

	var bullet_copy := MockBreakerBullet.new()
	bullet_copy.is_breaker_bullet = true
	bullet_copy.direction = Vector2.UP
	bullet_copy.global_position = Vector2.ZERO

	# Enemy at 50px above (directly in travel direction)
	var enemy_ahead := Vector2(0.0, -50.0)
	var result_ahead := bullet.check_enemy_in_shrapnel_cone(enemy_ahead)
	assert_true(result_ahead, "Enemy directly ahead (up) should trigger cone detonation")

	# Enemy at 50px to the right (90° from bullet direction UP — outside cone)
	var enemy_right := Vector2(50.0, 0.0)
	var result_right := bullet_copy.check_enemy_in_shrapnel_cone(enemy_right)
	assert_false(result_right, "Enemy 90° to the side should NOT trigger cone detonation")


func test_normal_bullet_does_not_detonate_via_cone_check() -> void:
	var normal_bullet := MockBreakerBullet.new()
	normal_bullet.is_breaker_bullet = false
	normal_bullet.direction = Vector2.RIGHT
	normal_bullet.global_position = Vector2.ZERO

	var result := normal_bullet.check_enemy_in_shrapnel_cone(Vector2(30.0, 0.0))

	assert_false(result, "Normal bullet should not detonate via cone check")


func test_does_not_detonate_when_enemy_in_cone_but_wall_blocks_los() -> void:
	# Root cause fix (Issue #1634): enemy in cone but behind a wall — must NOT detonate.
	# Previously, missing LOS check caused bullets to detonate against enemies through walls.
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var enemy_pos := Vector2(50.0, 0.0)  # In cone, within range

	# Simulate wall between bullet and enemy (has_line_of_sight=false)
	var result := bullet.check_enemy_in_shrapnel_cone(enemy_pos, false)

	assert_false(result, "Should NOT detonate when enemy in cone but wall blocks line of sight")
	assert_false(bullet.has_detonated())


func test_detonates_when_enemy_in_cone_with_clear_los() -> void:
	# Confirm baseline: enemy in cone, no wall blocking — should detonate.
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var enemy_pos := Vector2(50.0, 0.0)  # In cone, within range

	# Simulate clear line of sight (has_line_of_sight=true, default)
	var result := bullet.check_enemy_in_shrapnel_cone(enemy_pos, true)

	assert_true(result, "Should detonate when enemy in cone with clear line of sight")
	assert_true(bullet.has_detonated())


# ============================================================================
# Arming Distance Tests (Issue #1634 — prevents immediate detonation on spawn)
# ============================================================================


func test_arming_distance_constant() -> void:
	assert_eq(MockBreakerBullet.BREAKER_ARMING_DISTANCE, 40.0,
		"Arming distance should be 40px")


func test_does_not_detonate_via_cone_before_arming() -> void:
	# Root cause of 'pistol bullets still broken': enemy within 95px in cone at fire time
	# caused immediate detonation even with LOS check. Arming distance prevents this.
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var enemy_pos := Vector2(50.0, 0.0)  # In cone, within range, clear LOS

	# Bullet has not yet traveled the arming distance (just spawned)
	var result := bullet.check_enemy_in_shrapnel_cone(enemy_pos, true, 0.0)

	assert_false(result, "Should NOT detonate via cone when bullet has not traveled arming distance yet")
	assert_false(bullet.has_detonated())


func test_detonates_via_cone_after_arming() -> void:
	# After traveling >= BREAKER_ARMING_DISTANCE, the cone fuse activates normally.
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var enemy_pos := Vector2(50.0, 0.0)  # In cone, within range, clear LOS

	# Bullet has traveled exactly the arming distance
	var result := bullet.check_enemy_in_shrapnel_cone(enemy_pos, true, MockBreakerBullet.BREAKER_ARMING_DISTANCE)

	assert_true(result, "Should detonate via cone after bullet has traveled the arming distance")
	assert_true(bullet.has_detonated())


func test_detonates_when_rpg_rocket_ahead_in_cone_after_arming() -> void:
	# Issue #1955: proximity-fuse bullets must react to RPG rockets, not only enemies.
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var rocket_pos := Vector2(70.0, 0.0)

	var result := bullet.check_rpg_rocket_in_shrapnel_cone(rocket_pos, true, MockBreakerBullet.BREAKER_ARMING_DISTANCE)

	assert_true(result, "Should detonate when an RPG rocket is directly ahead within range")
	assert_true(bullet.has_detonated())


func test_does_not_detonate_for_rpg_rocket_before_arming() -> void:
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var rocket_pos := Vector2(70.0, 0.0)

	var result := bullet.check_rpg_rocket_in_shrapnel_cone(rocket_pos, true, 0.0)

	assert_false(result, "Should not detonate on an RPG rocket before the cone fuse arms")
	assert_false(bullet.has_detonated())


func test_does_not_detonate_for_rpg_rocket_when_wall_blocks_los() -> void:
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	var rocket_pos := Vector2(70.0, 0.0)

	var result := bullet.check_rpg_rocket_in_shrapnel_cone(rocket_pos, false, MockBreakerBullet.BREAKER_ARMING_DISTANCE)

	assert_false(result, "Should not detonate on an RPG rocket through a wall")
	assert_false(bullet.has_detonated())


func test_wall_check_still_works_before_arming() -> void:
	# The wall check (straight raycast) must still trigger even before arming.
	# Only the enemy-cone check is gated by arming distance.
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO

	# Wall at 30px — should still detonate regardless of arming
	var result := bullet.check_breaker_detonation(30.0)

	assert_true(result, "Wall check should still trigger before arming distance is reached")
	assert_true(bullet.has_detonated())


# ============================================================================
# Object Pool Interaction Tests (Issue #1634 Session 4 — Pool Bug Fix)
# ============================================================================
# When the ProjectilePoolManager recycles a bullet, pool_activate() calls
# _reset_state() which clears _breaker_shrapnel_scene and _breaker_distance_traveled.
# These tests verify the fix: set_is_breaker_bullet() reloads the shrapnel scene,
# and _reset_state() now resets _breaker_distance_traveled to 0.


class MockPooledBreakerBullet extends MockBreakerBullet:
	## Simulates the shrapnel scene reference (null = not loaded).
	var _breaker_shrapnel_scene_loaded: bool = false

	## Distance traveled since spawn (for arming).
	var _breaker_distance_traveled: float = 0.0

	## Simulate pool_activate() → _reset_state() clearing breaker state.
	func simulate_pool_reset() -> void:
		is_breaker_bullet = false
		_breaker_shrapnel_scene_loaded = false
		# Session 4 fix: _breaker_distance_traveled must also be reset to 0
		_breaker_distance_traveled = 0.0

	## Simulate set_is_breaker_bullet() with the Session 4 fix applied:
	## reloads shrapnel scene when it was cleared by pool reset.
	func set_is_breaker_bullet_fixed(is_breaker: bool) -> void:
		is_breaker_bullet = is_breaker
		# Fixed: reload shrapnel scene if it was cleared (e.g., by pool reset)
		if is_breaker and not _breaker_shrapnel_scene_loaded:
			_breaker_shrapnel_scene_loaded = true  # Simulates loading the scene

	## Simulate old (unfixed) set_is_breaker_bullet() — only sets the flag.
	func set_is_breaker_bullet_broken(is_breaker: bool) -> void:
		is_breaker_bullet = is_breaker
		# Bug: does NOT reload shrapnel scene — it remains null from pool reset

	## Whether shrapnel can spawn (requires scene loaded OR pool available).
	func can_spawn_shrapnel() -> bool:
		# Session 4 fix: allow pool-based shrapnel even if scene is null
		# In tests we simulate pool availability as false (unit test, no pool manager)
		return _breaker_shrapnel_scene_loaded


func test_pool_bullet_reloads_shrapnel_scene() -> void:
	# Root cause (Session 4): pool_activate() → _reset_state() clears shrapnel scene.
	# Fix: set_is_breaker_bullet() reloads the scene when it was cleared.
	var pooled := MockPooledBreakerBullet.new()

	# Simulate: bullet used previously, then returned to pool and reset
	pooled._breaker_shrapnel_scene_loaded = true  # Had scene from first use
	pooled._breaker_distance_traveled = 120.0     # Had traveled far on first use
	pooled.simulate_pool_reset()                   # Pool reuse: clears everything

	assert_false(pooled.is_breaker_bullet,
		"After pool reset, is_breaker_bullet should be false")
	assert_false(pooled._breaker_shrapnel_scene_loaded,
		"After pool reset, shrapnel scene reference should be cleared")
	assert_eq(pooled._breaker_distance_traveled, 0.0,
		"After pool reset, arming distance should reset to 0")

	# Now activate as breaker bullet (simulating player.gd calling set_is_breaker_bullet)
	pooled.set_is_breaker_bullet_fixed(true)

	assert_true(pooled.is_breaker_bullet,
		"After set_is_breaker_bullet(true), flag should be set")
	assert_true(pooled._breaker_shrapnel_scene_loaded,
		"After set_is_breaker_bullet(true), shrapnel scene should be reloaded")
	assert_true(pooled.can_spawn_shrapnel(),
		"After fix: pooled breaker bullet should be able to spawn shrapnel")


func test_pool_bullet_without_fix_cannot_spawn_shrapnel() -> void:
	# Verify the bug exists without the fix (regression guard).
	var pooled := MockPooledBreakerBullet.new()

	# Simulate pool reuse
	pooled._breaker_shrapnel_scene_loaded = true
	pooled.simulate_pool_reset()

	# Unfixed setter: does NOT reload shrapnel scene
	pooled.set_is_breaker_bullet_broken(true)

	assert_true(pooled.is_breaker_bullet,
		"is_breaker_bullet flag should still be set")
	assert_false(pooled._breaker_shrapnel_scene_loaded,
		"Without fix: shrapnel scene remains null after pool reset")
	assert_false(pooled.can_spawn_shrapnel(),
		"Without fix: pooled breaker bullet cannot spawn shrapnel (regression guard)")


func test_pool_bullet_resets_arming_distance() -> void:
	# Root cause (Session 4): _reset_state() did not reset _breaker_distance_traveled.
	# A bullet that traveled 120px on its first use would be re-armed immediately on reuse.
	var pooled := MockPooledBreakerBullet.new()

	# Simulate: bullet traveled well past arming distance on first use
	pooled._breaker_distance_traveled = 120.0  # Well past 40px arming distance

	# Before fix: pool reset did NOT clear _breaker_distance_traveled
	# This is now fixed — simulate_pool_reset() resets it to 0
	pooled.simulate_pool_reset()

	assert_eq(pooled._breaker_distance_traveled, 0.0,
		"After pool reset, arming distance MUST be 0 so the fuse is not pre-armed")

	# After pool reset, the new bullet starts fresh: cone check should not fire yet
	pooled.set_is_breaker_bullet_fixed(true)
	var result := pooled.check_enemy_in_shrapnel_cone(
		Vector2(50.0, 0.0), true, pooled._breaker_distance_traveled)

	assert_false(result,
		"Recycled bullet starts with _breaker_distance_traveled=0, should not arm immediately")


func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _extract_csharp_method(source: String, signature: String) -> String:
	var start := source.find(signature)
	assert_true(start >= 0, "Source should contain method signature: %s" % signature)
	if start < 0:
		return ""
	var depth := 0
	var saw_open_brace := false
	for i in range(start, source.length()):
		var ch := source.substr(i, 1)
		if ch == "{":
			depth += 1
			saw_open_brace = true
		elif ch == "}":
			depth -= 1
			if saw_open_brace and depth == 0:
				return source.substr(start, i - start + 1)
	return source.substr(start)


func test_csharp_breaker_shrapnel_uses_pool_fallback_when_scene_missing() -> void:
	# Regression for PM/Bullet9mm exported builds: MakarovPM fires the C# Bullet.cs path,
	# whose BreakerDetonation helper used to return immediately when GD.Load<PackedScene>
	# failed and therefore produced explosions without visible breaker shrapnel.
	var source := _read_text_file("res://Scripts/Projectiles/BreakerDetonation.cs")
	var body := _extract_csharp_method(source, "private static void SpawnShrapnel(")

	assert_true(body.contains("GetNodeOrNull(\"/root/ProjectilePoolManager\")"),
		"C# breaker shrapnel should ask ProjectilePoolManager for pooled fragments")
	assert_true(body.contains("get_breaker_shrapnel"),
		"C# breaker shrapnel should use the breaker shrapnel pool")
	assert_true(body.contains("shrapnelScene == null && !canUsePool"),
		"C# breaker shrapnel must only return early when both scene and pool fallback are unavailable")
	assert_true(body.contains("pool_activate"),
		"Pooled breaker shrapnel should be activated instead of manually added to the scene")
	assert_true(body.contains("pool_activate\", spawnPosition, shrapnelDirection, (int)shooterId, ShrapnelDamage, shrapnelSpeed"),
		"C# pooled breaker shrapnel should receive damage and speed during activation")
	assert_false(body.contains("pooledShrapnel.Set(\"damage\", ShrapnelDamage)"),
		"C# pooled breaker shrapnel should not set damage after activation")
	assert_false(body.contains("pooledShrapnel.Set(\"speed\", shrapnelSpeed)"),
		"C# pooled breaker shrapnel should not set speed after activation")
	assert_true(body.contains("var fallbackScene = shrapnelScene ?? GetShrapnelScene();"),
		"C# breaker shrapnel should retry the PackedScene fallback after a pool miss")
	assert_true(body.contains("fallbackScene.Instantiate<Node2D>()"),
		"C# breaker shrapnel should instantiate from the refreshed fallback scene when the pool misses")
	assert_eq(body.find("var shrapnelScene = GetShrapnelScene();\n        if (shrapnelScene == null)\n        {\n            return;\n        }"), -1,
		"C# breaker shrapnel must not skip spawning just because the PackedScene cache is null")


func test_csharp_deferred_weapon_selection_keeps_breaker_bullets_active() -> void:
	# Issue #1949: affected C# fallback maps first initialize breaker bullets on the
	# default MakarovPM, then ApplySelectedWeaponFromGameManager replaces the weapon.
	# The replacement path must reapply passive item flags to the new weapon.
	var player_source := _read_text_file("res://Scripts/Characters/Player.cs")
	var active_items_source := _read_text_file("res://Scripts/Characters/Player.ActiveItems.cs")
	var equip_body := _extract_csharp_method(player_source, "public void EquipWeapon(BaseWeapon weapon)")
	var deferred_body := _extract_csharp_method(player_source, "private void ApplySelectedWeaponFromGameManager()")
	var sync_body := _extract_csharp_method(active_items_source, "private void SyncBreakerBulletsToCurrentWeapon()")

	assert_true(active_items_source.contains("SyncBreakerBulletsToCurrentWeapon();"),
		"InitBreakerBullets should use the shared sync helper")
	assert_true(equip_body.contains("SyncBreakerBulletsToCurrentWeapon();"),
		"EquipWeapon should propagate breaker bullets to every newly equipped weapon")
	assert_true(deferred_body.contains("CurrentWeapon = weapon;\n            // Apply passive item flags after deferred fallback weapon replacement (Issue #1949).\n            SyncBreakerBulletsToCurrentWeapon();"),
		"Deferred GameManager weapon replacement should sync breaker bullets after assigning CurrentWeapon")
	assert_true(sync_body.contains("CurrentWeapon.IsBreakerBulletActive = _breakerBulletsActive;"),
		"The sync helper should copy the passive item flag to the current C# weapon")
