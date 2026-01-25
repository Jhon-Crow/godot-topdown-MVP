extends GutTest
## Unit tests for Player character.
##
## Tests the player movement calculations, ammo management, spread system,
## health system, and reload mechanics.


# ============================================================================
# Mock Player Class for Testing Logic
# ============================================================================


class MockPlayer:
	## Movement parameters
	var max_speed: float = 300.0
	var acceleration: float = 1200.0
	var friction: float = 1000.0

	## Ammo parameters
	var max_ammo: int = 90
	var _current_ammo: int = 90

	## Health parameters
	var max_health: int = 5
	var _current_health: int = 5
	var _is_alive: bool = true

	## Spread system constants
	const SPREAD_THRESHOLD: int = 3
	const INITIAL_SPREAD: float = 0.5
	const SPREAD_INCREMENT: float = 0.6
	const MAX_SPREAD: float = 4.0
	const SPREAD_RESET_TIME: float = 0.25

	## Spread tracking
	var _shot_count: int = 0
	var _shot_timer: float = 0.0

	## Reload tracking
	var _reload_sequence_step: int = 0
	var _is_reloading_sequence: bool = false
	var _is_reloading_simple: bool = false
	var reload_mode: int = 1  # 0 = Simple, 1 = Sequence

	## Screen shake parameters
	var screen_shake_intensity: float = 5.0
	var fire_rate: float = 10.0

	## Signals (simulated with callbacks)
	var on_ammo_changed: Callable
	var on_ammo_depleted: Callable
	var on_health_changed: Callable
	var on_died: Callable
	var on_reload_completed: Callable


	func get_current_spread() -> float:
		if _shot_count <= SPREAD_THRESHOLD:
			return INITIAL_SPREAD
		else:
			var extra_shots := _shot_count - SPREAD_THRESHOLD
			var spread := INITIAL_SPREAD + extra_shots * SPREAD_INCREMENT
			return minf(spread, MAX_SPREAD)


	func register_shot() -> void:
		if _current_ammo <= 0:
			if on_ammo_depleted:
				on_ammo_depleted.call()
			return

		_current_ammo -= 1
		_shot_count += 1
		_shot_timer = 0.0

		if on_ammo_changed:
			on_ammo_changed.call(_current_ammo, max_ammo)


	func update_spread_timer(delta: float) -> void:
		_shot_timer += delta
		if _shot_timer >= SPREAD_RESET_TIME:
			_shot_count = 0


	func get_current_ammo() -> int:
		return _current_ammo


	func get_max_ammo() -> int:
		return max_ammo


	func get_current_health() -> int:
		return _current_health


	func get_max_health() -> int:
		return max_health


	func get_health_percent() -> float:
		if max_health <= 0:
			return 0.0
		return float(_current_health) / float(max_health)


	func is_alive() -> bool:
		return _is_alive


	## Blood effect tracking for testing (Issue #350)
	var blood_effects_spawned: Array = []
	var on_blood_effect: Callable


	func on_hit() -> void:
		on_hit_with_info(Vector2.RIGHT, null)


	## Extended hit method with direction and caliber data.
	## This mirrors the real player's on_hit_with_info method.
	## @param hit_direction: Direction the bullet was traveling.
	## @param caliber_data: Caliber resource for effect scaling.
	func on_hit_with_info(hit_direction: Vector2, caliber_data: Resource) -> void:
		if not _is_alive:
			return

		_current_health -= 1

		if on_health_changed:
			on_health_changed.call(_current_health, max_health)

		# Track blood effect (mirrors ImpactEffectsManager.spawn_blood_effect call)
		var is_lethal := _current_health <= 0
		var blood_info := {
			"position": Vector2.ZERO,  # Would be global_position in real player
			"direction": hit_direction,
			"caliber_data": caliber_data,
			"is_lethal": is_lethal
		}
		blood_effects_spawned.append(blood_info)

		if on_blood_effect:
			on_blood_effect.call(blood_info)

		if _current_health <= 0:
			_is_alive = false
			if on_died:
				on_died.call()


	func is_reloading() -> bool:
		return _is_reloading_sequence or _is_reloading_simple


	func get_reload_step() -> int:
		return _reload_sequence_step


	func start_sequence_reload() -> void:
		if _current_ammo >= max_ammo or _is_reloading_sequence:
			return
		_reload_sequence_step = 1
		_is_reloading_sequence = true


	func advance_sequence_reload() -> void:
		if not _is_reloading_sequence:
			return
		match _reload_sequence_step:
			1:
				_reload_sequence_step = 2
			2:
				_complete_sequence_reload()


	func _complete_sequence_reload() -> void:
		_current_ammo = max_ammo
		_reload_sequence_step = 0
		_is_reloading_sequence = false
		if on_reload_completed:
			on_reload_completed.call()
		if on_ammo_changed:
			on_ammo_changed.call(_current_ammo, max_ammo)


	func cancel_reload() -> void:
		_reload_sequence_step = 0
		_is_reloading_sequence = false
		_is_reloading_simple = false


	func calculate_shake_intensity() -> float:
		if fire_rate > 0.0:
			return screen_shake_intensity / fire_rate * 10.0
		return screen_shake_intensity


	func calculate_movement(current_velocity: Vector2, input_direction: Vector2, delta: float) -> Vector2:
		if input_direction != Vector2.ZERO:
			return current_velocity.move_toward(input_direction * max_speed, acceleration * delta)
		else:
			return current_velocity.move_toward(Vector2.ZERO, friction * delta)


	func normalize_input(input: Vector2) -> Vector2:
		if input.length() > 1.0:
			return input.normalized()
		return input


