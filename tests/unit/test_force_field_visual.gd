extends GutTest
## Unit tests for ForceFieldEffect visual appearance (Issue #930).
##
## Tests that the force field bubble texture has the correct properties:
## - Semi-transparent interior fill (not fully transparent)
## - Bright glowing rim
## - Correct color (blue)
## - Transparent exterior
## - Constants match gameplay requirements
##
## Uses a Mock to test the texture-generation logic without requiring
## the Godot scene tree or real Sprite2D nodes.


# ============================================================================
# Mock ForceFieldEffect for Logic/Texture Tests
# ============================================================================


class MockForceFieldEffect:
	## Maximum charge duration in seconds.
	const MAX_CHARGE: float = 8.0

	## Radius of the force field protection area (pixels).
	const FIELD_RADIUS: float = 35.0

	## Shield visual scale.
	const SHIELD_SCALE: float = 0.28

	## Reflection velocity boost multiplier for grenades.
	const GRENADE_REFLECTION_BOOST: float = 1.2

	## Duration to disable grenade impact detection after bounce (seconds).
	const GRENADE_BOUNCE_IMMUNITY_TIME: float = 0.15

	## Low charge warning threshold (seconds).
	const LOW_CHARGE_WARNING: float = 2.0

	## Flash frequency when charge is low (Hz).
	const WARNING_FLASH_FREQUENCY: float = 3.0

	## Remaining charge in seconds.
	var remaining_charge: float = MAX_CHARGE

	## Whether the force field is currently active.
	var is_active: bool = false

	## Signal tracking for tests.
	var activated_signals: Array = []
	var deactivated_signals: Array = []
	var charge_changed_signals: Array = []
	var charge_depleted_signals: Array = []


	## Activate the force field.
	func activate() -> bool:
		if is_active:
			return false
		if remaining_charge <= 0.0:
			return false
		is_active = true
		activated_signals.append(remaining_charge)
		return true


	## Deactivate the force field.
	func deactivate() -> void:
		if not is_active:
			return
		is_active = false
		deactivated_signals.append(remaining_charge)


	## Process one frame.
	func process(delta: float) -> void:
		if not is_active:
			return
		remaining_charge -= delta
		if remaining_charge <= 0.0:
			remaining_charge = 0.0
			deactivate()
			charge_depleted_signals.append(true)
		charge_changed_signals.append({"current": remaining_charge, "max": MAX_CHARGE})


	## Check if the player is currently protected.
	func is_protecting() -> bool:
		return is_active


	## Get remaining charge.
	func get_remaining_charge() -> float:
		return remaining_charge


	## Simulate the _create_ring_texture() pixel calculation for a single pixel.
	## Returns the alpha value that would be set at normalized distance r (0.0 to 1.0).
	## This is a direct port of the GDScript logic for unit testing (Issue #930).
	func compute_pixel_alpha(r_normalized: float) -> float:
		# r_normalized: 0.0 = center, 1.0 = outer edge
		var rim_start_norm := 0.84  # rim starts at 84% radius

		if r_normalized > 1.0:
			return 0.0  # Outside circle — transparent
		elif r_normalized >= rim_start_norm:
			# Bright rim: bell curve alpha, peak 0.9
			var t := (r_normalized - rim_start_norm) / (1.0 - rim_start_norm)
			return sin(t * PI) * 0.9
		else:
			# Interior fill: soft translucent bubble interior (Issue #930)
			# Alpha ramps up from 0 at center to ~0.15 near the rim, like frosted glass.
			return pow(r_normalized, 1.5) * 0.15


var effect: MockForceFieldEffect


func before_each() -> void:
	effect = MockForceFieldEffect.new()


func after_each() -> void:
	effect = null


# ============================================================================
# Constants Tests — verify gameplay rules are preserved
# ============================================================================


func test_max_charge_is_8_seconds() -> void:
	assert_eq(MockForceFieldEffect.MAX_CHARGE, 8.0,
		"Max charge should be 8 seconds")


func test_field_radius_is_35_pixels() -> void:
	assert_eq(MockForceFieldEffect.FIELD_RADIUS, 35.0,
		"Field radius should be 35px (slightly larger than player 16px radius)")


func test_shield_scale_is_0_28() -> void:
	assert_eq(MockForceFieldEffect.SHIELD_SCALE, 0.28,
		"Shield scale should be 0.28 (gives visible radius ~36px at 256px texture)")


func test_grenade_reflection_boost_is_1_2() -> void:
	assert_eq(MockForceFieldEffect.GRENADE_REFLECTION_BOOST, 1.2,
		"Grenade reflection boost should be 1.2x")


func test_grenade_bounce_immunity_time_is_0_15() -> void:
	assert_eq(MockForceFieldEffect.GRENADE_BOUNCE_IMMUNITY_TIME, 0.15,
		"Grenade bounce immunity should be 0.15 seconds")


