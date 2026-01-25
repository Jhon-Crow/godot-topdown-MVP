extends Node
## Component that handles enemy grenade throwing behavior (Issue #363).
## Extracted from enemy.gd to reduce file size below 5000 lines.
class_name EnemyGrenadeComponent

## Grenade thrown signal.
signal grenade_thrown(grenade: Node, target_position: Vector2)

# Configuration - set these from enemy's export vars
var grenade_count: int = 0
var grenade_scene: PackedScene = null
var enabled: bool = true
var throw_cooldown: float = 15.0
var max_throw_distance: float = 600.0
var min_throw_distance: float = 275.0  # Updated to 275.0 per Issue #375
var safety_margin: float = 50.0  # Safety margin for blast radius (Issue #375)
var inaccuracy: float = 0.15
var throw_delay: float = 0.4
var debug_logging: bool = false

# Constants
const HIDDEN_THRESHOLD := 6.0
const PURSUIT_SPEED_THRESHOLD := 50.0
const KILL_THRESHOLD := 2
const KILL_WITNESS_WINDOW := 30.0
const SOUND_VALIDITY_WINDOW := 5.0
const SUSTAINED_FIRE_THRESHOLD := 10.0
const FIRE_GAP_TOLERANCE := 2.0
const VIEWPORT_ZONE_FRACTION := 6.0
const DESPERATION_HEALTH_THRESHOLD := 1

# State
var grenades_remaining: int = 0
var _cooldown: float = 0.0
var _is_throwing: bool = false
var _enemy: CharacterBody2D = null
var _logger: Node = null

# Trigger 1: Suppression
var _hidden_timer: float = 0.0
var _was_suppressed: bool = false

# Trigger 2: Pursuit
var _prev_dist: float = 0.0
var _approach_speed: float = 0.0

# Trigger 3: Witnessed Kills
var _kills_witnessed: int = 0
var _kill_reset_timer: float = 0.0

# Trigger 4: Sound
var _heard_sound: bool = false
var _sound_pos: Vector2 = Vector2.ZERO
var _sound_time: float = 0.0

# Trigger 5: Sustained Fire
var _fire_zone: Vector2 = Vector2.ZERO
var _fire_time: float = 0.0
var _fire_duration: float = 0.0
var _fire_valid: bool = false


func _ready() -> void:
	_logger = get_node_or_null("/root/FileLogger")
	_enemy = get_parent() as CharacterBody2D


func initialize() -> void:
	_cooldown = 0.0
	_is_throwing = false
	_reset_triggers()

	if grenade_count > 0:
		grenades_remaining = grenade_count
	else:
		var map := _get_map()
		if DifficultyManager.are_enemy_grenades_enabled(map):
			grenades_remaining = DifficultyManager.get_enemy_grenade_count(map)

	if grenade_scene == null and grenades_remaining > 0:
		var path := DifficultyManager.get_enemy_grenade_scene_path(_get_map())
		grenade_scene = load(path) if path else null
		if grenade_scene == null:
			grenade_scene = preload("res://scenes/projectiles/FragGrenade.tscn")

	if grenades_remaining > 0:
		_log("Initialized: %d grenades" % grenades_remaining)


func _get_map() -> String:
	var s := get_tree().current_scene
	return s.name if s else ""


func _reset_triggers() -> void:
	_hidden_timer = 0.0
	_was_suppressed = false
	_kills_witnessed = 0
	_heard_sound = false
	_fire_valid = false
	_fire_duration = 0.0


