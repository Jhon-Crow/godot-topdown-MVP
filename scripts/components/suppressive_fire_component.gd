extends Node
## Suppressive fire component for Issue #910: enemies fire fan-shots toward invisible player's sound source.
## Extracted from enemy.gd to keep it within the 5000-line architecture limit.
## Also includes muzzle flash detection for invisible player (Issue #910):
## when the invisible player fires their weapon, enemies detect the muzzle flash and fire toward it.
class_name SuppressiveFireComponent

## Fan/spread angle (radians) when firing suppressive rounds at invisible player's sound source.
const SUPPRESSIVE_RANGE: float = 600.0  ## Maximum range (px) to fire suppressive shots.
const FAN_SPREAD: float = 0.5  ## ~28.6° half-angle spread for fan fire.

var _enemy: Node2D = null  ## Parent enemy node.
var _muzzle_flash_detection: MuzzleFlashDetectionComponent = null  ## Issue #910: flash detection.

func _ready() -> void:
	_enemy = get_parent() as Node2D
	_muzzle_flash_detection = MuzzleFlashDetectionComponent.new()

## Per-physics-frame: check for muzzle flash from invisible player and update enemy's last known position.
func _physics_process(delta: float) -> void:
	if _enemy == null or _muzzle_flash_detection == null or _enemy._player == null:
		return
	# Note: muzzle flash is a fresh visual stimulus — do NOT block it with confusion timer.
	# Issue #910: blinded enemies cannot see flashes; visible players use normal targeting.
	if _enemy._can_see_player or _enemy._is_blinded:
		_muzzle_flash_detection.reset(); return
	var es: Node = _enemy.get_node_or_null("/root/ExperimentalSettings")
	var fov_on: bool = _enemy.fov_enabled and es != null and es.has_method("is_fov_enabled") and es.is_fov_enabled()
	var facing_angle: float = _enemy._enemy_model.global_rotation if _enemy._enemy_model else _enemy.rotation
	if _muzzle_flash_detection.check_muzzle_flash(_enemy.global_position, facing_angle, _enemy.fov_angle, fov_on, _enemy._player, _enemy._raycast, _enemy._can_see_player, delta):
		if _enemy._memory: _enemy._memory.update_position(_muzzle_flash_detection.estimated_player_position, MuzzleFlashDetectionComponent.MUZZLE_FLASH_DETECTION_CONFIDENCE)
		_enemy._last_known_player_position = _muzzle_flash_detection.estimated_player_position
		_enemy._log_to_file("[#910] Muzzle flash detected (invisible player): est_pos=%s" % _muzzle_flash_detection.estimated_player_position)
		# Issue #910: muzzle flash is a visual hostile event — transition to COMBAT (not PURSUING).
		# Owner requirement: "когда на врага попадает вспышка — он должен переходить в боевое состояние"
		if _enemy._current_state in [0, 8, 9]:  # AIState.IDLE=0, SEARCHING=8, EVADING_GRENADE=9
			_enemy._log_to_file("[#910] Muzzle flash triggered COMBAT from %s" % _enemy._current_state)
			_enemy._transition_to_combat()
		# Also fire immediately at flash position regardless of current state (if not already shooting)
		if not _enemy._can_see_player and not _enemy._is_reloading:
			shoot(_muzzle_flash_detection.estimated_player_position)

