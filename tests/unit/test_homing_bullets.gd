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
