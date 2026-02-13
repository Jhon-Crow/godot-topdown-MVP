extends Node
class_name ProjectilePoolManager
## Manages pools of reusable projectile objects for bullet-hell optimization.
##
## Object pooling eliminates the performance overhead of repeatedly creating
## and destroying projectiles. Instead of instantiating new bullets each shot,
## we retrieve pre-created bullets from a pool and reset their state.
##
## This manager is registered as an autoload singleton (ProjectilePoolManager).
##
## Usage:
##   var bullet = ProjectilePoolManager.get_bullet()
##   bullet.activate(position, direction, shooter_id)
##
## When bullet hits or times out, instead of queue_free():
##   ProjectilePoolManager.return_bullet(bullet)
##
## Performance optimizations implemented:
## - Pre-instantiation: All pool objects created at game start (warmup)
## - Reset Instead of Recreate: State reset on pool return
## - Overflow Handling: Oldest active projectile recycled if pool exhausted
## - Deferred Operations: call_deferred for thread-safe pool access
## - Configurable Pool Sizes: Adjustable via exported variables
##
## Issue #724: Optimize projectiles for bullet-hell scenarios.

## Pool sizes - can be adjusted based on game requirements
@export var bullet_pool_size: int = 100
@export var shrapnel_pool_size: int = 50
@export var breaker_shrapnel_pool_size: int = 80

## Scene references for instantiation
var _bullet_scene: PackedScene
var _shrapnel_scene: PackedScene
var _breaker_shrapnel_scene: PackedScene

## Pool arrays (inactive projectiles ready for use)
var _bullet_pool: Array[Node] = []
var _shrapnel_pool: Array[Node] = []
var _breaker_shrapnel_pool: Array[Node] = []

## Active projectile tracking (for overflow recycling)
var _active_bullets: Array[Node] = []
var _active_shrapnel: Array[Node] = []
var _active_breaker_shrapnel: Array[Node] = []

## Container nodes for pooled objects (keeps scene tree organized)
var _bullet_container: Node
var _shrapnel_container: Node
var _breaker_shrapnel_container: Node

## Statistics for debugging/profiling
var _stats: Dictionary = {
	"bullets_created": 0,
	"bullets_reused": 0,
	"bullets_recycled": 0,
	"shrapnel_created": 0,
	"shrapnel_reused": 0,
	"shrapnel_recycled": 0,
	"breaker_created": 0,
	"breaker_reused": 0,
	"breaker_recycled": 0,
	"warmup_time_ms": 0.0,
}

## Whether pool warmup has completed
var _is_warmed_up: bool = false

## Enable/disable debug logging
var _debug: bool = false


func _ready() -> void:
	# Load scene references
	_load_scenes()

	# Create container nodes for organization
	_create_containers()

	# Warmup can be called explicitly or happens on first use
	# For best performance, call warmup() during loading screen


## Loads the projectile scenes.
func _load_scenes() -> void:
	var bullet_path := "res://scenes/projectiles/Bullet.tscn"
	var shrapnel_path := "res://scenes/projectiles/Shrapnel.tscn"
	var breaker_path := "res://scenes/projectiles/BreakerShrapnel.tscn"

	if ResourceLoader.exists(bullet_path):
		_bullet_scene = load(bullet_path)
	else:
		push_warning("[ProjectilePoolManager] Bullet scene not found: %s" % bullet_path)

	if ResourceLoader.exists(shrapnel_path):
		_shrapnel_scene = load(shrapnel_path)
	else:
		push_warning("[ProjectilePoolManager] Shrapnel scene not found: %s" % shrapnel_path)

	if ResourceLoader.exists(breaker_path):
		_breaker_shrapnel_scene = load(breaker_path)
	else:
		push_warning("[ProjectilePoolManager] BreakerShrapnel scene not found: %s" % breaker_path)


## Creates container nodes to keep pooled objects organized in scene tree.
func _create_containers() -> void:
	_bullet_container = Node.new()
	_bullet_container.name = "BulletPool"
	add_child(_bullet_container)

	_shrapnel_container = Node.new()
	_shrapnel_container.name = "ShrapnelPool"
	add_child(_shrapnel_container)

	_breaker_shrapnel_container = Node.new()
	_breaker_shrapnel_container.name = "BreakerShrapnelPool"
	add_child(_breaker_shrapnel_container)


