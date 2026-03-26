extends GutTest
## Unit tests for sniper enemy aim inertia (Issue #1530).
##
## The sniper's lead prediction should use an EMA-smoothed player velocity
## so that sudden direction reversals cause the sniper to aim behind the
## player's new position (i.e., miss), while steady movement is still
## tracked accurately.


const SniperComponent := preload("res://scripts/components/enemy_sniper_component.gd")


# ============================================================================
# Constants
# ============================================================================


func test_aim_inertia_alpha_constant_exists() -> void:
	assert_true("AIM_INERTIA_ALPHA" in SniperComponent,
		"EnemySniperComponent must define AIM_INERTIA_ALPHA constant [#1530]")


func test_aim_inertia_alpha_is_positive() -> void:
	assert_gt(SniperComponent.AIM_INERTIA_ALPHA, 0.0,
		"AIM_INERTIA_ALPHA must be positive [#1530]")


func test_aim_inertia_alpha_is_less_than_one() -> void:
	assert_lt(SniperComponent.AIM_INERTIA_ALPHA, 1.0,
		"AIM_INERTIA_ALPHA must be less than 1.0 [#1530]")


func test_aim_inertia_alpha_is_in_reasonable_range() -> void:
	# Practical range: [0.05, 0.25]. Values outside this range make inertia either
	# invisible (too high) or so heavy the sniper never hits (too low).
	assert_ge(SniperComponent.AIM_INERTIA_ALPHA, 0.05,
		"AIM_INERTIA_ALPHA >= 0.05 (otherwise inertia is so heavy the sniper never corrects) [#1530]")
	assert_le(SniperComponent.AIM_INERTIA_ALPHA, 0.25,
		"AIM_INERTIA_ALPHA <= 0.25 (otherwise inertia is too light to cause meaningful misses) [#1530]")


# ============================================================================
# Initial state of new variables
# ============================================================================


func test_smoothed_player_velocity_starts_at_zero() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)
	assert_eq(comp._smoothed_player_velocity, Vector2.ZERO,
		"_smoothed_player_velocity should start at Vector2.ZERO [#1530]")


func test_velocity_ema_initialised_starts_false() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)
	assert_false(comp._velocity_ema_initialised,
		"_velocity_ema_initialised should start false [#1530]")


func test_was_seeing_player_starts_false() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)
	assert_false(comp._was_seeing_player,
		"_was_seeing_player should start false [#1530]")


# ============================================================================
# _update_velocity_ema — cold start (first sample)
# ============================================================================


class MockCharacterBody2D extends CharacterBody2D:
	var velocity: Vector2 = Vector2.ZERO


func test_update_velocity_ema_seeds_on_first_call() -> void:
	# On the first call (uninitialised), the EMA should be seeded directly
	# to the current velocity without any smoothing, so there is no initial lag.
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	var player := MockCharacterBody2D.new()
	player.velocity = Vector2(300.0, 0.0)
	add_child_autofree(player)

	comp._update_velocity_ema(player, true)

	assert_eq(comp._smoothed_player_velocity, Vector2(300.0, 0.0),
		"First call should seed EMA directly to current velocity (no inertia delay) [#1530]")
	assert_true(comp._velocity_ema_initialised,
		"EMA should be marked as initialised after first call [#1530]")


func test_update_velocity_ema_handles_null_player() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)
	# Should not crash when player is null
	comp._update_velocity_ema(null, false)
	assert_eq(comp._smoothed_player_velocity, Vector2.ZERO,
		"EMA should remain Vector2.ZERO when player is null [#1530]")


# ============================================================================
# _update_velocity_ema — smoothing behaviour (steady movement)
# ============================================================================


