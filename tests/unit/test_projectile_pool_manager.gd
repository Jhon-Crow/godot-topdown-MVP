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
	var is_pooled: bool = true
	var pool_managed: bool = false
	var return_requested_count: int = 0
	var id: int = 0
	var parent_name: String = "PoolContainer"
	var monitoring: bool = false
	var monitorable: bool = false
	var deferred_writes: Array = []

	func set_pool_managed(managed: bool) -> void:
		pool_managed = managed

	func is_pool_managed() -> bool:
		return pool_managed

	func pool_deactivate(return_to_manager: bool = true) -> void:
		if is_pooled:
			return
		is_active = false
		is_pooled = true
		set_collision_enabled(false)
		if return_to_manager and pool_managed:
			return_requested_count += 1

	func pool_activate() -> void:
		pool_managed = true
		is_active = true
		is_pooled = false
		set_collision_enabled(true)

	func set_collision_enabled(enabled: bool) -> void:
		monitoring = enabled
		monitorable = enabled
		deferred_writes.append(["monitoring", enabled])
		deferred_writes.append(["monitorable", enabled])

	func apply_deferred_writes() -> void:
		for write in deferred_writes:
			set(write[0], write[1])
		deferred_writes.clear()


class MockProjectilePoolManager:
	## Pool sizes (mirrors the actual defaults).
	var bullet_pool_size: int = 300
	var shrapnel_pool_size: int = 150
	var breaker_shrapnel_pool_size: int = 200

	## Pool arrays (inactive projectiles ready for use).
	var _bullet_pool: Array = []
	var _active_bullets: Array = []
	var _bullet_container_name: String = "BulletPool"
	var _current_scene_name: String = "CurrentScene"

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
			bullet.set_pool_managed(true)
			bullet.is_pooled = false
			bullet.pool_deactivate(false)
			_bullet_pool.append(bullet)
			_stats["bullets_created"] += 1
		_is_warmed_up = true

	## Gets a bullet from the pool.
	func get_bullet() -> MockProjectile:
		while _bullet_pool.size() > 0:
			var bullet: MockProjectile = _bullet_pool.pop_back()
			if not bullet.is_pool_managed():
				continue
			if _active_bullets.find(bullet) >= 0:
				continue
			_active_bullets.append(bullet)
			_activate_projectile_parent(bullet)
			_stats["bullets_reused"] += 1
			return bullet

		# Pool exhausted - recycle oldest active bullet.
		if _active_bullets.size() > 0:
			var oldest: MockProjectile = _active_bullets.pop_front()
			oldest.pool_deactivate(false)
			_active_bullets.append(oldest)
			_activate_projectile_parent(oldest)
			_stats["bullets_recycled"] += 1
			return oldest

		return null

	func _activate_projectile_parent(projectile: MockProjectile) -> void:
		projectile.parent_name = _current_scene_name

	func _return_to_pool_container(projectile: MockProjectile) -> void:
		projectile.parent_name = _bullet_container_name

	## Returns a bullet to the pool for reuse.
	func return_bullet(bullet: MockProjectile) -> void:
		if bullet == null:
			return
		if not bullet.is_pool_managed():
			return
		var idx := _active_bullets.find(bullet)
		if idx >= 0:
			_active_bullets.remove_at(idx)
		bullet.pool_deactivate(false)
		_return_to_pool_container(bullet)
		if _bullet_pool.find(bullet) < 0:
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
			if not bullet.is_pool_managed():
				continue
			bullet.pool_deactivate(false)
			_return_to_pool_container(bullet)
			if _bullet_pool.find(bullet) < 0:
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


func test_warmup_deactivation_does_not_self_return() -> void:
	pool.warmup(3)

	for bullet in pool._bullet_pool:
		assert_eq(bullet.return_requested_count, 0,
			"Warmup should deactivate pool-owned bullets without routing through return_bullet()")


func test_get_bullet_from_pool() -> void:
	pool.warmup(5)

	var bullet := pool.get_bullet()

	assert_not_null(bullet, "get_bullet() should return a bullet")
	assert_eq(bullet.parent_name, "CurrentScene",
		"Checked-out pooled projectiles should be reparented into the active gameplay scene")
	var stats := pool.get_stats()
	assert_eq(stats["bullets_available"], 4, "Available should decrease by 1")
	assert_eq(stats["bullets_active"], 1, "Active should increase by 1")
	assert_eq(stats["bullets_reused"], 1, "Reused count should be 1")


func test_return_bullet_to_pool() -> void:
	pool.warmup(5)
	var bullet := pool.get_bullet()
	bullet.pool_activate()

	pool.return_bullet(bullet)

	var stats := pool.get_stats()
	assert_eq(stats["bullets_available"], 5, "Available should return to 5")
	assert_eq(stats["bullets_active"], 0, "Active should return to 0")
	assert_false(bullet.is_active, "Returned bullet should be deactivated")
	assert_eq(bullet.parent_name, "BulletPool",
		"Returned projectiles should move back under their pool container")


