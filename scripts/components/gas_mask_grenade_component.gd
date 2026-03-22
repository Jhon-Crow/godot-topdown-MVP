extends EnemyGrenadeComponent
## Gas Mask Enemy grenade component (Issue #1129).
##
## Manages 4 chemical grenades. In combat state, the gas mask enemy throws
## a chemical grenade at the player before shooting.
##
## Cooldown rules after each throw:
## - If the player is NOT yet under the illusion effect: 4-second cooldown.
## - If the player IS under the illusion effect: wait until effect expires,
##   then resume throwing (no new throw while effect is active).
##
## Per issue #1129 comment (Mar 20):
## - новый тип врага «в противогазе» (gas mask enemy)
## - 4 химических гранаты
## - в состоянии боя бросает гранаты перед стрельбой (цель — игрок)
## - после первого броска — перезарядка 4 сек, если игрок не получил эффект
## - или ожидает до выхода игрока из эффекта, если тот уже под эффектом
class_name GasMaskGrenadeComponent

## Cooldown duration (seconds) when player is NOT under illusion effect.
const COOLDOWN_NO_EFFECT: float = 4.0

## Preloaded chemical grenade scene.
var _chemical_scene: PackedScene = null

## Whether the component is waiting for the player to exit the illusion effect.
var _waiting_for_effect_to_expire: bool = false


func _ready() -> void:
	_logger = get_node_or_null("/root/FileLogger")
	_enemy = get_parent() as CharacterBody2D


## Initialize with 4 chemical grenades.
func initialize() -> void:
	_cooldown = 0.0
	_is_throwing = false
	_reset_triggers()

	_chemical_scene = load("res://scenes/projectiles/ChemicalGasGrenade.tscn")
	if _chemical_scene == null:
		_log("WARNING: ChemicalGasGrenade.tscn not found — gas mask grenade disabled")
	else:
		_log("GasMaskGrenadeComponent initialized: 4 chemical grenades")

	grenade_scene = _chemical_scene
	grenade_count = 4
	grenades_remaining = 4


## Override update to handle illusion-effect cooldown tracking.
func update(delta: float, can_see: bool, under_fire: bool, player: Node2D, health: int, memory = null) -> void:
	if not enabled or grenades_remaining <= 0:
		return

	if _cooldown > 0.0:
		_cooldown -= delta

	# Track kill witness timer
	if _kill_reset_timer > 0.0:
		_kill_reset_timer -= delta
		if _kill_reset_timer <= 0.0:
			_kills_witnessed = 0

	# If we threw a grenade and the player was under effect, wait until it expires
	if _waiting_for_effect_to_expire:
		var status_manager: Node = get_node_or_null("/root/StatusEffectsManager")
		if status_manager and status_manager.has_method("is_player_under_illusion"):
			if not status_manager.is_player_under_illusion():
				# Effect expired — player can be targeted again
				_waiting_for_effect_to_expire = false
				_cooldown = 0.0
				_log("Player illusion expired — gas mask enemy can throw again")


## Override is_ready: throw when player is visible in combat (before shooting).
func is_ready(can_see: bool, under_fire: bool, health: int) -> bool:
	if not enabled or grenades_remaining <= 0 or _cooldown > 0.0 or _is_throwing:
		return false
	if _chemical_scene == null:
		return false
	if _waiting_for_effect_to_expire:
		return false
	# Only throw when player is visible (combat condition)
	return can_see


## Override get_target: always target the player's current position.
func get_target(can_see: bool, under_fire: bool, health: int, player: Node2D,
				last_known: Vector2, memory_pos: Vector2) -> Vector2:
	if player and can_see:
		return player.global_position
	if memory_pos != Vector2.ZERO:
		return memory_pos
	return last_known


