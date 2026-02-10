extends GutTest
## Unit tests for Revolver hammer cock fire sequence (Issue #661, #649).
##
## Tests the revolver fire sequence:
## LMB press → hammer cock + cylinder rotation (sounds) → short delay → shot fires.
## Manual cock (Issue #649): RMB → instant cock → LMB → instant shot (no delay).
## The hammer cocking is a separate event that can be used by other systems.
## Uses mock classes to test logic without requiring Godot scene tree or C# runtime.


# Mock implementation that mirrors the Revolver hammer cock fire behavior
class MockRevolverFire:
	## Reload states matching RevolverReloadState enum
	const NOT_RELOADING = 0
	const CYLINDER_OPEN = 1
	const LOADING = 2

	var reload_state: int = NOT_RELOADING
	var current_ammo: int = 5
	var can_fire: bool = true

	## Hammer cock state (Issue #661)
	var is_hammer_cocked: bool = false
	var hammer_cock_timer: float = 0.0
	var pending_shot_direction: Vector2 = Vector2.ZERO
	const HAMMER_COCK_DELAY: float = 0.15

	## Manual hammer cock state (Issue #649)
	var is_manually_hammer_cocked: bool = false

	## Track events for assertions
	var hammer_cocked_emitted: bool = false
	var hammer_cock_sound_played: bool = false
	var cylinder_rotate_sound_played: bool = false
	var shot_sound_played: bool = false
	var shot_fired: bool = false
	var empty_click_played: bool = false
	var fire_count: int = 0

	## Issue #716: Per-chamber tracking (mirrors Revolver._chamberOccupied)
	var chamber_occupied: Array[bool] = [true, true, true, true, true]  # 5 chambers
	var current_chamber_index: int = 0

	## Fire timer tracking (mirrors BaseWeapon._fireTimer)
	var fire_timer: float = 0.0

	## Issue #649: Manually cock the hammer via RMB.
	## Instantly cocks the hammer so the next fire() call fires without delay.
	## NOTE: Does NOT check can_fire / fire timer — the whole point of manual cocking
	## is to bypass the fire delay between shots (Issue #649 fix).
	func manual_cock_hammer() -> bool:
		# Cannot cock while cylinder is open
		if reload_state != NOT_RELOADING:
			return false

		# Cannot cock if already cocked (either manually or via fire sequence)
		if is_hammer_cocked or is_manually_hammer_cocked:
			return false

		# Issue #716: Allow hammer cocking even with empty cylinder.
		# Real revolvers can cock the hammer regardless of ammo state.
		# The empty click occurs when firing (trigger pull), not during cocking.

		# Reset fire timer — manual cocking prepares the weapon for immediate fire
		fire_timer = 0
		can_fire = true

		# Instantly cock the hammer
		is_manually_hammer_cocked = true

		# Play hammer cock and cylinder rotation sounds
		hammer_cock_sound_played = true
		cylinder_rotate_sound_played = true

		# Emit HammerCocked signal
		hammer_cocked_emitted = true

		return true


	func fire(direction: Vector2) -> bool:
		# Cannot fire while cylinder is open
		if reload_state != NOT_RELOADING:
			return false

		# Cannot fire while hammer is already cocked and waiting to fire (auto-cock delay)
		if is_hammer_cocked:
			return false

		# Check if we can fire at all
		if not can_fire:
			return false

		# Issue #649: If hammer was manually cocked, fire immediately without delay
		# Issue #716: Cocked fire is from CURRENT slot (no rotation before fire)
		if is_manually_hammer_cocked:
			is_manually_hammer_cocked = false

			# Issue #716: Check current chamber for cocked fire - click or shoot
			var current_chamber_has_round = current_chamber_index < chamber_occupied.size() and chamber_occupied[current_chamber_index]

			if not current_chamber_has_round:
				# Issue #716: Play empty click sound on cocked fire with empty chamber
				empty_click_played = true
				return true  # Action was performed (click)

			_execute_shot(direction)
			return true

		# Issue #716: Uncocked fire - cylinder rotates FIRST, then fire from NEW slot
		# Step 1: Rotate cylinder to next position BEFORE hammer cock animation
		current_chamber_index = (current_chamber_index + 1) % chamber_occupied.size()

		# Issue #661: Now cock the hammer - shot happens after delay from NEW position
		is_hammer_cocked = true
		hammer_cock_timer = HAMMER_COCK_DELAY
		pending_shot_direction = direction

		# Play hammer cock sound
		hammer_cock_sound_played = true

		# Play cylinder rotation sound
		cylinder_rotate_sound_played = true

		# Emit HammerCocked signal
		hammer_cocked_emitted = true

		return true


	func process(delta: float) -> void:
		# Handle hammer cock delay timer
		if is_hammer_cocked and hammer_cock_timer > 0:
			hammer_cock_timer -= delta
			if hammer_cock_timer <= 0:
				_execute_shot(pending_shot_direction)
				is_hammer_cocked = false


	func _execute_shot(direction: Vector2) -> void:
		# Re-check conditions
		if reload_state != NOT_RELOADING:
			return

		# Issue #716: Check current chamber (cylinder already rotated for uncocked shots)
		var current_chamber_has_round = current_chamber_index < chamber_occupied.size() and chamber_occupied[current_chamber_index]

		if not current_chamber_has_round:
			# Issue #716: Play empty click sound when hammer falls on empty chamber
			empty_click_played = true
			return

		# Fire the shot
		current_ammo -= 1
		# Issue #716: Mark current chamber as empty, do NOT rotate (already done in fire())
		chamber_occupied[current_chamber_index] = false
		shot_fired = true
		shot_sound_played = true
		fire_count += 1

		# Set fire timer (mirrors base.Fire() setting _fireTimer = 1.0 / FireRate)
		fire_timer = 0.5  # 1.0 / 2.0 FireRate
		can_fire = false


	func reset_tracking() -> void:
		hammer_cocked_emitted = false
		hammer_cock_sound_played = false
		cylinder_rotate_sound_played = false
		shot_sound_played = false
		shot_fired = false
		empty_click_played = false

	## Reset all state including ammo and chambers
	func full_reset() -> void:
		reset_tracking()
		current_ammo = 5
		chamber_occupied = [true, true, true, true, true]
		current_chamber_index = 0
		is_hammer_cocked = false
		is_manually_hammer_cocked = false
		hammer_cock_timer = 0.0
		fire_timer = 0.0
		can_fire = true
		fire_count = 0


