extends GutTest
## Unit tests for the homing bullets active item (Issue #677).
##
## Tests the homing bullet steering logic, charge management,
## activation/deactivation timing, and angle limiting behavior.


# ============================================================================
# Mock Homing Bullet Logic
# ============================================================================


class MockHomingBullet:
	## Whether homing is enabled on this bullet.
	var homing_enabled: bool = false

	## Maximum turn angle from original direction (radians).
	var homing_max_turn_angle: float = deg_to_rad(110.0)

	## Steering speed in radians per second.
	var homing_steer_speed: float = 8.0

	## Current bullet direction (normalized).
	var direction: Vector2 = Vector2.RIGHT

	## Original firing direction (stored when homing enabled).
	var _homing_original_direction: Vector2 = Vector2.ZERO

	## Bullet global position.
	var global_position: Vector2 = Vector2.ZERO

	## Speed of the bullet.
	var speed: float = 2500.0

	## Rotation angle.
	var rotation: float = 0.0

	## Enable homing.
	func enable_homing() -> void:
		homing_enabled = true
		_homing_original_direction = direction.normalized()

	## Apply homing steering toward a target position.
	## Returns the angle change applied (for testing).
	func apply_homing_toward(target_pos: Vector2, delta: float) -> float:
		if not homing_enabled:
			return 0.0

		if target_pos == Vector2.ZERO:
			return 0.0

		# Calculate desired direction toward target
		var to_target := (target_pos - global_position).normalized()

		# Calculate the angle difference
		var angle_diff := direction.angle_to(to_target)

		# Limit per-frame steering
		var max_steer_this_frame := homing_steer_speed * delta
		angle_diff = clampf(angle_diff, -max_steer_this_frame, max_steer_this_frame)

		# Calculate proposed new direction
		var new_direction := direction.rotated(angle_diff).normalized()

		# Check if new direction exceeds max turn angle from original
		var angle_from_original := _homing_original_direction.angle_to(new_direction)
		if absf(angle_from_original) > homing_max_turn_angle:
			return 0.0  # Angle limit reached

		# Apply steering
		direction = new_direction
		rotation = direction.angle()

		return angle_diff


# ============================================================================
# Mock Homing Charge Manager (simulates player.gd homing logic)
# ============================================================================


class MockHomingChargeManager:
	## Whether homing bullets are equipped.
	var homing_equipped: bool = false

	## Whether homing is currently active.
	var homing_active: bool = false

	## Remaining charges.
	var homing_charges: int = 6

	## Max charges per battle.
	const MAX_CHARGES: int = 6

	## Duration per activation.
	const DURATION: float = 1.0

	## Remaining timer.
	var homing_timer: float = 0.0

	## Signal tracking.
	var activated_count: int = 0
	var deactivated_count: int = 0
	var last_charges_emitted: int = -1

	## Activate homing (simulates Space press).
	func activate() -> bool:
		if not homing_equipped:
			return false
		if homing_charges <= 0:
			return false
		if homing_active:
			return false

		homing_active = true
		homing_timer = DURATION
		homing_charges -= 1
		activated_count += 1
		last_charges_emitted = homing_charges
		return true

	## Update timer (simulates _physics_process delta).
	func update(delta: float) -> void:
		if not homing_active:
			return

		homing_timer -= delta
		if homing_timer <= 0.0:
			homing_active = false
			homing_timer = 0.0
			deactivated_count += 1


# ============================================================================
# Homing Bullet Steering Tests
# ============================================================================


func test_homing_disabled_by_default() -> void:
	var bullet := MockHomingBullet.new()
	assert_false(bullet.homing_enabled,
		"Homing should be disabled by default")


func test_enable_homing_sets_flag() -> void:
	var bullet := MockHomingBullet.new()
	bullet.enable_homing()
	assert_true(bullet.homing_enabled,
		"Homing should be enabled after enable_homing()")


func test_enable_homing_stores_original_direction() -> void:
	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2(1, 1).normalized()
	bullet.enable_homing()
	assert_almost_eq(bullet._homing_original_direction.x, bullet.direction.x, 0.001,
		"Original direction X should match")
	assert_almost_eq(bullet._homing_original_direction.y, bullet.direction.y, 0.001,
		"Original direction Y should match")


