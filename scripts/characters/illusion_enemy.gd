extends Node2D
class_name IllusionEnemy
## Illusory copy of an enemy created by the ChemicalGasGrenade effect (Issue #1129).
##
## An illusory copy looks and acts like a normal enemy, but:
## - Stays near the original enemy, following its movements (does not rush toward player)
## - Is one-shot by any weapon or shrapnel (health = 1)
## - All weapons deal 5% of normal damage (ILLUSION_DAMAGE_MULTIPLIER = 0.05)
## - Does not stop bullets or shrapnel (collision disabled on physics layer 1)
## - Disappears if the original enemy is killed
## - Disappears when the illusion duration expires
##
## Per issue #1129 requirements:
## - иллюзорная копия выглядит и действует как обычный враг, но убивается одним выстрелом
## - все оружия иллюзорной копии наносят 5% от нормального урона
## - иллюзорные копии не останавливают пули или шрапнель
## - все иллюзорные копии врага исчезают, если убит оригинал
## - когда эффект гранаты истекает, все иллюзорные копии исчезают

## Damage multiplier for all weapons of illusory copies (5% of normal).
const ILLUSION_DAMAGE_MULTIPLIER: float = 0.05

## Maximum total illusion copies active on the map at once (performance cap).
const MAX_TOTAL_ILLUSIONS: int = 12

## Movement speed for illusion copies (following the original enemy).
const ILLUSION_MOVE_SPEED: float = 180.0

## Maximum distance an illusion copy can drift from the original enemy before snapping back.
const MAX_DISTANCE_FROM_ORIGINAL: float = 120.0

## Original enemy that this copy was spawned from.
var original_enemy: Node2D = null

## How long the illusion lasts before disappearing (seconds).
var illusion_duration: float = 20.0

## Offset from original position to spawn this copy.
var spawn_offset: Vector2 = Vector2.ZERO

## The instantiated enemy node that acts as the visual/behavior.
var _enemy_node: Node2D = null

## Remaining duration.
var _time_remaining: float = 0.0

## Whether the illusion has already been cleaned up.
var _cleaned_up: bool = false

## The persistent offset this copy maintains relative to the original enemy.
var _follow_offset: Vector2 = Vector2.ZERO

## Reference to the scene used for the enemy.
const ENEMY_SCENE_PATH := "res://scenes/objects/Enemy.tscn"


func _ready() -> void:
	_time_remaining = illusion_duration

	if original_enemy == null or not is_instance_valid(original_enemy):
		FileLogger.warning("[IllusionEnemy] No valid original enemy — freeing immediately")
		queue_free()
		return

	# Store the spawn offset as the persistent follow offset so copies stay near the original
	_follow_offset = spawn_offset

	# Register in illusion group for global cap tracking
	add_to_group("illusion_enemies")

	# Connect to original enemy's died signal so we disappear when original dies
	if original_enemy.has_signal("died"):
		original_enemy.died.connect(_on_original_died)

	# Spawn the actual enemy node as a visual/behavioral copy
	_spawn_enemy_copy()

	FileLogger.info("[IllusionEnemy] Illusion created at %s (duration=%.0fs)" % [str(global_position), illusion_duration])


func _physics_process(delta: float) -> void:
	_time_remaining -= delta

	if _time_remaining <= 0.0:
		_cleanup()
		return

	# Follow the original enemy: maintain a fixed offset from the original's position.
	# Illusion copies stay near their originals, mirroring their trajectory (Issue #1129 feedback).
	if _enemy_node != null and is_instance_valid(_enemy_node) and _enemy_node is CharacterBody2D:
		if original_enemy == null or not is_instance_valid(original_enemy):
			_cleanup()
			return

		# Target position = original enemy position + our persistent offset
		var target_pos := original_enemy.global_position + _follow_offset
		var current_pos := _enemy_node.global_position
		var to_target := target_pos - current_pos
		var distance := to_target.length()

		if distance > 2.0:
			# Move toward the target offset position
			var dir := to_target.normalized()
			var speed := ILLUSION_MOVE_SPEED
			# Speed up if drifted too far from original
			if distance > MAX_DISTANCE_FROM_ORIGINAL:
				speed *= 2.0
			_enemy_node.velocity = dir * speed
			_enemy_node.move_and_slide()
			# Rotate model to face movement direction
			var model: Node2D = _enemy_node.get_node_or_null("EnemyModel")
			if model:
				model.rotation = dir.angle()
		else:
			# Close enough — match the original enemy's facing direction
			_enemy_node.velocity = Vector2.ZERO
			_enemy_node.move_and_slide()
			var orig_model: Node2D = original_enemy.get_node_or_null("EnemyModel")
			var copy_model: Node2D = _enemy_node.get_node_or_null("EnemyModel")
			if orig_model and copy_model:
				copy_model.rotation = orig_model.rotation