var revolver: MockRevolverFire


func before_each() -> void:
	revolver = MockRevolverFire.new()


func after_each() -> void:
	revolver = null


# ============================================================================
# Hammer Cock Sequence Tests (Issue #661)
# ============================================================================


func test_fire_cocks_hammer_first() -> void:
	## Pressing fire should cock the hammer, not fire immediately
	revolver.fire(Vector2.RIGHT)

	assert_true(revolver.is_hammer_cocked, "Hammer should be cocked after fire press")
	assert_false(revolver.shot_fired, "Shot should NOT fire immediately")


func test_fire_plays_hammer_cock_sound() -> void:
	## Hammer cock sound should play when fire is pressed
	revolver.fire(Vector2.RIGHT)

	assert_true(revolver.hammer_cock_sound_played, "Hammer cock sound should play on fire")


func test_fire_plays_cylinder_rotate_sound() -> void:
	## Cylinder rotation sound should play when fire is pressed
	revolver.fire(Vector2.RIGHT)

	assert_true(revolver.cylinder_rotate_sound_played, "Cylinder rotate sound should play on fire")


func test_fire_emits_hammer_cocked_signal() -> void:
	## HammerCocked signal should be emitted as a separate event
	revolver.fire(Vector2.RIGHT)

	assert_true(revolver.hammer_cocked_emitted, "HammerCocked signal should be emitted")


func test_shot_fires_after_delay() -> void:
	## The actual shot should fire after the hammer cock delay
	revolver.fire(Vector2.RIGHT)

	# Simulate time passing (full delay)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)

	assert_true(revolver.shot_fired, "Shot should fire after hammer cock delay")
	assert_true(revolver.shot_sound_played, "Shot sound should play after delay")


func test_shot_does_not_fire_before_delay() -> void:
	## The shot should NOT fire before the delay expires
	revolver.fire(Vector2.RIGHT)

	# Simulate partial time (not enough for delay)
	revolver.process(revolver.HAMMER_COCK_DELAY * 0.5)

	assert_false(revolver.shot_fired, "Shot should NOT fire before delay expires")
	assert_true(revolver.is_hammer_cocked, "Hammer should still be cocked")