## Override try_throw to use chemical grenade with illusion-aware cooldown.
func try_throw(target: Vector2, is_alive: bool, is_stunned: bool, is_blinded: bool) -> bool:
	if not enabled or grenades_remaining <= 0 or _cooldown > 0.0 or _is_throwing:
		return false
	if not is_alive or is_stunned or is_blinded or target == Vector2.ZERO or _enemy == null:
		return false
	if _chemical_scene == null:
		return false
	if _waiting_for_effect_to_expire:
		return false

	var dist := _enemy.global_position.distance_to(target)

	# Chemical grenade has no lethal blast radius — safety check uses effect_radius
	var min_safe_distance := 50.0  # minimal safe distance for gas grenade (no explosion)
	if dist < min_safe_distance:
		_log("Too close for chemical grenade (dist=%.0f) — skipping" % dist)
		return false

	if dist > max_throw_distance:
		target = _enemy.global_position + (target - _enemy.global_position).normalized() * max_throw_distance

	if not _path_clear(target):
		_log("Throw path blocked to %s" % target)
		return false

	_execute_gas_throw(target, is_alive, is_stunned, is_blinded)
	return true


## Execute a chemical grenade throw with appropriate cooldown logic.
func _execute_gas_throw(target: Vector2, is_alive: bool, is_stunned: bool, is_blinded: bool) -> void:
	_is_throwing = true

	# Signal enemy to face throw direction
	var throw_dir := (target - _enemy.global_position).normalized()
	face_throw_direction.emit(throw_dir)

	# Wait for enemy to rotate toward target
	if face_direction_delay > 0.0:
		await get_tree().create_timer(face_direction_delay).timeout

	if throw_delay > 0.0:
		await get_tree().create_timer(throw_delay).timeout

	if not is_alive or is_stunned or is_blinded or not is_instance_valid(self) or not is_instance_valid(_enemy):
		_is_throwing = false
		return

	var dir := (target - _enemy.global_position).normalized().rotated(randf_range(-inaccuracy, inaccuracy))
	var grenade: Node2D = _chemical_scene.instantiate()
	grenade.global_position = _enemy.global_position + dir * 40.0

	# Set thrower_id so grenade won't affect the thrower
	if grenade.get("thrower_id") != null:
		grenade.thrower_id = _enemy.get_instance_id()

	var parent := get_tree().current_scene
	(parent if parent else _enemy.get_parent()).add_child(grenade)

	# Attach C# GrenadeTimer for gas type
	_attach_grenade_timer(grenade as RigidBody2D, "Gas")

	if grenade.has_method("activate_timer"):
		grenade.activate_timer()
	_activate_grenade_timer(grenade as RigidBody2D)

	var dist := _enemy.global_position.distance_to(target)
	if grenade.has_method("throw_grenade"):
		grenade.throw_grenade(dir, dist)
	elif grenade is RigidBody2D:
		grenade.freeze = false
		grenade.linear_velocity = dir * clampf(dist * 1.5, 200.0, 800.0)
		grenade.rotation = dir.angle()

	_mark_grenade_thrown(grenade as RigidBody2D)
	_set_grenade_thrower(grenade as RigidBody2D, _enemy.get_instance_id())

	grenades_remaining -= 1
	_is_throwing = false
	_reset_triggers()
	grenade_thrown.emit(grenade, target)

	# Determine cooldown based on whether player is already under effect
	var status_manager: Node = get_node_or_null("/root/StatusEffectsManager")
	var player_under_effect := false
	if status_manager and status_manager.has_method("is_player_under_illusion"):
		player_under_effect = status_manager.is_player_under_illusion()

	if player_under_effect:
		# Player is already under effect: wait until it expires before throwing again
		_waiting_for_effect_to_expire = true
		_cooldown = 0.0
		_log("Chemical grenade thrown — player under effect, waiting for expiry before next throw")
	else:
		# Player not yet under effect: 4-second cooldown
		_cooldown = COOLDOWN_NO_EFFECT
		_log("Chemical grenade thrown — player not yet under effect, cooldown=%.1fs" % _cooldown)

	_log("Gas mask enemy threw chemical grenade! Target: %s, dist=%.0f, %d remaining" % [
		str(target), dist, grenades_remaining
	])
