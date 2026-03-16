class_name EnemyTeleportComponent
extends Node
## Manages teleportation for enemies that have is_teleporter=true (Issue #752).
## Extracted from enemy.gd to keep file under CI line limit.
##
## The enemy teleports to cover when under fire, or to a flanking position
## when circling the player. Teleport distance is limited to 1 viewport diagonal.
## Cooldown is 10 seconds between teleports.
## A blue stripe is added to the enemy model as a visual indicator.

## Teleport cooldown in seconds.
const COOLDOWN: float = 10.0
## Fraction of viewport diagonal used as max teleport distance.
const VIEWPORT_FRACTION: float = 1.0
## Fallback diagonal when viewport is unavailable (1280x720).
const DEFAULT_DIAGONAL: float = 1469.0

var _parent: CharacterBody2D = null  ## The enemy node.
var _cooldown_timer: float = 0.0  ## Seconds until next teleport allowed.
var _ready_flag: bool = false  ## Set in _ready after parent resolves.

func _ready() -> void:
	_parent = get_parent() as CharacterBody2D
	_ready_flag = _parent != null

## Returns true when the teleport is off cooldown and ready to use.
func is_ready() -> bool:
	return _ready_flag and _cooldown_timer <= 0.0

## Advance cooldown timer each physics frame. Call from enemy _physics_process().
func update(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

## Attempt to teleport to target. Returns true if the teleport succeeded.
## Fails if on cooldown or target is farther than one viewport diagonal.
func try_teleport(target: Vector2) -> bool:
	if not is_ready() or _parent == null:
		return false
	var dist := _parent.global_position.distance_to(target)
	if dist > _get_max_distance():
		return false
	_execute_teleport(target)
	return true

## Add blue stripe visual indicator to the enemy model node.
## Call once from enemy _ready() after the model node is resolved.
static func add_blue_stripe(enemy_model: Node2D) -> void:
	if enemy_model == null:
		return
	var stripe := ColorRect.new()
	stripe.name = "TeleporterStripe"
	stripe.color = Color(0.2, 0.5, 1.0, 0.9)  ## Blue — marks teleporting enemy
	stripe.size = Vector2(16, 4)
	stripe.position = Vector2(-8, -26)  ## Centred above the body sprite
	stripe.z_index = 5
	enemy_model.add_child(stripe)

## Maximum teleport distance based on viewport size.
func _get_max_distance() -> float:
	var vp := _parent.get_viewport() if _parent else null
	if vp:
		var sz := vp.get_visible_rect().size
		return sqrt(sz.x * sz.x + sz.y * sz.y) * VIEWPORT_FRACTION
	return DEFAULT_DIAGONAL * VIEWPORT_FRACTION

## Execute the teleport: spawn effects, move, start cooldown.
func _execute_teleport(target: Vector2) -> void:
	var origin := _parent.global_position
	_spawn_effect(origin)
	_parent.global_position = target
	_spawn_effect(target)
	_cooldown_timer = COOLDOWN
	FileLogger.info("[Teleporter] Teleported from %s to %s" % [origin, target])

## Spawn a blue particle burst at pos for teleport visual feedback.
func _spawn_effect(pos: Vector2) -> void:
	var tree := _parent.get_tree() if _parent else null
	if tree == null:
		return
	var scene_root := tree.current_scene
	if scene_root == null:
		return
	var holder := Node2D.new()
	holder.global_position = pos
	var particles := GPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 12
	particles.lifetime = 0.35
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 15.0
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 60.0
	mat.initial_velocity_max = 120.0
	mat.gravity = Vector3.ZERO
	mat.color = Color(0.3, 0.6, 1.0, 1.0)
	mat.scale_min = 3.0
	mat.scale_max = 6.0
	particles.process_material = mat
	holder.add_child(particles)
	scene_root.add_child(holder)
	tree.create_timer(0.5).timeout.connect(func():
		if is_instance_valid(holder):
			holder.queue_free()
	)
