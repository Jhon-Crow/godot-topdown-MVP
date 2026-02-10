class_name AggressionComponent
extends Node
## Manages aggression gas effect (Issue #675) — makes enemies attack each other.
## Extracted from enemy.gd to keep file under CI line limit.

signal aggression_changed(is_aggressive: bool)

var _is_aggressive: bool = false
var _target: Node2D = null
var _parent: CharacterBody2D = null

func _ready() -> void:
	_parent = get_parent() as CharacterBody2D

func is_aggressive() -> bool: return _is_aggressive
func get_target() -> Node2D: return _target

func set_aggressive(aggressive: bool) -> void:
	var was := _is_aggressive; _is_aggressive = aggressive
	if aggressive and not was:
		_target = null; _log("AGGRESSIVE")
		aggression_changed.emit(true)
	elif not aggressive and was:
		_target = null; _log("Aggression expired")
		aggression_changed.emit(false)

func get_target_position() -> Vector2:
	if _is_aggressive and _target and is_instance_valid(_target):
		return _target.global_position
	return Vector2.ZERO

func process_combat(delta: float, rotation_speed: float, shoot_cooldown: float, combat_move_speed: float) -> void:
	if not _parent: return
	if _target == null or not is_instance_valid(_target) or _target.get("_is_alive") == false:
		_target = _find_nearest_enemy_target()
	if _target == null:
		_parent.velocity = Vector2.ZERO; return
	
	var direction_to_target := (_target.global_position - _parent.global_position).normalized()
	var distance_to_target := _parent.global_position.distance_to(_target.global_position)
	
	# Always rotate toward target
	var ad := wrapf(direction_to_target.angle() - _parent.rotation, -PI, PI)
	if abs(ad) <= rotation_speed * delta: 
		_parent.rotation = direction_to_target.angle()
	elif ad > 0: 
		_parent.rotation += rotation_speed * delta
	else: 
		_parent.rotation -= rotation_speed * delta
	if _parent.has_method("_force_model_to_face_direction"): 
		_parent._force_model_to_face_direction(direction_to_target)
	
	# Shooting logic
	var wf: Vector2 = _parent._get_weapon_forward_direction() if _parent.has_method("_get_weapon_forward_direction") else Vector2.RIGHT.rotated(_parent.rotation)
	if wf.dot(direction_to_target) >= 0.866 and _parent._can_shoot() and _parent._shoot_timer >= shoot_cooldown:
		_parent._shoot(); _parent._shoot_timer = 0.0
	
	# FIX: Add tactical movement instead of standing still
	if _has_los(_target):
		# Check if we should attempt flanking
		if _should_attempt_flank() and randf() < 0.3:  # 30% chance to flank when opportunity arises
			var flank_pos := _calculate_flank_position()
			if _parent.has_method("_move_to_target_nav"):
				_parent._move_to_target_nav(flank_pos, combat_move_speed)
				_log("Flanking to position %s" % str(flank_pos))
		else:
			# tactical movement behavior based on distance
			if distance_to_target > 400.0:
				# Long range: advance toward target
				_parent.velocity = direction_to_target * combat_move_speed * 0.8
				_log("Advancing on target (distance=%.0f)" % distance_to_target)
			elif distance_to_target > 200.0:
				# Medium range: advance with strafing
				var strafe_dir := Vector2(-direction_to_target.y, direction_to_target.x).normalized()
				var movement_dir := direction_to_target * 0.7 + strafe_dir * 0.3
				_parent.velocity = movement_dir * combat_move_speed * 0.6
				_log("Strafing toward target (distance=%.0f)" % distance_to_target)
			else:
				# Close range: circle strafe around target
				var circle_angle := get_time() * 2.0  # Circle around target
				var circle_dir := Vector2(cos(circle_angle), sin(circle_angle))
				var movement_dir := direction_to_target * 0.2 + circle_dir * 0.8
				_parent.velocity = movement_dir * combat_move_speed * 0.4
				_log("Circle strafing target (distance=%.0f)" % distance_to_target)
	else:
		# No line of sight: move toward target using navigation
		if _parent.has_method("_move_to_target_nav"): 
			_parent._move_to_target_nav(_target.global_position, combat_move_speed)
			_log("Moving to target position (no LOS)")

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

func _find_nearest_enemy_target() -> Node2D:
	if not _parent: return null
	var best: Node2D = null; var best_d := INF
	for e in _parent.get_tree().get_nodes_in_group("enemies"):
		if e == _parent or not is_instance_valid(e) or not e is Node2D: continue
		if e.get("_is_alive") == false: continue
		var d := _parent.global_position.distance_to(e.global_position)
		if d < best_d and _has_los(e): best_d = d; best = e
	return best

func _has_los(target: Node2D) -> bool:
	if not _parent: return false
	var q := PhysicsRayQueryParameters2D.create(_parent.global_position, target.global_position)
	q.collision_mask = 4; q.exclude = [_parent]
	return _parent.get_world_2d().direct_space_state.intersect_ray(q).is_empty()

func _log(message: String) -> void:
	if _parent and _parent.has_method("_log_to_file"): _parent._log_to_file("[#675] " + message)

## Add flanking behavior for aggressive enemies
func _should_attempt_flank() -> bool:
	if not _parent or not _target: return false
	var distance := _parent.global_position.distance_to(_target.global_position)
	# Don't flank if too close or too far
	if distance < 150.0 or distance > 500.0: return false
	
	# Check if target is engaged with another enemy
	if not _target.has_method("_get_current_shooter"): return false
	var current_shooter = _target._get_current_shooter()
	if current_shooter and current_shooter != _parent:
		# Target is shooting at someone else - good flanking opportunity
		return true
	return false

## Calculate flanking position
func _calculate_flank_position() -> Vector2:
	if not _parent or not _target: return Vector2.ZERO
	
	# Calculate perpendicular direction for flanking
	var direction_to_target := (_target.global_position - _parent.global_position).normalized()
	var flank_dir := Vector2(-direction_to_target.y, direction_to_target.x).normalized()
	
	# Choose left or right flank randomly
	if randf() < 0.5:
		flank_dir = -flank_dir
	
	# Position at flanking distance
	var flank_distance := 200.0
	return _target.global_position + flank_dir * flank_distance
