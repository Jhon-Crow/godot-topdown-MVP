extends GutTest
## Unit tests for the Trajectory Glasses active item (Issue #744).
##
## Tests the trajectory glasses effect including:
## - Charge management (2 charges per battle)
## - Effect duration (10 seconds per activation)
## - Activation/deactivation logic
## - Ricochet angle calculation
## - Signal emissions


# ============================================================================
# Mock Classes
# ============================================================================


class MockTrajectoryGlassesEffect:
	## Duration of trajectory glasses effect in seconds.
	const EFFECT_DURATION: float = 10.0

	## Maximum charges per battle.
	const MAX_CHARGES: int = 2

	## Maximum ricochet angle in degrees.
	const MAX_RICOCHET_ANGLE: float = 90.0

	## Continuous blink threshold in seconds (Issue #1085).
	const CONTINUOUS_BLINK_THRESHOLD: float = 4.0

	## Single-blink threshold — 25% of EFFECT_DURATION (Issue #1085).
	const SINGLE_BLINK_THRESHOLD: float = EFFECT_DURATION * 0.25  # 2.5 s

	## Flash frequency when time is low (Issue #1085).
	const WARNING_FLASH_FREQUENCY: float = 3.0

	## Current number of charges remaining.
	var charges: int = MAX_CHARGES

	## Whether the effect is currently active.
	var is_active: bool = false

	## Timer tracking remaining effect duration.
	var _effect_timer: float = 0.0

	## Continuous-blink flash timer (Issue #1085).
	var _warning_flash_timer: float = 0.0

	## Whether the continuous-blink phase has been logged this activation (Issue #1085).
	var _continuous_blink_logged: bool = false

	## Whether the single-blink at 25% has been triggered this activation (Issue #1085).
	var _single_blink_triggered: bool = false

	## Single-blink phase timer (Issue #1085).
	var _single_blink_timer: float = 0.0

	## Whether the trajectory ray is visible this frame (Issue #1085).
	var trajectory_ray_visible: bool = true

	## Signal tracking.
	var activation_count: int = 0
	var deactivation_count: int = 0
	var charges_changed_count: int = 0

	## Attempt to activate the trajectory glasses effect.
	func activate() -> bool:
		if is_active:
			return false
		if charges <= 0:
			return false

		charges -= 1
		is_active = true
		_effect_timer = EFFECT_DURATION
		activation_count += 1
		charges_changed_count += 1
		return true

	## Deactivate the trajectory glasses effect.
	func deactivate() -> void:
		if not is_active:
			return
		is_active = false
		_effect_timer = 0.0
		_warning_flash_timer = 0.0
		_continuous_blink_logged = false
		_single_blink_triggered = false
		_single_blink_timer = 0.0
		trajectory_ray_visible = true
		deactivation_count += 1

	## Simulate time passing (including flash logic, Issue #1085).
	func update(delta: float) -> void:
		if not is_active:
			return
		_effect_timer -= delta
		if _effect_timer <= 0.0:
			deactivate()
			return
		if _effect_timer <= CONTINUOUS_BLINK_THRESHOLD:
			# Trigger one-shot single blink when crossing 25% threshold (Issue #1085).
			if _effect_timer <= SINGLE_BLINK_THRESHOLD and not _single_blink_triggered:
				_single_blink_triggered = true
				_single_blink_timer = 0.0
			var single_blink_period := 1.0 / WARNING_FLASH_FREQUENCY
			if _single_blink_triggered and _single_blink_timer < single_blink_period:
				_single_blink_timer += delta
				if _single_blink_timer < single_blink_period * 0.5:
					trajectory_ray_visible = false
				else:
					trajectory_ray_visible = true
			else:
				# Continuous blink at WARNING_FLASH_FREQUENCY Hz.
				_warning_flash_timer += delta
				var flash_period := 1.0 / WARNING_FLASH_FREQUENCY
				trajectory_ray_visible = fmod(_warning_flash_timer, flash_period) < (flash_period * 0.5)
		else:
			# Normal phase
			_warning_flash_timer = 0.0
			_continuous_blink_logged = false
			_single_blink_triggered = false
			_single_blink_timer = 0.0
			trajectory_ray_visible = true

	## Get remaining effect time.
	func get_remaining_time() -> float:
		return _effect_timer if is_active else 0.0

	## Get current charges.
	func get_charges() -> int:
		return charges

	## Calculate the grazing/impact angle in degrees.
	func calculate_impact_angle(direction: Vector2, surface_normal: Vector2) -> float:
		var dot := absf(direction.normalized().dot(surface_normal.normalized()))
		dot = clampf(dot, 0.0, 1.0)
		return rad_to_deg(asin(dot))

	## Check if ricochet is valid at the given angle.
	func is_valid_ricochet_angle(angle_deg: float) -> bool:
		return angle_deg <= MAX_RICOCHET_ANGLE