func test_low_charge_warning_threshold_is_2_seconds() -> void:
	assert_eq(MockForceFieldEffect.LOW_CHARGE_WARNING, 2.0,
		"Low charge warning should trigger at 2 seconds remaining")


func test_warning_flash_frequency_is_3_hz() -> void:
	assert_eq(MockForceFieldEffect.WARNING_FLASH_FREQUENCY, 3.0,
		"Warning flash frequency should be 3 Hz")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_starts_with_full_charge() -> void:
	assert_eq(effect.get_remaining_charge(), 8.0,
		"Should start with full 8 second charge")


func test_starts_inactive() -> void:
	assert_false(effect.is_active,
		"Should start inactive")


func test_is_not_protecting_initially() -> void:
	assert_false(effect.is_protecting(),
		"Should not be protecting initially")


# ============================================================================
# Activation / Deactivation Tests
# ============================================================================


func test_activate_sets_active() -> void:
	effect.activate()
	assert_true(effect.is_active,
		"Should be active after activation")


func test_activate_returns_true_on_success() -> void:
	var result := effect.activate()
	assert_true(result, "activate() should return true on success")


func test_activate_emits_signal() -> void:
	effect.activate()
	assert_eq(effect.activated_signals.size(), 1,
		"Should emit activated signal")


func test_cannot_activate_twice() -> void:
	effect.activate()
	var result := effect.activate()
	assert_false(result, "Should not activate when already active")
	assert_eq(effect.activated_signals.size(), 1,
		"Should only emit one activated signal")


func test_cannot_activate_with_no_charge() -> void:
	effect.remaining_charge = 0.0
	var result := effect.activate()
	assert_false(result, "Should not activate with zero charge")


func test_deactivate_when_active() -> void:
	effect.activate()
	effect.deactivate()
	assert_false(effect.is_active,
		"Should be inactive after deactivation")


func test_deactivate_emits_signal() -> void:
	effect.activate()
	effect.deactivate()
	assert_eq(effect.deactivated_signals.size(), 1,
		"Should emit deactivated signal")


func test_deactivate_when_inactive_does_nothing() -> void:
	effect.deactivate()
	assert_eq(effect.deactivated_signals.size(), 0,
		"Should not emit signal when deactivating inactive field")


func test_is_protecting_when_active() -> void:
	effect.activate()
	assert_true(effect.is_protecting(),
		"Should be protecting when active")


# ============================================================================
# Charge Depletion Tests
# ============================================================================


func test_charge_decreases_over_time() -> void:
	effect.activate()
	effect.process(1.0)
	assert_almost_eq(effect.get_remaining_charge(), 7.0, 0.001,
		"Charge should decrease by delta each frame")


func test_charge_depletes_after_8_seconds() -> void:
	effect.activate()
	effect.process(8.0)
	assert_almost_eq(effect.get_remaining_charge(), 0.0, 0.001,
		"Charge should be depleted after 8 seconds")


func test_field_deactivates_when_charge_depletes() -> void:
	effect.activate()
	effect.process(8.1)
	assert_false(effect.is_active,
		"Field should auto-deactivate when charge depletes")


func test_charge_depleted_signal_emitted() -> void:
	effect.activate()
	effect.process(8.1)
	assert_eq(effect.charge_depleted_signals.size(), 1,
		"Should emit charge_depleted signal")


func test_charge_changed_signal_emitted_each_frame() -> void:
	effect.activate()
	effect.process(0.5)
	effect.process(0.5)
	assert_eq(effect.charge_changed_signals.size(), 2,
		"Should emit charge_changed signal each frame while active")


func test_charge_does_not_go_below_zero() -> void:
	effect.activate()
	effect.process(100.0)
	assert_almost_eq(effect.get_remaining_charge(), 0.0, 0.001,
		"Charge should not go below 0")


# ============================================================================
# Visual Texture Tests (Issue #930)
# Tests that the bubble texture has a semi-transparent interior, not just a ring.
# ============================================================================


func test_exterior_is_transparent() -> void:
	# Pixels outside the circle should be fully transparent
	var alpha := effect.compute_pixel_alpha(1.1)
	assert_eq(alpha, 0.0,
		"Pixels outside the circle should be fully transparent (r > 1.0)")


func test_rim_has_high_alpha() -> void:
	# The rim at ~92% radius (midpoint of 84%–100% range) should have peak alpha
	var alpha := effect.compute_pixel_alpha(0.92)
	assert_gt(alpha, 0.5,
		"Rim at 92% radius should have alpha > 0.5 (bright glowing edge)")


func test_rim_peak_alpha_near_0_9() -> void:
	# The bell curve peaks at the midpoint of the rim band (t=0.5 → r≈0.92)
	var alpha := effect.compute_pixel_alpha(0.92)
	assert_almost_eq(alpha, 0.9, 0.05,
		"Rim peak alpha should be approximately 0.9")


