extends Node
## Autoload singleton for managing projectile object pools.
##
## Provides centralized pooling for bullets and shrapnel to optimize
## bullet-hell scenarios by reducing instantiation/destruction overhead.
##
## Issue #724: Optimization for bullet-hell situations without reducing
## quantity or functionality.
##
## Key features:
## - Pre-allocates projectile instances at game start
## - Reuses projectiles instead of instantiate/queue_free cycles
## - Tracks active projectile counts for monitoring
## - Supports dynamic pool expansion when needed
## - Provides debug statistics for performance tuning

## Signal emitted when pool statistics change significantly.
signal pool_stats_changed(stats: Dictionary)

## Minimum pool size for each projectile type (preallocated at startup).
const MIN_BULLET_POOL_SIZE: int = 64
const MIN_SHRAPNEL_POOL_SIZE: int = 32
const MIN_BREAKER_SHRAPNEL_POOL_SIZE: int = 60

## Maximum pool size limits to prevent memory issues.
## -1 for unlimited (not recommended for production).
const MAX_BULLET_POOL_SIZE: int = 256
const MAX_SHRAPNEL_POOL_SIZE: int = 128
const MAX_BREAKER_SHRAPNEL_POOL_SIZE: int = 120

## Scene paths for projectile types.
const BULLET_SCENE_PATH: String = "res://scenes/projectiles/Bullet.tscn"
const SHRAPNEL_SCENE_PATH: String = "res://scenes/projectiles/Shrapnel.tscn"
const BREAKER_SHRAPNEL_SCENE_PATH: String = "res://scenes/projectiles/BreakerShrapnel.tscn"

## Preloaded projectile scenes.
var _bullet_scene: PackedScene = null
var _shrapnel_scene: PackedScene = null
var _breaker_shrapnel_scene: PackedScene = null

## Object pools for each projectile type.
## Inactive projectiles waiting to be reused.
var _bullet_pool: Array[Area2D] = []
var _shrapnel_pool: Array[Area2D] = []
var _breaker_shrapnel_pool: Array[Area2D] = []

## Active projectile tracking.
## These are currently in the scene and will be returned to pool on deactivation.
var _active_bullets: Array[Area2D] = []
var _active_shrapnel: Array[Area2D] = []
var _active_breaker_shrapnel: Array[Area2D] = []

## Statistics for monitoring.
var _total_bullets_created: int = 0
var _total_shrapnel_created: int = 0
var _total_breaker_shrapnel_created: int = 0
var _bullets_reused: int = 0
var _shrapnel_reused: int = 0
var _breaker_shrapnel_reused: int = 0

## Enable debug logging for pool operations.
var _debug_logging: bool = false

## Timer for periodic cleanup of oversized pools.
var _cleanup_timer: float = 0.0
const CLEANUP_INTERVAL: float = 10.0


func _ready() -> void:
	_load_projectile_scenes()
	_create_initial_pools()


func _process(delta: float) -> void:
	# Periodic cleanup of inactive projectiles exceeding minimum pool sizes
	_cleanup_timer += delta
	if _cleanup_timer >= CLEANUP_INTERVAL:
		_cleanup_timer = 0.0
		_cleanup_excess_pool_items()


## Loads the projectile scenes for instantiation.
func _load_projectile_scenes() -> void:
	if ResourceLoader.exists(BULLET_SCENE_PATH):
		_bullet_scene = load(BULLET_SCENE_PATH)
	else:
		push_warning("[ProjectilePool] Bullet scene not found: %s" % BULLET_SCENE_PATH)

	if ResourceLoader.exists(SHRAPNEL_SCENE_PATH):
		_shrapnel_scene = load(SHRAPNEL_SCENE_PATH)
	else:
		push_warning("[ProjectilePool] Shrapnel scene not found: %s" % SHRAPNEL_SCENE_PATH)

	if ResourceLoader.exists(BREAKER_SHRAPNEL_SCENE_PATH):
		_breaker_shrapnel_scene = load(BREAKER_SHRAPNEL_SCENE_PATH)
	else:
		push_warning("[ProjectilePool] Breaker shrapnel scene not found: %s" % BREAKER_SHRAPNEL_SCENE_PATH)


