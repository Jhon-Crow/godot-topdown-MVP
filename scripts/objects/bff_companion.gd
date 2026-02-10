class_name BffCompanion
extends CharacterBody2D
## BFF Companion NPC summoned by the BFF Pendant active item (Issue #674).
##
## A friendly companion that follows the player and shoots enemies with an M16.
## Has 2-4 HP and lasts until killed or the level ends.
## Uses simplified AI: follows the player, detects enemies, and shoots them.

## Companion died signal (for enemy counter exclusion).
signal companion_died

## Movement speed when following the player (px/s).
var move_speed: float = 200.0

## Distance to maintain from the player (px).
var follow_distance: float = 80.0

## Detection range for enemies (px).
var detection_range: float = 500.0

## Weapon configuration — uses RIFLE (M16).
var shoot_cooldown: float = 0.15
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
var _current_target: Node2D = null
var _shoot_timer: float = 0.0
var _current_ammo: int = 30
var _reload_timer: float = 0.0
var _is_reloading: bool = false
var _reload_time: float = 2.5

## Bullet scene.
var _bullet_scene: PackedScene = null

## Spread tracking (progressive spread like enemies).
var _shot_count: int = 0
var _spread_timer: float = 0.0
var _spread_threshold: int = 3
var _initial_spread: float = 0.5
var _spread_increment: float = 0.6
var _max_spread: float = 4.0
var _spread_reset_time: float = 0.25

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
var _full_health_color: Color = Color(0.2, 1.0, 0.6, 1.0)  # Green-cyan tint for companion (different from player's blue)
var _low_health_color: Color = Color(0.1, 0.4, 0.2, 1.0)
var _hit_flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## Aim tolerance for shooting (dot product threshold).
const AIM_TOLERANCE_DOT: float = 0.95

## Rotation speed (rad/s).
var _rotation_speed: float = 20.0

## Debug frame counter for periodic logging (every ~60 frames = 1 second).
var _debug_frame_counter: int = 0
const DEBUG_LOG_INTERVAL: int = 60


func _ready() -> void:
	FileLogger.info("[BffCompanion] _ready() called, initializing companion...")
	add_to_group("bff_companions")
	_initialize_health()
	_find_player()
	_load_bullet_scene()
	_update_health_visual()

	# Apply scale to model
	if _model:
		_model.scale = Vector2(model_scale, model_scale)
		FileLogger.info("[BffCompanion] Model scale set to %s" % str(_model.scale))
	else:
		FileLogger.info("[BffCompanion] WARNING: _model is null, visual setup may fail")

	FileLogger.info("[BffCompanion] Spawned with %d/%d HP, player found: %s" % [_current_health, _max_health, str(_player != null)])


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

	# Periodic debug logging
	_debug_frame_counter += 1
	if _debug_frame_counter >= DEBUG_LOG_INTERVAL:
		_debug_frame_counter = 0
		var target_name := "none" if _current_target == null else _current_target.name
		var player_name := "none" if _player == null else _player.name
		FileLogger.info("[BffCompanion] Status: pos=%s, player=%s, target=%s, ammo=%d, hp=%d" % [
			str(global_position), player_name, target_name, _current_ammo, _current_health])

	_shoot_timer += delta
	_spread_timer += delta
	if _spread_timer >= _spread_reset_time and _spread_reset_time > 0.0:
		_shot_count = 0

	# Update reload
	if _is_reloading:
		_reload_timer += delta
		if _reload_timer >= _reload_time:
			_current_ammo = magazine_size
			_is_reloading = false
			_reload_timer = 0.0

	# Update hit flash
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0.0:
			_update_health_visual()

	# Find player if lost
	if _player == null or not is_instance_valid(_player):
		_find_player()
		if _player == null:
			return

	# Find closest enemy target
	_find_target()

	# Rotate toward target (or player direction if no target)
	if _current_target != null and is_instance_valid(_current_target):
		var dir_to_target := (_current_target.global_position - global_position).normalized()
		_rotate_model_toward(dir_to_target, delta)
		_try_shoot(dir_to_target)
	else:
		# Face same direction as player
		if _model and _player:
			var player_model := _player.get_node_or_null("PlayerModel")
			if player_model:
				var target_rot := player_model.global_rotation
				_model.global_rotation = lerp_angle(_model.global_rotation, target_rot, _rotation_speed * delta)

	# Follow player
	_follow_player(delta)

	move_and_slide()


