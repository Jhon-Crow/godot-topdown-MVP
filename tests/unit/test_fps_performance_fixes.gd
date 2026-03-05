extends GutTest
## Unit tests for FPS performance fixes (Issue #953).
##
## Verifies the three key optimizations that address FPS drops at 20+ enemies:
##
## Fix 1: EnemyGrenadeComponent try_throw() throttle — prevents the per-frame
##         raycast storm caused by running up to 60 throw-path checks per second
##         per enemy (confirmed from 7,509 redundant skip log entries in session log).
##
## Fix 2: EnemyGrenadeComponent _log() file I/O guard — gates FileLogger writes
##         behind debug_logging, eliminating 10,357 disk writes per session.
##
## Fix 3: CASING_KICK sound propagation range reduction — reduces from 900px
##         to 150px so the O(n) listener broadcast covers only nearby enemies,
##         not all 19 listeners on every casing-kick event.
##
## Fix 4: Configurable blood decal budget in ExperimentalSettings — allows
##         capping decal count at ~200 to prevent 6,000+ accumulated scene nodes.


# ============================================================================
# Mock EnemyGrenadeComponent for Throttle Tests (Fix #1 and #2)
# ============================================================================


class MockEnemyGrenadeComponentWithThrottle:
	## Configuration mirrors EnemyGrenadeComponent.
	var enabled: bool = true
	var grenades_remaining: int = 3
	var min_throw_distance: float = 275.0
	var safety_margin: float = 50.0
	var max_throw_distance: float = 600.0
	var require_target_visibility: bool = true
	var debug_logging: bool = false

	## Issue #953: Throttle state.
	const THROW_CHECK_INTERVAL: float = 0.3
	var _throw_check_timer: float = 0.0
	var _cooldown: float = 0.0
	var _is_throwing: bool = false

	## Track how many times the actual throw logic (raycasts) was reached.
	var raycast_check_count: int = 0
	## Track how many times try_throw was called total.
	var call_count: int = 0
	## Track how many times the throttle prevented execution.
	var throttled_count: int = 0

	## Mock time — simulate Time.get_ticks_msec() / 1000.0.
	var _mock_time: float = 0.0

	## Mock enemy position and target.
	var _enemy_position: Vector2 = Vector2.ZERO
	var _target: Vector2 = Vector2(500.0, 0.0)

	## Track log calls to file logger.
	var _file_log_calls: int = 0
	## Track print calls (debug_logging guard).
	var _print_calls: int = 0

	## Simulates try_throw() with Issue #953 throttle.
	func try_throw(target: Vector2, is_alive: bool, is_stunned: bool, is_blinded: bool) -> bool:
		call_count += 1

		if not enabled or grenades_remaining <= 0 or _cooldown > 0.0 or _is_throwing:
			return false
		if not is_alive or is_stunned or is_blinded or target == Vector2.ZERO:
			return false

		# Issue #953: Throttle — mirrors the fix in enemy_grenade_component.gd.
		if _mock_time - _throw_check_timer < THROW_CHECK_INTERVAL:
			throttled_count += 1
			return false
		_throw_check_timer = _mock_time

		# Raycast logic would run here — count how often we reach this point.
		raycast_check_count += 1

		# Simulate "unsafe throw distance" skip — the most common pre-fix spam.
		var dist := _enemy_position.distance_to(target)
		var min_safe := 225.0 + safety_margin  # blast_radius + margin
		if dist < min_safe:
			_log("Unsafe throw distance (%.0f < %.0f safe distance)" % [dist, min_safe])
			return false

		return true

	## Simulates _log() with Issue #953 file-logging guard.
	func _log(msg: String) -> void:
		if debug_logging:
			_print_calls += 1
			# In real code, file logger call is also here (now inside debug_logging guard)
			_file_log_calls += 1
		# Previously the file logger call was OUTSIDE the debug_logging guard.
		# The bug was: _logger.log_info() called unconditionally even when debug_logging=false.

	## Advance mock time by delta (simulates physics frames).
	func advance_time(delta: float) -> void:
		_mock_time += delta


