extends GutTest
## Unit tests for ProjectilePool autoload.
##
## Tests object pooling functionality for bullets and shrapnel.
## Issue #724: Optimization for bullet-hell scenarios.


const ProjectilePoolScript = preload("res://scripts/autoload/projectile_pool.gd")


var pool: Node


func before_each() -> void:
	# Create a ProjectilePool instance for testing
	pool = Node.new()
	pool.set_script(ProjectilePoolScript)
	add_child_autoqfree(pool)


func after_each() -> void:
	pool = null


# ============================================================================
# Initialization Tests
# ============================================================================


func test_pool_initializes_with_expected_constants() -> void:
	# Check that pool constants are reasonable values
	assert_eq(pool.MIN_BULLET_POOL_SIZE, 64, "Minimum bullet pool size should be 64")
	assert_eq(pool.MIN_SHRAPNEL_POOL_SIZE, 32, "Minimum shrapnel pool size should be 32")
	assert_eq(pool.MIN_BREAKER_SHRAPNEL_POOL_SIZE, 60, "Minimum breaker shrapnel pool size should be 60")


func test_pool_has_max_size_limits() -> void:
	# Verify max pool sizes are set
	assert_gt(pool.MAX_BULLET_POOL_SIZE, 0, "Max bullet pool size should be positive")
	assert_gt(pool.MAX_SHRAPNEL_POOL_SIZE, 0, "Max shrapnel pool size should be positive")
	assert_gt(pool.MAX_BREAKER_SHRAPNEL_POOL_SIZE, 0, "Max breaker shrapnel pool size should be positive")


func test_pool_has_scene_paths() -> void:
	# Verify scene paths are defined
	assert_eq(pool.BULLET_SCENE_PATH, "res://scenes/projectiles/Bullet.tscn", "Bullet scene path should be set")
	assert_eq(pool.SHRAPNEL_SCENE_PATH, "res://scenes/projectiles/Shrapnel.tscn", "Shrapnel scene path should be set")
	assert_eq(pool.BREAKER_SHRAPNEL_SCENE_PATH, "res://scenes/projectiles/BreakerShrapnel.tscn", "Breaker shrapnel scene path should be set")


# ============================================================================
# Statistics Tests
# ============================================================================


func test_pool_provides_stats() -> void:
	var stats: Dictionary = pool.get_stats()

	# Check that stats dictionary has expected structure
	assert_true(stats.has("bullets"), "Stats should have bullets section")
	assert_true(stats.has("shrapnel"), "Stats should have shrapnel section")
	assert_true(stats.has("breaker_shrapnel"), "Stats should have breaker_shrapnel section")


func test_pool_stats_have_expected_keys() -> void:
	var stats: Dictionary = pool.get_stats()

	# Check bullets stats keys
	assert_true(stats.bullets.has("active"), "Bullet stats should have active count")
	assert_true(stats.bullets.has("pooled"), "Bullet stats should have pooled count")
	assert_true(stats.bullets.has("total_created"), "Bullet stats should have total_created count")
	assert_true(stats.bullets.has("reused"), "Bullet stats should have reused count")
	assert_true(stats.bullets.has("reuse_rate"), "Bullet stats should have reuse_rate")


func test_get_active_count_initially_zero() -> void:
	var active_count := pool.get_active_count()
	assert_eq(active_count, 0, "Initial active count should be 0")


func test_get_pooled_count_returns_value() -> void:
	var pooled_count := pool.get_pooled_count()
	# After initialization, there should be pooled projectiles
	assert_gte(pooled_count, 0, "Pooled count should be non-negative")


# ============================================================================
# Capacity Tests
# ============================================================================


func test_has_bullet_capacity_returns_true_initially() -> void:
	var has_capacity := pool.has_bullet_capacity()
	assert_true(has_capacity, "Should have bullet capacity initially")


func test_has_shrapnel_capacity_returns_true_initially() -> void:
	var has_capacity := pool.has_shrapnel_capacity()
	assert_true(has_capacity, "Should have shrapnel capacity initially")


func test_has_breaker_shrapnel_capacity_returns_true_initially() -> void:
	var has_capacity := pool.has_breaker_shrapnel_capacity()
	assert_true(has_capacity, "Should have breaker shrapnel capacity initially")


# ============================================================================
# Debug Settings Tests
# ============================================================================


func test_set_debug_logging() -> void:
	# Should not throw errors when setting debug logging
	pool.set_debug_logging(true)
	pool.set_debug_logging(false)
	assert_true(true, "Debug logging toggle should work without errors")


# ============================================================================
# Reuse Rate Calculation Tests
# ============================================================================


func test_reuse_rate_calculation_zero_total() -> void:
	# When total is 0, reuse rate should be 0
	var rate: float = pool._calculate_reuse_rate(0, 0)
	assert_eq(rate, 0.0, "Reuse rate with 0 total should be 0")


func test_reuse_rate_calculation_with_reuses() -> void:
	# With 5 reuses out of 10 total uses (5 created + 5 reused = 10)
	# The rate should be 50%
	var rate: float = pool._calculate_reuse_rate(5, 5)
	assert_almost_eq(rate, 50.0, 0.1, "Reuse rate should be 50%")


func test_reuse_rate_calculation_all_reused() -> void:
	# With 9 reuses out of 1 created (1 created + 9 reused = 10 uses)
	# The rate should be 90%
	var rate: float = pool._calculate_reuse_rate(9, 1)
	assert_almost_eq(rate, 90.0, 0.1, "Reuse rate should be 90%")
