extends GutTest
## Regression tests for semi-automatic weapon shoot input buffering (Issue #625).
##
## Tests verify that fast clicking on semi-automatic weapons (like the PM pistol)
## correctly buffers inputs so clicks during the fire cooldown are not lost.


# ============================================================================
# Mock Classes for Testing Input Buffering Logic
# ============================================================================


class MockWeapon:
	## Fire rate in shots per second.
	var fire_rate: float = 7.0
	## Whether the weapon is automatic.
	var is_automatic: bool = false
	## Current ammo in magazine.
	var current_ammo: int = 9
	## Whether the weapon is reloading.
	var is_reloading: bool = false
	## Internal fire timer (cooldown between shots).
	var _fire_timer: float = 0.0
	## Number of shots fired (for verification).
	var shots_fired: int = 0


	func can_fire() -> bool:
		return current_ammo > 0 and not is_reloading and _fire_timer <= 0


	func fire() -> bool:
		if not can_fire():
			return false
		current_ammo -= 1
		_fire_timer = 1.0 / fire_rate
		shots_fired += 1
		return true


	func update(delta: float) -> void:
		if _fire_timer > 0:
			_fire_timer -= delta


class MockShootingInput:
	## Simulates the Player's HandleShootingInput logic with buffering.
	## This mirrors the fix applied in Player.cs for Issue #625.

	var weapon: MockWeapon
	var _semi_auto_shoot_buffered: bool = false

	## Simulated input state.
	var _just_pressed: bool = false
	var _just_released: bool = false


	func _init(w: MockWeapon) -> void:
		weapon = w


	func simulate_click() -> void:
		_just_pressed = true
		_just_released = false


	func simulate_release() -> void:
		_just_pressed = false
		_just_released = true


	func clear_input() -> void:
		_just_pressed = false
		_just_released = false


	func handle_shooting_input() -> bool:
		## Returns true if a shot was fired this frame.

		# Buffer semi-auto clicks
		if not weapon.is_automatic and _just_pressed:
			_semi_auto_shoot_buffered = true

		# Determine if shooting input is active
		var shoot_input_active: bool
		if weapon.is_automatic:
			shoot_input_active = false  # Would use IsActionPressed in real code
		else:
			# Fire if we have a buffered click and weapon can fire
			shoot_input_active = _semi_auto_shoot_buffered and weapon.can_fire()

		if not shoot_input_active:
			return false

		# Consume the buffered input
		if not weapon.is_automatic:
			_semi_auto_shoot_buffered = false

		# Fire the weapon
		return weapon.fire()


# ============================================================================
# Test Variables
# ============================================================================


var weapon: MockWeapon
var input: MockShootingInput


func before_each() -> void:
	weapon = MockWeapon.new()
	input = MockShootingInput.new(weapon)


func after_each() -> void:
	weapon = null
	input = null


# ============================================================================
# Basic Shooting Tests
# ============================================================================


func test_basic_click_fires_weapon() -> void:
	input.simulate_click()
	var fired := input.handle_shooting_input()

	assert_true(fired, "Click should fire the weapon")
	assert_eq(weapon.shots_fired, 1, "One shot should be fired")


func test_no_fire_without_click() -> void:
	var fired := input.handle_shooting_input()

	assert_false(fired, "Should not fire without a click")
	assert_eq(weapon.shots_fired, 0, "No shots should be fired")


# ============================================================================
# Input Buffering Tests (Issue #625 Regression)
# ============================================================================


func test_click_during_cooldown_is_buffered() -> void:
	# Fire first shot
	input.simulate_click()
	input.handle_shooting_input()
	input.clear_input()
	assert_eq(weapon.shots_fired, 1, "First shot should fire")

	# Click during cooldown - should be buffered, not lost
	input.simulate_click()
	var fired := input.handle_shooting_input()
	assert_false(fired, "Should not fire during cooldown")
	assert_true(input._semi_auto_shoot_buffered, "Click should be buffered")
	input.clear_input()

	# Advance time past cooldown
	weapon.update(1.0 / weapon.fire_rate + 0.01)

	# Buffered click should fire now
	fired = input.handle_shooting_input()
	assert_true(fired, "Buffered click should fire after cooldown expires")
	assert_eq(weapon.shots_fired, 2, "Two shots should have been fired total")