var player: MockPlayer


func before_each() -> void:
	player = MockPlayer.new()


func after_each() -> void:
	player = null


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_ammo_equals_max() -> void:
	assert_eq(player.get_current_ammo(), player.max_ammo,
		"Initial ammo should equal max ammo")


func test_initial_health_equals_max() -> void:
	assert_eq(player.get_current_health(), player.max_health,
		"Initial health should equal max health")


func test_player_starts_alive() -> void:
	assert_true(player.is_alive(), "Player should start alive")


func test_initial_reload_step_is_zero() -> void:
	assert_eq(player.get_reload_step(), 0, "Initial reload step should be 0")


func test_initial_not_reloading() -> void:
	assert_false(player.is_reloading(), "Player should not be reloading initially")


# ============================================================================
# Spread System Tests
# ============================================================================


func test_initial_spread_is_minimal() -> void:
	assert_eq(player.get_current_spread(), MockPlayer.INITIAL_SPREAD,
		"Initial spread should be minimal (0.5 degrees)")


func test_spread_stays_minimal_within_threshold() -> void:
	# Fire up to threshold shots
	for i in range(MockPlayer.SPREAD_THRESHOLD):
		player.register_shot()

	assert_eq(player.get_current_spread(), MockPlayer.INITIAL_SPREAD,
		"Spread should stay minimal within threshold")


func test_spread_increases_after_threshold() -> void:
	# Fire beyond threshold
	for i in range(MockPlayer.SPREAD_THRESHOLD + 1):
		player.register_shot()

	var expected := MockPlayer.INITIAL_SPREAD + MockPlayer.SPREAD_INCREMENT
	assert_almost_eq(player.get_current_spread(), expected, 0.001,
		"Spread should increase after threshold")


func test_spread_maxes_out() -> void:
	# Fire many shots
	for i in range(20):
		player.register_shot()

	assert_eq(player.get_current_spread(), MockPlayer.MAX_SPREAD,
		"Spread should not exceed maximum (4.0 degrees)")


func test_spread_resets_after_delay() -> void:
	# Fire some shots
	for i in range(5):
		player.register_shot()

	# Wait for reset time
	player.update_spread_timer(MockPlayer.SPREAD_RESET_TIME + 0.1)

	assert_eq(player.get_current_spread(), MockPlayer.INITIAL_SPREAD,
		"Spread should reset after delay")


func test_spread_increment_calculation() -> void:
	# After threshold, each shot adds SPREAD_INCREMENT
	player._shot_count = MockPlayer.SPREAD_THRESHOLD + 2

	var expected := MockPlayer.INITIAL_SPREAD + 2 * MockPlayer.SPREAD_INCREMENT
	assert_almost_eq(player.get_current_spread(), expected, 0.001,
		"Spread should increase by INCREMENT per shot after threshold")


# ============================================================================
# Ammo Tests
# ============================================================================


func test_shoot_decreases_ammo() -> void:
	var initial := player.get_current_ammo()
	player.register_shot()

	assert_eq(player.get_current_ammo(), initial - 1, "Shooting should decrease ammo by 1")


func test_cannot_shoot_with_zero_ammo() -> void:
	player._current_ammo = 0
	var depleted_called := false
	player.on_ammo_depleted = func(): depleted_called = true

	player.register_shot()

	assert_eq(player.get_current_ammo(), 0, "Ammo should stay at 0")
	assert_true(depleted_called, "Ammo depleted callback should be called")