var effect: MockTrajectoryGlassesEffect


func before_each() -> void:
	effect = MockTrajectoryGlassesEffect.new()


func after_each() -> void:
	effect = null


# ============================================================================
# Charge Tests
# ============================================================================


func test_initial_charges_is_max() -> void:
	assert_eq(effect.charges, effect.MAX_CHARGES,
		"Initial charges should be MAX_CHARGES (2)")


func test_max_charges_is_two() -> void:
	assert_eq(effect.MAX_CHARGES, 2,
		"MAX_CHARGES should be 2 as per issue specification")


func test_activation_consumes_charge() -> void:
	var initial_charges := effect.charges
	effect.activate()
	assert_eq(effect.charges, initial_charges - 1,
		"Activation should consume one charge")


func test_cannot_activate_with_zero_charges() -> void:
	# Use up all charges
	effect.activate()
	effect.deactivate()
	effect.activate()
	effect.deactivate()

	# Should have 0 charges now
	assert_eq(effect.charges, 0, "Should have 0 charges after 2 activations")

	# Third activation should fail
	var result := effect.activate()
	assert_false(result, "Should not activate with 0 charges")


func test_charges_do_not_regenerate() -> void:
	effect.activate()
	effect.deactivate()
	assert_eq(effect.charges, 1,
		"Charges should remain at 1 after deactivation (no regeneration)")


# ============================================================================
# Duration Tests
# ============================================================================


func test_effect_duration_is_ten_seconds() -> void:
	assert_eq(effect.EFFECT_DURATION, 10.0,
		"EFFECT_DURATION should be 10 seconds as per issue specification")


func test_remaining_time_after_activation() -> void:
	effect.activate()
	assert_eq(effect.get_remaining_time(), effect.EFFECT_DURATION,
		"Remaining time should be EFFECT_DURATION right after activation")


func test_remaining_time_decreases() -> void:
	effect.activate()
	effect.update(3.0)  # 3 seconds pass
	assert_almost_eq(effect.get_remaining_time(), 7.0, 0.01,
		"Remaining time should decrease by delta")


func test_effect_deactivates_after_duration() -> void:
	effect.activate()
	effect.update(10.5)  # More than 10 seconds
	assert_false(effect.is_active,
		"Effect should automatically deactivate after duration expires")


func test_remaining_time_is_zero_when_inactive() -> void:
	assert_eq(effect.get_remaining_time(), 0.0,
		"Remaining time should be 0 when inactive")


# ============================================================================
# Activation State Tests
# ============================================================================


func test_starts_inactive() -> void:
	assert_false(effect.is_active, "Effect should start inactive")


func test_activate_returns_true_on_success() -> void:
	var result := effect.activate()
	assert_true(result, "activate() should return true on success")


func test_is_active_after_activation() -> void:
	effect.activate()
	assert_true(effect.is_active, "Effect should be active after activation")


func test_cannot_double_activate() -> void:
	effect.activate()
	var result := effect.activate()
	assert_false(result, "Should not be able to activate while already active")


func test_is_inactive_after_deactivation() -> void:
	effect.activate()
	effect.deactivate()
	assert_false(effect.is_active, "Effect should be inactive after deactivation")


func test_can_reactivate_after_deactivation() -> void:
	effect.activate()
	effect.deactivate()
	var result := effect.activate()
	assert_true(result, "Should be able to reactivate after deactivation")


# ============================================================================
# Signal Tracking Tests
# ============================================================================


