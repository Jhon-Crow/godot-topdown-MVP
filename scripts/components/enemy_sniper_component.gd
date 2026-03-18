extends Node
## Component that handles sniper rifle AI behavior (Issue #1163).
## Extracted from enemy.gd to keep it below 5000 lines.
## The sniper stays at preferred range, retreats when too close, and blind-fires
## through cover at last-known / predicted player positions.
class_name EnemySniperComponent

## Preferred engagement range (px).
const PREFERRED_DISTANCE: float = 550.0
## Below this distance: actively retreat from player.
const MIN_DISTANCE: float = 350.0
## Seconds between blind-fire shots through cover.
const BLIND_FIRE_COOLDOWN: float = 5.0

## Timer for blind fire at predicted player position.
var blind_fire_timer: float = 0.0

var _enemy: CharacterBody2D = null


func _ready() -> void:
	_enemy = get_parent() as CharacterBody2D


## Process sniper rifle combat behavior: maintain standoff distance and blind-fire through cover.
## Returns true if sniper handling was applied (caller should return early).
func process_combat(delta: float, can_see_player: bool, player: Node,
		last_known_pos: Vector2, prediction: PlayerPredictionComponent) -> bool:
	if player == null:
		return false

	var player_pos: Vector2 = (player as Node2D).global_position
	var distance_to_player: float = _enemy.global_position.distance_to(player_pos)
	var direction_to_player: Vector2 = (player_pos - _enemy.global_position).normalized()

	blind_fire_timer += delta

	if can_see_player:
		if distance_to_player < MIN_DISTANCE:
			var retreat_dir := -direction_to_player
			retreat_dir = (_enemy._apply_wall_avoidance(retreat_dir) as Vector2)
			_enemy.velocity = retreat_dir * _enemy.combat_move_speed
			_enemy._log_debug("Sniper: player too close (%.0f px), retreating" % distance_to_player)
		else:
			_enemy.velocity = Vector2.ZERO

		_enemy._aim_at_player()
		if _enemy._detection_delay_elapsed and _enemy._shoot_timer >= _enemy.shoot_cooldown and _enemy._can_shoot():
			_enemy._shoot()
			_enemy._shoot_timer = 0.0
			blind_fire_timer = 0.0
		return true

	# Player NOT visible: blind-fire at predicted position through cover.
	_enemy.velocity = Vector2.ZERO

	var blind_target := last_known_pos
	if prediction != null and prediction.has_predictions:
		var predicted: Vector2 = prediction.get_best_position()
		if predicted != Vector2.ZERO:
			blind_target = predicted

	if blind_target == Vector2.ZERO:
		_enemy._transition_to_pursuing()
		return true

	_rotate_toward(blind_target, delta)

	if blind_fire_timer >= BLIND_FIRE_COOLDOWN and _enemy._shoot_timer >= _enemy.shoot_cooldown and _enemy._can_shoot():
		fire_at_predicted_position(blind_target)
		blind_fire_timer = 0.0
	return true


## Handle sniper behavior in PURSUING state: hold position and blind-fire when at safe range.
## Returns true if the sniper held position (caller should return early).
func process_pursuing(delta: float, last_known_pos: Vector2, prediction: PlayerPredictionComponent) -> bool:
	blind_fire_timer += delta
	var blind_pos := last_known_pos
	if prediction != null and prediction.has_predictions:
		var ph: Vector2 = prediction.get_best_position()
		if ph != Vector2.ZERO:
			blind_pos = ph
	if blind_pos == Vector2.ZERO:
		return false
	if _enemy.global_position.distance_to(blind_pos) < MIN_DISTANCE:
		return false  # Too close — fall through to normal pursuit to reposition

	_enemy.velocity = Vector2.ZERO
	_rotate_toward(blind_pos, delta)
	if blind_fire_timer >= BLIND_FIRE_COOLDOWN and _enemy._shoot_timer >= _enemy.shoot_cooldown and _enemy._can_shoot():
		fire_at_predicted_position(blind_pos)
		blind_fire_timer = 0.0
	return true


## Fire sniper bullet at a predicted player position through cover walls.
## Uses the same projectile as normal shooting but bypasses the LOS requirement.
func fire_at_predicted_position(target_pos: Vector2) -> void:
	if _enemy.bullet_scene == null: return
	var to_target := (target_pos - _enemy.global_position).normalized()
	if to_target == Vector2.ZERO: return

	var enemy_model: Node = _enemy._enemy_model
	if enemy_model: enemy_model.global_rotation = to_target.angle()
	_enemy.rotation = to_target.angle()

	var spawn_pos: Vector2 = _enemy._get_bullet_spawn_position(to_target)
	var spread := deg_to_rad(randf_range(-3.0, 3.0))
	var direction := to_target.rotated(spread)
	_enemy._spawn_projectile(direction, spawn_pos)
	_enemy._spawn_muzzle_flash(spawn_pos, direction)
	_enemy._spawn_casing(direction, to_target)

	var audio: Node = _enemy.get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_asvk_shot"): audio.play_asvk_shot()

	var sp: Node = _enemy.get_node_or_null("/root/SoundPropagation")
	var now_s := Time.get_ticks_msec() / 1000.0
	if sp and sp.has_method("emit_sound") and now_s - _enemy._last_gunshot_propagation_time >= _enemy.ENEMY_GUNSHOT_PROPAGATION_COOLDOWN:
		sp.emit_sound(0, _enemy.global_position, 1, _enemy, _enemy.weapon_loudness)
		_enemy._last_gunshot_propagation_time = now_s

	_enemy._play_delayed_shell_sound()
	_enemy._shoot_timer = 0.0
	_enemy._current_ammo -= 1
	_enemy._shot_count += 1
	_enemy.ammo_changed.emit(_enemy._current_ammo, _enemy._reserve_ammo)
	_enemy._log_to_file("[#1163] Sniper blind-fire at predicted position %s, ammo=%d" % [target_pos, _enemy._current_ammo])
	if _enemy._current_ammo <= 0 and _enemy._reserve_ammo > 0:
		_enemy._start_reload()


func _rotate_toward(target_pos: Vector2, delta: float) -> void:
	var to_target := (target_pos - _enemy.global_position).normalized()
	if to_target == Vector2.ZERO: return
	var enemy_model: Node = _enemy._enemy_model
	if enemy_model:
		enemy_model.global_rotation = lerp_angle(enemy_model.global_rotation, to_target.angle(), _enemy.rotation_speed * delta)
	_enemy.rotation = lerp_angle(_enemy.rotation, to_target.angle(), _enemy.rotation_speed * delta)
