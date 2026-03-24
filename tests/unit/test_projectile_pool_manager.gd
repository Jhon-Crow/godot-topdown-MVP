extends GutTest
## Unit tests for ProjectilePoolManager autoload.
##
## Tests pool sizes, get/return logic, overflow recycling,
## and statistics tracking.


# ============================================================================
# Mock ProjectilePoolManager
# ============================================================================


class MockProjectile:
	var is_active: bool = false
	var id: int = 0

	func pool_deactivate() -> void:
		is_active = false

	func pool_activate() -> void:
		is_active = true


class MockProjectilePoolManager:
	## Pool sizes (mirrors the actual defaults).
	var bullet_pool_size: int = 300
	var shrapnel_pool_size: int = 150
	var breaker_shrapnel_pool_size: int = 200

	## Pool arrays (inactive projectiles ready for use).
	var _bullet_pool: Array = []
	var _active_bullets: Array = []

	## Statistics for debugging/profiling.
	var _stats: Dictionary = {
		"bullets_created": 0,
		"bullets_reused": 0,
		"bullets_recycled": 0,
	}

	var _is_warmed_up: bool = false

	## Pre-instantiates pool objects.
	func warmup(count: int) -> void:
		for i in range(count):
			var bullet := MockProjectile.new()
			bullet.id = i
			_bullet_pool.append(bullet)
			_stats["bullets_created"] += 1
		_is_warmed_up = true

	## Gets a bullet from the pool.
	func get_bullet() -> MockProjectile:
		if _bullet_pool.size() > 0:
			var bullet: MockProjectile = _bullet_pool.pop_back()
			_active_bullets.append(bullet)
			_stats["bullets_reused"] += 1
			return bullet

		# Pool exhausted - recycle oldest active bullet.
		if _active_bullets.size() > 0:
			var oldest: MockProjectile = _active_bullets.pop_front()
			oldest.pool_deactivate()
			_active_bullets.append(oldest)
			_stats["bullets_recycled"] += 1
			return oldest

		return null

	## Returns a bullet to the pool for reuse.
	func return_bullet(bullet: MockProjectile) -> void:
		if bullet == null:
			return
		var idx := _active_bullets.find(bullet)
		if idx >= 0:
			_active_bullets.remove_at(idx)
		bullet.pool_deactivate()
		_bullet_pool.append(bullet)

	## Returns pool statistics.
	func get_stats() -> Dictionary:
		return {
			"bullets_available": _bullet_pool.size(),
			"bullets_active": _active_bullets.size(),
			"bullets_created": _stats["bullets_created"],
			"bullets_reused": _stats["bullets_reused"],
			"bullets_recycled": _stats["bullets_recycled"],
			"is_warmed_up": _is_warmed_up,
		}

	func is_ready() -> bool:
		return _is_warmed_up

	## Clears all pools and returns active projectiles.
	func clear_all() -> void:
		for bullet in _active_bullets:
			bullet.pool_deactivate()
			_bullet_pool.append(bullet)
		_active_bullets.clear()


var pool: MockProjectilePoolManager


func before_each() -> void:
	pool = MockProjectilePoolManager.new()


func after_each() -> void:
	pool = null


# ============================================================================
# Pool Size Tests
# ============================================================================


func test_default_bullet_pool_size() -> void:
	assert_eq(pool.bullet_pool_size, 300,
		"Default bullet pool size should be 300")


func test_default_shrapnel_pool_size() -> void:
	assert_eq(pool.shrapnel_pool_size, 150,
		"Default shrapnel pool size should be 150")


func test_default_breaker_shrapnel_pool_size() -> void:
	assert_eq(pool.breaker_shrapnel_pool_size, 200,
		"Default breaker shrapnel pool size should be 200")


# ============================================================================
# Initial State Tests
# ============================================================================


func test_initial_not_warmed_up() -> void:
	assert_false(pool.is_ready(),
		"Pool should not be warmed up initially")


func test_initial_stats_zeroed() -> void:
	var stats := pool.get_stats()
	assert_eq(stats["bullets_created"], 0, "Initial bullets_created should be 0")
	assert_eq(stats["bullets_reused"], 0, "Initial bullets_reused should be 0")
	assert_eq(stats["bullets_recycled"], 0, "Initial bullets_recycled should be 0")
	assert_eq(stats["bullets_available"], 0, "Initial bullets_available should be 0")
	assert_eq(stats["bullets_active"], 0, "Initial bullets_active should be 0")


# ============================================================================
# Pool Get/Return Logic Tests
# ============================================================================


