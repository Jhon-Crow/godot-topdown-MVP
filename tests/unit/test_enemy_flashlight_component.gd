extends GutTest
## Unit tests for EnemyFlashlightComponent (Issue #824, #825).
##
## Tests the enemy flashlight behavior in night mode, including:
## - Pre-attack flash timing (300-500ms before shooting/grenade, Issue #825 fix)
## - Player detection in beam
## - Stun effect application via FlashbangPlayerEffectsManager
## - Night mode activation check
## - No shooting while flashlight is already running (Issue #825 bug fix)


# ============================================================================
# Mock Classes for Testing
# ============================================================================


class MockEnemyFlashlightComponent:
	## Pre-attack flash duration range (300-500ms, Issue #825 fix: was 50-100ms).
	const PRE_ATTACK_FLASH_DURATION_MIN: float = 0.3
	const PRE_ATTACK_FLASH_DURATION_MAX: float = 0.5

	## Flashlight beam half-angle in degrees (matches player flashlight).
	const BEAM_HALF_ANGLE_DEG: float = 9.0

	## Maximum range for the flashlight beam.
	const BEAM_RANGE: float = 600.0

	## Duration of the blindness effect on the player (seconds).
	const BLINDNESS_DURATION: float = 2.0

	## Cooldown in seconds before the player can be blinded again.
	const BLINDNESS_COOLDOWN: float = 20.0

	## Collision mask for obstacles.
	const OBSTACLE_COLLISION_MASK: int = 4

	## Whether the flashlight is currently on.
	var _is_on: bool = false

	## Whether currently in pre-attack flash phase.
	var _is_flashing_for_attack: bool = false

	## Flash timer.
	var _flash_timer: float = 0.0

	## Target flash duration.
	var _flash_target_duration: float = 0.0

	## Callback after flash completes.
	var _flash_callback: Callable = Callable()

	## Player blinded time for cooldown.
	var _player_blinded_time: int = 0

	## Mock: simulated current time in msec.
	var _mock_time_msec: int = 0

	## Mock: whether night mode is active.
	var _mock_night_mode: bool = false

	## Mock: whether line of sight is clear.
	var _mock_line_of_sight: bool = true

	## Global position of the flashlight.
	var global_position: Vector2 = Vector2.ZERO

	## Global rotation of the flashlight (radians).
	var global_rotation: float = 0.0

	## Track blindness applications.
	var blindness_applied: Array = []

	## Track callback executions.
	var callbacks_executed: int = 0


	func set_mock_night_mode(enabled: bool) -> void:
		_mock_night_mode = enabled


	func set_mock_line_of_sight(enabled: bool) -> void:
		_mock_line_of_sight = enabled


	func set_mock_time_msec(time_msec: int) -> void:
		_mock_time_msec = time_msec


	func is_on() -> bool:
		return _is_on


	func is_flashing_for_attack() -> bool:
		return _is_flashing_for_attack


	func _turn_on() -> void:
		_is_on = true


	func _turn_off() -> void:
		_is_on = false


	func _is_night_mode_active() -> bool:
		return _mock_night_mode


	## Start the pre-attack flashlight sequence.
	func start_pre_attack_flash(target_position: Vector2, callback: Callable) -> void:
		if not _is_night_mode_active():
			# Night mode not active, execute callback immediately
			if callback.is_valid():
				callback.call()
				callbacks_executed += 1
			return

		if _is_flashing_for_attack:
			return

		_is_flashing_for_attack = true
		_flash_timer = 0.0
		_flash_target_duration = randf_range(PRE_ATTACK_FLASH_DURATION_MIN, PRE_ATTACK_FLASH_DURATION_MAX)
		_flash_callback = callback

		_turn_on()


	## Simulate physics process update.
	func process(delta: float) -> void:
		if not _is_flashing_for_attack:
			return

		_flash_timer += delta

		if _flash_timer >= _flash_target_duration:
			_complete_flash()


	## Complete the flash sequence.
	func _complete_flash() -> void:
		_turn_off()
		_is_flashing_for_attack = false

		if _flash_callback.is_valid():
			_flash_callback.call()
			callbacks_executed += 1
		_flash_callback = Callable()


	## Check if player is in beam.
	func _is_player_in_beam(player_position: Vector2) -> bool:
		var beam_origin := global_position
		var beam_direction := Vector2.RIGHT.rotated(global_rotation)
		var to_player := player_position - beam_origin
		var distance := to_player.length()

		if distance > BEAM_RANGE or distance < 1.0:
			return false

		var angle_to_player := abs(beam_direction.angle_to(to_player))
		if angle_to_player > deg_to_rad(BEAM_HALF_ANGLE_DEG):
			return false

		return _mock_line_of_sight


	## Apply blindness to the player.
	func _blind_player(player_position: Vector2) -> void:
		var current_time := _mock_time_msec

		if _player_blinded_time > 0:
			var elapsed_sec: float = float(current_time - _player_blinded_time) / 1000.0
			if elapsed_sec < BLINDNESS_COOLDOWN:
				return

		_player_blinded_time = current_time

		var distance := global_position.distance_to(player_position)
		blindness_applied.append({
			"distance": distance,
			"duration": BLINDNESS_DURATION
		})


	## Check and apply blindness to player in beam.
	func check_player_in_beam(player_position: Vector2) -> void:
		if not _is_on:
			return

		if _is_player_in_beam(player_position):
			_blind_player(player_position)


