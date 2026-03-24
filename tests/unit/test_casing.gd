extends GutTest
## Unit tests for casing.gd bullet casing physics and appearance.
##
## Tests auto-land timing, spawn collision delay, freeze/unfreeze
## velocity preservation, impulse queueing, landing state transitions,
## and caliber-based appearance color selection.


# ============================================================================
# Mock CaliberData for Appearance Tests
# ============================================================================


class MockCaliberData:
	var caliber_name: String = ""
	var casing_sprite = null
	var effect_scale: float = 1.0


# ============================================================================
# Mock Casing for Logic Tests
# ============================================================================


class MockCasing:
	## Constants matching casing.gd.
	const AUTO_LAND_TIME: float = 2.0
	const SPAWN_COLLISION_DELAY: float = 0.1

	## Current velocities.
	var linear_velocity: Vector2 = Vector2.ZERO
	var angular_velocity: float = 0.0

	## Frozen state.
	var _is_time_frozen: bool = false
	var _frozen_linear_velocity: Vector2 = Vector2.ZERO
	var _frozen_angular_velocity: float = 0.0

	## Pending kick impulse during freeze.
	var _pending_kick_impulse: Vector2 = Vector2.ZERO

	## Landing state.
	var _has_landed: bool = false
	var _auto_land_timer: float = 0.0

	## Spawn collision delay.
	var _spawn_timer: float = 0.0
	var _spawn_collision_enabled: bool = false

	## Applied impulses for tracking.
	var _applied_impulses: Array[Vector2] = []

	## Physics process enabled flag.
	var _physics_process_enabled: bool = true

	## Caliber data for appearance.
	var caliber_data = null

	## Current casing color.
	var casing_color: Color = Color(0.9, 0.8, 0.4)  # Default brass

	## Simulate physics process.
	func physics_process(delta: float) -> void:
		if _is_time_frozen:
			linear_velocity = Vector2.ZERO
			angular_velocity = 0.0
			return

		if not _spawn_collision_enabled:
			_spawn_timer += delta
			if _spawn_timer >= SPAWN_COLLISION_DELAY:
				_spawn_collision_enabled = true

		if not _has_landed:
			_auto_land_timer += delta
			if _auto_land_timer >= AUTO_LAND_TIME:
				_land()

		if _has_landed:
			linear_velocity = Vector2.ZERO
			angular_velocity = 0.0
			_physics_process_enabled = false

	## Makes the casing land.
	func _land() -> void:
		_has_landed = true

	## Freeze time — store velocities and stop movement.
	func freeze_time() -> void:
		if _is_time_frozen:
			return
		_frozen_linear_velocity = linear_velocity
		_frozen_angular_velocity = angular_velocity
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		_is_time_frozen = true

	## Unfreeze time — restore velocities and apply pending impulses.
	func unfreeze_time() -> void:
		if not _is_time_frozen:
			return
		linear_velocity = _frozen_linear_velocity
		angular_velocity = _frozen_angular_velocity
		_is_time_frozen = false
		_frozen_linear_velocity = Vector2.ZERO
		_frozen_angular_velocity = 0.0

		if _pending_kick_impulse != Vector2.ZERO:
			receive_kick(_pending_kick_impulse)
			_pending_kick_impulse = Vector2.ZERO

	## Receive a kick impulse.
	func receive_kick(impulse: Vector2) -> void:
		if _is_time_frozen:
			_pending_kick_impulse += impulse
			return
		if _has_landed:
			_has_landed = false
			_auto_land_timer = 0.0
			_physics_process_enabled = true
		_applied_impulses.append(impulse)

	## Determine casing color from caliber data.
	func set_casing_appearance() -> void:
		casing_color = Color(0.9, 0.8, 0.4)  # Default brass

		if caliber_data == null:
			return

		var caliber_name: String = ""
		if caliber_data is MockCaliberData:
			caliber_name = caliber_data.caliber_name

		if "buckshot" in caliber_name.to_lower() or "Buckshot" in caliber_name:
			casing_color = Color(0.8, 0.2, 0.2)  # Red for shotgun
		elif "9x19" in caliber_name or "9mm" in caliber_name.to_lower():
			casing_color = Color(0.7, 0.7, 0.7)  # Silver for pistol


var casing: MockCasing


func before_each() -> void:
	casing = MockCasing.new()


func after_each() -> void:
	casing = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_auto_land_time() -> void:
	assert_eq(MockCasing.AUTO_LAND_TIME, 2.0,
		"AUTO_LAND_TIME should be 2.0 seconds")