func test_homing_steers_toward_target() -> void:
	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	bullet.enable_homing()

	# Target is above-right (should steer upward)
	var target := Vector2(100, -100)
	var angle_change := bullet.apply_homing_toward(target, 0.016)  # ~60fps

	# Direction should have changed (Y should be negative now)
	assert_true(bullet.direction.y < 0.0,
		"Bullet should steer upward toward target above")
	assert_true(angle_change != 0.0,
		"Angle change should be non-zero")


func test_homing_does_nothing_when_disabled() -> void:
	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	# Don't enable homing

	var target := Vector2(100, -100)
	var angle_change := bullet.apply_homing_toward(target, 0.016)

	assert_eq(angle_change, 0.0,
		"No steering should occur when homing is disabled")
	assert_eq(bullet.direction, Vector2.RIGHT,
		"Direction should not change when homing disabled")


func test_homing_no_target_no_steering() -> void:
	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.enable_homing()

	var angle_change := bullet.apply_homing_toward(Vector2.ZERO, 0.016)

	assert_eq(angle_change, 0.0,
		"No steering should occur with zero target")


func test_homing_max_turn_angle_default_110_degrees() -> void:
	var bullet := MockHomingBullet.new()
	var expected := deg_to_rad(110.0)
	assert_almost_eq(bullet.homing_max_turn_angle, expected, 0.001,
		"Default max turn angle should be 110 degrees in radians")


func test_homing_respects_angle_limit() -> void:
	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	bullet.homing_steer_speed = 100.0  # Very fast steering to hit limit quickly
	bullet.enable_homing()

	# Target is directly behind (180 degrees away, exceeds 110 limit)
	var target := Vector2(-100, 0)

	# Apply many steering frames to try to reach the limit
	for i in range(100):
		bullet.apply_homing_toward(target, 0.016)

	# Check that the angle from original direction doesn't exceed max
	var angle_from_original := absf(bullet._homing_original_direction.angle_to(bullet.direction))
	assert_true(angle_from_original <= bullet.homing_max_turn_angle + 0.01,
		"Total turn should not exceed max angle limit (110°), got: %s°" % rad_to_deg(angle_from_original))


func test_homing_steers_left() -> void:
	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	bullet.enable_homing()

	# Target is below (should steer downward/clockwise)
	var target := Vector2(100, 100)
	bullet.apply_homing_toward(target, 0.016)

	assert_true(bullet.direction.y > 0.0,
		"Bullet should steer downward toward target below")


func test_homing_steers_right() -> void:
	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	bullet.enable_homing()

	# Target is above (should steer upward/counter-clockwise)
	var target := Vector2(100, -100)
	bullet.apply_homing_toward(target, 0.016)

	assert_true(bullet.direction.y < 0.0,
		"Bullet should steer upward toward target above")


func test_homing_updates_rotation() -> void:
	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.rotation = 0.0
	bullet.global_position = Vector2.ZERO
	bullet.enable_homing()

	var target := Vector2(100, -100)
	bullet.apply_homing_toward(target, 0.016)

	assert_true(bullet.rotation != 0.0,
		"Rotation should update with direction change")


func test_homing_smooth_steering_limits_per_frame() -> void:
	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO
	bullet.homing_steer_speed = 2.0  # Slow steering
	bullet.enable_homing()

	# Target 90 degrees away
	var target := Vector2(0, -100)
	var angle_change := bullet.apply_homing_toward(target, 0.016)

	# With steer_speed=2.0 and delta=0.016, max change = 0.032 radians (~1.83°)
	assert_true(absf(angle_change) <= 2.0 * 0.016 + 0.001,
		"Per-frame steering should be limited by steer_speed * delta")


# ============================================================================
# Homing Charge Manager Tests
# ============================================================================


func test_charge_manager_default_not_equipped() -> void:
	var mgr := MockHomingChargeManager.new()
	assert_false(mgr.homing_equipped,
		"Should not be equipped by default")


func test_charge_manager_default_charges() -> void:
	var mgr := MockHomingChargeManager.new()
	assert_eq(mgr.homing_charges, 6,
		"Should start with 6 charges")