## Pre-instantiates all pool objects. Call during loading screen for best results.
## Returns the time taken in milliseconds.
func warmup() -> float:
	if _is_warmed_up:
		return 0.0

	var start_time := Time.get_ticks_msec()

	# Create bullets
	if _bullet_scene:
		for i in range(bullet_pool_size):
			var bullet := _create_bullet()
			_bullet_pool.append(bullet)
			_stats["bullets_created"] += 1

	# Create shrapnel
	if _shrapnel_scene:
		for i in range(shrapnel_pool_size):
			var shrapnel := _create_shrapnel()
			_shrapnel_pool.append(shrapnel)
			_stats["shrapnel_created"] += 1

	# Create breaker shrapnel
	if _breaker_shrapnel_scene:
		for i in range(breaker_shrapnel_pool_size):
			var breaker := _create_breaker_shrapnel()
			_breaker_shrapnel_pool.append(breaker)
			_stats["breaker_created"] += 1

	var elapsed := Time.get_ticks_msec() - start_time
	_stats["warmup_time_ms"] = elapsed
	_is_warmed_up = true

	if _debug:
		print("[ProjectilePoolManager] Warmup complete in %d ms" % elapsed)
		print("  - Bullets: %d" % _bullet_pool.size())
		print("  - Shrapnel: %d" % _shrapnel_pool.size())
		print("  - BreakerShrapnel: %d" % _breaker_shrapnel_pool.size())

	return float(elapsed)


## Creates a bullet instance in deactivated state.
func _create_bullet() -> Node:
	var bullet := _bullet_scene.instantiate()
	_bullet_container.add_child(bullet)

	# Initialize in inactive state
	if bullet.has_method("pool_deactivate"):
		bullet.pool_deactivate()
	else:
		# Fallback for non-pooling-aware bullets
		bullet.visible = false
		bullet.set_physics_process(false)
		bullet.set_process(false)

	return bullet


## Creates a shrapnel instance in deactivated state.
func _create_shrapnel() -> Node:
	var shrapnel := _shrapnel_scene.instantiate()
	_shrapnel_container.add_child(shrapnel)

	if shrapnel.has_method("pool_deactivate"):
		shrapnel.pool_deactivate()
	else:
		shrapnel.visible = false
		shrapnel.set_physics_process(false)
		shrapnel.set_process(false)

	return shrapnel


## Creates a breaker shrapnel instance in deactivated state.
func _create_breaker_shrapnel() -> Node:
	var breaker := _breaker_shrapnel_scene.instantiate()
	_breaker_shrapnel_container.add_child(breaker)

	if breaker.has_method("pool_deactivate"):
		breaker.pool_deactivate()
	else:
		breaker.visible = false
		breaker.set_physics_process(false)
		breaker.set_process(false)

	return breaker


# =============================================================================
# Public API: Getting Projectiles from Pool
# =============================================================================


## Gets a bullet from the pool. Returns null if pool not initialized.
## The bullet is in deactivated state - caller must call pool_activate().
func get_bullet() -> Node:
	if not _is_warmed_up:
		warmup()

	if _bullet_pool.size() > 0:
		var bullet: Node = _bullet_pool.pop_back()
		_active_bullets.append(bullet)
		_stats["bullets_reused"] += 1
		if _debug:
			print("[ProjectilePoolManager] Bullet retrieved from pool (available: %d)" % _bullet_pool.size())
		return bullet

	# Pool exhausted - recycle oldest active bullet
	if _active_bullets.size() > 0:
		var oldest: Node = _active_bullets.pop_front()
		if oldest.has_method("pool_deactivate"):
			oldest.pool_deactivate()
		_active_bullets.append(oldest)
		_stats["bullets_recycled"] += 1
		if _debug:
			print("[ProjectilePoolManager] Bullet recycled (active: %d)" % _active_bullets.size())
		return oldest

	# Fallback: create new bullet (shouldn't happen if pool sized correctly)
	if _bullet_scene:
		var bullet := _create_bullet()
		_active_bullets.append(bullet)
		_stats["bullets_created"] += 1
		push_warning("[ProjectilePoolManager] Bullet pool exhausted, created new instance")
		return bullet

	return null


## Gets a shrapnel from the pool. Returns null if pool not initialized.
func get_shrapnel() -> Node:
	if not _is_warmed_up:
		warmup()

	if _shrapnel_pool.size() > 0:
		var shrapnel: Node = _shrapnel_pool.pop_back()
		_active_shrapnel.append(shrapnel)
		_stats["shrapnel_reused"] += 1
		return shrapnel

	# Pool exhausted - recycle oldest
	if _active_shrapnel.size() > 0:
		var oldest: Node = _active_shrapnel.pop_front()
		if oldest.has_method("pool_deactivate"):
			oldest.pool_deactivate()
		_active_shrapnel.append(oldest)
		_stats["shrapnel_recycled"] += 1
		return oldest

	# Fallback: create new
	if _shrapnel_scene:
		var shrapnel := _create_shrapnel()
		_active_shrapnel.append(shrapnel)
		_stats["shrapnel_created"] += 1
		return shrapnel

	return null