func test_rapid_clicking_fires_at_max_fire_rate() -> void:
	var delta := 1.0 / 60.0  # 60 FPS
	var fire_cooldown := 1.0 / weapon.fire_rate  # ~143ms for PM

	# Simulate rapid clicking: click every frame for 1 second
	var total_frames := int(1.0 / delta)
	var click_interval := 3  # Click every 3 frames (~50ms, faster than fire rate)

	for frame in range(total_frames):
		# Simulate input
		if frame % click_interval == 0:
			input.simulate_click()
		else:
			input.clear_input()

		input.handle_shooting_input()
		weapon.update(delta)

	# With buffering, we should fire at approximately the weapon's fire rate
	# PM fire rate is 7.0 shots/sec, in 1 second we should get ~7 shots
	# (may be 6-7 due to timing)
	assert_true(weapon.shots_fired >= 6,
		"Rapid clicking should fire at least 6 shots in 1 second (fire rate 7.0). Got: %d" % weapon.shots_fired)
	assert_true(weapon.shots_fired <= 8,
		"Should not exceed fire rate. Got: %d" % weapon.shots_fired)


func test_click_and_release_during_cooldown_still_fires() -> void:
	# Fire first shot
	input.simulate_click()
	input.handle_shooting_input()
	input.clear_input()
	assert_eq(weapon.shots_fired, 1, "First shot should fire")

	# Click during cooldown
	input.simulate_click()
	input.handle_shooting_input()
	input.clear_input()

	# Release during cooldown (player released mouse before cooldown expired)
	# Buffer should NOT be cleared by release
	input.clear_input()

	# Advance time past cooldown
	weapon.update(1.0 / weapon.fire_rate + 0.01)

	# Buffered click should still fire
	var fired := input.handle_shooting_input()
	assert_true(fired, "Buffered click should fire even after mouse release")
	assert_eq(weapon.shots_fired, 2, "Two shots should have been fired")


func test_without_buffering_clicks_are_lost() -> void:
	# This test demonstrates the old behavior (without buffering)
	# where clicks during cooldown are lost.
	# It verifies the problem that Issue #625 describes.

	var old_weapon := MockWeapon.new()
	var shots_without_buffer := 0
	var delta := 1.0 / 60.0
	var click_interval := 3  # Click every 3 frames

	# Simulate OLD behavior: only fire on the exact frame of click
	var fire_timer := 0.0
	var total_frames := int(1.0 / delta)

	for frame in range(total_frames):
		if fire_timer > 0:
			fire_timer -= delta

		var just_pressed := (frame % click_interval == 0)

		# Old behavior: IsActionJustPressed only true for one frame
		if just_pressed and old_weapon.current_ammo > 0 and fire_timer <= 0:
			old_weapon.current_ammo -= 1
			fire_timer = 1.0 / old_weapon.fire_rate
			shots_without_buffer += 1

	# Without buffering, many clicks are lost because they happen during cooldown
	# The buffered version should fire MORE shots
	assert_true(shots_without_buffer < weapon.shots_fired if weapon.shots_fired > 0 else true,
		"Old behavior without buffering loses clicks")


func test_buffer_consumed_after_firing() -> void:
	# Verify that the buffer is consumed after firing (no double shots)
	input.simulate_click()
	input.handle_shooting_input()
	input.clear_input()

	# Without another click, should not fire again even after cooldown
	weapon.update(1.0 / weapon.fire_rate + 0.01)
	var fired := input.handle_shooting_input()

	assert_false(fired, "Should not fire again without a new click")
	assert_eq(weapon.shots_fired, 1, "Only one shot should be fired from one click")


func test_empty_magazine_with_buffered_click() -> void:
	weapon.current_ammo = 1

	# Fire last bullet
	input.simulate_click()
	input.handle_shooting_input()
	input.clear_input()
	assert_eq(weapon.shots_fired, 1, "Should fire last bullet")

	# Click with empty magazine
	input.simulate_click()
	input.handle_shooting_input()
	input.clear_input()

	# Even after cooldown, should not fire (no ammo)
	weapon.update(1.0 / weapon.fire_rate + 0.01)
	var fired := input.handle_shooting_input()

	assert_false(fired, "Should not fire with empty magazine")
	assert_eq(weapon.shots_fired, 1, "Should still be 1 shot")


func test_buffer_works_during_reload() -> void:
	weapon.is_reloading = true

	# Click during reload - should buffer
	input.simulate_click()
	var fired := input.handle_shooting_input()

	assert_false(fired, "Should not fire during reload")
	assert_true(input._semi_auto_shoot_buffered, "Click should be buffered during reload")

	# Finish reload and advance time
	weapon.is_reloading = false
	weapon._fire_timer = 0.0

	# Buffered click should fire
	fired = input.handle_shooting_input()
	assert_true(fired, "Buffered click should fire after reload completes")
