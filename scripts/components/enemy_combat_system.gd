extends Node
## Component that handles enemy shooting and ammunition management (Issue #336).
## Extracted from enemy.gd to reduce file size below 2500 lines.
class_name EnemyCombatSystem

## Signals
signal ammo_changed(current_ammo: int, reserve_ammo: int)
signal reload_started
signal reload_finished
signal ammo_depleted
signal shot_fired(bullet: Node, spawn_position: Vector2, direction: Vector2)

# Configuration - set from enemy's export vars
var bullet_scene: PackedScene = null
var casing_scene: PackedScene = null
var shoot_cooldown: float = 0.1
var bullet_spawn_offset: float = 30.0
var weapon_loudness: float = 1469.0
var magazine_size: int = 30
var total_magazines: int = 5
var reload_time: float = 3.0
var bullet_speed: float = 2500.0
var enable_lead_prediction: bool = true
var lead_prediction_delay: float = 0.3
var lead_prediction_visibility_threshold: float = 0.6
var debug_logging: bool = false

# Constants
const AIM_TOLERANCE_DOT: float = 0.866  ## cos(30°) - aim tolerance (issue #254/#264)
const RETREAT_INACCURACY_SPREAD: float = 0.15  ## Retreat accuracy penalty
const RETREAT_BURST_ARC: float = 0.4  ## ONE_HIT burst arc (rad)
const RETREAT_BURST_COOLDOWN: float = 0.06  ## Burst shot interval (sec)

# State
var _current_ammo: int = 0
var _reserve_ammo: int = 0
var _is_reloading: bool = false
var _reload_timer: float = 0.0
var _shoot_timer: float = 0.0
var _enemy: CharacterBody2D = null
var _weapon_mount: Node2D = null
var _weapon_sprite: Sprite2D = null

# Retreat burst state
var _retreat_burst_remaining: int = 0
var _retreat_burst_timer: float = 0.0
var _retreat_burst_angle_offset: float = 0.0
var _retreat_burst_complete: bool = false


func _ready() -> void:
	_enemy = get_parent() as CharacterBody2D


## Initialize the combat system with weapon references.
func initialize(weapon_mount: Node2D, weapon_sprite: Sprite2D) -> void:
	_weapon_mount = weapon_mount
	_weapon_sprite = weapon_sprite
	_initialize_ammo()


## Initialize ammunition values.
func _initialize_ammo() -> void:
	_current_ammo = magazine_size
	_reserve_ammo = magazine_size * (total_magazines - 1)


## Update the combat system each frame.
func update(delta: float) -> void:
	_shoot_timer += delta
	_update_reload(delta)
	_update_weapon_sprite_rotation()


## Process reload state each frame.
func _update_reload(delta: float) -> void:
	if not _is_reloading:
		return

	_reload_timer += delta
	if _reload_timer >= reload_time:
		_finish_reload()


## Start reloading the weapon.
func start_reload() -> void:
	if _is_reloading or _reserve_ammo <= 0:
		return

	_is_reloading = true
	_reload_timer = 0.0
	reload_started.emit()
	_log_debug("Reloading... (%d reserve ammo)" % _reserve_ammo)


## Finish the reload process.
func _finish_reload() -> void:
	_is_reloading = false
	_reload_timer = 0.0

	var ammo_needed := magazine_size - _current_ammo
	var ammo_to_load := mini(ammo_needed, _reserve_ammo)

	_reserve_ammo -= ammo_to_load
	_current_ammo += ammo_to_load

	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_reload_full"):
		audio_manager.play_reload_full(_enemy.global_position if _enemy else Vector2.ZERO)

	reload_finished.emit()
	ammo_changed.emit(_current_ammo, _reserve_ammo)
	_log_debug("Reload complete. Magazine: %d/%d, Reserve: %d" % [_current_ammo, magazine_size, _reserve_ammo])


## Check if the enemy can shoot (has ammo and not reloading).
func can_shoot() -> bool:
	if _is_reloading:
		return false

	if _current_ammo <= 0:
		if _reserve_ammo > 0:
			start_reload()
		else:
			ammo_depleted.emit()
			_log_debug("All ammunition depleted!")
		return false

	return true


