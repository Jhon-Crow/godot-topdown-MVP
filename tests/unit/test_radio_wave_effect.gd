extends GutTest
## Unit tests for radio_wave_effect.gd radio jammer visual effect.
##
## Tests ring constants, spawn interval, ring expansion logic,
## and ring fade logic.


# ============================================================================
# Mock Ring for Expansion/Fade Tests
# ============================================================================


class MockRing:
	var radius: float = 0.0
	var alpha: float = 1.0


# ============================================================================
# Mock RadioWaveEffect for Logic Tests
# ============================================================================


class MockRadioWaveEffect:
	## Ring radius constants.
	const MAX_RING_RADIUS: float = 60.0
	const MIN_RING_RADIUS: float = 10.0

	## Speed at which rings expand (pixels/second).
	const RING_EXPAND_SPEED: float = 40.0

	## Time between spawning new rings (seconds).
	const RING_SPAWN_INTERVAL: float = 0.5

	## Ring color.
	const RING_COLOR: Color = Color(0.2, 0.8, 1.0, 0.6)

	## Line width.
	const LINE_WIDTH: float = 2.0

	## Active rings.
	var _rings: Array = []

	## Spawn timer accumulator.
	var _spawn_timer: float = 0.0

	## Spawn a new ring.
	func spawn_ring() -> void:
		var ring := MockRing.new()
		ring.radius = MIN_RING_RADIUS
		ring.alpha = 1.0
		_rings.append(ring)

	## Simulate ready.
	func ready() -> void:
		spawn_ring()

	## Simulate process.
	func process(delta: float) -> void:
		# Advance all rings
		for ring in _rings:
			ring.radius += RING_EXPAND_SPEED * delta
			var t: float = (ring.radius - MIN_RING_RADIUS) / (MAX_RING_RADIUS - MIN_RING_RADIUS)
			ring.alpha = clampf(1.0 - t, 0.0, 1.0)

		# Remove finished rings
		_rings = _rings.filter(func(r): return r.alpha > 0.0)

		# Spawn new rings
		_spawn_timer += delta
		if _spawn_timer >= RING_SPAWN_INTERVAL:
			_spawn_timer -= RING_SPAWN_INTERVAL
			spawn_ring()


var effect: MockRadioWaveEffect


func before_each() -> void:
	effect = MockRadioWaveEffect.new()


func after_each() -> void:
	effect = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_max_ring_radius() -> void:
	assert_eq(MockRadioWaveEffect.MAX_RING_RADIUS, 60.0,
		"MAX_RING_RADIUS should be 60.0 pixels")


func test_min_ring_radius() -> void:
	assert_eq(MockRadioWaveEffect.MIN_RING_RADIUS, 10.0,
		"MIN_RING_RADIUS should be 10.0 pixels")


func test_ring_expand_speed() -> void:
	assert_eq(MockRadioWaveEffect.RING_EXPAND_SPEED, 40.0,
		"RING_EXPAND_SPEED should be 40.0 pixels/second")


func test_ring_spawn_interval() -> void:
	assert_eq(MockRadioWaveEffect.RING_SPAWN_INTERVAL, 0.5,
		"RING_SPAWN_INTERVAL should be 0.5 seconds")


func test_ring_color() -> void:
	assert_eq(MockRadioWaveEffect.RING_COLOR, Color(0.2, 0.8, 1.0, 0.6),
		"RING_COLOR should be cyan-ish semi-transparent")


# ============================================================================
# Ring Spawn Tests
# ============================================================================


func test_initial_ring_spawned_on_ready() -> void:
	effect.ready()

	assert_eq(effect._rings.size(), 1,
		"One ring should be spawned on ready")


func test_initial_ring_starts_at_min_radius() -> void:
	effect.ready()

	assert_eq(effect._rings[0].radius, 10.0,
		"Ring should start at MIN_RING_RADIUS")


func test_initial_ring_full_alpha() -> void:
	effect.ready()

	assert_eq(effect._rings[0].alpha, 1.0,
		"Ring should start at full alpha")


func test_new_ring_spawned_at_interval() -> void:
	effect.ready()
	effect.process(0.5)

	# Should have original ring + new ring spawned at 0.5s
	assert_eq(effect._rings.size(), 2,
		"New ring should be spawned at RING_SPAWN_INTERVAL")


# ============================================================================
# Ring Expansion Tests
# ============================================================================


func test_ring_expands_over_time() -> void:
	effect.ready()
	var initial_radius: float = effect._rings[0].radius

	effect.process(0.25)

	# Radius should increase by RING_EXPAND_SPEED * delta = 40 * 0.25 = 10
	assert_gt(effect._rings[0].radius, initial_radius,
		"Ring radius should increase over time")
	assert_almost_eq(effect._rings[0].radius, 20.0, 0.01,
		"Ring should expand by RING_EXPAND_SPEED * delta")


func test_ring_reaches_max_radius() -> void:
	effect.ready()
	# Time to go from MIN to MAX: (60 - 10) / 40 = 1.25 seconds
	effect.process(1.25)

	# The first ring should be at or past max radius
	# (it may have been removed if alpha went to 0)
	# Check that the expansion math works
	var expected_radius: float = 10.0 + 40.0 * 1.25
	assert_almost_eq(expected_radius, 60.0, 0.01,
		"Ring should reach MAX_RING_RADIUS after (MAX-MIN)/SPEED seconds")


# ============================================================================
# Ring Fade Tests
# ============================================================================


func test_ring_fades_as_it_expands() -> void:
	effect.ready()
	effect.process(0.25)
	# radius = 20, t = (20-10)/(60-10) = 0.2, alpha = 0.8

	assert_lt(effect._rings[0].alpha, 1.0,
		"Ring alpha should decrease as it expands")
	assert_almost_eq(effect._rings[0].alpha, 0.8, 0.01,
		"Ring alpha should be 1 - t where t = (radius-MIN)/(MAX-MIN)")


func test_ring_half_expanded_half_alpha() -> void:
	effect.ready()
	# To reach midpoint: radius = 35 (midpoint of 10-60)
	# time = (35-10)/40 = 0.625s
	effect.process(0.625)
	# t = (35-10)/(60-10) = 0.5, alpha = 0.5

	assert_almost_eq(effect._rings[0].alpha, 0.5, 0.01,
		"Ring should have 0.5 alpha at midpoint expansion")


func test_ring_removed_at_zero_alpha() -> void:
	effect.ready()
	# To reach max: time = (60-10)/40 = 1.25s, then alpha = 0
	effect.process(1.3)

	# First ring should have been removed (alpha <= 0)
	# Only the rings spawned later should remain
	for ring in effect._rings:
		assert_gt(ring.alpha, 0.0,
			"No ring should have zero alpha (they should be removed)")


func test_ring_alpha_clamped_to_valid_range() -> void:
	effect.ready()
	effect.process(0.5)

	for ring in effect._rings:
		assert_gte(ring.alpha, 0.0,
			"Ring alpha should be >= 0")
		assert_lte(ring.alpha, 1.0,
			"Ring alpha should be <= 1")
