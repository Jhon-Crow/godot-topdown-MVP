extends Node2D
class_name IllusionEffect
## Visual-only illusion copy of an enemy (Issue #1353).
##
## Instead of spawning a real Enemy node (~50+ child nodes, full AI, physics, etc.),
## this creates a lightweight visual copy using only Sprite2D nodes that look
## identical to the original enemy. The illusion:
## - Is visually indistinguishable from the real enemy
## - Follows the original enemy with a fixed offset
## - Mirrors the original's facing direction
## - Fires phantom bullets (damage player only)
## - Has 1 HP (destroyed by any hit)
## - Disappears when the original enemy dies or after a timeout
## - Fades out in the last 3 seconds before expiry
##
## Performance: ~6 nodes per illusion vs ~50+ for a real Enemy clone.

## How long the illusion persists (seconds).
@export var illusion_duration: float = 20.0

## Offset from the original enemy.
@export var follow_offset: Vector2 = Vector2(80, 0)

## Interval between phantom shots (seconds).
@export var phantom_shoot_interval: float = 2.0

## Whether the illusion is still active.
var _is_alive: bool = true

## Reference to the original enemy being copied.
var _original_enemy: Node2D = null

## Time remaining before the illusion expires.
var _time_remaining: float = 0.0

## Timer for phantom shooting.
var _shoot_timer: float = 0.0

## The visual model node containing all sprites.
var _model: Node2D = null

## Shader material (unused — illusions are visually identical to originals).
var _shader_material: ShaderMaterial = null

## HitArea for bullet collision detection.
var _hit_area: Area2D = null

## Health (1 HP = one-shot).
var _health: int = 1

## Max total illusions allowed on the map at once.
const MAX_TOTAL_ILLUSIONS: int = 12

## Group name for tracking illusions.
const ILLUSION_GROUP: String = "illusion_effects"

## Bullet scene for phantom shots.
var _bullet_scene: PackedScene = null


func _ready() -> void:
	add_to_group(ILLUSION_GROUP)
	_time_remaining = illusion_duration
	_setup_hit_area()
	FileLogger.info("[IllusionEffect] Spawned at %s, offset=%s, duration=%.0fs" % [
		str(global_position), str(follow_offset), illusion_duration
	])


func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	# Check if original enemy is still alive
	if _original_enemy == null or not is_instance_valid(_original_enemy):
		_destroy()
		return
	if _original_enemy.has_method("is_alive") and not _original_enemy.is_alive():
		_destroy()
		return

	# Follow the original enemy with offset
	_update_position()

	# Mirror the original enemy's rotation
	rotation = _original_enemy.rotation

	# Mirror model flip
	if _model and _original_enemy.get("_enemy_model"):
		var orig_model: Node2D = _original_enemy.get("_enemy_model")
		if orig_model:
			_model.scale.y = orig_model.scale.y

	# Phantom shooting
	_shoot_timer += delta
	if _shoot_timer >= phantom_shoot_interval:
		_shoot_timer = 0.0
		_fire_phantom_bullet()

	# Duration countdown
	_time_remaining -= delta
	if _time_remaining <= 0.0:
		_destroy()
		return

	# Fade out in the last 3 seconds (modulate alpha)
	if _time_remaining < 3.0:
		modulate.a = _time_remaining / 3.0


## Initialize the illusion from an original enemy.
## Call this after instantiating and before adding to the scene tree.
func setup(original: Node2D, offset: Vector2) -> void:
	_original_enemy = original
	follow_offset = offset

	# Copy bullet scene from original enemy
	if original.get("bullet_scene"):
		_bullet_scene = original.bullet_scene

	# Create the visual model by copying sprite textures
	_create_visual_model(original)

	# Set initial position
	global_position = original.global_position + follow_offset.rotated(original.rotation)


## Create the visual model by copying sprite data from the original enemy.
## This creates only Sprite2D nodes (no physics, no AI, no components).
func _create_visual_model(original: Node2D) -> void:
	_model = Node2D.new()
	_model.name = "IllusionModel"
	add_child(_model)

	# Issue #1353: Illusion copies must be visually indistinguishable from originals.
	# No shader applied — sprites are copied with their original appearance.

	# Copy each sprite from the original's EnemyModel
	var orig_model: Node2D = original.get_node_or_null("EnemyModel")
	if orig_model == null:
		FileLogger.warning("[IllusionEffect] Original enemy has no EnemyModel node")
		return

	_copy_sprite_recursive(orig_model, _model)

	# Match original model scale
	if original.get("enemy_model_scale"):
		_model.scale = Vector2(original.enemy_model_scale, original.enemy_model_scale)
	elif orig_model.scale != Vector2.ONE:
		_model.scale = orig_model.scale


