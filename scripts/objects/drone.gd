extends CharacterBody2D
## Drone entity spawned by the Drone Operator enemy (Issue #1397, #1417, #1508).
##
## All AI, visuals, and hit handling in one script to avoid exported-build
## script-load failures seen when logic was split into DroneComponent child node.
##
## Behavior:
## - SEARCHING: 360° vision (no FOV), LOS raycast, expanding spiral orbit around operator.
## - COMBAT: Red LED, morse-code beeping, 3× speed kamikaze flight, drift.
##   On player collision: RPG-rocket-style explosion (150px radius, 3 HP).

## Signals matching standard enemy interface.
signal hit
signal died
signal died_with_info(is_ricochet_kill: bool, is_penetration_kill: bool, is_player_kill: bool)

## Drone AI states.
enum DroneState { SEARCHING, COMBAT }

## --- Constants ---
const DRONE_BODY_SIZE: float = 10.0
const ROTOR_ARM_LENGTH: float = 12.0
const ROTOR_RADIUS: float = 4.0
const DRONE_HP: int = 2
const SEARCH_SPEED: float = 150.0
const COMBAT_SPEED: float = 450.0   # 3× search speed (Issue #1417)
const COLLISION_DISTANCE: float = 24.0
const EXPLOSION_RADIUS: float = 150.0
const EXPLOSION_DAMAGE: int = 3
const DRIFT_FACTOR: float = 0.85
const BEEP_INTERVAL: float = 0.3
## Spiral search constants (Issue #1508)
const SPIRAL_START_RADIUS: float = 60.0     # Initial orbit radius around operator (px)
const SPIRAL_MAX_RADIUS: float = 350.0      # Maximum spiral expansion radius (px)
const SPIRAL_EXPAND_RATE: float = 25.0      # Radius growth per second (px/s)
const SPIRAL_ANGULAR_SPEED: float = 1.8     # Angular velocity (rad/s)
const BEEP_FREQUENCY: float = 1200.0
const BEEP_DURATION: float = 0.08

## --- State ---
var _state: int = DroneState.SEARCHING
var _hp: int = DRONE_HP
var _is_alive: bool = true
var _has_exploded: bool = false
var _operator: Node2D = null
var _player: Node2D = null
var _nav_agent: NavigationAgent2D = null
var _current_move_dir: Vector2 = Vector2.ZERO

## Spiral search state (Issue #1508)
var _spiral_angle: float = 0.0        # Current angle in the spiral orbit (radians)
var _spiral_radius: float = SPIRAL_START_RADIUS  # Current orbit radius

## ORCA-computed avoidance velocity (Issue #1508): set asynchronously via velocity_computed signal.
## Prevents the drone from pushing other enemies during the spiral search.
var _avoidance_velocity: Vector2 = Vector2.ZERO

## Beep state
var _beep_timer: float = 0.0
var _beep_idx: int = 0
var _beep_pattern: Array = [0.08, 0.08, 0.2, 0.08, 0.08, 0.2, 0.08, 0.08]
var _beep_player: AudioStreamPlayer2D = null

## Visual
var _rotor_angle: float = 0.0
var _rotor_sprites: Array = []
var _led: Polygon2D = null
var _led_light: PointLight2D = null


func _ready() -> void:
	add_to_group("enemies")
	FileLogger.info("[Drone] _ready started")

	_nav_agent = get_node_or_null("NavigationAgent2D") as NavigationAgent2D
	if _nav_agent:
		_nav_agent.path_desired_distance = 8.0
		_nav_agent.target_desired_distance = 8.0
		# Issue #1508: hook ORCA avoidance so drone doesn't push other enemies.
		if _nav_agent.avoidance_enabled:
			_nav_agent.velocity_computed.connect(_on_avoidance_velocity_computed)
		FileLogger.info("[Drone] NavigationAgent2D found and configured (avoidance=%s)" % str(_nav_agent.avoidance_enabled))
	else:
		FileLogger.info("[Drone] WARNING: NavigationAgent2D not found")

	_setup_beep_player()
	_find_player()
	_setup_drone_visual()

	FileLogger.info("[Drone] _ready complete (state=SEARCHING spiral, player=%s, nav=%s)" % [
		(_player.name if _player else "null"),
		("found" if _nav_agent else "missing")
	])