## Creates initial pools with minimum sizes.
func _create_initial_pools() -> void:
	for i in range(MIN_BULLET_POOL_SIZE):
		var bullet := _create_bullet_instance()
		if bullet:
			_bullet_pool.append(bullet)

	for i in range(MIN_SHRAPNEL_POOL_SIZE):
		var shrapnel := _create_shrapnel_instance()
		if shrapnel:
			_shrapnel_pool.append(shrapnel)

	for i in range(MIN_BREAKER_SHRAPNEL_POOL_SIZE):
		var breaker := _create_breaker_shrapnel_instance()
		if breaker:
			_breaker_shrapnel_pool.append(breaker)

	if _debug_logging:
		print("[ProjectilePool] Initialized pools - Bullets: %d, Shrapnel: %d, BreakerShrapnel: %d" % [
			_bullet_pool.size(), _shrapnel_pool.size(), _breaker_shrapnel_pool.size()])


## Creates a new bullet instance in deactivated state.
func _create_bullet_instance() -> Area2D:
	if _bullet_scene == null:
		return null

	var bullet := _bullet_scene.instantiate() as Area2D
	if bullet == null:
		return null

	_total_bullets_created += 1

	# Keep as child of pool manager for scene tree stability
	add_child(bullet)

	# Deactivate the bullet
	_deactivate_projectile(bullet)

	return bullet


## Creates a new shrapnel instance in deactivated state.
func _create_shrapnel_instance() -> Area2D:
	if _shrapnel_scene == null:
		return null

	var shrapnel := _shrapnel_scene.instantiate() as Area2D
	if shrapnel == null:
		return null

	_total_shrapnel_created += 1

	add_child(shrapnel)
	_deactivate_projectile(shrapnel)

	return shrapnel


## Creates a new breaker shrapnel instance in deactivated state.
func _create_breaker_shrapnel_instance() -> Area2D:
	if _breaker_shrapnel_scene == null:
		return null

	var breaker := _breaker_shrapnel_scene.instantiate() as Area2D
	if breaker == null:
		return null

	_total_breaker_shrapnel_created += 1

	add_child(breaker)
	_deactivate_projectile(breaker)

	return breaker


## Deactivates a projectile for pooling.
## Hides it and disables physics processing.
func _deactivate_projectile(projectile: Area2D) -> void:
	projectile.visible = false
	projectile.set_physics_process(false)
	projectile.set_process(false)
	projectile.monitoring = false
	projectile.monitorable = false

	# Disable collision shape if present
	var collision := projectile.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision:
		collision.disabled = true


## Activates a projectile from the pool.
## Makes it visible and enables physics processing.
func _activate_projectile(projectile: Area2D) -> void:
	projectile.visible = true
	projectile.set_physics_process(true)
	projectile.set_process(true)
	projectile.monitoring = true
	projectile.monitorable = true

	# Enable collision shape if present
	var collision := projectile.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision:
		collision.disabled = false


## Gets a bullet from the pool or creates a new one if needed.
## Returns null if pool is at maximum capacity.
## @param parent: The node to reparent the bullet to (usually current scene).
func get_bullet(parent: Node = null) -> Area2D:
	var bullet: Area2D = null

	if _bullet_pool.size() > 0:
		bullet = _bullet_pool.pop_back()
		_bullets_reused += 1
	elif MAX_BULLET_POOL_SIZE == -1 or _total_bullets_created < MAX_BULLET_POOL_SIZE:
		bullet = _create_bullet_instance()
	else:
		if _debug_logging:
			print("[ProjectilePool] Bullet pool exhausted (max: %d)" % MAX_BULLET_POOL_SIZE)
		return null

	if bullet == null:
		return null

	# Reset bullet state
	_reset_bullet(bullet)

	# Reparent to the specified parent (or current scene)
	if parent:
		bullet.reparent(parent)
	else:
		var scene := get_tree().current_scene
		if scene:
			bullet.reparent(scene)

	_activate_projectile(bullet)
	_active_bullets.append(bullet)

	if _debug_logging:
		print("[ProjectilePool] Bullet acquired - Active: %d, Pool: %d" % [
			_active_bullets.size(), _bullet_pool.size()])

	return bullet