func test_ammo_consumed_after_delay() -> void:
	## Ammo should be consumed when the shot actually fires (after delay)
	revolver.current_ammo = 5
	revolver.fire(Vector2.RIGHT)

	assert_eq(revolver.current_ammo, 5, "Ammo should NOT be consumed during hammer cock")

	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)

	assert_eq(revolver.current_ammo, 4, "Ammo should be consumed after shot fires")


func test_cannot_fire_while_hammer_cocked() -> void:
	## Cannot initiate another fire while hammer is already cocked
	revolver.fire(Vector2.RIGHT)
	revolver.reset_tracking()

	var result := revolver.fire(Vector2.RIGHT)

	assert_false(result, "Should not fire while hammer is already cocked")
	assert_false(revolver.hammer_cock_sound_played, "Should not play hammer cock sound again")


func test_uncocked_fire_rotates_then_fires() -> void:
	## Issue #716: Uncocked fire rotates cylinder FIRST, then fires from NEW slot
	revolver.current_ammo = 5
	revolver.current_chamber_index = 0

	# LMB fire (uncocked) - should rotate cylinder first
	revolver.fire(Vector2.RIGHT)

	# Cylinder should have rotated to slot 1 BEFORE hammer cock delay starts
	assert_eq(revolver.current_chamber_index, 1, "Cylinder should rotate to slot 1")
	assert_true(revolver.is_hammer_cocked, "Hammer should be cocked")
	assert_false(revolver.shot_fired, "Shot should NOT fire immediately")

	# After delay, fires from slot 1
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_true(revolver.shot_fired, "Shot should fire after delay")
	assert_false(revolver.chamber_occupied[1], "Slot 1 should be empty after firing")
	assert_true(revolver.chamber_occupied[0], "Slot 0 should still have round (not fired)")


func test_cannot_fire_while_reloading() -> void:
	## Cannot fire while cylinder is open for reload
	revolver.reload_state = MockRevolverFire.CYLINDER_OPEN

	var result := revolver.fire(Vector2.RIGHT)

	assert_false(result, "Should not fire while cylinder is open")
	assert_false(revolver.is_hammer_cocked, "Hammer should not be cocked")


func test_shot_cancelled_if_cylinder_opened_during_delay() -> void:
	## If player opens cylinder during hammer cock delay, shot should be cancelled
	revolver.fire(Vector2.RIGHT)

	# Open cylinder during delay
	revolver.reload_state = MockRevolverFire.CYLINDER_OPEN

	# Process the delay
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)

	assert_false(revolver.shot_fired, "Shot should be cancelled if cylinder opened")


func test_shot_cancelled_if_ammo_gone_during_delay() -> void:
	## If ammo somehow reaches 0 during delay, shot should be cancelled
	revolver.fire(Vector2.RIGHT)

	# Remove ammo during delay
	revolver.current_ammo = 0

	# Process the delay
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)

	assert_false(revolver.shot_fired, "Shot should be cancelled if no ammo")


func test_hammer_uncocks_after_shot() -> void:
	## Hammer should return to uncocked state after shot fires
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)

	assert_false(revolver.is_hammer_cocked, "Hammer should be uncocked after shot")


func test_can_fire_again_after_shot_completes() -> void:
	## Should be able to fire again after previous shot completes
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)

	assert_true(revolver.shot_fired, "First shot should have fired")
	revolver.reset_tracking()

	# Fire again
	var result := revolver.fire(Vector2.RIGHT)

	assert_true(result, "Should be able to fire again")
	assert_true(revolver.hammer_cock_sound_played, "Should play hammer cock sound again")


func test_multiple_shots_sequence() -> void:
	## Test firing multiple shots in sequence (uncocked - rotates before each)
	revolver.full_reset()

	# Shot 1 (rotates to slot 1, fires from slot 1)
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.fire_count, 1, "Should have fired 1 shot")
	assert_eq(revolver.current_ammo, 4, "Should have 4 rounds left")

	# Shot 2 (rotates to slot 2, fires from slot 2)
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.fire_count, 2, "Should have fired 2 shots")
	assert_eq(revolver.current_ammo, 3, "Should have 3 rounds left")

	# Shot 3 (rotates to slot 3, fires from slot 3)
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.fire_count, 3, "Should have fired 3 shots")
	assert_eq(revolver.current_ammo, 2, "Should have 2 rounds left")

	# Shot 4 (rotates to slot 4, fires from slot 4)
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.fire_count, 4, "Should have fired 4 shots")
	assert_eq(revolver.current_ammo, 1, "Should have 1 round left")

	# Shot 5 (rotates to slot 0 - already empty from skip, fires from slot 0)
	# Note: Slot 0 was never fired! Only slots 1-4 were fired.
	# Now slot 0 gets fired
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.fire_count, 5, "Should have fired 5 shots")
	assert_eq(revolver.current_ammo, 0, "Should have 0 rounds left")