## Fire suppressive fan-shot toward invisible player's last known sound/flash position (Issue #910).
## Called from _process_pursuing_state, _process_in_cover_state, and sound handlers when player is invisible.
func shoot(target_pos: Vector2) -> void:
	if _enemy.bullet_scene == null or not _enemy._can_shoot(): return
	if _enemy._shoot_timer < _enemy.shoot_cooldown: return  # Respect shoot cooldown
	var to_target := (target_pos - _enemy.global_position).normalized()
	if to_target == Vector2.ZERO: return
	var direction := to_target.rotated(randf_range(-FAN_SPREAD, FAN_SPREAD))
	var spawn_pos: Vector2 = _enemy._get_bullet_spawn_position(_enemy._get_weapon_forward_direction())
	if not _enemy._is_bullet_spawn_clear(direction): _enemy._log_debug("[#910] Suppressive blocked: wall"); return
	_enemy._spawn_projectile(direction, spawn_pos); _enemy._spawn_muzzle_flash(spawn_pos, direction)
	_enemy._log_to_file("[#910] Suppressive shot toward invisible player sound at %s" % target_pos)
	var audio: Node = _enemy.get_node_or_null("/root/AudioManager")
	if audio:
		if _enemy._is_shotgun_weapon and audio.has_method("play_shotgun_shot"): audio.play_shotgun_shot(_enemy.global_position)
		elif _enemy.weapon_type == 4 and audio.has_method("play_ak_shot"): audio.play_ak_shot(_enemy.global_position)  # [#1033] MACHINE_GUN(4) = AK sound
		elif audio.has_method("play_m16_shot"): audio.play_m16_shot(_enemy.global_position)
	var sp: Node = _enemy.get_node_or_null("/root/SoundPropagation")
	if sp and sp.has_method("emit_sound"): sp.emit_sound(0, _enemy.global_position, 1, _enemy, _enemy.weapon_loudness)
	_enemy._play_delayed_shell_sound()
	_enemy._shoot_timer = 0.0  # Reset cooldown after each suppressive shot
	_enemy._current_ammo -= 1; _enemy._shot_count += 1; _enemy._spread_timer = 0.0
	_enemy.ammo_changed.emit(_enemy._current_ammo, _enemy._reserve_ammo)
	if _enemy._current_ammo <= 0 and _enemy._reserve_ammo > 0: _enemy._start_reload()

## Issue #910: Fire suppressive shot at a player sound position if player is invisible.
## Called directly from on_sound_heard_with_intensity for all player sound types.
## Returns true if a shot was fired or attempted.
func try_shoot_on_sound(player: Node, position: Vector2, sound_name: String) -> bool:
	if player == null or not player.has_method("is_invisible") or not player.is_invisible(): return false
	_enemy._log_to_file("[#910] Invisible player %s sound — firing suppressive at %s" % [sound_name, position])
	shoot(position)
	return true

## Check and fire suppressive rounds during PURSUING state. Updates enemy shoot_timer if a shot is fired.
## Returns true if suppressive fire was attempted (regardless of shot success), false if conditions not met.
func try_suppress_pursuing(can_see: bool, last_pos: Vector2, is_melee: bool, player: Node, is_reloading: bool, shoot_timer: float, cooldown: float) -> bool:
	if can_see or is_melee: return false
	if not player or not player.has_method("is_invisible") or not player.is_invisible(): return false
	# Prefer flash-detected position (more accurate) over last sound position
	var target_pos := _muzzle_flash_detection.estimated_player_position if (_muzzle_flash_detection and _muzzle_flash_detection.detected) else last_pos
	if target_pos == Vector2.ZERO or _enemy.global_position.distance_to(target_pos) > SUPPRESSIVE_RANGE or is_reloading: return false
	if shoot_timer >= cooldown: shoot(target_pos); _enemy._shoot_timer = 0.0
	return true

## Check and fire suppressive rounds during IN_COVER state. Returns true if suppressing (stay in cover).
func try_suppress_cover(player: Node, last_pos: Vector2, is_melee: bool, is_reloading: bool, shoot_timer: float, cooldown: float) -> bool:
	if not player or not player.has_method("is_invisible") or not player.is_invisible(): return false
	if is_melee: return false
	# Prefer flash-detected position (more accurate) over last sound position
	var target_pos := _muzzle_flash_detection.estimated_player_position if (_muzzle_flash_detection and _muzzle_flash_detection.detected) else last_pos
	if target_pos == Vector2.ZERO or _enemy.global_position.distance_to(target_pos) > SUPPRESSIVE_RANGE or is_reloading: return false
	if shoot_timer >= cooldown: shoot(target_pos); _enemy._shoot_timer = 0.0
	return true