func test_return_bullet_rejects_unmanaged_projectile() -> void:
	pool.warmup(5)
	var unmanaged := MockProjectile.new()

	pool.return_bullet(unmanaged)

	var stats := pool.get_stats()
	assert_eq(stats["bullets_available"], 5,
		"Unmanaged projectiles must not enter the generic bullet pool")
	assert_eq(pool._bullet_pool.find(unmanaged), -1,
		"Freshly instantiated weapon bullets must not contaminate the pool")


func test_duplicate_return_does_not_duplicate_pool_entry() -> void:
	pool.warmup(1)
	var bullet := pool.get_bullet()
	bullet.pool_activate()

	pool.return_bullet(bullet)
	pool.return_bullet(bullet)

	var stats := pool.get_stats()
	assert_eq(stats["bullets_available"], 1,
		"Returning the same projectile twice must not create duplicate pool references")
	assert_eq(stats["bullets_active"], 0,
		"Duplicate returns should leave no active references")


func test_same_frame_reuse_leaves_collision_enabled_after_deferred_flush() -> void:
	pool.warmup(1)
	var bullet := pool.get_bullet()
	bullet.pool_activate()
	bullet.apply_deferred_writes()

	pool.return_bullet(bullet)
	var reused := pool.get_bullet()
	reused.pool_activate()
	reused.apply_deferred_writes()

	assert_true(reused.monitoring,
		"A pooled projectile reused in the same frame must not be disabled by stale deferred return state")
	assert_true(reused.monitorable,
		"A pooled projectile reused in the same frame must stay monitorable after deferred writes flush")


func test_get_bullet_skips_active_duplicate_reference() -> void:
	pool.warmup(1)
	var bullet := pool.get_bullet()
	pool._bullet_pool.append(bullet)

	var reused := pool.get_bullet()

	assert_eq(reused, bullet,
		"With no inactive projectiles left, the active projectile may only be recycled once")
	assert_eq(pool.get_stats()["bullets_active"], 1,
		"An active projectile duplicated in the idle pool must not be tracked twice")
	assert_eq(pool._bullet_pool.find(bullet), -1,
		"Active duplicate references should be discarded from the idle pool")


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
	assert_eq(recycled.parent_name, "CurrentScene",
		"Recycled projectiles should stay in the active gameplay scene for the next activation")


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


func _read_text_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "%s must be readable" % path)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _extract_gdscript_method(source: String, signature: String) -> String:
	var start := source.find(signature)
	assert_true(start >= 0, "Source should contain method signature: %s" % signature)
	if start < 0:
		return ""
	var next_func := source.find("\nfunc ", start + signature.length())
	if next_func < 0:
		return source.substr(start)
	return source.substr(start, next_func - start)


func test_enemy_specialized_bullet_scenes_bypass_generic_pool() -> void:
	# Regression from issue #1634 review: enemy shots with Bullet9mm.tscn were routed
	# through ProjectilePoolManager.get_bullet(), which returns generic Bullet.tscn.
	# That made some enemy bullets disappear or behave unlike the configured weapon.
	var source := _read_text_file("res://scripts/objects/enemy.gd")
	var body := _extract_gdscript_method(source, "func _spawn_projectile(dir: Vector2, pos: Vector2) -> void:")

	assert_true(body.contains("bullet_scene.resource_path == \"res://scenes/projectiles/Bullet.tscn\""),
		"Enemy projectile pooling should be limited to the generic Bullet.tscn scene")
	assert_true(body.contains("can_use_generic_bullet_pool and pm and pm.has_method(\"get_bullet\")"),
		"Enemy projectile spawn should only call get_bullet() when the configured scene matches the pool scene")
	assert_eq(body.find("if pm and pm.has_method(\"get_bullet\"):"), -1,
		"Enemy projectile spawn must not blindly replace configured bullet_scene with generic pooled bullets")


func test_breaker_shrapnel_pool_activate_applies_damage_and_speed_atomically() -> void:
	var shrapnel := preload("res://scripts/projectiles/breaker_shrapnel.gd").new()
	add_child(shrapnel)

	shrapnel.pool_deactivate(false)
	shrapnel.pool_activate(Vector2(12, 34), Vector2.DOWN, 12345, 0.25, 2100.0)

	assert_eq(shrapnel.global_position, Vector2(12, 34),
		"Activation should place pooled breaker shrapnel at the spawn position")
	assert_eq(shrapnel.direction, Vector2.DOWN,
		"Activation should set the travel direction")
	assert_eq(shrapnel.source_id, 12345,
		"Activation should set the shooter/source id")
	assert_almost_eq(shrapnel.damage, 0.25, 0.001,
		"Activation should set damage before the shard can process")
	assert_almost_eq(shrapnel.speed, 2100.0, 0.001,
		"Activation should set speed before the shard can process")
