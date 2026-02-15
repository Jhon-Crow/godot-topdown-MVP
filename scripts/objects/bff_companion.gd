class_name BffCompanion
extends CharacterBody2D
## BFF Companion NPC summoned by the BFF Pendant active item (Issue #674).
##
## AI modeled EXACTLY after enemy AggressionComponent (Issue #675 gas grenade behavior).
## Differences: targets enemies group (not other enemies), follows player when no target.
## User feedback: "копировать ии врага, но чтоб он был в состоянии agressive"

## Companion died signal (for enemy counter exclusion).
signal companion_died

## Movement speed (px/s) — matches enemy combat_move_speed.
var move_speed: float = 220.0
var combat_move_speed: float = 320.0

## Distance to maintain from the player (px).
var follow_distance: float = 80.0

## Weapon configuration — uses RIFLE (M16), same as enemy defaults.
var shoot_cooldown: float = 0.1  # Match enemy default (10 rounds/sec)
var rotation_speed: float = 25.0  # Match enemy rotation_speed for aim-before-shoot
var bullet_speed: float = 2500.0
var bullet_spawn_offset: float = 30.0
var magazine_size: int = 30

## Health.
var min_health: int = 2
var max_health: int = 4

## Visual scale.
var model_scale: float = 1.3

## Internal state.
var _current_health: int = 0
var _max_health: int = 0
var _is_alive: bool = true
var _player: Node2D = null
var _current_target: Node2D = null  # Enemy target with LOS
var _nav_target: Node2D = null  # Enemy target for navigation (no LOS)
var _shoot_timer: float = 0.0
var _current_ammo: int = 30
var _reload_timer: float = 0.0
var _is_reloading: bool = false
var _reload_time: float = 3.0  # Match enemy reload_time

## Bullet scene.
var _bullet_scene: PackedScene = null

## Spread tracking (progressive spread like enemies - Issue #516).
var _shot_count: int = 0
var _spread_timer: float = 0.0
var _spread_threshold: int = 3
var _initial_spread: float = 0.5
var _spread_increment: float = 0.6
var _max_spread: float = 4.0
var _spread_reset_time: float = 0.25

## Navigation agent for pathfinding.
@onready var _nav_agent: NavigationAgent2D = $NavigationAgent2D

## Node references (resolved from scene tree in _ready).
@onready var _model: Node2D = $CompanionModel
@onready var _body_sprite: Sprite2D = $CompanionModel/Body
@onready var _head_sprite: Sprite2D = $CompanionModel/Head
@onready var _left_arm_sprite: Sprite2D = $CompanionModel/LeftArm
@onready var _right_arm_sprite: Sprite2D = $CompanionModel/RightArm
@onready var _weapon_sprite: Sprite2D = $CompanionModel/WeaponMount/WeaponSprite

## Hit flash.
var _hit_flash_timer: float = 0.0
var _hit_flash_duration: float = 0.1
var _full_health_color: Color = Color(0.2, 1.0, 0.6, 1.0)  # Green-cyan tint for companion
var _low_health_color: Color = Color(0.1, 0.4, 0.2, 1.0)
var _hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Aim tolerance for shooting (dot product threshold) — cos(30°) same as enemy.
const AIM_TOLERANCE_DOT: float = 0.866

## Debug frame counter for periodic logging (every ~60 frames = 1 second).
var _debug_frame_counter: int = 0
const DEBUG_LOG_INTERVAL: int = 60

## Throttle navigation logs to once per second.
var _last_nav_log_frame: int = -100


func _ready() -> void:
	_log("[BffCompanion] _ready() called")
	add_to_group("bff_companions")
	_initialize_health()
	_find_player()
	_load_bullet_scene()
	_update_health_visual()

	# Apply scale to model (same as enemy)
	if _model:
		_model.scale = Vector2(model_scale, model_scale)

	# Setup navigation agent
	if _nav_agent:
		_nav_agent.path_desired_distance = 4.0
		_nav_agent.target_desired_distance = 10.0

	_log("[BffCompanion] Spawned: HP=%d/%d, player=%s" % [_current_health, _max_health, str(_player != null)])