## Called by DroneOperatorComponent after the drone is added to the scene tree.
func initialize_drone(operator: Node2D) -> void:
	_operator = operator
	FileLogger.info("[Drone] Initialized by operator: %s" % (operator.name if operator else "null"))


func _physics_process(delta: float) -> void:
	if not _is_alive:
		return

	_rotor_angle += 20.0 * delta
	_animate_rotors()

	if _player == null or not is_instance_valid(_player):
		_find_player()
		return

	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and not gm.get("player_alive"):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _state == DroneState.SEARCHING:
		_update_searching(delta)
	else:
		_update_combat(delta)


func _update_searching(delta: float) -> void:
	if _player.has_method("is_invisible") and _player.is_invisible():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	if _has_line_of_sight():
		_transition_to_combat()
		return

	# Expand spiral orbit around the operator (Issue #1508).
	# If the operator is gone, hover in place as a fallback.
	if _operator == null or not is_instance_valid(_operator):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_spiral_angle += SPIRAL_ANGULAR_SPEED * delta
	_spiral_radius = minf(_spiral_radius + SPIRAL_EXPAND_RATE * delta, SPIRAL_MAX_RADIUS)

	var orbit_target: Vector2 = _operator.global_position + Vector2(cos(_spiral_angle), sin(_spiral_angle)) * _spiral_radius

	# Issue #1508: use NavigationAgent2D so the drone navigates *around* walls
	# instead of flying straight into them.  Fall back to direct movement when
	# the nav agent is unavailable (e.g. no NavMesh in test scenes).
	var intended_dir: Vector2
	if _nav_agent:
		_nav_agent.target_position = orbit_target
		var next_pos: Vector2 = _nav_agent.get_next_path_position()
		intended_dir = global_position.direction_to(next_pos)
	else:
		intended_dir = global_position.direction_to(orbit_target)

	var intended_vel: Vector2 = intended_dir * SEARCH_SPEED

	# Feed ORCA so the drone avoids pushing other enemies (avoidance_enabled=true
	# in Drone.tscn).  The computed safe velocity arrives asynchronously via
	# _on_avoidance_velocity_computed and is applied on the next physics frame.
	if _nav_agent and _nav_agent.avoidance_enabled:
		_nav_agent.set_velocity(intended_vel)
		velocity = _avoidance_velocity if _avoidance_velocity.length_squared() > 0.01 else intended_vel
	else:
		velocity = intended_vel

	move_and_slide()


func _has_line_of_sight() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = _player.global_position
	query.collision_mask = 4
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return true
	var dist_hit := global_position.distance_to(result["position"])
	var dist_player := global_position.distance_to(_player.global_position)
	return dist_hit >= dist_player - 10.0


func _transition_to_combat() -> void:
	_state = DroneState.COMBAT
	_beep_timer = 0.0
	_beep_idx = 0
	if _led:
		_led.color = Color(1.0, 0.1, 0.05, 0.95)
	if _led_light:
		_led_light.energy = 3.0
	FileLogger.info("[Drone] COMBAT mode activated — kamikaze flight toward player! (spiral_angle=%.2f, spiral_radius=%.1f)" % [_spiral_angle, _spiral_radius])