func test_ammo_changed_callback_called() -> void:
	var callback_called := false
	var received_current := -1
	var received_max := -1
	player.on_ammo_changed = func(c, m):
		callback_called = true
		received_current = c
		received_max = m

	player.register_shot()

	assert_true(callback_called, "Ammo changed callback should be called")
	assert_eq(received_current, 89, "Current ammo should be 89")
	assert_eq(received_max, 90, "Max ammo should be 90")


# ============================================================================
# Health Tests
# ============================================================================


func test_hit_decreases_health() -> void:
	var initial := player.get_current_health()
	player.on_hit()

	assert_eq(player.get_current_health(), initial - 1, "Hit should decrease health by 1")


func test_player_dies_at_zero_health() -> void:
	player._current_health = 1
	player.on_hit()

	assert_false(player.is_alive(), "Player should die when health reaches 0")


func test_died_callback_called() -> void:
	var died_called := false
	player.on_died = func(): died_called = true

	# Kill the player
	for i in range(player.max_health):
		player.on_hit()

	assert_true(died_called, "Died callback should be called")


func test_cannot_hit_dead_player() -> void:
	player._is_alive = false
	var initial_health := player.get_current_health()

	player.on_hit()

	assert_eq(player.get_current_health(), initial_health,
		"Dead player should not take more damage")


func test_health_percent_full() -> void:
	assert_eq(player.get_health_percent(), 1.0, "Full health should be 100%")


func test_health_percent_half() -> void:
	player._current_health = player.max_health / 2
	# 5/2 = 2 (integer division), 2/5 = 0.4
	var expected := float(player.max_health / 2) / float(player.max_health)

	assert_almost_eq(player.get_health_percent(), expected, 0.001,
		"Half health should be ~40-50%")


func test_health_percent_zero() -> void:
	player._current_health = 0
	assert_eq(player.get_health_percent(), 0.0, "Zero health should be 0%")


# ============================================================================
# Reload Sequence Tests
# ============================================================================


func test_start_reload_sets_step_to_1() -> void:
	player._current_ammo = 50  # Less than max
	player.start_sequence_reload()

	assert_eq(player.get_reload_step(), 1, "Starting reload should set step to 1")
	assert_true(player.is_reloading(), "Player should be reloading")


func test_cannot_start_reload_at_max_ammo() -> void:
	player._current_ammo = player.max_ammo
	player.start_sequence_reload()

	assert_eq(player.get_reload_step(), 0, "Should not start reload at max ammo")
	assert_false(player.is_reloading(), "Should not be reloading")


func test_advance_reload_step_1_to_2() -> void:
	player._current_ammo = 50
	player.start_sequence_reload()
	player.advance_sequence_reload()

	assert_eq(player.get_reload_step(), 2, "Should advance from step 1 to 2")


func test_advance_reload_step_2_completes() -> void:
	player._current_ammo = 50
	player.start_sequence_reload()
	player.advance_sequence_reload()  # 1 -> 2
	player.advance_sequence_reload()  # 2 -> complete

	assert_eq(player.get_current_ammo(), player.max_ammo, "Reload should refill ammo")
	assert_eq(player.get_reload_step(), 0, "Step should reset to 0")
	assert_false(player.is_reloading(), "Should not be reloading after completion")


func test_reload_completed_callback_called() -> void:
	var completed := false
	player.on_reload_completed = func(): completed = true

	player._current_ammo = 50
	player.start_sequence_reload()
	player.advance_sequence_reload()
	player.advance_sequence_reload()

	assert_true(completed, "Reload completed callback should be called")


func test_cancel_reload_resets_state() -> void:
	player._current_ammo = 50
	player.start_sequence_reload()
	player.cancel_reload()

	assert_eq(player.get_reload_step(), 0, "Cancel should reset reload step")
	assert_false(player.is_reloading(), "Should not be reloading after cancel")


# ============================================================================
# Screen Shake Tests
# ============================================================================


func test_shake_intensity_calculation() -> void:
	# intensity / fire_rate * 10 = 5 / 10 * 10 = 5
	var expected := 5.0
	assert_eq(player.calculate_shake_intensity(), expected,
		"Shake intensity should be calculated correctly")


func test_shake_intensity_with_different_fire_rate() -> void:
	player.fire_rate = 5.0
	# 5 / 5 * 10 = 10
	var expected := 10.0
	assert_eq(player.calculate_shake_intensity(), expected,
		"Lower fire rate should increase shake per shot")


func test_shake_intensity_zero_fire_rate() -> void:
	player.fire_rate = 0.0
	# Should return base intensity when fire_rate is 0
	assert_eq(player.calculate_shake_intensity(), player.screen_shake_intensity,
		"Zero fire rate should return base intensity")