## Check if shoot cooldown has elapsed.
func is_shoot_ready() -> bool:
	return _shoot_timer >= shoot_cooldown


## Shoot at a target position.
## Returns true if shot was fired, false otherwise.
func shoot(target_position: Vector2, friendly_fire_checker: Callable = Callable(), cover_checker: Callable = Callable()) -> bool:
	if bullet_scene == null or _enemy == null:
		return false

	if not can_shoot() or not is_shoot_ready():
		return false

	# Get weapon direction
	var weapon_forward := get_weapon_forward_direction()
	var bullet_spawn_pos := get_bullet_spawn_position(weapon_forward)

	# Use enemy center for aim check (Issue #344)
	var to_target := (target_position - _enemy.global_position).normalized()

	# Check aim tolerance
	var aim_dot := weapon_forward.dot(to_target)
	if aim_dot < AIM_TOLERANCE_DOT:
		if debug_logging:
			var aim_angle_deg := rad_to_deg(acos(clampf(aim_dot, -1.0, 1.0)))
			_log_debug("SHOOT BLOCKED: Not aimed. aim_dot=%.3f (%.1f deg off)" % [aim_dot, aim_angle_deg])
		return false

	# Check friendly fire
	if friendly_fire_checker.is_valid() and not friendly_fire_checker.call(target_position):
		_log_debug("SHOOT BLOCKED: Friendly in line of fire")
		return false

	# Check cover obstruction
	if cover_checker.is_valid() and not cover_checker.call(target_position):
		_log_debug("SHOOT BLOCKED: Cover in the way")
		return false

	# Check bullet spawn is clear
	if not _is_bullet_spawn_clear(weapon_forward):
		_log_debug("SHOOT BLOCKED: Wall at muzzle")
		return false

	# Fire the bullet
	_fire_bullet(bullet_spawn_pos, weapon_forward)
	return true


## Shoot with reduced accuracy for retreat mode.
func shoot_with_inaccuracy(target_position: Vector2) -> bool:
	if bullet_scene == null or _enemy == null:
		return false

	if not can_shoot() or not is_shoot_ready():
		return false

	var weapon_forward := get_weapon_forward_direction()
	var bullet_spawn_pos := get_bullet_spawn_position(weapon_forward)
	var to_target := (target_position - _enemy.global_position).normalized()

	var aim_dot := weapon_forward.dot(to_target)
	if aim_dot < AIM_TOLERANCE_DOT:
		return false

	# Add inaccuracy spread
	var direction := weapon_forward
	var inaccuracy_angle := randf_range(-RETREAT_INACCURACY_SPREAD, RETREAT_INACCURACY_SPREAD)
	direction = direction.rotated(inaccuracy_angle)

	if not _is_bullet_spawn_clear(direction):
		return false

	_fire_bullet(bullet_spawn_pos, direction)
	return true


## Shoot a burst shot with arc spread.
func shoot_burst_shot(target_position: Vector2, arc_offset: float) -> bool:
	if bullet_scene == null or _enemy == null:
		return false

	if not can_shoot():
		return false

	var weapon_forward := get_weapon_forward_direction()
	var bullet_spawn_pos := get_bullet_spawn_position(weapon_forward)
	var to_target := (target_position - _enemy.global_position).normalized()

	var aim_dot := weapon_forward.dot(to_target)
	if aim_dot < AIM_TOLERANCE_DOT:
		return false

	var direction := weapon_forward.rotated(arc_offset)
	var inaccuracy_angle := randf_range(-RETREAT_INACCURACY_SPREAD * 0.5, RETREAT_INACCURACY_SPREAD * 0.5)
	direction = direction.rotated(inaccuracy_angle)

	if not _is_bullet_spawn_clear(direction):
		return false

	_fire_bullet(bullet_spawn_pos, direction)
	return true