func test_charge_manager_max_charges() -> void:
	var mgr := MockHomingChargeManager.new()
	assert_eq(mgr.MAX_CHARGES, 6,
		"Max charges should be 6")


func test_charge_manager_duration() -> void:
	var mgr := MockHomingChargeManager.new()
	assert_eq(mgr.DURATION, 1.0,
		"Activation duration should be 1 second")


func test_activate_fails_when_not_equipped() -> void:
	var mgr := MockHomingChargeManager.new()
	var result := mgr.activate()
	assert_false(result, "Should not activate when not equipped")
	assert_false(mgr.homing_active, "Should not be active")


func test_activate_succeeds_when_equipped() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true
	var result := mgr.activate()
	assert_true(result, "Should activate when equipped with charges")
	assert_true(mgr.homing_active, "Should be active after activation")


func test_activate_decrements_charge() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true
	mgr.activate()
	assert_eq(mgr.homing_charges, 5,
		"Should decrement charge on activation")


func test_activate_sets_timer() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true
	mgr.activate()
	assert_eq(mgr.homing_timer, 1.0,
		"Timer should be set to duration on activation")


func test_activate_emits_signal() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true
	mgr.activate()
	assert_eq(mgr.activated_count, 1,
		"Activation signal should be emitted")
	assert_eq(mgr.last_charges_emitted, 5,
		"Charge change signal should report remaining charges")


func test_cannot_activate_when_already_active() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true
	mgr.activate()
	var result := mgr.activate()
	assert_false(result, "Should not activate while already active")
	assert_eq(mgr.homing_charges, 5,
		"Charge should not be decremented on failed activation")


func test_cannot_activate_with_zero_charges() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true
	mgr.homing_charges = 0
	var result := mgr.activate()
	assert_false(result, "Should not activate with zero charges")


func test_timer_expires_deactivates() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true
	mgr.activate()

	# Simulate 1 second passing
	mgr.update(1.0)

	assert_false(mgr.homing_active,
		"Should deactivate after timer expires")
	assert_eq(mgr.deactivated_count, 1,
		"Deactivation signal should be emitted")


func test_timer_partial_update() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true
	mgr.activate()

	# Simulate 0.5 seconds (half duration)
	mgr.update(0.5)

	assert_true(mgr.homing_active,
		"Should still be active at 0.5 seconds")
	assert_almost_eq(mgr.homing_timer, 0.5, 0.001,
		"Timer should be at 0.5 seconds remaining")


func test_use_all_six_charges() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true

	for i in range(6):
		assert_true(mgr.activate(), "Activation %d should succeed" % (i + 1))
		mgr.update(1.1)  # Let it expire

	assert_eq(mgr.homing_charges, 0,
		"All 6 charges should be used")
	assert_false(mgr.activate(),
		"7th activation should fail (no charges)")


func test_update_does_nothing_when_inactive() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true

	# Update without activation
	mgr.update(1.0)

	assert_false(mgr.homing_active,
		"Should remain inactive")
	assert_eq(mgr.deactivated_count, 0,
		"No deactivation signal when not active")


func test_reactivate_after_expiry() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true

	# First activation
	mgr.activate()
	mgr.update(1.1)  # Let it expire

	# Second activation
	var result := mgr.activate()
	assert_true(result, "Should be able to reactivate after expiry")
	assert_eq(mgr.homing_charges, 4,
		"Should have 4 charges remaining after 2 activations")


# ============================================================================
# Integration-Like Tests (Bullet + Charge Manager)
# ============================================================================


func test_bullet_homing_during_active_charge() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true

	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO

	# Activate homing
	mgr.activate()

	# Enable homing on bullet (simulates what player._shoot() does)
	if mgr.homing_active:
		bullet.enable_homing()

	assert_true(bullet.homing_enabled,
		"Bullet should have homing enabled during active charge")

	# Steer toward target
	var target := Vector2(100, -50)
	var angle_change := bullet.apply_homing_toward(target, 0.016)

	assert_true(angle_change != 0.0,
		"Bullet should steer toward target")


func test_bullet_no_homing_when_charge_inactive() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true

	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO

	# Don't activate homing
	if mgr.homing_active:
		bullet.enable_homing()

	assert_false(bullet.homing_enabled,
		"Bullet should NOT have homing when charge is inactive")