## Unified logging function that uses FileLogger if available, else print.
func _log(message: String) -> void:
	if Engine.has_singleton("FileLogger"):
		var fl = Engine.get_singleton("FileLogger")
		if fl and fl.has_method("info"):
			fl.info(message)
			return
	# Fallback: try autoload node
	var fl_node = get_node_or_null("/root/FileLogger")
	if fl_node and fl_node.has_method("info"):
		fl_node.info(message)
	else:
		# Last resort: print to console
		print(message)


func _load_bullet_scene() -> void:
	var config := WeaponConfigComponent.get_config(0)  # RIFLE config
	if config.get("bullet_scene_path", "") != "":
		var scene := load(config["bullet_scene_path"]) as PackedScene
		if scene:
			_bullet_scene = scene
	if _bullet_scene == null:
		_bullet_scene = preload("res://scenes/projectiles/Bullet.tscn")


func _initialize_health() -> void:
	_max_health = randi_range(min_health, max_health)
	_current_health = _max_health
	_is_alive = true


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		return
	var root := get_tree().current_scene
	if root:
		_player = _find_player_recursive(root)


func _find_player_recursive(node: Node) -> Node2D:
	if node.name == "Player" and node is Node2D:
		return node
	for child in node.get_children():
		var result := _find_player_recursive(child)
		if result:
			return result
	return null


func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	# Update timers (same as enemy)
	_shoot_timer += delta
	_spread_timer += delta
	if _spread_timer >= _spread_reset_time and _spread_reset_time > 0.0:
		_shot_count = 0

	# Update reload (same as enemy)
	if _is_reloading:
		_reload_timer += delta
		if _reload_timer >= _reload_time:
			_current_ammo = magazine_size
			_is_reloading = false
			_reload_timer = 0.0
			_log("[BffCompanion] Reload complete: %d/%d" % [_current_ammo, magazine_size])

	# Update hit flash
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0:
			_update_health_visual()

	# Find player if lost
	if _player == null or not is_instance_valid(_player):
		_find_player()

	# Periodic debug logging
	_debug_frame_counter += 1
	if _debug_frame_counter >= DEBUG_LOG_INTERVAL:
		_debug_frame_counter = 0
		var t := "none" if _current_target == null else _current_target.name
		_log("[BffCompanion] pos=%s, target=%s, ammo=%d, hp=%d" % [
			str(global_position).substr(0, 20), t, _current_ammo, _current_health])

	# === AI Logic (mirrors AggressionComponent.process_combat) ===
	_process_combat_ai(delta)

	move_and_slide()


## Process combat AI — mirrors AggressionComponent.process_combat() exactly.
## Key difference: targets "enemies" group, follows player when no enemies.
func _process_combat_ai(delta: float) -> void:
	# Step 1: Find enemy target with LOS (like _find_nearest_enemy_target_with_los)
	if _current_target == null or not is_instance_valid(_current_target) or _current_target.get("_is_alive") == false:
		_current_target = _find_enemy_with_los()

	# Step 2: If we have LOS to target, engage in combat
	if _current_target != null and _has_los_to(_current_target):
		# Combat mode: rotate toward target and shoot (like aggressive enemy)
		var dir := (_current_target.global_position - global_position).normalized()

		# Rotate toward target (same logic as AggressionComponent)
		var angle_diff := wrapf(dir.angle() - rotation, -PI, PI)
		if abs(angle_diff) <= rotation_speed * delta:
			rotation = dir.angle()
		elif angle_diff > 0:
			rotation += rotation_speed * delta
		else:
			rotation -= rotation_speed * delta

		# Force model to face direction
		if _model:
			_model.rotation = rotation

		# Check aim and shoot (same as AggressionComponent)
		var weapon_forward := Vector2.RIGHT.rotated(rotation)
		if weapon_forward.dot(dir) >= AIM_TOLERANCE_DOT and _can_shoot() and _shoot_timer >= shoot_cooldown:
			_shoot(weapon_forward)
			_shoot_timer = 0.0

		# Stop moving during combat (like aggressive enemy)
		velocity = Vector2.ZERO

	elif _current_target != null:
		# Have target but no LOS — navigate toward them
		_move_to_target_nav(_current_target.global_position, combat_move_speed)

	else:
		# No visible target — find any enemy and navigate, OR follow player
		_nav_target = _find_any_enemy()
		if _nav_target != null:
			# Navigate toward enemy (like aggressive enemy with no LOS)
			_move_to_target_nav(_nav_target.global_position, combat_move_speed)
			# Throttle logging
			var frame := Engine.get_physics_frames()
			if frame - _last_nav_log_frame >= 60:
				_last_nav_log_frame = frame
				_log("[BffCompanion] Moving to %s (no LOS)" % _nav_target.name)
		else:
			# No enemies at all — follow player
			_process_follow_player(delta)