func test_interior_is_not_fully_transparent() -> void:
	# The interior (Issue #930 fix) should have some alpha — it's a bubble, not hollow
	var alpha_center := effect.compute_pixel_alpha(0.0)
	var alpha_mid := effect.compute_pixel_alpha(0.5)
	assert_gt(alpha_mid, 0.0,
		"Interior at 50% radius should not be fully transparent (bubble interior fill)")
	# Center may approach 0 but mid-radius should have visible fill
	assert_gt(alpha_mid, alpha_center - 0.001,
		"Interior fill should increase from center toward rim")


func test_interior_fill_stays_low_opacity() -> void:
	# Interior should be semi-transparent (low alpha), not opaque
	var alpha_center := effect.compute_pixel_alpha(0.0)
	var alpha_mid := effect.compute_pixel_alpha(0.5)
	assert_lt(alpha_center, 0.15,
		"Center alpha should be below 0.15 (translucent, not opaque)")
	assert_lt(alpha_mid, 0.15,
		"Mid-radius alpha should be below 0.15 (translucent, not opaque)")


func test_interior_fill_increases_toward_rim() -> void:
	# Interior fill ramps up toward the rim (pow(r, 1.5) * 0.15) — frosted glass bubble effect
	var alpha_30 := effect.compute_pixel_alpha(0.30)
	var alpha_60 := effect.compute_pixel_alpha(0.60)
	assert_gt(alpha_60, alpha_30,
		"60% radius should have higher alpha than 30% (fill ramps toward rim)")


func test_rim_start_at_84_percent() -> void:
	# Just inside the rim (83%) should be interior fill, not rim brightness
	var alpha_just_inside_rim := effect.compute_pixel_alpha(0.83)
	var alpha_in_rim := effect.compute_pixel_alpha(0.90)
	assert_lt(alpha_just_inside_rim, alpha_in_rim,
		"Interior at 83% should be less bright than rim at 90%")


func test_rim_fades_at_outer_edge() -> void:
	# At the very outer edge (100%), the bell curve has t=1 so alpha = sin(PI) = 0
	var alpha_outer_edge := effect.compute_pixel_alpha(1.0)
	assert_almost_eq(alpha_outer_edge, 0.0, 0.01,
		"Alpha at outer edge (r=1.0) should approach 0 (bell curve endpoint)")


func test_bubble_look_not_hollow_ring() -> void:
	# Issue #930: the key requirement is that the field looks like a bubble, not just a ring.
	# A bubble has interior fill; a hollow ring has alpha=0 in the interior.
	var interior_alpha := effect.compute_pixel_alpha(0.5)
	assert_gt(interior_alpha, 0.0,
		"Interior should have non-zero alpha — field should look like a bubble, not a hollow ring")


func test_alpha_values_are_valid_range() -> void:
	# All alpha values should be in [0.0, 1.0]
	var test_radii := [0.0, 0.1, 0.3, 0.5, 0.6, 0.7, 0.84, 0.92, 1.0, 1.1]
	for r in test_radii:
		var alpha := effect.compute_pixel_alpha(r)
		assert_gte(alpha, 0.0,
			"Alpha at r=%.2f should be >= 0.0" % r)
		assert_lte(alpha, 1.0,
			"Alpha at r=%.2f should be <= 1.0" % r)


# ============================================================================
# Integration-Style Tests
# ============================================================================


func test_full_charge_cycle() -> void:
	# Start full
	assert_eq(effect.get_remaining_charge(), 8.0)
	assert_false(effect.is_protecting())

	# Activate
	effect.activate()
	assert_true(effect.is_protecting())

	# Run for 4 seconds
	effect.process(4.0)
	assert_almost_eq(effect.get_remaining_charge(), 4.0, 0.001)
	assert_true(effect.is_protecting())

	# Deactivate manually
	effect.deactivate()
	assert_false(effect.is_protecting())
	assert_almost_eq(effect.get_remaining_charge(), 4.0, 0.001)

	# Re-activate and use remaining charge
	effect.activate()
	effect.process(4.0)
	assert_almost_eq(effect.get_remaining_charge(), 0.0, 0.001)
	assert_false(effect.is_protecting())
	assert_eq(effect.charge_depleted_signals.size(), 1)


func test_partial_charge_usage() -> void:
	# Use charge in 1-second increments
	for i in range(8):
		effect.activate()
		effect.process(1.0)
		effect.deactivate()
		assert_almost_eq(effect.get_remaining_charge(), float(7 - i), 0.001)

	# Now fully depleted
	assert_almost_eq(effect.get_remaining_charge(), 0.0, 0.001)
	var result := effect.activate()
	assert_false(result, "Should not activate with no charge")
