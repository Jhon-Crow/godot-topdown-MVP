extends GutTest
## Unit tests for FpsMonitor autoload.
##
## Tests the FPS monitoring constants, sample timer accumulation,
## and FPS drop detection logic.


# ============================================================================
# Mock FpsMonitor
# ============================================================================


class MockFpsMonitor:
	## FPS below this value is considered a drop and will be logged.
	const FPS_DROP_THRESHOLD: int = 30

	## How often (in seconds) to sample FPS and check for drops.
	const SAMPLE_INTERVAL: float = 1.0

	## Accumulated time since last sample.
	var _sample_timer: float = 0.0

	## Last sampled FPS value.
	var _last_fps: int = 0

	## Whether the FPS counter label is visible.
	var label_visible: bool = false

	## Tracking for drop logging.
	var drops_logged: Array[int] = []

	## Whether drop logging is enabled.
	var drop_logging_enabled: bool = false

	## Simulates _process(delta) accumulation and sampling.
	func process(delta: float, current_fps: int) -> void:
		_sample_timer += delta
		if _sample_timer < SAMPLE_INTERVAL:
			return

		_sample_timer = 0.0
		_last_fps = current_fps

		# Log drops if enabled
		if drop_logging_enabled and _last_fps < FPS_DROP_THRESHOLD:
			drops_logged.append(_last_fps)

	## Returns the last sampled FPS.
	func get_last_fps() -> int:
		return _last_fps

	## Returns the current sample timer value.
	func get_sample_timer() -> float:
		return _sample_timer


var monitor: MockFpsMonitor


func before_each() -> void:
	monitor = MockFpsMonitor.new()


func after_each() -> void:
	monitor = null


# ============================================================================
# Constant Tests
# ============================================================================


func test_fps_drop_threshold_is_30() -> void:
	assert_eq(MockFpsMonitor.FPS_DROP_THRESHOLD, 30,
		"FPS_DROP_THRESHOLD should be 30")


func test_sample_interval_is_1_second() -> void:
	assert_almost_eq(MockFpsMonitor.SAMPLE_INTERVAL, 1.0, 0.001,
		"SAMPLE_INTERVAL should be 1.0 second")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_sample_timer_is_zero() -> void:
	assert_almost_eq(monitor.get_sample_timer(), 0.0, 0.001,
		"Initial sample timer should be 0.0")


func test_initial_last_fps_is_zero() -> void:
	assert_eq(monitor.get_last_fps(), 0,
		"Initial last FPS should be 0")


func test_initial_drops_logged_is_empty() -> void:
	assert_eq(monitor.drops_logged.size(), 0,
		"Initial drops logged should be empty")


# ============================================================================
# Sample Timer Accumulation Tests
# ============================================================================


func test_timer_accumulates_below_interval() -> void:
	monitor.process(0.5, 60)

	assert_almost_eq(monitor.get_sample_timer(), 0.5, 0.001,
		"Timer should accumulate to 0.5 when delta is 0.5")
	assert_eq(monitor.get_last_fps(), 0,
		"FPS should not be sampled before interval elapses")


func test_timer_accumulates_multiple_frames() -> void:
	monitor.process(0.016, 60)
	monitor.process(0.016, 60)
	monitor.process(0.016, 60)

	assert_almost_eq(monitor.get_sample_timer(), 0.048, 0.001,
		"Timer should accumulate across multiple frames")
	assert_eq(monitor.get_last_fps(), 0,
		"FPS should not be sampled before interval elapses")


func test_timer_resets_on_sample() -> void:
	monitor.process(1.0, 60)

	assert_almost_eq(monitor.get_sample_timer(), 0.0, 0.001,
		"Timer should reset to 0.0 after sampling")
	assert_eq(monitor.get_last_fps(), 60,
		"FPS should be sampled when interval elapses")


func test_timer_resets_when_exceeding_interval() -> void:
	monitor.process(1.5, 45)

	assert_almost_eq(monitor.get_sample_timer(), 0.0, 0.001,
		"Timer should reset even when delta exceeds interval")
	assert_eq(monitor.get_last_fps(), 45,
		"FPS should be sampled when delta exceeds interval")


# ============================================================================
# FPS Drop Detection Tests
# ============================================================================


func test_no_drop_logged_when_fps_above_threshold() -> void:
	monitor.drop_logging_enabled = true
	monitor.process(1.0, 60)

	assert_eq(monitor.drops_logged.size(), 0,
		"No drop should be logged when FPS is above threshold")


func test_no_drop_logged_when_fps_equals_threshold() -> void:
	monitor.drop_logging_enabled = true
	monitor.process(1.0, 30)

	assert_eq(monitor.drops_logged.size(), 0,
		"No drop should be logged when FPS equals threshold (must be below)")


func test_drop_logged_when_fps_below_threshold() -> void:
	monitor.drop_logging_enabled = true
	monitor.process(1.0, 20)

	assert_eq(monitor.drops_logged.size(), 1,
		"Drop should be logged when FPS is below threshold")
	assert_eq(monitor.drops_logged[0], 20,
		"Logged drop should record the actual FPS value")


func test_no_drop_logged_when_logging_disabled() -> void:
	monitor.drop_logging_enabled = false
	monitor.process(1.0, 10)

	assert_eq(monitor.drops_logged.size(), 0,
		"No drop should be logged when drop logging is disabled")


func test_multiple_drops_logged() -> void:
	monitor.drop_logging_enabled = true

	monitor.process(1.0, 25)
	monitor.process(1.0, 15)
	monitor.process(1.0, 29)

	assert_eq(monitor.drops_logged.size(), 3,
		"All drops below threshold should be logged")
	assert_eq(monitor.drops_logged[0], 25, "First drop should be 25")
	assert_eq(monitor.drops_logged[1], 15, "Second drop should be 15")
	assert_eq(monitor.drops_logged[2], 29, "Third drop should be 29")


func test_drop_not_logged_before_interval() -> void:
	monitor.drop_logging_enabled = true
	monitor.process(0.5, 10)

	assert_eq(monitor.drops_logged.size(), 0,
		"Drop should not be logged before sample interval elapses")