func _follow_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		velocity = Vector2.ZERO
		return

	var to_player := _player.global_position - global_position
	var distance := to_player.length()

	if distance > follow_distance:
		var direction := to_player.normalized()
		velocity = direction * move_speed
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)


func _find_target() -> void:
	_current_target = null
	var closest_dist := detection_range
	var enemies := get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if not enemy is CharacterBody2D:
			continue
		# Check if the enemy is alive
		if enemy.has_method("is_alive") and not enemy.is_alive():
			continue
		# Check if enemy has _is_alive property
		if "_is_alive" in enemy and not enemy._is_alive:
			continue

		var dist := global_position.distance_to(enemy.global_position)
		if dist < closest_dist:
			# Check line of sight
			if _has_line_of_sight(enemy.global_position):
				closest_dist = dist
				_current_target = enemy


func _has_line_of_sight(target_pos: Vector2) -> bool:
	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return false

	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = target_pos
	query.collision_mask = 1  # Walls only (layer 1)
	query.exclude = [get_rid()]

	var result := space_state.intersect_ray(query)
	return result.is_empty()  # True if no wall in the way


func _rotate_model_toward(direction: Vector2, delta: float) -> void:
	if _model == null:
		return
	var target_angle := direction.angle()
	_model.rotation = lerp_angle(_model.rotation, target_angle, _rotation_speed * delta)


func _try_shoot(direction: Vector2) -> void:
	if _bullet_scene == null:
		return
	if _is_reloading:
		return
	if _current_ammo <= 0:
		_start_reload()
		return
	if _shoot_timer < shoot_cooldown:
		return

	# Check aim alignment
	var weapon_forward := Vector2.RIGHT.rotated(_model.rotation) if _model else direction
	var aim_dot := weapon_forward.dot(direction)
	if aim_dot < AIM_TOLERANCE_DOT:
		return

	# Check friendly fire — don't shoot if player is in the way
	if _player and is_instance_valid(_player):
		if _is_player_in_firing_line(direction):
			return

	# Shoot
	_shoot(weapon_forward)


func _is_player_in_firing_line(direction: Vector2) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false

	var space_state := get_world_2d().direct_space_state
	if space_state == null:
		return false

	var muzzle_pos := global_position + direction * bullet_spawn_offset
	var target_pos := global_position + direction * detection_range

	var query := PhysicsRayQueryParameters2D.new()
	query.from = muzzle_pos
	query.to = target_pos
	query.collision_mask = 4  # Player collision layer
	query.exclude = [get_rid()]

	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return false

	# Check if the hit is the player
	var hit_body = result.get("collider")
	if hit_body == _player:
		return true
	return false


func _shoot(direction: Vector2) -> void:
	if _bullet_scene == null:
		return

	var bullet_spawn_pos := global_position + direction * bullet_spawn_offset

	# Apply progressive spread
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

	# Play shoot sound
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_m16_shot"):
		audio.play_m16_shot(global_position)

	# Sound propagation
	var sp: Node = get_node_or_null("/root/SoundPropagation")
	if sp and sp.has_method("emit_sound"):
		sp.emit_sound(0, global_position, 1, self, 1469.0)

	_current_ammo -= 1
	_shot_count += 1
	_spread_timer = 0.0
	_shoot_timer = 0.0

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

	FileLogger.info("[BffCompanion] Hit: dmg=%d, hp=%d/%d" % [actual_damage, _current_health, _max_health])

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
	FileLogger.info("[BffCompanion] Companion died")
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
