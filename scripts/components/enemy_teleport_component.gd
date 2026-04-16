class_name EnemyTeleportComponent
extends Node
## Manages teleportation for enemies that have is_teleporter=true (Issue #752).
## Extracted from enemy.gd to keep file under CI line limit.
##
## The enemy teleports to cover when under fire, or to a flanking position
## when circling the player. Teleport distance is limited to 1 viewport diagonal.
## Cooldown is 5 seconds between teleports (halved from 10 s per Issue #1350).
## A blue backpack sprite is added to the enemy model as a visual indicator.

## Teleport cooldown in seconds.
const COOLDOWN: float = 5.0
## Fraction of viewport diagonal used as max teleport distance.
const VIEWPORT_FRACTION: float = 1.0
## Fallback diagonal when viewport is unavailable (1280x720).
const DEFAULT_DIAGONAL: float = 1469.0
## Minimum teleport distance in pixels (Issue #1355: reject short teleports).
const MIN_DISTANCE: float = 10.0
## Max distance from nav-mesh to still count as "on the map" (Issue #1355).
const NAV_SNAP_TOLERANCE: float = 50.0

var _parent: CharacterBody2D = null  ## The enemy node.
var _cooldown_timer: float = 0.0  ## Seconds until next teleport allowed.
var _ready_flag: bool = false  ## Set in _ready after parent resolves.
var _last_reject_reason: String = ""  ## Last rejection reason (for rate-limiting logs).
var _reject_count: int = 0  ## Consecutive identical rejections.

func _ready() -> void:
	_parent = get_parent() as CharacterBody2D
	_ready_flag = _parent != null
	if _ready_flag:
		FileLogger.info("[Teleporter] Component initialized on %s" % _parent.name)
	else:
		FileLogger.warning("[Teleporter] Component parent is not CharacterBody2D (parent=%s)" % str(get_parent()))

## Returns true when the teleport is off cooldown and ready to use.
## Uses lazy parent resolution in case _ready() was deferred (Issue #1694).
func is_ready() -> bool:
	if not _ready_flag and _parent == null:
		_parent = get_parent() as CharacterBody2D
		_ready_flag = _parent != null
	return _ready_flag and _cooldown_timer <= 0.0

## Advance cooldown timer each physics frame. Call from enemy _physics_process().
func update(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

## Attempt to teleport to target. Returns true if the teleport succeeded.
## Fails if on cooldown, target too close/far, or target is off the nav-map.
func try_teleport(target: Vector2) -> bool:
	if not is_ready():
		FileLogger.info("[Teleporter] try_teleport rejected: not ready (flag=%s, cooldown=%.2f)" % [_ready_flag, _cooldown_timer])
		return false
	if _parent == null:
		FileLogger.warning("[Teleporter] try_teleport rejected: _parent is null")
		return false
	# Issue #1355: reject uninitialized (0,0) targets.
	if target == Vector2.ZERO:
		_log_reject("target is (0,0)")
		return false
	var dist := _parent.global_position.distance_to(target)
	# Issue #1355: reject teleports that are too short (visual flicker).
	if dist < MIN_DISTANCE:
		_log_reject("distance %.1f < min %.1f" % [dist, MIN_DISTANCE])
		return false
	if dist > _get_max_distance():
		_log_reject("distance %.1f > max %.1f" % [dist, _get_max_distance()])
		return false
	# Issue #1355: reject targets that are outside the navigation map.
	if not _is_on_nav_map(target):
		_log_reject("target %s is off the nav-map" % target)
		return false
	_flush_reject_log()
	_execute_teleport(target)
	return true

## Add blue backpack visual indicator to the enemy model node.
## Call once from enemy _ready() after the model node is resolved.
static func add_backpack(enemy_model: Node2D) -> void:
	if enemy_model == null:
		return
	var tex: Texture2D = load("res://assets/sprites/characters/enemy/teleporter_backpack.png")
	if tex == null:
		return
	var backpack := Sprite2D.new()
	backpack.name = "TeleporterBackpack"
	backpack.texture = tex
	backpack.z_index = 2  ## Same z-index as body sprite overlay
	backpack.position = Vector2(-4, 0)  ## Aligned with body sprite
	enemy_model.add_child(backpack)

## Rate-limited rejection log. Only logs first occurrence and a summary when reason changes.
func _log_reject(reason: String) -> void:
	if reason == _last_reject_reason:
		_reject_count += 1
		return
	_flush_reject_log()
	_last_reject_reason = reason
	_reject_count = 1
	FileLogger.info("[Teleporter] Rejected teleport: %s" % reason)

## Flush pending rejection log summary if there were repeated identical rejections.
func _flush_reject_log() -> void:
	if _reject_count > 1:
		FileLogger.info("[Teleporter] (repeated %d more times: %s)" % [_reject_count - 1, _last_reject_reason])
	_last_reject_reason = ""
	_reject_count = 0

## Attempt an immediate teleport in response to taking damage (Issue #1355).
## Bypasses the under_fire requirement — the enemy should teleport on first hit.
## Returns true if teleport succeeded.
func try_damage_teleport(cover_position: Vector2, flank_target: Vector2) -> bool:
	if not is_ready():
		FileLogger.info("[Teleporter] try_damage_teleport rejected: not ready (flag=%s, cooldown=%.2f)" % [_ready_flag, _cooldown_timer])
		return false
	if _parent == null:
		FileLogger.warning("[Teleporter] try_damage_teleport rejected: _parent is null")
		return false
	# Try cover position first, then flank target.
	if cover_position != Vector2.ZERO and try_teleport(cover_position):
		return true
	if flank_target != Vector2.ZERO and try_teleport(flank_target):
		return true
	return false

## Returns true if pos is inside (or very close to) the navigation mesh.
## Uses NavigationServer2D to snap the point; if the snapped point is far
## from the original, the target is off-map (Issue #1355).
func _is_on_nav_map(pos: Vector2) -> bool:
	if _parent == null:
		return false
	var nav_agent := _parent.get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	if nav_agent == null:
		return true  # No nav-agent — cannot validate, allow teleport.
	var nav_map: RID = nav_agent.get_navigation_map()
	if not nav_map.is_valid():
		return true
	var closest: Vector2 = NavigationServer2D.map_get_closest_point(nav_map, pos)
	return closest.distance_to(pos) <= NAV_SNAP_TOLERANCE

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