func _update_combat(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_update_beep(delta)

	if _led_light:
		_led_light.energy = 2.0 + 1.5 * abs(sin(_rotor_angle * 2.0))

	var to_player: Vector2 = _player.global_position - global_position
	var distance: float = to_player.length()

	if distance <= COLLISION_DISTANCE:
		_explode()
		return

	var desired_dir: Vector2
	if _nav_agent:
		_nav_agent.target_position = _player.global_position
		desired_dir = global_position.direction_to(_nav_agent.get_next_path_position())
	else:
		desired_dir = to_player.normalized()

	if _current_move_dir == Vector2.ZERO:
		_current_move_dir = desired_dir
	else:
		_current_move_dir = (_current_move_dir * DRIFT_FACTOR + desired_dir * (1.0 - DRIFT_FACTOR)).normalized()

	velocity = _current_move_dir * COMBAT_SPEED
	move_and_slide()

	for i in range(get_slide_collision_count()):
		var col := get_slide_collision(i)
		if col and col.get_collider() and col.get_collider().is_in_group("player"):
			_explode()
			return


func _update_beep(delta: float) -> void:
	_beep_timer -= delta
	if _beep_timer <= 0.0:
		var duration: float = _beep_pattern[_beep_idx % _beep_pattern.size()]
		_play_beep(duration)
		_beep_idx += 1
		_beep_timer = duration + BEEP_INTERVAL


func _play_beep(duration: float) -> void:
	if _beep_player == null:
		return
	var rate: int = 22050
	var n: int = int(duration * rate)
	if n <= 0:
		return
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / rate
		var env: float = 1.0 - (float(i) / n)
		var s: int = clampi(int(sin(t * BEEP_FREQUENCY * TAU) * env * 0.5 * 32767.0), -32768, 32767)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	stream.data = data
	_beep_player.stream = stream
	_beep_player.play()


func _explode() -> void:
	if _has_exploded or not _is_alive:
		return
	_has_exploded = true
	_is_alive = false
	FileLogger.info("[Drone] EXPLODED at pos=%s (kamikaze)" % str(global_position))

	var pos: Vector2 = global_position

	var pfx: Node = get_node_or_null("/root/PowerFantasyEffectsManager")
	if pfx and pfx.has_method("on_grenade_exploded"):
		pfx.on_grenade_exploded()

	var snd: Node = get_node_or_null("/root/SoundPropagation")
	if snd and snd.has_method("emit_sound"):
		var vp := get_viewport()
		var diag := 1469.0
		if vp:
			var sz := vp.get_visible_rect().size
			diag = sqrt(sz.x * sz.x + sz.y * sz.y)
		snd.emit_sound(1, pos, 1, self, diag * 2.0)

	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_offensive_grenade_explosion"):
		audio.play_offensive_grenade_explosion(pos)

	_damage_in_radius(pos)
	_spawn_explosion_vfx(pos)

	died.emit()
	died_with_info.emit(false, false, false)
	set_physics_process(false)
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)


func _damage_in_radius(pos: Vector2) -> void:
	var space_state := get_world_2d().direct_space_state
	var tree := get_tree()
	if tree == null:
		return

	for enemy in tree.get_nodes_in_group("enemies"):
		if enemy == self:
			continue
		if enemy is Node2D and pos.distance_to(enemy.global_position) <= EXPLOSION_RADIUS:
			if _los_clear(space_state, pos, enemy.global_position):
				_apply_hit(enemy, pos)

	var players := tree.get_nodes_in_group("player")
	if players.size() > 0 and players[0] is Node2D:
		var pl: Node2D = players[0]
		if pos.distance_to(pl.global_position) <= EXPLOSION_RADIUS:
			if _los_clear(space_state, pos, pl.global_position):
				_apply_hit(pl, pos)


func _los_clear(space_state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collision_mask = 4
	return space_state.intersect_ray(q).is_empty()


func _apply_hit(entity: Node2D, explode_pos: Vector2) -> void:
	var dir := (entity.global_position - explode_pos).normalized()
	if entity.has_method("on_hit_with_info"):
		for i in range(EXPLOSION_DAMAGE):
			entity.on_hit_with_info(dir, null)
	elif entity.has_method("on_hit"):
		for i in range(EXPLOSION_DAMAGE):
			entity.on_hit()


func _spawn_explosion_vfx(pos: Vector2) -> void:
	var mgr: Node = get_node_or_null("/root/ImpactEffectsManager")
	if mgr and mgr.has_method("spawn_explosion_effect"):
		mgr.spawn_explosion_effect(pos, EXPLOSION_RADIUS)
		return
	# Fallback: simple radial flash
	var flash := Sprite2D.new()
	var r := int(EXPLOSION_RADIUS)
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


## --- Hit handling ---

func on_hit() -> void:
	if not _is_alive:
		return
	hit.emit()
	_hp -= 1
	FileLogger.info("[Drone] Hit! hp=%d/%d" % [_hp, DRONE_HP])
	if _hp <= 0:
		_die(false, false, false)


func on_hit_with_info(_dir: Vector2, _cal: Resource) -> void:
	on_hit()


func on_hit_with_bullet_info(_dir: Vector2, _cal: Resource, ricocheted: bool, penetrated: bool, dmg: float = 1.0, from_player: bool = false) -> void:
	if not _is_alive:
		return
	hit.emit()
	_hp -= maxi(int(round(dmg)), 1)
	FileLogger.info("[Drone] Hit! hp=%d/%d" % [_hp, DRONE_HP])
	if _hp <= 0:
		_die(ricocheted, penetrated, from_player)


func _die(ricochet: bool, penetration: bool, player_kill: bool) -> void:
	if not _is_alive:
		return
	_is_alive = false
	died.emit()
	died_with_info.emit(ricochet, penetration, player_kill)
	FileLogger.info("[Drone] Destroyed (ricochet=%s, penetration=%s, player=%s)" % [
		str(ricochet), str(penetration), str(player_kill)])
	set_physics_process(false)
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)


