extends GutTest
## Unit tests for force_field_effect.gd energy bubble shield.
##
## Tests charge constants, field radius, projectile release speeds,
## grenade reflection boost, and charge tracking.


# ============================================================================
# Mock ForceFieldEffect for Logic Tests
# ============================================================================


class MockForceFieldEffect:
	## Maximum charge duration in seconds.
	const MAX_CHARGE: float = 8.0

	## Radius of the force field (pixels).
	const FIELD_RADIUS: float = 35.0

	## Reflection velocity boost for grenades.
	const GRENADE_REFLECTION_BOOST: float = 1.2

	## Speed for released bullets (pixels/sec).
	const BULLET_RELEASE_SPEED: float = 800.0

	## Speed for released shrapnel (pixels/sec).
	const SHRAPNEL_RELEASE_SPEED: float = 600.0

	## Low charge warning threshold (seconds).
	const LOW_CHARGE_WARNING: float = 2.0

	## Warning flash frequency (Hz).
	const WARNING_FLASH_FREQUENCY: float = 3.0

	## Shield visual scale.
	const SHIELD_SCALE: float = 0.28

	## Grenade bounce immunity time.
	const GRENADE_BOUNCE_IMMUNITY_TIME: float = 0.15

	## Remaining charge in seconds.
	var remaining_charge: float = MAX_CHARGE

	## Whether the force field is currently active.
	var is_active: bool = false

	## Whether owned by player.
	var owner_is_player: bool = true

	## Trapped projectile counts.
	var _trapped_bullets_count: int = 0
	var _trapped_shrapnel_count: int = 0

	## Track signals.
	var _activated_emitted: bool = false
	var _deactivated_emitted: bool = false
	var _depleted_emitted: bool = false

	## Activate the force field.
	func activate() -> bool:
		if is_active:
			return false
		if remaining_charge <= 0.0:
			return false
		is_active = true
		_activated_emitted = true
		return true

	## Deactivate the force field.
	func deactivate() -> void:
		if not is_active:
			return
		is_active = false
		_deactivated_emitted = true

	## Simulate process update (charge depletion).
	func process(delta: float) -> void:
		if not is_active:
			return
		remaining_charge -= delta
		if remaining_charge <= 0.0:
			remaining_charge = 0.0
			deactivate()
			_depleted_emitted = true

	## Get remaining charge.
	func get_remaining_charge() -> float:
		return remaining_charge

	## Check if protecting.
	func is_protecting() -> bool:
		return is_active


var field: MockForceFieldEffect


func before_each() -> void:
	field = MockForceFieldEffect.new()


func after_each() -> void:
	field = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_max_charge() -> void:
	assert_eq(MockForceFieldEffect.MAX_CHARGE, 8.0,
		"MAX_CHARGE should be 8.0 seconds")


func test_field_radius() -> void:
	assert_eq(MockForceFieldEffect.FIELD_RADIUS, 35.0,
		"FIELD_RADIUS should be 35.0 pixels")


func test_grenade_reflection_boost() -> void:
	assert_eq(MockForceFieldEffect.GRENADE_REFLECTION_BOOST, 1.2,
		"GRENADE_REFLECTION_BOOST should be 1.2")


func test_bullet_release_speed() -> void:
	assert_eq(MockForceFieldEffect.BULLET_RELEASE_SPEED, 800.0,
		"BULLET_RELEASE_SPEED should be 800.0 pixels/sec")


func test_shrapnel_release_speed() -> void:
	assert_eq(MockForceFieldEffect.SHRAPNEL_RELEASE_SPEED, 600.0,
		"SHRAPNEL_RELEASE_SPEED should be 600.0 pixels/sec")


func test_low_charge_warning() -> void:
	assert_eq(MockForceFieldEffect.LOW_CHARGE_WARNING, 2.0,
		"LOW_CHARGE_WARNING should be 2.0 seconds")


func test_warning_flash_frequency() -> void:
	assert_eq(MockForceFieldEffect.WARNING_FLASH_FREQUENCY, 3.0,
		"WARNING_FLASH_FREQUENCY should be 3.0 Hz")


func test_shield_scale() -> void:
	assert_eq(MockForceFieldEffect.SHIELD_SCALE, 0.28,
		"SHIELD_SCALE should be 0.28")


func test_grenade_bounce_immunity_time() -> void:
	assert_eq(MockForceFieldEffect.GRENADE_BOUNCE_IMMUNITY_TIME, 0.15,
		"GRENADE_BOUNCE_IMMUNITY_TIME should be 0.15 seconds")


# ============================================================================
# Charge Tracking Tests
# ============================================================================


func test_initial_charge_equals_max() -> void:
	assert_eq(field.remaining_charge, 8.0,
		"Initial charge should equal MAX_CHARGE")


func test_charge_depletes_while_active() -> void:
	field.activate()
	field.process(3.0)

	assert_almost_eq(field.remaining_charge, 5.0, 0.01,
		"Charge should deplete by delta while active")


func test_charge_does_not_deplete_when_inactive() -> void:
	field.process(3.0)

	assert_eq(field.remaining_charge, 8.0,
		"Charge should not deplete when inactive")


func test_charge_depleted_deactivates_field() -> void:
	field.activate()
	field.process(8.0)

	assert_false(field.is_active,
		"Field should deactivate when charge is depleted")
	assert_eq(field.remaining_charge, 0.0,
		"Charge should be exactly 0 after depletion")


func test_charge_depleted_emits_signal() -> void:
	field.activate()
	field.process(8.0)

	assert_true(field._depleted_emitted,
		"Charge depleted signal should be emitted")


func test_partial_charge_usage() -> void:
	field.activate()
	field.process(2.0)
	field.deactivate()

	assert_almost_eq(field.remaining_charge, 6.0, 0.01,
		"Remaining charge should reflect partial usage")


func test_reactivation_uses_remaining_charge() -> void:
	field.activate()
	field.process(4.0)
	field.deactivate()
	field.activate()
	field.process(4.0)

	assert_false(field.is_active,
		"Field should deactivate when remaining charge depleted")
	assert_eq(field.remaining_charge, 0.0,
		"Charge should be fully depleted after second use")


# ============================================================================
# Activation / Deactivation Tests
# ============================================================================


func test_activate_returns_true() -> void:
	assert_true(field.activate(),
		"Activate should return true on first call")


func test_activate_when_already_active_returns_false() -> void:
	field.activate()

	assert_false(field.activate(),
		"Activate should return false when already active")


func test_activate_with_no_charge_returns_false() -> void:
	field.remaining_charge = 0.0

	assert_false(field.activate(),
		"Activate should return false when charge is 0")


func test_deactivate_sets_inactive() -> void:
	field.activate()
	field.deactivate()

	assert_false(field.is_active,
		"Deactivate should set is_active to false")


func test_is_protecting_when_active() -> void:
	field.activate()

	assert_true(field.is_protecting(),
		"is_protecting should return true when active")


func test_not_protecting_when_inactive() -> void:
	assert_false(field.is_protecting(),
		"is_protecting should return false when inactive")


# ============================================================================
# Release Speed Comparison Tests
# ============================================================================


func test_bullet_release_faster_than_shrapnel() -> void:
	assert_gt(MockForceFieldEffect.BULLET_RELEASE_SPEED,
		MockForceFieldEffect.SHRAPNEL_RELEASE_SPEED,
		"Bullets should be released faster than shrapnel")
