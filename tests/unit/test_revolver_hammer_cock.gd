extends GutTest
## Unit tests for Revolver hammer cock fire sequence (Issue #661).
##
## Tests the revolver fire sequence:
## LMB press → hammer cock + cylinder rotation (sounds) → short delay → shot fires.
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

	## Track events for assertions
	var hammer_cocked_emitted: bool = false
	var hammer_cock_sound_played: bool = false
	var cylinder_rotate_sound_played: bool = false
	var shot_sound_played: bool = false
	var shot_fired: bool = false
	var empty_click_played: bool = false
	var fire_count: int = 0


	func fire(direction: Vector2) -> bool:
		# Cannot fire while cylinder is open
		if reload_state != NOT_RELOADING:
			return false

		# Cannot fire while hammer is already cocked
		if is_hammer_cocked:
			return false

		# Check for empty cylinder
		if current_ammo <= 0:
			empty_click_played = true
			return false

		# Check if we can fire at all
		if not can_fire:
			return false

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
