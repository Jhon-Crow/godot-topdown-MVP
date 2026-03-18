extends Node2D
class_name IllusionEnemy
## Illusory copy of an enemy created by the ChemicalGasGrenade effect (Issue #1129).
##
## An illusory copy looks and acts like a normal enemy, but:
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

## Reference to the scene used for the enemy.
const ENEMY_SCENE_PATH := "res://scenes/objects/Enemy.tscn"


func _ready() -> void:
	_time_remaining = illusion_duration

	if original_enemy == null or not is_instance_valid(original_enemy):
		FileLogger.warning("[IllusionEnemy] No valid original enemy — freeing immediately")
		queue_free()
		return

	# Connect to original enemy's died signal so we disappear when original dies
	if original_enemy.has_signal("died"):
		original_enemy.died.connect(_on_original_died)

	# Spawn the actual enemy node as a visual/behavioral copy
	_spawn_enemy_copy()

	FileLogger.info("[IllusionEnemy] Illusion created at %s (duration=%.0fs)" % [str(global_position), illusion_duration])


func _physics_process(delta: float) -> void:
	_time_remaining -= delta

	# Track original enemy position (illusions wander near original)
	if is_instance_valid(original_enemy) and _enemy_node != null:
		# Update position to follow original with spawn offset
		global_position = original_enemy.global_position + spawn_offset

	if _time_remaining <= 0.0:
		_cleanup()


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

	# Position at spawn offset from original
	_enemy_node.global_position = original_enemy.global_position + spawn_offset
	global_position = _enemy_node.global_position

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

	add_child(_enemy_node)

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