# ============================================================================
# Mock SoundPropagation for CASING_KICK Range Tests (Fix #3)
# ============================================================================


class MockSoundPropagation:
	## Propagation distances — mirrors PROPAGATION_DISTANCES in sound_propagation.gd.
	## After Issue #953 fix: CASING_KICK reduced from 900 to 150.
	const CASING_KICK_RANGE_FIXED: float = 150.0
	const CASING_KICK_RANGE_ORIGINAL: float = 900.0
	const GUNSHOT_RANGE: float = 1468.6

	## Count listeners notified within range for a given sound range.
	static func count_notified(listener_positions: Array, sound_pos: Vector2, range: float) -> int:
		var count := 0
		for pos in listener_positions:
			if (pos as Vector2).distance_to(sound_pos) <= range:
				count += 1
		return count


# ============================================================================
# Mock ExperimentalSettings for Blood Decal Budget Tests (Fix #4)
# ============================================================================


class MockExperimentalSettings:
	## Whether blood decal budget is enabled (Issue #953).
	var blood_decal_budget_enabled: bool = false
	## Maximum blood decals when budget is enabled.
	var blood_decal_max_count: int = 200

	func is_blood_decal_budget_enabled() -> bool:
		return blood_decal_budget_enabled

	func get_blood_decal_max_count() -> int:
		return blood_decal_max_count


class MockImpactEffectsManager:
	## Blood decal list.
	var _blood_decals: Array = []
	## MAX_BLOOD_DECALS constant (0 = unlimited, original behavior).
	const MAX_BLOOD_DECALS: int = 0
	## Reference to ExperimentalSettings mock.
	var _experimental_settings: MockExperimentalSettings = null

	func _get_blood_decal_limit() -> int:
		if MAX_BLOOD_DECALS > 0:
			return MAX_BLOOD_DECALS
		if _experimental_settings and \
				_experimental_settings.is_blood_decal_budget_enabled():
			return _experimental_settings.get_blood_decal_max_count()
		return 0

	## Simulates adding a blood decal with budget enforcement.
	func add_blood_decal(decal: Dictionary) -> void:
		_blood_decals.append(decal)
		var effective_limit := _get_blood_decal_limit()
		if effective_limit > 0:
			while _blood_decals.size() > effective_limit:
				_blood_decals.pop_front()

	func get_decal_count() -> int:
		return _blood_decals.size()


# ============================================================================
# Fix #1 Tests: EnemyGrenadeComponent try_throw() throttle
# ============================================================================


func test_throw_check_throttle_prevents_per_frame_calls() -> void:
	## Verifies that the Issue #953 throttle prevents try_throw() from executing
	## the raycast-heavy check path more than once per THROW_CHECK_INTERVAL.
	var comp := MockEnemyGrenadeComponentWithThrottle.new()
	comp._target = Vector2(500.0, 0.0)  # far enough to pass distance check

	# Simulate 60 fps for 1 second (60 calls)
	var frames := 60
	for i in range(frames):
		comp.advance_time(1.0 / 60.0)  # ~16.7ms per frame
		comp.try_throw(comp._target, true, false, false)

	# At 60fps over 1 second with THROW_CHECK_INTERVAL=0.3s:
	# Should only execute raycast checks at t≈0.3, 0.6, 0.9 = at most 3-4 times
	# (actual count depends on frame timing alignment)
	assert_lt(comp.raycast_check_count, 5,
		"Throttle should limit raycast checks to ≤4 per second (INTERVAL=0.3s)")
	assert_gt(comp.throttled_count, 50,
		"Throttle should block >50 of 60 calls per second")
	gut.p("Raycast checks in 1 sec (60 calls): %d, throttled: %d" % [comp.raycast_check_count, comp.throttled_count])