## Gets a shrapnel from the pool or creates a new one if needed.
## @param parent: The node to reparent the shrapnel to.
func get_shrapnel(parent: Node = null) -> Area2D:
	var shrapnel: Area2D = null

	if _shrapnel_pool.size() > 0:
		shrapnel = _shrapnel_pool.pop_back()
		_shrapnel_reused += 1
	elif MAX_SHRAPNEL_POOL_SIZE == -1 or _total_shrapnel_created < MAX_SHRAPNEL_POOL_SIZE:
		shrapnel = _create_shrapnel_instance()
	else:
		if _debug_logging:
			print("[ProjectilePool] Shrapnel pool exhausted (max: %d)" % MAX_SHRAPNEL_POOL_SIZE)
		return null

	if shrapnel == null:
		return null

	_reset_shrapnel(shrapnel)

	if parent:
		shrapnel.reparent(parent)
	else:
		var scene := get_tree().current_scene
		if scene:
			shrapnel.reparent(scene)

	_activate_projectile(shrapnel)
	_active_shrapnel.append(shrapnel)

	return shrapnel


## Gets a breaker shrapnel from the pool or creates a new one if needed.
## @param parent: The node to reparent the shrapnel to.
func get_breaker_shrapnel(parent: Node = null) -> Area2D:
	var breaker: Area2D = null

	if _breaker_shrapnel_pool.size() > 0:
		breaker = _breaker_shrapnel_pool.pop_back()
		_breaker_shrapnel_reused += 1
	elif MAX_BREAKER_SHRAPNEL_POOL_SIZE == -1 or _total_breaker_shrapnel_created < MAX_BREAKER_SHRAPNEL_POOL_SIZE:
		breaker = _create_breaker_shrapnel_instance()
	else:
		if _debug_logging:
			print("[ProjectilePool] Breaker shrapnel pool exhausted (max: %d)" % MAX_BREAKER_SHRAPNEL_POOL_SIZE)
		return null

	if breaker == null:
		return null

	_reset_breaker_shrapnel(breaker)

	if parent:
		breaker.reparent(parent)
	else:
		var scene := get_tree().current_scene
		if scene:
			breaker.reparent(scene)

	_activate_projectile(breaker)
	_active_breaker_shrapnel.append(breaker)

	return breaker


## Returns a bullet to the pool for reuse.
## Call this instead of queue_free() on pooled bullets.
func return_bullet(bullet: Area2D) -> void:
	if bullet == null or not is_instance_valid(bullet):
		return

	# Remove from active list
	var idx := _active_bullets.find(bullet)
	if idx >= 0:
		_active_bullets.remove_at(idx)

	# Deactivate and return to pool
	_deactivate_projectile(bullet)
	bullet.reparent(self)
	_bullet_pool.append(bullet)

	if _debug_logging:
		print("[ProjectilePool] Bullet returned - Active: %d, Pool: %d" % [
			_active_bullets.size(), _bullet_pool.size()])


## Returns a shrapnel to the pool for reuse.
func return_shrapnel(shrapnel: Area2D) -> void:
	if shrapnel == null or not is_instance_valid(shrapnel):
		return

	var idx := _active_shrapnel.find(shrapnel)
	if idx >= 0:
		_active_shrapnel.remove_at(idx)

	_deactivate_projectile(shrapnel)
	shrapnel.reparent(self)
	_shrapnel_pool.append(shrapnel)


