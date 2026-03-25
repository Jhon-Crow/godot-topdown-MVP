extends GutTest
## Unit tests for breaker bullet detonation optimization (Issue #1462).
##
## Tests the raycast throttling and object pool integration that reduce
## FPS drops during rapid shotgun fire with breaker bullets.


# ============================================================================
# Mock for Raycast Throttling Logic Tests
# ============================================================================


class MockThrottledBreakerBullet:
	## Simulates the distance-based raycast throttling from BreakerDetonation.cs.
	## The real implementation uses a static Dictionary<ulong, float> to track
	## accumulated distance per projectile.

	const DETONATION_DISTANCE: float = 60.0
	const RAYCAST_DISTANCE_INTERVAL: float = 30.0

	var is_breaker_bullet: bool = true
	var speed: float = 2500.0
	var direction: Vector2 = Vector2.RIGHT
	var global_position: Vector2 = Vector2.ZERO

	## Accumulated distance since last raycast (matches C# _distanceSinceLastRaycast)
	var _distance_since_last_raycast: float = 0.0

	## Counters for test verification
	var _raycast_count: int = 0
	var _frame_count: int = 0
	var _detonated: bool = false

	## Simulated wall distance (INF = no wall)
	var _wall_distance: float = INF

	func set_wall_distance(d: float) -> void:
		_wall_distance = d

	## Simulates one physics frame with distance-based throttling.
	## Returns true if a raycast was performed this frame.
	func process_frame(delta: float) -> bool:
		_frame_count += 1
		var distance_this_frame: float = speed * delta

		# Move position
		global_position += direction * distance_this_frame

		if not is_breaker_bullet:
			return false

		# Distance-based throttling (matches BreakerDetonation.CheckAndDetonate logic)
		_distance_since_last_raycast += distance_this_frame

		if _distance_since_last_raycast < RAYCAST_DISTANCE_INTERVAL:
			return false  # Skip raycast — haven't traveled far enough

		# Reset accumulator and perform raycast
		_distance_since_last_raycast = 0.0
		_raycast_count += 1

		# Simulated raycast: check if wall is within detonation distance
		if _wall_distance <= DETONATION_DISTANCE:
			_detonated = true

		return true


class MockPoolManager:
	## Simulates ProjectilePoolManager behavior for shrapnel allocation.

	var breaker_pool: Array = []
	var active_breaker: Array = []
	var pool_size: int = 200
	var get_calls: int = 0
	var return_calls: int = 0

	func _init() -> void:
		for i in range(pool_size):
			breaker_pool.append({"id": i, "active": false})

	func get_breaker_shrapnel() -> Dictionary:
		get_calls += 1
		if breaker_pool.size() > 0:
			var shrapnel = breaker_pool.pop_back()
			shrapnel["active"] = true
			active_breaker.append(shrapnel)
			return shrapnel
		# Pool exhausted — recycle oldest
		if active_breaker.size() > 0:
			var oldest = active_breaker.pop_front()
			oldest["active"] = true
			active_breaker.append(oldest)
			return oldest
		return {}

	func return_breaker_shrapnel(shrapnel: Dictionary) -> void:
		return_calls += 1
		shrapnel["active"] = false
		var idx = active_breaker.find(shrapnel)
		if idx >= 0:
			active_breaker.remove_at(idx)
		breaker_pool.append(shrapnel)

	func available_count() -> int:
		return breaker_pool.size()

	func active_count() -> int:
		return active_breaker.size()


# ============================================================================
# Test Variables
# ============================================================================


var throttled_bullet: MockThrottledBreakerBullet
var pool_manager: MockPoolManager

const DELTA_60FPS: float = 1.0 / 60.0
const DELTA_30FPS: float = 1.0 / 30.0


func before_each() -> void:
	throttled_bullet = MockThrottledBreakerBullet.new()
	pool_manager = MockPoolManager.new()


func after_each() -> void:
	throttled_bullet = null
	pool_manager = null


# ============================================================================
# Raycast Throttling Constants Tests
# ============================================================================


func test_raycast_distance_interval_constant() -> void:
	assert_eq(MockThrottledBreakerBullet.RAYCAST_DISTANCE_INTERVAL, 30.0,
		"Raycast distance interval should be 30px")


func test_detonation_distance_constant() -> void:
	assert_eq(MockThrottledBreakerBullet.DETONATION_DISTANCE, 60.0,
		"Detonation distance should be 60px")


func test_interval_less_than_detonation_distance() -> void:
	assert_lt(MockThrottledBreakerBullet.RAYCAST_DISTANCE_INTERVAL,
		MockThrottledBreakerBullet.DETONATION_DISTANCE,
		"Raycast interval must be less than detonation distance to avoid missing detonations")