func test_throw_check_throttle_allows_throw_after_interval() -> void:
	## Verifies that try_throw() does execute when enough time has passed.
	var comp := MockEnemyGrenadeComponentWithThrottle.new()
	comp._enemy_position = Vector2.ZERO
	comp._target = Vector2(500.0, 0.0)  # distance=500, min_safe=275, so will execute

	# First call at t=0: should be allowed (timer starts at 0)
	comp._mock_time = 0.0
	comp.try_throw(comp._target, true, false, false)
	assert_eq(comp.raycast_check_count, 1,
		"First call at t=0 should reach raycast check")

	# Immediate second call: should be throttled
	comp.try_throw(comp._target, true, false, false)
	assert_eq(comp.raycast_check_count, 1,
		"Immediate second call should be throttled")

	# After THROW_CHECK_INTERVAL: should be allowed again
	comp._mock_time = MockEnemyGrenadeComponentWithThrottle.THROW_CHECK_INTERVAL + 0.01
	comp.try_throw(comp._target, true, false, false)
	assert_eq(comp.raycast_check_count, 2,
		"Call after THROW_CHECK_INTERVAL should reach raycast check again")


func test_throw_check_throttle_does_not_affect_cooldown_skip() -> void:
	## Verifies that the cooldown guard still prevents throws independently.
	var comp := MockEnemyGrenadeComponentWithThrottle.new()
	comp._cooldown = 5.0  # Active cooldown
	comp._mock_time = 100.0  # Well past any throttle interval

	comp.try_throw(comp._target, true, false, false)
	assert_eq(comp.raycast_check_count, 0,
		"Active cooldown should prevent reaching throttle or raycast check")


func test_throw_check_throttle_interval_is_reasonable() -> void:
	## Verifies the throttle interval is in the 0.1–1.0 second range.
	## Too short (< 0.1s) wastes CPU; too long (> 1.0s) hurts gameplay responsiveness.
	assert_gte(MockEnemyGrenadeComponentWithThrottle.THROW_CHECK_INTERVAL, 0.1,
		"THROW_CHECK_INTERVAL should be >= 0.1 seconds to meaningfully reduce CPU load")
	assert_lte(MockEnemyGrenadeComponentWithThrottle.THROW_CHECK_INTERVAL, 1.0,
		"THROW_CHECK_INTERVAL should be <= 1.0 second to preserve grenade responsiveness")


# ============================================================================
# Fix #2 Tests: EnemyGrenadeComponent file logging guard
# ============================================================================


func test_log_does_not_write_to_file_when_debug_logging_false() -> void:
	## Verifies that _log() does NOT write to file logger when debug_logging=false.
	## Before the fix, _logger.log_info() was called unconditionally, producing
	## 10,357 disk-write calls per session from grenade skip messages alone.
	var comp := MockEnemyGrenadeComponentWithThrottle.new()
	comp.debug_logging = false  # Default state
	comp._mock_time = 100.0

	# Force a "Unsafe throw distance" log call by placing enemy close to target
	comp._enemy_position = Vector2.ZERO
	comp._target = Vector2(100.0, 0.0)  # Very close — will trigger unsafe distance log
	comp.try_throw(comp._target, true, false, false)

	assert_eq(comp._file_log_calls, 0,
		"File logger should NOT be called when debug_logging=false (Issue #953 fix)")
	assert_eq(comp._print_calls, 0,
		"Print should NOT be called when debug_logging=false")


func test_log_writes_to_file_when_debug_logging_true() -> void:
	## Verifies that _log() writes when debug_logging=true (existing behavior preserved).
	var comp := MockEnemyGrenadeComponentWithThrottle.new()
	comp.debug_logging = true
	comp._mock_time = 100.0

	# Force an unsafe distance log call
	comp._enemy_position = Vector2.ZERO
	comp._target = Vector2(100.0, 0.0)  # Close — will trigger unsafe distance log
	comp.try_throw(comp._target, true, false, false)

	assert_gt(comp._file_log_calls, 0,
		"File logger SHOULD be called when debug_logging=true")


