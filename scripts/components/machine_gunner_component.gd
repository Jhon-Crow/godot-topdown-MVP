extends Node
class_name MachineGunnerComponent
## Machine gunner enemy component (Issue #1033).
## Handles machine gunner specific behaviors:
##   1. Corridor suppression: sustained fire at last-known player position (no LOS needed).
##   2. PM fallback: switch to sidearm and retreat to distant cover when belt empties.
##   3. Distant cover search: prefer hidden positions far from the player for retreat.
## Extracted from enemy.gd to keep the file below the 5000-line CI limit.

## Reference to the owner enemy node. Set explicitly by enemy.gd on instantiation
## (preferred) or resolved via get_parent() in _ready() as a fallback.
var enemy: CharacterBody2D = null

## Enable file logging (forwarded from enemy debug setting).
var log_to_file_fn: Callable = Callable()


func _ready() -> void:
	if enemy == null:
		enemy = get_parent() as CharacterBody2D


## [#1033] Machine gunner corridor suppression: burst into corridor where player was last seen (no LOS needed).
func fire_at_corridor(target_pos: Vector2) -> void:
	if enemy == null or enemy.bullet_scene == null: return
	# Issue #1334 Round 5: Don't shoot at a dead player
	var _gm := enemy.get_node_or_null("/root/GameManager")
	if _gm and not _gm.player_alive: return
	var to_target := (target_pos - enemy.global_position).normalized()
	if to_target == Vector2.ZERO: return
	# Face toward the corridor
	if enemy._enemy_model: enemy._enemy_model.global_rotation = to_target.angle()
	enemy._rotate_body_toward(to_target.angle(), enemy.get_physics_process_delta_time())
	var spawn_pos := enemy._get_bullet_spawn_position(to_target)
	# Small spread (±5°) to simulate suppressive corridor fire
	var spread := deg_to_rad(randf_range(-5.0, 5.0))
	var direction := to_target.rotated(spread)
	if not enemy._is_bullet_spawn_clear(direction): return
	enemy._spawn_projectile(direction, spawn_pos)
	enemy._spawn_muzzle_flash(spawn_pos, direction)
	enemy._spawn_casing(direction, to_target)
	var audio: Node = enemy.get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_ak_shot"): audio.play_ak_shot(enemy.global_position)
	var sp: Node = enemy.get_node_or_null("/root/SoundPropagation")
	var _now_mg := Time.get_ticks_msec() / 1000.0
	if sp and sp.has_method("emit_sound") and _now_mg - enemy._last_gunshot_propagation_time >= enemy.ENEMY_GUNSHOT_PROPAGATION_COOLDOWN:
		sp.emit_sound(0, enemy.global_position, 1, enemy, enemy.weapon_loudness)
		enemy._last_gunshot_propagation_time = _now_mg
	enemy._play_delayed_shell_sound()
	enemy._shoot_timer = 0.0
	enemy._current_ammo -= 1; enemy._shot_count += 1
	enemy.ammo_changed.emit(enemy._current_ammo, enemy._reserve_ammo)
	if log_to_file_fn.is_valid():
		log_to_file_fn.call("[#1033] MG corridor suppression: fired at passage %s, ammo=%d" % [target_pos, enemy._current_ammo])
	if enemy._current_ammo <= 0 and enemy._reserve_ammo > 0:
		enemy._start_reload()
	elif enemy._current_ammo <= 0 and enemy._reserve_ammo <= 0 and not enemy._machine_gunner_pm_active:
		activate_pm_fallback()


## [#1033] Machine gunner PM fallback: switch to RIFLE-config sidearm and retreat to distant cover.
func activate_pm_fallback() -> void:
	if enemy == null: return
	enemy._machine_gunner_pm_active = true; enemy._machine_gunner_suppressing_corridor = false
	enemy.weapon_type = 0  # WeaponType.RIFLE == 0
	enemy._configure_weapon_type()
	enemy.magazine_size = 8; enemy.total_magazines = 2
	enemy._current_ammo = enemy.magazine_size; enemy._reserve_ammo = enemy.magazine_size
	enemy._is_reloading = false; enemy._reload_timer = 0.0
	enemy._goap_world_state["ammo_depleted"] = false
	find_distant_cover()  # [#1033] Retreat to DISTANT cover, not closest
	if log_to_file_fn.is_valid():
		log_to_file_fn.call("[#1033] Machine gunner belts empty — switched to PM, retreating to distant cover")
	enemy._transition_to_retreating()


## [#1033] Find cover far from player for machine gunner PM fallback (prefers hidden + far, opposite of normal).
func find_distant_cover() -> void:
	if enemy == null: return
	if enemy._player == null: enemy._has_valid_cover = false; return
	var current_time := Time.get_ticks_msec() / 1000.0  ## Issue #1411: throttle
	if current_time - enemy._last_distant_cover_search_time < enemy.COVER_SEARCH_COOLDOWN: return  ## Issue #1411: cooldown applies even without valid cover
	enemy._last_distant_cover_search_time = current_time
	var player_pos := enemy._player.global_position
	var best_cover: Vector2 = Vector2.ZERO; var best_score: float = -INF; var found_hidden: bool = false
	for i in range(enemy.COVER_CHECK_COUNT):
		var raycast := enemy._cover_raycasts[i]
		raycast.target_position = Vector2.from_angle((float(i) / enemy.COVER_CHECK_COUNT) * TAU) * enemy.COVER_CHECK_DISTANCE
		raycast.force_raycast_update()
		if not raycast.is_colliding(): continue
		var cover_pos := raycast.get_collision_point() + raycast.get_collision_normal() * 35.0
		if enemy.is_teleporter and enemy.global_position.distance_to(cover_pos) < 10.0: continue  # Issue #1355
		if not enemy._can_reach_position(cover_pos): continue
		var is_hidden := not enemy._is_position_visible_from_player(cover_pos)
		if not is_hidden and found_hidden: continue
		var dist_to_player := cover_pos.distance_to(player_pos)
		var total_score := (10.0 if is_hidden else 0.0) + dist_to_player / enemy.COVER_CHECK_DISTANCE
		if is_hidden and not found_hidden:
			found_hidden = true; best_score = total_score; best_cover = cover_pos
		elif (is_hidden or not found_hidden) and total_score > best_score:
			best_score = total_score; best_cover = cover_pos
	if best_score > 0:
		enemy._cover_position = best_cover; enemy._has_valid_cover = true
		if log_to_file_fn.is_valid():
			log_to_file_fn.call("[#1033] Distant cover found at %s (dist_to_player=%.0f)" % [best_cover, best_cover.distance_to(player_pos)])
	else:
		enemy._find_cover_position()  # Fallback to normal cover search
