class_name EnemyArmoredSkinComponent
extends Node
## Manages the Armored Skin passive item for enemies (Issue #1123).
## Extracted as a component following the EnemyForceFieldComponent pattern.
##
## Effect (same as the player's Armored Skin, Issue #1045):
## - +1 HP bonus applied at spawn (added after base health is set).
## - When the enemy is at ≤2 HP and takes a hit, 20 glass/crystal shards
##   fly outward in all directions.
## - Visual: enemy sprites get a glassy transparent bluish armor shader overlay.
##
## Shards use the existing ArmoredSkinShard scene (same as the player).
## They deal 1 damage each, do NOT ricochet, and do NOT hit the source enemy.

## HP threshold at or below which shards spawn on hit.
const HP_THRESHOLD: int = 2

## Number of shards to spawn per trigger.
const SHARD_COUNT: int = 20

## Path to the shard scene (shared with the player implementation).
const SHARD_SCENE_PATH: String = "res://scenes/projectiles/ArmoredSkinShard.tscn"

## Path to the armored skin visual shader.
const ARMOR_SHADER_PATH: String = "res://scripts/shaders/armored_skin.gdshader"

var _parent: Node2D = null
var _has_triggered: bool = false  ## True after shards have been spawned — prevents re-triggering (Issue #1143).
var _trigger_frame: int = -1  ## Physics frame when the effect triggered; used to absorb same-frame burst hits (Issue #1143).


func _ready() -> void:
	_parent = get_parent() as Node2D
	_apply_armor_visual()


## Apply the glassy armor shader to all enemy body sprites so the enemy
## looks like it is covered in transparent crystal/glass armor (Issue #1123).
func _apply_armor_visual() -> void:
	if _parent == null:
		return
	if not ResourceLoader.exists(ARMOR_SHADER_PATH):
		FileLogger.info("[EnemyArmoredSkin] WARNING: Shader not found: %s" % ARMOR_SHADER_PATH)
		return
	var shader: Shader = load(ARMOR_SHADER_PATH)
	if shader == null:
		FileLogger.info("[EnemyArmoredSkin] WARNING: Failed to load armor shader")
		return

	# Apply shader to all Sprite2D children inside EnemyModel.
	var model: Node = _parent.get_node_or_null("EnemyModel")
	if model == null:
		FileLogger.info("[EnemyArmoredSkin] WARNING: EnemyModel node not found, skipping visual")
		return

	var applied_count: int = 0
	for child in model.get_children():
		if child is Sprite2D:
			var mat := ShaderMaterial.new()
			mat.shader = shader
			child.material = mat
			applied_count += 1

	FileLogger.info("[EnemyArmoredSkin] Armor shader applied to %d sprites" % applied_count)


## Apply the +1 HP bonus to the enemy's current and max health.
## Call this from enemy._ready() after _initialize_health().
func apply_hp_bonus(current_health: int, max_health: int) -> Array[int]:
	var new_max: int = max_health + 1
	var new_current: int = current_health + 1
	FileLogger.info("[EnemyArmoredSkin] +1 HP bonus applied — health %d/%d -> %d/%d" % [
		current_health, max_health, new_current, new_max])
	return [new_current, new_max]


## Try to spawn shards when the enemy is hit at low HP or by a lethal hit.
## Call from enemy.on_hit_with_bullet_info() before applying damage.
## Triggers at most once — subsequent hits at low HP are handled normally.
## Same-frame hits after the trigger are also absorbed so that area-of-effect
## damage bursts (e.g. grenade explosions) cannot kill the enemy in the same
## physics frame as the trigger (Issue #1143).
## @param current_health: Health *before* this hit is applied.
## @param incoming_damage: Damage amount about to be applied (default 1). Used to detect
##   lethal hits from high-damage weapons (e.g. silenced pistol) that would otherwise
##   skip the low-HP threshold check entirely (Issue #1300).
## @return true if the hit must be absorbed (initial trigger or same-frame burst hit).
func try_spawn_shards(current_health: int, incoming_damage: int = 1) -> bool:
	# Absorb all hits on the same physics frame as the trigger (grenade burst fix).
	if _has_triggered and Engine.get_physics_frames() == _trigger_frame:
		return true
	if _has_triggered:
		return false
	# Trigger when HP is already low OR when this hit would be lethal (Issue #1300).
	# High-damage weapons (e.g. silenced pistol with 10 dmg) can one-shot an armored
	# enemy whose HP is still above HP_THRESHOLD, bypassing the armor entirely without
	# this second condition.
	if current_health > HP_THRESHOLD and current_health - incoming_damage > 0:
		return false
	_has_triggered = true
	_trigger_frame = Engine.get_physics_frames()
	_spawn_shards()
	_remove_armor_visual()
	return true


## Remove the armor visual shader from all enemy sprites when shards are spawned.
## The enemy becomes a regular enemy after the effect triggers (Issue #1143).
func _remove_armor_visual() -> void:
	if _parent == null:
		return
	var model: Node = _parent.get_node_or_null("EnemyModel")
	if model == null:
		return
	var removed_count: int = 0
	for child in model.get_children():
		if child is Sprite2D and child.material is ShaderMaterial:
			child.material = null
			removed_count += 1
	FileLogger.info("[EnemyArmoredSkin] Armor visual removed from %d sprites (triggered)" % removed_count)


## Spawn 20 glass shards in all directions from the enemy position.
func _spawn_shards() -> void:
	if _parent == null:
		return

	if not ResourceLoader.exists(SHARD_SCENE_PATH):
		FileLogger.info("[EnemyArmoredSkin] WARNING: Shard scene not found: %s" % SHARD_SCENE_PATH)
		return

	var shard_scene: PackedScene = load(SHARD_SCENE_PATH)
	if shard_scene == null:
		FileLogger.info("[EnemyArmoredSkin] WARNING: Failed to load shard scene")
		return

	var spawn_parent: Node = _parent.get_parent()
	if spawn_parent == null:
		spawn_parent = _parent

	FileLogger.info("[EnemyArmoredSkin] Spawning %d glass shards (hp <= %d)" % [SHARD_COUNT, HP_THRESHOLD])

	for i in range(SHARD_COUNT):
		var shard: Node2D = shard_scene.instantiate()

		var base_angle: float = (float(i) / float(SHARD_COUNT)) * TAU
		var angle_deviation: float = randf_range(-PI / SHARD_COUNT, PI / SHARD_COUNT)
		var angle: float = base_angle + angle_deviation
		shard.direction = Vector2(cos(angle), sin(angle)).normalized()
		# Use parent's instance ID so shards don't hit the source enemy.
		shard.source_id = _parent.get_instance_id()

		spawn_parent.add_child(shard)
		shard.global_position = _parent.global_position
