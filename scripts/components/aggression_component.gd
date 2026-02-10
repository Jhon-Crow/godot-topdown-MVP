class_name AggressionComponent
extends Node
## Manages aggression gas effect (Issue #675) — makes enemies attack each other.
## Extracted from enemy.gd to keep file under CI line limit.
##
## Issue #729 fix: Aggressive enemies now actively move toward other enemies
## even when there is no line of sight. Previously, enemies would stand still
## when they couldn't see any targets, which looked broken to players.

signal aggression_changed(is_aggressive: bool)

var _is_aggressive: bool = false
var _target: Node2D = null
var _nav_target: Node2D = null  ## [#729] Target for navigation when no LOS available
var _last_nav_log_frame: int = -100  ## [#729] Throttle navigation logs
var _parent: CharacterBody2D = null

func _ready() -> void:
	_parent = get_parent() as CharacterBody2D

func is_aggressive() -> bool: return _is_aggressive
func get_target() -> Node2D: return _target

func set_aggressive(aggressive: bool) -> void:
	var was := _is_aggressive; _is_aggressive = aggressive
	if aggressive and not was:
		_target = null; _nav_target = null; _log("AGGRESSIVE")
		aggression_changed.emit(true)
	elif not aggressive and was:
		_target = null; _nav_target = null; _log("Aggression expired")
		aggression_changed.emit(false)

func get_target_position() -> Vector2:
	if _is_aggressive and _target and is_instance_valid(_target):
		return _target.global_position
	return Vector2.ZERO

func process_combat(delta: float, rotation_speed: float, shoot_cooldown: float, combat_move_speed: float) -> void:
	if not _parent: return
	if _target == null or not is_instance_valid(_target) or _target.get("_is_alive") == false:
		_target = _find_nearest_enemy_target_with_los()
	if _target != null and _has_los(_target):
		# Have LOS to target - engage in combat
		var d := (_target.global_position - _parent.global_position).normalized()
		var ad := wrapf(d.angle() - _parent.rotation, -PI, PI)
		if abs(ad) <= rotation_speed * delta: _parent.rotation = d.angle()
		elif ad > 0: _parent.rotation += rotation_speed * delta
		else: _parent.rotation -= rotation_speed * delta
		if _parent.has_method("_force_model_to_face_direction"): _parent._force_model_to_face_direction(d)
		var wf: Vector2 = _parent._get_weapon_forward_direction() if _parent.has_method("_get_weapon_forward_direction") else Vector2.RIGHT.rotated(_parent.rotation)
		if wf.dot(d) >= 0.866 and _parent._can_shoot() and _parent._shoot_timer >= shoot_cooldown:
			_parent._shoot(); _parent._shoot_timer = 0.0
		_parent.velocity = Vector2.ZERO
	elif _target != null:
		# Have target but no LOS - navigate toward them
		if _parent.has_method("_move_to_target_nav"): _parent._move_to_target_nav(_target.global_position, combat_move_speed)
	else:
		# [#729] No visible target - find any enemy and navigate toward them
		_nav_target = _find_nearest_enemy_any()
		if _nav_target != null:
			if _parent.has_method("_move_to_target_nav"):
				_parent._move_to_target_nav(_nav_target.global_position, combat_move_speed)
				# Throttle logging to once per second to avoid spam
				var frame := Engine.get_physics_frames()
				if frame - _last_nav_log_frame >= 60:
					_last_nav_log_frame = frame
					_log("Moving to %s (no LOS)" % _nav_target.name)
		else:
			# No enemies left - stop moving
			_parent.velocity = Vector2.ZERO

func check_retaliation(hit_direction: Vector2) -> void:
	if not _parent: return
	var adir := -hit_direction.normalized(); var best: Node2D = null; var bs := -INF
	for e in _parent.get_tree().get_nodes_in_group("enemies"):
		if e == _parent or not is_instance_valid(e) or not e is Node2D: continue
		if not (e.has_method("is_aggressive") and e.is_aggressive()) or e.get("_is_alive") == false: continue
		var dm := adir.dot((e.global_position - _parent.global_position).normalized())
		if dm > 0.5:
			var s := dm - (_parent.global_position.distance_to(e.global_position) / 1000.0)
			if s > bs: bs = s; best = e
	if best: on_hit_by_aggressive_enemy(best)

func on_hit_by_aggressive_enemy(attacker: Node2D) -> void:
	if not is_instance_valid(attacker) or not _parent or _parent.get("_is_alive") == false: return
	if not _is_aggressive: _log("Retaliating against %s" % attacker.name)
	_is_aggressive = true; _target = attacker
	aggression_changed.emit(true)
	var sm: Node = _parent.get_node_or_null("/root/StatusEffectsManager")
	if sm and sm.has_method("apply_aggression"): sm.apply_aggression(_parent, 10.0)

func get_debug_text() -> String:
	if not _is_aggressive: return ""
	return "\n{AGGRESSIVE%s}" % (" -> %s" % _target.name if _target and is_instance_valid(_target) else "")

## Find the nearest enemy with line of sight (for combat targeting).
func _find_nearest_enemy_target_with_los() -> Node2D:
	if not _parent: return null
	var best: Node2D = null; var best_d := INF
	for e in _parent.get_tree().get_nodes_in_group("enemies"):
		if e == _parent or not is_instance_valid(e) or not e is Node2D: continue
		if e.get("_is_alive") == false: continue
		var d := _parent.global_position.distance_to(e.global_position)
		if d < best_d and _has_los(e): best_d = d; best = e
	return best

## [#729] Find the nearest enemy regardless of line of sight (for navigation).
## This allows aggressive enemies to actively move toward targets they can't see.
func _find_nearest_enemy_any() -> Node2D:
	if not _parent: return null
	var best: Node2D = null; var best_d := INF
	for e in _parent.get_tree().get_nodes_in_group("enemies"):
		if e == _parent or not is_instance_valid(e) or not e is Node2D: continue
		if e.get("_is_alive") == false: continue
		var d := _parent.global_position.distance_to(e.global_position)
		if d < best_d: best_d = d; best = e
	return best

func _has_los(target: Node2D) -> bool:
	if not _parent: return false
	var q := PhysicsRayQueryParameters2D.create(_parent.global_position, target.global_position)
	q.collision_mask = 4; q.exclude = [_parent]
	return _parent.get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _log(message: String) -> void:
	if _parent and _parent.has_method("_log_to_file"): _parent._log_to_file("[#675] " + message)
