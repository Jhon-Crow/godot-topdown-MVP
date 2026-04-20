extends GrenadeBase
class_name DroneGrenade

## Drone body half-size (pixels).
const DRONE_BODY_SIZE: float = 10.0
## Rotor arm length from center (pixels).
const ROTOR_ARM_LENGTH: float = 12.0
## Rotor disc radius (pixels).
const ROTOR_RADIUS: float = 4.0
## Drone grenade (Issue #1628).
##
## When thrown, a player-controlled drone is spawned at the throw position.
## Control transfers to the drone: the player pilots it using WASD / arrow keys
## toward the mouse cursor. The camera follows the drone.
##
## The drone explodes RPG-style (area damage, NO wall penetration) when it:
##   - crashes into an enemy (CharacterBody2D in "enemies" group), OR
##   - is hit by a bullet (any node calling on_hit()).
##
## After the explosion control returns to the player automatically.

## Speed of the player-controlled drone (pixels/second).
@export var drone_speed: float = 400.0

## Explosion radius matching RPG charge (pixels). 50% larger than standard (150 → 225).
@export var explosion_radius: float = 225.0

## Explosion damage to enemies in blast radius.
@export var explosion_damage: int = 5

## Drift factor: how much previous velocity carries over each frame (Issue #1667).
## Matches the enemy Drone drift — gives banking/inertia feel on turns.
const DRIFT_FACTOR: float = 0.82

## Delay (seconds) before enemies start targeting this drone (Issue #1667).
const ENEMY_TARGETING_DELAY: float = 1.5

## Whether the drone has been launched (player is now piloting).
var _drone_launched: bool = false

## Whether the drone is alive (not yet exploded).
var _drone_alive: bool = false

## Reference to the Camera2D that follows the player (reparented to drone while active).
var _player_camera: Camera2D = null

## Reference to the player node (to return control after explosion).
var _player: Node2D = null

## Accumulated movement direction for the drone from player input.
var _move_dir: Vector2 = Vector2.ZERO

## Current banked (inertial) movement direction — smoothed by DRIFT_FACTOR (Issue #1667).
var _current_move_dir: Vector2 = Vector2.ZERO

## Timer counting down until enemies start targeting the drone (Issue #1667).
var _enemy_targeting_timer: float = 0.0

## Whether enemies are currently targeting this drone (Issue #1667).
var _enemy_targeting_active: bool = false

## Visual: drone body polygon drawn procedurally.
var _drone_visual: Node2D = null


func _ready() -> void:
	super._ready()
	# Drone grenade activates instantly when thrown — no fuse timer needed.
	# Override fuse_time to a large value so the base timer never fires.
	fuse_time = 9999.0

	# No wall bounce: drone should collide with walls.
	wall_bounce = 0.0

	# Set collision to detect enemies (layer 2) and obstacles (layer 4).
	collision_mask = 4 | 2

	# Hide the static Sprite2D (grenade image) and replace with drone visual.
	var sprite := get_node_or_null("Sprite2D")
	if sprite:
		sprite.hide()
	_setup_drone_visual()

	FileLogger.info("[DroneGrenade] Ready")


## Override activate_timer — the drone grenade has no fuse.
## We still call super to trigger the pin-pull sound.
func activate_timer() -> void:
	if _timer_active:
		return
	_timer_active = true
	_time_remaining = fuse_time
	if not _activation_sound_played:
		_activation_sound_played = true
		_play_activation_sound()
	FileLogger.info("[DroneGrenade] Pin pulled — drone will launch on throw")


## Override throw methods to launch the drone immediately.
func throw_grenade_simple(throw_direction: Vector2, throw_speed: float) -> void:
	super.throw_grenade_simple(throw_direction, throw_speed)
	_launch_drone()


func throw_grenade_velocity_based(mouse_velocity: Vector2, swing_distance: float) -> void:
	super.throw_grenade_velocity_based(mouse_velocity, swing_distance)
	_launch_drone()


func throw_grenade_with_direction(throw_direction: Vector2, velocity_magnitude: float, swing_distance: float) -> void:
	super.throw_grenade_with_direction(throw_direction, velocity_magnitude, swing_distance)
	_launch_drone()


func throw_grenade(direction: Vector2, drag_distance: float) -> void:
	super.throw_grenade(direction, drag_distance)
	_launch_drone()