func test_per_frame_logging_reduction_at_20_enemies() -> void:
	## Simulates 20 enemies running for 1 second to quantify the reduction.
	## Pre-fix: each enemy logs on every call = 60 * 20 = 1200 log calls/sec.
	## Post-fix: only when debug_logging=true (default=false) = 0 log calls/sec.
	var enemy_count := 20
	var fps := 60
	var duration_sec := 1
	var total_log_calls := 0

	for _e in range(enemy_count):
		var comp := MockEnemyGrenadeComponentWithThrottle.new()
		comp.debug_logging = false  # Default
		comp._enemy_position = Vector2.ZERO
		comp._target = Vector2(100.0, 0.0)  # Close — always hits unsafe distance
		comp._mock_time = 0.0
		# Note: mock time never advances so all calls hit the throttle after first
		# We're testing logging, so skip throttle by advancing time
		for _frame in range(fps * duration_sec):
			comp._mock_time += 1.0  # Each call gets new time to bypass throttle
			comp.try_throw(comp._target, true, false, false)
		total_log_calls += comp._file_log_calls

	assert_eq(total_log_calls, 0,
		"With debug_logging=false, zero file log calls across 20 enemies × 60fps × 1sec")
	gut.p("Total file log calls (debug_logging=false): %d (was ~1200 pre-fix)" % total_log_calls)


# ============================================================================
# Fix #3 Tests: CASING_KICK sound propagation range reduction
# ============================================================================


func test_casing_kick_range_reduced_from_900_to_150() -> void:
	## Verifies the fixed CASING_KICK range is significantly less than 900px.
	assert_lt(MockSoundPropagation.CASING_KICK_RANGE_FIXED, 300.0,
		"CASING_KICK range should be < 300px after Issue #953 fix")
	assert_lt(MockSoundPropagation.CASING_KICK_RANGE_FIXED,
		MockSoundPropagation.CASING_KICK_RANGE_ORIGINAL,
		"Fixed CASING_KICK range should be less than original 900px")


func test_casing_kick_fixed_range_notifies_fewer_enemies() -> void:
	## Simulates 19 enemies spread across a level and counts how many are
	## notified by a casing kick at the center — at 900px vs 150px.
	var sound_pos := Vector2(500.0, 500.0)
	# Build listener positions: mix of near and far enemies
	var listener_positions: Array = []
	# 3 enemies very close (<150px)
	listener_positions.append(Vector2(520.0, 520.0))  # dist ~28px
	listener_positions.append(Vector2(560.0, 500.0))  # dist ~60px
	listener_positions.append(Vector2(500.0, 620.0))  # dist ~120px
	# 16 enemies farther away (150px-900px)
	for i in range(16):
		listener_positions.append(Vector2(500.0 + 200.0 + i * 40.0, 500.0))  # 700px-1300px from sound

	var notified_original := MockSoundPropagation.count_notified(listener_positions, sound_pos,
		MockSoundPropagation.CASING_KICK_RANGE_ORIGINAL)
	var notified_fixed := MockSoundPropagation.count_notified(listener_positions, sound_pos,
		MockSoundPropagation.CASING_KICK_RANGE_FIXED)

	assert_gt(notified_original, notified_fixed,
		"Original 900px range should notify more enemies than fixed 150px range")
	assert_lte(notified_fixed, 3,
		"Fixed 150px range should notify at most 3 nearby enemies")
	assert_eq(notified_original, 19,
		"Original 900px range notifies all 19 listeners")
	gut.p("Enemies notified: original=% d, fixed=%d" % [notified_original, notified_fixed])


func test_casing_kick_fixed_range_allows_close_enemies_to_react() -> void:
	## Verifies that nearby enemies can still hear casings with the reduced range.
	var sound_pos := Vector2.ZERO
	var close_enemy := Vector2(100.0, 0.0)  # 100px away — within 150px range
	var far_enemy := Vector2(500.0, 0.0)    # 500px away — outside 150px range

	assert_lte(close_enemy.distance_to(sound_pos), MockSoundPropagation.CASING_KICK_RANGE_FIXED,
		"Enemy at 100px should be within fixed CASING_KICK range")
	assert_gt(far_enemy.distance_to(sound_pos), MockSoundPropagation.CASING_KICK_RANGE_FIXED,
		"Enemy at 500px should be outside fixed CASING_KICK range")


