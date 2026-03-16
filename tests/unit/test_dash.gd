extends GutTest
## Unit tests for the Dash active item (Issue #1071).
##
## Tests the dash ability: mechanics, invincibility, cooldown, and integration
## with the ActiveItemManager. Uses mock objects to avoid needing a full scene.


# ============================================================================
# Mock classes
# ============================================================================


class MockDashController:
	## Dash speed in pixels per second.
	const DASH_SPEED: float = 900.0

	## Duration of the dash in seconds.
	const DASH_DURATION: float = 0.12

	## Cooldown between dashes in seconds.
	const DASH_COOLDOWN: float = 1.2

	## Whether dash is equipped.
	var dash_equipped: bool = false

	## Whether a dash is currently in progress.
	var dash_active: bool = false

	## Time remaining in the current dash.
	var dash_timer: float = 0.0

	## Cooldown remaining before next dash.
	var dash_cooldown_timer: float = 0.0

	## Direction of the current dash.
	var dash_direction: Vector2 = Vector2.ZERO

	## Signal tracking
	var dash_started_count: int = 0
	var dash_ended_count: int = 0

	## Start a dash in the given direction.
	func start_dash(direction: Vector2) -> bool:
		if not dash_equipped:
			return false
		if dash_active or dash_cooldown_timer > 0.0:
			return false
		if direction.length_squared() > 0.01:
			dash_direction = direction.normalized()
		else:
			dash_direction = Vector2.RIGHT
		dash_active = true
		dash_timer = DASH_DURATION
		dash_started_count += 1
		return true

	## Update dash state by one delta tick.
	func update(delta: float) -> void:
		if not dash_equipped:
			return

		if dash_active:
			dash_timer -= delta
			if dash_timer <= 0.0:
				dash_active = false
				dash_timer = 0.0
				dash_cooldown_timer = DASH_COOLDOWN
				dash_ended_count += 1
			return

		if dash_cooldown_timer > 0.0:
			dash_cooldown_timer -= delta
			if dash_cooldown_timer < 0.0:
				dash_cooldown_timer = 0.0

	## Returns true while a dash is in progress.
	func is_dashing() -> bool:
		return dash_active

	## Returns true when dash is ready (not dashing, not on cooldown).
	func is_ready() -> bool:
		return dash_equipped and not dash_active and dash_cooldown_timer <= 0.0


class MockPlayer:
	## Current health.
	var current_health: int = 5

	## Whether player is alive.
	var is_alive: bool = true

	## Dash controller.
	var dash: MockDashController = MockDashController.new()

	## Invincibility enabled (F6 toggle).
	var invincibility_enabled: bool = false

	## Hit counter for testing.
	var hit_count: int = 0

	## Simulate receiving a hit — respects dash invincibility and F6 mode.
	func on_hit_with_info(_direction: Vector2, _caliber) -> void:
		if not is_alive:
			return
		if invincibility_enabled:
			return
		# Dash invincibility (Issue #1071)
		if dash.is_dashing():
			return
		current_health -= 1
		hit_count += 1
		if current_health <= 0:
			is_alive = false


var controller: MockDashController
var player: MockPlayer


func before_each() -> void:
	controller = MockDashController.new()
	player = MockPlayer.new()
	player.dash = MockDashController.new()


func after_each() -> void:
	controller = null
	player = null


# ============================================================================
# Dash Constants Tests
# ============================================================================


func test_dash_speed_is_three_times_max_speed() -> void:
	# max_speed = 300, dash speed = 3x = 900
	assert_eq(controller.DASH_SPEED, 900.0,
		"Dash speed should be 900 px/s (3x normal max_speed of 300)")


func test_dash_duration_is_short() -> void:
	assert_true(controller.DASH_DURATION > 0.0 and controller.DASH_DURATION < 0.5,
		"Dash duration should be a short burst (0.0 < duration < 0.5s)")


func test_dash_cooldown_matches_spec() -> void:
	# Issue #1071 specifies 1.2 seconds cooldown
	assert_eq(controller.DASH_COOLDOWN, 1.2,
		"Dash cooldown must be 1.2 seconds per issue #1071 spec")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_dash_not_active_by_default() -> void:
	assert_false(controller.dash_active,
		"Dash should not be active by default")


func test_dash_not_equipped_by_default() -> void:
	assert_false(controller.dash_equipped,
		"Dash should not be equipped by default")


func test_dash_timer_is_zero_by_default() -> void:
	assert_eq(controller.dash_timer, 0.0,
		"Dash timer should be 0 by default")


func test_dash_cooldown_timer_is_zero_by_default() -> void:
	assert_eq(controller.dash_cooldown_timer, 0.0,
		"Dash cooldown timer should be 0 by default")


func test_dash_direction_is_zero_by_default() -> void:
	assert_eq(controller.dash_direction, Vector2.ZERO,
		"Dash direction should be zero by default")


