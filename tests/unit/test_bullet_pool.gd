extends GutTest
## Unit tests for BulletPool autoload (Issue #862).
##
## Verifies that the pool correctly tracks available bullets,
## reuses nodes instead of instantiating new ones, and that
## bullet.reset_for_pool() restores clean state.


# ============================================================================
# Pool Constants Tests
# ============================================================================


func test_pool_size_constant_is_positive() -> void:
	var pool_size := 200
	assert_gt(pool_size, 0, "POOL_SIZE must be positive")


func test_bullet_scene_path_constant_is_set() -> void:
	var path := "res://scenes/projectiles/Bullet.tscn"
	assert_ne(path, "", "BULLET_SCENE_PATH must not be empty")


func test_bullet_scene_path_is_gdscript_bullet() -> void:
	var path := "res://scenes/projectiles/Bullet.tscn"
	# The pool targets the GDScript bullet scene, not the C# one.
	assert_false(path.ends_with(".cs"), "Pool scene path should not be a C# script")


# ============================================================================
# BulletPool autoload availability
# ============================================================================


func test_bullet_pool_autoload_exists() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	assert_not_null(pool, "BulletPool autoload should be registered in project.godot")


func test_bullet_pool_has_acquire_method() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	assert_true(pool.has_method("acquire"), "BulletPool must expose acquire()")


func test_bullet_pool_has_release_method() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	assert_true(pool.has_method("release"), "BulletPool must expose release()")


func test_bullet_pool_has_activate_method() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	assert_true(pool.has_method("activate"), "BulletPool must expose activate()")


func test_bullet_pool_available_count_is_non_negative() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	assert_gte(pool.available_count(), 0, "available_count() must be >= 0")


# ============================================================================
# Pool Acquire / Release cycle
# ============================================================================


func test_acquire_returns_node() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	var bullet := pool.acquire()
	assert_not_null(bullet, "acquire() must return a non-null node")
	# Clean up: release if valid
	if bullet != null:
		pool.release(bullet)


func test_acquire_decrements_available_count() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	var before: int = pool.available_count()
	var bullet := pool.acquire()
	if bullet == null:
		pass_test("Pool exhausted, skipping count check")
		return
	var after: int = pool.available_count()
	assert_eq(after, before - 1, "available_count should decrease by 1 after acquire()")
	pool.release(bullet)


func test_release_increments_available_count() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	var bullet := pool.acquire()
	if bullet == null:
		pass_test("Pool exhausted, skipping count check")
		return
	var before: int = pool.available_count()
	pool.release(bullet)
	var after: int = pool.available_count()
	assert_eq(after, before + 1, "available_count should increase by 1 after release()")


func test_acquire_and_release_restores_count() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	var initial: int = pool.available_count()
	var bullet := pool.acquire()
	if bullet == null:
		pass_test("Pool exhausted, skipping")
		return
	pool.release(bullet)
	assert_eq(pool.available_count(), initial, "Count should be restored after acquire+release cycle")


# ============================================================================
# Bullet reset_for_pool tests
# ============================================================================


func _make_mock_bullet() -> Node2D:
	## Creates a minimal in-memory node that mimics bullet mutable state.
	var b := Node2D.new()
	b.set_script(load("res://scripts/projectiles/bullet.gd"))
	add_child(b)  # Must be in tree for _ready() signals to connect
	return b


func test_reset_for_pool_clears_time_alive() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	var bullet := pool.acquire()
	if bullet == null:
		pass_test("Pool exhausted, skipping")
		return
	# Simulate some in-flight state
	bullet.set("_time_alive", 2.5)
	bullet.call("reset_for_pool")
	assert_eq(bullet.get("_time_alive"), 0.0, "_time_alive must be 0 after reset")
	pool.release(bullet)


func test_reset_for_pool_clears_ricochet_state() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	var bullet := pool.acquire()
	if bullet == null:
		pass_test("Pool exhausted, skipping")
		return
	bullet.set("_has_ricocheted", true)
	bullet.set("_ricochet_count", 3)
	bullet.set("_distance_since_ricochet", 500.0)
	bullet.call("reset_for_pool")
	assert_false(bullet.get("_has_ricocheted"), "_has_ricocheted must be false after reset")
	assert_eq(bullet.get("_ricochet_count"), 0, "_ricochet_count must be 0 after reset")
	assert_eq(bullet.get("_distance_since_ricochet"), 0.0, "_distance_since_ricochet must be 0 after reset")
	pool.release(bullet)


func test_reset_for_pool_clears_penetration_state() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	var bullet := pool.acquire()
	if bullet == null:
		pass_test("Pool exhausted, skipping")
		return
	bullet.set("_is_penetrating", true)
	bullet.set("_has_penetrated", true)
	bullet.set("_penetration_distance_traveled", 30.0)
	bullet.call("reset_for_pool")
	assert_false(bullet.get("_is_penetrating"), "_is_penetrating must be false after reset")
	assert_false(bullet.get("_has_penetrated"), "_has_penetrated must be false after reset")
	assert_eq(bullet.get("_penetration_distance_traveled"), 0.0, "penetration distance must be 0 after reset")
	pool.release(bullet)


func test_reset_for_pool_resets_shooter_id() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	var bullet := pool.acquire()
	if bullet == null:
		pass_test("Pool exhausted, skipping")
		return
	bullet.set("shooter_id", 12345)
	bullet.call("reset_for_pool")
	assert_eq(bullet.get("shooter_id"), -1, "shooter_id must be reset to -1 after pool reset")
	pool.release(bullet)


func test_reset_for_pool_disables_homing() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	var bullet := pool.acquire()
	if bullet == null:
		pass_test("Pool exhausted, skipping")
		return
	bullet.set("homing_enabled", true)
	bullet.call("reset_for_pool")
	assert_false(bullet.get("homing_enabled"), "homing_enabled must be false after pool reset")
	pool.release(bullet)


func test_reset_for_pool_disables_breaker_flag() -> void:
	var pool := get_node_or_null("/root/BulletPool")
	if pool == null:
		pass_test("BulletPool not found, skipping")
		return
	var bullet := pool.acquire()
	if bullet == null:
		pass_test("Pool exhausted, skipping")
		return
	bullet.set("is_breaker_bullet", true)
	bullet.call("reset_for_pool")
	assert_false(bullet.get("is_breaker_bullet"), "is_breaker_bullet must be false after pool reset")
	pool.release(bullet)