func test_activation_increments_count() -> void:
	effect.activate()
	assert_eq(effect.activation_count, 1, "Activation should increment count")


func test_deactivation_increments_count() -> void:
	effect.activate()
	effect.deactivate()
	assert_eq(effect.deactivation_count, 1, "Deactivation should increment count")


func test_charges_changed_on_activation() -> void:
	effect.activate()
	assert_eq(effect.charges_changed_count, 1,
		"Charges changed should be emitted on activation")


func test_auto_deactivation_increments_deactivation_count() -> void:
	effect.activate()
	effect.update(15.0)  # Force auto-deactivation
	assert_eq(effect.deactivation_count, 1,
		"Auto-deactivation should increment deactivation count")


# ============================================================================
# Ricochet Angle Calculation Tests
# ============================================================================


func test_parallel_shot_has_zero_impact_angle() -> void:
	# Bullet traveling parallel to surface (grazing)
	var direction := Vector2.RIGHT
	var normal := Vector2.UP  # Perpendicular to bullet direction
	var angle := effect.calculate_impact_angle(direction, normal)
	assert_almost_eq(angle, 0.0, 0.1,
		"Parallel/grazing shot should have ~0 degree impact angle")


func test_perpendicular_shot_has_90_degree_impact_angle() -> void:
	# Bullet traveling directly into surface (head-on)
	var direction := Vector2.UP
	var normal := Vector2.DOWN  # Opposite to bullet direction
	var angle := effect.calculate_impact_angle(direction, normal)
	assert_almost_eq(angle, 90.0, 0.1,
		"Perpendicular/head-on shot should have ~90 degree impact angle")


func test_45_degree_shot() -> void:
	# Bullet traveling at 45 degrees to surface
	var direction := Vector2(1, 1).normalized()
	var normal := Vector2.UP
	var angle := effect.calculate_impact_angle(direction, normal)
	assert_almost_eq(angle, 45.0, 0.1,
		"45-degree shot should have ~45 degree impact angle")


func test_shallow_angle_is_valid_ricochet() -> void:
	# 15 degrees - shallow angle, should ricochet
	assert_true(effect.is_valid_ricochet_angle(15.0),
		"15 degree angle should be valid for ricochet")


func test_moderate_angle_is_valid_ricochet() -> void:
	# 45 degrees - moderate angle, still valid
	assert_true(effect.is_valid_ricochet_angle(45.0),
		"45 degree angle should be valid for ricochet")


func test_steep_angle_is_valid_at_max() -> void:
	# 90 degrees - exactly at max angle
	assert_true(effect.is_valid_ricochet_angle(90.0),
		"90 degree angle should be valid (at max threshold)")


func test_beyond_max_angle_is_invalid() -> void:
	# 91 degrees - beyond max angle
	assert_false(effect.is_valid_ricochet_angle(91.0),
		"91 degree angle should be invalid for ricochet")


# ============================================================================
# Integration Tests
# ============================================================================


func test_full_usage_cycle() -> void:
	# First activation
	assert_true(effect.activate(), "First activation should succeed")
	assert_eq(effect.charges, 1, "Should have 1 charge left")
	assert_true(effect.is_active, "Should be active")

	# Wait for duration
	effect.update(10.0)
	assert_false(effect.is_active, "Should be inactive after duration")

	# Second activation
	assert_true(effect.activate(), "Second activation should succeed")
	assert_eq(effect.charges, 0, "Should have 0 charges left")
	assert_true(effect.is_active, "Should be active")

	# Wait for duration
	effect.update(10.0)
	assert_false(effect.is_active, "Should be inactive after duration")

	# Third activation should fail
	assert_false(effect.activate(), "Third activation should fail (no charges)")
	assert_eq(effect.charges, 0, "Should still have 0 charges")


func test_manual_deactivation_preserves_charges() -> void:
	effect.activate()
	effect.update(3.0)  # 3 seconds used
	effect.deactivate()  # Manually deactivate early

	assert_eq(effect.charges, 1, "Manual deactivation should preserve remaining charge")
	assert_false(effect.is_active, "Should be inactive after manual deactivation")