func test_hammer_cock_delay_value() -> void:
	## The hammer cock delay should be 0.15 seconds (responsive but audible)
	assert_eq(revolver.HAMMER_COCK_DELAY, 0.15, "Hammer cock delay should be 0.15 seconds")


func test_fire_returns_true_on_hammer_cock() -> void:
	## Fire should return true when hammer cock sequence starts successfully
	var result := revolver.fire(Vector2.RIGHT)

	assert_true(result, "Fire should return true when hammer cock initiates")


func test_sounds_play_before_shot() -> void:
	## Hammer cock and cylinder rotate sounds should play before the shot sound
	revolver.fire(Vector2.RIGHT)

	# At this point: hammer cock and cylinder sounds played, shot not yet
	assert_true(revolver.hammer_cock_sound_played, "Hammer cock sound should play first")
	assert_true(revolver.cylinder_rotate_sound_played, "Cylinder rotate sound should play first")
	assert_false(revolver.shot_sound_played, "Shot sound should NOT play yet")

	# After delay: shot sound plays
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_true(revolver.shot_sound_played, "Shot sound should play after delay")


# ============================================================================
# Manual Hammer Cock Tests (Issue #649)
# ============================================================================


func test_manual_cock_sets_state() -> void:
	## RMB should manually cock the hammer
	var result := revolver.manual_cock_hammer()

	assert_true(result, "Manual cock should succeed")
	assert_true(revolver.is_manually_hammer_cocked, "Should be manually cocked")


func test_manual_cock_plays_sounds() -> void:
	## Manual cock should play hammer cock and cylinder rotation sounds
	revolver.manual_cock_hammer()

	assert_true(revolver.hammer_cock_sound_played, "Hammer cock sound should play")
	assert_true(revolver.cylinder_rotate_sound_played, "Cylinder rotate sound should play")


func test_manual_cock_emits_signal() -> void:
	## Manual cock should emit HammerCocked signal
	revolver.manual_cock_hammer()

	assert_true(revolver.hammer_cocked_emitted, "HammerCocked signal should be emitted")


func test_manual_cock_does_not_fire() -> void:
	## Manual cock alone should NOT fire the weapon
	revolver.manual_cock_hammer()

	assert_false(revolver.shot_fired, "Shot should NOT fire on manual cock")
	assert_eq(revolver.current_ammo, 5, "Ammo should not be consumed")


func test_fire_after_manual_cock_is_instant() -> void:
	## After manual cock (RMB), fire (LMB) should be instant (no delay)
	revolver.manual_cock_hammer()
	revolver.reset_tracking()

	# Fire immediately - no process() needed (no delay)
	var result := revolver.fire(Vector2.RIGHT)

	assert_true(result, "Fire should succeed")
	assert_true(revolver.shot_fired, "Shot should fire INSTANTLY after manual cock")
	assert_eq(revolver.current_ammo, 4, "Ammo should be consumed")


func test_fire_after_manual_cock_no_extra_sounds() -> void:
	## Fire after manual cock should NOT play hammer cock sounds again
	## (they already played during the manual cock)
	revolver.manual_cock_hammer()
	revolver.reset_tracking()

	revolver.fire(Vector2.RIGHT)

	assert_false(revolver.hammer_cock_sound_played, "No extra hammer cock sound on fire")
	assert_false(revolver.cylinder_rotate_sound_played, "No extra cylinder rotate sound on fire")
	assert_true(revolver.shot_sound_played, "Shot sound should play")


func test_manual_cock_resets_after_fire() -> void:
	## After firing with manual cock, the state should reset
	revolver.manual_cock_hammer()
	revolver.fire(Vector2.RIGHT)

	assert_false(revolver.is_manually_hammer_cocked, "Manual cock state should reset after fire")


func test_cannot_manual_cock_while_cylinder_open() -> void:
	## Cannot manually cock hammer while cylinder is open for reload
	revolver.reload_state = MockRevolverFire.CYLINDER_OPEN

	var result := revolver.manual_cock_hammer()

	assert_false(result, "Should not cock while cylinder is open")
	assert_false(revolver.is_manually_hammer_cocked, "Should not be cocked")


