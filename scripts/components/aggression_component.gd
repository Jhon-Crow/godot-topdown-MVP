class_name AggressionComponent
extends Node
## Manages aggression gas effect (Issue #675) — makes enemies attack each other.
## Extracted from enemy.gd to keep file under CI line limit.
##
## Issue #729 fix: Aggressive enemies now actively move toward other enemies
## even when there is no line of sight. Previously, enemies would stand still
## when they couldn't see any targets, which looked broken to players.
##
## Issue #919 fix (Part 1): Aggression gas no longer propagates to enemies hit
## by aggressive enemies (removed chain reaction in check_retaliation).
##
## Issue #919 fix (Part 2): Non-aggressive enemies now detect and pursue
## aggressive enemies (treating them as a second player/threat), without
## themselves becoming aggressive. When no LOS, they navigate toward the
## aggressor (same as #729 pattern). This is separate from the aggression gas effect.

signal aggression_changed(is_aggressive: bool)

var _is_aggressive: bool = false
var _target: Node2D = null
var _nav_target: Node2D = null  ## [#729] Target for navigation when no LOS available
var _last_nav_log_frame: int = -100  ## [#729] Throttle navigation logs
var _parent: CharacterBody2D = null
var _hostile_aggressor: Node2D = null  ## [#919] Aggressive enemy perceived as player by this non-aggressive enemy
var _hostile_nav_target: Node2D = null  ## [#919] Aggressor to navigate toward when no LOS
var _last_hostile_nav_log_frame: int = -100  ## [#919] Throttle hostile nav logs

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


## [#919] Unified tick: handles both aggressive combat and non-aggressive enemy detection of aggressors.
## Returns true if this enemy took over AI processing (caller should return early).
## - If this enemy IS aggressive: runs process_combat() as before.
## - If NOT aggressive: detects aggressive enemies and engages or pursues them (like the player).
##   With LOS: face, aim, and shoot at the aggressor.
##   Without LOS: navigate toward the nearest aggressor (same as #729 pattern for aggressive enemies).
func process_aggression_tick(delta: float, rotation_speed: float, shoot_cooldown: float, combat_move_speed: float) -> bool:
	if not _parent: return false
	if _is_aggressive:
		process_combat(delta, rotation_speed, shoot_cooldown, combat_move_speed)
		return true
	# [#919] Non-aggressive: find and attack or pursue any aggressive enemy
	# First, refresh cached LOS target if it's no longer valid
	if _hostile_aggressor == null or not is_instance_valid(_hostile_aggressor) or _hostile_aggressor.get("_is_alive") == false or not _hostile_aggressor.has_method("is_aggressive") or not _hostile_aggressor.is_aggressive():
		_hostile_aggressor = _find_nearest_aggressive_enemy_with_los()
	if _hostile_aggressor != null:
		# Have LOS to aggressor - engage as if it were the player
		var d := (_hostile_aggressor.global_position - _parent.global_position).normalized()
		var ad := wrapf(d.angle() - _parent.rotation, -PI, PI)
		if abs(ad) <= rotation_speed * delta: _parent.rotation = d.angle()
		elif ad > 0: _parent.rotation += rotation_speed * delta
		else: _parent.rotation -= rotation_speed * delta
		if _parent.has_method("_force_model_to_face_direction"): _parent._force_model_to_face_direction(d)
		var wf: Vector2 = _parent._get_weapon_forward_direction() if _parent.has_method("_get_weapon_forward_direction") else Vector2.RIGHT.rotated(_parent.rotation)
		if wf.dot(d) >= 0.866 and _parent._can_shoot() and _parent._shoot_timer >= shoot_cooldown:
			_log("[#919] Shooting at aggressor %s" % _hostile_aggressor.name)
			_parent._shoot(); _parent._shoot_timer = 0.0
		_parent.velocity = Vector2.ZERO
		return true
	# [#919] No LOS aggressor — navigate toward nearest aggressive enemy (same as #729 pattern)
	_hostile_nav_target = _find_nearest_aggressive_enemy_any()
	if _hostile_nav_target != null:
		if _parent.has_method("_move_to_target_nav"):
			_parent._move_to_target_nav(_hostile_nav_target.global_position, combat_move_speed)
			var frame := Engine.get_physics_frames()
			if frame - _last_hostile_nav_log_frame >= 60:
				_last_hostile_nav_log_frame = frame
				_log("[#919] Moving to aggressor %s (no LOS)" % _hostile_nav_target.name)
		return true
	return false  # No aggressive enemy anywhere — normal AI handles this

## [#919] Find the nearest aggressive enemy with line of sight (for non-aggressive enemy targeting).
func _find_nearest_aggressive_enemy_with_los() -> Node2D:
	if not _parent: return null
	var best: Node2D = null; var best_d := INF
	for e in _parent.get_tree().get_nodes_in_group("enemies"):
		if e == _parent or not is_instance_valid(e) or not e is Node2D: continue
		if e.get("_is_alive") == false: continue
		if not e.has_method("is_aggressive") or not e.is_aggressive(): continue
		var d := _parent.global_position.distance_to(e.global_position)
		if d < best_d and _has_los(e): best_d = d; best = e
	return best

## [#919] Find the nearest aggressive enemy regardless of LOS (for navigation when no LOS available).
## Mirrors _find_nearest_enemy_any() but filters for aggressive enemies only.
func _find_nearest_aggressive_enemy_any() -> Node2D:
	if not _parent: return null
	var best: Node2D = null; var best_d := INF
	for e in _parent.get_tree().get_nodes_in_group("enemies"):
		if e == _parent or not is_instance_valid(e) or not e is Node2D: continue
		if e.get("_is_alive") == false: continue
		if not e.has_method("is_aggressive") or not e.is_aggressive(): continue
		var d := _parent.global_position.distance_to(e.global_position)
		if d < best_d: best_d = d; best = e
	return best

func get_debug_text() -> String:
	if _is_aggressive: return "\n{AGGRESSIVE%s}" % (" -> %s" % _target.name if _target and is_instance_valid(_target) else "")
	if _hostile_aggressor and is_instance_valid(_hostile_aggressor): return "\n{ENGAGING AGGRESSOR -> %s}" % _hostile_aggressor.name
	if _hostile_nav_target and is_instance_valid(_hostile_nav_target): return "\n{PURSUING AGGRESSOR -> %s (no LOS)}" % _hostile_nav_target.name
	return ""

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