## Spawn the enemy copy by instantiating the Enemy scene and configuring it.
func _spawn_enemy_copy() -> void:
	var enemy_scene: PackedScene = load(ENEMY_SCENE_PATH)
	if enemy_scene == null:
		FileLogger.warning("[IllusionEnemy] Could not load Enemy scene from %s" % ENEMY_SCENE_PATH)
		queue_free()
		return

	_enemy_node = enemy_scene.instantiate()
	if _enemy_node == null:
		FileLogger.warning("[IllusionEnemy] Could not instantiate Enemy scene")
		queue_free()
		return

	# Mark as illusion via metadata so other systems can check
	_enemy_node.set_meta("is_illusion", true)
	_enemy_node.set_meta("illusion_damage_multiplier", ILLUSION_DAMAGE_MULTIPLIER)

	# Configure as one-shot: set health to 1
	if _enemy_node.get("min_health") != null:
		_enemy_node.min_health = 1
		_enemy_node.max_health = 1

	# Apply yellowish-transparent tint to visually distinguish (subtle shimmer)
	_apply_illusion_visual(_enemy_node)

	# Disable collision on bullet/shrapnel layer (layer 1 = 0b00001) so bullets pass through.
	# Enemies are on layer 2 (0b00010). We keep layer 2 so enemies can still be selected by
	# AI targeting, but disable layer 1 so projectiles don't collide.
	# Note: collision_mask is what we collide WITH; collision_layer is what we ARE on.
	# Projectiles check layer 2 for enemies. We keep that but disable projectile passthrough
	# by NOT being on the projectile collision layer. The enemy's HitArea handles this.
	_configure_bullet_passthrough(_enemy_node)

	# Reduce damage dealt by all weapons
	_configure_damage_reduction(_enemy_node)

	# Connect to the copy's died signal so we can clean up when it's one-shotted
	if _enemy_node.has_signal("died"):
		_enemy_node.died.connect(_on_copy_died)

	# IMPORTANT: global_position must be set on the IllusionEnemy node BEFORE add_child,
	# because IllusionEnemy is already in the scene tree (added by ChemicalCloud). This means
	# setting our global_position works correctly here. When add_child(_enemy_node) runs,
	# Enemy._ready() captures global_position — since _enemy_node.position defaults to (0,0)
	# relative to us, global_position will equal our global_position = target_pos. This ensures
	# the inner enemy's _initial_position (used for patrol/guard anchoring) is set correctly.
	var target_pos := original_enemy.global_position + spawn_offset
	global_position = target_pos

	add_child(_enemy_node)
	# _enemy_node.position is (0,0) relative to IllusionEnemy, so its global_position == target_pos

	# CRITICAL: Disable expensive AI systems to prevent FPS drops (Issue #1129 perf fix).
	# A full Enemy.tscn has ~4900 lines of AI, 24 raycasts, NavigationAgent2D, GOAP, etc.
	# With 12 illusion copies, this causes 3-5 FPS. Instead, we keep only visuals + hit detection.
	# Disable synchronously first (stops _physics_process immediately), then defer cleanup
	# for systems registered via call_deferred in Enemy._ready() (e.g. SoundPropagation).
	_disable_expensive_ai(_enemy_node)
	call_deferred("_deferred_disable_ai", _enemy_node)

	FileLogger.info("[IllusionEnemy] Enemy copy spawned, health=1, damage=5%% of normal")


## Apply a subtle yellowish semi-transparent visual to indicate illusion.
func _apply_illusion_visual(enemy_node: Node2D) -> void:
	# Apply a subtle yellow-tinted modulate to all sprites
	if enemy_node.has_method("_set_all_sprites_modulate"):
		enemy_node._set_all_sprites_modulate(Color(1.0, 1.0, 0.6, 0.8))
	else:
		var body: Sprite2D = enemy_node.get_node_or_null("EnemyModel/Body")
		if body:
			body.modulate = Color(1.0, 1.0, 0.6, 0.8)


## Configure the enemy copy so bullets and shrapnel pass through it.
## This is done by clearing the collision layer so the CharacterBody2D itself
## doesn't block physics. The HitArea (Area2D) on layer 2 still allows damage.
func _configure_bullet_passthrough(enemy_node: Node2D) -> void:
	# Remove the CharacterBody2D from collision layer 1 (bullet/shrapnel collision).
	# The enemy body is on layer 2 by default; projectiles use mask 2 for hit detection
	# via HitArea. We want bullets to physically pass through but still register hits.
	# Solution: keep HitArea for damage detection, but set collision_layer=0 on body
	# so the CharacterBody2D doesn't physically block projectiles.
	if enemy_node is CharacterBody2D:
		# Layer 2 (enemies group) stays for AI detection; layer 1 removed for bullet passthrough
		enemy_node.collision_layer = 2  # Keep only enemy layer, remove obstacle layer
		enemy_node.collision_mask = 1   # Only collide with walls (layer 1)
	enemy_node.set_meta("is_illusion_no_bullet_block", true)