## Find nearest enemy with line of sight (for combat targeting).
## Mirrors AggressionComponent._find_nearest_enemy_target_with_los().
func _find_enemy_with_los() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if enemy.get("_is_alive") == false:
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < best_dist and _has_los_to(enemy):
			best_dist = dist
			best = enemy
	return best


## Find nearest enemy regardless of line of sight (for navigation).
## Mirrors AggressionComponent._find_nearest_enemy_any().
func _find_any_enemy() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not enemy is Node2D:
			continue
		if enemy.get("_is_alive") == false:
			continue
		var dist := global_position.distance_to(enemy.global_position)
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


## Check line of sight to target.
## Mirrors AggressionComponent._has_los().
func _has_los_to(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position)
	query.collision_mask = 4  # Walls (layer 3)
	query.exclude = [self]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


## Move toward target using NavigationAgent2D.
## Mirrors enemy._move_to_target_nav().
func _move_to_target_nav(target_pos: Vector2, speed: float) -> void:
	if _nav_agent == null:
		# Fallback: direct movement
		var dir := (target_pos - global_position).normalized()
		velocity = dir * speed
		rotation = dir.angle()
		if _model:
			_model.rotation = rotation
		return

	_nav_agent.target_position = target_pos

	if _nav_agent.is_navigation_finished():
		velocity = Vector2.ZERO
		return

	var next_pos: Vector2 = _nav_agent.get_next_path_position()
	var direction: Vector2 = (next_pos - global_position).normalized()

	velocity = direction * speed
	rotation = direction.angle()
	if _model:
		_model.rotation = rotation


## Check if can shoot (has ammo and not reloading).
## Mirrors enemy._can_shoot().
func _can_shoot() -> bool:
	if _is_reloading:
		return false
	if _current_ammo <= 0:
		_start_reload()
		return false
	return true


## Process follow state: navigate toward player when no enemies.
func _process_follow_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		velocity = Vector2.ZERO
		return

	var to_player := _player.global_position - global_position
	var distance := to_player.length()

	if distance > follow_distance:
		# Navigate toward player
		_move_to_target_nav(_player.global_position, move_speed)
	else:
		# Close enough — stop and face same direction as player
		velocity = Vector2.ZERO
		if _player:
			var player_model := _player.get_node_or_null("PlayerModel")
			if player_model:
				var target_rot := player_model.global_rotation
				rotation = lerp_angle(rotation, target_rot, rotation_speed * delta)
				if _model:
					_model.rotation = rotation