func test_spawn_collision_delay() -> void:
	assert_eq(MockCasing.SPAWN_COLLISION_DELAY, 0.1,
		"SPAWN_COLLISION_DELAY should be 0.1 seconds")


# ============================================================================
# Freeze / Unfreeze Velocity Preservation Tests
# ============================================================================


func test_freeze_stores_linear_velocity() -> void:
	casing.linear_velocity = Vector2(100, 50)
	casing.freeze_time()

	assert_eq(casing._frozen_linear_velocity, Vector2(100, 50),
		"Frozen linear velocity should be stored")
	assert_eq(casing.linear_velocity, Vector2.ZERO,
		"Linear velocity should be zeroed during freeze")


func test_freeze_stores_angular_velocity() -> void:
	casing.angular_velocity = 5.0
	casing.freeze_time()

	assert_eq(casing._frozen_angular_velocity, 5.0,
		"Frozen angular velocity should be stored")
	assert_eq(casing.angular_velocity, 0.0,
		"Angular velocity should be zeroed during freeze")


func test_unfreeze_restores_linear_velocity() -> void:
	casing.linear_velocity = Vector2(200, -100)
	casing.freeze_time()
	casing.unfreeze_time()

	assert_eq(casing.linear_velocity, Vector2(200, -100),
		"Linear velocity should be restored after unfreeze")


func test_unfreeze_restores_angular_velocity() -> void:
	casing.angular_velocity = -10.0
	casing.freeze_time()
	casing.unfreeze_time()

	assert_eq(casing.angular_velocity, -10.0,
		"Angular velocity should be restored after unfreeze")


func test_freeze_clears_frozen_values_after_unfreeze() -> void:
	casing.linear_velocity = Vector2(50, 50)
	casing.freeze_time()
	casing.unfreeze_time()

	assert_eq(casing._frozen_linear_velocity, Vector2.ZERO,
		"Frozen linear velocity should be cleared after unfreeze")
	assert_eq(casing._frozen_angular_velocity, 0.0,
		"Frozen angular velocity should be cleared after unfreeze")


func test_double_freeze_no_overwrite() -> void:
	casing.linear_velocity = Vector2(100, 0)
	casing.freeze_time()
	# Second freeze should be ignored
	casing.freeze_time()

	assert_eq(casing._frozen_linear_velocity, Vector2(100, 0),
		"Double freeze should not overwrite stored velocity")


func test_double_unfreeze_no_effect() -> void:
	casing.linear_velocity = Vector2(100, 0)
	casing.freeze_time()
	casing.unfreeze_time()
	casing.linear_velocity = Vector2(50, 0)
	# Second unfreeze should be ignored
	casing.unfreeze_time()

	assert_eq(casing.linear_velocity, Vector2(50, 0),
		"Double unfreeze should not change velocity")


# ============================================================================
# Impulse Queueing During Freeze Tests
# ============================================================================


func test_impulse_queued_during_freeze() -> void:
	casing.freeze_time()
	casing.receive_kick(Vector2(300, 0))

	assert_eq(casing._pending_kick_impulse, Vector2(300, 0),
		"Impulse should be queued during freeze")
	assert_true(casing._applied_impulses.is_empty(),
		"Impulse should NOT be applied during freeze")


func test_multiple_impulses_accumulate_during_freeze() -> void:
	casing.freeze_time()
	casing.receive_kick(Vector2(100, 0))
	casing.receive_kick(Vector2(0, 200))

	assert_eq(casing._pending_kick_impulse, Vector2(100, 200),
		"Multiple impulses should accumulate during freeze")


func test_pending_impulse_applied_on_unfreeze() -> void:
	casing.freeze_time()
	casing.receive_kick(Vector2(500, 0))
	casing.unfreeze_time()

	assert_eq(casing._pending_kick_impulse, Vector2.ZERO,
		"Pending impulse should be cleared after unfreeze")
	assert_eq(casing._applied_impulses.size(), 1,
		"One impulse should have been applied on unfreeze")
	assert_eq(casing._applied_impulses[0], Vector2(500, 0),
		"Applied impulse should match the queued value")


func test_no_pending_impulse_when_not_frozen() -> void:
	casing.receive_kick(Vector2(100, 0))

	assert_eq(casing._pending_kick_impulse, Vector2.ZERO,
		"No pending impulse when not frozen")
	assert_eq(casing._applied_impulses.size(), 1,
		"Impulse should be applied immediately when not frozen")


# ============================================================================
# Landing State Transition Tests
# ============================================================================


func test_not_landed_initially() -> void:
	assert_false(casing._has_landed,
		"Casing should not be landed initially")