var component: MockEnemyFlashlightComponent


func before_each() -> void:
	component = MockEnemyFlashlightComponent.new()


func after_each() -> void:
	component = null


# ============================================================================
# Constants Tests
# ============================================================================


func test_pre_attack_duration_min_is_300ms() -> void:
	assert_eq(component.PRE_ATTACK_FLASH_DURATION_MIN, 0.3,
		"Pre-attack flash minimum duration should be 300ms (0.3s) — visible to player (Issue #825 fix)")


func test_pre_attack_duration_max_is_500ms() -> void:
	assert_eq(component.PRE_ATTACK_FLASH_DURATION_MAX, 0.5,
		"Pre-attack flash maximum duration should be 500ms (0.5s) — fair warning time (Issue #825 fix)")


func test_beam_half_angle_matches_player() -> void:
	assert_eq(component.BEAM_HALF_ANGLE_DEG, 9.0,
		"Beam half-angle should be 9 degrees (same as player)")


func test_beam_range_matches_player() -> void:
	assert_eq(component.BEAM_RANGE, 600.0,
		"Beam range should be 600 pixels (same as player)")


func test_blindness_duration_is_2_seconds() -> void:
	assert_eq(component.BLINDNESS_DURATION, 2.0,
		"Blindness duration should be 2.0 seconds")


func test_blindness_cooldown_is_20_seconds() -> void:
	assert_eq(component.BLINDNESS_COOLDOWN, 20.0,
		"Blindness cooldown should be 20.0 seconds")


# ============================================================================
# Night Mode Check Tests
# ============================================================================


func test_night_mode_off_executes_callback_immediately() -> void:
	component.set_mock_night_mode(false)

	var callback_called := false
	var callback := func(): callback_called = true

	component.start_pre_attack_flash(Vector2(300, 0), callback)

	assert_eq(component.callbacks_executed, 1,
		"Callback should be executed immediately when night mode is off")
	assert_false(component.is_on(),
		"Flashlight should not turn on when night mode is off")
	assert_false(component.is_flashing_for_attack(),
		"Should not be in flashing state when night mode is off")


func test_night_mode_on_starts_flash_sequence() -> void:
	component.set_mock_night_mode(true)

	component.start_pre_attack_flash(Vector2(300, 0), func(): pass)

	assert_true(component.is_on(),
		"Flashlight should turn on when night mode is active")
	assert_true(component.is_flashing_for_attack(),
		"Should be in flashing state when night mode is active")
	assert_eq(component.callbacks_executed, 0,
		"Callback should NOT be executed immediately when night mode is on")