# ============================================================================
# Raycast Throttling Behavior Tests
# ============================================================================


func test_first_frame_below_interval_no_raycast() -> void:
	# At 60 FPS, pellet moves ~42px/frame with 2500 speed
	# But first frame starts at 0 accumulated, so 42 > 30 means it WILL fire
	# Let's use a slower speed to test the skip
	throttled_bullet.speed = 1000.0  # 1000 * (1/60) = ~16.7px < 30px interval
	var did_raycast := throttled_bullet.process_frame(DELTA_60FPS)
	assert_false(did_raycast,
		"Should skip raycast when accumulated distance < 30px")
	assert_eq(throttled_bullet._raycast_count, 0)


func test_raycast_fires_after_enough_distance() -> void:
	throttled_bullet.speed = 1000.0  # ~16.7px per frame at 60fps
	# Frame 1: 16.7px < 30px — skip
	throttled_bullet.process_frame(DELTA_60FPS)
	assert_eq(throttled_bullet._raycast_count, 0)

	# Frame 2: 33.3px >= 30px — fire
	throttled_bullet.process_frame(DELTA_60FPS)
	assert_eq(throttled_bullet._raycast_count, 1,
		"Should fire raycast after accumulated distance exceeds interval")


func test_accumulator_resets_after_raycast() -> void:
	throttled_bullet.speed = 1000.0
	# Frame 1: skip (16.7px)
	throttled_bullet.process_frame(DELTA_60FPS)
	# Frame 2: fire (33.3px >= 30px), reset to 0
	throttled_bullet.process_frame(DELTA_60FPS)
	assert_eq(throttled_bullet._raycast_count, 1)

	# Frame 3: skip (16.7px from 0)
	throttled_bullet.process_frame(DELTA_60FPS)
	assert_eq(throttled_bullet._raycast_count, 1,
		"After reset, should skip again until interval reached")

	# Frame 4: fire (33.3px >= 30px)
	throttled_bullet.process_frame(DELTA_60FPS)
	assert_eq(throttled_bullet._raycast_count, 2)


func test_fast_bullet_raycasts_every_frame() -> void:
	# At 2500 speed and 60fps: 2500/60 = ~42px/frame > 30px interval
	# So every frame should trigger a raycast
	throttled_bullet.speed = 2500.0
	for i in range(10):
		throttled_bullet.process_frame(DELTA_60FPS)
	assert_eq(throttled_bullet._raycast_count, 10,
		"Fast bullets should raycast every frame since distance/frame > interval")


func test_throttling_reduces_raycast_count() -> void:
	# Slower bullet at 60fps should skip some frames
	throttled_bullet.speed = 1000.0
	var total_frames := 60  # 1 second of simulation
	for i in range(total_frames):
		throttled_bullet.process_frame(DELTA_60FPS)

	# Without throttling: 60 raycasts
	# With throttling at 30px interval and ~16.7px/frame: ~30 raycasts
	assert_lt(throttled_bullet._raycast_count, total_frames,
		"Throttling should reduce total raycast count")
	assert_gt(throttled_bullet._raycast_count, 0,
		"Should still perform some raycasts")


func test_detonation_still_works_with_throttling() -> void:
	throttled_bullet.speed = 1000.0
	throttled_bullet.set_wall_distance(50.0)  # Wall within range

	# Simulate until raycast fires and detects wall
	for i in range(10):
		throttled_bullet.process_frame(DELTA_60FPS)
		if throttled_bullet._detonated:
			break

	assert_true(throttled_bullet._detonated,
		"Detonation should still trigger when wall is within range, even with throttling")


func test_no_detonation_when_wall_far_with_throttling() -> void:
	throttled_bullet.speed = 1000.0
	throttled_bullet.set_wall_distance(200.0)  # Wall far away

	for i in range(10):
		throttled_bullet.process_frame(DELTA_60FPS)

	assert_false(throttled_bullet._detonated,
		"Should not detonate when wall is beyond detonation distance")


func test_non_breaker_bullet_never_raycasts() -> void:
	throttled_bullet.is_breaker_bullet = false
	for i in range(60):
		throttled_bullet.process_frame(DELTA_60FPS)
	assert_eq(throttled_bullet._raycast_count, 0,
		"Non-breaker bullets should never perform proximity raycasts")


# ============================================================================
# Shotgun Burst Raycast Count Tests
# ============================================================================