## Recursively copy Sprite2D nodes from source to target, preserving hierarchy.
func _copy_sprite_recursive(source: Node, target: Node) -> void:
	for child in source.get_children():
		if child is Sprite2D:
			var sprite := Sprite2D.new()
			sprite.name = child.name
			sprite.texture = child.texture
			sprite.position = child.position
			sprite.rotation = child.rotation
			sprite.scale = child.scale
			sprite.offset = child.offset
			sprite.z_index = child.z_index
			sprite.flip_h = child.flip_h
			sprite.flip_v = child.flip_v
			sprite.modulate = child.modulate
			sprite.visible = child.visible
			# Copy original material if present (preserves enemy's visual appearance)
			if child.material:
				sprite.material = child.material.duplicate()
			target.add_child(sprite)
			# Recurse into sprite children (e.g., WeaponMount/WeaponSprite)
			_copy_sprite_recursive(child, sprite)
		elif child is Node2D:
			# Non-sprite Node2D containers (like WeaponMount)
			var container := Node2D.new()
			container.name = child.name
			container.position = child.position
			container.rotation = child.rotation
			container.scale = child.scale
			target.add_child(container)
			_copy_sprite_recursive(child, container)


## Set up a lightweight HitArea for bullet detection (1 HP).
func _setup_hit_area() -> void:
	_hit_area = Area2D.new()
	_hit_area.name = "IllusionHitArea"
	# Same collision setup as real enemies: layer 2 (enemies), mask 16 (bullets)
	_hit_area.collision_layer = 2
	_hit_area.collision_mask = 16

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0  # Same as enemy collision shape
	shape.shape = circle
	shape.name = "HitCollisionShape"

	_hit_area.add_child(shape)
	add_child(_hit_area)

	# Connect the hit detection — use a script method on the Area2D
	_hit_area.set_script(load("res://scripts/effects/illusion_hit_area.gd"))
	_hit_area.set("illusion_parent", self)


## Update position to follow the original enemy.
func _update_position() -> void:
	if _original_enemy and is_instance_valid(_original_enemy):
		var target_pos := _original_enemy.global_position + follow_offset.rotated(_original_enemy.rotation)
		# Smooth follow
		global_position = global_position.lerp(target_pos, 0.1)


## Fire a phantom bullet toward the player.
## Phantom bullets are visual-only and only damage the player.
func _fire_phantom_bullet() -> void:
	if _bullet_scene == null:
		return

	# Only shoot if original enemy can see the player (use original's state)
	if _original_enemy and _original_enemy.get("_can_see_player") != null:
		if not _original_enemy._can_see_player:
			return

	# Find the player
	var player: Node2D = null
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player = players[0] as Node2D
	if player == null:
		return

	# Calculate direction to player
	var dir := (player.global_position - global_position).normalized()
	var spawn_pos := global_position + dir * 30.0  # offset from center

	# Spawn phantom bullet
	var bullet: Node2D = _bullet_scene.instantiate()
	bullet.global_position = spawn_pos
	if bullet.get("direction") != null:
		bullet.direction = dir
	if bullet.get("shooter_id") != null:
		bullet.shooter_id = get_instance_id()
	# Mark as phantom — only damages the player
	if bullet.get("is_phantom") != null:
		bullet.is_phantom = true

	get_tree().current_scene.add_child(bullet)

	# Spawn muzzle flash effect
	var effects_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if effects_manager and effects_manager.has_method("spawn_muzzle_flash"):
		effects_manager.spawn_muzzle_flash(spawn_pos, dir)


## Called when the illusion is hit by a bullet.
func take_damage(_amount: float = 1.0) -> void:
	_health -= 1
	if _health <= 0:
		_destroy()


## Check if the illusion is still alive.
func is_alive() -> bool:
	return _is_alive


## Destroy the illusion with a brief fade.
func _destroy() -> void:
	if not _is_alive:
		return
	_is_alive = false

	# Disable hit detection immediately
	if _hit_area:
		_hit_area.set_deferred("monitoring", false)
		_hit_area.set_deferred("monitorable", false)

	FileLogger.info("[IllusionEffect] Destroyed at %s (time_remaining=%.1fs)" % [
		str(global_position), _time_remaining
	])

	queue_free()


## Static helper: count current illusions on the map.
static func get_illusion_count(tree: SceneTree) -> int:
	return tree.get_nodes_in_group(ILLUSION_GROUP).size()


## Static helper: check if we can spawn more illusions.
static func can_spawn_more(tree: SceneTree) -> bool:
	return get_illusion_count(tree) < MAX_TOTAL_ILLUSIONS