## Launch the drone: stop physics movement, transfer control.
func _launch_drone() -> void:
	if _drone_launched:
		return
	_drone_launched = true
	_drone_alive = true

	# Stop physics movement — the drone is now under direct player control.
	linear_velocity = Vector2.ZERO

	# Issue #1667: enemies can shoot this drone; add it to a discoverable group.
	add_to_group("player_drones")

	# Issue #1667: start enemy targeting countdown.
	_enemy_targeting_timer = ENEMY_TARGETING_DELAY
	_enemy_targeting_active = false

	_find_player_and_camera()
	_attach_camera_to_drone()
	_disable_player_control()

	FileLogger.info("[DroneGrenade] Drone launched at %s — player now piloting" % str(global_position))


## Find the player node and its Camera2D.
func _find_player_and_camera() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		_player = players[0] as Node2D

	if _player == null:
		var scene := get_tree().current_scene
		if scene:
			_player = scene.get_node_or_null("Player") as Node2D

	if _player == null:
		FileLogger.info("[DroneGrenade] WARNING: Player node not found")
		return

	# Find Camera2D in the player's subtree.
	for child in _player.get_children():
		if child is Camera2D:
			_player_camera = child as Camera2D
			break

	FileLogger.info("[DroneGrenade] Player found: %s, Camera: %s" % [
		_player.name, (_player_camera.name if _player_camera else "null")
	])


## Reparent the player's camera to follow the drone.
func _attach_camera_to_drone() -> void:
	if _player_camera == null:
		return
	var old_parent := _player_camera.get_parent()
	if old_parent:
		old_parent.remove_child(_player_camera)
	add_child(_player_camera)
	_player_camera.global_position = global_position
	_player_camera.make_current()
	FileLogger.info("[DroneGrenade] Camera attached to drone")


## Return the camera to the player.
func _detach_camera_from_drone() -> void:
	if _player_camera == null or not is_instance_valid(_player_camera):
		return
	if _player_camera.get_parent() == self:
		remove_child(_player_camera)
	if _player != null and is_instance_valid(_player):
		_player.add_child(_player_camera)
		_player_camera.global_position = _player.global_position
		_player_camera.make_current()
	FileLogger.info("[DroneGrenade] Camera returned to player")


## Disable player movement + shooting while drone is active.
func _disable_player_control() -> void:
	if _player == null:
		return
	# Set a flag on the player so its _physics_process skips input.
	if _player.has_method("set_drone_piloting"):
		_player.set_drone_piloting(true)
	else:
		# Fallback: disable physics processing on the player.
		_player.set_physics_process(false)
	FileLogger.info("[DroneGrenade] Player control disabled")


## Re-enable player control after drone explosion.
func _restore_player_control() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _player.has_method("set_drone_piloting"):
		_player.set_drone_piloting(false)
	else:
		_player.set_physics_process(true)
	FileLogger.info("[DroneGrenade] Player control restored")


## Override _physics_process to pilot the drone via player input.
func _physics_process(delta: float) -> void:
	if _has_exploded:
		return

	# FIX for Issue #432 fallback: if drone was unfrozen without timer, launch it.
	if _was_frozen_on_start and not freeze:
		_was_frozen_on_start = false
		if not _drone_launched:
			_launch_drone()

	if not _drone_launched or not _drone_alive:
		return

	# Issue #1667: tick down enemy-targeting delay.
	if not _enemy_targeting_active:
		_enemy_targeting_timer -= delta
		if _enemy_targeting_timer <= 0.0:
			_enemy_targeting_active = true
			FileLogger.info("[DroneGrenade] Enemy targeting now active (delay elapsed)")

	# Issue #1895: while piloting the drone the player can fire their weapon and
	# use their active item.  We detect the inputs here (the player's own
	# _physics_process is suspended) and delegate to the player's public helpers.
	if _player != null and is_instance_valid(_player):
		# Shoot: support both automatic (held) and semi-automatic (just-pressed).
		var shoot_just_pressed: bool = Input.is_action_just_pressed("shoot")
		var shoot_held: bool = Input.is_action_pressed("shoot")
		if shoot_just_pressed or shoot_held:
			if _player.has_method("ShootFromDrone"):
				_player.call("ShootFromDrone", global_position)
		# Active item (Space key) — delegate every frame so hold-based items work.
		if _player.has_method("TriggerActiveItemFromDrone"):
			_player.call("TriggerActiveItemFromDrone", delta)

	# Read WASD / arrow key input.
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_down"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_up"):
		input_dir.y -= 1.0

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()

	# Issue #1667: apply drift/inertia (banking) like the enemy Drone.
	# Blend input_dir with current banked direction using DRIFT_FACTOR so the drone
	# carries momentum through turns rather than snapping instantly.
	if input_dir != Vector2.ZERO:
		if _current_move_dir == Vector2.ZERO:
			_current_move_dir = input_dir
		else:
			_current_move_dir = (_current_move_dir * DRIFT_FACTOR + input_dir * (1.0 - DRIFT_FACTOR)).normalized()
		linear_velocity = _current_move_dir * drone_speed
		# Rotate drone body to face banked movement direction.
		rotation = _current_move_dir.angle()
	else:
		# No input: gradually bleed off momentum (coast).
		_current_move_dir = _current_move_dir * DRIFT_FACTOR
		if _current_move_dir.length_squared() < 0.01:
			_current_move_dir = Vector2.ZERO
		linear_velocity = _current_move_dir * drone_speed