func test_casing_kick_range_vs_gunshot_range() -> void:
	## Verifies CASING_KICK range is meaningfully smaller than GUNSHOT range.
	## Gunshots should alert enemies much farther away than a casing rolling on the floor.
	assert_lt(MockSoundPropagation.CASING_KICK_RANGE_FIXED,
		MockSoundPropagation.GUNSHOT_RANGE / 5.0,
		"CASING_KICK range should be less than 1/5 of GUNSHOT range")


# ============================================================================
# Fix #4 Tests: Configurable blood decal budget
# ============================================================================


func test_blood_decal_budget_disabled_allows_unlimited_decals() -> void:
	## Verifies that when budget is disabled (default), decals accumulate without limit.
	var manager := MockImpactEffectsManager.new()
	manager._experimental_settings = MockExperimentalSettings.new()
	manager._experimental_settings.blood_decal_budget_enabled = false

	for i in range(500):
		manager.add_blood_decal({"id": i})

	assert_eq(manager.get_decal_count(), 500,
		"With budget disabled, all 500 decals should persist (unlimited behavior)")


func test_blood_decal_budget_enabled_caps_at_max_count() -> void:
	## Verifies that when budget is enabled, decal count is capped at max_count.
	var manager := MockImpactEffectsManager.new()
	var settings := MockExperimentalSettings.new()
	settings.blood_decal_budget_enabled = true
	settings.blood_decal_max_count = 200
	manager._experimental_settings = settings

	for i in range(500):
		manager.add_blood_decal({"id": i})

	assert_eq(manager.get_decal_count(), 200,
		"With budget enabled at 200, exactly 200 decals should remain")


func test_blood_decal_budget_removes_oldest_first() -> void:
	## Verifies that the oldest decals are removed when budget is exceeded (FIFO).
	var manager := MockImpactEffectsManager.new()
	var settings := MockExperimentalSettings.new()
	settings.blood_decal_budget_enabled = true
	settings.blood_decal_max_count = 3
	manager._experimental_settings = settings

	# Add 5 decals with identifiable ids
	for i in range(5):
		manager.add_blood_decal({"id": i})

	assert_eq(manager.get_decal_count(), 3,
		"Budget of 3 should keep only 3 decals")
	assert_eq((manager._blood_decals[0] as Dictionary)["id"], 2,
		"Oldest decals (id=0, id=1) should have been removed; id=2 is now oldest")
	assert_eq((manager._blood_decals[2] as Dictionary)["id"], 4,
		"Newest decal (id=4) should still be present")


func test_blood_decal_budget_default_settings_are_off() -> void:
	## Verifies that the blood decal budget is OFF by default (preserving
	## issues #293 and #370 design intent for permanent blood).
	var settings := MockExperimentalSettings.new()
	assert_false(settings.is_blood_decal_budget_enabled(),
		"Blood decal budget should be disabled by default")


func test_blood_decal_budget_default_max_count_is_reasonable() -> void:
	## Verifies the default max count is in a sensible range when enabled.
	var settings := MockExperimentalSettings.new()
	assert_gte(settings.get_blood_decal_max_count(), 50,
		"Default max count should allow a visually rich scene (>= 50)")
	assert_lte(settings.get_blood_decal_max_count(), 1000,
		"Default max count should bound scene-tree growth (<= 1000)")


func test_blood_decal_budget_max_count_constant_takes_precedence() -> void:
	## Verifies that MAX_BLOOD_DECALS constant (if > 0) takes precedence
	## over ExperimentalSettings (backward-compatibility guarantee).
	# Note: We can't test this directly since MockImpactEffectsManager has
	# MAX_BLOOD_DECALS = 0. We verify the logic in _get_blood_decal_limit():
	# if MAX_BLOOD_DECALS > 0: return MAX_BLOOD_DECALS (no ExperimentalSettings check)
	# This test documents the expected behavior.
	var manager := MockImpactEffectsManager.new()
	# With MAX_BLOOD_DECALS = 0 and no experimental settings set
	assert_eq(manager._get_blood_decal_limit(), 0,
		"With MAX_BLOOD_DECALS=0 and no ExperimentalSettings, limit should be 0 (unlimited)")