func update(delta: float, can_see: bool, under_fire: bool, player: Node2D, health: int) -> void:
	if not enabled or grenades_remaining <= 0:
		return

	if _cooldown > 0.0:
		_cooldown -= delta

	if _kill_reset_timer > 0.0:
		_kill_reset_timer -= delta
		if _kill_reset_timer <= 0.0:
			_kills_witnessed = 0

	# Trigger 1
	if under_fire:
		_was_suppressed = true
	if _was_suppressed and not can_see:
		_hidden_timer += delta
	elif can_see:
		_hidden_timer = 0.0
		_was_suppressed = false

	# Trigger 2
	if player and _enemy:
		var d := _enemy.global_position.distance_to(player.global_position)
		if _prev_dist > 0.0:
			_approach_speed = (_prev_dist - d) / delta if delta > 0 else 0.0
		_prev_dist = d

	# Trigger 5
	if _fire_valid:
		if Time.get_ticks_msec() / 1000.0 - _fire_time > FIRE_GAP_TOLERANCE:
			_fire_valid = false
			_fire_duration = 0.0


func on_gunshot(pos: Vector2) -> void:
	if not enabled or grenades_remaining <= 0:
		return
	var r := _get_zone_radius()
	var t := Time.get_ticks_msec() / 1000.0
	if _fire_valid:
		if pos.distance_to(_fire_zone) <= r and t - _fire_time <= FIRE_GAP_TOLERANCE:
			_fire_duration += t - _fire_time
			_fire_time = t
		else:
			_fire_zone = pos
			_fire_time = t
			_fire_duration = 0.0
	else:
		_fire_zone = pos
		_fire_time = t
		_fire_duration = 0.0
		_fire_valid = true


func _get_zone_radius() -> float:
	var vp := get_viewport()
	if vp == null:
		return 200.0
	var s := vp.get_visible_rect().size
	return sqrt(s.x ** 2 + s.y ** 2) / VIEWPORT_ZONE_FRACTION / 2.0


func on_vulnerable_sound(pos: Vector2, can_see: bool) -> void:
	if not enabled or grenades_remaining <= 0 or can_see:
		return
	_heard_sound = true
	_sound_pos = pos
	_sound_time = Time.get_ticks_msec() / 1000.0


func on_ally_died(pos: Vector2, by_player: bool, can_see_pos: bool) -> void:
	if not by_player or not enabled or grenades_remaining <= 0 or not can_see_pos:
		return
	_kills_witnessed += 1
	_kill_reset_timer = KILL_WITNESS_WINDOW


# Trigger checks
func _t1() -> bool:
	return _was_suppressed and _hidden_timer >= HIDDEN_THRESHOLD

func _t2(under_fire: bool) -> bool:
	return under_fire and _approach_speed >= PURSUIT_SPEED_THRESHOLD

func _t3() -> bool:
	return _kills_witnessed >= KILL_THRESHOLD

func _t4(can_see: bool) -> bool:
	if not _heard_sound:
		return false
	if Time.get_ticks_msec() / 1000.0 - _sound_time > SOUND_VALIDITY_WINDOW:
		_heard_sound = false
		return false
	return not can_see

func _t5() -> bool:
	return _fire_valid and _fire_duration >= SUSTAINED_FIRE_THRESHOLD

func _t6(health: int) -> bool:
	return health <= DESPERATION_HEALTH_THRESHOLD


func is_ready(can_see: bool, under_fire: bool, health: int) -> bool:
	if not enabled or grenades_remaining <= 0 or _cooldown > 0.0 or _is_throwing:
		return false
	return _t1() or _t2(under_fire) or _t3() or _t4(can_see) or _t5() or _t6(health)


func get_target(can_see: bool, under_fire: bool, health: int, player: Node2D,
				last_known: Vector2, memory_pos: Vector2) -> Vector2:
	if _t6(health):
		return player.global_position if player else memory_pos
	if _t4(can_see):
		return _sound_pos
	if _t2(under_fire) and player and _enemy:
		var dir := (player.global_position - _enemy.global_position).normalized()
		var d := minf(200.0, _enemy.global_position.distance_to(player.global_position) * 0.5)
		return _enemy.global_position + dir * d
	if _t3():
		return player.global_position if player and can_see else memory_pos
	if _t5():
		return _fire_zone
	if _t1():
		return memory_pos if memory_pos != Vector2.ZERO else last_known
	return Vector2.ZERO