## Override body collision to explode when hitting an enemy.
func _on_body_entered(body: Node) -> void:
	super._on_body_entered(body)

	if not _drone_alive or _has_exploded:
		return

	# Explode on contact with an enemy.
	if body.is_in_group("enemies") or body is CharacterBody2D:
		# Only trigger on enemies (not walls/obstacles for drone — drone flies over them
		# conceptually, but walls block movement via physics).
		if body.is_in_group("enemies"):
			FileLogger.info("[DroneGrenade] Crashed into enemy '%s' — exploding!" % body.name)
			_explode()


## Called when a bullet hits the drone.
## Issue #1667: drone explodes when shot by enemies (after targeting delay elapses).
func on_hit() -> void:
	if not _drone_alive or _has_exploded:
		return
	FileLogger.info("[DroneGrenade] Drone hit by bullet — exploding!")
	_explode()


## Returns true when enemies should aim at this drone (Issue #1667).
## Enemies read this flag to decide whether to open fire on the drone.
func is_targetable_by_enemies() -> bool:
	return _drone_alive and not _has_exploded and _enemy_targeting_active


## Override _on_explode to produce RPG-style area damage (no wall penetration).
func _on_explode() -> void:
	_drone_alive = false
	_enemy_targeting_active = false
	# Issue #1667: leave the targeting group so enemies stop shooting at debris.
	if is_in_group("player_drones"):
		remove_from_group("player_drones")

	var pos := global_position

	# Restore player control before any awaits.
	_detach_camera_from_drone()
	_restore_player_control()

	# Damage enemies in radius (line-of-sight required — no wall penetration).
	var space_state := get_world_2d().direct_space_state
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy is Node2D:
			var dist := pos.distance_to(enemy.global_position)
			if dist <= explosion_radius:
				if _los_clear(space_state, pos, enemy.global_position):
					_apply_explosion_damage(enemy, pos)

	# Visual effect.
	var impact_manager: Node = get_node_or_null("/root/ImpactEffectsManager")
	if impact_manager and impact_manager.has_method("spawn_explosion_effect"):
		impact_manager.spawn_explosion_effect(pos, explosion_radius)
	else:
		_fallback_explosion_vfx(pos)

	# Scorch mark on the floor.
	_spawn_scorch_mark(40.0, 0.6, "drone")

	# Scatter shell casings in and around the blast zone (Issue #432).
	_scatter_casings(explosion_radius)

	FileLogger.info("[DroneGrenade] Drone explosion at %s (radius=%.0f)" % [str(pos), explosion_radius])


## Override _get_effect_radius for base class helpers.
func _get_effect_radius() -> float:
	return explosion_radius