# ============================================================================
# Activation Tests
# ============================================================================


func test_dash_cannot_start_when_not_equipped() -> void:
	controller.dash_equipped = false
	var result := controller.start_dash(Vector2.RIGHT)
	assert_false(result, "Dash should not start when not equipped")
	assert_false(controller.dash_active, "Dash should remain inactive")


func test_dash_starts_when_equipped() -> void:
	controller.dash_equipped = true
	var result := controller.start_dash(Vector2.RIGHT)
	assert_true(result, "Dash should start when equipped")
	assert_true(controller.dash_active, "Dash should be active after start")


func test_dash_sets_direction_to_input() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2(1.0, 0.0))
	assert_eq(controller.dash_direction, Vector2(1.0, 0.0),
		"Dash direction should match input direction")


func test_dash_normalizes_diagonal_direction() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2(3.0, 4.0))  # Not normalized
	var len := controller.dash_direction.length()
	assert_almost_eq(len, 1.0, 0.001,
		"Dash direction should be normalized")


func test_dash_defaults_to_right_when_no_input() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.ZERO)
	assert_eq(controller.dash_direction, Vector2.RIGHT,
		"Dash should default to right direction when no input")


func test_dash_starts_timer() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)
	assert_eq(controller.dash_timer, controller.DASH_DURATION,
		"Dash timer should be set to DASH_DURATION on start")


func test_dash_emits_started_signal() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)
	assert_eq(controller.dash_started_count, 1,
		"Dash started signal should be emitted once")


# ============================================================================
# Duration / Timer Tests
# ============================================================================


func test_dash_ends_after_duration() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)
	assert_true(controller.dash_active, "Dash should be active at start")

	# Advance by exactly DASH_DURATION
	controller.update(controller.DASH_DURATION)
	assert_false(controller.dash_active, "Dash should end after DASH_DURATION")


func test_dash_still_active_before_duration_ends() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)

	# Advance by half of dash duration
	controller.update(controller.DASH_DURATION * 0.5)
	assert_true(controller.dash_active, "Dash should still be active before duration ends")


func test_dash_emits_ended_signal_when_complete() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)
	controller.update(controller.DASH_DURATION)
	assert_eq(controller.dash_ended_count, 1,
		"Dash ended signal should be emitted when dash completes")


# ============================================================================
# Cooldown Tests
# ============================================================================


func test_cooldown_starts_after_dash_ends() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)
	controller.update(controller.DASH_DURATION)  # End the dash
	assert_eq(controller.dash_cooldown_timer, controller.DASH_COOLDOWN,
		"Cooldown should start immediately after dash ends")


func test_dash_cannot_start_during_cooldown() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)
	controller.update(controller.DASH_DURATION)  # End dash, start cooldown

	# Try to dash again — should fail
	var result := controller.start_dash(Vector2.RIGHT)
	assert_false(result, "Dash should not start during cooldown")


func test_dash_ready_after_cooldown_expires() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)
	controller.update(controller.DASH_DURATION)  # End dash, start cooldown

	# Advance past full cooldown
	controller.update(controller.DASH_COOLDOWN + 0.1)
	assert_true(controller.is_ready(),
		"Dash should be ready after cooldown expires")


func test_dash_cannot_start_again_during_active_dash() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)

	# Try to dash again while still dashing
	var result := controller.start_dash(Vector2.UP)
	assert_false(result, "Dash should not start while already dashing")


func test_cooldown_timer_decreases_over_time() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)
	controller.update(controller.DASH_DURATION)  # End dash, start cooldown

	var initial_cooldown := controller.dash_cooldown_timer
	controller.update(0.5)
	assert_true(controller.dash_cooldown_timer < initial_cooldown,
		"Cooldown timer should decrease over time")


func test_unlimited_uses_after_each_cooldown() -> void:
	controller.dash_equipped = true

	# Do three dashes with full cooldown between them
	for i in range(3):
		assert_true(controller.is_ready(), "Dash should be ready before dash %d" % (i + 1))
		controller.start_dash(Vector2.RIGHT)
		controller.update(controller.DASH_DURATION)
		controller.update(controller.DASH_COOLDOWN)

	# Should still be ready (unlimited uses)
	assert_true(controller.is_ready(),
		"Dash should be ready again after 3 dashes — unlimited uses (Issue #1071)")


# ============================================================================
# Invincibility Tests (Issue #1071 Requirement)
# ============================================================================


func test_player_takes_damage_normally_when_not_dashing() -> void:
	player.dash.dash_equipped = true
	var initial_health := player.current_health

	player.on_hit_with_info(Vector2.RIGHT, null)
	assert_eq(player.current_health, initial_health - 1,
		"Player should take damage when not dashing")


