extends GutTest
## Unit tests for illusion_effect.gd visual illusion copies.
##
## Tests maximum total illusions, illusion duration, phantom shoot
## interval, health (1 HP), and alive state.


# ============================================================================
# Mock IllusionEffect for Logic Tests
# ============================================================================


class MockIllusionEffect:
	## Max total illusions allowed on the map.
	const MAX_TOTAL_ILLUSIONS: int = 12

	## Group name for tracking.
	const ILLUSION_GROUP: String = "illusion_effects"

	## How long the illusion persists (seconds).
	var illusion_duration: float = 20.0

	## Offset from the original enemy.
	var follow_offset: Vector2 = Vector2(80, 0)

	## Interval between phantom shots (seconds).
	var phantom_shoot_interval: float = 2.0

	## Whether the illusion is alive.
	var _is_alive: bool = true

	## Health (1 HP = one-shot).
	var _health: int = 1

	## Time remaining.
	var _time_remaining: float = 0.0

	## Shoot timer.
	var _shoot_timer: float = 0.0

	## Track if destroyed.
	var _destroyed: bool = false

	## Track phantom shots fired.
	var _shots_fired: int = 0

	## Current modulate alpha.
	var modulate_a: float = 1.0

	## Simulate ready.
	func ready() -> void:
		_time_remaining = illusion_duration

	## Simulate physics process.
	func physics_process(delta: float) -> void:
		if not _is_alive:
			return

		_shoot_timer += delta
		if _shoot_timer >= phantom_shoot_interval:
			_shoot_timer = 0.0
			_shots_fired += 1

		_time_remaining -= delta
		if _time_remaining <= 0.0:
			_destroy()
			return

		# Fade out in last 3 seconds
		if _time_remaining < 3.0:
			modulate_a = _time_remaining / 3.0

	## Take damage.
	func take_damage(_amount: float = 1.0) -> void:
		_health -= 1
		if _health <= 0:
			_destroy()

	## Check if alive.
	func is_alive() -> bool:
		return _is_alive

	## Destroy the illusion.
	func _destroy() -> void:
		if not _is_alive:
			return
		_is_alive = false
		_destroyed = true

	## Static: check if can spawn more (simulated with current count parameter).
	static func can_spawn_more(current_count: int) -> bool:
		return current_count < MAX_TOTAL_ILLUSIONS


var illusion: MockIllusionEffect


func before_each() -> void:
	illusion = MockIllusionEffect.new()


func after_each() -> void:
	illusion = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_max_total_illusions() -> void:
	assert_eq(MockIllusionEffect.MAX_TOTAL_ILLUSIONS, 12,
		"MAX_TOTAL_ILLUSIONS should be 12")


func test_illusion_group_name() -> void:
	assert_eq(MockIllusionEffect.ILLUSION_GROUP, "illusion_effects",
		"ILLUSION_GROUP should be 'illusion_effects'")


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_illusion_duration_default() -> void:
	assert_eq(illusion.illusion_duration, 20.0,
		"Illusion duration should default to 20.0 seconds")


func test_phantom_shoot_interval_default() -> void:
	assert_eq(illusion.phantom_shoot_interval, 2.0,
		"Phantom shoot interval should default to 2.0 seconds")


func test_health_is_one_hp() -> void:
	assert_eq(illusion._health, 1,
		"Illusion health should be 1 HP")


func test_follow_offset_default() -> void:
	assert_eq(illusion.follow_offset, Vector2(80, 0),
		"Default follow offset should be Vector2(80, 0)")


# ============================================================================
# Health / Damage Tests
# ============================================================================


func test_alive_initially() -> void:
	assert_true(illusion.is_alive(),
		"Illusion should be alive initially")


func test_one_hit_kills() -> void:
	illusion.take_damage(1.0)

	assert_false(illusion.is_alive(),
		"Illusion should die after taking any damage (1 HP)")


func test_destroy_sets_not_alive() -> void:
	illusion._destroy()

	assert_false(illusion.is_alive(),
		"Destroy should set illusion to not alive")


func test_double_destroy_safe() -> void:
	illusion._destroy()
	illusion._destroy()

	assert_false(illusion.is_alive(),
		"Double destroy should be safe")


# ============================================================================
# Duration / Expiry Tests
# ============================================================================


func test_time_remaining_set_on_ready() -> void:
	illusion.ready()

	assert_eq(illusion._time_remaining, 20.0,
		"Time remaining should be set to illusion_duration on ready")


func test_expires_after_duration() -> void:
	illusion.ready()
	illusion.physics_process(21.0)

	assert_false(illusion.is_alive(),
		"Illusion should expire after duration")
	assert_true(illusion._destroyed,
		"Illusion should be destroyed after expiry")


func test_persists_before_duration() -> void:
	illusion.ready()
	illusion.physics_process(10.0)

	assert_true(illusion.is_alive(),
		"Illusion should persist before duration expires")


# ============================================================================
# Fade-Out Tests
# ============================================================================


func test_no_fade_above_3_seconds() -> void:
	illusion.ready()
	illusion.physics_process(10.0)

	assert_eq(illusion.modulate_a, 1.0,
		"Modulate alpha should be 1.0 when time remaining > 3s")


func test_fade_in_last_3_seconds() -> void:
	illusion.ready()
	illusion.physics_process(18.5)
	# time_remaining = 1.5, alpha = 1.5/3.0 = 0.5

	assert_almost_eq(illusion.modulate_a, 0.5, 0.05,
		"Modulate alpha should fade in last 3 seconds")


# ============================================================================
# Phantom Shooting Tests
# ============================================================================


func test_no_shots_before_interval() -> void:
	illusion.ready()
	illusion.physics_process(1.5)

	assert_eq(illusion._shots_fired, 0,
		"No shots should be fired before phantom_shoot_interval")


func test_shot_at_interval() -> void:
	illusion.ready()
	illusion.physics_process(2.0)

	assert_eq(illusion._shots_fired, 1,
		"One shot should be fired at phantom_shoot_interval")


# ============================================================================
# Spawn Limit Tests
# ============================================================================


func test_can_spawn_more_below_limit() -> void:
	assert_true(MockIllusionEffect.can_spawn_more(5),
		"Should be able to spawn more when below limit")


func test_cannot_spawn_more_at_limit() -> void:
	assert_false(MockIllusionEffect.can_spawn_more(12),
		"Should not be able to spawn more at MAX_TOTAL_ILLUSIONS")


func test_cannot_spawn_more_above_limit() -> void:
	assert_false(MockIllusionEffect.can_spawn_more(20),
		"Should not be able to spawn more above limit")


func test_can_spawn_at_zero() -> void:
	assert_true(MockIllusionEffect.can_spawn_more(0),
		"Should be able to spawn when count is 0")