## Check line of sight between two points (obstacles only, layer 4).
func _los_clear(space_state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collision_mask = 4
	q.exclude = [get_rid()]
	return space_state.intersect_ray(q).is_empty()


## Apply RPG-style explosion damage to a target.
func _apply_explosion_damage(target: Node2D, explode_pos: Vector2) -> void:
	var dir := (target.global_position - explode_pos).normalized()
	if target.has_method("on_hit_with_info"):
		for i in range(explosion_damage):
			target.on_hit_with_info(dir, null)
	elif target.has_method("on_hit"):
		for i in range(explosion_damage):
			target.on_hit()
	FileLogger.info("[DroneGrenade] Applied %d damage to '%s'" % [explosion_damage, target.name])


## Simple explosion VFX fallback when ImpactEffectsManager is unavailable.
func _fallback_explosion_vfx(pos: Vector2) -> void:
	var flash := Sprite2D.new()
	var r := int(explosion_radius)
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	var center := Vector2(r, r)
	for x in range(r * 2):
		for y in range(r * 2):
			var d := Vector2(x, y).distance_to(center)
			if d <= r:
				img.set_pixel(x, y, Color(1.0, 0.5, 0.1, 1.0 - d / r))
	flash.texture = ImageTexture.create_from_image(img)
	flash.global_position = pos
	flash.z_index = 100
	get_tree().current_scene.add_child(flash)
	var tw := get_tree().create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.3)
	tw.tween_callback(flash.queue_free)


## Build a procedural quadcopter-style drone visual (matches the enemy Drone entity).
func _setup_drone_visual() -> void:
	var model := get_node_or_null("DroneModel") as Node2D
	if model == null:
		model = Node2D.new()
		model.name = "DroneModel"
		add_child(model)

	_drone_visual = model

	# Central body square.
	var body := Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-DRONE_BODY_SIZE, -DRONE_BODY_SIZE),
		Vector2(DRONE_BODY_SIZE, -DRONE_BODY_SIZE),
		Vector2(DRONE_BODY_SIZE, DRONE_BODY_SIZE),
		Vector2(-DRONE_BODY_SIZE, DRONE_BODY_SIZE),
	])
	body.color = Color(0.2, 0.2, 0.25, 0.9)
	body.z_index = 1
	model.add_child(body)

	# Front camera lens.
	var lens := Polygon2D.new()
	lens.polygon = PackedVector2Array([
		Vector2(DRONE_BODY_SIZE - 2, -3), Vector2(DRONE_BODY_SIZE + 3, -3),
		Vector2(DRONE_BODY_SIZE + 3, 3), Vector2(DRONE_BODY_SIZE - 2, 3),
	])
	lens.color = Color(0.1, 0.5, 0.9, 0.9)
	lens.z_index = 2
	model.add_child(lens)

	# Four rotor arms + rotor discs.
	var arm_positions: Array = [
		Vector2(ROTOR_ARM_LENGTH, ROTOR_ARM_LENGTH),
		Vector2(ROTOR_ARM_LENGTH, -ROTOR_ARM_LENGTH),
		Vector2(-ROTOR_ARM_LENGTH, ROTOR_ARM_LENGTH),
		Vector2(-ROTOR_ARM_LENGTH, -ROTOR_ARM_LENGTH),
	]
	for arm_pos in arm_positions:
		var arm := Polygon2D.new()
		arm.polygon = PackedVector2Array([
			Vector2(-1, -1) + arm_pos * 0.2, Vector2(1, -1) + arm_pos * 0.2,
			Vector2(1, 1) + arm_pos, Vector2(-1, 1) + arm_pos,
		])
		arm.color = Color(0.3, 0.3, 0.35, 0.8)
		model.add_child(arm)

		var rotor := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(8):
			var ang: float = i * TAU / 8.0
			pts.append(arm_pos + Vector2(cos(ang), sin(ang)) * ROTOR_RADIUS)
		rotor.polygon = pts
		rotor.color = Color(0.5, 0.5, 0.6, 0.3)
		rotor.z_index = 3
		model.add_child(rotor)

	# Green status LED (center).
	var led := Polygon2D.new()
	led.polygon = PackedVector2Array([
		Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2),
	])
	led.color = Color(0.2, 0.8, 0.2, 0.9)
	led.z_index = 4
	model.add_child(led)

	FileLogger.info("[DroneGrenade] Drone visual set up (quadcopter style)")


## Override explosion sound to match RPG/offensive style.
func _play_explosion_sound() -> void:
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_offensive_grenade_explosion"):
		audio_manager.play_offensive_grenade_explosion(global_position)

	var sound_propagation: Node = get_node_or_null("/root/SoundPropagation")
	if sound_propagation and sound_propagation.has_method("emit_sound"):
		var vp := get_viewport()
		var diag := 1469.0
		if vp:
			var sz := vp.get_visible_rect().size
			diag = sqrt(sz.x * sz.x + sz.y * sz.y)
		sound_propagation.emit_sound(1, global_position, 2, self, diag * 2.0)