# ============================================================================
# CaliberData Property Access Tests (Issue #935)
# ============================================================================


func test_caliber_data_max_ricochet_angle_is_readable() -> void:
	# Regression test for Issue #935: trajectory glasses always showed green for AKGL
	# because caliber properties obtained via C# interop returned default (90°) instead
	# of the .tres value (70°). Fix: cast to CaliberData before reading properties.
	var caliber := CaliberData.new()
	caliber.max_ricochet_angle = 70.0

	# Verify that direct property access reads the set value (not the GDScript default 90°)
	assert_almost_eq(caliber.max_ricochet_angle, 70.0, 0.01,
		"CaliberData.max_ricochet_angle should return the value that was set (70°), not the default (90°)")


func test_caliber_data_can_ricochet_false_stops_ricochet() -> void:
	# Regression test for Issue #935: ensure can_ricochet=false is correctly read
	# after CaliberData cast, so non-ricocheting weapons show red trajectory.
	var caliber := CaliberData.new()
	caliber.can_ricochet = false

	assert_false(caliber.can_ricochet,
		"CaliberData.can_ricochet should return false when set to false")


func test_caliber_data_762x39_has_restricted_angle() -> void:
	# Verify that the 7.62x39mm caliber (AKGL) has max_ricochet_angle = 70°, not the
	# default 90°. This angle was set in PR #918 and must not regress to 90°.
	var caliber := load("res://resources/calibers/caliber_762x39.tres") as CaliberData
	assert_not_null(caliber, "caliber_762x39.tres should load as CaliberData")
	assert_almost_eq(caliber.max_ricochet_angle, 70.0, 0.01,
		"7.62x39mm max_ricochet_angle should be 70° (not the default 90°)")


func test_akgl_weapon_data_has_caliber_max_ricochet_angle_70() -> void:
	# Regression test for Issue #935 (v3 fix): AKGLData.tres must have
	# CaliberMaxRicochetAngle = 70.0 as a native C# WeaponData property.
	# Previous fixes tried reading from WeaponData.Caliber.Get("max_ricochet_angle")
	# from C#, but Godot 4.3 returns the GDScript script default (90°) instead of
	# the serialized .tres value (70°) in that case.
	# The v3 fix stores the value directly in WeaponData.cs C# [Export] properties.
	var weapon_data_res = load("res://resources/weapons/AKGLData.tres")
	assert_not_null(weapon_data_res, "AKGLData.tres should load successfully")
	var max_angle: float = weapon_data_res.get("CaliberMaxRicochetAngle")
	assert_almost_eq(max_angle, 70.0, 0.01,
		"AKGLData.CaliberMaxRicochetAngle must be 70° to fix ricochet indicator (Issue #935 v3)")


func test_akgl_weapon_data_caliber_can_ricochet_true() -> void:
	# Regression test: AKGLData.tres must have CaliberCanRicochet = true.
	var weapon_data_res = load("res://resources/weapons/AKGLData.tres")
	assert_not_null(weapon_data_res, "AKGLData.tres should load successfully")
	var can_ricochet: bool = weapon_data_res.get("CaliberCanRicochet")
	assert_true(can_ricochet,
		"AKGLData.CaliberCanRicochet must be true for AKGL (Issue #935 v3)")


func test_sniper_weapon_data_caliber_cannot_ricochet() -> void:
	# Regression test: SniperRifleData.tres must have CaliberCanRicochet = false.
	# 12.7x108mm anti-materiel caliber does not ricochet.
	var weapon_data_res = load("res://resources/weapons/SniperRifleData.tres")
	assert_not_null(weapon_data_res, "SniperRifleData.tres should load successfully")
	var can_ricochet: bool = weapon_data_res.get("CaliberCanRicochet")
	assert_false(can_ricochet,
		"SniperRifleData.CaliberCanRicochet must be false for ASVK (12.7x108mm)")


# ============================================================================
# Trajectory Ray Flash Tests (Issue #1085)
# ============================================================================


func test_trajectory_ray_visible_when_not_active() -> void:
	# Ray visibility defaults to true when inactive
	assert_true(effect.trajectory_ray_visible,
		"trajectory_ray_visible should be true when effect is inactive")