# ============================================================================
# Movement Tests
# ============================================================================


func test_movement_accelerates_towards_input() -> void:
	var current := Vector2.ZERO
	var input := Vector2(1, 0)  # Right
	var delta := 0.016  # ~60fps

	var result := player.calculate_movement(current, input, delta)

	assert_true(result.x > 0, "Should accelerate right")


func test_movement_decelerates_with_no_input() -> void:
	var current := Vector2(100, 0)  # Moving right
	var input := Vector2.ZERO
	var delta := 0.016

	var result := player.calculate_movement(current, input, delta)

	assert_true(result.x < 100, "Should decelerate when no input")


func test_input_normalization_diagonal() -> void:
	var input := Vector2(1, 1)  # Diagonal input
	var result := player.normalize_input(input)

	assert_almost_eq(result.length(), 1.0, 0.001,
		"Diagonal input should be normalized to length 1")


func test_input_normalization_small_values() -> void:
	var input := Vector2(0.5, 0)  # Small input
	var result := player.normalize_input(input)

	assert_eq(result, input, "Small inputs should not be normalized")


# ============================================================================
# Difficulty Integration Tests
# ============================================================================


func test_max_ammo_can_be_changed() -> void:
	player.max_ammo = 60  # Hard mode
	player._current_ammo = 60

	assert_eq(player.get_max_ammo(), 60, "Max ammo should update for difficulty")


# ============================================================================
# Blood Effect Tests (Issue #350)
# These tests verify blood effect spawning behavior that matches the
# C# Player implementation in Scripts/Characters/Player.cs.
# The C# Player now has on_hit_with_info() method that spawns blood effects
# via ImpactEffectsManager.spawn_blood_effect().
# ============================================================================


func test_blood_effect_spawned_on_non_lethal_hit() -> void:
	player._current_health = 5  # Full health
	player.on_hit_with_info(Vector2.RIGHT, null)

	assert_eq(player.blood_effects_spawned.size(), 1,
		"Blood effect should be spawned on non-lethal hit")

	var effect = player.blood_effects_spawned[0]
	assert_false(effect.is_lethal, "Non-lethal hit should have is_lethal=false")


func test_blood_effect_spawned_on_lethal_hit() -> void:
	player._current_health = 1  # One hit from death
	player.on_hit_with_info(Vector2.LEFT, null)

	assert_eq(player.blood_effects_spawned.size(), 1,
		"Blood effect should be spawned on lethal hit")

	var effect = player.blood_effects_spawned[0]
	assert_true(effect.is_lethal, "Lethal hit should have is_lethal=true")


func test_blood_effect_direction_matches_hit_direction() -> void:
	var hit_dir := Vector2(0.5, -0.5).normalized()
	player.on_hit_with_info(hit_dir, null)

	var effect = player.blood_effects_spawned[0]
	assert_eq(effect.direction, hit_dir, "Blood effect direction should match hit direction")


func test_blood_effect_callback_called() -> void:
	var callback_called := false
	var received_info = null
	player.on_blood_effect = func(info):
		callback_called = true
		received_info = info

	player.on_hit_with_info(Vector2.DOWN, null)

	assert_true(callback_called, "Blood effect callback should be called on hit")
	assert_not_null(received_info, "Blood effect info should be passed to callback")


func test_multiple_hits_spawn_multiple_blood_effects() -> void:
	player._current_health = 5

	# Take 3 non-lethal hits
	for i in range(3):
		player.on_hit_with_info(Vector2.RIGHT, null)

	assert_eq(player.blood_effects_spawned.size(), 3,
		"Each hit should spawn a blood effect")

	# Verify first 2 are non-lethal, last one is lethal (5-3=2 health left, then dead)
	# Wait, health goes 5->4->3->2, so none are lethal
	for i in range(3):
		assert_false(player.blood_effects_spawned[i].is_lethal,
			"Non-lethal hits should have is_lethal=false")


func test_blood_effect_with_caliber_data() -> void:
	# Create a mock caliber data object
	var caliber = RefCounted.new()
	caliber.set_meta("effect_scale", 1.5)

	player.on_hit_with_info(Vector2.UP, caliber)

	var effect = player.blood_effects_spawned[0]
	assert_eq(effect.caliber_data, caliber, "Blood effect should include caliber data")


func test_no_blood_effect_on_dead_player() -> void:
	player._is_alive = false
	player.on_hit_with_info(Vector2.RIGHT, null)

	assert_eq(player.blood_effects_spawned.size(), 0,
		"Dead player should not spawn blood effects")