func test_player_invincible_during_dash() -> void:
	player.dash.dash_equipped = true
	player.dash.start_dash(Vector2.RIGHT)
	assert_true(player.dash.is_dashing(), "Player should be dashing")

	var initial_health := player.current_health
	player.on_hit_with_info(Vector2.RIGHT, null)
	assert_eq(player.current_health, initial_health,
		"Player should be invincible during dash — no damage taken (Issue #1071)")


func test_player_invincible_throughout_dash_duration() -> void:
	player.dash.dash_equipped = true
	player.dash.start_dash(Vector2.RIGHT)

	var initial_health := player.current_health

	# Simulate multiple hits throughout the dash
	var mid_dash := player.dash.DASH_DURATION * 0.5
	player.dash.update(mid_dash)
	player.on_hit_with_info(Vector2.UP, null)
	player.on_hit_with_info(Vector2.LEFT, null)
	player.on_hit_with_info(Vector2.DOWN, null)

	assert_eq(player.current_health, initial_health,
		"Player should be invincible throughout the dash (all hits blocked)")


func test_player_vulnerable_after_dash_ends() -> void:
	player.dash.dash_equipped = true
	player.dash.start_dash(Vector2.RIGHT)

	# Let dash expire
	player.dash.update(player.dash.DASH_DURATION)
	assert_false(player.dash.is_dashing(), "Dash should have ended")

	var health_after_dash := player.current_health
	player.on_hit_with_info(Vector2.RIGHT, null)
	assert_eq(player.current_health, health_after_dash - 1,
		"Player should be vulnerable again after dash ends")


func test_dash_invincibility_does_not_affect_normal_play() -> void:
	# Without dash equipped, hits always apply
	player.dash.dash_equipped = false
	var initial_health := player.current_health

	player.on_hit_with_info(Vector2.RIGHT, null)
	assert_eq(player.current_health, initial_health - 1,
		"Without dash, hits should apply normally")


# ============================================================================
# ActiveItemManager Integration Tests
# ============================================================================


class MockActiveItemManagerWithDash:
	const ActiveItemType := {
		NONE = 0,
		FLASHLIGHT = 1,
		HOMING_BULLETS = 2,
		TELEPORT_BRACERS = 3,
		BFF_PENDANT = 4,
		INVISIBILITY_SUIT = 5,
		BREAKER_BULLETS = 6,
		FORCE_FIELD = 7,
		TRAJECTORY_GLASSES = 8,
		LASER_SIGHT = 9,
		DASH = 10
	}

	var current_active_item: int = ActiveItemType.NONE

	func has_dash() -> bool:
		return current_active_item == ActiveItemType.DASH

	func set_active_item(type: int) -> void:
		current_active_item = type


var aim: MockActiveItemManagerWithDash


func before_each_aim() -> void:
	aim = MockActiveItemManagerWithDash.new()


func test_dash_enum_value_is_10() -> void:
	assert_eq(
		MockActiveItemManagerWithDash.ActiveItemType.DASH, 10,
		"DASH should be enum value 10 (after LASER_SIGHT at 9)"
	)


func test_has_dash_false_by_default() -> void:
	var m := MockActiveItemManagerWithDash.new()
	assert_false(m.has_dash(),
		"has_dash should return false when NONE is selected")


func test_has_dash_true_after_selection() -> void:
	var m := MockActiveItemManagerWithDash.new()
	m.set_active_item(10)
	assert_true(m.has_dash(),
		"has_dash should return true after selecting DASH")


func test_dash_mutually_exclusive_with_flashlight() -> void:
	var m := MockActiveItemManagerWithDash.new()
	m.set_active_item(10)  # DASH
	assert_true(m.has_dash(), "DASH should be selected")
	assert_false(m.current_active_item == 1, "FLASHLIGHT should NOT be selected")


func test_dash_mutually_exclusive_with_force_field() -> void:
	var m := MockActiveItemManagerWithDash.new()
	m.set_active_item(10)  # DASH
	assert_true(m.has_dash(), "DASH should be selected")
	assert_false(m.current_active_item == 7, "FORCE_FIELD should NOT be selected")


func test_no_dash_after_deselection() -> void:
	var m := MockActiveItemManagerWithDash.new()
	m.set_active_item(10)
	m.set_active_item(0)  # Back to NONE
	assert_false(m.has_dash(),
		"has_dash should return false after switching back to NONE")


# ============================================================================
# Progress Bar Display Tests (cooldown visualization)
# ============================================================================


class MockProgressBar:
	var mode: int = -1
	var current: float = 0.0
	var maximum: float = 0.0
	var visible: bool = false

	func show_bar(m: int, c: float, mx: float) -> void:
		mode = m
		current = c
		maximum = mx
		visible = true

	func hide_bar() -> void:
		visible = false