func test_warmup_creates_bullets() -> void:
	pool.warmup(10)

	var stats := pool.get_stats()
	assert_eq(stats["bullets_created"], 10, "Warmup should create 10 bullets")
	assert_eq(stats["bullets_available"], 10, "All 10 should be available")
	assert_true(pool.is_ready(), "Pool should be warmed up after warmup()")


func test_get_bullet_from_pool() -> void:
	pool.warmup(5)

	var bullet := pool.get_bullet()

	assert_not_null(bullet, "get_bullet() should return a bullet")
	var stats := pool.get_stats()
	assert_eq(stats["bullets_available"], 4, "Available should decrease by 1")
	assert_eq(stats["bullets_active"], 1, "Active should increase by 1")
	assert_eq(stats["bullets_reused"], 1, "Reused count should be 1")


func test_return_bullet_to_pool() -> void:
	pool.warmup(5)
	var bullet := pool.get_bullet()

	pool.return_bullet(bullet)

	var stats := pool.get_stats()
	assert_eq(stats["bullets_available"], 5, "Available should return to 5")
	assert_eq(stats["bullets_active"], 0, "Active should return to 0")
	assert_false(bullet.is_active, "Returned bullet should be deactivated")


func test_get_and_return_multiple_bullets() -> void:
	pool.warmup(5)

	var b1 := pool.get_bullet()
	var b2 := pool.get_bullet()
	var b3 := pool.get_bullet()

	var stats := pool.get_stats()
	assert_eq(stats["bullets_available"], 2, "3 taken, 2 should remain")
	assert_eq(stats["bullets_active"], 3, "3 should be active")

	pool.return_bullet(b1)
	pool.return_bullet(b2)

	stats = pool.get_stats()
	assert_eq(stats["bullets_available"], 4, "2 returned, 4 should be available")
	assert_eq(stats["bullets_active"], 1, "1 should still be active")


func test_get_bullet_returns_null_when_empty_and_no_active() -> void:
	# No warmup, no active bullets
	var bullet := pool.get_bullet()
	assert_null(bullet, "get_bullet() should return null when pool is empty and no active bullets")


# ============================================================================
# Overflow Recycling Tests
# ============================================================================


func test_overflow_recycles_oldest_active() -> void:
	pool.warmup(2)

	var b1 := pool.get_bullet()
	var b2 := pool.get_bullet()

	# Pool is now empty, next get should recycle oldest
	var b3 := pool.get_bullet()

	assert_not_null(b3, "Overflow should recycle, not return null")
	assert_eq(b3, b1, "Oldest active bullet should be recycled")
	var stats := pool.get_stats()
	assert_eq(stats["bullets_recycled"], 1, "Recycled count should be 1")


func test_overflow_deactivates_recycled_bullet() -> void:
	pool.warmup(1)

	var b1 := pool.get_bullet()
	b1.pool_activate()

	# Pool is now empty
	var recycled := pool.get_bullet()

	assert_eq(recycled, b1, "Should recycle the only active bullet")
	assert_false(recycled.is_active, "Recycled bullet should be deactivated")


func test_multiple_overflow_cycles() -> void:
	pool.warmup(1)
	pool.get_bullet()  # Take the only one

	# Each get now recycles
	pool.get_bullet()
	pool.get_bullet()
	pool.get_bullet()

	var stats := pool.get_stats()
	assert_eq(stats["bullets_recycled"], 3, "Should have 3 recycled operations")


# ============================================================================
# Statistics Tracking Tests
# ============================================================================


func test_stats_track_created_count() -> void:
	pool.warmup(15)

	assert_eq(pool.get_stats()["bullets_created"], 15,
		"Stats should track total bullets created during warmup")


func test_stats_track_reused_count() -> void:
	pool.warmup(5)
	pool.get_bullet()
	pool.get_bullet()
	pool.get_bullet()

	assert_eq(pool.get_stats()["bullets_reused"], 3,
		"Stats should track total bullets reused from pool")


func test_stats_track_recycled_count() -> void:
	pool.warmup(1)
	pool.get_bullet()

	pool.get_bullet()  # recycle
	pool.get_bullet()  # recycle

	assert_eq(pool.get_stats()["bullets_recycled"], 2,
		"Stats should track total bullets recycled from overflow")


func test_clear_all_returns_active_to_pool() -> void:
	pool.warmup(5)
	pool.get_bullet()
	pool.get_bullet()
	pool.get_bullet()

	pool.clear_all()

	var stats := pool.get_stats()
	assert_eq(stats["bullets_available"], 5, "All bullets should be available after clear_all")
	assert_eq(stats["bullets_active"], 0, "No bullets should be active after clear_all")