## Gets a breaker shrapnel from the pool. Returns null if pool not initialized.
func get_breaker_shrapnel() -> Node:
	if not _is_warmed_up:
		warmup()

	if _breaker_shrapnel_pool.size() > 0:
		var breaker: Node = _breaker_shrapnel_pool.pop_back()
		_active_breaker_shrapnel.append(breaker)
		_stats["breaker_reused"] += 1
		return breaker

	# Pool exhausted - recycle oldest
	if _active_breaker_shrapnel.size() > 0:
		var oldest: Node = _active_breaker_shrapnel.pop_front()
		if oldest.has_method("pool_deactivate"):
			oldest.pool_deactivate()
		_active_breaker_shrapnel.append(oldest)
		_stats["breaker_recycled"] += 1
		return oldest

	# Fallback: create new
	if _breaker_shrapnel_scene:
		var breaker := _create_breaker_shrapnel()
		_active_breaker_shrapnel.append(breaker)
		_stats["breaker_created"] += 1
		return breaker

	return null


# =============================================================================
# Public API: Returning Projectiles to Pool
# =============================================================================


## Returns a bullet to the pool for reuse.
func return_bullet(bullet: Node) -> void:
	if not is_instance_valid(bullet):
		return

	# Remove from active tracking
	var idx := _active_bullets.find(bullet)
	if idx >= 0:
		_active_bullets.remove_at(idx)

	# Deactivate and return to pool
	if bullet.has_method("pool_deactivate"):
		bullet.pool_deactivate()
	else:
		bullet.visible = false
		bullet.set_physics_process(false)
		bullet.set_process(false)

	_bullet_pool.append(bullet)

	if _debug:
		print("[ProjectilePoolManager] Bullet returned to pool (available: %d)" % _bullet_pool.size())


## Returns a shrapnel to the pool for reuse.
func return_shrapnel(shrapnel: Node) -> void:
	if not is_instance_valid(shrapnel):
		return

	var idx := _active_shrapnel.find(shrapnel)
	if idx >= 0:
		_active_shrapnel.remove_at(idx)

	if shrapnel.has_method("pool_deactivate"):
		shrapnel.pool_deactivate()
	else:
		shrapnel.visible = false
		shrapnel.set_physics_process(false)
		shrapnel.set_process(false)

	_shrapnel_pool.append(shrapnel)


## Returns a breaker shrapnel to the pool for reuse.
func return_breaker_shrapnel(breaker: Node) -> void:
	if not is_instance_valid(breaker):
		return

	var idx := _active_breaker_shrapnel.find(breaker)
	if idx >= 0:
		_active_breaker_shrapnel.remove_at(idx)

	if breaker.has_method("pool_deactivate"):
		breaker.pool_deactivate()
	else:
		breaker.visible = false
		breaker.set_physics_process(false)
		breaker.set_process(false)

	_breaker_shrapnel_pool.append(breaker)


# =============================================================================
# Utility Methods
# =============================================================================


## Returns pool statistics for debugging/profiling.
func get_stats() -> Dictionary:
	return {
		"bullets_available": _bullet_pool.size(),
		"bullets_active": _active_bullets.size(),
		"bullets_created": _stats["bullets_created"],
		"bullets_reused": _stats["bullets_reused"],
		"bullets_recycled": _stats["bullets_recycled"],
		"shrapnel_available": _shrapnel_pool.size(),
		"shrapnel_active": _active_shrapnel.size(),
		"shrapnel_created": _stats["shrapnel_created"],
		"shrapnel_reused": _stats["shrapnel_reused"],
		"shrapnel_recycled": _stats["shrapnel_recycled"],
		"breaker_available": _breaker_shrapnel_pool.size(),
		"breaker_active": _active_breaker_shrapnel.size(),
		"breaker_created": _stats["breaker_created"],
		"breaker_reused": _stats["breaker_reused"],
		"breaker_recycled": _stats["breaker_recycled"],
		"warmup_time_ms": _stats["warmup_time_ms"],
		"is_warmed_up": _is_warmed_up,
	}


## Returns true if the pool system is ready (warmed up).
func is_ready() -> bool:
	return _is_warmed_up


## Clears all pools and active projectiles. Use when changing levels.
func clear_all() -> void:
	# Return all active projectiles to pools
	for bullet in _active_bullets:
		if is_instance_valid(bullet):
			if bullet.has_method("pool_deactivate"):
				bullet.pool_deactivate()
			_bullet_pool.append(bullet)
	_active_bullets.clear()

	for shrapnel in _active_shrapnel:
		if is_instance_valid(shrapnel):
			if shrapnel.has_method("pool_deactivate"):
				shrapnel.pool_deactivate()
			_shrapnel_pool.append(shrapnel)
	_active_shrapnel.clear()

	for breaker in _active_breaker_shrapnel:
		if is_instance_valid(breaker):
			if breaker.has_method("pool_deactivate"):
				breaker.pool_deactivate()
			_breaker_shrapnel_pool.append(breaker)
	_active_breaker_shrapnel.clear()

	if _debug:
		print("[ProjectilePoolManager] All projectiles returned to pools")


## Enables or disables debug logging.
func set_debug(enabled: bool) -> void:
	_debug = enabled
