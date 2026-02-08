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


	## Issue #649: Manually cock the hammer via RMB.
	## Instantly cocks the hammer so the next fire() call fires without delay.
	func manual_cock_hammer() -> bool:
		# Cannot cock while cylinder is open
		if reload_state != NOT_RELOADING:
			return false

		# Cannot cock if already cocked (either manually or via fire sequence)
		if is_hammer_cocked or is_manually_hammer_cocked:
			return false

		# Cannot cock with empty cylinder
		if current_ammo <= 0:
			empty_click_played = true
			return false

		# Cannot cock if weapon can't fire (fire timer active)
		if not can_fire:
			return false

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

		# Check for empty cylinder
		if current_ammo <= 0:
			empty_click_played = true
			return false

		# Check if we can fire at all
		if not can_fire:
			return false

		# Issue #649: If hammer was manually cocked, fire immediately without delay
		if is_manually_hammer_cocked:
			is_manually_hammer_cocked = false
			_execute_shot(direction)
			return true

		# Issue #661: Cock the hammer and rotate the cylinder before firing
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
		if current_ammo <= 0:
			return

		# Fire the shot
		current_ammo -= 1
		shot_fired = true
		shot_sound_played = true
		fire_count += 1


	func reset_tracking() -> void:
		hammer_cocked_emitted = false
		hammer_cock_sound_played = false
		cylinder_rotate_sound_played = false
		shot_sound_played = false
		shot_fired = false
		empty_click_played = false


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


func test_cannot_fire_with_empty_cylinder() -> void:
	## Empty cylinder should play click sound, not cock hammer
	revolver.current_ammo = 0

	var result := revolver.fire(Vector2.RIGHT)

	assert_false(result, "Should not fire with empty cylinder")
	assert_true(revolver.empty_click_played, "Should play empty click sound")
	assert_false(revolver.is_hammer_cocked, "Hammer should not be cocked")
	assert_false(revolver.hammer_cock_sound_played, "Should not play hammer cock sound")


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
	## Test firing multiple shots in sequence
	revolver.current_ammo = 3

	# Shot 1
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.fire_count, 1, "Should have fired 1 shot")
	assert_eq(revolver.current_ammo, 2, "Should have 2 rounds left")

	# Shot 2
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.fire_count, 2, "Should have fired 2 shots")
	assert_eq(revolver.current_ammo, 1, "Should have 1 round left")

	# Shot 3
	revolver.fire(Vector2.RIGHT)
	revolver.process(revolver.HAMMER_COCK_DELAY + 0.01)
	assert_eq(revolver.fire_count, 3, "Should have fired 3 shots")
	assert_eq(revolver.current_ammo, 0, "Should have 0 rounds left")

	# Shot 4 - should fail (empty)
	var result := revolver.fire(Vector2.RIGHT)
	assert_false(result, "Should not fire with empty cylinder")
	assert_true(revolver.empty_click_played, "Should play empty click")


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


func test_cannot_manual_cock_with_empty_cylinder() -> void:
	## Cannot manually cock with empty cylinder
	revolver.current_ammo = 0

	var result := revolver.manual_cock_hammer()

	assert_false(result, "Should not cock with empty cylinder")
	assert_true(revolver.empty_click_played, "Should play empty click sound")
	assert_false(revolver.is_manually_hammer_cocked, "Should not be cocked")


func test_cannot_manual_cock_when_cannot_fire() -> void:
	## Cannot manually cock when weapon can't fire (fire timer active)
	revolver.can_fire = false

	var result := revolver.manual_cock_hammer()

	assert_false(result, "Should not cock when can't fire")
	assert_false(revolver.is_manually_hammer_cocked, "Should not be cocked")


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
	revolver.current_ammo = 3

	# Shot 1: manual cock + fire
	revolver.manual_cock_hammer()
	revolver.fire(Vector2.RIGHT)
	assert_eq(revolver.fire_count, 1, "Should have fired 1 shot")
	assert_eq(revolver.current_ammo, 2, "Should have 2 rounds left")

	# Shot 2: manual cock + fire
	revolver.manual_cock_hammer()
	revolver.fire(Vector2.RIGHT)
	assert_eq(revolver.fire_count, 2, "Should have fired 2 shots")
	assert_eq(revolver.current_ammo, 1, "Should have 1 round left")

	# Shot 3: manual cock + fire
	revolver.manual_cock_hammer()
	revolver.fire(Vector2.RIGHT)
	assert_eq(revolver.fire_count, 3, "Should have fired 3 shots")
	assert_eq(revolver.current_ammo, 0, "Should have 0 rounds left")

	# Shot 4: manual cock should fail (empty)
	var result := revolver.manual_cock_hammer()
	assert_false(result, "Should not cock with empty cylinder")
	assert_true(revolver.empty_click_played, "Should play empty click")


func test_manual_cock_cylinder_open_cancels() -> void:
	## If player opens cylinder after manual cock, the cock state should reset
	revolver.manual_cock_hammer()
	assert_true(revolver.is_manually_hammer_cocked, "Should be manually cocked")

	# Opening cylinder resets manual cock state
	revolver.reload_state = MockRevolverFire.CYLINDER_OPEN
	revolver.is_manually_hammer_cocked = false  # Simulates OpenCylinder() resetting state

	var result := revolver.fire(Vector2.RIGHT)
	assert_false(result, "Should not fire - cylinder is open")