func test_ema_approaches_steady_velocity_over_time() -> void:
	# After many frames of constant velocity, the EMA should converge close to it.
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	var player := MockCharacterBody2D.new()
	player.velocity = Vector2(200.0, 0.0)
	add_child_autofree(player)

	# Seed cold-start
	comp._update_velocity_ema(player, true)

	# 60 frames of the same velocity — EMA should be very close to 200, 0
	for _i in range(60):
		comp._update_velocity_ema(player, true)

	assert_almost_eq(comp._smoothed_player_velocity.x, 200.0, 2.0,
		"After 60 frames of steady velocity 200, EMA.x should be ~200 [#1530]")
	assert_almost_eq(comp._smoothed_player_velocity.y, 0.0, 2.0,
		"After 60 frames of steady velocity 200,0, EMA.y should be ~0 [#1530]")


func test_ema_lags_on_direction_reversal() -> void:
	# After many frames heading right (+X), a sudden reversal to left (-X) should
	# leave the EMA still pointing right for several frames.
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	var player := MockCharacterBody2D.new()
	player.velocity = Vector2(300.0, 0.0)
	add_child_autofree(player)

	# Establish EMA in the +X direction over 60 frames
	comp._update_velocity_ema(player, true)
	for _i in range(59):
		comp._update_velocity_ema(player, true)

	# Player reverses to -X
	player.velocity = Vector2(-300.0, 0.0)

	# Immediately after reversal, EMA should still be strongly in the +X direction
	comp._update_velocity_ema(player, true)
	assert_gt(comp._smoothed_player_velocity.x, 0.0,
		"EMA.x should still be positive immediately after direction reversal [#1530]")


func test_ema_eventually_corrects_after_reversal() -> void:
	# After a long time in the new direction, the EMA should eventually point that way too.
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	var player := MockCharacterBody2D.new()
	player.velocity = Vector2(300.0, 0.0)
	add_child_autofree(player)

	# Establish +X direction
	comp._update_velocity_ema(player, true)
	for _i in range(60):
		comp._update_velocity_ema(player, true)

	# Reverse to -X
	player.velocity = Vector2(-300.0, 0.0)

	# Run 120 more frames in the new direction — EMA should correct
	for _i in range(120):
		comp._update_velocity_ema(player, true)

	assert_lt(comp._smoothed_player_velocity.x, 0.0,
		"After 120 frames in -X direction, EMA.x should be negative (correction complete) [#1530]")


# ============================================================================
# _update_velocity_ema — re-acquisition reset
# ============================================================================


func test_ema_resets_on_player_reacquisition() -> void:
	# After losing and re-acquiring the player, the EMA should cold-start again
	# so stale pre-disappearance velocity doesn't corrupt the first shot.
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	var player := MockCharacterBody2D.new()
	player.velocity = Vector2(300.0, 0.0)
	add_child_autofree(player)

	# Establish EMA tracking player moving right
	comp._update_velocity_ema(player, true)
	for _i in range(30):
		comp._update_velocity_ema(player, true)

	# Lose sight (can_see_player = false for some frames)
	for _i in range(5):
		comp._update_velocity_ema(player, false)

	# Player now moving down at time of re-acquisition
	player.velocity = Vector2(0.0, 300.0)

	# Re-acquire (can_see_player transitions false → true)
	comp._update_velocity_ema(player, true)

	# EMA should be seeded to new velocity (no lag from old rightward velocity)
	assert_almost_eq(comp._smoothed_player_velocity.x, 0.0, 5.0,
		"EMA.x should reset on re-acquisition (player now moving down, not right) [#1530]")
	assert_almost_eq(comp._smoothed_player_velocity.y, 300.0, 5.0,
		"EMA.y should be seeded to current velocity on re-acquisition [#1530]")


func test_was_seeing_player_tracks_visibility() -> void:
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	var player := MockCharacterBody2D.new()
	add_child_autofree(player)

	comp._update_velocity_ema(player, true)
	assert_true(comp._was_seeing_player,
		"_was_seeing_player should be true after can_see_player=true [#1530]")

	comp._update_velocity_ema(player, false)
	assert_false(comp._was_seeing_player,
		"_was_seeing_player should be false after can_see_player=false [#1530]")


# ============================================================================
# Verify source code uses smoothed velocity for sniper lead prediction
# ============================================================================


