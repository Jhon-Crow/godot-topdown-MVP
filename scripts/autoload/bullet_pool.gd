extends Node
## BulletPool — Autoload singleton for reusing bullet nodes (Issue #862).
##
## Instantiating and freeing Godot nodes has significant overhead due to
## scene-tree insertion/removal and physics-server registration.  In
## bullet-hell scenarios (many projectiles at once) this becomes the
## dominant CPU bottleneck.
##
## This pool pre-allocates a fixed set of GDScript bullet nodes, keeps
## them parked in the scene tree (process-disabled, hidden), and hands
## them out on demand.  When a bullet is "done" it calls
## BulletPool.release(bullet) instead of queue_free() and the node is
## immediately available for the next shot.
##
## Usage (shooter side):
##   var b := BulletPool.acquire()
##   b.global_position = spawn_pos
##   b.direction = dir
##   b.shooter_id = get_instance_id()
##   b.shooter_position = global_position
##   BulletPool.activate(b)
##
## Usage (bullet side – replaces every queue_free() call):
##   BulletPool.release(self)
##
## The pool size (POOL_SIZE) covers the worst-case simultaneous bullets.
## In a typical assault-rifle bullet-hell with 20 enemies firing at 10 Hz
## each, plus the player, a pool of 200 is sufficient (bullets live ~0.1–3 s).

## Number of bullet nodes to pre-allocate.
## 200 covers: 20 enemies × 10 rps × 1 s average lifetime = 200 concurrent bullets.
const POOL_SIZE: int = 200

## Path to the GDScript bullet scene.
const BULLET_SCENE_PATH: String = "res://scenes/projectiles/Bullet.tscn"

## Pre-loaded bullet PackedScene.
var _bullet_scene: PackedScene = null

## Free (idle) bullets ready to be handed out.
var _free_bullets: Array = []

## Parent node that holds all pooled bullets.
var _bullet_container: Node2D = null

## Whether the pool has been initialised.
var _initialised: bool = false

## Debug logging toggle (off by default to avoid I/O overhead – Issue #862).
var _debug: bool = false


func _ready() -> void:
	# Defer initialisation to after the first scene is loaded so that
	# get_tree().current_scene is available for container placement.
	call_deferred("_initialise_pool")


## Creates the pool.  Must be called after the scene tree is ready.
func _initialise_pool() -> void:
	if _initialised:
		return

	_bullet_scene = load(BULLET_SCENE_PATH) as PackedScene
	if _bullet_scene == null:
		push_warning("[BulletPool] Could not load bullet scene: " + BULLET_SCENE_PATH)
		return

	# Create an off-screen container node for idle bullets so they stay in
	# the tree (required for physics-server Area2D registration) but do not
	# participate in gameplay.
	_bullet_container = Node2D.new()
	_bullet_container.name = "BulletPoolContainer"
	# Disable processing on the container itself.
	_bullet_container.set_process(false)
	_bullet_container.set_physics_process(false)
	add_child(_bullet_container)

	for i in range(POOL_SIZE):
		var b: Node2D = _bullet_scene.instantiate() as Node2D
		if b == null:
			continue
		_bullet_container.add_child(b)
		_park(b)

	_initialised = true
	if _debug:
		print("[BulletPool] Initialised with %d bullets." % _free_bullets.size())


## Returns an idle bullet, or null when the pool is exhausted.
## The caller is responsible for setting position, direction, shooter_id,
## shooter_position and any optional fields, then calling activate().
func acquire() -> Node2D:
	if not _initialised:
		_initialise_pool()

	if _free_bullets.is_empty():
		# Pool exhausted: fall back to a fresh instance (no pooling benefit,
		# but gameplay is preserved).
		if _debug:
			push_warning("[BulletPool] Pool exhausted — spawning extra bullet.")
		if _bullet_scene:
			return _bullet_scene.instantiate() as Node2D
		return null

	var b: Node2D = _free_bullets.pop_back() as Node2D
	if not is_instance_valid(b):
		# Node was freed externally; try again recursively.
		return acquire()
	return b


## Moves the acquired bullet into the gameplay scene and enables it.
## Call this after setting all bullet properties.
## @param b: The bullet obtained from acquire().
## @param scene_root: The scene to parent it into (defaults to current_scene).
func activate(b: Node2D, scene_root: Node = null) -> void:
	if not is_instance_valid(b):
		return

	var target_root: Node = scene_root if scene_root else get_tree().current_scene
	if target_root == null:
		push_warning("[BulletPool] No scene root to activate bullet into.")
		_park(b)
		return

	# Re-parent from pool container to the gameplay scene.
	_bullet_container.remove_child(b)
	target_root.add_child(b)

	# Re-enable the bullet.
	b.set_physics_process(true)
	b.visible = true
	# Re-enable collision monitoring.
	if b is Area2D:
		(b as Area2D).monitoring = true
		(b as Area2D).monitorable = true

	if _debug:
		print("[BulletPool] Activated bullet. Free: %d" % _free_bullets.size())


## Returns a bullet to the pool.  Call this instead of queue_free().
## The bullet must have been obtained from this pool (or be a compatible node).
func release(b: Node2D) -> void:
	if not is_instance_valid(b):
		return

	# If this bullet was not allocated from the pool (overflow case), free it normally.
	if _free_bullets.size() >= POOL_SIZE:
		b.queue_free()
		return

	# Disable the bullet before parking.
	b.set_physics_process(false)
	b.visible = false
	if b is Area2D:
		(b as Area2D).monitoring = false
		(b as Area2D).monitorable = false

	# Reset bullet state so it is clean for the next use.
	if b.has_method("reset_for_pool"):
		b.reset_for_pool()

	# Move back to the pool container.
	var parent := b.get_parent()
	if parent != null and parent != _bullet_container:
		parent.remove_child(b)
		_bullet_container.add_child(b)
	elif parent == null:
		_bullet_container.add_child(b)

	_free_bullets.append(b)

	if _debug:
		print("[BulletPool] Released bullet. Free: %d" % _free_bullets.size())


## Returns the number of bullets currently available in the pool.
func available_count() -> int:
	return _free_bullets.size()


## Returns the total pool capacity.
func total_count() -> int:
	return POOL_SIZE


# -----------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------


## Parks (deactivates) a bullet node for idle storage.
func _park(b: Node2D) -> void:
	b.set_physics_process(false)
	b.visible = false
	if b is Area2D:
		(b as Area2D).monitoring = false
		(b as Area2D).monitorable = false
	if b.has_method("reset_for_pool"):
		b.reset_for_pool()
	_free_bullets.append(b)