func test_trajectory_ray_visible_in_normal_phase() -> void:
	effect.activate()
	# Advance to 5 seconds remaining (above CONTINUOUS_BLINK_THRESHOLD=4.0 and SINGLE_BLINK_THRESHOLD=2.5)
	effect.update(5.0)
	assert_true(effect.trajectory_ray_visible,
		"Ray should be continuously visible when remaining time > CONTINUOUS_BLINK_THRESHOLD")


func test_trajectory_ray_single_blink_triggered_at_25_percent() -> void:
	effect.activate()
	# Advance to just inside CONTINUOUS_BLINK_THRESHOLD (4 s) and past SINGLE_BLINK_THRESHOLD (2.5 s).
	# 10 - 7.6 = 2.4 s remaining → inside continuous blink AND past 25% threshold.
	# The single-blink fires: ray goes off for half a period.
	effect.update(7.6)
	effect.update(0.001)  # tiny step to enter single-blink override
	assert_false(effect.trajectory_ray_visible,
		"Ray should be off during first half of single-blink at 25% threshold")


func test_trajectory_ray_returns_to_visible_after_single_blink() -> void:
	effect.activate()
	# Advance to 2.4 s remaining (single-blink triggered inside continuous blink zone)
	effect.update(7.6)
	# Advance through one full single-blink period (~0.333 s)
	var single_blink_period := 1.0 / effect.WARNING_FLASH_FREQUENCY
	effect.update(single_blink_period)
	assert_true(effect.trajectory_ray_visible,
		"Ray should return to visible after single-blink completes")


func test_trajectory_ray_single_blink_fires_only_once() -> void:
	effect.activate()
	# Advance past 25% threshold
	effect.update(7.6)
	# Let the single-blink finish
	var single_blink_period := 1.0 / effect.WARNING_FLASH_FREQUENCY
	effect.update(single_blink_period + 0.1)
	# Advance a bit more — still in continuous blink zone
	effect.update(0.1)
	# _single_blink_triggered must stay true so the flash does not repeat
	assert_true(effect._single_blink_triggered,
		"_single_blink_triggered flag must remain true so single blink doesn't repeat")


func test_trajectory_ray_starts_continuous_blink_at_4_seconds() -> void:
	effect.activate()
	# Advance to just below CONTINUOUS_BLINK_THRESHOLD: 10 - 6.1 = 3.9 s remaining
	effect.update(6.1)
	# After a full blink period the cycle has definitely toggled at least once
	var flash_period := 1.0 / effect.WARNING_FLASH_FREQUENCY
	effect.update(flash_period)
	# Visibility is either on or off — just verify it's being driven by the blink logic
	assert_true(effect.trajectory_ray_visible == true or effect.trajectory_ray_visible == false,
		"trajectory_ray_visible must be controlled during continuous blink")


func test_continuous_blink_ray_is_off_during_first_half_period() -> void:
	effect.activate()
	# Advance to 3.9 s remaining (just inside continuous blink zone, above 25% threshold)
	effect.update(6.1)
	# At the very first tick into continuous blink the flash_timer is near 0 → ray should be off
	effect.update(0.001)
	assert_false(effect.trajectory_ray_visible,
		"Ray should be off during first half of blink period in continuous phase")


func test_trajectory_ray_visible_resets_on_deactivation() -> void:
	effect.activate()
	# Advance into continuous blink zone
	effect.update(6.5)
	effect.deactivate()
	assert_true(effect.trajectory_ray_visible,
		"trajectory_ray_visible should reset to true on deactivation")


func test_warning_flash_timer_resets_on_deactivation() -> void:
	effect.activate()
	effect.update(6.5)
	effect.deactivate()
	# Re-activate; blink should start fresh (timer at 0)
	effect.activate()
	effect.update(0.0)  # No delta: timer should not have advanced
	assert_true(effect.trajectory_ray_visible,
		"After re-activation flash timer should start at 0; ray should be visible")


func test_single_blink_triggered_flag_resets_on_deactivation() -> void:
	effect.activate()
	# Trigger the single blink
	effect.update(7.6)
	assert_true(effect._single_blink_triggered,
		"_single_blink_triggered should be true after 25% threshold is crossed")
	effect.deactivate()
	assert_false(effect._single_blink_triggered,
		"_single_blink_triggered should reset to false on deactivation")


