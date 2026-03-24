extends GutTest
## Unit tests for effect_cleanup.gd auto-cleanup script.
##
## Tests the cleanup delay configuration and total wait time calculation
## for one-shot particle effects.


# ============================================================================
# Mock EffectCleanup for Logic Tests
# ============================================================================


class MockEffectCleanup:
	## Extra time after lifetime before cleanup (allows particles to fade).
	var cleanup_delay: float = 0.5

	## Inherited from GPUParticles2D — particle lifetime.
	var lifetime: float = 1.0

	## Whether cleanup was triggered.
	var queue_freed: bool = false

	## Computed total wait time.
	var _total_wait: float = 0.0

	## Simulate _ready logic.
	func ready() -> void:
		_total_wait = lifetime + cleanup_delay

	## Simulate queue_free.
	func queue_free() -> void:
		queue_freed = true


var cleanup: MockEffectCleanup


func before_each() -> void:
	cleanup = MockEffectCleanup.new()


func after_each() -> void:
	cleanup = null


# ============================================================================
# Default Configuration Tests
# ============================================================================


func test_cleanup_delay_default() -> void:
	assert_eq(cleanup.cleanup_delay, 0.5,
		"Default cleanup_delay should be 0.5 seconds")


func test_lifetime_default() -> void:
	assert_eq(cleanup.lifetime, 1.0,
		"Default lifetime should be 1.0 seconds")


# ============================================================================
# Total Wait Time Calculation Tests
# ============================================================================


func test_total_wait_time_default() -> void:
	cleanup.ready()

	assert_eq(cleanup._total_wait, 1.5,
		"Total wait time should be lifetime (1.0) + cleanup_delay (0.5) = 1.5")


func test_total_wait_time_custom_lifetime() -> void:
	cleanup.lifetime = 3.0
	cleanup.ready()

	assert_eq(cleanup._total_wait, 3.5,
		"Total wait time should be 3.0 + 0.5 = 3.5")


func test_total_wait_time_custom_cleanup_delay() -> void:
	cleanup.cleanup_delay = 2.0
	cleanup.ready()

	assert_eq(cleanup._total_wait, 3.0,
		"Total wait time should be 1.0 + 2.0 = 3.0")


func test_total_wait_time_both_custom() -> void:
	cleanup.lifetime = 5.0
	cleanup.cleanup_delay = 1.0
	cleanup.ready()

	assert_eq(cleanup._total_wait, 6.0,
		"Total wait time should be 5.0 + 1.0 = 6.0")


func test_total_wait_time_zero_cleanup_delay() -> void:
	cleanup.cleanup_delay = 0.0
	cleanup.ready()

	assert_eq(cleanup._total_wait, 1.0,
		"Total wait time should equal lifetime when cleanup_delay is 0")


func test_total_wait_time_zero_lifetime() -> void:
	cleanup.lifetime = 0.0
	cleanup.ready()

	assert_eq(cleanup._total_wait, 0.5,
		"Total wait time should equal cleanup_delay when lifetime is 0")


func test_total_wait_time_both_zero() -> void:
	cleanup.lifetime = 0.0
	cleanup.cleanup_delay = 0.0
	cleanup.ready()

	assert_eq(cleanup._total_wait, 0.0,
		"Total wait time should be 0 when both are 0")