# ============================================================================
# Flash Timing Tests
# ============================================================================


func test_flash_completes_after_duration() -> void:
	component.set_mock_night_mode(true)
	component._flash_target_duration = 0.3  # Force specific duration for test

	component.start_pre_attack_flash(Vector2(300, 0), func(): pass)
	assert_true(component.is_flashing_for_attack())

	# Simulate time passing
	component.process(0.2)  # 200ms
	assert_true(component.is_flashing_for_attack(),
		"Should still be flashing before duration completes")

	component.process(0.15)  # 350ms total (> 300ms)
	assert_false(component.is_flashing_for_attack(),
		"Should not be flashing after duration completes")
	assert_false(component.is_on(),
		"Flashlight should be off after flash completes")


func test_callback_executed_after_flash() -> void:
	component.set_mock_night_mode(true)
	component._flash_target_duration = 0.3

	component.start_pre_attack_flash(Vector2(300, 0), func(): pass)

	# Complete the flash
	component.process(0.35)

	assert_eq(component.callbacks_executed, 1,
		"Callback should be executed after flash completes")


func test_double_flash_request_ignored() -> void:
	component.set_mock_night_mode(true)

	component.start_pre_attack_flash(Vector2(300, 0), func(): pass)
	component.start_pre_attack_flash(Vector2(400, 0), func(): pass)

	# Only one flash should be active
	assert_eq(component.callbacks_executed, 0,
		"Second flash request should be ignored while first is in progress")


# ============================================================================
# Beam Detection Tests
# ============================================================================


func test_player_directly_in_front_detected() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0  # Pointing right

	assert_true(component._is_player_in_beam(Vector2(300, 0)),
		"Player directly in front should be in beam")


func test_player_behind_not_detected() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0  # Pointing right

	assert_false(component._is_player_in_beam(Vector2(-300, 0)),
		"Player behind should not be in beam")


func test_player_outside_cone_angle_not_detected() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0

	# 9 degrees half-angle: at distance 300, max offset is ~47.5
	assert_false(component._is_player_in_beam(Vector2(300, 100)),
		"Player outside cone angle should not be in beam")


func test_player_inside_cone_angle_detected() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0

	# At distance 300, offset of 30 gives angle ~5.7 degrees (< 9 degrees)
	assert_true(component._is_player_in_beam(Vector2(300, 30)),
		"Player inside cone angle should be in beam")


func test_player_beyond_range_not_detected() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0

	assert_false(component._is_player_in_beam(Vector2(700, 0)),
		"Player beyond beam range should not be in beam")


func test_player_blocked_by_wall_not_detected() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0
	component.set_mock_line_of_sight(false)

	assert_false(component._is_player_in_beam(Vector2(300, 0)),
		"Player blocked by wall should not be in beam")


# ============================================================================
# Player Blinding Tests
# ============================================================================


func test_player_in_beam_gets_blinded() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0
	component._turn_on()
	component.set_mock_time_msec(0)

	component.check_player_in_beam(Vector2(300, 0))

	assert_eq(component.blindness_applied.size(), 1,
		"Player in beam should be blinded")


func test_player_not_blinded_when_flashlight_off() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0
	# Flashlight starts off
	component.set_mock_time_msec(0)

	component.check_player_in_beam(Vector2(300, 0))

	assert_eq(component.blindness_applied.size(), 0,
		"Player should not be blinded when flashlight is off")


func test_player_not_blinded_again_within_cooldown() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0
	component._turn_on()
	component.set_mock_time_msec(0)

	# First blind
	component.check_player_in_beam(Vector2(300, 0))
	assert_eq(component.blindness_applied.size(), 1)

	# Second check within cooldown
	component.set_mock_time_msec(10000)  # 10 seconds
	component.check_player_in_beam(Vector2(300, 0))
	assert_eq(component.blindness_applied.size(), 1,
		"Player should not be blinded again within 20s cooldown")