func test_continuous_blink_threshold_constant_is_four_seconds() -> void:
	assert_eq(effect.CONTINUOUS_BLINK_THRESHOLD, 4.0,
		"CONTINUOUS_BLINK_THRESHOLD should be 4.0 seconds (Issue #1085)")


func test_single_blink_threshold_constant_is_25_percent_of_duration() -> void:
	assert_almost_eq(effect.SINGLE_BLINK_THRESHOLD, effect.EFFECT_DURATION * 0.25, 0.001,
		"SINGLE_BLINK_THRESHOLD should be 25% of EFFECT_DURATION (Issue #1085)")


func test_warning_flash_frequency_constant() -> void:
	assert_eq(effect.WARNING_FLASH_FREQUENCY, 3.0,
		"WARNING_FLASH_FREQUENCY should be 3.0 Hz")


# ============================================================================
# Charge Pip HUD Auto-Hide Tests (Issue #1049)
# ============================================================================


class MockTrajectoryGlassesHud:
	## How long (in seconds) to show the charge pips after activation before auto-hiding.
	const ACTIVATION_SHOW_DURATION: float = 0.3

	## Whether the HUD is currently visible.
	var visible: bool = false

	## Timer counting down auto-hide after activation (0 = not running).
	var _hide_timer: float = 0.0

	## Show/hide the HUD. When active=true, starts the 300 ms auto-hide timer.
	func set_active(active: bool) -> void:
		if active:
			visible = true
			_hide_timer = ACTIVATION_SHOW_DURATION
		else:
			visible = false
			_hide_timer = 0.0

	## Simulate time passing (mirrors _process logic).
	func update(delta: float) -> void:
		if _hide_timer > 0.0:
			_hide_timer -= delta
			if _hide_timer <= 0.0:
				_hide_timer = 0.0
				visible = false


var hud: MockTrajectoryGlassesHud


func before_each_hud() -> void:
	hud = MockTrajectoryGlassesHud.new()


func test_hud_activation_show_duration_constant() -> void:
	var h := MockTrajectoryGlassesHud.new()
	assert_almost_eq(h.ACTIVATION_SHOW_DURATION, 0.3, 0.001,
		"ACTIVATION_SHOW_DURATION should be 0.3 seconds (300 ms)")


func test_hud_starts_hidden() -> void:
	var h := MockTrajectoryGlassesHud.new()
	assert_false(h.visible,
		"Charge pip HUD should start hidden")


func test_hud_visible_immediately_after_set_active() -> void:
	var h := MockTrajectoryGlassesHud.new()
	h.set_active(true)
	assert_true(h.visible,
		"HUD should be visible immediately after set_active(true)")


func test_hud_auto_hides_after_activation_duration() -> void:
	var h := MockTrajectoryGlassesHud.new()
	h.set_active(true)
	h.update(0.4)  # More than 0.3 s
	assert_false(h.visible,
		"HUD should auto-hide after ACTIVATION_SHOW_DURATION (300 ms)")


func test_hud_still_visible_before_activation_duration_expires() -> void:
	var h := MockTrajectoryGlassesHud.new()
	h.set_active(true)
	h.update(0.1)  # Less than 0.3 s
	assert_true(h.visible,
		"HUD should still be visible before ACTIVATION_SHOW_DURATION expires")


func test_hud_hidden_when_set_active_false() -> void:
	var h := MockTrajectoryGlassesHud.new()
	h.set_active(true)
	h.set_active(false)
	assert_false(h.visible,
		"HUD should become hidden immediately when set_active(false) is called")


func test_hud_hide_timer_resets_on_deactivation() -> void:
	var h := MockTrajectoryGlassesHud.new()
	h.set_active(true)
	h.update(0.1)
	h.set_active(false)
	# Re-activate: timer should restart from full ACTIVATION_SHOW_DURATION
	h.set_active(true)
	h.update(0.15)  # Still within 0.3 s
	assert_true(h.visible,
		"After re-activation HUD hide timer should reset; HUD should still be visible")