func test_enemy_gd_uses_smoothed_velocity_for_sniper() -> void:
	# enemy.gd _calculate_lead_prediction must reference _sniper_component._smoothed_player_velocity
	# for sniper enemies rather than raw _player.velocity [#1530].
	var src := FileAccess.open("res://scripts/objects/enemy.gd", FileAccess.READ)
	assert_not_null(src, "enemy.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("_sniper_component._smoothed_player_velocity"),
		"enemy.gd _calculate_lead_prediction must reference _smoothed_player_velocity from sniper component [#1530]")
	# Also verify raw _player.velocity is no longer used alone for lead prediction in the sniper path
	assert_true(text.contains("_sniper_component != null"),
		"enemy.gd must guard sniper velocity with _sniper_component != null check [#1530]")


func test_sniper_component_defines_update_velocity_ema_method() -> void:
	# The EMA update method must exist on EnemySniperComponent [#1530].
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("func _update_velocity_ema"),
		"enemy_sniper_component.gd must define _update_velocity_ema() [#1530]")


func test_sniper_component_calls_ema_in_process_combat() -> void:
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("_update_velocity_ema(player, can_see_player)"),
		"process_combat must call _update_velocity_ema [#1530]")


func test_sniper_component_calls_ema_in_process_pursuing() -> void:
	var src := FileAccess.open("res://scripts/components/enemy_sniper_component.gd", FileAccess.READ)
	assert_not_null(src, "enemy_sniper_component.gd must be readable")
	if src == null:
		return
	var text := src.get_as_text()
	src.close()
	assert_true(text.contains("_update_velocity_ema(player, can_see_player)"),
		"process_pursuing must call _update_velocity_ema [#1530]")


# ============================================================================
# EMA formula correctness (single-step arithmetic)
# ============================================================================


func test_ema_formula_single_step() -> void:
	# After cold-start seeding to (100, 0), one frame of (0, 100) should give
	# smoothed = alpha*(0,100) + (1-alpha)*(100,0)
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	var player := MockCharacterBody2D.new()
	player.velocity = Vector2(100.0, 0.0)
	add_child_autofree(player)

	# Cold-start seed
	comp._update_velocity_ema(player, true)

	# One step with perpendicular velocity
	player.velocity = Vector2(0.0, 100.0)
	comp._update_velocity_ema(player, true)

	var alpha: float = SniperComponent.AIM_INERTIA_ALPHA
	var expected_x: float = alpha * 0.0 + (1.0 - alpha) * 100.0
	var expected_y: float = alpha * 100.0 + (1.0 - alpha) * 0.0

	assert_almost_eq(comp._smoothed_player_velocity.x, expected_x, 0.001,
		"EMA.x after one step: alpha*0 + (1-alpha)*100 [#1530]")
	assert_almost_eq(comp._smoothed_player_velocity.y, expected_y, 0.001,
		"EMA.y after one step: alpha*100 + (1-alpha)*0 [#1530]")


func test_ema_halves_error_in_expected_frames() -> void:
	# At alpha = AIM_INERTIA_ALPHA, the number of frames to halve the error is
	# roughly ceil(log(0.5) / log(1 - alpha)).  After that many frames, the EMA
	# should be more than halfway toward the new value.
	var comp := SniperComponent.new()
	add_child_autofree(comp)

	var player := MockCharacterBody2D.new()
	player.velocity = Vector2(200.0, 0.0)
	add_child_autofree(player)

	comp._update_velocity_ema(player, true)  # Seed to (200, 0)

	# Reverse to (-200, 0)
	player.velocity = Vector2(-200.0, 0.0)

	var alpha: float = SniperComponent.AIM_INERTIA_ALPHA
	var half_life_frames: int = ceili(log(0.5) / log(1.0 - alpha))

	for _i in range(half_life_frames):
		comp._update_velocity_ema(player, true)

	# After half-life frames, EMA should be between 0 and 200 (halfway toward -200)
	assert_lt(comp._smoothed_player_velocity.x, 200.0,
		"EMA should have moved below 200 after half-life frames [#1530]")
	assert_gt(comp._smoothed_player_velocity.x, -200.0,
		"EMA should not have fully corrected yet at half-life [#1530]")