func test_cooldown_bar_shown_after_dash_ends() -> void:
	var bar := MockProgressBar.new()
	var ctrl := MockDashController.new()
	ctrl.dash_equipped = true
	ctrl.start_dash(Vector2.RIGHT)

	# End dash — cooldown starts
	ctrl.update(ctrl.DASH_DURATION)
	assert_true(ctrl.dash_cooldown_timer > 0.0, "Cooldown should be running")

	# Simulate bar update call: current = elapsed, max = DASH_COOLDOWN
	var elapsed := ctrl.DASH_COOLDOWN - ctrl.dash_cooldown_timer
	bar.show_bar(1, elapsed, ctrl.DASH_COOLDOWN)  # mode 1 = CONTINUOUS

	assert_true(bar.visible, "Cooldown bar should be visible")
	assert_eq(bar.maximum, ctrl.DASH_COOLDOWN,
		"Bar maximum should equal DASH_COOLDOWN")
	assert_true(bar.current >= 0.0 and bar.current <= ctrl.DASH_COOLDOWN,
		"Bar current should be within [0, DASH_COOLDOWN]")


func test_cooldown_bar_fills_as_cooldown_depletes() -> void:
	var ctrl := MockDashController.new()
	ctrl.dash_equipped = true
	ctrl.start_dash(Vector2.RIGHT)
	ctrl.update(ctrl.DASH_DURATION)  # End dash

	# Just after dash ends: cooldown is full, elapsed = 0
	var elapsed_start := ctrl.DASH_COOLDOWN - ctrl.dash_cooldown_timer
	assert_almost_eq(elapsed_start, 0.0, 0.01,
		"Elapsed should be ~0 right after dash ends (bar empty = not ready)")

	# Half way through cooldown
	ctrl.update(ctrl.DASH_COOLDOWN * 0.5)
	var elapsed_mid := ctrl.DASH_COOLDOWN - ctrl.dash_cooldown_timer
	assert_true(elapsed_mid > elapsed_start,
		"Elapsed time (bar fill) should increase as cooldown depletes")


func test_cooldown_bar_full_when_ready() -> void:
	var ctrl := MockDashController.new()
	ctrl.dash_equipped = true
	ctrl.start_dash(Vector2.RIGHT)
	ctrl.update(ctrl.DASH_DURATION)  # End dash, start cooldown
	ctrl.update(ctrl.DASH_COOLDOWN)  # Complete cooldown

	assert_eq(ctrl.dash_cooldown_timer, 0.0,
		"Cooldown timer should be 0 when ready")
	# When timer = 0, elapsed = DASH_COOLDOWN → bar is full
	var elapsed := ctrl.DASH_COOLDOWN - ctrl.dash_cooldown_timer
	assert_eq(elapsed, ctrl.DASH_COOLDOWN,
		"Bar should be full (elapsed = max) when dash is ready")


# ============================================================================
# Edge Case Tests
# ============================================================================


func test_dash_direction_preserved_during_dash() -> void:
	controller.dash_equipped = true
	var dir := Vector2(0.6, 0.8)  # 3-4-5 triangle, normalized
	controller.start_dash(dir)

	# Even after a partial update, direction should be unchanged
	controller.update(controller.DASH_DURATION * 0.5)
	assert_eq(controller.dash_direction, dir.normalized(),
		"Dash direction should not change mid-dash")


func test_multiple_damage_sources_blocked_during_dash() -> void:
	player.dash.dash_equipped = true
	player.dash.start_dash(Vector2.RIGHT)

	var initial_health := player.current_health

	# Simulate grenade + bullet + shrapnel simultaneously
	player.on_hit_with_info(Vector2.RIGHT, null)   # bullet
	player.on_hit_with_info(Vector2.LEFT, null)    # shrapnel
	player.on_hit_with_info(Vector2.UP, null)      # explosion
	player.on_hit_with_info(Vector2.DOWN, null)    # another bullet

	assert_eq(player.current_health, initial_health,
		"All damage sources should be blocked during dash (Issue #1071)")
	assert_eq(player.hit_count, 0, "Hit count should remain 0 during dash")


func test_is_ready_true_initially_when_equipped() -> void:
	controller.dash_equipped = true
	assert_true(controller.is_ready(),
		"Dash should be ready immediately when equipped (no charges needed)")


func test_is_ready_false_when_not_equipped() -> void:
	controller.dash_equipped = false
	assert_false(controller.is_ready(),
		"Dash is not ready when not equipped")


func test_is_ready_false_while_dashing() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)
	assert_false(controller.is_ready(),
		"Dash is not ready while actively dashing")


func test_is_ready_false_during_cooldown() -> void:
	controller.dash_equipped = true
	controller.start_dash(Vector2.RIGHT)
	controller.update(controller.DASH_DURATION)  # End dash, start cooldown
	assert_false(controller.is_ready(),
		"Dash is not ready during cooldown")