func is_alive() -> bool:
	return _is_alive


func is_in_combat() -> bool:
	return _state == DroneState.COMBAT


## Called by NavigationAgent2D.velocity_computed when ORCA avoidance is enabled.
## Stores the safe velocity; applied on the next physics frame in _update_searching().
func _on_avoidance_velocity_computed(safe_velocity: Vector2) -> void:
	_avoidance_velocity = safe_velocity


## --- Visual helpers ---

func _find_player() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var players: Array = tree.get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0]
		return
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.get("player") and is_instance_valid(gm.get("player")):
		_player = gm.player
		return
	var root: Node = tree.current_scene
	if root:
		var found := root.find_child("Player", true, false)
		if found:
			_player = found


func _setup_beep_player() -> void:
	_beep_player = AudioStreamPlayer2D.new()
	_beep_player.name = "DroneBeepPlayer"
	_beep_player.max_distance = 800.0
	_beep_player.attenuation = 2.0
	_beep_player.volume_db = -8.0
	add_child(_beep_player)


func _animate_rotors() -> void:
	var speed_mult: float = 3.0 if _state == DroneState.COMBAT else 1.0
	for rotor in _rotor_sprites:
		if is_instance_valid(rotor):
			rotor.color.a = 0.2 + 0.15 * abs(sin(_rotor_angle * speed_mult))


func _setup_drone_visual() -> void:
	var model: Node2D = get_node_or_null("DroneModel")
	if model == null:
		return

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

	var lens := Polygon2D.new()
	lens.polygon = PackedVector2Array([
		Vector2(DRONE_BODY_SIZE - 2, -3), Vector2(DRONE_BODY_SIZE + 3, -3),
		Vector2(DRONE_BODY_SIZE + 3, 3), Vector2(DRONE_BODY_SIZE - 2, 3),
	])
	lens.color = Color(0.1, 0.5, 0.9, 0.9)
	lens.z_index = 2
	model.add_child(lens)

	var arm_positions: Array = [
		Vector2(ROTOR_ARM_LENGTH, ROTOR_ARM_LENGTH),
		Vector2(ROTOR_ARM_LENGTH, -ROTOR_ARM_LENGTH),
		Vector2(-ROTOR_ARM_LENGTH, ROTOR_ARM_LENGTH),
		Vector2(-ROTOR_ARM_LENGTH, -ROTOR_ARM_LENGTH),
	]
	for pos in arm_positions:
		var arm := Polygon2D.new()
		arm.polygon = PackedVector2Array([
			Vector2(-1, -1) + pos * 0.2, Vector2(1, -1) + pos * 0.2,
			Vector2(1, 1) + pos, Vector2(-1, 1) + pos,
		])
		arm.color = Color(0.3, 0.3, 0.35, 0.8)
		model.add_child(arm)

		var rotor := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in range(8):
			var ang: float = i * TAU / 8.0
			pts.append(pos + Vector2(cos(ang), sin(ang)) * ROTOR_RADIUS)
		rotor.polygon = pts
		rotor.color = Color(0.5, 0.5, 0.6, 0.3)
		rotor.z_index = 3
		model.add_child(rotor)
		_rotor_sprites.append(rotor)

	_led = Polygon2D.new()
	_led.polygon = PackedVector2Array([
		Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2),
	])
	_led.color = Color(0.2, 0.8, 0.2, 0.9)
	_led.z_index = 4
	model.add_child(_led)

	_led_light = PointLight2D.new()
	_led_light.name = "LEDGlow"
	_led_light.color = Color(1.0, 0.1, 0.1, 1.0)
	_led_light.energy = 0.0
	_led_light.texture = _create_light_texture()
	_led_light.texture_scale = 0.3
	_led_light.z_index = 5
	model.add_child(_led_light)

	FileLogger.info("[Drone] Visual setup complete (quadcopter style, LED=green/searching)")


func _create_light_texture() -> ImageTexture:
	var size: int = 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius: float = size / 2.0
	for x in range(size):
		for y in range(size):
			var d := Vector2(x, y).distance_to(center)
			if d <= radius:
				var a := 1.0 - (d / radius)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