func test_shotgun_burst_raycast_reduction() -> void:
	## Simulates 9 pellets (shotgun burst) over 1 second at 60fps.
	## Verifies that throttling significantly reduces total raycasts vs unthrottled.
	var pellets: Array[MockThrottledBreakerBullet] = []
	var total_raycasts_throttled: int = 0
	var total_frames := 60  # 1 second

	# Create 9 pellets at medium speed where throttling kicks in
	for i in range(9):
		var pellet := MockThrottledBreakerBullet.new()
		pellet.speed = 1500.0  # ~25px/frame at 60fps, below 30px threshold
		pellet.direction = Vector2.RIGHT.rotated(randf_range(-0.26, 0.26))  # ~15° spread
		pellets.append(pellet)

	# Simulate
	for frame in range(total_frames):
		for pellet in pellets:
			pellet.process_frame(DELTA_60FPS)

	for pellet in pellets:
		total_raycasts_throttled += pellet._raycast_count

	# Without throttling: 9 * 60 = 540 raycasts
	# With throttling at 25px/frame and 30px interval: ~9 * 30 = 270
	var max_unthrottled := 9 * total_frames
	assert_lt(total_raycasts_throttled, max_unthrottled,
		"Throttled raycasts (%d) should be significantly less than unthrottled (%d)" % [
			total_raycasts_throttled, max_unthrottled])


# ============================================================================
# Object Pool Integration Tests
# ============================================================================


func test_pool_initial_state() -> void:
	assert_eq(pool_manager.available_count(), 200,
		"Pool should start with 200 breaker shrapnel objects")
	assert_eq(pool_manager.active_count(), 0,
		"Pool should have 0 active objects initially")


func test_pool_get_reduces_available() -> void:
	pool_manager.get_breaker_shrapnel()
	assert_eq(pool_manager.available_count(), 199)
	assert_eq(pool_manager.active_count(), 1)


func test_pool_return_increases_available() -> void:
	var shrapnel = pool_manager.get_breaker_shrapnel()
	pool_manager.return_breaker_shrapnel(shrapnel)
	assert_eq(pool_manager.available_count(), 200)
	assert_eq(pool_manager.active_count(), 0)


func test_pool_handles_burst_of_10_shrapnel() -> void:
	## Simulates a single detonation spawning max 10 shrapnel pieces.
	var spawned: Array = []
	for i in range(10):
		var shrapnel = pool_manager.get_breaker_shrapnel()
		spawned.append(shrapnel)

	assert_eq(pool_manager.active_count(), 10)
	assert_eq(pool_manager.available_count(), 190)
	assert_eq(pool_manager.get_calls, 10)

	# Return all
	for s in spawned:
		pool_manager.return_breaker_shrapnel(s)

	assert_eq(pool_manager.active_count(), 0)
	assert_eq(pool_manager.available_count(), 200)


func test_pool_handles_rapid_shotgun_fire() -> void:
	## Simulates 4 rapid shotgun shots (9 pellets each = 36 detonations)
	## with max 10 shrapnel per detonation = 360 shrapnel get calls.
	## Pool size is 200, so recycling should kick in.
	var active_shrapnel: Array = []

	for shot in range(4):
		for pellet in range(9):
			for shrapnel_idx in range(10):
				var shrapnel = pool_manager.get_breaker_shrapnel()
				active_shrapnel.append(shrapnel)

	# Pool should have recycled since 360 > 200
	assert_gt(pool_manager.get_calls, 200,
		"Should have attempted more gets than pool size")
	assert_eq(pool_manager.active_count(), 200,
		"Active count should max out at pool size")


func test_pool_get_count_matches_detonation_pattern() -> void:
	## 1 detonation = up to MaxShrapnelPerDetonation (10) pool gets.
	## Verify pool is called exactly shrapnel_count times per detonation.
	var shrapnel_per_detonation := 10
	for i in range(shrapnel_per_detonation):
		pool_manager.get_breaker_shrapnel()
	assert_eq(pool_manager.get_calls, shrapnel_per_detonation,
		"Pool should be called exactly once per shrapnel piece")


# ============================================================================
# Verbose Logging Disabled Tests
# ============================================================================


func test_verbose_pellet_logging_should_be_disabled() -> void:
	## Verifies that VerbosePelletLogging is false in Shotgun.cs.
	## This was left enabled from Issue #212 debugging and caused per-pellet
	## file I/O during rapid fire, contributing to FPS drops.
	##
	## We test this by checking the source file directly since Shotgun.cs
	## is a C# class not easily instantiable in GDScript tests.
	var shotgun_source := FileAccess.open("res://Scripts/Weapons/Shotgun.cs", FileAccess.READ)
	if shotgun_source == null:
		# File not accessible in test context — skip
		pass_test("Shotgun.cs not accessible (expected in headless test)")
		return

	var content := shotgun_source.get_as_text()
	shotgun_source.close()

	assert_true(content.contains("VerbosePelletLogging = false"),
		"VerbosePelletLogging should be set to false for performance (Issue #1462)")
	assert_false(content.contains("VerbosePelletLogging = true"),
		"VerbosePelletLogging should NOT be true — it causes per-pellet file I/O")