## Returns a breaker shrapnel to the pool for reuse.
func return_breaker_shrapnel(breaker: Area2D) -> void:
	if breaker == null or not is_instance_valid(breaker):
		return

	var idx := _active_breaker_shrapnel.find(breaker)
	if idx >= 0:
		_active_breaker_shrapnel.remove_at(idx)

	_deactivate_projectile(breaker)
	breaker.reparent(self)
	_breaker_shrapnel_pool.append(breaker)


## Resets a bullet to its default state for reuse.
func _reset_bullet(bullet: Area2D) -> void:
	# Reset position and rotation
	bullet.position = Vector2.ZERO
	bullet.rotation = 0.0

	# Reset bullet-specific properties
	if bullet.has_method("reset_for_pool"):
		bullet.reset_for_pool()
	else:
		# Fallback: reset common properties directly
		bullet.set("direction", Vector2.RIGHT)
		bullet.set("speed", 2500.0)
		bullet.set("damage", 1.0)
		bullet.set("damage_multiplier", 1.0)
		bullet.set("shooter_id", -1)
		bullet.set("shooter_position", Vector2.ZERO)
		bullet.set("stun_duration", 0.0)
		bullet.set("homing_enabled", false)
		bullet.set("is_breaker_bullet", false)
		bullet.set("caliber_data", null)
		bullet.set("_time_alive", 0.0)
		bullet.set("_ricochet_count", 0)
		bullet.set("_has_ricocheted", false)
		bullet.set("_has_penetrated", false)
		bullet.set("_is_penetrating", false)
		bullet.set("_penetrating_body", null)
		bullet.set("_penetration_distance_traveled", 0.0)
		bullet.set("_distance_since_ricochet", 0.0)

		# Clear trail
		var pos_history = bullet.get("_position_history")
		if pos_history is Array:
			pos_history.clear()

		var trail = bullet.get("_trail")
		if trail is Line2D:
			trail.clear_points()


## Resets a shrapnel to its default state for reuse.
func _reset_shrapnel(shrapnel: Area2D) -> void:
	shrapnel.position = Vector2.ZERO
	shrapnel.rotation = 0.0

	if shrapnel.has_method("reset_for_pool"):
		shrapnel.reset_for_pool()
	else:
		shrapnel.set("direction", Vector2.RIGHT)
		shrapnel.set("speed", 5000.0)
		shrapnel.set("damage", 1)
		shrapnel.set("source_id", -1)
		shrapnel.set("thrower_id", -1)
		shrapnel.set("_time_alive", 0.0)
		shrapnel.set("_ricochet_count", 0)

		var pos_history = shrapnel.get("_position_history")
		if pos_history is Array:
			pos_history.clear()

		var trail = shrapnel.get("_trail")
		if trail is Line2D:
			trail.clear_points()


## Resets a breaker shrapnel to its default state for reuse.
func _reset_breaker_shrapnel(breaker: Area2D) -> void:
	breaker.position = Vector2.ZERO
	breaker.rotation = 0.0

	if breaker.has_method("reset_for_pool"):
		breaker.reset_for_pool()
	else:
		breaker.set("direction", Vector2.RIGHT)
		breaker.set("speed", 1800.0)
		breaker.set("damage", 0.1)
		breaker.set("source_id", -1)
		breaker.set("_time_alive", 0.0)

		var pos_history = breaker.get("_position_history")
		if pos_history is Array:
			pos_history.clear()

		var trail = breaker.get("_trail")
		if trail is Line2D:
			trail.clear_points()


## Cleans up excess pool items that exceed minimum pool sizes.
## Called periodically to prevent memory bloat.
func _cleanup_excess_pool_items() -> void:
	# Clean up excess bullets
	while _bullet_pool.size() > MIN_BULLET_POOL_SIZE * 2:
		var bullet := _bullet_pool.pop_back()
		if bullet and is_instance_valid(bullet):
			bullet.queue_free()

	# Clean up excess shrapnel
	while _shrapnel_pool.size() > MIN_SHRAPNEL_POOL_SIZE * 2:
		var shrapnel := _shrapnel_pool.pop_back()
		if shrapnel and is_instance_valid(shrapnel):
			shrapnel.queue_free()

	# Clean up excess breaker shrapnel
	while _breaker_shrapnel_pool.size() > MIN_BREAKER_SHRAPNEL_POOL_SIZE * 2:
		var breaker := _breaker_shrapnel_pool.pop_back()
		if breaker and is_instance_valid(breaker):
			breaker.queue_free()