func test_cannot_manual_cock_while_already_cocked() -> void:
	## Cannot manually cock if already manually cocked
	revolver.manual_cock_hammer()
	revolver.reset_tracking()

	var result := revolver.manual_cock_hammer()

	assert_false(result, "Should not cock again if already cocked")
	assert_false(revolver.hammer_cock_sound_played, "No sound if already cocked")


func test_cannot_manual_cock_while_auto_cocked() -> void:
	## Cannot manually cock if hammer is already auto-cocked (LMB fire sequence)
	revolver.fire(Vector2.RIGHT)
	revolver.reset_tracking()

	var result := revolver.manual_cock_hammer()

	assert_false(result, "Should not manually cock while auto-cock in progress")


func test_can_manual_cock_with_empty_cylinder() -> void:
	## Issue #716: CAN manually cock with empty cylinder (real revolver behavior)
	revolver.current_ammo = 0

	var result := revolver.manual_cock_hammer()

	assert_true(result, "Should be able to cock with empty cylinder (Issue #716)")
	assert_false(revolver.empty_click_played, "Should NOT play empty click on cock (only on fire)")
	assert_true(revolver.is_manually_hammer_cocked, "Hammer should be cocked even when empty")


func test_manual_cock_works_during_fire_timer() -> void:
	## Issue #649 fix: Manual cock should work even during fire timer cooldown.
	## The whole point of manual cocking is to bypass the fire delay.
	revolver.can_fire = false
	revolver.fire_timer = 0.4  # Simulate active fire timer after a shot

	var result := revolver.manual_cock_hammer()

	assert_true(result, "Should be able to cock during fire timer cooldown")
	assert_true(revolver.is_manually_hammer_cocked, "Should be manually cocked")
	assert_eq(revolver.fire_timer, 0.0, "Fire timer should be reset to 0")
	assert_true(revolver.can_fire, "Can_fire should be true after manual cock")


func test_manual_cock_then_fire_sequence() -> void:
	## Full manual cock flow: RMB → LMB = instant shot
	revolver.current_ammo = 3

	# Manual cock (RMB)
	revolver.manual_cock_hammer()
	assert_true(revolver.is_manually_hammer_cocked, "Should be manually cocked")
	assert_false(revolver.shot_fired, "No shot yet")

	# Fire (LMB) - instant, no delay
	revolver.fire(Vector2.RIGHT)
	assert_true(revolver.shot_fired, "Shot should fire instantly")
	assert_eq(revolver.current_ammo, 2, "Ammo consumed")
	assert_eq(revolver.fire_count, 1, "One shot fired")


func test_normal_vs_manual_cock_comparison() -> void:
	## Compare normal fire (with delay) vs manual cock fire (instant)
	## Normal fire: requires process() to pass delay before shot fires
	revolver.current_ammo = 5

	# Normal fire - shot does NOT fire immediately
	revolver.fire(Vector2.RIGHT)
	assert_false(revolver.shot_fired, "Normal: shot not immediate")
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_true(revolver.shot_fired, "Normal: shot after delay")
	assert_eq(revolver.current_ammo, 4, "Normal: ammo consumed after delay")

	revolver.reset_tracking()

	# Manual cock fire - shot fires immediately
	revolver.manual_cock_hammer()
	revolver.reset_tracking()
	revolver.fire(Vector2.RIGHT)
	assert_true(revolver.shot_fired, "Manual: shot fires instantly")
	assert_eq(revolver.current_ammo, 3, "Manual: ammo consumed instantly")


