extends Node
## Suppressive fire component for Issue #910: enemies fire fan-shots toward invisible player's sound source.
## Extracted from enemy.gd to keep it within the 5000-line architecture limit.
class_name SuppressiveFireComponent

## Fan/spread angle (radians) when firing suppressive rounds at invisible player's sound source.
const SUPPRESSIVE_RANGE: float = 600.0  ## Maximum range (px) to fire suppressive shots.
const FAN_SPREAD: float = 0.5  ## ~28.6° half-angle spread for fan fire.

var _enemy: Node2D = null  ## Parent enemy node.

func _ready() -> void:
	_enemy = get_parent() as Node2D

## Fire suppressive fan-shot toward invisible player's last known sound position (Issue #910).
## Called from _process_pursuing_state and _process_in_cover_state when player is invisible.
func shoot(target_pos: Vector2) -> void:
	if _enemy.bullet_scene == null or not _enemy._can_shoot(): return
	var to_target := (target_pos - _enemy.global_position).normalized()
	if to_target == Vector2.ZERO: return
	var direction := to_target.rotated(randf_range(-FAN_SPREAD, FAN_SPREAD))
	var spawn_pos := _enemy._get_bullet_spawn_position(_enemy._get_weapon_forward_direction())
	if not _enemy._is_bullet_spawn_clear(direction): _enemy._log_debug("[#910] Suppressive blocked: wall"); return
	_enemy._spawn_projectile(direction, spawn_pos); _enemy._spawn_muzzle_flash(spawn_pos, direction)
	_enemy._log_to_file("[#910] Suppressive shot toward invisible player sound at %s" % target_pos)
	var audio: Node = _enemy.get_node_or_null("/root/AudioManager")
	if audio:
		if _enemy._is_shotgun_weapon and audio.has_method("play_shotgun_shot"): audio.play_shotgun_shot(_enemy.global_position)
		elif audio.has_method("play_m16_shot"): audio.play_m16_shot(_enemy.global_position)
	var sp: Node = _enemy.get_node_or_null("/root/SoundPropagation")
	if sp and sp.has_method("emit_sound"): sp.emit_sound(0, _enemy.global_position, 1, _enemy, _enemy.weapon_loudness)
	_enemy._play_delayed_shell_sound()
	_enemy._current_ammo -= 1; _enemy._shot_count += 1; _enemy._spread_timer = 0.0
	_enemy.ammo_changed.emit(_enemy._current_ammo, _enemy._reserve_ammo)
	if _enemy._current_ammo <= 0 and _enemy._reserve_ammo > 0: _enemy._start_reload()

## Check and fire suppressive rounds during PURSUING state. Updates enemy shoot_timer if a shot is fired.
## Returns true if suppressive fire was attempted (regardless of shot success), false if conditions not met.
func try_suppress_pursuing(can_see: bool, last_pos: Vector2, is_melee: bool, player: Node, is_reloading: bool, shoot_timer: float, cooldown: float) -> bool:
	if can_see or last_pos == Vector2.ZERO or is_melee: return false
	if not player or not player.has_method("is_invisible") or not player.is_invisible(): return false
	if _enemy.global_position.distance_to(last_pos) > SUPPRESSIVE_RANGE or is_reloading: return false
	if shoot_timer >= cooldown: shoot(last_pos); _enemy._shoot_timer = 0.0
	return true

## Check and fire suppressive rounds during IN_COVER state. Returns true if suppressing (stay in cover).
func try_suppress_cover(player: Node, last_pos: Vector2, is_melee: bool, is_reloading: bool, shoot_timer: float, cooldown: float) -> bool:
	if not player or not player.has_method("is_invisible") or not player.is_invisible(): return false
	if last_pos == Vector2.ZERO or is_melee: return false
	if _enemy.global_position.distance_to(last_pos) > SUPPRESSIVE_RANGE or is_reloading: return false
	if shoot_timer >= cooldown: shoot(last_pos); _enemy._shoot_timer = 0.0
	return true