## Configure weapons to deal reduced damage.
func _configure_damage_reduction(enemy_node: Node2D) -> void:
	# Store damage multiplier as metadata; weapon systems check this
	enemy_node.set_meta("damage_multiplier", ILLUSION_DAMAGE_MULTIPLIER)

	# If the enemy has a bullet_scene export, we'll patch bullets on fire
	# via the metadata check in bullet.gd (if it exists) or via signal
	# The primary mechanism is the metadata "damage_multiplier" that bullet/weapon
	# scripts should check when the shooter has this meta set.


## Disable expensive AI systems on the enemy copy for performance.
## Keeps: visuals (sprites, modulate), HitArea (for one-shot kills), died signal.
## Disables: _physics_process (GOAP, AI states, movement), NavigationAgent2D,
## all RayCast2Ds (24 per enemy), ThreatSphere, SoundPropagation, components.
## Also removes from "enemies" group so other enemies don't iterate over copies in O(n²).
func _disable_expensive_ai(enemy_node: Node2D) -> void:
	# 1. Stop the main AI loop (4900-line _physics_process in enemy.gd)
	enemy_node.set_physics_process(false)

	# 2. Remove from "enemies" group to prevent O(n²) inter-enemy queries.
	#    Enemy._ready() adds itself to "enemies". Other enemies iterate this group
	#    for tactical coordination, GOAP, and pursuit — O(n) per enemy per frame.
	#    We keep the copy in the scene tree for visual rendering and hit detection.
	if enemy_node.is_in_group("enemies"):
		enemy_node.remove_from_group("enemies")

	# 3. Disable NavigationAgent2D (pathfinding queries)
	var nav_agent: NavigationAgent2D = enemy_node.get_node_or_null("NavigationAgent2D")
	if nav_agent:
		nav_agent.avoidance_enabled = false
		nav_agent.set_physics_process(false)

	# 4. Disable all RayCast2Ds (8 wall + 16 cover + 1 LOS = 25 raycasts)
	for child in enemy_node.get_children():
		if child is RayCast2D:
			child.enabled = false
		# Also disable ThreatSphere Area2D (bullet proximity detection)
		if child is Area2D and child.name == "ThreatSphere":
			child.monitoring = false
			child.monitorable = false
		# Disable CasingPusher Area2D
		if child is Area2D and child.name == "CasingPusher":
			child.monitoring = false
			child.monitorable = false

	# 5. Disable any child nodes that have their own _physics_process
	for child in enemy_node.get_children():
		if child.has_method("_physics_process"):
			child.set_physics_process(false)


## Deferred cleanup for systems registered via call_deferred in Enemy._ready().
## Enemy._ready() defers SoundPropagation registration, so we must defer unregistration
## to run after it.
func _deferred_disable_ai(enemy_node: Node2D) -> void:
	if not is_instance_valid(enemy_node):
		return
	# Unregister from SoundPropagation (deferred registration in Enemy._ready)
	var sound_propagation: Node = enemy_node.get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("unregister_listener"):
		sound_propagation.unregister_listener(enemy_node)
	# Ensure enemy is still removed from "enemies" group (deferred adds may have re-added)
	if enemy_node.is_in_group("enemies"):
		enemy_node.remove_from_group("enemies")


## Called when original enemy dies — all illusion copies disappear.
func _on_original_died() -> void:
	FileLogger.info("[IllusionEnemy] Original enemy died — removing illusion copy")
	_cleanup()


## Called when the copy itself takes a one-shot kill.
func _on_copy_died() -> void:
	FileLogger.info("[IllusionEnemy] Illusion copy destroyed")
	_cleanup()


## Clean up this illusion (remove copy and self).
func _cleanup() -> void:
	if _cleaned_up:
		return
	_cleaned_up = true

	if is_instance_valid(original_enemy) and original_enemy.has_signal("died"):
		if original_enemy.died.is_connected(_on_original_died):
			original_enemy.died.disconnect(_on_original_died)

	if _enemy_node != null and is_instance_valid(_enemy_node):
		_enemy_node.queue_free()
		_enemy_node = null

	FileLogger.info("[IllusionEnemy] Cleaned up at %s" % str(global_position))
	queue_free()


## Returns true — used by other systems to identify illusion copies.
func is_illusion() -> bool:
	return true