## Fire a bullet with sound effects.
func _fire_bullet(spawn_pos: Vector2, direction: Vector2) -> void:
	var bullet := bullet_scene.instantiate()
	bullet.global_position = spawn_pos
	bullet.direction = direction
	bullet.shooter_id = _enemy.get_instance_id()
	bullet.shooter_position = spawn_pos
	get_tree().current_scene.add_child(bullet)

	# Play sounds
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_m16_shot"):
		audio_manager.play_m16_shot(_enemy.global_position)

	# Sound propagation
	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		sound_propagation.emit_sound(0, _enemy.global_position, 1, _enemy, weapon_loudness)

	_play_delayed_shell_sound()

	# Consume ammo
	_current_ammo -= 1
	_shoot_timer = 0.0
	ammo_changed.emit(_current_ammo, _reserve_ammo)

	if _current_ammo <= 0 and _reserve_ammo > 0:
		start_reload()

	shot_fired.emit(bullet, spawn_pos, direction)


## Play shell casing sound after delay.
func _play_delayed_shell_sound() -> void:
	if _enemy == null:
		return

	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_casing_sound_delayed"):
		audio_manager.play_casing_sound_delayed(_enemy.global_position, 0.3)

	# Spawn casing if scene is set
	if casing_scene:
		var casing := casing_scene.instantiate()
		casing.global_position = get_bullet_spawn_position(get_weapon_forward_direction())
		get_tree().current_scene.add_child(casing)


## Get the weapon's forward direction.
func get_weapon_forward_direction() -> Vector2:
	if _weapon_mount == null:
		return Vector2.RIGHT.rotated(_enemy.rotation if _enemy else 0.0)

	var weapon_angle := _weapon_mount.global_rotation
	return Vector2.RIGHT.rotated(weapon_angle)


## Get the bullet spawn position at the weapon muzzle.
func get_bullet_spawn_position(direction: Vector2) -> Vector2:
	if _enemy == null:
		return Vector2.ZERO

	return _enemy.global_position + direction * bullet_spawn_offset


## Check if bullet spawn point is clear of walls.
func _is_bullet_spawn_clear(direction: Vector2) -> bool:
	if _enemy == null:
		return false

	var space_state := _enemy.get_world_2d().direct_space_state
	if space_state == null:
		return true

	var query := PhysicsRayQueryParameters2D.create(
		_enemy.global_position,
		_enemy.global_position + direction * bullet_spawn_offset,
		2  # Wall collision layer
	)
	query.exclude = [_enemy]

	var result := space_state.intersect_ray(query)
	return result.is_empty()


## Update weapon sprite rotation to match weapon mount.
func _update_weapon_sprite_rotation() -> void:
	if _weapon_sprite == null or _weapon_mount == null:
		return

	_weapon_sprite.rotation = _weapon_mount.rotation


## Calculate lead prediction for moving targets.
func calculate_lead_prediction(player: Node2D, visibility_timer: float, visibility_ratio: float) -> Vector2:
	if player == null or _enemy == null:
		return Vector2.ZERO

	if not enable_lead_prediction:
		return player.global_position

	if visibility_timer < lead_prediction_delay:
		return player.global_position

	if visibility_ratio < lead_prediction_visibility_threshold:
		return player.global_position

	var player_velocity := Vector2.ZERO
	if player.has_method("get_velocity"):
		player_velocity = player.get_velocity()
	elif "velocity" in player:
		player_velocity = player.velocity

	if player_velocity.length_squared() < 100.0:
		return player.global_position

	var distance := _enemy.global_position.distance_to(player.global_position)
	var time_to_target := distance / bullet_speed
	var predicted_pos := player.global_position + player_velocity * time_to_target

	return predicted_pos


# --- Accessors ---

func get_current_ammo() -> int:
	return _current_ammo


func get_reserve_ammo() -> int:
	return _reserve_ammo


func get_total_ammo() -> int:
	return _current_ammo + _reserve_ammo


func is_reloading() -> bool:
	return _is_reloading


func has_ammo() -> bool:
	return _current_ammo > 0 or _reserve_ammo > 0


# --- Debug ---

func _log_debug(message: String) -> void:
	if debug_logging:
		print("[EnemyCombatSystem] ", message)