# ============================================================================
# Statistics and Debug Methods
# ============================================================================


## Returns current pool statistics for monitoring.
func get_stats() -> Dictionary:
	return {
		"bullets": {
			"active": _active_bullets.size(),
			"pooled": _bullet_pool.size(),
			"total_created": _total_bullets_created,
			"reused": _bullets_reused,
			"reuse_rate": _calculate_reuse_rate(_bullets_reused, _total_bullets_created)
		},
		"shrapnel": {
			"active": _active_shrapnel.size(),
			"pooled": _shrapnel_pool.size(),
			"total_created": _total_shrapnel_created,
			"reused": _shrapnel_reused,
			"reuse_rate": _calculate_reuse_rate(_shrapnel_reused, _total_shrapnel_created)
		},
		"breaker_shrapnel": {
			"active": _active_breaker_shrapnel.size(),
			"pooled": _breaker_shrapnel_pool.size(),
			"total_created": _total_breaker_shrapnel_created,
			"reused": _breaker_shrapnel_reused,
			"reuse_rate": _calculate_reuse_rate(_breaker_shrapnel_reused, _total_breaker_shrapnel_created)
		}
	}


## Calculates the reuse rate as a percentage.
func _calculate_reuse_rate(reused: int, total: int) -> float:
	if total == 0:
		return 0.0
	var total_uses := total + reused
	return (float(reused) / float(total_uses)) * 100.0


## Returns the total count of active projectiles.
func get_active_count() -> int:
	return _active_bullets.size() + _active_shrapnel.size() + _active_breaker_shrapnel.size()


## Returns the total count of pooled (inactive) projectiles.
func get_pooled_count() -> int:
	return _bullet_pool.size() + _shrapnel_pool.size() + _breaker_shrapnel_pool.size()


## Enables or disables debug logging.
func set_debug_logging(enabled: bool) -> void:
	_debug_logging = enabled


## Returns whether the bullet pool has available capacity.
func has_bullet_capacity() -> bool:
	return _bullet_pool.size() > 0 or MAX_BULLET_POOL_SIZE == -1 or _total_bullets_created < MAX_BULLET_POOL_SIZE


## Returns whether the shrapnel pool has available capacity.
func has_shrapnel_capacity() -> bool:
	return _shrapnel_pool.size() > 0 or MAX_SHRAPNEL_POOL_SIZE == -1 or _total_shrapnel_created < MAX_SHRAPNEL_POOL_SIZE


## Returns whether the breaker shrapnel pool has available capacity.
func has_breaker_shrapnel_capacity() -> bool:
	return _breaker_shrapnel_pool.size() > 0 or MAX_BREAKER_SHRAPNEL_POOL_SIZE == -1 or _total_breaker_shrapnel_created < MAX_BREAKER_SHRAPNEL_POOL_SIZE


## Prints detailed pool statistics to the console.
func print_stats() -> void:
	var stats := get_stats()
	print("=== ProjectilePool Statistics ===")
	print("Bullets: %d active, %d pooled, %d total created, %.1f%% reuse rate" % [
		stats.bullets.active, stats.bullets.pooled, stats.bullets.total_created, stats.bullets.reuse_rate])
	print("Shrapnel: %d active, %d pooled, %d total created, %.1f%% reuse rate" % [
		stats.shrapnel.active, stats.shrapnel.pooled, stats.shrapnel.total_created, stats.shrapnel.reuse_rate])
	print("Breaker Shrapnel: %d active, %d pooled, %d total created, %.1f%% reuse rate" % [
		stats.breaker_shrapnel.active, stats.breaker_shrapnel.pooled, stats.breaker_shrapnel.total_created, stats.breaker_shrapnel.reuse_rate])
	print("=================================")