func test_bullet_keeps_homing_after_charge_expires() -> void:
	var mgr := MockHomingChargeManager.new()
	mgr.homing_equipped = true

	var bullet := MockHomingBullet.new()
	bullet.direction = Vector2.RIGHT
	bullet.global_position = Vector2.ZERO

	# Activate and enable on bullet
	mgr.activate()
	bullet.enable_homing()

	# Charge expires
	mgr.update(1.1)

	# Bullet should still home (it was already fired with homing)
	assert_true(bullet.homing_enabled,
		"Already-fired homing bullet should keep homing after charge expires")

	var target := Vector2(100, -50)
	var angle_change := bullet.apply_homing_toward(target, 0.016)
	assert_true(angle_change != 0.0,
		"Already-fired homing bullet should still steer")


# ============================================================================
# Mock Homing Pellet (Issue #704 - Shotgun Pellet Homing)
# ============================================================================


class MockHomingPellet:
	## Whether homing is enabled on this pellet.
	var homing_enabled: bool = false

	## Maximum turn angle from original direction (radians).
	var homing_max_turn_angle: float = deg_to_rad(110.0)

	## Steering speed in radians per second.
	var homing_steer_speed: float = 8.0

	## Current pellet direction (normalized).
	var direction: Vector2 = Vector2.RIGHT

	## Original firing direction.
	var _homing_original_direction: Vector2 = Vector2.ZERO

	## Pellet global position.
	var global_position: Vector2 = Vector2.ZERO

	## Rotation angle.
	var rotation: float = 0.0

	## Aim-line targeting fields (Issue #704).
	var _use_aim_line_targeting: bool = false
	var _shooter_origin: Vector2 = Vector2.ZERO
	var _shooter_aim_direction: Vector2 = Vector2.ZERO

	## Enable homing (for airborne pellets).
	func enable_homing() -> void:
		homing_enabled = true
		_homing_original_direction = direction.normalized()

	## Enable homing with aim-line targeting (for newly fired pellets).
	func enable_homing_with_aim_line(shooter_pos: Vector2, aim_dir: Vector2) -> void:
		homing_enabled = true
		_homing_original_direction = direction.normalized()
		_use_aim_line_targeting = true
		_shooter_origin = shooter_pos
		_shooter_aim_direction = aim_dir.normalized()

	## Apply homing steering toward a target position.
	func apply_homing_toward(target_pos: Vector2, delta: float) -> float:
		if not homing_enabled:
			return 0.0
		if target_pos == Vector2.ZERO:
			return 0.0

		var to_target := (target_pos - global_position).normalized()
		var angle_diff := direction.angle_to(to_target)
		var max_steer_this_frame := homing_steer_speed * delta
		angle_diff = clampf(angle_diff, -max_steer_this_frame, max_steer_this_frame)

		var new_direction := direction.rotated(angle_diff).normalized()
		var angle_from_original := _homing_original_direction.angle_to(new_direction)
		if absf(angle_from_original) > homing_max_turn_angle:
			return 0.0

		direction = new_direction
		rotation = direction.angle()
		return angle_diff

	## Find best target: nearest to aim line or nearest to pellet (Issue #704).
	func find_best_target(enemies: Array[Vector2]) -> Vector2:
		if enemies.is_empty():
			return Vector2.ZERO

		if _use_aim_line_targeting:
			return _find_nearest_to_aim_line(enemies)

		# Default: nearest to pellet
		var nearest := Vector2.ZERO
		var nearest_dist := INF
		for enemy_pos in enemies:
			var dist := global_position.distance_squared_to(enemy_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = enemy_pos
		return nearest

	## Find enemy nearest to the player's aim line (Issue #704).
	func _find_nearest_to_aim_line(enemies: Array[Vector2]) -> Vector2:
		var best_target := Vector2.ZERO
		var best_score := INF
		var max_perp_distance := 500.0
		var max_angle := homing_max_turn_angle

		for enemy_pos in enemies:
			var to_enemy := enemy_pos - _shooter_origin
			var dist_to_enemy := to_enemy.length()
			if dist_to_enemy < 1.0:
				continue

			var angle := absf(_shooter_aim_direction.angle_to(to_enemy.normalized()))
			if angle > max_angle:
				continue

			# Perpendicular distance from aim line
			var perp_dist := absf(to_enemy.x * _shooter_aim_direction.y - to_enemy.y * _shooter_aim_direction.x)
			if perp_dist > max_perp_distance:
				continue

			var score := perp_dist + dist_to_enemy * 0.1
			if score < best_score:
				best_score = score
				best_target = enemy_pos

		return best_target


# ============================================================================
# Shotgun Pellet Homing Tests (Issue #704)
# ============================================================================


func test_pellet_homing_disabled_by_default() -> void:
	var pellet := MockHomingPellet.new()
	assert_false(pellet.homing_enabled,
		"Pellet homing should be disabled by default")


func test_pellet_enable_homing() -> void:
	var pellet := MockHomingPellet.new()
	pellet.enable_homing()
	assert_true(pellet.homing_enabled,
		"Pellet homing should be enabled after enable_homing()")


func test_pellet_homing_steers_toward_target() -> void:
	var pellet := MockHomingPellet.new()
	pellet.direction = Vector2.RIGHT
	pellet.global_position = Vector2.ZERO
	pellet.enable_homing()

	var target := Vector2(100, -100)
	var angle_change := pellet.apply_homing_toward(target, 0.016)

	assert_true(pellet.direction.y < 0.0,
		"Pellet should steer upward toward target above")
	assert_true(angle_change != 0.0,
		"Angle change should be non-zero")


func test_pellet_homing_respects_angle_limit() -> void:
	var pellet := MockHomingPellet.new()
	pellet.direction = Vector2.RIGHT
	pellet.global_position = Vector2.ZERO
	pellet.homing_steer_speed = 100.0
	pellet.enable_homing()

	var target := Vector2(-100, 0)
	for i in range(100):
		pellet.apply_homing_toward(target, 0.016)

	var angle_from_original := absf(pellet._homing_original_direction.angle_to(pellet.direction))
	assert_true(angle_from_original <= pellet.homing_max_turn_angle + 0.01,
		"Pellet turn should not exceed 110° limit, got: %s°" % rad_to_deg(angle_from_original))


func test_pellet_aim_line_targeting_enabled() -> void:
	var pellet := MockHomingPellet.new()
	pellet.direction = Vector2.RIGHT
	pellet.enable_homing_with_aim_line(Vector2.ZERO, Vector2.RIGHT)

	assert_true(pellet.homing_enabled,
		"Homing should be enabled")
	assert_true(pellet._use_aim_line_targeting,
		"Aim-line targeting should be enabled")


func test_pellet_aim_line_finds_nearest_to_aim() -> void:
	var pellet := MockHomingPellet.new()
	pellet.direction = Vector2.RIGHT
	pellet.global_position = Vector2(50, 50)  # Pellet is off to the side
	pellet.enable_homing_with_aim_line(Vector2.ZERO, Vector2.RIGHT)

	# Enemy A: on the aim line (200, 0) - closest to aim line
	# Enemy B: near the pellet (60, 40) - closest to pellet
	var enemies: Array[Vector2] = [Vector2(200, 0), Vector2(60, 40)]
	var target := pellet.find_best_target(enemies)

	assert_eq(target, Vector2(200, 0),
		"With aim-line targeting, should select enemy nearest to aim line, not nearest to pellet")


func test_pellet_default_targeting_finds_nearest_to_pellet() -> void:
	var pellet := MockHomingPellet.new()
	pellet.direction = Vector2.RIGHT
	pellet.global_position = Vector2(50, 50)
	pellet.enable_homing()  # No aim-line targeting

	# Enemy A: far from pellet (200, 0)
	# Enemy B: near the pellet (60, 40)
	var enemies: Array[Vector2] = [Vector2(200, 0), Vector2(60, 40)]
	var target := pellet.find_best_target(enemies)

	assert_eq(target, Vector2(60, 40),
		"Without aim-line targeting, should select enemy nearest to pellet")


func test_aim_line_rejects_enemies_behind_shooter() -> void:
	var pellet := MockHomingPellet.new()
	pellet.direction = Vector2.RIGHT
	pellet.global_position = Vector2(50, 0)
	pellet.enable_homing_with_aim_line(Vector2.ZERO, Vector2.RIGHT)

	# Enemy behind the shooter (beyond 110 degrees from aim direction)
	var enemies: Array[Vector2] = [Vector2(-200, 0)]
	var target := pellet.find_best_target(enemies)

	assert_eq(target, Vector2.ZERO,
		"Should not target enemies behind the shooter (>110° from aim)")


func test_aim_line_rejects_enemies_too_far_from_line() -> void:
	var pellet := MockHomingPellet.new()
	pellet.direction = Vector2.RIGHT
	pellet.global_position = Vector2(50, 0)
	pellet.enable_homing_with_aim_line(Vector2.ZERO, Vector2.RIGHT)

	# Enemy too far from the aim line (>500px perpendicular distance)
	var enemies: Array[Vector2] = [Vector2(100, 600)]
	var target := pellet.find_best_target(enemies)

	assert_eq(target, Vector2.ZERO,
		"Should not target enemies too far from aim line (>500px perp distance)")


# ============================================================================
# Sniper Rifle Homing Tests (Issue #704)
# ============================================================================


## Mock for sniper rifle aim-line targeting.
class MockSniperHoming:
	var max_angle: float = deg_to_rad(110.0)
	var max_perp_distance: float = 500.0

	## Find nearest enemy near the aim line (same algorithm as SniperRifle.cs).
	func find_nearest_enemy_near_aim_line(origin: Vector2, aim_dir: Vector2, enemies: Array[Vector2]) -> Vector2:
		var best_target := Vector2.ZERO
		var best_score := INF

		for enemy_pos in enemies:
			var to_enemy := enemy_pos - origin
			var dist_to_enemy := to_enemy.length()
			if dist_to_enemy < 1.0:
				continue

			var angle := absf(aim_dir.angle_to(to_enemy.normalized()))
			if angle > max_angle:
				continue

			var perp_dist := absf(to_enemy.x * aim_dir.y - to_enemy.y * aim_dir.x)
			if perp_dist > max_perp_distance:
				continue

			var score := perp_dist + dist_to_enemy * 0.1
			if score < best_score:
				best_score = score
				best_target = enemy_pos

		return best_target


func test_sniper_homing_finds_enemy_on_aim_line() -> void:
	var sniper := MockSniperHoming.new()
	var origin := Vector2.ZERO
	var aim_dir := Vector2.RIGHT

	# Enemy directly on the aim line
	var enemies: Array[Vector2] = [Vector2(300, 0)]
	var target := sniper.find_nearest_enemy_near_aim_line(origin, aim_dir, enemies)

	assert_eq(target, Vector2(300, 0),
		"Should find enemy directly on aim line")


func test_sniper_homing_prefers_closer_to_aim_line() -> void:
	var sniper := MockSniperHoming.new()
	var origin := Vector2.ZERO
	var aim_dir := Vector2.RIGHT

	# Enemy A: close to aim line (300, 10)
	# Enemy B: far from aim line (300, 200)
	var enemies: Array[Vector2] = [Vector2(300, 200), Vector2(300, 10)]
	var target := sniper.find_nearest_enemy_near_aim_line(origin, aim_dir, enemies)

	assert_eq(target, Vector2(300, 10),
		"Should prefer enemy closer to aim line")


func test_sniper_homing_rejects_behind() -> void:
	var sniper := MockSniperHoming.new()
	var origin := Vector2.ZERO
	var aim_dir := Vector2.RIGHT

	# Enemy behind the player
	var enemies: Array[Vector2] = [Vector2(-300, 0)]
	var target := sniper.find_nearest_enemy_near_aim_line(origin, aim_dir, enemies)

	assert_eq(target, Vector2.ZERO,
		"Should not target enemies behind the player")


func test_sniper_homing_no_enemies() -> void:
	var sniper := MockSniperHoming.new()
	var origin := Vector2.ZERO
	var aim_dir := Vector2.RIGHT

	var enemies: Array[Vector2] = []
	var target := sniper.find_nearest_enemy_near_aim_line(origin, aim_dir, enemies)

	assert_eq(target, Vector2.ZERO,
		"Should return zero vector when no enemies")