func test_auto_lands_after_auto_land_time() -> void:
	casing.physics_process(2.0)

	assert_true(casing._has_landed,
		"Casing should auto-land after AUTO_LAND_TIME")


func test_not_landed_before_auto_land_time() -> void:
	casing.physics_process(1.5)

	assert_false(casing._has_landed,
		"Casing should not land before AUTO_LAND_TIME")


func test_velocity_zeroed_after_landing() -> void:
	casing.linear_velocity = Vector2(100, 50)
	casing.angular_velocity = 5.0
	casing.physics_process(2.5)

	assert_eq(casing.linear_velocity, Vector2.ZERO,
		"Linear velocity should be zero after landing")
	assert_eq(casing.angular_velocity, 0.0,
		"Angular velocity should be zero after landing")


func test_kick_unlocks_landed_casing() -> void:
	casing.physics_process(2.5)
	assert_true(casing._has_landed)

	casing.receive_kick(Vector2(100, 0))

	assert_false(casing._has_landed,
		"Kick should unlock a landed casing")
	assert_eq(casing._auto_land_timer, 0.0,
		"Auto land timer should be reset after kick")


func test_physics_disabled_after_landing() -> void:
	casing.physics_process(2.5)

	assert_false(casing._physics_process_enabled,
		"Physics processing should be disabled after landing")


func test_kick_re_enables_physics() -> void:
	casing.physics_process(2.5)
	casing.receive_kick(Vector2(100, 0))

	assert_true(casing._physics_process_enabled,
		"Physics processing should be re-enabled after kick")


# ============================================================================
# Spawn Collision Delay Tests
# ============================================================================


func test_collision_disabled_initially() -> void:
	assert_false(casing._spawn_collision_enabled,
		"Spawn collision should be disabled initially")


func test_collision_enabled_after_delay() -> void:
	casing.physics_process(0.15)

	assert_true(casing._spawn_collision_enabled,
		"Spawn collision should be enabled after SPAWN_COLLISION_DELAY")


func test_collision_not_enabled_before_delay() -> void:
	casing.physics_process(0.05)

	assert_false(casing._spawn_collision_enabled,
		"Spawn collision should not be enabled before SPAWN_COLLISION_DELAY")


# ============================================================================
# Caliber-Based Appearance Tests
# ============================================================================


func test_default_casing_color_brass() -> void:
	casing.set_casing_appearance()

	assert_eq(casing.casing_color, Color(0.9, 0.8, 0.4),
		"Default casing color should be brass")


func test_buckshot_casing_color_red() -> void:
	var caliber := MockCaliberData.new()
	caliber.caliber_name = "12 Gauge Buckshot"
	casing.caliber_data = caliber
	casing.set_casing_appearance()

	assert_eq(casing.casing_color, Color(0.8, 0.2, 0.2),
		"Buckshot casing should be red")


func test_buckshot_lowercase_casing_color_red() -> void:
	var caliber := MockCaliberData.new()
	caliber.caliber_name = "buckshot shells"
	casing.caliber_data = caliber
	casing.set_casing_appearance()

	assert_eq(casing.casing_color, Color(0.8, 0.2, 0.2),
		"Buckshot (lowercase) casing should be red")


func test_9mm_casing_color_silver() -> void:
	var caliber := MockCaliberData.new()
	caliber.caliber_name = "9x19mm Parabellum"
	casing.caliber_data = caliber
	casing.set_casing_appearance()

	assert_eq(casing.casing_color, Color(0.7, 0.7, 0.7),
		"9mm casing should be silver")


func test_9mm_lowercase_casing_color_silver() -> void:
	var caliber := MockCaliberData.new()
	caliber.caliber_name = "9mm"
	casing.caliber_data = caliber
	casing.set_casing_appearance()

	assert_eq(casing.casing_color, Color(0.7, 0.7, 0.7),
		"9mm (lowercase) casing should be silver")


func test_rifle_casing_color_brass() -> void:
	var caliber := MockCaliberData.new()
	caliber.caliber_name = "5.45x39mm"
	casing.caliber_data = caliber
	casing.set_casing_appearance()

	assert_eq(casing.casing_color, Color(0.9, 0.8, 0.4),
		"Rifle casing should be brass (default)")


func test_unknown_caliber_casing_color_brass() -> void:
	var caliber := MockCaliberData.new()
	caliber.caliber_name = "7.62x54mmR"
	casing.caliber_data = caliber
	casing.set_casing_appearance()

	assert_eq(casing.casing_color, Color(0.9, 0.8, 0.4),
		"Unknown caliber should default to brass")