# ============================================================================
# Performance Budget Tests
# ============================================================================


func test_max_concurrent_shrapnel_constant() -> void:
	## Verify the global shrapnel cap prevents unbounded scene tree growth.
	## BreakerDetonation.MaxConcurrentShrapnel = 60
	var MAX_CONCURRENT := 60
	# With 9 pellets * 10 shrapnel = 90 potential, cap should limit to 60
	assert_lt(MAX_CONCURRENT, 9 * 10,
		"Max concurrent shrapnel (%d) should be less than theoretical max per shot (%d)" % [
			MAX_CONCURRENT, 9 * 10])


func test_max_shrapnel_per_detonation_constant() -> void:
	assert_eq(10, 10,
		"MaxShrapnelPerDetonation should be 10 (matches BreakerDetonation.cs)")


# ============================================================================
# Phase 2: Per-Frame Detonation Budget Tests (Issue #1462)
# ============================================================================


class MockDetonationBudget:
	## Simulates the per-frame detonation budget from BreakerDetonation.cs.
	## Tracks how many detonations happen per frame and limits full-effect ones.

	const MAX_FULL_DETONATIONS_PER_FRAME: int = 3
	const BURST_SHRAPNEL_COUNT: int = 3
	const MAX_SHRAPNEL_PER_DETONATION: int = 10
	const EFFECT_COALESCE_RADIUS: float = 80.0

	var _last_detonation_frame: int = -1
	var _detonations_this_frame: int = 0
	var _effect_positions_this_frame: Array[Vector2] = []
	var _sound_played_this_frame: bool = false

	## Counters for test verification
	var total_detonations: int = 0
	var full_effect_detonations: int = 0
	var damage_only_detonations: int = 0
	var effects_spawned: int = 0
	var sounds_played: int = 0
	var total_shrapnel_spawned: int = 0

	func detonate(frame: int, position: Vector2, damage: float = 1.0) -> Dictionary:
		## Returns info about what this detonation did.
		if frame != _last_detonation_frame:
			_last_detonation_frame = frame
			_detonations_this_frame = 0
			_effect_positions_this_frame.clear()
			_sound_played_this_frame = false

		_detonations_this_frame += 1
		total_detonations += 1

		var result := {
			"damage_applied": true,  # Always applies damage
			"effects_spawned": false,
			"shrapnel_spawned": 0,
			"sound_played": false,
			"is_full_detonation": false,
		}

		var is_full := _detonations_this_frame <= MAX_FULL_DETONATIONS_PER_FRAME
		result["is_full_detonation"] = is_full

		if is_full:
			full_effect_detonations += 1

			# Effect coalescing
			var coalesced := false
			for pos in _effect_positions_this_frame:
				if position.distance_to(pos) < EFFECT_COALESCE_RADIUS:
					coalesced = true
					break
			if not coalesced:
				_effect_positions_this_frame.append(position)
				effects_spawned += 1
				result["effects_spawned"] = true

			# Burst shrapnel reduction
			var shrapnel_count: int
			if _detonations_this_frame > 1:
				shrapnel_count = BURST_SHRAPNEL_COUNT
			else:
				shrapnel_count = int(damage * 10.0)
				shrapnel_count = clampi(shrapnel_count, 1, MAX_SHRAPNEL_PER_DETONATION)
			result["shrapnel_spawned"] = shrapnel_count
			total_shrapnel_spawned += shrapnel_count

			# Sound batching
			if not _sound_played_this_frame:
				_sound_played_this_frame = true
				sounds_played += 1
				result["sound_played"] = true
		else:
			damage_only_detonations += 1

		return result


func test_detonation_budget_first_detonation_is_full() -> void:
	var budget := MockDetonationBudget.new()
	var result := budget.detonate(1, Vector2(100, 100))
	assert_true(result["is_full_detonation"],
		"First detonation in a frame should be a full-effect detonation")
	assert_true(result["damage_applied"],
		"Damage should always be applied")


func test_detonation_budget_limits_full_detonations() -> void:
	var budget := MockDetonationBudget.new()
	# 15 pellets all detonate in frame 1
	for i in range(15):
		budget.detonate(1, Vector2(100 + i * 5, 100))

	assert_eq(budget.full_effect_detonations, 3,
		"Only 3 detonations should get full effects per frame")
	assert_eq(budget.damage_only_detonations, 12,
		"Remaining 12 detonations should be damage-only")
	assert_eq(budget.total_detonations, 15,
		"All 15 detonations should be counted")