func test_multiple_manual_cock_shots() -> void:
	## Test firing multiple shots using manual cocking
	## Issue #716: Manual cock fires from CURRENT slot (no rotation)
	revolver.full_reset()
	revolver.current_chamber_index = 0  # Start at slot 0

	# Shot 1: manual cock + fire from slot 0
	revolver.manual_cock_hammer()
	revolver.fire(Vector2.RIGHT)
	assert_eq(revolver.fire_count, 1, "Should have fired 1 shot")
	assert_eq(revolver.current_ammo, 4, "Should have 4 rounds left")
	assert_eq(revolver.current_chamber_index, 0, "Cocked fire: stayed at slot 0")

	# Shot 2: manual cock + fire - still at slot 0 but it's empty now!
	# Since we haven't rotated, slot 0 is empty - should click
	revolver.reset_tracking()
	revolver.manual_cock_hammer()
	revolver.fire(Vector2.RIGHT)
	assert_true(revolver.empty_click_played, "Should click - slot 0 is now empty")
	assert_false(revolver.shot_fired, "Should not fire from empty slot")

	# Player needs to use uncocked fire to rotate to next slot
	revolver.reset_tracking()
	revolver.fire(Vector2.RIGHT)  # Rotates to slot 1, fires
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.current_chamber_index, 1, "Uncocked fire rotated to slot 1")
	assert_true(revolver.shot_fired, "Shot fired from slot 1")
	assert_eq(revolver.fire_count, 2, "Should have fired 2 shots total")
	assert_eq(revolver.current_ammo, 3, "Should have 3 rounds left")


func test_fire_then_immediate_manual_cock_then_fire() -> void:
	## Issue #649 key scenario: fire a shot, immediately manual cock, fire again.
	## This is the rapid fire sequence the player wants to use.
	## Issue #716 update: Uncocked fire rotates first, so we adjust expectations.
	revolver.full_reset()
	revolver.current_ammo = 5
	revolver.current_chamber_index = 0

	# Normal fire (LMB) — rotates to slot 1, shot fires after delay
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_true(revolver.shot_fired, "First shot should have fired")
	assert_eq(revolver.current_ammo, 4, "Should have 4 rounds after first shot")
	assert_eq(revolver.current_chamber_index, 1, "Should be at slot 1 after uncocked fire")
	assert_true(revolver.fire_timer > 0, "Fire timer should be active after shot")
	assert_false(revolver.can_fire, "Can_fire should be false during fire timer")

	revolver.reset_tracking()

	# Immediately manual cock (RMB) — should work despite fire timer
	var cock_result := revolver.manual_cock_hammer()
	assert_true(cock_result, "Manual cock should succeed during fire timer cooldown")
	assert_true(revolver.is_manually_hammer_cocked, "Should be manually cocked")
	assert_eq(revolver.fire_timer, 0.0, "Fire timer should be reset")

	revolver.reset_tracking()

	# Fire again (LMB) — instant shot from current slot (no rotation for cocked fire)
	var fire_result := revolver.fire(Vector2.RIGHT)
	assert_true(fire_result, "Fire should succeed after manual cock")
	assert_true(revolver.shot_fired, "Shot should fire instantly")
	assert_eq(revolver.current_ammo, 3, "Should have 3 rounds left")
	assert_eq(revolver.fire_count, 2, "Should have fired 2 shots total")
	assert_eq(revolver.current_chamber_index, 1, "Should stay at slot 1 (cocked fire)")


func test_manual_cock_cylinder_open_cancels() -> void:
	## If player opens cylinder after manual cock, the cock state should reset
	revolver.manual_cock_hammer()
	assert_true(revolver.is_manually_hammer_cocked, "Should be manually cocked")

	# Opening cylinder resets manual cock state
	revolver.reload_state = MockRevolverFire.CYLINDER_OPEN
	revolver.is_manually_hammer_cocked = false  # Simulates OpenCylinder() resetting state

	var result := revolver.fire(Vector2.RIGHT)
	assert_false(result, "Should not fire - cylinder is open")


func test_empty_cylinder_cock_then_fire_plays_click() -> void:
	## Issue #716: Can cock empty cylinder, but firing should play empty click sound
	revolver.current_ammo = 0
	revolver.chamber_occupied = [false, false, false, false, false]  # All empty

	# Manual cock should succeed
	var cock_result := revolver.manual_cock_hammer()
	assert_true(cock_result, "Should cock with empty cylinder (Issue #716)")
	assert_true(revolver.is_manually_hammer_cocked, "Hammer should be cocked")
	assert_false(revolver.empty_click_played, "No click on cock")

	revolver.reset_tracking()

	# Fire should play empty click (not shoot)
	var fire_result := revolver.fire(Vector2.RIGHT)
	assert_true(fire_result, "Fire call returns true")
	assert_true(revolver.empty_click_played, "Should play empty click on fire")
	assert_false(revolver.shot_fired, "Should NOT fire bullet")
	assert_eq(revolver.current_ammo, 0, "Ammo should remain 0")