## Shoot a bullet in the given direction.
## Mirrors enemy._shoot() but simpler (no shotgun/machete variants).
func _shoot(direction: Vector2) -> void:
	if _bullet_scene == null:
		return

	var bullet_spawn_pos := global_position + direction * bullet_spawn_offset

	# Apply progressive spread (same as enemy - Issue #516)
	var spread_deg: float = 0.0
	if _shot_count >= _spread_threshold:
		var excess: int = _shot_count - _spread_threshold
		spread_deg = _initial_spread + excess * _spread_increment
		spread_deg = minf(spread_deg, _max_spread)

	var spread_rad := deg_to_rad(spread_deg)
	var final_direction := direction.rotated(randf_range(-spread_rad, spread_rad))

	var bullet := _bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = bullet_spawn_pos

	# Set bullet properties — compatible with both C# and GDScript bullets
	if bullet.has_method("set_direction"):
		bullet.set_direction(final_direction)
	elif "direction" in bullet:
		bullet.direction = final_direction

	if "speed" in bullet:
		bullet.speed = bullet_speed

	# Set shooter_id to prevent hitting ourselves
	if "shooter_id" in bullet:
		bullet.shooter_id = get_instance_id()

	# Play shoot sound (same as enemy)
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_m16_shot"):
		audio.play_m16_shot(global_position)

	# Sound propagation (same as enemy)
	var sp: Node = get_node_or_null("/root/SoundPropagation")
	if sp and sp.has_method("emit_sound"):
		sp.emit_sound(0, global_position, 1, self, 1469.0)

	_current_ammo -= 1
	_shot_count += 1
	_spread_timer = 0.0

	if _current_ammo <= 0:
		_start_reload()


func _start_reload() -> void:
	if _is_reloading:
		return
	_is_reloading = true
	_reload_timer = 0.0


## Apply damage to the companion. Primary entry point for C# bullets.
func take_damage(amount: float) -> void:
	on_hit(Vector2.RIGHT, amount)


## Called when companion is hit.
func on_hit(hit_direction: Vector2, damage: float = 1.0) -> void:
	if not _is_alive:
		return

	var actual_damage: int = maxi(int(round(damage)), 1)
	_current_health -= actual_damage

	_log("[BffCompanion] Hit: dmg=%d, hp=%d/%d" % [actual_damage, _current_health, _max_health])

	_show_hit_flash()

	# Blood/hit effects
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")

	if _current_health <= 0:
		if audio_manager and audio_manager.has_method("play_hit_lethal"):
			audio_manager.play_hit_lethal(global_position)
		if impact_manager and impact_manager.has_method("spawn_blood_effect"):
			impact_manager.spawn_blood_effect(global_position, hit_direction, null, true)
		_on_death()
	else:
		if audio_manager and audio_manager.has_method("play_hit_non_lethal"):
			audio_manager.play_hit_non_lethal(global_position)
		if impact_manager and impact_manager.has_method("spawn_blood_effect"):
			impact_manager.spawn_blood_effect(global_position, hit_direction, null, false)
		_update_health_visual()


## Called when companion is hit with full bullet info (C# Bullet compatibility).
func on_hit_with_bullet_info(hit_direction: Vector2, _caliber_data: Resource, _has_ricocheted: bool, _has_penetrated: bool, damage: float = 1.0) -> void:
	on_hit(hit_direction, damage)


func _on_death() -> void:
	_is_alive = false
	_log("[BffCompanion] Companion died")
	companion_died.emit()

	# Visual death — fade out and remove
	if _model:
		var tween := create_tween()
		tween.tween_property(_model, "modulate:a", 0.0, 0.5)
		tween.tween_callback(queue_free)
	else:
		queue_free()


func _show_hit_flash() -> void:
	_hit_flash_timer = _hit_flash_duration
	_set_model_color(_hit_flash_color)


func _update_health_visual() -> void:
	if _max_health <= 0:
		return
	var health_percent: float = float(_current_health) / float(_max_health)
	var color := _low_health_color.lerp(_full_health_color, health_percent)
	_set_model_color(color)


func _set_model_color(color: Color) -> void:
	if _body_sprite:
		_body_sprite.modulate = color
	if _head_sprite:
		_head_sprite.modulate = color
	if _left_arm_sprite:
		_left_arm_sprite.modulate = color
	if _right_arm_sprite:
		_right_arm_sprite.modulate = color


## Check if the companion is alive.
func is_alive() -> bool:
	return _is_alive