func try_throw(target: Vector2, is_alive: bool, is_stunned: bool, is_blinded: bool) -> bool:
	if not enabled or grenades_remaining <= 0 or _cooldown > 0.0 or _is_throwing:
		return false
	if not is_alive or is_stunned or is_blinded or target == Vector2.ZERO or _enemy == null:
		return false

	var dist := _enemy.global_position.distance_to(target)

	# Issue #375: Check safe distance based on blast radius
	var blast_radius := _get_blast_radius()
	var min_safe_distance := blast_radius + safety_margin

	if dist < min_safe_distance:
		_log("Unsafe throw distance (%.0f < %.0f safe distance, blast=%.0f, margin=%.0f) - skipping throw" %
			[dist, min_safe_distance, blast_radius, safety_margin])
		return false

	# Legacy minimum distance check (should be covered by above, but kept for compatibility)
	if dist < min_throw_distance:
		_log("Target too close (%.0f < %.0f) - skipping throw" % [dist, min_throw_distance])
		return false

	if dist > max_throw_distance:
		target = _enemy.global_position + (target - _enemy.global_position).normalized() * max_throw_distance

	if not _path_clear(target):
		_log("Throw path blocked to %s" % target)
		return false

	_execute_throw(target, is_alive, is_stunned, is_blinded)
	return true


## Get grenade blast radius (Issue #375)
func _get_blast_radius() -> float:
	if grenade_scene == null:
		return 225.0  # Default frag grenade radius

	# Try to instantiate grenade temporarily to query its radius
	var temp_grenade = grenade_scene.instantiate()
	if temp_grenade == null:
		return 225.0  # Fallback

	var radius := 225.0  # Default

	# Check if grenade has effect_radius property
	if temp_grenade.get("effect_radius") != null:
		radius = temp_grenade.effect_radius

	# Clean up temporary instance
	temp_grenade.queue_free()

	return radius


func _path_clear(target: Vector2) -> bool:
	if _enemy == null:
		return true
	var space := _enemy.get_world_2d().direct_space_state
	if space == null:
		return true
	var query := PhysicsRayQueryParameters2D.create(_enemy.global_position, target)
	query.collision_mask = 4
	query.exclude = [_enemy]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return true
	return _enemy.global_position.distance_to(result.position) > _enemy.global_position.distance_to(target) * 0.6


func _execute_throw(target: Vector2, is_alive: bool, is_stunned: bool, is_blinded: bool) -> void:
	if grenade_scene == null:
		return
	_is_throwing = true

	if throw_delay > 0.0:
		await get_tree().create_timer(throw_delay).timeout

	if not is_alive or is_stunned or is_blinded or not is_instance_valid(self) or not is_instance_valid(_enemy):
		_is_throwing = false
		return

	var dir := (target - _enemy.global_position).normalized().rotated(randf_range(-inaccuracy, inaccuracy))
	var grenade: Node2D = grenade_scene.instantiate()
	grenade.global_position = _enemy.global_position + dir * 40.0

	var parent := get_tree().current_scene
	(parent if parent else _enemy.get_parent()).add_child(grenade)

	if grenade.has_method("activate_timer"):
		grenade.activate_timer()

	var dist := _enemy.global_position.distance_to(target)
	if grenade.has_method("throw_grenade"):
		grenade.throw_grenade(dir, dist)
	elif grenade is RigidBody2D:
		grenade.freeze = false
		grenade.linear_velocity = dir * clampf(dist * 1.5, 200.0, 800.0)
		grenade.rotation = dir.angle()

	grenades_remaining -= 1
	_cooldown = throw_cooldown
	_is_throwing = false
	_reset_triggers()
	grenade_thrown.emit(grenade, target)


func add_grenades(count: int) -> void:
	grenades_remaining += count


func _log(msg: String) -> void:
	if debug_logging:
		print("[EnemyGrenadeComponent] %s" % msg)
	if _logger and _logger.has_method("log_info"):
		_logger.log_info("[EnemyGrenade] %s" % msg)