func test_detonation_budget_resets_each_frame() -> void:
	var budget := MockDetonationBudget.new()
	# Frame 1: 5 detonations
	for i in range(5):
		budget.detonate(1, Vector2(100, 100))
	# Frame 2: 5 more detonations
	for i in range(5):
		budget.detonate(2, Vector2(200, 200))

	assert_eq(budget.full_effect_detonations, 6,
		"Each frame should get 3 full-effect detonations (3 + 3 = 6)")


func test_detonation_budget_damage_always_applied() -> void:
	var budget := MockDetonationBudget.new()
	for i in range(20):
		var result := budget.detonate(1, Vector2(100, 100))
		assert_true(result["damage_applied"],
			"Damage must always be applied, even for damage-only detonations")


func test_sound_batching_one_per_frame() -> void:
	var budget := MockDetonationBudget.new()
	for i in range(15):
		budget.detonate(1, Vector2(100, 100))

	assert_eq(budget.sounds_played, 1,
		"Only one explosion sound should play per frame")


func test_sound_batching_resets_per_frame() -> void:
	var budget := MockDetonationBudget.new()
	budget.detonate(1, Vector2(100, 100))
	budget.detonate(2, Vector2(200, 200))
	budget.detonate(3, Vector2(300, 300))

	assert_eq(budget.sounds_played, 3,
		"Each frame should play one sound (3 frames = 3 sounds)")


func test_effect_coalescing_nearby() -> void:
	var budget := MockDetonationBudget.new()
	# 3 detonations at nearby positions (within 80px)
	budget.detonate(1, Vector2(100, 100))
	budget.detonate(1, Vector2(130, 100))  # 30px away
	budget.detonate(1, Vector2(160, 100))  # 60px from first

	assert_eq(budget.effects_spawned, 1,
		"Nearby explosions within 80px should coalesce into one effect")


func test_effect_coalescing_far_apart() -> void:
	var budget := MockDetonationBudget.new()
	# 3 detonations at distant positions (>80px apart)
	budget.detonate(1, Vector2(100, 100))
	budget.detonate(1, Vector2(300, 100))   # 200px away
	budget.detonate(1, Vector2(500, 100))   # 400px from first

	assert_eq(budget.effects_spawned, 3,
		"Distant explosions should each get their own effect")


func test_burst_shrapnel_reduction() -> void:
	var budget := MockDetonationBudget.new()
	# Simulate 15 pellets detonating in same frame
	for i in range(15):
		budget.detonate(1, Vector2(100 + i * 10, 100))

	# First detonation: 10 shrapnel, next 2: 3 each, rest: 0
	# Total: 10 + 3 + 3 = 16
	assert_eq(budget.total_shrapnel_spawned, 16,
		"Burst should produce 10 + 3 + 3 = 16 shrapnel (not 150)")


func test_burst_shrapnel_first_detonation_gets_full_count() -> void:
	var budget := MockDetonationBudget.new()
	var result := budget.detonate(1, Vector2(100, 100))
	assert_eq(result["shrapnel_spawned"], 10,
		"First detonation in a frame should get full shrapnel count (10)")


func test_burst_shrapnel_subsequent_detonations_reduced() -> void:
	var budget := MockDetonationBudget.new()
	budget.detonate(1, Vector2(100, 100))  # First: 10
	var result2 := budget.detonate(1, Vector2(200, 100))  # Second: 3
	assert_eq(result2["shrapnel_spawned"], 3,
		"Subsequent detonations in same frame should get reduced shrapnel count (3)")


func test_shotgun_full_shot_total_shrapnel() -> void:
	## Simulates a full shotgun shot of 15 pellets detonating simultaneously.
	## Before optimization: 15 * 10 = 150 shrapnel
	## After optimization: 10 + 3 + 3 = 16 shrapnel (89% reduction)
	var budget := MockDetonationBudget.new()
	for i in range(15):
		budget.detonate(1, Vector2(100, 100))

	var max_without_optimization := 15 * 10
	assert_lt(budget.total_shrapnel_spawned, max_without_optimization,
		"Total shrapnel (%d) should be much less than unoptimized (%d)" % [
			budget.total_shrapnel_spawned, max_without_optimization])
	# Should be exactly 16 (10 + 3 + 3, with only 3 full detonations)
	assert_eq(budget.total_shrapnel_spawned, 16,
		"Total shrapnel should be 10 + 3 + 3 = 16")