# ============================================================================
# Cylinder Rotation Timing Tests (Issue #716)
# ============================================================================


func test_cocked_fire_no_rotation() -> void:
	## Issue #716: Cocked fire (RMB then LMB) fires from CURRENT slot, no rotation
	revolver.current_chamber_index = 2  # Start at slot 2
	revolver.chamber_occupied[2] = true  # Slot 2 has round

	# Manual cock (RMB)
	revolver.manual_cock_hammer()
	assert_eq(revolver.current_chamber_index, 2, "Cylinder should NOT rotate on cock")

	revolver.reset_tracking()

	# Fire (LMB) - should fire from slot 2, no rotation
	revolver.fire(Vector2.RIGHT)
	assert_eq(revolver.current_chamber_index, 2, "Cylinder should stay at slot 2 for cocked fire")
	assert_true(revolver.shot_fired, "Should fire from current slot")
	assert_false(revolver.chamber_occupied[2], "Slot 2 should be empty after firing")


func test_uncocked_fire_to_empty_slot_clicks() -> void:
	## Issue #716: If uncocked fire rotates to empty slot, should click (not fire)
	revolver.current_chamber_index = 0  # Start at slot 0
	revolver.chamber_occupied = [true, false, true, true, true]  # Slot 1 is empty

	# LMB fire (uncocked) - rotates to slot 1 (empty)
	revolver.fire(Vector2.RIGHT)
	assert_eq(revolver.current_chamber_index, 1, "Should rotate to slot 1")

	# After delay, should click (slot 1 is empty)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_true(revolver.empty_click_played, "Should click - slot 1 is empty")
	assert_false(revolver.shot_fired, "Should NOT fire from empty slot")
	assert_eq(revolver.current_ammo, 5, "Ammo should not be consumed")


func test_cocked_fire_on_empty_current_slot() -> void:
	## Issue #716: Cocked fire on empty current slot plays click sound
	revolver.current_chamber_index = 2
	revolver.chamber_occupied[2] = false  # Current slot is empty

	# Manual cock should succeed (Issue #716: can cock on empty slot)
	var cock_result := revolver.manual_cock_hammer()
	assert_true(cock_result, "Should cock even with empty current slot")

	revolver.reset_tracking()

	# Fire should click (not shoot)
	revolver.fire(Vector2.RIGHT)
	assert_true(revolver.empty_click_played, "Should click - current slot is empty")
	assert_false(revolver.shot_fired, "Should NOT fire from empty slot")
	assert_eq(revolver.current_chamber_index, 2, "Cylinder should stay at slot 2 (no rotation)")


func test_rotation_sequence_uncocked_fire() -> void:
	## Issue #716: Verify full uncocked fire sequence - rotate first, fire from new slot
	revolver.full_reset()
	revolver.current_chamber_index = 3  # Start at slot 3

	# Fire 1 (uncocked) - rotates to slot 4, fires from slot 4
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.current_chamber_index, 4, "First fire should rotate to slot 4")
	assert_false(revolver.chamber_occupied[4], "Slot 4 should be empty after firing")
	assert_true(revolver.chamber_occupied[3], "Slot 3 should still have round")

	revolver.reset_tracking()

	# Fire 2 (uncocked) - rotates to slot 0 (wrap), fires from slot 0
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.current_chamber_index, 0, "Second fire should wrap to slot 0")
	assert_false(revolver.chamber_occupied[0], "Slot 0 should be empty after firing")


func test_cocked_vs_uncocked_rotation_difference() -> void:
	## Issue #716: Demonstrate the key difference between cocked and uncocked fire
	revolver.full_reset()
	revolver.current_chamber_index = 0

	# Scenario A: Cocked fire stays at current slot
	revolver.manual_cock_hammer()
	revolver.fire(Vector2.RIGHT)
	assert_eq(revolver.current_chamber_index, 0, "Cocked fire: stays at slot 0")
	assert_false(revolver.chamber_occupied[0], "Cocked fire: slot 0 fired")
	assert_true(revolver.chamber_occupied[1], "Cocked fire: slot 1 still loaded")

	revolver.reset_tracking()

	# Scenario B: Uncocked fire rotates first
	revolver.fire(Vector2.RIGHT)  # Rotates to slot 1, then fires
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.current_chamber_index, 1, "Uncocked fire: rotated to slot 1")
	assert_false(revolver.chamber_occupied[1], "Uncocked fire: slot 1 fired")