func test_player_blinded_again_after_cooldown() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0
	component._turn_on()
	component.set_mock_time_msec(0)

	# First blind
	component.check_player_in_beam(Vector2(300, 0))
	assert_eq(component.blindness_applied.size(), 1)

	# After cooldown
	component.set_mock_time_msec(21000)  # 21 seconds
	component.check_player_in_beam(Vector2(300, 0))
	assert_eq(component.blindness_applied.size(), 2,
		"Player should be blinded again after 20s cooldown")


# ============================================================================
# Rotated Beam Tests
# ============================================================================


func test_beam_pointing_up_detects_player_above() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = -PI / 2  # Pointing up

	assert_true(component._is_player_in_beam(Vector2(0, -300)),
		"Player above should be detected when beam points up")
	assert_false(component._is_player_in_beam(Vector2(0, 300)),
		"Player below should not be detected when beam points up")


func test_beam_45_degrees() -> void:
	component.global_position = Vector2(0, 0)
	component.global_rotation = PI / 4  # Pointing bottom-right at 45 degrees

	var player_pos := Vector2(200, 200)  # Along diagonal
	assert_true(component._is_player_in_beam(player_pos),
		"Player on 45-degree diagonal should be detected")


# ============================================================================
# Integration Tests: Flash + Blind Sequence
# ============================================================================


func test_full_pre_attack_flash_sequence() -> void:
	component.set_mock_night_mode(true)
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0
	component._flash_target_duration = 0.3
	component.set_mock_time_msec(0)

	var attack_executed := false
	var attack_callback := func(): attack_executed = true

	# Start flash
	component.start_pre_attack_flash(Vector2(300, 0), attack_callback)
	assert_true(component.is_on(), "Flashlight should be on during flash")

	# Check player during flash (simulate player in beam)
	component.check_player_in_beam(Vector2(300, 0))
	assert_eq(component.blindness_applied.size(), 1,
		"Player should be blinded during pre-attack flash")

	# Complete flash
	component.process(0.35)
	assert_true(attack_executed, "Attack callback should be executed after flash")
	assert_false(component.is_on(), "Flashlight should be off after flash")


## Regression test: when flashlight is already running, a second shoot should not
## fire without the flashlight. The existing flash will fire the attack when done.
## (Issue #825 Bug Fix)
func test_second_shoot_while_flashing_does_not_fire_immediately() -> void:
	component.set_mock_night_mode(true)
	component._flash_target_duration = 0.3

	var shoot_count := 0
	var shoot_callback := func(): shoot_count += 1

	# First shoot starts the flash
	component.start_pre_attack_flash(Vector2(300, 0), shoot_callback)
	assert_true(component.is_flashing_for_attack(), "Should be flashing after first request")
	assert_eq(shoot_count, 0, "Should not have fired yet")

	# Second shoot during flash — should be ignored (not fire immediately)
	component.start_pre_attack_flash(Vector2(300, 0), shoot_callback)
	assert_eq(shoot_count, 0, "Second shoot during flash should not fire immediately")

	# Flash completes — first shoot fires
	component.process(0.35)
	assert_eq(shoot_count, 1, "First shoot fires when flash completes")
	assert_false(component.is_flashing_for_attack(), "Flash should be done")


func test_no_flash_when_night_mode_off_but_attack_still_happens() -> void:
	component.set_mock_night_mode(false)
	component.global_position = Vector2(0, 0)
	component.global_rotation = 0.0
	component.set_mock_time_msec(0)

	var attack_executed := false
	var attack_callback := func(): attack_executed = true

	component.start_pre_attack_flash(Vector2(300, 0), attack_callback)

	# Attack should happen immediately without flash
	assert_true(attack_executed, "Attack should happen immediately without flash")
	assert_false(component.is_on(), "Flashlight should not turn on")

	# Player should not be blinded since flashlight never turned on
	component.check_player_in_beam(Vector2(300, 0))
	assert_eq(component.blindness_applied.size(), 0,
		"Player should not be blinded when night mode is off")
